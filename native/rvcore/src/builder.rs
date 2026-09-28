//! `ChunkBuilder`: generates terrain chunks on native worker threads.
//!
//! Workers only touch plain Rust data (`rvgen`), never Godot objects, so no engine
//! thread-safety rules apply. Conversion to Godot types happens in `poll()` on the main
//! thread, where the caller controls how much work is done per frame.

use std::collections::VecDeque;
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::{Arc, Condvar, Mutex};
use std::thread::{self, JoinHandle};
use std::time::Instant;

use godot::prelude::*;
use rvgen::mesh::{self, MeshData};
use rvgen::scatter::{self, PropInstance, TreeInstance};
use rvgen::{ChunkCoord, SeedCode, World};

use crate::convert;

/// `request()` flag: also scatter trees and props.
const DECOR: i32 = 1;
/// `request()` flag: also return the raw heights (for collision).
const HEIGHTS: i32 = 2;
/// `request()` flag: jump the queue (collision someone is waiting on).
const PRIORITY: i32 = 4;

struct Job {
    coord: ChunkCoord,
    /// LOD spacing, or 0 for no mesh.
    step: u32,
    decor: bool,
    heights: bool,
}

struct Output {
    coord: ChunkCoord,
    step: u32,
    hash: u64,
    mesh: Option<MeshData>,
    decor: Option<(Vec<TreeInstance>, Vec<PropInstance>)>,
    heights: Option<Vec<f32>>,
    micros: u64,
}

#[derive(Default)]
struct Queue {
    jobs: VecDeque<Job>,
    shutdown: bool,
}

#[derive(Default)]
struct Shared {
    queue: Mutex<Queue>,
    wake: Condvar,
}

/// Background terrain chunk generator.
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct ChunkBuilder {
    shared: Option<Arc<Shared>>,
    results: Option<Receiver<Output>>,
    workers: Vec<JoinHandle<()>>,
    in_flight: usize,
}

/// On Apple Silicon, mark the thread as "utility" work so the scheduler prefers efficiency
/// cores, keeping performance cores free for Godot's main and render threads.
#[cfg(target_os = "macos")]
fn prefer_efficiency_cores() {
    const QOS_CLASS_UTILITY: u32 = 0x11;
    unsafe extern "C" {
        fn pthread_set_qos_class_self_np(qos_class: u32, relative_priority: i32) -> i32;
    }
    // SAFETY: only changes the calling thread's scheduling class.
    unsafe {
        pthread_set_qos_class_self_np(QOS_CLASS_UTILITY, 0);
    }
}

#[cfg(not(target_os = "macos"))]
fn prefer_efficiency_cores() {}

fn worker(world: Arc<World>, shared: Arc<Shared>, tx: Sender<Output>) {
    prefer_efficiency_cores();
    loop {
        let job = {
            let mut q = shared.queue.lock().expect("queue poisoned");
            loop {
                if q.shutdown {
                    return;
                }
                if let Some(job) = q.jobs.pop_front() {
                    break job;
                }
                q = shared.wake.wait(q).expect("queue poisoned");
            }
        };
        let started = Instant::now();
        let hf = world.heightfield(job.coord);
        let out = Output {
            coord: job.coord,
            step: job.step,
            hash: hf.content_hash(),
            mesh: (job.step > 0).then(|| mesh::chunk_mesh(&world, &hf, job.step)),
            decor: job.decor.then(|| {
                let trees = scatter::trees(&world, &hf);
                let props = scatter::props(&world, &hf, &trees);
                (trees, props)
            }),
            heights: job.heights.then(|| hf.heights_m()),
            micros: started.elapsed().as_micros() as u64,
        };
        if tx.send(out).is_err() {
            return; // Builder dropped.
        }
    }
}

#[godot_api]
impl ChunkBuilder {
    /// `request()` flag: also scatter trees and props.
    #[constant]
    const DECOR: i32 = DECOR;
    /// `request()` flag: also return the raw heights (for collision).
    #[constant]
    const HEIGHTS: i32 = HEIGHTS;
    /// `request()` flag: jump the queue (collision someone is waiting on).
    #[constant]
    const PRIORITY: i32 = PRIORITY;

    /// Starts `threads` workers (0 = one per spare CPU core) for seed `code`.
    #[func]
    fn start(&mut self, code: GString, threads: i32) -> bool {
        self.stop();
        let world = match SeedCode::parse(&code.to_string()).and_then(World::new) {
            Ok(w) => Arc::new(w),
            Err(e) => {
                godot_error!("ChunkBuilder: bad seed code '{code}': {e}");
                return false;
            }
        };
        let threads = if threads > 0 {
            threads as usize
        } else {
            thread::available_parallelism()
                .map(|n| n.get().saturating_sub(1).max(1))
                .unwrap_or(2)
        };
        let shared = Arc::new(Shared::default());
        let (tx, rx) = mpsc::channel();
        for i in 0..threads {
            let (world, shared, tx) = (world.clone(), shared.clone(), tx.clone());
            let handle = thread::Builder::new()
                .name(format!("rvgen-{i}"))
                .spawn(move || worker(world, shared, tx));
            match handle {
                Ok(h) => self.workers.push(h),
                Err(e) => godot_error!("ChunkBuilder: could not spawn worker: {e}"),
            }
        }
        self.shared = Some(shared);
        self.results = Some(rx);
        !self.workers.is_empty()
    }

    /// Number of worker threads running.
    #[func]
    fn thread_count(&self) -> i32 {
        self.workers.len() as i32
    }

    /// Queues a chunk. `step` is the mesh LOD spacing (1, 2, 4 or 8 m), or 0 for no mesh.
    /// `flags` is a mix of `DECOR`, `HEIGHTS` and `PRIORITY`. Jobs run in request order,
    /// except that `PRIORITY` ones go to the front.
    #[func]
    fn request(&mut self, cx: i32, cz: i32, step: i32, flags: i32) {
        let Some(shared) = &self.shared else {
            godot_error!("ChunkBuilder: call start() first");
            return;
        };
        if step != 0 && !mesh::LOD_STEPS.contains(&(step as u32)) {
            godot_error!(
                "ChunkBuilder.request: step must be 0 or one of {:?}",
                mesh::LOD_STEPS
            );
            return;
        }
        if step == 0 && flags & (DECOR | HEIGHTS) == 0 {
            godot_error!("ChunkBuilder.request: nothing requested");
            return;
        }
        let job = Job {
            coord: ChunkCoord::new(cx, cz),
            step: step as u32,
            decor: flags & DECOR != 0,
            heights: flags & HEIGHTS != 0,
        };
        let mut queue = shared.queue.lock().expect("queue poisoned");
        if flags & PRIORITY != 0 {
            queue.jobs.push_front(job);
        } else {
            queue.jobs.push_back(job);
        }
        drop(queue);
        shared.wake.notify_one();
        self.in_flight += 1;
    }

    /// Drops jobs that have not started yet (e.g. after the camera moved). Returns how many.
    #[func]
    fn clear_queue(&mut self) -> i32 {
        let Some(shared) = &self.shared else {
            return 0;
        };
        let mut q = shared.queue.lock().expect("queue poisoned");
        let dropped = q.jobs.len();
        q.jobs.clear();
        self.in_flight -= dropped;
        dropped as i32
    }

    /// Jobs queued or running whose results have not been polled yet.
    #[func]
    fn pending(&self) -> i32 {
        self.in_flight as i32
    }

    /// Up to `max` finished chunks, each a Dictionary with keys `cx`, `cz`, `step`, `hash`,
    /// `arrays` (for `add_surface_from_arrays`, or null when `step` is 0), `gen_usec`,
    /// `heights` (129 × 129 PackedFloat32Array, or null) and, with `DECOR` (else null / 0):
    /// - `trees`: packed `[x, y, z, yaw, scale, kind] * tree_count`;
    /// - `tree_buffers`: one `MultiMesh.buffer` per tree kind;
    /// - `props`: packed `[3×4 transform, kind, variant] * prop_count` (see `props_packed`).
    #[func]
    fn poll(&mut self, max: i32) -> VarArray {
        let mut out = VarArray::new();
        let Some(rx) = &self.results else {
            return out;
        };
        for _ in 0..max.max(0) {
            let Ok(r) = rx.try_recv() else {
                break;
            };
            self.in_flight = self.in_flight.saturating_sub(1);
            let mut d = VarDictionary::new();
            let mut put = |k: &str, v: Variant| d.set(&k.to_variant(), &v);
            put("cx", r.coord.x.to_variant());
            put("cz", r.coord.z.to_variant());
            put("step", (r.step as i32).to_variant());
            put("hash", convert::hash_hex(r.hash).to_variant());
            put(
                "arrays",
                r.mesh
                    .as_ref()
                    .map_or(Variant::nil(), |m| convert::mesh_arrays(m).to_variant()),
            );
            match &r.decor {
                Some((trees, props)) => {
                    put("trees", convert::trees_packed(trees).to_variant());
                    put(
                        "tree_buffers",
                        convert::trees_multimesh_buffers(trees).to_variant(),
                    );
                    put("tree_count", (trees.len() as i32).to_variant());
                    put("props", convert::props_packed(props).to_variant());
                    put("prop_count", (props.len() as i32).to_variant());
                }
                None => {
                    put("trees", Variant::nil());
                    put("tree_buffers", Variant::nil());
                    put("tree_count", 0.to_variant());
                    put("props", Variant::nil());
                    put("prop_count", 0.to_variant());
                }
            }
            put(
                "heights",
                r.heights.map_or(Variant::nil(), |h| {
                    PackedFloat32Array::from(h.as_slice()).to_variant()
                }),
            );
            put("gen_usec", (r.micros as i64).to_variant());
            out.push(&d.to_variant());
        }
        out
    }

    /// Stops all workers and discards queued work. Safe to call repeatedly.
    #[func]
    fn stop(&mut self) {
        if let Some(shared) = self.shared.take() {
            {
                let mut q = shared.queue.lock().expect("queue poisoned");
                q.shutdown = true;
                q.jobs.clear();
            }
            shared.wake.notify_all();
        }
        self.results = None;
        for h in self.workers.drain(..) {
            let _ = h.join();
        }
        self.in_flight = 0;
    }
}

impl Drop for ChunkBuilder {
    fn drop(&mut self) {
        self.stop();
    }
}

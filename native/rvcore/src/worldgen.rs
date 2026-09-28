//! `WorldGen`: synchronous access to the generator (seed codes, hashes, heights, one-off
//! chunks). Streaming uses `ChunkBuilder` instead so the main thread never waits.

use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use godot::prelude::*;
use rvgen::route::{PLANK_LENGTH, ROAD_HALF_WIDTH, SAMPLE};
use rvgen::{ChunkCoord, GEN_VERSION, SeedCode, TripLength, World, mesh, scatter};

use crate::convert;

/// Deterministic world generator bound to one seed code.
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct WorldGen {
    world: Option<World>,
}

static ENTROPY_COUNTER: AtomicU64 = AtomicU64::new(0);

fn trip_from(index: i32) -> TripLength {
    TripLength::from_index(index.clamp(0, 2) as u8).unwrap_or(TripLength::Short)
}

#[godot_api]
impl WorldGen {
    /// Generator version baked into seed codes and saves.
    #[func]
    fn gen_version() -> i32 {
        GEN_VERSION as i32
    }

    /// A fresh random seed code. `trip`: 0 = short, 1 = medium, 2 = long.
    #[func]
    fn random_code(trip: i32) -> GString {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_nanos() as u64)
            .unwrap_or(0);
        let entropy = nanos
            ^ ENTROPY_COUNTER
                .fetch_add(1, Ordering::Relaxed)
                .rotate_left(32);
        GString::from(
            SeedCode::from_entropy(trip_from(trip), entropy)
                .to_string()
                .as_str(),
        )
    }

    /// Human-readable problem with `code`, or an empty string if it can be played.
    #[func]
    fn code_error(code: GString) -> GString {
        let result = SeedCode::parse(&code.to_string()).and_then(|c| c.check_supported());
        match result {
            Ok(()) => GString::new(),
            Err(e) => GString::from(e.to_string().as_str()),
        }
    }

    /// Binds this generator to `code`. Returns false (and logs why) if the code is invalid.
    #[func]
    fn load(&mut self, code: GString) -> bool {
        match SeedCode::parse(&code.to_string()).and_then(World::new) {
            Ok(world) => {
                self.world = Some(world);
                true
            }
            Err(e) => {
                godot_error!("WorldGen: bad seed code '{code}': {e}");
                false
            }
        }
    }

    /// The normalised seed code, or "" if nothing is loaded.
    #[func]
    fn get_code(&self) -> GString {
        self.world
            .as_ref()
            .map(|w| GString::from(w.code().to_string().as_str()))
            .unwrap_or_default()
    }

    /// Content hash of one chunk, as 16 hex digits. Peers compare these on join.
    #[func]
    fn chunk_hash(&self, cx: i32, cz: i32) -> GString {
        match self.world() {
            Some(w) => convert::hash_hex(w.heightfield(ChunkCoord::new(cx, cz)).content_hash()),
            None => GString::new(),
        }
    }

    /// 129 × 129 heights in metres for `HeightMapShape3D.map_data`.
    #[func]
    fn chunk_heights(&self, cx: i32, cz: i32) -> PackedFloat32Array {
        match self.world() {
            Some(w) => PackedFloat32Array::from(
                w.heightfield(ChunkCoord::new(cx, cz))
                    .heights_m()
                    .as_slice(),
            ),
            None => PackedFloat32Array::new(),
        }
    }

    /// Mesh arrays for one chunk at LOD spacing `step` (1, 2, 4 or 8 m).
    #[func]
    fn chunk_mesh(&self, cx: i32, cz: i32, step: i32) -> VarArray {
        let Some(w) = self.world() else {
            return VarArray::new();
        };
        if !mesh::LOD_STEPS.contains(&(step as u32)) {
            godot_error!(
                "WorldGen.chunk_mesh: step must be one of {:?}",
                mesh::LOD_STEPS
            );
            return VarArray::new();
        }
        let hf = w.heightfield(ChunkCoord::new(cx, cz));
        convert::mesh_arrays(&mesh::chunk_mesh(w, &hf, step as u32))
    }

    /// Trees in one chunk, packed as `[x, y, z, yaw, scale, kind] * n` (chunk-local).
    #[func]
    fn chunk_trees(&self, cx: i32, cz: i32) -> PackedFloat32Array {
        match self.world() {
            Some(w) => {
                let hf = w.heightfield(ChunkCoord::new(cx, cz));
                convert::trees_packed(&scatter::trees(w, &hf))
            }
            None => PackedFloat32Array::new(),
        }
    }

    /// Props in one chunk, packed as `[3×4 transform, kind, variant] * n` (chunk-local; see
    /// `ChunkBuilder.poll`).
    #[func]
    fn chunk_props(&self, cx: i32, cz: i32) -> PackedFloat32Array {
        match self.world() {
            Some(w) => {
                let hf = w.heightfield(ChunkCoord::new(cx, cz));
                let trees = scatter::trees(w, &hf);
                convert::props_packed(&scatter::props(w, &hf, &trees))
            }
            None => PackedFloat32Array::new(),
        }
    }

    /// The trip, as a Dictionary:
    /// - `length` (metres of road), `road_half_width`, `plank_length`;
    /// - `points`: PackedVector3Array of the road centreline (x, road height, z) every 8 m;
    /// - `pads`: [{kind: 0 camp | 1 station | 2 home, s, pos: Vector3, dir: Vector3, side}];
    /// - `obstacles`: [{kind: 0 gap | 1 ledge | 2 mud | 3 climb, s, pos, dir, length, size,
    ///   difficulty}];
    /// - `supplies`: [{kind: 0 planks | 1 anchor, pos, dir, count}].
    #[func]
    fn trip(&self) -> VarDictionary {
        let mut d = VarDictionary::new();
        let Some(w) = self.world() else {
            return d;
        };
        let r = w.route();
        let v3 = |p: [f32; 3]| Vector3::new(p[0], p[1], p[2]);
        let dir3 = |d: [f32; 2]| Vector3::new(d[0], 0.0, d[1]);
        let every = (8.0 / SAMPLE) as usize;
        let points: PackedVector3Array =
            r.xz.iter()
                .zip(&r.h)
                .step_by(every)
                .map(|(p, &h)| Vector3::new(p[0], h, p[1]))
                .collect();
        let mut pads = VarArray::new();
        for p in &r.pads {
            let mut e = VarDictionary::new();
            e.set("kind", p.kind as i32);
            e.set("s", p.s);
            e.set("pos", v3(p.pos));
            e.set("dir", dir3(p.dir));
            e.set("side", p.side);
            pads.push(&e.to_variant());
        }
        let mut obstacles = VarArray::new();
        for o in &r.obstacles {
            let mut e = VarDictionary::new();
            e.set("kind", o.kind as i32);
            e.set("s", o.s);
            e.set("pos", v3(o.pos));
            e.set("dir", dir3(o.dir));
            e.set("length", o.length);
            e.set("size", o.size);
            e.set("difficulty", o.difficulty);
            obstacles.push(&e.to_variant());
        }
        let mut supplies = VarArray::new();
        for s in &r.supplies {
            let mut e = VarDictionary::new();
            e.set("kind", s.kind as i32);
            e.set("pos", v3(s.pos));
            e.set("dir", dir3(s.yaw_dir));
            e.set("count", s.count as i32);
            supplies.push(&e.to_variant());
        }
        d.set("length", r.length);
        d.set("road_half_width", ROAD_HALF_WIDTH);
        d.set("plank_length", PLANK_LENGTH);
        d.set("points", &points.to_variant());
        d.set("pads", &pads.to_variant());
        d.set("obstacles", &obstacles.to_variant());
        d.set("supplies", &supplies.to_variant());
        d
    }

    /// How muddy the ground is at a world position, 0..1 (the game lowers tire grip).
    #[func]
    fn mud_at(&self, x: f32, z: f32) -> f32 {
        self.world().map_or(0.0, |w| w.route().mud_at(x, z))
    }

    /// Distance along the road of the closest road point, or -1 if well away from it.
    #[func]
    fn road_progress(&self, x: f32, z: f32) -> f32 {
        self.world()
            .and_then(|w| w.route().near(x, z))
            .map_or(-1.0, |r| r.s)
    }

    /// Terrain height in metres at a world position (matches the collision shape).
    #[func]
    fn height_at(&self, x: f32, z: f32) -> f32 {
        self.world().map_or(0.0, |w| w.height_at(x, z))
    }
}

impl WorldGen {
    fn world(&self) -> Option<&World> {
        if self.world.is_none() {
            godot_error!("WorldGen: call load(code) first");
        }
        self.world.as_ref()
    }
}

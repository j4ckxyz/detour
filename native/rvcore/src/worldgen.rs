//! `WorldGen`: synchronous access to the generator (seed codes, hashes, heights, one-off
//! chunks). Streaming uses `ChunkBuilder` instead so the main thread never waits.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};

use godot::prelude::*;
use rvgen::route::{
    BEAM_OFFSET, BEAM_WIDTH, DECK_KICKER, KICKER, PLANK_LENGTH, RIVER_HALF, ROAD_HALF_WIDTH, SAMPLE,
};
use rvgen::{ChunkCoord, GEN_VERSION, SeedCode, TripLength, World, mesh, scatter};

use crate::cache::{self, Progress};
use crate::convert;

/// Deterministic world generator bound to one seed code.
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct WorldGen {
    world: Option<Arc<World>>,
    loading: Option<Arc<Mutex<Progress>>>,
    load_error: String,
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

    /// Any text as a seed (like Minecraft): `{code, error}`. A seed code is itself, a whole
    /// number is that seed, anything else (the first 20 characters) is hashed; blank text
    /// gives an empty code (roll a new trip). `trip`: 0 short, 1 medium, 2 long (a typed
    /// seed code keeps its own).
    #[func]
    fn code_from_text(text: GString, trip: i32) -> VarDictionary {
        let mut d = VarDictionary::new();
        let (code, error) = match SeedCode::from_text(trip_from(trip), &text.to_string()) {
            None => (String::new(), String::new()),
            Some(Ok(c)) => (c.to_string(), String::new()),
            Some(Err(e)) => (String::new(), e.to_string()),
        };
        d.set("code", code.as_str());
        d.set("error", error.as_str());
        d
    }

    /// The longest text `code_from_text` reads.
    #[func]
    fn text_seed_max() -> i32 {
        rvgen::seed::TEXT_SEED_MAX as i32
    }

    /// Whether the world for `code` has been built already this session (loading is instant).
    #[func]
    fn is_cached(code: GString) -> bool {
        SeedCode::parse(&code.to_string()).is_ok_and(|c| cache::cached(c).is_some())
    }

    /// Binds this generator to `code`, building its world now if it hasn't been. Returns
    /// false (and logs why) if the code is invalid.
    #[func]
    fn load(&mut self, code: GString) -> bool {
        match cache::world_for(&code.to_string()) {
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

    /// Starts building the world for `code` on a background thread; follow it with
    /// `load_progress`, `load_stage` and `poll_load`.
    #[func]
    fn begin_load(&mut self, code: GString) {
        self.loading = Some(cache::load_in_background(&code.to_string()));
    }

    /// 0..1: how far the background load has got.
    #[func]
    fn load_progress(&self) -> f32 {
        self.loading
            .as_ref()
            .and_then(|l| l.lock().ok().map(|p| p.fraction))
            .unwrap_or(0.0)
    }

    /// What the background load is doing ("Surveying routes", ...).
    #[func]
    fn load_stage(&self) -> GString {
        self.loading
            .as_ref()
            .and_then(|l| l.lock().ok().map(|p| GString::from(p.stage.as_str())))
            .unwrap_or_default()
    }

    /// 0 while the background load runs, 1 once it's done (the world is bound), -1 if it
    /// failed (see `load_error`).
    #[func]
    fn poll_load(&mut self) -> i32 {
        let Some(loading) = &self.loading else {
            return if self.world.is_some() { 1 } else { -1 };
        };
        let result = loading.lock().ok().and_then(|mut p| p.result.take());
        match result {
            None => 0,
            Some(Ok(world)) => {
                self.world = Some(world);
                self.loading = None;
                1
            }
            Some(Err(e)) => {
                self.load_error = e;
                self.loading = None;
                -1
            }
        }
    }

    /// Why the last background load failed.
    #[func]
    fn load_error(&self) -> GString {
        GString::from(self.load_error.as_str())
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
    ///   difficulty, start, end (the arc lengths of the stretch of road it takes up)}];
    /// - `supplies`: [{kind: 0 planks | 1 anchor, pos, dir, count, s (arc length nearest it)}];
    /// - `lakes`: [{pos: Vector3 (centre, water level), radius, frozen}];
    /// - `caves`: [{pos, dir, biome}];
    /// - `biomes`: PackedInt32Array, the biomes in the order the road meets them
    ///   (0 woods, 1 bayou, 2 canyon, 3 mountain pass).
    ///
    /// Obstacle kinds also include 4 ford (a river across the road: `length` is the channel
    /// width, `size` the water depth), 5 ice (a frozen pond: `length` its radius, `size`
    /// how far below the road it lies), 6 bridge (over a ravine `length` wide, `size` deep;
    /// its deck has a hole `hole` long centred `hole_at` along it, with a little kicker of
    /// `deck_kicker` (height, length) before), 7 beams (two narrow beams, `beam_width` wide at
    /// ±`beam_offset`, across a ravine) and 8 jump (a gully with a `kicker` ramp before its
    /// lip) and 9 hill (a steep climb `length` long rising `size`).
    ///
    /// Also `pois`: [{kind: 0 cabin | 1 tower | 2 wreck | 3 lookout, pos, dir, radius}] and
    /// `spurs` (side tracks to nowhere): [{from_s, points}].
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
            e.set("hole", o.hole);
            e.set("hole_at", o.hole_at);
            let (start, end) = o.extent();
            e.set("start", start);
            e.set("end", end);
            obstacles.push(&e.to_variant());
        }
        let mut supplies = VarArray::new();
        for s in &r.supplies {
            let mut e = VarDictionary::new();
            e.set("kind", s.kind as i32);
            e.set("pos", v3(s.pos));
            e.set("dir", dir3(s.yaw_dir));
            e.set("count", s.count as i32);
            e.set("s", s.s);
            supplies.push(&e.to_variant());
        }
        let mut lakes = VarArray::new();
        for l in &r.lakes {
            let mut e = VarDictionary::new();
            e.set("pos", v3(l.pos));
            e.set("radius", l.radius);
            e.set("frozen", l.frozen);
            lakes.push(&e.to_variant());
        }
        let mut caves = VarArray::new();
        for c in &r.caves {
            let mut e = VarDictionary::new();
            e.set("pos", v3(c.pos));
            e.set("dir", dir3(c.dir));
            e.set("biome", c.biome as i32);
            caves.push(&e.to_variant());
        }
        let mut pois = VarArray::new();
        for p in &r.pois {
            let mut e = VarDictionary::new();
            e.set("kind", p.kind as i32);
            e.set("pos", v3(p.pos));
            e.set("dir", dir3(p.dir));
            e.set("radius", p.radius);
            pois.push(&e.to_variant());
        }
        let mut spurs = VarArray::new();
        for sp in &r.spurs {
            let mut e = VarDictionary::new();
            let points: PackedVector3Array = sp
                .xz
                .iter()
                .zip(&sp.h)
                .step_by(every)
                .map(|(p, &h)| Vector3::new(p[0], h, p[1]))
                .collect();
            e.set("from_s", sp.from_s);
            e.set("points", &points.to_variant());
            spurs.push(&e.to_variant());
        }
        let biomes: PackedInt32Array = w
            .terrain()
            .biomes()
            .sequence()
            .iter()
            .map(|b| *b as i32)
            .collect();
        d.set("pois", &pois.to_variant());
        d.set("spurs", &spurs.to_variant());
        d.set("kicker", Vector2::new(KICKER[0], KICKER[1]));
        d.set("deck_kicker", Vector2::new(DECK_KICKER[0], DECK_KICKER[1]));
        d.set("beam_width", BEAM_WIDTH);
        d.set("beam_offset", BEAM_OFFSET);
        d.set("lakes", &lakes.to_variant());
        d.set("caves", &caves.to_variant());
        d.set("biomes", &biomes.to_variant());
        d.set("river_half", RIVER_HALF);
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

    /// How icy the ground is at a world position, 0..1 (almost no tire grip on ice).
    #[func]
    fn ice_at(&self, x: f32, z: f32) -> f32 {
        self.world().map_or(0.0, |w| w.route().ice_at(x, z))
    }

    /// The water surface height over a point (a river or a lake), or -10000 if it's dry.
    #[func]
    fn water_level(&self, x: f32, z: f32) -> f32 {
        self.world()
            .and_then(|w| w.route().water_at(x, z))
            .unwrap_or(NO_WATER)
    }

    /// The main biome at a world position: 0 woods, 1 bayou, 2 canyon, 3 mountain pass.
    #[func]
    fn biome_at(&self, x: f32, z: f32) -> i32 {
        self.world()
            .map_or(0, |w| w.terrain().biomes().at(x, z) as i32)
    }

    /// How far outside the valley floor a point is (metres; <= 0 on the floor, where you
    /// can walk; past it the walls rise).
    #[func]
    fn outside_valley(&self, x: f32, z: f32) -> f32 {
        self.world().map_or(0.0, |w| w.route().outside_valley(x, z))
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

const NO_WATER: f32 = -10000.0;

impl WorldGen {
    fn world(&self) -> Option<&World> {
        if self.world.is_none() {
            godot_error!("WorldGen: call load(code) first");
        }
        self.world.as_deref()
    }
}

//! Deterministic world generation for Detour.
//!
//! Every client builds the world locally from a short seed code, so the output of this crate
//! must be **bit-identical on every OS and CPU** we ship (x86_64 and ARM64). Rules:
//!
//! - Only IEEE-754 basic operations (`+ - * /`, `sqrt`, `floor`, `round`, `abs`, `min`, `max`).
//!   These are correctly rounded everywhere. Rust never fuses `a * b + c` into an FMA unless we
//!   call `mul_add` explicitly, and has no fast-math.
//! - No platform `libm` transcendental functions (`sin`, `exp`, `powf`, ...). If one is ever
//!   needed, use the pure-Rust `libm` crate so every platform runs the same code.
//! - No `std` hashers or `HashMap` iteration order in anything that affects output.
//! - Every random decision comes from [`rng::Pcg32`] seeded via [`hash::sub_seed`].
//!
//! `tests/golden.rs` pins chunk hashes; CI runs it on every target triple.

pub mod biome;
pub mod chunk;
pub mod hash;
pub mod mesh;
pub mod noise;
pub mod rng;
pub mod route;
pub mod scatter;
pub mod seed;
pub mod terrain;

pub use chunk::{CHUNK_SIZE, CHUNK_VERTS, ChunkCoord, Heightfield};
pub use seed::{GEN_VERSION, SeedCode, SeedCodeError, TripLength};

use route::Route;
use terrain::TerrainGen;

/// A generated world: everything derivable from one seed code.
#[derive(Clone, Debug)]
pub struct World {
    code: SeedCode,
    world_seed: u64,
    terrain: TerrainGen,
    route: Route,
}

impl World {
    /// Builds the world for `code`. Fails if the code was made by a different generator version.
    pub fn new(code: SeedCode) -> Result<Self, SeedCodeError> {
        code.check_supported()?;
        let world_seed = code.world_seed();
        let terrain = TerrainGen::new(world_seed, code.trip);
        let route = Route::generate(world_seed, code.trip, &terrain);
        Ok(Self {
            code,
            world_seed,
            terrain,
            route,
        })
    }

    pub fn code(&self) -> SeedCode {
        self.code
    }

    pub fn world_seed(&self) -> u64 {
        self.world_seed
    }

    pub fn terrain(&self) -> &TerrainGen {
        &self.terrain
    }

    /// The trip: road, obstacles, stations.
    pub fn route(&self) -> &Route {
        &self.route
    }

    /// Quantised height at an integer world grid point (1 m grid), road and obstacles
    /// included. This is the canonical, hashed value.
    pub fn height_q(&self, gx: i32, gz: i32) -> u16 {
        let (x, z) = (gx as f32, gz as f32);
        let natural = self.terrain.height_m(x, z);
        let h = self.route.shape(x, z, natural);
        terrain::quantize(h)
    }

    /// Generates the full-resolution heightfield of one chunk.
    pub fn heightfield(&self, coord: ChunkCoord) -> Heightfield {
        Heightfield::generate(self, coord)
    }

    /// Bilinear height in metres at any world position, from the quantised grid.
    /// This matches what the collision heightfield reports.
    pub fn height_at(&self, x: f32, z: f32) -> f32 {
        let x0 = x.floor();
        let z0 = z.floor();
        let (ix, iz) = (x0 as i32, z0 as i32);
        let (fx, fz) = (x - x0, z - z0);
        let h00 = terrain::q_to_m(self.height_q(ix, iz));
        let h10 = terrain::q_to_m(self.height_q(ix + 1, iz));
        let h01 = terrain::q_to_m(self.height_q(ix, iz + 1));
        let h11 = terrain::q_to_m(self.height_q(ix + 1, iz + 1));
        let a = h00 + (h10 - h00) * fx;
        let b = h01 + (h11 - h01) * fx;
        a + (b - a) * fz
    }
}

//! Terrain height function.
//!
//! Phase 0 uses one placeholder biome ("pine hills") so we can benchmark rendering and prove
//! cross-platform determinism. The route-aware corridor terrain from PLAN.md §5.2 replaces
//! this in Phase 3 (bump `GEN_VERSION` when it does).

use crate::hash::sub_seed32;
use crate::noise::{Fractal, fbm, perlin, ridged, smoothstep};

/// Quantisation: 2 cm steps, so a `u16` covers 0–1310.7 m.
pub const HEIGHT_STEPS_PER_M: f32 = 50.0;
const MAX_HEIGHT_M: f32 = 1310.0;

/// Quantises a height in metres to 2 cm steps.
#[inline]
pub fn quantize(m: f32) -> u16 {
    (m.clamp(0.0, MAX_HEIGHT_M) * HEIGHT_STEPS_PER_M).round() as u16
}

/// Converts a quantised height to metres.
#[inline]
pub fn q_to_m(q: u16) -> f32 {
    q as f32 / HEIGHT_STEPS_PER_M
}

const WARP: Fractal = Fractal {
    octaves: 3,
    frequency: 1.0 / 512.0,
    lacunarity: 2.0,
    gain: 0.5,
};
const BASE: Fractal = Fractal {
    octaves: 6,
    frequency: 1.0 / 1024.0,
    lacunarity: 2.0,
    gain: 0.5,
};
const RIDGE: Fractal = Fractal {
    octaves: 5,
    frequency: 1.0 / 2048.0,
    lacunarity: 2.0,
    gain: 0.5,
};
const MASK: Fractal = Fractal {
    octaves: 2,
    frequency: 1.0 / 4096.0,
    lacunarity: 2.0,
    gain: 0.5,
};
const HILLS: Fractal = Fractal {
    octaves: 4,
    frequency: 1.0 / 256.0,
    lacunarity: 2.0,
    gain: 0.45,
};
const DETAIL: Fractal = Fractal {
    octaves: 3,
    frequency: 1.0 / 32.0,
    lacunarity: 2.0,
    gain: 0.5,
};
const FOREST: Fractal = Fractal {
    octaves: 3,
    frequency: 1.0 / 256.0,
    lacunarity: 2.0,
    gain: 0.5,
};
const ROCKS: Fractal = Fractal {
    octaves: 2,
    frequency: 1.0 / 192.0,
    lacunarity: 2.0,
    gain: 0.5,
};

/// Height above which trees stop growing.
pub const TREELINE_M: f32 = 320.0;

#[derive(Clone, Debug)]
pub struct TerrainGen {
    warp_x: u32,
    warp_z: u32,
    base: u32,
    ridge: u32,
    mask: u32,
    hills: u32,
    detail: u32,
    forest: u32,
    rocks: u32,
    tint: u32,
}

impl TerrainGen {
    pub fn new(world_seed: u64) -> Self {
        Self {
            warp_x: sub_seed32(world_seed, "terrain.warp_x"),
            warp_z: sub_seed32(world_seed, "terrain.warp_z"),
            base: sub_seed32(world_seed, "terrain.base"),
            ridge: sub_seed32(world_seed, "terrain.ridge"),
            mask: sub_seed32(world_seed, "terrain.mask"),
            hills: sub_seed32(world_seed, "terrain.hills"),
            detail: sub_seed32(world_seed, "terrain.detail"),
            forest: sub_seed32(world_seed, "terrain.forest"),
            rocks: sub_seed32(world_seed, "terrain.rocks"),
            tint: sub_seed32(world_seed, "terrain.tint"),
        }
    }

    /// Unquantised height in metres at world position `(x, z)`.
    pub fn height_m(&self, x: f32, z: f32) -> f32 {
        let wx = x + 80.0 * fbm(self.warp_x, x, z, &WARP);
        let wz = z + 80.0 * fbm(self.warp_z, x, z, &WARP);
        let rolling = 120.0 + 70.0 * fbm(self.base, wx, wz, &BASE);
        let hills = 28.0 * fbm(self.hills, wx, wz, &HILLS);
        let mountains = smoothstep(-0.1, 0.5, fbm(self.mask, x, z, &MASK));
        let peaks = 260.0 * ridged(self.ridge, wx, wz, &RIDGE) * mountains;
        let bumps = 0.6 * fbm(self.detail, x, z, &DETAIL);
        (rolling + hills + peaks + bumps).clamp(0.0, MAX_HEIGHT_M)
    }

    /// Quantised natural height at an integer grid point (no road). The world's canonical
    /// height is `World::height_q`, which adds the trip's road on top.
    pub fn height_q(&self, gx: i32, gz: i32) -> u16 {
        quantize(self.height_m(gx as f32, gz as f32))
    }

    /// Tree density in `[0, 1]` before slope and treeline limits.
    pub fn forest_density(&self, x: f32, z: f32) -> f32 {
        0.75 * smoothstep(-0.25, 0.35, fbm(self.forest, x, z, &FOREST))
    }

    /// How rocky the ground is, in `[0, 1]`, before slope and height are taken into account.
    pub fn rockiness(&self, x: f32, z: f32) -> f32 {
        smoothstep(-0.05, 0.45, fbm(self.rocks, x, z, &ROCKS))
    }

    /// Low-frequency colour variation in `[0, 1]`. Visual only.
    pub fn tint(&self, x: f32, z: f32) -> f32 {
        0.5 + 0.5 * perlin(self.tint, x * (1.0 / 64.0), z * (1.0 / 64.0))
    }
}

//! Terrain height function: rolling hills, ridged mountains and small bumps, reshaped by
//! biome (see [`crate::biome`]): the bayou is low and flat, the canyon is terraced into
//! cliffs, the mountain pass is higher with bigger relief.

use crate::biome::{Biomes, Weights};
use crate::hash::sub_seed32;
use crate::noise::{Fractal, fbm, perlin, ridged, smoothstep};
use crate::seed::TripLength;

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
    biomes: Biomes,
}

/// Canyon terraces: flat benches `step` metres apart joined by steep walls.
const TERRACE: f32 = 9.0;

fn terrace(h: f32, step: f32) -> f32 {
    let t = h / step;
    let floor = t.floor();
    (floor + smoothstep(0.6, 0.9, t - floor)) * step
}

impl TerrainGen {
    pub fn new(world_seed: u64, trip: TripLength) -> Self {
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
            biomes: Biomes::new(world_seed, trip),
        }
    }

    pub fn biomes(&self) -> &Biomes {
        &self.biomes
    }

    /// Unquantised height in metres at world position `(x, z)`.
    pub fn height_m(&self, x: f32, z: f32) -> f32 {
        let w = self.biomes.weights(x, z);
        self.height_with(x, z, &w)
    }

    /// Height given the biome weights there (callers that already have them).
    pub fn height_with(&self, x: f32, z: f32, w: &Weights) -> f32 {
        let wx = x + 80.0 * fbm(self.warp_x, x, z, &WARP);
        let wz = z + 80.0 * fbm(self.warp_z, x, z, &WARP);
        let rolling = 120.0 + 70.0 * fbm(self.base, wx, wz, &BASE);
        let hills = 28.0 * fbm(self.hills, wx, wz, &HILLS);
        let mountains = smoothstep(-0.1, 0.5, fbm(self.mask, x, z, &MASK));
        let peaks = 260.0 * ridged(self.ridge, wx, wz, &RIDGE) * mountains;
        let bumps = 0.6 * fbm(self.detail, x, z, &DETAIL);
        let mut h = 0.0;
        if w[0] > 0.0 {
            h += w[0] * (rolling + hills + peaks + bumps);
        }
        if w[1] > 0.0 {
            h += w[1] * (rolling - 6.0 + 0.3 * hills + 0.12 * peaks + 0.4 * bumps);
        }
        if w[2] > 0.0 {
            h += w[2] * (terrace(rolling + 1.3 * hills + 0.7 * peaks, TERRACE) + 0.3 * bumps);
        }
        if w[3] > 0.0 {
            h += w[3] * (rolling + 18.0 + 1.4 * hills + 1.5 * peaks + bumps);
        }
        h.clamp(0.0, MAX_HEIGHT_M)
    }

    /// Quantised natural height at an integer grid point (no road). The world's canonical
    /// height is `World::height_q`, which adds the trip's road on top.
    pub fn height_q(&self, gx: i32, gz: i32) -> u16 {
        quantize(self.height_m(gx as f32, gz as f32))
    }

    /// Tree density in `[0, 1]` before slope and treeline limits: thick pine woods, thinner
    /// bayou and pass, a few cacti in the canyon.
    pub fn forest_density(&self, x: f32, z: f32) -> f32 {
        let w = self.biomes.weights(x, z);
        let f = 0.75 * smoothstep(-0.25, 0.35, fbm(self.forest, x, z, &FOREST));
        f * (w[0] + 0.5 * w[1] + 0.45 * w[3]) + 0.05 * w[2]
    }

    /// How rocky the ground is, in `[0, 1]`, before slope and height are taken into account.
    pub fn rockiness(&self, x: f32, z: f32) -> f32 {
        let w = self.biomes.weights(x, z);
        let r = smoothstep(-0.05, 0.45, fbm(self.rocks, x, z, &ROCKS));
        (r * (1.0 - 0.6 * w[1]) + 0.35 * w[2] + 0.2 * w[3]).min(1.0)
    }

    /// Low-frequency colour variation in `[0, 1]`. Visual only.
    pub fn tint(&self, x: f32, z: f32) -> f32 {
        0.5 + 0.5 * perlin(self.tint, x * (1.0 / 64.0), z * (1.0 / 64.0))
    }
}

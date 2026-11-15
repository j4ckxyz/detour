//! A world's personality: a handful of numbers drawn once from the seed that every layer of
//! the generator reads, so that whole trips differ in character and not just in detail. One
//! seed is big mountains and a road that zig-zags up them; another is open plains with long
//! sweeping bends; another is low, wet river country.
//!
//! Each seed picks an [`Archetype`] and then jitters every number round that archetype's
//! values, so two worlds of the same archetype still aren't alike.

use crate::hash::sub_seed;
use crate::rng::Pcg32;

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
#[repr(u8)]
pub enum Archetype {
    /// Rolling hill country: a bit of everything.
    Rolling = 0,
    /// Open plains: gentle ground, few mountains, a road of long sweeping bends.
    Plains = 1,
    /// Highlands: big relief, mountains everywhere, a road that zig-zags up and down them.
    Highlands = 2,
    /// River country: low and wet, with fords, mud and ponds whatever the biome.
    Rivers = 3,
    /// Badlands: dry, broken, twisted ground and a tight, twisty road.
    Badlands = 4,
}

pub const ARCHETYPES: usize = 5;
pub const ALL: [Archetype; ARCHETYPES] = [
    Archetype::Rolling,
    Archetype::Plains,
    Archetype::Highlands,
    Archetype::Rivers,
    Archetype::Badlands,
];

impl Archetype {
    pub const fn name(self) -> &'static str {
        match self {
            Self::Rolling => "Rolling hills",
            Self::Plains => "Open plains",
            Self::Highlands => "Highlands",
            Self::Rivers => "River country",
            Self::Badlands => "Badlands",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Personality {
    pub archetype: Archetype,
    /// Scales the broad shape of the land: plateaus, basins and rolling ground (~0.4–1.6).
    pub relief: f32,
    /// Shifts how much of the world is mountains (~-0.35 none to speak of, +0.35 most of it).
    pub mountains: f32,
    /// Scales how tall the mountains are (~0.5–1.6).
    pub peaks: f32,
    /// Scales the hills (~0.45–1.9).
    pub ruggedness: f32,
    /// How far the land is twisted about (domain warp, metres).
    pub warp: f32,
    /// How wet the world is, 0–1: fords, mud and ponds turn up outside the bayou.
    pub wetness: f32,
    /// Eastward progress per metre of road the route aims for (1 = dead straight east). The
    /// road winds as much as it takes to hit this, so it's the seed's sinuosity.
    pub directness: f32,
    /// Scales the length of the road's bends (long sweepers > 1, tight and twisty < 1).
    pub bend_length: f32,
    /// How readily the road breaks into switchbacks, 0–1.
    pub switchbacks: f32,
}

impl Personality {
    pub fn new(world_seed: u64) -> Self {
        let mut rng = Pcg32::new(sub_seed(world_seed, "personality", 0, 0), 17);
        let archetype = ALL[rng.below(ARCHETYPES as u32) as usize];
        // [relief, mountains, peaks, ruggedness, warp, wetness, directness, bend, switchbacks]
        let base: [f32; 9] = match archetype {
            Archetype::Rolling => [1.0, 0.0, 1.0, 1.0, 80.0, 0.3, 0.73, 1.0, 0.35],
            Archetype::Plains => [0.45, -0.3, 0.6, 0.5, 50.0, 0.35, 0.8, 1.5, 0.08],
            Archetype::Highlands => [1.4, 0.3, 1.4, 1.35, 120.0, 0.15, 0.62, 0.85, 0.95],
            Archetype::Rivers => [0.6, -0.15, 0.8, 0.7, 70.0, 0.95, 0.69, 1.1, 0.2],
            Archetype::Badlands => [0.9, 0.0, 0.9, 1.7, 150.0, 0.05, 0.65, 0.65, 0.6],
        };
        // Every draw is made whatever the archetype, so the stream never shifts.
        let mut vary = |v: f32, by: f32| v * rng.range_f32(1.0 - by, 1.0 + by);
        let relief = vary(base[0], 0.15);
        let peaks = vary(base[2], 0.15);
        let ruggedness = vary(base[3], 0.12);
        let warp = vary(base[4], 0.2);
        let bend_length = vary(base[7], 0.15);
        let switchbacks = vary(base[8], 0.2).min(1.0);
        let mountains = base[1] + rng.range_f32(-0.08, 0.08);
        let wetness = (base[5] + rng.range_f32(-0.1, 0.1)).clamp(0.0, 1.0);
        let directness = base[6] + rng.range_f32(-0.03, 0.03);
        Self {
            archetype,
            relief,
            mountains,
            peaks,
            ruggedness,
            warp,
            wetness,
            directness,
            bend_length,
            switchbacks,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_archetype_turns_up_and_seeds_differ() {
        let mut seen = [0; ARCHETYPES];
        for seed in 0..200u64 {
            let p = Personality::new(crate::hash::mix64(seed));
            assert_eq!(p, Personality::new(crate::hash::mix64(seed)));
            seen[p.archetype as usize] += 1;
            assert!((0.55..=0.85).contains(&p.directness), "{p:?}");
            assert!(p.relief > 0.3 && p.relief < 1.7, "{p:?}");
        }
        assert!(seen.iter().all(|&n| n > 20), "{seen:?}");
    }
}

//! Biomes along the trip (PLAN.md §5.1): every trip starts in the pine woods, then passes
//! through the others in a seeded order, changing at (about) each gas station. The world is
//! split into bands along x (the road always heads east), with a wobbly, blended boundary.
//!
//! Biomes shape the terrain (flat, low swamps; terraced canyon walls; big alpine relief), the
//! ground colours, what grows and which obstacles the road throws at you.

use crate::hash::{sub_seed, sub_seed32};
use crate::noise::{perlin, smoothstep};
use crate::rng::Pcg32;
use crate::seed::TripLength;

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
#[repr(u8)]
pub enum Biome {
    /// Pine woods: rolling hills and forest (the start of every trip).
    Forest = 0,
    /// Bayou: low, flat and wet: mud, ponds and river fords.
    Swamp = 1,
    /// Red-rock canyon: dry, terraced cliffs, cacti, ledges and climbs.
    Canyon = 2,
    /// Mountain pass: big relief, snow, frozen lakes and ice.
    Alpine = 3,
}

pub const BIOMES: usize = 4;
pub const ALL: [Biome; BIOMES] = [Biome::Forest, Biome::Swamp, Biome::Canyon, Biome::Alpine];

/// Half-width of the blend between two biomes, metres.
const BLEND: f32 = 90.0;
/// How far a boundary wanders east/west, metres.
const WOBBLE: f32 = 45.0;
/// Where trips start (x), and the rough ratio of eastward progress to road length.
const START_X: f32 = 64.0;
const PROGRESS: f32 = 0.86;

/// Per-biome weights at a point; they sum to 1.
pub type Weights = [f32; BIOMES];

#[derive(Clone, Debug)]
pub struct Biomes {
    /// Boundaries in x (increasing) and the biome that begins at each; `first` is west of all.
    first: Biome,
    bounds: Vec<(f32, Biome)>,
    wobble: u32,
}

impl Biomes {
    /// The biome plan for a trip. Segment lengths are drawn exactly as `Route::generate`
    /// draws them, so biome changes land near the gas stations.
    pub fn new(world_seed: u64, trip: TripLength) -> Self {
        let mut rng = Pcg32::new(sub_seed(world_seed, "route", 0, 0), 3);
        let segments = trip.stations() as usize;
        let mut ends = Vec::with_capacity(segments);
        let mut total = 0.0;
        for _ in 0..segments {
            total += rng.range_f32(650.0, 950.0);
            ends.push(total);
        }
        // The pine woods first and the mountain pass (the hardest) last; the bayou and the
        // canyon in between, in a seeded order. Short trips skip one of those two.
        let mut pick = Pcg32::new(sub_seed(world_seed, "biomes", 0, 0), 5);
        let (a, b) = if pick.chance(0.5) {
            (Biome::Swamp, Biome::Canyon)
        } else {
            (Biome::Canyon, Biome::Swamp)
        };
        let seq = [Biome::Forest, a, b, Biome::Alpine];
        let n = segments;
        let of = |i: usize| -> Biome {
            if n >= BIOMES {
                seq[(i * BIOMES / n).min(BIOMES - 1)]
            } else if i + 1 == n {
                Biome::Alpine
            } else {
                seq[i.min(BIOMES - 1)]
            }
        };
        let mut bounds = Vec::new();
        for i in 1..n {
            let b = of(i);
            if b != of(i - 1) {
                bounds.push((START_X + ends[i - 1] * PROGRESS, b));
            }
        }
        Self {
            first: Biome::Forest,
            bounds,
            wobble: sub_seed32(world_seed, "biomes.wobble"),
        }
    }

    /// Blend weights of every biome at a point.
    pub fn weights(&self, x: f32, z: f32) -> Weights {
        let mut w = [0.0; BIOMES];
        let x = x + WOBBLE * perlin(self.wobble, z * (1.0 / 350.0), x * (1.0 / 350.0));
        let mut current = self.first;
        let mut left = 1.0;
        for &(bx, next) in &self.bounds {
            let t = smoothstep(bx - BLEND, bx + BLEND, x);
            w[current as usize] += left * (1.0 - t);
            left *= t;
            current = next;
        }
        w[current as usize] += left;
        w
    }

    /// The biome with the most weight at a point.
    pub fn at(&self, x: f32, z: f32) -> Biome {
        dominant(&self.weights(x, z))
    }

    /// The biomes in the order the trip meets them.
    pub fn sequence(&self) -> Vec<Biome> {
        let mut out = vec![self.first];
        out.extend(self.bounds.iter().map(|b| b.1));
        out
    }
}

pub fn dominant(w: &Weights) -> Biome {
    let mut best = 0;
    for i in 1..BIOMES {
        if w[i] > w[best] {
            best = i;
        }
    }
    ALL[best]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn starts_in_the_woods_and_weights_sum_to_one() {
        for seed in 0..40u64 {
            for trip in [TripLength::Short, TripLength::Medium, TripLength::Long] {
                let b = Biomes::new(seed * 7919, trip);
                assert_eq!(b.at(64.0, 64.0), Biome::Forest);
                let seq = b.sequence();
                assert!(seq.len() >= 3, "{trip:?} {seq:?}");
                assert_eq!(seq.last(), Some(&Biome::Alpine), "the pass comes last");
                for x in (-500..12000).step_by(97) {
                    let w = b.weights(x as f32, 37.0);
                    let sum: f32 = w.iter().sum();
                    assert!((sum - 1.0).abs() < 1e-4 && w.iter().all(|&v| v >= 0.0));
                }
            }
        }
    }

    #[test]
    fn long_trips_see_every_biome() {
        let b = Biomes::new(12345, TripLength::Long);
        let seq = b.sequence();
        for biome in ALL {
            assert!(seq.contains(&biome), "{seq:?}");
        }
    }
}

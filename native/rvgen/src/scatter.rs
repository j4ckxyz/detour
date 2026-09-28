//! Prop scatter: trees, then rocks, stumps, logs and saplings around them. Positions are
//! deterministic because trees, rocks and stumps double as winch anchors (and collision)
//! that every client must agree on.

use crate::World;
use crate::chunk::{CHUNK_SIZE, Heightfield};
use crate::hash::sub_seed;
use crate::noise::smoothstep;
use crate::rng::Pcg32;
use crate::terrain::TREELINE_M;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct TreeInstance {
    /// Chunk-local position; `y` sits on the terrain.
    pub pos: [f32; 3],
    pub yaw: f32,
    pub scale: f32,
    pub kind: u8,
}

/// Number of tree models `kind` can pick from.
pub const TREE_KINDS: u8 = 3;

/// Jittered-grid cell size in metres.
const CELL: i32 = 8;
/// Steepest slope (rise over run) a tree will grow on.
const MAX_SLOPE: f32 = 0.7;

pub fn trees(world: &World, hf: &Heightfield) -> Vec<TreeInstance> {
    let coord = hf.coord;
    let (ox, oz) = coord.origin();
    let mut rng = Pcg32::new(
        sub_seed(
            world.world_seed(),
            "scatter.trees",
            coord.x as i64,
            coord.z as i64,
        ),
        1,
    );
    let cells = CHUNK_SIZE / CELL;
    let mut out = Vec::new();
    for cz in 0..cells {
        for cx in 0..cells {
            // Always draw the same number of values per cell so one rejection can't shift
            // the random stream for the rest of the chunk.
            let lx = (cx * CELL) as f32 + rng.range_f32(0.5, CELL as f32 - 0.5);
            let lz = (cz * CELL) as f32 + rng.range_f32(0.5, CELL as f32 - 0.5);
            let yaw = rng.range_f32(0.0, core::f32::consts::TAU);
            let scale = rng.range_f32(0.8, 1.35);
            let roll = rng.next_f32();
            let kind = rng.below(TREE_KINDS as u32) as u8;

            let density = world
                .terrain()
                .forest_density((ox as f32) + lx, (oz as f32) + lz);
            if roll >= density {
                continue;
            }
            let y = hf.sample_m(lx, lz);
            if y > TREELINE_M {
                continue;
            }
            let dx = hf.sample_m(lx + 1.0, lz) - hf.sample_m(lx - 1.0, lz);
            let dz = hf.sample_m(lx, lz + 1.0) - hf.sample_m(lx, lz - 1.0);
            let slope_sq = (dx * dx + dz * dz) * 0.25;
            if slope_sq > MAX_SLOPE * MAX_SLOPE {
                continue;
            }
            out.push(TreeInstance {
                pos: [lx, y, lz],
                yaw,
                scale,
                kind,
            });
        }
    }
    out
}

/// What a scattered prop is. The numeric values are part of the generator output.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum PropKind {
    /// A rock or boulder; `variant` picks the shape. Big ones are winch anchors.
    Rock = 0,
    /// A tree stump: a winch anchor.
    Stump = 1,
    /// A fallen log lying on the ground.
    Log = 2,
    /// A young pine. Visual only: the RV drives over it.
    Sapling = 3,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct PropInstance {
    /// Chunk-local position of the model's origin (its base).
    pub pos: [f32; 3],
    /// Unnormalised up vector: the prop leans towards the terrain normal. `up[1]` is 1.
    pub up: [f32; 3],
    pub yaw: f32,
    pub scale: f32,
    pub kind: PropKind,
    /// Shape variant, `0..=255`. The game maps it onto however many models it has.
    pub variant: u8,
}

/// Prop cell size in metres: at most one feature (a rock cluster, a log...) per cell.
const PROP_CELL: i32 = 16;
/// Most props in one feature (a rock cluster or a clump of saplings).
const MAX_MEMBERS: usize = 5;
/// Random draws per cell, fixed so rejections never shift the stream.
const DRAWS: usize = 6 + MAX_MEMBERS * 5;
/// Props stay this far inside the chunk so clusters never spill into a neighbour.
const EDGE: f32 = 0.5;

/// Rough footprint radius at scale 1, used to keep props off tree trunks and each other.
fn footprint(kind: PropKind) -> f32 {
    match kind {
        PropKind::Rock => 1.1,
        PropKind::Stump => 0.7,
        PropKind::Log => 1.5,
        PropKind::Sapling => 0.5,
    }
}

/// How far a kind leans towards the terrain normal (0 = upright, 1 = flush with the ground).
fn lean(kind: PropKind) -> f32 {
    match kind {
        PropKind::Rock => 0.6,
        PropKind::Stump => 0.25,
        PropKind::Log => 1.0,
        PropKind::Sapling => 0.1,
    }
}

struct Draws {
    v: [u32; DRAWS],
    i: usize,
}

impl Draws {
    fn new(rng: &mut Pcg32) -> Self {
        let mut v = [0u32; DRAWS];
        for x in &mut v {
            *x = rng.next_u32();
        }
        Self { v, i: 0 }
    }

    fn u32(&mut self) -> u32 {
        let x = self.v[self.i];
        self.i += 1;
        x
    }

    fn f32(&mut self) -> f32 {
        (self.u32() >> 8) as f32 * (1.0 / 16_777_216.0)
    }

    fn range(&mut self, lo: f32, hi: f32) -> f32 {
        lo + (hi - lo) * self.f32()
    }
}

/// Terrain gradient (rise over run) at a chunk-local position.
fn gradient(hf: &Heightfield, lx: f32, lz: f32) -> (f32, f32) {
    let dx = (hf.sample_m(lx + 1.0, lz) - hf.sample_m(lx - 1.0, lz)) * 0.5;
    let dz = (hf.sample_m(lx, lz + 1.0) - hf.sample_m(lx, lz - 1.0)) * 0.5;
    (dx, dz)
}

/// Blocks props from overlapping trees and each other, using a coarse grid of circles.
struct Occupancy {
    cells: Vec<Vec<(f32, f32, f32)>>,
}

impl Occupancy {
    const CELL: f32 = 8.0;
    const SIDE: usize = (CHUNK_SIZE / 8) as usize;

    fn new() -> Self {
        Self {
            cells: vec![Vec::new(); Self::SIDE * Self::SIDE],
        }
    }

    fn index(x: f32, z: f32) -> (i32, i32) {
        (
            (x / Self::CELL).floor() as i32,
            (z / Self::CELL).floor() as i32,
        )
    }

    fn free(&self, x: f32, z: f32, r: f32) -> bool {
        let (cx, cz) = Self::index(x, z);
        for dz in -1..=1 {
            for dx in -1..=1 {
                let (gx, gz) = (cx + dx, cz + dz);
                if gx < 0 || gz < 0 || gx >= Self::SIDE as i32 || gz >= Self::SIDE as i32 {
                    continue;
                }
                for &(ox, oz, or) in &self.cells[gz as usize * Self::SIDE + gx as usize] {
                    let (ddx, ddz) = (x - ox, z - oz);
                    let min = r + or;
                    if ddx * ddx + ddz * ddz < min * min {
                        return false;
                    }
                }
            }
        }
        true
    }

    fn add(&mut self, x: f32, z: f32, r: f32) {
        let (cx, cz) = Self::index(x, z);
        let side = Self::SIDE as i32;
        let (cx, cz) = (cx.clamp(0, side - 1), cz.clamp(0, side - 1));
        self.cells[cz as usize * Self::SIDE + cx as usize].push((x, z, r));
    }
}

/// Rocks, stumps, logs and saplings for one chunk. `trees` must be `trees(world, hf)`: props
/// are kept clear of their trunks.
pub fn props(world: &World, hf: &Heightfield, trees: &[TreeInstance]) -> Vec<PropInstance> {
    let coord = hf.coord;
    let (ox, oz) = coord.origin();
    let terrain = world.terrain();
    let mut rng = Pcg32::new(
        sub_seed(
            world.world_seed(),
            "scatter.props",
            coord.x as i64,
            coord.z as i64,
        ),
        2,
    );
    let mut occupied = Occupancy::new();
    for t in trees {
        occupied.add(t.pos[0], t.pos[2], 0.6 * t.scale);
    }

    let cells = CHUNK_SIZE / PROP_CELL;
    let max = CHUNK_SIZE as f32 - EDGE;
    let mut out = Vec::new();
    for cz in 0..cells {
        for cx in 0..cells {
            let mut d = Draws::new(&mut rng);
            let lx = (cx * PROP_CELL) as f32 + d.range(1.0, PROP_CELL as f32 - 1.0);
            let lz = (cz * PROP_CELL) as f32 + d.range(1.0, PROP_CELL as f32 - 1.0);
            let roll = d.f32();
            let pick = d.f32();
            let big = d.f32();
            let count_roll = d.u32();

            let (wx, wz) = ((ox as f32) + lx, (oz as f32) + lz);
            let y = hf.sample_m(lx, lz);
            let (gx, gz) = gradient(hf, lx, lz);
            let slope = (gx * gx + gz * gz).sqrt();
            let forest = terrain.forest_density(wx, wz) * (1.0 / 0.75);
            let alpine = smoothstep(TREELINE_M - 40.0, TREELINE_M + 20.0, y);
            let p_rocks = (0.05
                + 0.30 * terrain.rockiness(wx, wz)
                + 0.35 * smoothstep(0.3, 0.9, slope)
                + 0.25 * alpine)
                .min(0.85);
            let p_debris = 0.45 * forest * (1.0 - alpine);
            let p_lone = 0.10;

            // (kind, members, first scale range, others' scale range, spread in metres)
            let (kind, members, first, rest, spread) = if roll < p_rocks {
                let n = 2 + (count_roll % 4) as usize;
                let first = if big < 0.12 { (2.4, 3.8) } else { (1.0, 2.0) };
                (PropKind::Rock, n, first, (0.35, 0.9), 2.5)
            } else if roll < p_rocks + p_debris {
                if pick < 0.40 {
                    (PropKind::Stump, 1, (0.8, 1.3), (0.8, 1.3), 0.0)
                } else if pick < 0.70 {
                    (PropKind::Log, 1, (1.3, 2.2), (1.3, 2.2), 0.0)
                } else {
                    let n = 1 + (count_roll % 4) as usize;
                    (PropKind::Sapling, n, (0.6, 1.1), (0.4, 0.9), 2.5)
                }
            } else if roll < p_rocks + p_debris + p_lone {
                if pick < 0.6 {
                    (PropKind::Rock, 1, (0.5, 1.2), (0.5, 1.2), 0.0)
                } else {
                    (PropKind::Sapling, 1, (0.5, 1.0), (0.5, 1.0), 0.0)
                }
            } else {
                (PropKind::Rock, 0, (1.0, 1.0), (1.0, 1.0), 0.0)
            };

            for m in 0..MAX_MEMBERS {
                // Always draw this member's values, used or not.
                let angle = d.f32();
                let dist = d.range(0.35, 1.0);
                let scale_t = d.f32();
                let yaw = d.range(0.0, core::f32::consts::TAU);
                let variant = (d.u32() >> 24) as u8;
                if m >= members {
                    continue;
                }
                let (lo, hi) = if m == 0 { first } else { rest };
                let scale = lo + (hi - lo) * scale_t;
                let (px, pz) = if m == 0 {
                    (lx, lz)
                } else {
                    // Integer-free angle: walk the unit square's perimeter, then normalise.
                    let (ux, uz) = square_dir(angle);
                    let r = spread * first.1.min(2.0) * dist;
                    (lx + ux * r, lz + uz * r)
                };
                let radius = footprint(kind) * scale;
                if px < EDGE || pz < EDGE || px > max || pz > max {
                    continue;
                }
                if !occupied.free(px, pz, radius) {
                    continue;
                }
                let (gx, gz) = gradient(hf, px, pz);
                // Sit on the lowest point under the footprint so nothing floats on a slope.
                let r = radius * 0.6;
                let mut base = hf.sample_m(px, pz);
                for (sx, sz) in [(r, 0.0), (-r, 0.0), (0.0, r), (0.0, -r)] {
                    base = base.min(hf.sample_m(px + sx, pz + sz));
                }
                let k = lean(kind);
                let (wobble_x, wobble_z) = if kind == PropKind::Rock {
                    let (ux, uz) = square_dir(scale_t);
                    (0.15 * ux, 0.15 * uz)
                } else {
                    (0.0, 0.0)
                };
                occupied.add(px, pz, radius);
                out.push(PropInstance {
                    pos: [px, base, pz],
                    up: [-gx * k + wobble_x, 1.0, -gz * k + wobble_z],
                    yaw,
                    scale,
                    kind,
                    variant,
                });
            }
        }
    }
    out
}

/// A unit direction from `t` in `[0, 1)` without trig: walk the unit square's perimeter and
/// normalise. Not uniform in angle, which is fine for scatter.
fn square_dir(t: f32) -> (f32, f32) {
    let s = t * 8.0;
    let (x, z) = if s < 2.0 {
        (s - 1.0, -1.0)
    } else if s < 4.0 {
        (1.0, s - 3.0)
    } else if s < 6.0 {
        (5.0 - s, 1.0)
    } else {
        (-1.0, 7.0 - s)
    };
    let len = (x * x + z * z).sqrt();
    (x / len, z / len)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{ChunkCoord, SeedCode, TripLength};

    #[test]
    fn props_deterministic_in_bounds_and_varied() {
        let w = World::new(SeedCode::new(TripLength::Short, 99)).unwrap();
        let mut counts = [0usize; 4];
        for cz in -3..3 {
            for cx in -3..3 {
                let hf = w.heightfield(ChunkCoord::new(cx, cz));
                let trees = trees(&w, &hf);
                let a = props(&w, &hf, &trees);
                assert_eq!(a, props(&w, &hf, &trees));
                for p in &a {
                    assert!((EDGE..=128.0 - EDGE).contains(&p.pos[0]));
                    assert!((EDGE..=128.0 - EDGE).contains(&p.pos[2]));
                    assert!(
                        p.pos[1] <= hf.sample_m(p.pos[0], p.pos[2]) + 1e-4,
                        "prop floats"
                    );
                    assert!(p.scale > 0.3 && p.scale < 4.0);
                    for t in &trees {
                        let (dx, dz) = (p.pos[0] - t.pos[0], p.pos[2] - t.pos[2]);
                        assert!(dx * dx + dz * dz > 0.25, "prop inside a trunk");
                    }
                    counts[p.kind as usize] += 1;
                }
            }
        }
        // 36 chunks × 64 cells: every kind shows up, but the ground isn't carpeted.
        let total: usize = counts.iter().sum();
        assert!(counts.iter().all(|&c| c > 10), "{counts:?}");
        assert!(total > 400 && total < 36 * 64 * 3, "{total} props");
    }

    #[test]
    fn square_dir_is_unit() {
        for i in 0..64 {
            let (x, z) = square_dir(i as f32 / 64.0);
            assert!(((x * x + z * z) - 1.0).abs() < 1e-5);
        }
    }

    #[test]
    fn deterministic_and_in_bounds() {
        let w = World::new(SeedCode::new(TripLength::Short, 99)).unwrap();
        let mut total = 0;
        for cz in -2..2 {
            for cx in -2..2 {
                let hf = w.heightfield(ChunkCoord::new(cx, cz));
                let a = trees(&w, &hf);
                assert_eq!(a, trees(&w, &hf));
                for t in &a {
                    assert!((0.0..=128.0).contains(&t.pos[0]));
                    assert!((0.0..=128.0).contains(&t.pos[2]));
                }
                total += a.len();
            }
        }
        // 16 chunks × 256 cells; expect a real forest but not a solid wall.
        assert!(total > 200 && total < 16 * 256, "{total} trees");
    }
}

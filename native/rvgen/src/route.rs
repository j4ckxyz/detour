//! The trip (PLAN.md §5.1–5.4): a meandering road from the start camp to home, split into
//! segments that end at gas stations, with obstacles along it that get harder towards home.
//!
//! Everything is a pure function of the seed. The road is carved into the terrain (cut and
//! fill to a grade limit), obstacles stamp their own shapes into it (a washed-out gap, a ledge,
//! a steep climb, a mud hole), and flat pads are levelled for the camp, stations and home.
//! The road runs along a valley: past its floor, steep walls rise either side (and close it
//! off behind the camp and past home), so the road is the only way to go.
//! `Route::validate` checks the static solvability rules.

use std::collections::BTreeMap;

use crate::biome::Biome;
use crate::hash::{sub_seed, sub_seed32};
use crate::noise::{perlin, smoothstep};
use crate::rng::Pcg32;
use crate::seed::TripLength;
use crate::terrain::TerrainGen;

/// Half the driveable width of the road, metres.
pub const ROAD_HALF_WIDTH: f32 = 3.2;
/// Width of the cut/fill blend beyond the road edge.
pub const SHOULDER: f32 = 9.0;
/// No trees or props within this distance of the centreline.
pub const CLEAR: f32 = ROAD_HALF_WIDTH + 3.5;
/// Beyond the clearing, trees crowd the road so it reads as a forest track (and going round
/// an obstacle is hard).
pub const TREE_WALL: f32 = 16.0;
/// Spacing of route samples along the road.
pub const SAMPLE: f32 = 2.0;
/// Steepest ordinary road grade (obstacles break it on purpose).
pub const MAX_GRADE: f32 = 0.09;
/// Where every trip starts (world x, z).
pub const START: [f32; 2] = [64.0, 64.0];
/// Length of a plank (the game's plank model must match), metres.
pub const PLANK_LENGTH: f32 = 5.0;

const STEP: f32 = 20.0;
const GRID: f32 = 32.0;
const REACH: f32 = ROAD_HALF_WIDTH + SHOULDER + 2.0;
/// Pads: the camp, stations and home. Half-size along and across the road.
const PAD_HALF: [f32; 2] = [16.0, 11.0];
const PAD_BLEND: f32 = 10.0;
/// A ford's river runs this far either side of the road (metres); its banks are this wide.
pub const RIVER_HALF: f32 = 60.0;
const RIVER_FADE: f32 = 18.0;
const RIVER_BANK: f32 = 6.0;
/// Deepest ford the RV can drive through (metres of water at the road).
pub const MAX_FORD_DEPTH: f32 = 0.8;
/// A frozen pond's ramps in and out are this long.
const ICE_RAMP: f32 = 11.0;
/// Width of the grassy bank ring round a lake.
const LAKE_BANK: f32 = 10.0;
/// A cave's levelled clearing (radius) and the blend round it.
pub const CAVE_RADIUS: f32 = 9.0;
const CAVE_BLEND: f32 = 8.0;
/// The valley: its floor reaches at least this far either side of the road (metres), up to
/// `WALL_VARY` more, then a wall rises over `WALL_BAND` metres.
pub const WALL_START: f32 = 40.0;
const WALL_VARY: f32 = 14.0;
pub const WALL_BAND: f32 = 12.0;
/// How far a wall rises above the ground it stands on (plus up to `WALL_HEIGHT_VARY`): too
/// steep to drive or climb.
pub const WALL_HEIGHT: f32 = 24.0;
const WALL_HEIGHT_VARY: f32 = 12.0;
/// Past the wall's top, a crest this wide, then the ground eases back down to its natural
/// height over `WALL_FADE[1] - WALL_FADE[0]` metres.
const WALL_FADE: [f32; 2] = [40.0, 100.0];
/// Furthest from the road the valley changes anything.
const WALL_REACH: f32 = WALL_START + WALL_VARY + WALL_WOBBLE + WALL_BAND + WALL_FADE[1] + 1.0;
/// How far the foot of a wall wanders in and out, and how craggy its top is (metres).
const WALL_WOBBLE: f32 = 4.0;
const WALL_CRAGS: f32 = 9.0;
/// A gap's gully and a ledge's raised ground reach this far either side, into the walls.
const SIDE_REACH: f32 = WALL_START + WALL_VARY + WALL_WOBBLE + WALL_BAND;
/// Road samples per segment of the coarse centreline the walls follow.
const WALL_STRIDE: usize = 4;
/// A side lake or cave opens the valley out to this far past its edge.
const BAY: f32 = 8.0;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum ObstacleKind {
    /// A washed-out bridge: a deep trench across the road whose clear span (between the
    /// abutments the game builds at `±length/2`) is bridged with planks.
    Gap = 0,
    /// A step up the RV can't climb: winch up it (an anchor waits at the top).
    Ledge = 1,
    /// A soft, slippery stretch: momentum, planks or the winch.
    Mud = 2,
    /// A short, very steep climb: low gear and momentum, or the winch.
    Climb = 3,
    /// A river across the road, shallow enough to drive through (slowly), too deep to go round.
    Ford = 4,
    /// A frozen pond in a hollow: slippery ice, and an icy climb out (planks or the winch).
    Ice = 5,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum PadKind {
    Camp = 0,
    Station = 1,
    Home = 2,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Obstacle {
    pub kind: ObstacleKind,
    /// Arc length of its centre along the road.
    pub s: f32,
    /// Centre on the road (x, road height before the stamp, z) and the road direction (x, z).
    pub pos: [f32; 3],
    pub dir: [f32; 2],
    /// Extent along the road (gap width, mud length, climb length, ledge face).
    pub length: f32,
    /// Gap depth, ledge rise, climb height or mud dip, metres.
    pub size: f32,
    /// 0 (first) .. 1 (last): how far into the trip it is.
    pub difficulty: f32,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Pad {
    pub kind: PadKind,
    pub s: f32,
    /// Centre (x, height, z), the road direction at it, and which side of the road (+1 right).
    pub pos: [f32; 3],
    pub dir: [f32; 2],
    pub side: f32,
}

/// Something the game must put near an obstacle for it to be solvable.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Supply {
    pub kind: SupplyKind,
    pub pos: [f32; 3],
    pub yaw_dir: [f32; 2],
    pub count: u8,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum SupplyKind {
    /// A pile of planks (items, spawned by the game).
    Planks = 0,
    /// A boulder to winch from (a scattered prop, see `scatter::props`).
    Anchor = 1,
}

/// A pond or lake beside the road (frozen in the mountains).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Lake {
    /// Centre (x, water level, z).
    pub pos: [f32; 3],
    pub radius: f32,
    pub frozen: bool,
}

/// A cave in a clearing off the road, with supplies inside (the game builds it).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Cave {
    /// Clearing centre (x, ground height, z) and the direction the mouth faces (x, z).
    pub pos: [f32; 3],
    pub dir: [f32; 2],
    pub biome: Biome,
}

#[derive(Clone, Debug)]
pub struct Route {
    /// Road centreline samples every `SAMPLE` metres: (x, z).
    pub xz: Vec<[f32; 2]>,
    /// Road surface height at each sample, before obstacle stamps.
    pub h: Vec<f32>,
    pub obstacles: Vec<Obstacle>,
    /// The camp, one pad per station, and home, in order along the road.
    pub pads: Vec<Pad>,
    pub supplies: Vec<Supply>,
    pub lakes: Vec<Lake>,
    pub caves: Vec<Cave>,
    pub length: f32,
    /// Samples near each grid cell (cells of `GRID` metres, keyed by cell).
    grid: BTreeMap<(i32, i32), Vec<u32>>,
    bounds: [f32; 4],
    /// Coarse centreline segments (start sample indices) within `WALL_REACH` of each cell.
    wall_grid: BTreeMap<(i32, i32), Vec<u32>>,
    wall_bounds: [f32; 4],
    wall_seed: u32,
}

/// Where a point is relative to the road.
#[derive(Clone, Copy, Debug)]
pub struct RoadPoint {
    /// Distance from the centreline (metres, always >= 0).
    pub distance: f32,
    /// Signed sideways offset (+ = right of the direction of travel).
    pub lateral: f32,
    /// Arc length of the closest point.
    pub s: f32,
    /// Road height there (before obstacle stamps).
    pub height: f32,
}

impl Route {
    pub fn generate(world_seed: u64, trip: TripLength, terrain: &TerrainGen) -> Self {
        let mut rng = Pcg32::new(sub_seed(world_seed, "route", 0, 0), 3);
        let segments = trip.stations() as usize;
        let mut ends = Vec::with_capacity(segments);
        let mut total = 0.0;
        for _ in 0..segments {
            total += rng.range_f32(650.0, 950.0);
            ends.push(total);
        }

        // 1. A coarse walk east that prefers level ground, then a smooth resampled curve.
        let mut coarse = vec![START];
        let mut heading: f32 = 0.0;
        let steps = (total / STEP) as usize + 4;
        for _ in 0..steps {
            let [x, z] = *coarse.last().unwrap();
            let h0 = terrain.height_m(x, z);
            let mut best = (f32::INFINITY, heading);
            for k in 0..5 {
                let cand = heading + (k as f32 - 2.0) * 0.14 + rng.range_f32(-0.05, 0.05);
                let cand = cand.clamp(-0.85, 0.85); // Keep heading home (east): never loops.
                let (dx, dz) = dir_of(cand);
                let h1 = terrain.height_m(x + dx * STEP, z + dz * STEP);
                let cost = (h1 - h0).abs() + (cand - heading).abs() * 3.0 + cand.abs() * 0.8;
                if cost < best.0 {
                    best = (cost, cand);
                }
            }
            heading = best.1;
            let (dx, dz) = dir_of(heading);
            coarse.push([x + dx * STEP, z + dz * STEP]);
        }
        let xz = resample(&catmull_rom(&coarse, 8), SAMPLE, total + 40.0);

        // 2. Road profile: smoothed terrain, then clamped to the grade limit (cut and fill).
        let natural: Vec<f32> = xz.iter().map(|p| terrain.height_m(p[0], p[1])).collect();
        let mut h = moving_average(&natural, 20);
        limit_grade(&mut h, MAX_GRADE * SAMPLE);

        let mut route = Route {
            length: (xz.len() - 1) as f32 * SAMPLE,
            xz,
            h,
            obstacles: Vec::new(),
            pads: Vec::new(),
            supplies: Vec::new(),
            lakes: Vec::new(),
            caves: Vec::new(),
            grid: BTreeMap::new(),
            bounds: [0.0; 4],
            wall_grid: BTreeMap::new(),
            wall_bounds: [0.0; 4],
            wall_seed: sub_seed32(world_seed, "route.walls"),
        };

        // 3. Pads: the camp at the start, a station at each segment end, home at the end.
        route.pads.push(route.pad(PadKind::Camp, 30.0, 1.0));
        for (i, &e) in ends.iter().enumerate() {
            let kind = if i + 1 == ends.len() {
                PadKind::Home
            } else {
                PadKind::Station
            };
            let side = if rng.chance(0.5) { 1.0 } else { -1.0 };
            route
                .pads
                .push(route.pad(kind, e.min(route.length - 20.0), side));
        }

        // 4. Obstacles between the pads, harder towards home, with a breather now and then.
        let mut s = 200.0;
        let mut since_breather = 0;
        while s < route.length - 120.0 {
            let near_pad = route.pads.iter().any(|p| (p.s - s).abs() < 90.0);
            if !near_pad {
                if since_breather >= 3 && rng.chance(0.5) {
                    since_breather = 0; // A quiet stretch of road.
                } else {
                    let t = s / route.length;
                    let p = route.xz[route.index_at(s)];
                    let biome = terrain.biomes().at(p[0], p[1]);
                    route.place_obstacle(&mut rng, terrain, s, t, biome);
                    since_breather += 1;
                }
            }
            s += rng.range_f32(150.0, 240.0);
        }

        route.build_grid();
        route.build_wall_grid();
        route.place_lakes(world_seed, terrain);
        route.place_caves(world_seed, terrain);
        route
    }

    /// Ponds in the bayou and frozen lakes in the mountains, off to the sides of the road.
    fn place_lakes(&mut self, world_seed: u64, terrain: &TerrainGen) {
        let mut rng = Pcg32::new(sub_seed(world_seed, "route.lakes", 0, 0), 7);
        let mut s = 120.0;
        while s < self.length - 60.0 {
            let (chance, side_roll, radius, offset) = (
                rng.next_f32(),
                rng.next_f32(),
                rng.range_f32(12.0, 30.0),
                rng.range_f32(8.0, 28.0),
            );
            s += rng.range_f32(110.0, 190.0);
            let i = self.index_at(s);
            let p = self.xz[i];
            let biome = terrain.biomes().at(p[0], p[1]);
            let frozen = biome == Biome::Alpine;
            if !(biome == Biome::Swamp || frozen) || chance > 0.55 {
                continue;
            }
            let side = if side_roll < 0.5 { 1.0 } else { -1.0 };
            let d = self.dir(i);
            let n = [-d[1] * side, d[0] * side];
            let off = radius + LAKE_BANK + REACH + offset;
            let c = [p[0] + n[0] * off, p[1] + n[1] * off];
            if self.min_road_distance(c[0], c[1], s, radius + 120.0)
                < radius + LAKE_BANK + REACH + 2.0
            {
                continue;
            }
            let clear = |q: [f32; 3], r: f32| dist2(q, [c[0], 0.0, c[1]]) > r * r;
            if !self.pads.iter().all(|pad| clear(pad.pos, radius + 45.0))
                || !self
                    .obstacles
                    .iter()
                    .all(|o| clear(o.pos, radius + RIVER_HALF + 10.0))
                || !self
                    .lakes
                    .iter()
                    .all(|l| clear(l.pos, radius + l.radius + 2.0 * LAKE_BANK))
            {
                continue;
            }
            let level = terrain.height_m(c[0], c[1]) - 0.4;
            self.lakes.push(Lake {
                pos: [c[0], level, c[1]],
                radius,
                frozen,
            });
        }
    }

    /// One cave per stretch of road in the woods or the canyon, in a clearing off to a side.
    fn place_caves(&mut self, world_seed: u64, terrain: &TerrainGen) {
        let mut rng = Pcg32::new(sub_seed(world_seed, "route.caves", 0, 0), 9);
        for k in 0..self.pads.len().saturating_sub(1) {
            let (a, b) = (self.pads[k].s, self.pads[k + 1].s);
            let (t, side_roll, offset) = (
                rng.range_f32(0.3, 0.7),
                rng.next_f32(),
                rng.range_f32(4.0, 14.0),
            );
            let s = a + (b - a) * t;
            let i = self.index_at(s);
            let p = self.xz[i];
            let biome = terrain.biomes().at(p[0], p[1]);
            if !(biome == Biome::Forest || biome == Biome::Canyon) {
                continue;
            }
            let side = if side_roll < 0.5 { 1.0 } else { -1.0 };
            let d = self.dir(i);
            let n = [-d[1] * side, d[0] * side];
            let off = CAVE_RADIUS + CAVE_BLEND + REACH + offset;
            let c = [p[0] + n[0] * off, p[1] + n[1] * off];
            if self.min_road_distance(c[0], c[1], s, 150.0) < CAVE_RADIUS + CAVE_BLEND + REACH {
                continue;
            }
            let clear = |q: [f32; 3], r: f32| dist2(q, [c[0], 0.0, c[1]]) > r * r;
            if !self.pads.iter().all(|pad| clear(pad.pos, 60.0))
                || !self
                    .obstacles
                    .iter()
                    .all(|o| clear(o.pos, RIVER_HALF + 25.0))
                || !self
                    .lakes
                    .iter()
                    .all(|l| clear(l.pos, l.radius + LAKE_BANK + 30.0))
            {
                continue;
            }
            // The mouth faces the road.
            self.caves.push(Cave {
                pos: [c[0], terrain.height_m(c[0], c[1]), c[1]],
                dir: [-n[0], -n[1]],
                biome,
            });
        }
    }

    /// Distance from a point to the road, looking `window` metres either side of arc length `s`.
    fn min_road_distance(&self, x: f32, z: f32, s: f32, window: f32) -> f32 {
        let i0 = self.index_at((s - window).max(0.0));
        let i1 = self.index_at(s + window);
        let mut best = f32::INFINITY;
        for p in &self.xz[i0..=i1] {
            best = best.min((p[0] - x) * (p[0] - x) + (p[1] - z) * (p[1] - z));
        }
        best.sqrt()
    }

    fn pad(&self, kind: PadKind, s: f32, side: f32) -> Pad {
        let i = self.index_at(s);
        let (p, d) = (self.xz[i], self.dir(i));
        let offset = if kind == PadKind::Camp {
            0.0
        } else {
            ROAD_HALF_WIDTH + PAD_HALF[1]
        };
        let n = [-d[1] * side, d[0] * side]; // Right-hand normal (x, z) times side.
        let c = [p[0] + n[0] * offset, p[1] + n[1] * offset];
        Pad {
            kind,
            s,
            pos: [c[0], self.h[i], c[1]],
            dir: d,
            side,
        }
    }

    /// Somewhere off the road at arc length `s`, `off` metres to the side, for supplies to lie
    /// (a coin flip `roll` picks the side). Takes the side nearer the road's height, so it can
    /// be walked to; if both are far above or below, it falls back to the verge.
    fn stash_spot(&self, terrain: &TerrainGen, s: f32, off: f32, roll: f32) -> [f32; 3] {
        let j = self.index_at(s.max(0.0));
        let (p, d) = (self.xz[j], self.dir(j));
        let first = if roll < 0.5 { 1.0 } else { -1.0 };
        let mut best: Option<(f32, [f32; 3])> = None;
        for side in [first, -first] {
            let n = [-d[1] * side, d[0] * side];
            let q = [p[0] + n[0] * off, p[1] + n[1] * off];
            let rise = (terrain.height_m(q[0], q[1]) - self.h[j]).abs();
            if best.is_none_or(|(b, _)| rise < b - 0.5) {
                best = Some((rise, [q[0], self.h[j], q[1]]));
            }
        }
        match best {
            Some((rise, q)) if rise < 2.5 => q,
            _ => {
                let n = [-d[1] * first, d[0] * first];
                let o = ROAD_HALF_WIDTH + 1.5;
                [p[0] + n[0] * o, self.h[j], p[1] + n[1] * o]
            }
        }
    }

    fn place_obstacle(
        &mut self,
        rng: &mut Pcg32,
        terrain: &TerrainGen,
        s: f32,
        t: f32,
        biome: Biome,
    ) {
        // Always draw the same values, whichever kind wins.
        let pick = rng.next_f32();
        let a = rng.next_f32();
        let b = rng.next_f32();
        // By biome, then weighted by how far into the trip it is: gentle mud and climbs
        // early, then gaps and ledges, which need tools (planks, the winch).
        let kind = match biome {
            Biome::Swamp => Some(if pick < 0.4 {
                ObstacleKind::Mud
            } else if pick < 0.72 {
                ObstacleKind::Ford
            } else if pick < 0.9 {
                ObstacleKind::Gap
            } else {
                ObstacleKind::Climb
            }),
            Biome::Canyon => Some(if pick < 0.35 {
                ObstacleKind::Ledge
            } else if pick < 0.6 {
                ObstacleKind::Climb
            } else if pick < 0.85 {
                ObstacleKind::Gap
            } else {
                ObstacleKind::Ford
            }),
            Biome::Alpine => Some(if pick < 0.42 {
                ObstacleKind::Ice
            } else if pick < 0.65 {
                ObstacleKind::Climb
            } else if pick < 0.85 {
                ObstacleKind::Ledge
            } else {
                ObstacleKind::Gap
            }),
            Biome::Forest => None,
        };
        let kind = if let Some(k) = kind {
            k
        } else if t < 0.25 {
            if pick < 0.6 {
                ObstacleKind::Mud
            } else {
                ObstacleKind::Climb
            }
        } else if t < 0.65 {
            if pick < 0.4 {
                ObstacleKind::Gap
            } else if pick < 0.75 {
                ObstacleKind::Ledge
            } else {
                ObstacleKind::Mud
            }
        } else if pick < 0.3 {
            ObstacleKind::Gap
        } else if pick < 0.65 {
            ObstacleKind::Ledge
        } else if pick < 0.85 {
            ObstacleKind::Climb
        } else {
            ObstacleKind::Mud
        };
        let (length, size) = match kind {
            ObstacleKind::Gap => (3.8 + 0.6 * t, 1.9 + 0.7 * a),
            ObstacleKind::Ledge => (1.0, 1.1 + 0.5 * t + 0.1 * a),
            ObstacleKind::Mud => (14.0 + 10.0 * t + 6.0 * a, 0.25),
            ObstacleKind::Climb => (70.0, 5.0 + 3.0 * t + 1.0 * b),
            // Channel width at the road, and the water's depth there.
            ObstacleKind::Ford => (8.0 + 4.0 * a, (0.45 + 0.3 * t).min(MAX_FORD_DEPTH - 0.05)),
            // The pond's radius, and how far below the road its ice lies.
            ObstacleKind::Ice => (14.0 + 4.0 * a, 1.4 + 0.6 * t),
        };
        let i = self.index_at(s);
        let d = self.dir(i);
        let obstacle = Obstacle {
            kind,
            s,
            pos: [self.xz[i][0], self.h[i], self.xz[i][1]],
            dir: d,
            length,
            size,
            difficulty: t,
        };
        match kind {
            ObstacleKind::Gap => {
                // What's left of the bridge: its planks, dumped off in the trees somewhere
                // before the gap.
                let back = rng.range_f32(12.0, 40.0);
                let off = rng.range_f32(8.0, 16.0);
                let p = self.stash_spot(terrain, s - back, off, a);
                self.supplies.push(Supply {
                    kind: SupplyKind::Planks,
                    pos: p,
                    yaw_dir: self.dir(self.index_at((s - back).max(0.0))),
                    count: 4,
                });
            }
            ObstacleKind::Ledge => {
                // The road beyond the face is raised: it rejoins the natural profile over a
                // long gentle ramp. A boulder sits on the plateau as a winch anchor.
                let rise = size;
                let i0 = self.index_at(s + length * 0.5);
                let ramp = (rise / (MAX_GRADE * 0.8 * SAMPLE)) as usize;
                let plateau = 12;
                for k in 0..(plateau + ramp) {
                    let idx = i0 + k;
                    if idx >= self.h.len() {
                        break;
                    }
                    let f = if k < plateau {
                        1.0
                    } else {
                        1.0 - (k - plateau) as f32 / ramp as f32
                    };
                    self.h[idx] += rise * f;
                }
                let side = if b < 0.5 { 1.0 } else { -1.0 };
                let j = self.index_at(s + 10.0 + 8.0 * a);
                let n = [-self.dir(j)[1] * side, self.dir(j)[0] * side];
                let off = ROAD_HALF_WIDTH + 2.5;
                let p = [
                    self.xz[j][0] + n[0] * off,
                    self.h[j],
                    self.xz[j][1] + n[1] * off,
                ];
                self.supplies.push(Supply {
                    kind: SupplyKind::Anchor,
                    pos: p,
                    yaw_dir: self.dir(j),
                    count: 1,
                });
            }
            ObstacleKind::Climb => {
                // A hump whose steepest part is ~25-30 %.
                let i0 = self.index_at(s - length * 0.5);
                let n = (length / SAMPLE) as usize;
                for k in 0..=n {
                    let idx = i0 + k;
                    if idx >= self.h.len() {
                        break;
                    }
                    let u = k as f32 / n as f32;
                    // Smooth bump (3u² − 2u³ up then down) — no trig, for determinism.
                    let w = if u < 0.5 {
                        smoothstep(0.0, 0.5, u)
                    } else {
                        smoothstep(1.0, 0.5, u)
                    };
                    self.h[idx] += size * w;
                }
            }
            ObstacleKind::Ice => {
                // Planks somewhere in the trees before (for grip on the ice), a boulder beyond
                // (to winch out).
                let side = if a < 0.5 { 1.0 } else { -1.0 };
                let back = length + ICE_RAMP + rng.range_f32(8.0, 16.0);
                let off = rng.range_f32(8.0, 14.0);
                let p = self.stash_spot(terrain, s - back, off, a);
                self.supplies.push(Supply {
                    kind: SupplyKind::Planks,
                    pos: p,
                    yaw_dir: self.dir(self.index_at((s - back).max(0.0))),
                    count: 4,
                });
                let k = self.index_at(s + length + ICE_RAMP + 8.0 + 6.0 * b);
                let n = [-self.dir(k)[1] * -side, self.dir(k)[0] * -side];
                let off = ROAD_HALF_WIDTH + 2.5;
                self.supplies.push(Supply {
                    kind: SupplyKind::Anchor,
                    pos: [
                        self.xz[k][0] + n[0] * off,
                        self.h[k],
                        self.xz[k][1] + n[1] * off,
                    ],
                    yaw_dir: self.dir(k),
                    count: 1,
                });
            }
            ObstacleKind::Mud | ObstacleKind::Ford => {}
        }
        self.obstacles.push(obstacle);
    }

    fn build_grid(&mut self) {
        let mut lo = [f32::INFINITY; 2];
        let mut hi = [f32::NEG_INFINITY; 2];
        for (i, p) in self.xz.iter().enumerate() {
            lo = [lo[0].min(p[0]), lo[1].min(p[1])];
            hi = [hi[0].max(p[0]), hi[1].max(p[1])];
            let c0 = cell_of(p[0] - REACH, p[1] - REACH);
            let c1 = cell_of(p[0] + REACH, p[1] + REACH);
            for cz in c0.1..=c1.1 {
                for cx in c0.0..=c1.0 {
                    self.grid.entry((cx, cz)).or_default().push(i as u32);
                }
            }
        }
        let m = PAD_HALF[0] + PAD_BLEND + ROAD_HALF_WIDTH + PAD_HALF[1] * 2.0 + 30.0;
        self.bounds = [lo[0] - m, lo[1] - m, hi[0] + m, hi[1] + m];
    }

    pub fn index_at(&self, s: f32) -> usize {
        ((s / SAMPLE).round() as usize).min(self.xz.len() - 1)
    }

    /// Unit direction of travel (x, z) at sample `i`.
    pub fn dir(&self, i: usize) -> [f32; 2] {
        let a = self.xz[i.saturating_sub(1)];
        let b = self.xz[(i + 1).min(self.xz.len() - 1)];
        let (dx, dz) = (b[0] - a[0], b[1] - a[1]);
        let len = (dx * dx + dz * dz).sqrt().max(1e-6);
        [dx / len, dz / len]
    }

    /// The road near a point, if within reach of the centreline (road + shoulder).
    pub fn near(&self, x: f32, z: f32) -> Option<RoadPoint> {
        let list = self.grid.get(&cell_of(x, z))?;
        let mut best: Option<(f32, u32)> = None;
        for &i in list {
            let p = self.xz[i as usize];
            let d2 = (p[0] - x) * (p[0] - x) + (p[1] - z) * (p[1] - z);
            if best.is_none_or(|(b, _)| d2 < b) {
                best = Some((d2, i));
            }
        }
        let (_, i) = best?;
        let i = i as usize;
        // Project onto whichever neighbouring segment is closer.
        let mut out: Option<RoadPoint> = None;
        for (a, b) in [
            (i.saturating_sub(1), i),
            (i, (i + 1).min(self.xz.len() - 1)),
        ] {
            if a == b {
                continue;
            }
            let (pa, pb) = (self.xz[a], self.xz[b]);
            let (ex, ez) = (pb[0] - pa[0], pb[1] - pa[1]);
            let len2 = ex * ex + ez * ez;
            let t = (((x - pa[0]) * ex + (z - pa[1]) * ez) / len2).clamp(0.0, 1.0);
            let (cx, cz) = (pa[0] + ex * t, pa[1] + ez * t);
            let (ox, oz) = (x - cx, z - cz);
            let dist = (ox * ox + oz * oz).sqrt();
            // Right of travel: cross((ex, ez), (ox, oz)) < 0 in x-right, z-down (Godot) axes.
            let lateral = if ex * oz - ez * ox > 0.0 { dist } else { -dist };
            let rp = RoadPoint {
                distance: dist,
                lateral,
                s: (a as f32 + t) * SAMPLE,
                height: self.h[a] + (self.h[b] - self.h[a]) * t,
            };
            if out.is_none_or(|o| rp.distance < o.distance) {
                out = Some(rp);
            }
        }
        out.filter(|r| r.distance < REACH)
    }

    pub fn in_bounds(&self, x: f32, z: f32) -> bool {
        x >= self.bounds[0] && z >= self.bounds[1] && x <= self.bounds[2] && z <= self.bounds[3]
    }

    /// Terrain height with the road, obstacle stamps and pads applied on top of `natural`.
    pub fn shape(&self, x: f32, z: f32, natural: f32) -> f32 {
        if !self.in_bounds(x, z) {
            return natural + self.wall_lift(x, z);
        }
        let mut h = natural;
        for pad in &self.pads {
            let (along, across) = local(pad.pos, pad.dir, x, z);
            let ex = (along.abs() - PAD_HALF[0]).max(0.0);
            let ez = (across.abs() - PAD_HALF[1]).max(0.0);
            let e = (ex * ex + ez * ez).sqrt();
            if e < PAD_BLEND {
                let w = smoothstep(PAD_BLEND, 0.0, e);
                h += (pad.pos[1] - h) * w;
            }
        }
        // The road last among the surfaces, so it's always level across, pads or not.
        if let Some(r) = self.near(x, z) {
            let w = smoothstep(
                ROAD_HALF_WIDTH + SHOULDER,
                ROAD_HALF_WIDTH + 0.5,
                r.distance,
            );
            h += (r.height - h) * w;
        }
        for o in &self.obstacles {
            let (along, across) = local(o.pos, o.dir, x, z);
            match o.kind {
                ObstacleKind::Gap => {
                    // A trench right across the corridor, a little wider than the clear span:
                    // the game's abutments give the crisp edges at road level.
                    // It runs on as a gully right across the valley, into its walls, so
                    // there's no driving round.
                    let half = o.length * 0.5 + 0.5;
                    if along.abs() < half + 1.0 && across.abs() < SIDE_REACH {
                        // Crisp at the road (where planks rest); a little softer off it, so the
                        // 1 m terrain grid doesn't saw its edges (still far too steep to climb).
                        let soft = smoothstep(
                            ROAD_HALF_WIDTH + SHOULDER,
                            ROAD_HALF_WIDTH + SHOULDER + 10.0,
                            across.abs(),
                        );
                        let wall = smoothstep(half + 0.35 + 1.1 * soft, half - 0.15, along.abs());
                        let fade = smoothstep(SIDE_REACH, SIDE_REACH - 8.0, across.abs());
                        h -= o.size * wall * fade;
                    }
                }
                ObstacleKind::Ledge => {
                    // The raised road profile already makes the step. Undo its 2 m
                    // interpolation just below the face so the face is sheer, and lift the
                    // ground either side so the RV can't just drive round.
                    let face = o.length * 0.5;
                    let in_corridor = smoothstep(
                        ROAD_HALF_WIDTH + SHOULDER,
                        ROAD_HALF_WIDTH + 0.5,
                        across.abs(),
                    );
                    if along > -SAMPLE - face && along < -face {
                        h -= o.size * smoothstep(-SAMPLE - face, -face, along) * in_corridor;
                    }
                    if along > -face && along < 30.0 && across.abs() < SIDE_REACH {
                        let wing = smoothstep(SIDE_REACH, SIDE_REACH - 8.0, across.abs());
                        let up = smoothstep(-face, face, along) * smoothstep(30.0, 18.0, along);
                        let target = o.pos[1] + o.size;
                        if across.abs() > ROAD_HALF_WIDTH {
                            h += (target - h).max(0.0) * wing * up;
                        }
                    }
                }
                ObstacleKind::Mud => {
                    let half = o.length * 0.5;
                    if along.abs() < half + 2.0 && across.abs() < ROAD_HALF_WIDTH + 1.5 {
                        h -= o.size
                            * smoothstep(half + 2.0, half - 1.0, along.abs())
                            * smoothstep(
                                ROAD_HALF_WIDTH + 1.5,
                                ROAD_HALF_WIDTH - 1.0,
                                across.abs(),
                            );
                    }
                }
                ObstacleKind::Climb => {}
                ObstacleKind::Ford => {
                    // The river's channel, straight across: shallow where the road fords it,
                    // deep off to the sides (no driving round), banks a little above the water.
                    let half = o.length * 0.5;
                    let reach = half + RIVER_BANK + 8.0;
                    if along.abs() < reach && across.abs() < RIVER_HALF {
                        let level = o.pos[1] - 0.05;
                        let off_road = smoothstep(
                            ROAD_HALF_WIDTH + 2.0,
                            ROAD_HALF_WIDTH + SHOULDER,
                            across.abs(),
                        );
                        let depth = o.size + 1.6 * off_road;
                        let channel = smoothstep(half + RIVER_BANK, half, along.abs());
                        // Banks stand a little proud of the water off the road; the road itself
                        // runs straight down into the ford.
                        let target = level - depth * channel + 0.5 * off_road * (1.0 - channel);
                        let w = smoothstep(reach, half + RIVER_BANK, along.abs())
                            * smoothstep(RIVER_HALF, RIVER_HALF - RIVER_FADE, across.abs());
                        h += (target - h) * w;
                    }
                }
                ObstacleKind::Ice => {
                    let d = (along * along + across * across).sqrt();
                    let r = o.length;
                    if d < r + ICE_RAMP {
                        let level = o.pos[1] - o.size;
                        h += (level - h) * smoothstep(r + ICE_RAMP, r, d);
                    }
                }
            }
        }
        for l in &self.lakes {
            let (dx, dz) = (x - l.pos[0], z - l.pos[2]);
            let d = (dx * dx + dz * dz).sqrt();
            if d < l.radius + LAKE_BANK {
                let target = if d < l.radius {
                    if l.frozen {
                        l.pos[1]
                    } else {
                        l.pos[1] - 0.3 - 2.0 * smoothstep(l.radius, l.radius * 0.4, d)
                    }
                } else {
                    l.pos[1] + 0.4
                };
                h += (target - h) * smoothstep(l.radius + LAKE_BANK, l.radius + 2.0, d);
            }
        }
        for c in &self.caves {
            let (dx, dz) = (x - c.pos[0], z - c.pos[2]);
            let d = (dx * dx + dz * dz).sqrt();
            if d < CAVE_RADIUS + CAVE_BLEND {
                h += (c.pos[1] - h) * smoothstep(CAVE_RADIUS + CAVE_BLEND, CAVE_RADIUS, d);
            }
        }
        h + self.wall_lift(x, z)
    }

    /// How far outside the valley floor a point is (metres; <= 0 on it): past the road's
    /// corridor, and past the bays round side lakes and caves.
    pub fn outside_valley(&self, x: f32, z: f32) -> f32 {
        let road = self.wall_road_distance(x, z);
        let mut out = if road.is_finite() {
            let n = (0.5 + 0.5 * perlin(self.wall_seed, x * (1.0 / 160.0), z * (1.0 / 160.0)))
                .clamp(0.0, 1.0);
            // A wobble, so the foot of the wall isn't a smooth curve.
            let wobble =
                WALL_WOBBLE * perlin(self.wall_seed ^ 0xb0b, x * (1.0 / 40.0), z * (1.0 / 40.0));
            road - (WALL_START + WALL_VARY * n) + wobble
        } else {
            f32::INFINITY
        };
        let bay = |cx: f32, cz: f32, r: f32| {
            let (dx, dz) = (x - cx, z - cz);
            (dx * dx + dz * dz).sqrt() - r
        };
        for l in &self.lakes {
            out = out.min(bay(l.pos[0], l.pos[2], l.radius + LAKE_BANK + BAY));
        }
        for c in &self.caves {
            out = out.min(bay(c.pos[0], c.pos[2], CAVE_RADIUS + CAVE_BLEND + BAY));
        }
        out
    }

    /// How much the valley's walls lift the ground at a point: a steep rise just past the
    /// floor, a crest, then easing back to the natural ground far away.
    fn wall_lift(&self, x: f32, z: f32) -> f32 {
        if !self.in_wall_bounds(x, z) {
            return 0.0;
        }
        let e = self.outside_valley(x, z);
        if e <= 0.0 || e >= WALL_BAND + WALL_FADE[1] {
            return 0.0;
        }
        let rise = smoothstep(0.0, WALL_BAND, e);
        let fall = smoothstep(WALL_BAND + WALL_FADE[1], WALL_BAND + WALL_FADE[0], e);
        let n = (0.5 + 0.5 * perlin(self.wall_seed ^ 0x5eed, x * (1.0 / 96.0), z * (1.0 / 96.0)))
            .clamp(0.0, 1.0);
        // Crags along the top, once the wall has most of its height.
        let crag = WALL_CRAGS
            * perlin(self.wall_seed ^ 0xc4a6, x * (1.0 / 22.0), z * (1.0 / 22.0)).abs()
            * smoothstep(0.6 * WALL_BAND, WALL_BAND + 10.0, e);
        (WALL_HEIGHT + WALL_HEIGHT_VARY * n + crag) * rise * fall
    }

    /// Distance to the coarse road centreline, or infinity beyond `WALL_REACH`-ish.
    fn wall_road_distance(&self, x: f32, z: f32) -> f32 {
        let Some(list) = self.wall_grid.get(&wall_cell_of(x, z)) else {
            return f32::INFINITY;
        };
        let mut best = f32::INFINITY;
        for &i in list {
            let i = i as usize;
            let (pa, pb) = (
                self.xz[i],
                self.xz[(i + WALL_STRIDE).min(self.xz.len() - 1)],
            );
            let (ex, ez) = (pb[0] - pa[0], pb[1] - pa[1]);
            let len2 = (ex * ex + ez * ez).max(1e-6);
            let t = (((x - pa[0]) * ex + (z - pa[1]) * ez) / len2).clamp(0.0, 1.0);
            let (ox, oz) = (x - (pa[0] + ex * t), z - (pa[1] + ez * t));
            best = best.min(ox * ox + oz * oz);
        }
        best.sqrt()
    }

    fn in_wall_bounds(&self, x: f32, z: f32) -> bool {
        let b = &self.wall_bounds;
        x >= b[0] && z >= b[1] && x <= b[2] && z <= b[3]
    }

    fn build_wall_grid(&mut self) {
        let mut i = 0;
        while i + 1 < self.xz.len() {
            let (pa, pb) = (
                self.xz[i],
                self.xz[(i + WALL_STRIDE).min(self.xz.len() - 1)],
            );
            let c0 = wall_cell_of(pa[0].min(pb[0]) - WALL_REACH, pa[1].min(pb[1]) - WALL_REACH);
            let c1 = wall_cell_of(pa[0].max(pb[0]) + WALL_REACH, pa[1].max(pb[1]) + WALL_REACH);
            for cz in c0.1..=c1.1 {
                for cx in c0.0..=c1.0 {
                    self.wall_grid.entry((cx, cz)).or_default().push(i as u32);
                }
            }
            i += WALL_STRIDE;
        }
        // Lakes' and caves' bays can reach a little further out than the road's corridor.
        let m = WALL_REACH + 2.0 * (30.0 + LAKE_BANK + BAY);
        self.wall_bounds = [
            self.bounds[0] - m,
            self.bounds[1] - m,
            self.bounds[2] + m,
            self.bounds[3] + m,
        ];
    }

    /// How icy a point is, 0..1 (frozen ponds on the road and frozen lakes).
    pub fn ice_at(&self, x: f32, z: f32) -> f32 {
        if !self.in_bounds(x, z) {
            return 0.0;
        }
        let mut ice: f32 = 0.0;
        for o in self
            .obstacles
            .iter()
            .filter(|o| o.kind == ObstacleKind::Ice)
        {
            let (along, across) = local(o.pos, o.dir, x, z);
            let d = (along * along + across * across).sqrt();
            ice = ice.max(smoothstep(o.length + 3.5, o.length + 1.5, d));
        }
        for l in self.lakes.iter().filter(|l| l.frozen) {
            let (dx, dz) = (x - l.pos[0], z - l.pos[2]);
            ice = ice.max(smoothstep(
                l.radius + 0.5,
                l.radius - 1.0,
                (dx * dx + dz * dz).sqrt(),
            ));
        }
        ice
    }

    /// The water surface height over a point, if it's in a river or an unfrozen lake.
    pub fn water_at(&self, x: f32, z: f32) -> Option<f32> {
        if !self.in_bounds(x, z) {
            return None;
        }
        for o in self
            .obstacles
            .iter()
            .filter(|o| o.kind == ObstacleKind::Ford)
        {
            let (along, across) = local(o.pos, o.dir, x, z);
            if along.abs() < o.length * 0.5 + RIVER_BANK * 0.6
                && across.abs() < RIVER_HALF - RIVER_FADE * 0.5
            {
                return Some(o.pos[1] - 0.05);
            }
        }
        for l in self.lakes.iter().filter(|l| !l.frozen) {
            let (dx, dz) = (x - l.pos[0], z - l.pos[2]);
            if dx * dx + dz * dz < l.radius * l.radius {
                return Some(l.pos[1]);
            }
        }
        None
    }

    /// Whether a point is somewhere nothing should grow or lie: a pad, a cave clearing, a
    /// lake, a river, where planks lie.
    pub fn blocked(&self, x: f32, z: f32, margin: f32) -> bool {
        if !self.in_bounds(x, z) {
            return false;
        }
        if self.on_pad(x, z, margin) {
            return true;
        }
        let near = |p: [f32; 3], r: f32| dist2(p, [x, 0.0, z]) < r * r;
        self.caves.iter().any(|c| near(c.pos, CAVE_RADIUS + margin))
            || self
                .supplies
                .iter()
                .any(|s| s.kind == SupplyKind::Planks && near(s.pos, 2.5 + margin))
            || self
                .lakes
                .iter()
                .any(|l| near(l.pos, l.radius + 2.0 + margin))
            || self.obstacles.iter().any(|o| {
                if o.kind == ObstacleKind::Ford {
                    let (along, across) = local(o.pos, o.dir, x, z);
                    along.abs() < o.length * 0.5 + RIVER_BANK + margin && across.abs() < RIVER_HALF
                } else if o.kind == ObstacleKind::Ice {
                    near(o.pos, o.length + margin)
                } else {
                    false
                }
            })
    }

    /// Whether a point is on a mud hole (the game lowers tire grip there).
    pub fn mud_at(&self, x: f32, z: f32) -> f32 {
        let mut m: f32 = 0.0;
        for o in self
            .obstacles
            .iter()
            .filter(|o| o.kind == ObstacleKind::Mud)
        {
            let (along, across) = local(o.pos, o.dir, x, z);
            let half = o.length * 0.5;
            m = m.max(
                smoothstep(half + 1.5, half - 1.0, along.abs())
                    * smoothstep(ROAD_HALF_WIDTH + 2.0, ROAD_HALF_WIDTH - 0.5, across.abs()),
            );
        }
        m
    }

    /// How much a point is road surface (1 on the road, fading out over the edge).
    pub fn road_at(&self, x: f32, z: f32) -> f32 {
        if !self.in_bounds(x, z) {
            return 0.0;
        }
        let mut w = self.near(x, z).map_or(0.0, |r| {
            smoothstep(ROAD_HALF_WIDTH + 1.2, ROAD_HALF_WIDTH - 0.4, r.distance)
        });
        for pad in &self.pads {
            let (along, across) = local(pad.pos, pad.dir, x, z);
            if along.abs() < PAD_HALF[0] && across.abs() < PAD_HALF[1] {
                w = w.max(0.8);
            }
        }
        w
    }

    /// Distance from the road centreline, or infinity if well away from it.
    pub fn distance(&self, x: f32, z: f32) -> f32 {
        if !self.in_bounds(x, z) {
            return f32::INFINITY;
        }
        self.near(x, z).map_or(f32::INFINITY, |r| r.distance)
    }

    /// Whether a point is on a pad (kept clear of props).
    pub fn on_pad(&self, x: f32, z: f32, margin: f32) -> bool {
        self.pads.iter().any(|pad| {
            let (along, across) = local(pad.pos, pad.dir, x, z);
            along.abs() < PAD_HALF[0] + margin && across.abs() < PAD_HALF[1] + margin
        })
    }

    /// Static solvability checks (PLAN.md §5.4). Returns the problems found.
    pub fn validate(&self) -> Vec<String> {
        let mut problems = Vec::new();
        for (i, w) in self.h.windows(2).enumerate() {
            let s = i as f32 * SAMPLE;
            let excused = self.obstacles.iter().any(|o| {
                matches!(o.kind, ObstacleKind::Ledge | ObstacleKind::Climb)
                    && s > o.s - o.length - 2.0 * SAMPLE
                    && s < o.s + 120.0
            });
            if !excused && (w[1] - w[0]).abs() > MAX_GRADE * SAMPLE + 1e-3 {
                let near: Vec<String> = self
                    .obstacles
                    .iter()
                    .filter(|o| (o.s - s).abs() < 300.0)
                    .map(|o| format!("{:?}@{:.0}", o.kind, o.s))
                    .collect();
                problems.push(format!(
                    "road too steep at {s:.0} m ({:.2} m/sample; near {near:?})",
                    (w[1] - w[0]).abs()
                ));
                break;
            }
        }
        for o in &self.obstacles {
            match o.kind {
                ObstacleKind::Gap => {
                    let planks = self.supplies.iter().any(|s| {
                        s.kind == SupplyKind::Planks
                            && s.count >= 2
                            && dist2(s.pos, o.pos) < 60.0 * 60.0
                    });
                    if !planks {
                        problems.push(format!("gap at {:.0} m has no planks before it", o.s));
                    }
                    // Planks rest on the abutments either side of the clear span. (Narrower
                    // than ~3.5 m and the RV just hops it at speed.)
                    if o.length > PLANK_LENGTH - 0.6 || o.length < 3.5 {
                        problems.push(format!(
                            "gap at {:.0} m is wider than a plank can span",
                            o.s
                        ));
                    }
                }
                ObstacleKind::Ledge => {
                    let anchor = self
                        .supplies
                        .iter()
                        .any(|s| s.kind == SupplyKind::Anchor && dist2(s.pos, o.pos) < 30.0 * 30.0);
                    if !anchor {
                        problems.push(format!("ledge at {:.0} m has no winch anchor", o.s));
                    }
                }
                ObstacleKind::Ford => {
                    if o.size > MAX_FORD_DEPTH {
                        problems.push(format!(
                            "ford at {:.0} m is too deep ({:.2} m)",
                            o.s, o.size
                        ));
                    }
                }
                ObstacleKind::Ice => {
                    let reach = o.length + ICE_RAMP + 30.0;
                    let anchor = self.supplies.iter().any(|s| {
                        s.kind == SupplyKind::Anchor && dist2(s.pos, o.pos) < reach * reach
                    });
                    let planks = self.supplies.iter().any(|s| {
                        s.kind == SupplyKind::Planks && dist2(s.pos, o.pos) < reach * reach
                    });
                    if !anchor || !planks {
                        problems.push(format!("ice at {:.0} m has no winch anchor or planks", o.s));
                    }
                }
                _ => {}
            }
        }
        for pair in self.obstacles.windows(2) {
            if pair[1].s - pair[0].s < 120.0 {
                problems.push(format!(
                    "obstacles at {:.0} and {:.0} m are too close",
                    pair[0].s, pair[1].s
                ));
            }
        }
        for l in &self.lakes {
            if self.min_road_distance(l.pos[0], l.pos[2], self.near_s(l.pos), l.radius + 150.0)
                < l.radius + LAKE_BANK + REACH
            {
                problems.push(format!(
                    "lake at ({:.0}, {:.0}) floods the road",
                    l.pos[0], l.pos[2]
                ));
            }
        }
        for c in &self.caves {
            if self.min_road_distance(c.pos[0], c.pos[2], self.near_s(c.pos), 200.0)
                < CAVE_RADIUS + CAVE_BLEND + REACH - 1.0
            {
                problems.push(format!(
                    "cave at ({:.0}, {:.0}) is on the road",
                    c.pos[0], c.pos[2]
                ));
            }
        }
        if self.pads.first().map(|p| p.kind) != Some(PadKind::Camp)
            || self.pads.last().map(|p| p.kind) != Some(PadKind::Home)
        {
            problems.push("trip must start at camp and end at home".into());
        }
        problems
    }
}

impl Route {
    /// Arc length of the road sample closest to a point (a full scan; validation only).
    fn near_s(&self, p: [f32; 3]) -> f32 {
        let mut best = (f32::INFINITY, 0usize);
        for (i, q) in self.xz.iter().enumerate() {
            let d = (q[0] - p[0]) * (q[0] - p[0]) + (q[1] - p[2]) * (q[1] - p[2]);
            if d < best.0 {
                best = (d, i);
            }
        }
        best.1 as f32 * SAMPLE
    }
}

fn dist2(a: [f32; 3], b: [f32; 3]) -> f32 {
    (a[0] - b[0]) * (a[0] - b[0]) + (a[2] - b[2]) * (a[2] - b[2])
}

/// (along, across) of a point in a road-aligned frame at `origin` facing `dir`.
fn local(origin: [f32; 3], dir: [f32; 2], x: f32, z: f32) -> (f32, f32) {
    let (ox, oz) = (x - origin[0], z - origin[2]);
    let along = ox * dir[0] + oz * dir[1];
    // Right of travel: (-dz, dx) in x/z where +z is "down" on a map with +x east.
    let across = -ox * dir[1] + oz * dir[0];
    (along, across)
}

fn cell_of(x: f32, z: f32) -> (i32, i32) {
    ((x / GRID).floor() as i32, (z / GRID).floor() as i32)
}

const WALL_GRID: f32 = 64.0;

fn wall_cell_of(x: f32, z: f32) -> (i32, i32) {
    (
        (x / WALL_GRID).floor() as i32,
        (z / WALL_GRID).floor() as i32,
    )
}

/// Heading (0 = +x, east; positive turns towards +z) as a unit (x, z), using a polynomial
/// approximation instead of platform trig so every CPU agrees.
fn dir_of(heading: f32) -> (f32, f32) {
    let (s, c) = sin_cos(heading);
    (c, s)
}

/// sin/cos for |a| <= 1, via Taylor series (plenty for |a| < 0.9; deterministic).
fn sin_cos(a: f32) -> (f32, f32) {
    let a2 = a * a;
    let s = a * (1.0 - a2 / 6.0 * (1.0 - a2 / 20.0 * (1.0 - a2 / 42.0 * (1.0 - a2 / 72.0))));
    let c = 1.0 - a2 / 2.0 * (1.0 - a2 / 12.0 * (1.0 - a2 / 30.0 * (1.0 - a2 / 56.0)));
    (s, c)
}

fn catmull_rom(points: &[[f32; 2]], per_segment: usize) -> Vec<[f32; 2]> {
    let mut out = Vec::with_capacity(points.len() * per_segment);
    let get = |i: isize| points[i.clamp(0, points.len() as isize - 1) as usize];
    for i in 0..points.len() - 1 {
        let (p0, p1, p2, p3) = (
            get(i as isize - 1),
            get(i as isize),
            get(i as isize + 1),
            get(i as isize + 2),
        );
        for k in 0..per_segment {
            let t = k as f32 / per_segment as f32;
            let (t2, t3) = (t * t, t * t * t);
            let f = |a: f32, b: f32, c: f32, d: f32| {
                0.5 * (2.0 * b
                    + (-a + c) * t
                    + (2.0 * a - 5.0 * b + 4.0 * c - d) * t2
                    + (-a + 3.0 * b - 3.0 * c + d) * t3)
            };
            out.push([f(p0[0], p1[0], p2[0], p3[0]), f(p0[1], p1[1], p2[1], p3[1])]);
        }
    }
    out.push(*points.last().unwrap());
    out
}

/// Evenly spaced points along a polyline, up to `max_len` of arc length.
fn resample(points: &[[f32; 2]], spacing: f32, max_len: f32) -> Vec<[f32; 2]> {
    let mut out = vec![points[0]];
    let mut carry = 0.0;
    let mut walked = 0.0;
    for w in points.windows(2) {
        let (a, b) = (w[0], w[1]);
        let seg = ((b[0] - a[0]) * (b[0] - a[0]) + (b[1] - a[1]) * (b[1] - a[1])).sqrt();
        let mut d = spacing - carry;
        while d <= seg {
            let t = d / seg;
            out.push([a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]);
            walked += spacing;
            if walked >= max_len {
                return out;
            }
            d += spacing;
        }
        carry = seg - (d - spacing);
    }
    out
}

fn moving_average(v: &[f32], radius: usize) -> Vec<f32> {
    let n = v.len();
    (0..n)
        .map(|i| {
            let (a, b) = (i.saturating_sub(radius), (i + radius).min(n - 1));
            v[a..=b].iter().sum::<f32>() / (b - a + 1) as f32
        })
        .collect()
}

/// Limits the change between neighbouring samples to `max_step` (forwards then backwards).
fn limit_grade(h: &mut [f32], max_step: f32) {
    for i in 1..h.len() {
        h[i] = h[i].clamp(h[i - 1] - max_step, h[i - 1] + max_step);
    }
    for i in (0..h.len() - 1).rev() {
        h[i] = h[i].clamp(h[i + 1] - max_step, h[i + 1] + max_step);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{SeedCode, World};

    fn route(seed: u64, trip: TripLength) -> Route {
        World::new(SeedCode::new(trip, seed))
            .unwrap()
            .route()
            .clone()
    }

    #[test]
    fn deterministic() {
        let a = route(5, TripLength::Short);
        let b = route(5, TripLength::Short);
        assert_eq!(a.xz, b.xz);
        assert_eq!(a.h, b.h);
        assert_eq!(a.obstacles, b.obstacles);
    }

    #[test]
    fn heads_home_without_looping() {
        let r = route(11, TripLength::Short);
        for w in r.xz.windows(2) {
            assert!(
                w[1][0] > w[0][0] - 0.01,
                "the road always makes progress east"
            );
        }
        assert!(r.length > 1900.0 && r.length < 3000.0, "{}", r.length);
    }

    #[test]
    fn trips_have_stations_and_obstacles() {
        for trip in [TripLength::Short, TripLength::Medium] {
            let r = route(3, trip);
            let stations = r.pads.iter().filter(|p| p.kind == PadKind::Station).count();
            assert_eq!(stations + 1, trip.stations() as usize);
            assert!(r.obstacles.len() >= 5, "{} obstacles", r.obstacles.len());
        }
    }

    #[test]
    fn many_seeds_validate() {
        let mut kinds = [0; 6];
        let (mut lakes, mut frozen, mut caves) = (0, 0, 0);
        for seed in 0..200 {
            let trip = if seed % 4 == 0 {
                TripLength::Medium
            } else {
                TripLength::Short
            };
            let r = route(seed, trip);
            let problems = r.validate();
            assert!(problems.is_empty(), "seed {seed}: {problems:?}");
            for o in &r.obstacles {
                kinds[o.kind as usize] += 1;
            }
            lakes += r.lakes.len();
            frozen += r.lakes.iter().filter(|l| l.frozen).count();
            caves += r.caves.len();
        }
        assert!(
            kinds.iter().all(|&k| k > 20),
            "every obstacle kind appears: {kinds:?}"
        );
        assert!(
            lakes > 50 && frozen > 10 && caves > 50,
            "{lakes} lakes ({frozen} frozen), {caves} caves"
        );
    }

    #[test]
    fn fords_are_wet_and_ice_is_icy() {
        let (mut fords, mut ice) = (0, 0);
        for seed in 0..60 {
            let w = World::new(SeedCode::new(TripLength::Medium, seed)).unwrap();
            let r = w.route();
            for o in &r.obstacles {
                match o.kind {
                    ObstacleKind::Ford => {
                        fords += 1;
                        let level = r.water_at(o.pos[0], o.pos[2]).expect("water on the ford");
                        let depth = level - w.height_at(o.pos[0], o.pos[2]);
                        assert!(
                            depth > 0.2 && depth <= MAX_FORD_DEPTH + 0.05,
                            "ford {depth:.2} m deep"
                        );
                        // Off to the side it's too deep to drive round.
                        let side = [o.pos[0] - o.dir[1] * 15.0, o.pos[2] + o.dir[0] * 15.0];
                        let deep = level - w.height_at(side[0], side[1]);
                        assert!(deep > 1.2, "ford sides only {deep:.2} m deep");
                    }
                    ObstacleKind::Ice => {
                        ice += 1;
                        assert!(r.ice_at(o.pos[0], o.pos[2]) > 0.99);
                        assert!(r.water_at(o.pos[0], o.pos[2]).is_none());
                    }
                    _ => {}
                }
            }
        }
        assert!(fords > 5 && ice > 5, "{fords} fords, {ice} ice");
    }

    #[test]
    fn road_is_flat_across_and_carved() {
        let w = World::new(SeedCode::new(TripLength::Short, 9)).unwrap();
        let r = w.route();
        for i in (50..r.xz.len() - 50).step_by(37) {
            let p = r.xz[i];
            if r.obstacles
                .iter()
                .any(|o| (o.s - i as f32 * SAMPLE).abs() < 60.0)
            {
                continue;
            }
            let d = r.dir(i);
            let n = [-d[1], d[0]];
            let hl = w.height_at(p[0] + n[0] * 2.0, p[1] + n[1] * 2.0);
            let hr = w.height_at(p[0] - n[0] * 2.0, p[1] - n[1] * 2.0);
            assert!(
                (hl - hr).abs() < 0.35,
                "road level across at sample {i}: {hl} vs {hr}"
            );
            assert!(
                (w.height_at(p[0], p[1]) - r.h[i]).abs() < 0.3,
                "road carved at sample {i}"
            );
        }
    }

    #[test]
    fn walls_keep_you_in_the_valley() {
        // Flood-fill everywhere you could stand from the camp (ground no steeper than the
        // player's 50° limit, on a 2 m grid; the RV manages far less): it must never get past
        // the valley's walls, behind the camp or past home.
        for seed in [1, 7, 21] {
            let w = World::new(SeedCode::new(TripLength::Short, seed)).unwrap();
            let r = w.route();
            let h = |x: i32, z: i32| crate::terrain::q_to_m(w.height_q(x, z));
            let standable = |x: i32, z: i32| {
                let gx = (h(x + 1, z) - h(x - 1, z)) * 0.5;
                let gz = (h(x, z + 1) - h(x, z - 1)) * 0.5;
                gx * gx + gz * gz < 1.19 * 1.19
            };
            let start = (r.xz[0][0] as i32 & !1, r.xz[0][1] as i32 & !1);
            let mut seen = std::collections::BTreeSet::from([start]);
            let mut stack = vec![start];
            while let Some((x, z)) = stack.pop() {
                let out = r.outside_valley(x as f32, z as f32);
                assert!(
                    out < WALL_BAND,
                    "seed {seed}: walked out of the valley at ({x}, {z}), {out:.1} m past its floor"
                );
                for (dx, dz) in [(2, 0), (-2, 0), (0, 2), (0, -2)] {
                    let n = (x + dx, z + dz);
                    if !seen.contains(&n)
                        && standable(n.0, n.1)
                        && (h(n.0, n.1) - h(x, z)).abs() < 1.5
                    {
                        seen.insert(n);
                        stack.push(n);
                    }
                }
            }
            assert!(
                seen.len() > 5000,
                "seed {seed}: the fill got going ({} cells)",
                seen.len()
            );
        }
    }

    #[test]
    fn the_valley_floor_holds_the_trip() {
        for seed in 0..60 {
            let w = World::new(SeedCode::new(TripLength::Short, seed)).unwrap();
            let r = w.route();
            let on_floor = |p: [f32; 3], what: &str| {
                let out = r.outside_valley(p[0], p[2]);
                assert!(
                    out < -2.0,
                    "seed {seed}: {what} at {p:?} is {out:.1} m into a wall"
                );
            };
            for (i, p) in r.xz.iter().enumerate().step_by(5) {
                on_floor([p[0], 0.0, p[1]], &format!("road sample {i}"));
            }
            for p in &r.pads {
                on_floor(p.pos, "a stop");
            }
            for s in &r.supplies {
                on_floor(s.pos, "a supply");
            }
            for c in &r.caves {
                on_floor(c.pos, "a cave");
            }
            for l in &r.lakes {
                on_floor(l.pos, "a lake");
            }
            // Behind the camp and past home it's walled off.
            let (a, d) = (r.xz[0], r.dir(0));
            let behind = [a[0] - d[0] * 90.0, a[1] - d[1] * 90.0];
            let lift =
                w.height_at(behind[0], behind[1]) - w.terrain().height_m(behind[0], behind[1]);
            assert!(
                lift > WALL_HEIGHT - 1.0,
                "seed {seed}: walled off behind the camp ({lift:.1} m)"
            );
        }
    }

    #[test]
    fn sin_cos_is_accurate() {
        for k in -9..=9 {
            let a = k as f32 * 0.1;
            let (s, c) = sin_cos(a);
            assert!((s - a.sin()).abs() < 1e-5 && (c - a.cos()).abs() < 1e-5);
        }
    }
}

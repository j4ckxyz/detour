//! The trip (PLAN.md §5.1–5.4): a long, winding road from the start camp to home, split into
//! segments that end at gas stations, with obstacles along it that get harder towards home.
//!
//! Everything is a pure function of the seed:
//!
//! 1. **The road**: several candidate routes are walked east across the terrain, each
//!    meandering its own way, and the best is kept (`path`): little cutting and filling, no
//!    mountains looming over it, some hills to climb, straight runs for bridges and jumps.
//! 2. **Obstacles** are planned along it by biome, difficulty and what the ground there
//!    allows (a jump needs a straight, level run-up; a hill climb needs a real hill).
//! 3. **The profile**: the road is carved into the terrain (cut and fill to a grade limit),
//!    except up the hills, where it climbs as steep as the hill; obstacles stamp their shapes
//!    (gaps, ravines, gullies, ledges, humps, fords, frozen ponds, mud).
//! 4. **The valley** (`valley`): wide between obstacles, pinched at each, walled beyond.
//! 5. **Side features**: lakes, caves, places to look round (a cabin, a fire lookout, a
//!    wreck, a hill with a view), and a tempting side track at the foot of each hill.
//!
//! `Route::validate` checks the solvability rules; the tests check them for many seeds.

mod path;
mod valley;

#[cfg(test)]
mod tests;

use std::collections::BTreeMap;

use crate::biome::Biome;
use crate::hash::{sub_seed, sub_seed32};
use crate::noise::smoothstep;
use crate::rng::Pcg32;
use crate::seed::TripLength;
use crate::terrain::TerrainGen;

pub use path::{CANDIDATES, sin_cos};
use valley::Walls;
pub use valley::{FLOOR_NARROW, FLOOR_WIDE, WALL_BAND, WALL_HEIGHT};

/// Half the driveable width of the road, metres.
pub const ROAD_HALF_WIDTH: f32 = 3.2;
/// Width of the cut/fill blend beyond the road edge.
pub const SHOULDER: f32 = 9.0;
/// No trees or props within this distance of the centreline.
pub const CLEAR: f32 = ROAD_HALF_WIDTH + 3.5;
/// Beyond the clearing, trees crowd the road so it reads as a forest track.
pub const TREE_WALL: f32 = 16.0;
/// Spacing of route samples along the road.
pub const SAMPLE: f32 = 2.0;
/// Steepest ordinary road grade (obstacles break it on purpose).
pub const MAX_GRADE: f32 = 0.09;
/// Where every trip starts (world x, z).
pub const START: [f32; 2] = [64.0, 64.0];
/// Length of a plank (the game's plank model must match), metres.
pub const PLANK_LENGTH: f32 = 5.0;
/// The road's level from the start to here (the camp's at 30 m).
const CAMP_LEVEL: f32 = 180.0;
/// Segment lengths (camp → station → ... → home), metres.
pub const SEGMENT: [f32; 2] = [1300.0, 1800.0];

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
/// A side lake, cave or place opens the valley out to this far past its clearing.
const BAY: f32 = 14.0;
/// Gullies, ravines and a ledge's raised ground reach this far either side (into the walls
/// where the valley pinches in).
const SIDE_REACH: f32 = FLOOR_NARROW + valley::WALL_WOBBLE + WALL_BAND + 8.0;
/// Hills: at least this rise over this length of road, climbed at up to this grade.
pub const HILL_RISE: f32 = 14.0;
pub const HILL_LENGTH: f32 = 160.0;
pub const HILL_MAX_GRADE: f32 = 0.22;
/// A jump: the kicker's height and length before the lip, and how far the far side lies
/// below the lip (so a fast run carries over).
pub const KICKER: [f32; 2] = [0.8, 8.0];
pub const LANDING_DROP: f32 = 1.5;
/// A jump's straight, level run-up before the kicker.
pub const RUN_UP: f32 = 140.0;
/// Bridges: the deck's kicker before its hole (height, length).
pub const DECK_KICKER: [f32; 2] = [0.3, 2.5];
/// Two-beam crossings: each beam's width, and how far each is from the centreline (the
/// RV's wheels are ±0.9–0.92 m out).
pub const BEAM_WIDTH: f32 = 0.45;
pub const BEAM_OFFSET: f32 = 0.91;

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
    /// An old wooden bridge over a deep ravine (the game builds it) with a hole in its deck:
    /// jump it off the little kicker before it (third gear), or lay planks across.
    Bridge = 6,
    /// A ravine crossed by two narrow beams, one under each wheel track: line up and creep.
    Beams = 7,
    /// A gully too wide for planks, with a kicker ramp before it and the far side a little
    /// lower: take a straight run at it, fast.
    Jump = 8,
    /// The road goes straight up a real hill, steep (up to 22 %); a side track that's easier
    /// going heads off downhill from its foot, to a dead end.
    Hill = 9,
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
    /// Arc length of its centre along the road (a hill: its foot).
    pub s: f32,
    /// Centre on the road (x, road height, z) and the road direction (x, z).
    pub pos: [f32; 3],
    pub dir: [f32; 2],
    /// Extent along the road (gap, ravine or gully width; mud, climb or hill length).
    pub length: f32,
    /// Depth (gap, ravine, gully), rise (ledge, climb, hill) or dip (mud, ice), metres.
    pub size: f32,
    /// A bridge's hole: its length and where its centre is along the bridge (from `pos`).
    pub hole: f32,
    pub hole_at: f32,
    /// 0 (first) .. 1 (last): how far into the trip it is.
    pub difficulty: f32,
}

impl Obstacle {
    /// The stretch of road it takes up (arc lengths, start and end).
    pub fn extent(&self) -> (f32, f32) {
        let half = self.length * 0.5;
        match self.kind {
            ObstacleKind::Gap | ObstacleKind::Bridge | ObstacleKind::Beams | ObstacleKind::Mud => {
                (self.s - half - 2.0, self.s + half + 2.0)
            }
            ObstacleKind::Ledge => (self.s - 4.0, self.s + 32.0),
            ObstacleKind::Climb => (self.s - half, self.s + half),
            ObstacleKind::Ford => (
                self.s - half - RIVER_BANK - 8.0,
                self.s + half + RIVER_BANK + 8.0,
            ),
            ObstacleKind::Ice => (
                self.s - self.length - ICE_RAMP,
                self.s + self.length + ICE_RAMP,
            ),
            ObstacleKind::Jump => (self.s - half - KICKER[1] - 4.0, self.s + half + 20.0),
            ObstacleKind::Hill => (self.s - 20.0, self.s + self.length + 20.0),
        }
    }
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

/// A place off the road worth a look (the game builds it and puts a few things there).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum PoiKind {
    /// An abandoned cabin.
    Cabin = 0,
    /// A fire lookout tower, tall enough to see from the road.
    Tower = 1,
    /// A wrecked old car, good for scrap.
    Wreck = 2,
    /// A hill with a view (walk up it).
    Lookout = 3,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Poi {
    pub kind: PoiKind,
    /// Centre (x, ground height, z; a lookout: the foot) and the direction facing the road.
    pub pos: [f32; 3],
    pub dir: [f32; 2],
    /// The levelled clearing's radius (a lookout: its hill's).
    pub radius: f32,
}

const LOOKOUT_HEIGHT: f32 = 11.0;
const LOOKOUT_TOP: f32 = 6.0;

/// A side track off the road (at the foot of a hill), ending nowhere.
#[derive(Clone, Debug, PartialEq)]
pub struct Spur {
    /// Arc length along the road where it leaves.
    pub from_s: f32,
    /// Centreline every `SAMPLE` metres (x, z) and its surface height.
    pub xz: Vec<[f32; 2]>,
    pub h: Vec<f32>,
    bounds: [f32; 4],
}

impl Spur {
    /// Distance from the centreline (a scan; spurs are short), or infinity well away.
    pub fn distance(&self, x: f32, z: f32) -> f32 {
        self.nearest(x, z).map_or(f32::INFINITY, |n| n.0)
    }

    /// (distance, height there) of the closest centreline point, if within ~260 m.
    fn nearest(&self, x: f32, z: f32) -> Option<(f32, f32)> {
        let b = &self.bounds;
        if x < b[0] || z < b[1] || x > b[2] || z > b[3] {
            return None;
        }
        let mut best = (f32::INFINITY, 0.0);
        for (i, p) in self.xz.iter().enumerate() {
            let d = (p[0] - x) * (p[0] - x) + (p[1] - z) * (p[1] - z);
            if d < best.0 {
                best = (d, self.h[i]);
            }
        }
        Some((best.0.sqrt(), best.1))
    }
}

const SPUR_HALF_WIDTH: f32 = 2.6;

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
    pub pois: Vec<Poi>,
    pub spurs: Vec<Spur>,
    pub length: f32,
    /// Samples near each grid cell (cells of `GRID` metres, keyed by cell).
    grid: BTreeMap<(i32, i32), Vec<u32>>,
    bounds: [f32; 4],
    walls: Walls,
    /// Bays the valley opens into: (x, z, radius).
    bays: Vec<[f32; 3]>,
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

/// The trip's segment lengths, drawn the same way everywhere (the biomes need them too).
pub fn segment_lengths(world_seed: u64, trip: TripLength) -> Vec<f32> {
    let mut rng = Pcg32::new(sub_seed(world_seed, "route", 0, 0), 3);
    (0..trip.stations())
        .map(|_| rng.range_f32(SEGMENT[0], SEGMENT[1]))
        .collect()
}

impl Route {
    pub fn generate(world_seed: u64, trip: TripLength, terrain: &TerrainGen) -> Self {
        Self::generate_with(world_seed, trip, terrain, &mut |_, _| {})
    }

    /// Generates the trip, telling `progress(fraction, what)` how it's going.
    pub fn generate_with(
        world_seed: u64,
        trip: TripLength,
        terrain: &TerrainGen,
        progress: &mut dyn FnMut(f32, &str),
    ) -> Self {
        let lengths = segment_lengths(world_seed, trip);
        let mut ends = Vec::with_capacity(lengths.len());
        let mut total = 0.0;
        for l in &lengths {
            total += l;
            ends.push(total);
        }

        // 1. Survey candidate routes and keep the best.
        let mut best: Option<path::Candidate> = None;
        for k in 0..CANDIDATES {
            progress(0.7 * k as f32 / CANDIDATES as f32, "Surveying routes");
            let c = path::candidate(world_seed, k, total, terrain);
            if best.as_ref().is_none_or(|b| c.score < b.score) {
                best = Some(c);
            }
        }
        let xz = best.map(|b| b.xz).unwrap_or_default();
        progress(0.72, "Planning the obstacles");
        let natural: Vec<f32> = xz.iter().map(|p| terrain.height_m(p[0], p[1])).collect();
        let n = xz.len();
        let mut proto = path::moving_average(&natural, 20);
        path::limit_grade(&mut proto, &vec![MAX_GRADE * SAMPLE; n]);

        let mut rng = Pcg32::new(sub_seed(world_seed, "route.plan", 0, 0), 13);
        let mut route = Route {
            length: (n - 1) as f32 * SAMPLE,
            xz,
            h: proto,
            obstacles: Vec::new(),
            pads: Vec::new(),
            supplies: Vec::new(),
            lakes: Vec::new(),
            caves: Vec::new(),
            pois: Vec::new(),
            spurs: Vec::new(),
            grid: BTreeMap::new(),
            bounds: [0.0; 4],
            walls: Walls::default(),
            bays: Vec::new(),
        };

        // 2. Pads: the camp at the start, a station at each segment end, home at the end.
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

        // 3. Obstacles.
        route.plan_obstacles(&mut rng, terrain, &natural);
        progress(0.8, "Carving the road");
        // Levelling round crossings can flatten a hill; one that's lost its climb is dropped.
        for _ in 0..4 {
            route.build_profile(&natural);
            let before = route.obstacles.len();
            let weak: Vec<bool> = route
                .obstacles
                .iter()
                .map(|o| o.kind == ObstacleKind::Hill && route.hill_rise(o) < HILL_RISE * 0.75)
                .collect();
            let mut k = 0;
            route.obstacles.retain(|_| {
                k += 1;
                !weak[k - 1]
            });
            if route.obstacles.len() == before {
                break;
            }
        }
        route.stamp_obstacles();
        route.place_supplies(&mut rng, terrain);
        route.build_grid();
        progress(0.85, "Shaping the valley");
        route.place_spurs(terrain);
        route.walls = Walls::build(&route, sub_seed32(world_seed, "route.walls"));
        progress(0.9, "Placing lakes, caves and places to explore");
        route.place_lakes(world_seed, terrain);
        route.place_caves(world_seed, terrain);
        route.place_pois(world_seed, terrain);
        route.bays = route.collect_bays();
        progress(1.0, "Checking every crossing can be made");
        route
    }

    // --- planning ------------------------------------------------------------------------

    /// Picks obstacles along the road by biome, difficulty and what the ground allows, with
    /// a quiet stretch now and then.
    fn plan_obstacles(&mut self, rng: &mut Pcg32, terrain: &TerrainGen, natural: &[f32]) {
        let hills: Vec<f32> = path::hill_sites(natural)
            .into_iter()
            .map(|i| i as f32 * SAMPLE)
            .collect();
        let mut s = 260.0;
        let mut since_breather = 0;
        let mut last_hill = f32::NEG_INFINITY;
        while s < self.length - 200.0 {
            let (pick, a, b, c) = (
                rng.next_f32(),
                rng.next_f32(),
                rng.next_f32(),
                rng.next_f32(),
            );
            let (seek, gap_after) = (rng.next_f32(), rng.range_f32(120.0, 210.0));
            if self.pads.iter().any(|p| (p.s - s).abs() < 110.0) {
                s += 60.0;
                continue;
            }
            if since_breather >= 3 && a < 0.45 {
                since_breather = 0; // A quiet stretch: the valley opens out.
                s += 260.0;
                continue;
            }
            let t = s / self.length;
            let i = self.index_at(s);
            let biome = terrain.biomes().at(self.xz[i][0], self.xz[i][1]);
            // A hill nearby takes priority (one every 900 m at most).
            let hill = hills
                .iter()
                .copied()
                .find(|&h| h >= s - 20.0 && h < s + 160.0 && h - last_hill > 900.0);
            // Otherwise, more often than not, a crossing (bridge, beams, jump or gap) where the
            // road runs straight in the next stretch, if there is one.
            let crossing = || {
                (0..20).map(|k| s + k as f32 * 10.0).find_map(|at| {
                    let t = at / self.length;
                    self.choose_kind(pick, biome, t, at, true)
                        .map(|kind| (kind, at, t))
                })
            };
            let o = if let Some(foot) = hill.filter(|_| pick < 0.85) {
                last_hill = foot;
                self.make(
                    ObstacleKind::Hill,
                    foot,
                    t,
                    HILL_LENGTH,
                    natural[self.index_at(foot + HILL_LENGTH)] - natural[self.index_at(foot)],
                    b,
                    c,
                )
            } else if let Some((kind, at, t)) = crossing().filter(|_| seek < 0.6) {
                self.sized(kind, at, t, b, c)
            } else {
                let kind = self
                    .choose_kind(pick, biome, t, s, false)
                    .unwrap_or(if t < 0.5 {
                        ObstacleKind::Mud
                    } else {
                        ObstacleKind::Climb
                    });
                self.sized(kind, s, t, b, c)
            };
            let (start, end) = o.extent();
            let clear_of_pads = self
                .pads
                .iter()
                .all(|p| p.s < start - 90.0 || p.s > end + 90.0);
            let clear_of_last = self
                .obstacles
                .last()
                .is_none_or(|l| l.extent().1 + 90.0 < start);
            if clear_of_pads && clear_of_last && end < self.length - 150.0 {
                self.obstacles.push(o);
                since_breather += 1;
                s = end + gap_after;
            } else {
                s += 40.0;
            }
        }
    }

    /// An obstacle kind for arc length `s` by biome and difficulty, among those the ground
    /// there allows (only crossings, if `crossings`).
    fn choose_kind(
        &self,
        roll: f32,
        biome: Biome,
        t: f32,
        s: f32,
        crossings: bool,
    ) -> Option<ObstacleKind> {
        use ObstacleKind::*;
        // [Gap, Ledge, Mud, Climb, Ford, Ice, Bridge, Beams, Jump]
        let base: [f32; 9] = match biome {
            Biome::Forest => [0.2, 0.1, 0.12, 0.1, 0.0, 0.0, 0.2, 0.14, 0.14],
            Biome::Swamp => [0.14, 0.0, 0.26, 0.04, 0.26, 0.0, 0.18, 0.08, 0.04],
            Biome::Canyon => [0.14, 0.2, 0.0, 0.14, 0.06, 0.0, 0.14, 0.14, 0.18],
            Biome::Alpine => [0.1, 0.14, 0.0, 0.14, 0.0, 0.26, 0.14, 0.1, 0.12],
        };
        let kinds = [Gap, Ledge, Mud, Climb, Ford, Ice, Bridge, Beams, Jump];
        let mut w = base;
        // The first stretch teaches: mud, climbs, a plank gap or a ford.
        let min_t = [0.0, 0.15, 0.0, 0.0, 0.0, 0.1, 0.12, 0.2, 0.28];
        for k in 0..9 {
            if t < min_t[k] {
                w[k] = 0.0;
            }
        }
        // Bridges, beams and gaps want a straight, level stretch; a jump a long straight,
        // level run-up.
        let level = |a: f32, b: f32| {
            let (ia, ib) = (self.index_at(a.max(0.0)), self.index_at(b));
            (self.h[ib] - self.h[ia]).abs() <= 0.04 * (b - a).max(1.0)
        };
        let straight = |a: f32, b: f32, min_dot: f32| {
            path::is_straight(
                &self.xz,
                self.index_at(a.max(0.0)),
                self.index_at(b),
                min_dot,
            )
        };
        if !(straight(s - 40.0, s + 40.0, 0.99) && level(s - 30.0, s + 30.0)) {
            w[6] = 0.0;
            w[7] = 0.0;
        }
        let run_up_rise = self.h[self.index_at(s)] - self.h[self.index_at((s - RUN_UP).max(0.0))];
        if !(straight(s - RUN_UP - 10.0, s + 20.0, 0.996)
            && run_up_rise < 0.02 * RUN_UP
            && level(s - 30.0, s + 30.0))
        {
            w[8] = 0.0;
        }
        if !straight(s - 15.0, s + 15.0, 0.98) {
            w[0] = 0.0;
        }
        if crossings {
            for k in [1, 2, 3, 4, 5] {
                w[k] = 0.0;
            }
            // Bridges, beams and jumps are what the straights are for.
            w[0] = 0.0;
        }
        let total: f32 = w.iter().sum();
        if total <= 0.0 {
            return None;
        }
        let mut r = roll * total;
        for k in 0..9 {
            r -= w[k];
            if r < 0.0 && w[k] > 0.0 {
                return Some(kinds[k]);
            }
        }
        w.iter().rposition(|&x| x > 0.0).map(|k| kinds[k])
    }

    /// An obstacle of `kind` at `s`, sized by difficulty `t` and two rolls.
    fn sized(&self, kind: ObstacleKind, s: f32, t: f32, a: f32, b: f32) -> Obstacle {
        use ObstacleKind::*;
        let (length, size) = match kind {
            Gap => (3.8 + 0.6 * t, 1.9 + 0.7 * a),
            Ledge => (1.0, 1.1 + 0.5 * t + 0.1 * a),
            Mud => (16.0 + 14.0 * t + 8.0 * a, 0.25),
            Climb => (70.0, 5.0 + 3.0 * t + 1.0 * b),
            Ford => (8.0 + 4.0 * a, (0.45 + 0.3 * t).min(MAX_FORD_DEPTH - 0.05)),
            Ice => (14.0 + 4.0 * a, 1.4 + 0.6 * t),
            Bridge => (20.0 + 8.0 * a, 8.0 + 2.0 * b),
            Beams => (9.0 + 4.0 * t + 1.0 * a, 7.0 + 2.0 * b),
            Jump => (5.6 + 1.4 * t, 4.5),
            Hill => (HILL_LENGTH, HILL_RISE),
        };
        self.make(kind, s, t, length, size, a, b)
    }

    #[allow(clippy::too_many_arguments)]
    fn make(
        &self,
        kind: ObstacleKind,
        s: f32,
        t: f32,
        length: f32,
        size: f32,
        a: f32,
        b: f32,
    ) -> Obstacle {
        let i = self.index_at(s);
        let (hole, hole_at) = if kind == ObstacleKind::Bridge {
            let hole = 3.4 + 0.8 * a.max(t);
            (hole, (b - 0.5) * (length - 14.0).max(0.0))
        } else {
            (0.0, 0.0)
        };
        Obstacle {
            kind,
            s,
            pos: [self.xz[i][0], self.h[i], self.xz[i][1]],
            dir: self.dir(i),
            length,
            size,
            hole,
            hole_at,
            difficulty: t,
        }
    }

    /// How far the road climbs over a hill.
    fn hill_rise(&self, o: &Obstacle) -> f32 {
        self.h[self.index_at(o.s + o.length)] - self.h[self.index_at(o.s)]
    }

    /// The final road profile: carved to the grade limit, but straight up the hills (as steep
    /// as they are, to `HILL_MAX_GRADE`), level across bridges, beams, gaps and jumps.
    fn build_profile(&mut self, natural: &[f32]) {
        let n = self.xz.len();
        let gentle = path::moving_average(natural, 20);
        let tight = path::moving_average(natural, 4);
        let mut target = gentle.clone();
        let mut limits = vec![MAX_GRADE * SAMPLE; n];
        for o in self
            .obstacles
            .iter()
            .filter(|o| o.kind == ObstacleKind::Hill)
        {
            let (a, b) = (self.index_at(o.s), self.index_at(o.s + o.length));
            for i in a.saturating_sub(15)..(b + 15).min(n) {
                let k = if i < a {
                    1.0 - (a - i) as f32 / 15.0
                } else if i > b {
                    1.0 - (i - b) as f32 / 15.0
                } else {
                    1.0
                };
                target[i] = gentle[i] + (tight[i] - gentle[i]) * k;
                limits[i] = HILL_MAX_GRADE * SAMPLE;
            }
        }
        path::limit_grade(&mut target, &limits);
        self.h = target;
        // Level where the RV must meet a structure (or a lip) square on, and through a ford
        // (banks and all): those stretches are pinned, and the road between them eases in and
        // out at the grade limit.
        let mut pinned = vec![false; n];
        let mut spans = Vec::new();
        for o in &self.obstacles {
            if matches!(
                o.kind,
                ObstacleKind::Gap
                    | ObstacleKind::Bridge
                    | ObstacleKind::Beams
                    | ObstacleKind::Jump
                    | ObstacleKind::Ford
            ) {
                let (before, after) = match o.kind {
                    ObstacleKind::Jump => (RUN_UP * 0.4, 8.0),
                    ObstacleKind::Ford => (RIVER_BANK + 12.0, RIVER_BANK + 12.0),
                    _ => (8.0, 8.0),
                };
                let (a, b) = (
                    self.index_at(o.s - o.length * 0.5 - before),
                    self.index_at(o.s + o.length * 0.5 + after),
                );
                spans.push((a, b, self.h[self.index_at(o.s)]));
            }
        }
        // The camp sits in a level clearing, with a level stretch to get going on.
        spans.push((0, self.index_at(CAMP_LEVEL), self.h[self.index_at(30.0)]));
        // Each level must be reachable from the one before at the grade limit.
        spans.sort_by_key(|x| x.0);
        for k in 1..spans.len() {
            let (prev_b, prev_level) = (spans[k - 1].1, spans[k - 1].2);
            let a = spans[k].0.max(prev_b);
            let budget: f32 = limits[prev_b..a].iter().sum::<f32>() * 0.98;
            spans[k].2 = spans[k].2.clamp(prev_level - budget, prev_level + budget);
        }
        for (a, b, level) in spans {
            self.h[a..=b].fill(level);
            pinned[a..=b].fill(true);
        }
        for i in 1..n {
            if !pinned[i] {
                let m = limits[i - 1];
                self.h[i] = self.h[i].clamp(self.h[i - 1] - m, self.h[i - 1] + m);
            }
        }
        for i in (0..n - 1).rev() {
            if !pinned[i] {
                let m = limits[i];
                self.h[i] = self.h[i].clamp(self.h[i + 1] - m, self.h[i + 1] + m);
            }
        }
        // Everything placed so far takes its height from the final profile.
        for o in &mut self.obstacles {
            let i = ((o.s / SAMPLE).round() as usize).min(n - 1);
            o.pos[1] = self.h[i];
        }
        for p in &mut self.pads {
            let i = ((p.s / SAMPLE).round() as usize).min(n - 1);
            p.pos[1] = self.h[i];
        }
    }

    /// Obstacles that reshape the road's own profile: ledges, humps and jumps.
    fn stamp_obstacles(&mut self) {
        let n = self.h.len();
        for o in self.obstacles.clone() {
            match o.kind {
                ObstacleKind::Ledge => {
                    // The road beyond the face is raised: it rejoins the natural profile over a
                    // long gentle ramp.
                    let i0 = self.index_at(o.s + o.length * 0.5);
                    let ramp = (o.size / (MAX_GRADE * 0.8 * SAMPLE)) as usize;
                    let plateau = 12;
                    for k in 0..(plateau + ramp) {
                        let idx = i0 + k;
                        if idx >= n {
                            break;
                        }
                        let f = if k < plateau {
                            1.0
                        } else {
                            1.0 - (k - plateau) as f32 / ramp as f32
                        };
                        self.h[idx] += o.size * f;
                    }
                }
                ObstacleKind::Climb => {
                    // A hump whose steepest part is ~25-30 %.
                    let i0 = self.index_at(o.s - o.length * 0.5);
                    let steps = (o.length / SAMPLE) as usize;
                    for k in 0..=steps {
                        let idx = i0 + k;
                        if idx >= n {
                            break;
                        }
                        let u = k as f32 / steps as f32;
                        let w = if u < 0.5 {
                            smoothstep(0.0, 0.5, u)
                        } else {
                            smoothstep(1.0, 0.5, u)
                        };
                        self.h[idx] += o.size * w;
                    }
                }
                ObstacleKind::Jump => {
                    // A kicker up to the lip, and the far side a little lower, easing back.
                    let lip = o.s - o.length * 0.5;
                    let (k0, k1) = (self.index_at(lip - KICKER[1]), self.index_at(lip));
                    for idx in k0..=k1 {
                        let u = (idx - k0) as f32 / (k1 - k0).max(1) as f32;
                        self.h[idx] += KICKER[0] * u;
                    }
                    let far = self.index_at(o.s + o.length * 0.5);
                    let ease = (60.0 / SAMPLE) as usize;
                    for k in 0..ease {
                        let idx = far + k;
                        if idx >= n {
                            break;
                        }
                        self.h[idx] -=
                            LANDING_DROP * (1.0 - smoothstep(0.0, 1.0, k as f32 / ease as f32));
                    }
                }
                _ => {}
            }
        }
    }

    /// What must lie near an obstacle for it to be solvable: planks (2-3, off in the trees)
    /// and boulders to winch from.
    fn place_supplies(&mut self, rng: &mut Pcg32, terrain: &TerrainGen) {
        for o in self.obstacles.clone() {
            let (a, b) = (rng.next_f32(), rng.next_f32());
            match o.kind {
                ObstacleKind::Gap | ObstacleKind::Bridge | ObstacleKind::Ice => {
                    let back = match o.kind {
                        ObstacleKind::Ice => o.length + ICE_RAMP + 8.0 + 10.0 * b,
                        _ => o.length * 0.5 + 12.0 + 26.0 * b,
                    };
                    let count = if o.kind == ObstacleKind::Gap && a < 0.5 {
                        2
                    } else {
                        3
                    };
                    let p = self.stash_spot(terrain, o.s - back, 7.0 + 7.0 * a, a);
                    self.supplies.push(Supply {
                        kind: SupplyKind::Planks,
                        pos: p,
                        yaw_dir: self.dir(self.index_at((o.s - back).max(0.0))),
                        count,
                    });
                }
                _ => {}
            }
            let anchors: &[(f32, f32)] = match o.kind {
                // (arc length from the obstacle's s, side)
                ObstacleKind::Ledge => &[(12.0, 1.0)],
                ObstacleKind::Ice => &[(o.length + ICE_RAMP + 10.0, -1.0)],
                ObstacleKind::Beams => &[(o.length * 0.5 + 14.0, 1.0)],
                ObstacleKind::Hill => &[(o.length * 0.5, 1.0), (o.length + 8.0, -1.0)],
                _ => &[],
            };
            for &(ds, side) in anchors {
                let side = if b < 0.5 { side } else { -side };
                let j = self.index_at(o.s + ds);
                let d = self.dir(j);
                let off = ROAD_HALF_WIDTH + 2.5;
                self.supplies.push(Supply {
                    kind: SupplyKind::Anchor,
                    pos: [
                        self.xz[j][0] - d[1] * side * off,
                        self.h[j],
                        self.xz[j][1] + d[0] * side * off,
                    ],
                    yaw_dir: d,
                    count: 1,
                });
            }
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

    /// At the foot of each hill, a track heads off downhill: the easy way, to nowhere.
    fn place_spurs(&mut self, terrain: &TerrainGen) {
        for o in self
            .obstacles
            .clone()
            .iter()
            .filter(|o| o.kind == ObstacleKind::Hill)
        {
            let from = o.s - 8.0;
            let i = self.index_at(from);
            let d = self.dir(i);
            // Towards whichever way falls away most (it must fall away).
            let mut best: Option<(f32, [f32; 2])> = None;
            for side in [-1.0, 1.0] {
                for angle in [0.5, 0.75, 1.0, 1.25, 1.5] {
                    let sd = path::rotate(d, angle * side);
                    let fall = [60.0, 120.0]
                        .iter()
                        .map(|u| {
                            terrain.height_m(self.xz[i][0] + sd[0] * u, self.xz[i][1] + sd[1] * u)
                        })
                        .fold(f32::NEG_INFINITY, f32::max);
                    if best.is_none_or(|(f, _)| fall < f) {
                        best = Some((fall, sd));
                    }
                }
            }
            let Some((fall, sd)) = best else { continue };
            if fall > self.h[i] - 2.0 {
                continue;
            }
            let len = 130.0;
            let count = (len / SAMPLE) as usize;
            let xz: Vec<[f32; 2]> = (0..=count)
                .map(|k| {
                    let u = k as f32 * SAMPLE;
                    // Curving gently away as it goes.
                    let bend = path::rotate(
                        sd,
                        0.002
                            * u
                            * if sd[0] * d[1] - sd[1] * d[0] > 0.0 {
                                -1.0
                            } else {
                                1.0
                            },
                    );
                    [self.xz[i][0] + bend[0] * u, self.xz[i][1] + bend[1] * u]
                })
                .collect();
            let natural: Vec<f32> = xz.iter().map(|p| terrain.height_m(p[0], p[1])).collect();
            let mut h = path::moving_average(&natural, 8);
            h[0] = self.h[i];
            path::limit_grade(&mut h[..], &vec![MAX_GRADE * SAMPLE; count + 1]);
            // Pin the start to the road (limit_grade may have moved it).
            let start = self.h[i];
            for (k, v) in h.iter_mut().enumerate() {
                let pin = 1.0 - smoothstep(0.0, 12.0, k as f32);
                *v += (start - *v) * pin;
            }
            let ok = xz
                .iter()
                .enumerate()
                .skip(12)
                .all(|(_, p)| self.min_road_distance(p[0], p[1], from, 400.0) > 12.0)
                && self.obstacles.iter().all(|x| {
                    x.s == o.s || dist2(x.pos, [xz[count][0], 0.0, xz[count][1]]) > 150.0 * 150.0
                })
                && self.pads.iter().all(|pad| {
                    xz.iter()
                        .all(|p| dist2(pad.pos, [p[0], 0.0, p[1]]) > 60.0 * 60.0)
                });
            if !ok {
                continue;
            }
            let (mut lo, mut hi) = ([f32::INFINITY; 2], [f32::NEG_INFINITY; 2]);
            for p in &xz {
                lo = [lo[0].min(p[0]), lo[1].min(p[1])];
                hi = [hi[0].max(p[0]), hi[1].max(p[1])];
            }
            let m = 260.0;
            self.spurs.push(Spur {
                from_s: from,
                xz,
                h,
                bounds: [lo[0] - m, lo[1] - m, hi[0] + m, hi[1] + m],
            });
        }
    }

    /// Ponds in the bayou and frozen lakes in the mountains, off to the sides of the road
    /// where the valley's wide.
    fn place_lakes(&mut self, world_seed: u64, terrain: &TerrainGen) {
        let mut rng = Pcg32::new(sub_seed(world_seed, "route.lakes", 0, 0), 7);
        let mut s = 120.0;
        while s < self.length - 60.0 {
            let (chance, side_roll, radius, offset) = (
                rng.next_f32(),
                rng.next_f32(),
                rng.range_f32(12.0, 30.0),
                rng.range_f32(8.0, 40.0),
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
            if off + radius > self.walls.floor_at(s) + 20.0 {
                continue;
            }
            let c = [p[0] + n[0] * off, p[1] + n[1] * off];
            if self.min_road_distance(c[0], c[1], s, radius + 120.0)
                < radius + LAKE_BANK + REACH + 2.0
                || !self.clear_of_features(c, radius + 20.0)
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
                rng.range_f32(4.0, 24.0),
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
            if self.min_road_distance(c[0], c[1], s, 150.0) < CAVE_RADIUS + CAVE_BLEND + REACH
                || !self.clear_of_features(c, CAVE_RADIUS + 15.0)
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

    /// Places worth a look where the valley's wide: a cabin, a fire lookout tower, a wreck, a
    /// hill with a view.
    fn place_pois(&mut self, world_seed: u64, terrain: &TerrainGen) {
        let mut rng = Pcg32::new(sub_seed(world_seed, "route.pois", 0, 0), 17);
        let mut s = 320.0;
        while s < self.length - 200.0 {
            let (kind_roll, side_roll, off_roll) = (rng.next_f32(), rng.next_f32(), rng.next_f32());
            s += rng.range_f32(260.0, 420.0);
            let floor = self.walls.floor_at(s);
            if floor < 75.0 {
                continue;
            }
            let kind = if kind_roll < 0.3 {
                PoiKind::Cabin
            } else if kind_roll < 0.5 {
                PoiKind::Tower
            } else if kind_roll < 0.75 {
                PoiKind::Wreck
            } else {
                PoiKind::Lookout
            };
            let radius = match kind {
                PoiKind::Cabin => 11.0,
                PoiKind::Tower => 8.0,
                PoiKind::Wreck => 7.0,
                PoiKind::Lookout => 30.0,
            };
            let i = self.index_at(s);
            let side = if side_roll < 0.5 { 1.0 } else { -1.0 };
            let d = self.dir(i);
            let n = [-d[1] * side, d[0] * side];
            let off = (REACH + radius + 8.0 + off_roll * 40.0).min(floor - radius - 6.0);
            let c = [self.xz[i][0] + n[0] * off, self.xz[i][1] + n[1] * off];
            if off < REACH + radius + 6.0
                || self.min_road_distance(c[0], c[1], s, 400.0) < REACH + radius + 4.0
                || !self.clear_of_features(c, radius + 25.0)
                || self.obstacles.iter().any(|o| {
                    let (a, b) = o.extent();
                    s > a - 120.0 && s < b + 120.0
                })
            {
                continue;
            }
            self.pois.push(Poi {
                kind,
                pos: [c[0], terrain.height_m(c[0], c[1]), c[1]],
                dir: [-n[0], -n[1]],
                radius,
            });
        }
    }

    /// Whether a spot is clear of the stops, lakes, caves, places and spurs by `r` metres.
    fn clear_of_features(&self, c: [f32; 2], r: f32) -> bool {
        let clear =
            |q: [f32; 3], extra: f32| dist2(q, [c[0], 0.0, c[1]]) > (r + extra) * (r + extra);
        self.pads.iter().all(|p| clear(p.pos, 30.0))
            && self
                .obstacles
                .iter()
                .all(|o| clear(o.pos, RIVER_HALF.min(40.0)))
            && self
                .lakes
                .iter()
                .all(|l| clear(l.pos, l.radius + LAKE_BANK))
            && self
                .caves
                .iter()
                .all(|cv| clear(cv.pos, CAVE_RADIUS + 10.0))
            && self.pois.iter().all(|p| clear(p.pos, p.radius + 10.0))
            && self
                .spurs
                .iter()
                .all(|sp| sp.distance(c[0], c[1]) > r + 12.0)
    }

    fn collect_bays(&self) -> Vec<[f32; 3]> {
        let mut out = Vec::new();
        for l in &self.lakes {
            out.push([l.pos[0], l.pos[2], l.radius + LAKE_BANK + BAY]);
        }
        for c in &self.caves {
            out.push([c.pos[0], c.pos[2], CAVE_RADIUS + CAVE_BLEND + BAY]);
        }
        for p in &self.pois {
            out.push([p.pos[0], p.pos[2], p.radius + BAY]);
        }
        out
    }

    /// Bays the valley opens into: (x, z, radius).
    pub fn bays(&self) -> &[[f32; 3]] {
        &self.bays
    }

    // --- geometry helpers ---------------------------------------------------------------------

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
        // Everything the route shapes (pads, rivers, ravines, lakes, caves, places, spurs)
        // lies within this margin of the road.
        let m = 330.0;
        self.bounds = [lo[0] - m, lo[1] - m, hi[0] + m, hi[1] + m];
    }

    pub fn index_at(&self, s: f32) -> usize {
        ((s.max(0.0) / SAMPLE).round() as usize).min(self.xz.len() - 1)
    }

    /// Unit direction of travel (x, z) at sample `i`.
    pub fn dir(&self, i: usize) -> [f32; 2] {
        path::dir(&self.xz, i)
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

    /// How far outside the valley floor a point is (metres; <= 0 on it).
    pub fn outside_valley(&self, x: f32, z: f32) -> f32 {
        self.walls.outside(self, x, z)
    }

    /// Floor half-width of the valley at arc length `s`.
    pub fn floor_at(&self, s: f32) -> f32 {
        self.walls.floor_at(s)
    }

    // --- the ground ------------------------------------------------------------------------

    /// Terrain height with the road, obstacle stamps, pads, features and the valley's walls
    /// applied on top of `natural`.
    pub fn shape(&self, x: f32, z: f32, natural: f32) -> f32 {
        if !self.in_bounds(x, z) {
            return natural + self.walls.lift(self, x, z);
        }
        let mut h = natural;
        for pad in &self.pads {
            let (along, across) = local(pad.pos, pad.dir, x, z);
            let ex = (along.abs() - PAD_HALF[0]).max(0.0);
            let ez = (across.abs() - PAD_HALF[1]).max(0.0);
            let e = (ex * ex + ez * ez).sqrt();
            if e < PAD_BLEND {
                h += (pad.pos[1] - h) * smoothstep(PAD_BLEND, 0.0, e);
            }
        }
        // Lookout hills, cave and place clearings.
        for p in &self.pois {
            let (dx, dz) = (x - p.pos[0], z - p.pos[2]);
            let d = (dx * dx + dz * dz).sqrt();
            if p.kind == PoiKind::Lookout {
                if d < p.radius {
                    h += LOOKOUT_HEIGHT * smoothstep(p.radius, LOOKOUT_TOP, d);
                }
            } else if d < p.radius + 8.0 {
                h += (p.pos[1] - h) * smoothstep(p.radius + 8.0, p.radius, d);
            }
        }
        for c in &self.caves {
            let (dx, dz) = (x - c.pos[0], z - c.pos[2]);
            let d = (dx * dx + dz * dz).sqrt();
            if d < CAVE_RADIUS + CAVE_BLEND {
                h += (c.pos[1] - h) * smoothstep(CAVE_RADIUS + CAVE_BLEND, CAVE_RADIUS, d);
            }
        }
        // Side tracks, then the road (always level across, pads or not).
        for spur in &self.spurs {
            if let Some((d, sh)) = spur.nearest(x, z)
                && d < SPUR_HALF_WIDTH + SHOULDER
            {
                h += (sh - h) * smoothstep(SPUR_HALF_WIDTH + SHOULDER, SPUR_HALF_WIDTH + 0.5, d);
            }
        }
        if let Some(r) = self.near(x, z) {
            let w = smoothstep(
                ROAD_HALF_WIDTH + SHOULDER,
                ROAD_HALF_WIDTH + 0.5,
                r.distance,
            );
            h += (r.height - h) * w;
        }
        for o in &self.obstacles {
            h = self.stamp(o, x, z, h);
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
        h + self.walls.lift(self, x, z)
    }

    /// One obstacle's shape in the ground at a point.
    fn stamp(&self, o: &Obstacle, x: f32, z: f32, mut h: f32) -> f32 {
        let (along, across) = local(o.pos, o.dir, x, z);
        if along.abs() > 150.0 || across.abs() > 150.0 {
            return h;
        }
        match o.kind {
            ObstacleKind::Gap | ObstacleKind::Bridge | ObstacleKind::Beams | ObstacleKind::Jump => {
                // A trench right across the valley, into its walls. Crisp at the road (where
                // planks, bridges and landings meet it), softer off it so the 1 m terrain grid
                // doesn't saw its edges (still far too steep to climb).
                let half = o.length * 0.5
                    + if o.kind == ObstacleKind::Gap {
                        0.5
                    } else {
                        0.0
                    };
                // First the ground round it is brought to the road's level (so it's a clean
                // cut across level ground, as deep off the road as on it)...
                if along.abs() < half + 16.0 && across.abs() < SIDE_REACH {
                    let flat = smoothstep(half + 16.0, half + 5.0, along.abs())
                        * smoothstep(SIDE_REACH, SIDE_REACH - 10.0, across.abs());
                    // (A jump's kicker is part of the road: leave the road be there.)
                    let keep = if o.kind == ObstacleKind::Jump {
                        smoothstep(
                            ROAD_HALF_WIDTH + SHOULDER,
                            ROAD_HALF_WIDTH + 0.5,
                            across.abs(),
                        )
                    } else {
                        0.0
                    };
                    h += (o.pos[1] - h) * flat * (1.0 - keep);
                }
                // ...then the trench.
                if along.abs() < half + 3.0 && across.abs() < SIDE_REACH {
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
                // The raised road profile makes the step. Undo its 2 m interpolation just below
                // the face so it's sheer, and lift the ground either side so there's no way round.
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
                        * smoothstep(ROAD_HALF_WIDTH + 1.5, ROAD_HALF_WIDTH - 1.0, across.abs());
                }
            }
            ObstacleKind::Climb | ObstacleKind::Hill => {}
            ObstacleKind::Ford => {
                // The river's channel, straight across: shallow where the road fords it, deep
                // off to the sides, banks a little above the water.
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
        h
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

    /// Whether a point is somewhere nothing should grow or lie: a pad, a cave or place
    /// clearing (a lookout's top), a lake, a river, where planks lie.
    pub fn blocked(&self, x: f32, z: f32, margin: f32) -> bool {
        if !self.in_bounds(x, z) {
            return false;
        }
        if self.on_pad(x, z, margin) {
            return true;
        }
        let near = |p: [f32; 3], r: f32| dist2(p, [x, 0.0, z]) < r * r;
        self.caves.iter().any(|c| near(c.pos, CAVE_RADIUS + margin))
            || self.pois.iter().any(|p| {
                near(
                    p.pos,
                    if p.kind == PoiKind::Lookout {
                        LOOKOUT_TOP
                    } else {
                        p.radius
                    } + margin,
                )
            })
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

    /// How much a point is road surface (1 on the road, fading out over the edge; a side
    /// track is fainter).
    pub fn road_at(&self, x: f32, z: f32) -> f32 {
        if !self.in_bounds(x, z) {
            return 0.0;
        }
        let mut w = self.near(x, z).map_or(0.0, |r| {
            smoothstep(ROAD_HALF_WIDTH + 1.2, ROAD_HALF_WIDTH - 0.4, r.distance)
        });
        for spur in &self.spurs {
            let d = spur.distance(x, z);
            w = w.max(0.55 * smoothstep(SPUR_HALF_WIDTH + 1.0, SPUR_HALF_WIDTH - 0.6, d));
        }
        for pad in &self.pads {
            let (along, across) = local(pad.pos, pad.dir, x, z);
            if along.abs() < PAD_HALF[0] && across.abs() < PAD_HALF[1] {
                w = w.max(0.8);
            }
        }
        w
    }

    /// Distance from the road (or a side track) centreline, or infinity if well away.
    pub fn distance(&self, x: f32, z: f32) -> f32 {
        if !self.in_bounds(x, z) {
            return f32::INFINITY;
        }
        let road = self.near(x, z).map_or(f32::INFINITY, |r| r.distance);
        self.spurs.iter().fold(road, |d, s| d.min(s.distance(x, z)))
    }

    /// Whether a point is on a pad (kept clear of props).
    pub fn on_pad(&self, x: f32, z: f32, margin: f32) -> bool {
        self.pads.iter().any(|pad| {
            let (along, across) = local(pad.pos, pad.dir, x, z);
            along.abs() < PAD_HALF[0] + margin && across.abs() < PAD_HALF[1] + margin
        })
    }

    // --- solvability ------------------------------------------------------------------------

    /// Static solvability checks (PLAN.md §5.4). Returns the problems found.
    pub fn validate(&self) -> Vec<String> {
        let mut problems = Vec::new();
        let hill_at = |s: f32| {
            self.obstacles.iter().any(|o| {
                o.kind == ObstacleKind::Hill && s > o.s - 40.0 && s < o.s + o.length + 40.0
            })
        };
        for (i, w) in self.h.windows(2).enumerate() {
            let s = i as f32 * SAMPLE;
            let limit = if hill_at(s) {
                HILL_MAX_GRADE
            } else {
                MAX_GRADE
            };
            let excused = self.obstacles.iter().any(|o| {
                matches!(
                    o.kind,
                    ObstacleKind::Ledge | ObstacleKind::Climb | ObstacleKind::Jump
                ) && s > o.s - o.length - KICKER[1] - 4.0 * SAMPLE
                    && s < o.s + 120.0
            });
            if !excused && (w[1] - w[0]).abs() > limit * SAMPLE + 1e-3 {
                problems.push(format!(
                    "road too steep at {s:.0} m ({:.2} m/sample)",
                    (w[1] - w[0]).abs()
                ));
                break;
            }
        }
        let planks_near = |p: [f32; 3], r: f32, need: u8| {
            self.supplies
                .iter()
                .any(|s| s.kind == SupplyKind::Planks && s.count >= need && dist2(s.pos, p) < r * r)
        };
        let anchor_near = |p: [f32; 3], r: f32| {
            self.supplies
                .iter()
                .any(|s| s.kind == SupplyKind::Anchor && dist2(s.pos, p) < r * r)
        };
        for o in &self.obstacles {
            match o.kind {
                ObstacleKind::Gap => {
                    if !planks_near(o.pos, 60.0, 2) {
                        problems.push(format!("gap at {:.0} m has no planks near it", o.s));
                    }
                    if o.length > PLANK_LENGTH - 0.6 || o.length < 3.5 {
                        problems.push(format!(
                            "gap at {:.0} m is wider than a plank can span",
                            o.s
                        ));
                    }
                }
                ObstacleKind::Bridge => {
                    if !planks_near(o.pos, o.length * 0.5 + 50.0, 2) {
                        problems.push(format!("bridge at {:.0} m has no planks near it", o.s));
                    }
                    if o.hole > PLANK_LENGTH - 0.6 || o.hole < 3.0 {
                        problems.push(format!(
                            "bridge at {:.0} m has a hole planks can't span",
                            o.s
                        ));
                    }
                    if o.hole_at.abs() + o.hole * 0.5 > o.length * 0.5 - 4.0 {
                        problems.push(format!(
                            "bridge at {:.0} m: the hole is too near an end",
                            o.s
                        ));
                    }
                }
                ObstacleKind::Beams => {
                    if o.length > 15.0 {
                        problems.push(format!("beams at {:.0} m are too long", o.s));
                    }
                }
                ObstacleKind::Jump => {
                    if o.length > 7.5 || o.length < 5.0 {
                        problems.push(format!("jump at {:.0} m is {:.1} m wide", o.s, o.length));
                    }
                    let lip = o.s - o.length * 0.5;
                    let (a, b) = (
                        self.index_at(lip - RUN_UP),
                        self.index_at(lip - KICKER[1] - 1.0),
                    );
                    let rise = self.h[b] - self.h[a];
                    if rise > 0.04 * RUN_UP || !path::is_straight(&self.xz, a, b, 0.995) {
                        problems.push(format!(
                            "jump at {:.0} m has no straight, level run-up ({rise:.1} m)",
                            o.s
                        ));
                    }
                }
                ObstacleKind::Ledge => {
                    if !anchor_near(o.pos, 30.0) {
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
                    if !anchor_near(o.pos, reach) || !planks_near(o.pos, reach + 10.0, 2) {
                        problems.push(format!("ice at {:.0} m has no winch anchor or planks", o.s));
                    }
                }
                ObstacleKind::Hill => {
                    if self.hill_rise(o) < HILL_RISE * 0.75 {
                        problems.push(format!(
                            "hill at {:.0} m only climbs {:.1} m",
                            o.s,
                            self.hill_rise(o)
                        ));
                    }
                    let top = [
                        self.xz[self.index_at(o.s + o.length)][0],
                        0.0,
                        self.xz[self.index_at(o.s + o.length)][1],
                    ];
                    if !anchor_near(top, 40.0) {
                        problems.push(format!("hill at {:.0} m has no anchor near the top", o.s));
                    }
                }
                _ => {}
            }
            // Where there's no way round: the valley pinches in.
            if self.floor_at(o.s) > FLOOR_NARROW + 1.0 {
                problems.push(format!(
                    "{:?} at {:.0} m can be driven round ({:.0} m of floor)",
                    o.kind,
                    o.s,
                    self.floor_at(o.s)
                ));
            }
        }
        for pair in self.obstacles.windows(2) {
            if pair[0].extent().1 + 80.0 > pair[1].extent().0 {
                problems.push(format!(
                    "obstacles at {:.0} and {:.0} m are too close",
                    pair[0].s, pair[1].s
                ));
            }
        }
        // Far-apart stretches of road stay apart (no short cuts between them).
        let every = 20;
        let far = (path::SEPARATION_ARC / SAMPLE) as usize;
        'outer: for i in (0..self.xz.len()).step_by(every) {
            for j in ((i + far)..self.xz.len()).step_by(every) {
                if dist2(
                    [self.xz[i][0], 0.0, self.xz[i][1]],
                    [self.xz[j][0], 0.0, self.xz[j][1]],
                ) < path::SEPARATION * path::SEPARATION * 0.9
                {
                    problems.push(format!(
                        "the road comes back near itself at {:.0} m",
                        i as f32 * SAMPLE
                    ));
                    break 'outer;
                }
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
        for p in &self.pois {
            if self.min_road_distance(p.pos[0], p.pos[2], self.near_s(p.pos), 400.0)
                < p.radius + REACH
            {
                problems.push(format!(
                    "{:?} at ({:.0}, {:.0}) is on the road",
                    p.kind, p.pos[0], p.pos[2]
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

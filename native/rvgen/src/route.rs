//! The trip (PLAN.md §5.1–5.4): a meandering road from the start camp to home, split into
//! segments that end at gas stations, with obstacles along it that get harder towards home.
//!
//! Everything is a pure function of the seed. The road is carved into the terrain (cut and
//! fill to a grade limit), obstacles stamp their own shapes into it (a washed-out gap, a ledge,
//! a steep climb, a mud hole), and flat pads are levelled for the camp, stations and home.
//! `Route::validate` checks the static solvability rules.

use std::collections::BTreeMap;

use crate::hash::sub_seed;
use crate::noise::smoothstep;
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
    pub length: f32,
    /// Samples near each grid cell (cells of `GRID` metres, keyed by cell).
    grid: BTreeMap<(i32, i32), Vec<u32>>,
    bounds: [f32; 4],
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
            grid: BTreeMap::new(),
            bounds: [0.0; 4],
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
                    route.place_obstacle(&mut rng, s, t);
                    since_breather += 1;
                }
            }
            s += rng.range_f32(150.0, 240.0);
        }

        route.build_grid();
        route
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

    fn place_obstacle(&mut self, rng: &mut Pcg32, s: f32, t: f32) {
        // Always draw the same values, whichever kind wins.
        let pick = rng.next_f32();
        let a = rng.next_f32();
        let b = rng.next_f32();
        // Weighted by how far into the trip it is: gentle mud and climbs early, then gaps
        // and ledges, which need tools (planks, the winch).
        let kind = if t < 0.25 {
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
                // Planks a little before the gap, off to the side of the road.
                let side = if a < 0.5 { 1.0 } else { -1.0 };
                let j = self.index_at((s - rng.range_f32(18.0, 30.0)).max(0.0));
                let n = [-self.dir(j)[1] * side, self.dir(j)[0] * side];
                let off = ROAD_HALF_WIDTH + 1.5;
                let p = [
                    self.xz[j][0] + n[0] * off,
                    self.h[j],
                    self.xz[j][1] + n[1] * off,
                ];
                self.supplies.push(Supply {
                    kind: SupplyKind::Planks,
                    pos: p,
                    yaw_dir: self.dir(j),
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
            ObstacleKind::Mud => {}
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
            return natural;
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
                    let half = o.length * 0.5 + 0.5;
                    if along.abs() < half + 1.0 && across.abs() < ROAD_HALF_WIDTH + SHOULDER + 12.0
                    {
                        let wall = smoothstep(half + 0.35, half - 0.15, along.abs());
                        let fade = smoothstep(
                            ROAD_HALF_WIDTH + SHOULDER + 12.0,
                            ROAD_HALF_WIDTH + SHOULDER + 4.0,
                            across.abs(),
                        );
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
                    if along > -face
                        && along < 30.0
                        && across.abs() < ROAD_HALF_WIDTH + SHOULDER + 10.0
                    {
                        let wing = smoothstep(
                            ROAD_HALF_WIDTH + SHOULDER + 10.0,
                            ROAD_HALF_WIDTH + 1.0,
                            across.abs(),
                        );
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
            }
        }
        h
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
                            && dist2(s.pos, o.pos) < 45.0 * 45.0
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
        if self.pads.first().map(|p| p.kind) != Some(PadKind::Camp)
            || self.pads.last().map(|p| p.kind) != Some(PadKind::Home)
        {
            problems.push("trip must start at camp and end at home".into());
        }
        problems
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
        let mut kinds = [0; 4];
        for seed in 0..200 {
            let r = route(seed, TripLength::Short);
            let problems = r.validate();
            assert!(problems.is_empty(), "seed {seed}: {problems:?}");
            for o in &r.obstacles {
                kinds[o.kind as usize] += 1;
            }
        }
        assert!(
            kinds.iter().all(|&k| k > 20),
            "every obstacle kind appears: {kinds:?}"
        );
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
    fn sin_cos_is_accurate() {
        for k in -9..=9 {
            let a = k as f32 * 0.1;
            let (s, c) = sin_cos(a);
            assert!((s - a.sin()).abs() < 1e-5 && (c - a.cos()).abs() < 1e-5);
        }
    }
}

//! The valley the road runs along. Its floor is wide and open between obstacles (room for
//! lakes, caves and places to look round), and pinches in at each obstacle so there's no
//! driving round it. Past the floor, walls rise too steeply to drive or climb, then ease back
//! to the natural ground far away. The valley is closed off behind the camp and past home,
//! and opens into bays round side places (lakes, caves, cabins...) and along side tracks.

use std::collections::BTreeMap;

use crate::noise::{perlin, smoothstep};

use super::{Route, SAMPLE};

/// Widest and narrowest the floor gets either side of the road (metres).
pub const FLOOR_WIDE: [f32; 2] = [70.0, 130.0];
/// The floor either side of the road at an obstacle.
pub const FLOOR_NARROW: f32 = 20.0;
/// Round the stops (the station pads reach ~35 m from the road).
pub const FLOOR_AT_STOPS: f32 = 46.0;
/// How far past an obstacle's own extent the pinch holds, and how long it takes to open out.
pub const PINCH_MARGIN: f32 = 25.0;
pub const PINCH_BLEND: f32 = 70.0;
/// A wall rises over this band past the floor.
pub const WALL_BAND: f32 = 12.0;
/// How far a wall rises above the ground it stands on (plus up to `WALL_HEIGHT_VARY`).
pub const WALL_HEIGHT: f32 = 24.0;
const WALL_HEIGHT_VARY: f32 = 12.0;
/// Past the wall's top, a crest, then the ground eases back to natural.
const WALL_FADE: [f32; 2] = [40.0, 100.0];
/// How far the foot of a wall wanders, and how craggy its top is (metres).
pub const WALL_WOBBLE: f32 = 4.0;
const WALL_CRAGS: f32 = 9.0;
/// Furthest from the road the valley changes anything.
pub const WALL_REACH: f32 = FLOOR_WIDE[1] + WALL_WOBBLE + WALL_BAND + WALL_FADE[1] + 1.0;
/// Road samples per segment of the coarse centreline the walls follow.
pub const WALL_STRIDE: usize = 4;
const WALL_GRID: f32 = 64.0;
/// A side track keeps this much floor either side of it.
pub const SPUR_ROOM: f32 = 16.0;

/// What the walls need, built once the road and its features are known.
#[derive(Clone, Debug, Default)]
pub struct Walls {
    /// Coarse centreline segments (start sample indices) within `WALL_REACH` of each cell.
    grid: BTreeMap<(i32, i32), Vec<u32>>,
    bounds: [f32; 4],
    /// Floor half-width at each coarse sample (every `WALL_STRIDE` road samples).
    floor: Vec<f32>,
    seed: u32,
}

impl Walls {
    pub fn build(route: &Route, seed: u32) -> Self {
        let mut walls = Walls {
            seed,
            ..Default::default()
        };
        let n = route.xz.len();
        // Floor widths: wide and wandering, pinched round obstacles, roomy at the stops.
        let coarse = n.div_ceil(WALL_STRIDE);
        walls.floor = (0..coarse)
            .map(|c| {
                let s = (c * WALL_STRIDE) as f32 * SAMPLE;
                let wander = (0.5 + 0.5 * perlin(seed ^ 0xf100, s / 420.0, 0.37)).clamp(0.0, 1.0);
                let mut w = FLOOR_WIDE[0] + (FLOOR_WIDE[1] - FLOOR_WIDE[0]) * wander;
                for o in &route.obstacles {
                    let (a, b) = o.extent();
                    let outside = (a - PINCH_MARGIN - s).max(s - b - PINCH_MARGIN).max(0.0);
                    let k = smoothstep(0.0, PINCH_BLEND, outside);
                    w = w.min(FLOOR_NARROW + (w - FLOOR_NARROW) * k);
                }
                for p in &route.pads {
                    if (p.s - s).abs() < 70.0 {
                        w = w.max(FLOOR_AT_STOPS);
                    }
                }
                w
            })
            .collect();
        let mut i = 0;
        while i + 1 < n {
            let (pa, pb) = (route.xz[i], route.xz[(i + WALL_STRIDE).min(n - 1)]);
            let c0 = cell_of(pa[0].min(pb[0]) - WALL_REACH, pa[1].min(pb[1]) - WALL_REACH);
            let c1 = cell_of(pa[0].max(pb[0]) + WALL_REACH, pa[1].max(pb[1]) + WALL_REACH);
            for cz in c0.1..=c1.1 {
                for cx in c0.0..=c1.0 {
                    walls.grid.entry((cx, cz)).or_default().push(i as u32);
                }
            }
            i += WALL_STRIDE;
        }
        let (mut lo, mut hi) = ([f32::INFINITY; 2], [f32::NEG_INFINITY; 2]);
        for p in route
            .xz
            .iter()
            .chain(route.spurs.iter().flat_map(|s| s.xz.iter()))
        {
            lo = [lo[0].min(p[0]), lo[1].min(p[1])];
            hi = [hi[0].max(p[0]), hi[1].max(p[1])];
        }
        // Bays (lakes, caves, places) can reach a little further out than the corridor.
        let m = WALL_REACH + 160.0;
        walls.bounds = [lo[0] - m, lo[1] - m, hi[0] + m, hi[1] + m];
        walls
    }

    pub fn in_bounds(&self, x: f32, z: f32) -> bool {
        let b = &self.bounds;
        x >= b[0] && z >= b[1] && x <= b[2] && z <= b[3]
    }

    /// Floor half-width at arc length `s`.
    pub fn floor_at(&self, s: f32) -> f32 {
        if self.floor.is_empty() {
            return FLOOR_WIDE[0];
        }
        let f = s / (WALL_STRIDE as f32 * SAMPLE);
        let i = (f.floor().max(0.0) as usize).min(self.floor.len() - 1);
        let j = (i + 1).min(self.floor.len() - 1);
        let t = (f - i as f32).clamp(0.0, 1.0);
        self.floor[i] + (self.floor[j] - self.floor[i]) * t
    }

    /// Distance to the coarse road centreline and the arc length there, or infinity beyond
    /// about `WALL_REACH`.
    pub fn road_distance(&self, route: &Route, x: f32, z: f32) -> (f32, f32) {
        let Some(list) = self.grid.get(&cell_of(x, z)) else {
            return (f32::INFINITY, 0.0);
        };
        let n = route.xz.len();
        let mut best = (f32::INFINITY, 0.0);
        for &i in list {
            let i = i as usize;
            let j = (i + WALL_STRIDE).min(n - 1);
            let (pa, pb) = (route.xz[i], route.xz[j]);
            let (ex, ez) = (pb[0] - pa[0], pb[1] - pa[1]);
            let len2 = (ex * ex + ez * ez).max(1e-6);
            let t = (((x - pa[0]) * ex + (z - pa[1]) * ez) / len2).clamp(0.0, 1.0);
            let (ox, oz) = (x - (pa[0] + ex * t), z - (pa[1] + ez * t));
            let d2 = ox * ox + oz * oz;
            if d2 < best.0 {
                best = (d2, (i as f32 + (j - i) as f32 * t) * SAMPLE);
            }
        }
        (best.0.sqrt(), best.1)
    }

    /// How far outside the valley floor a point is (metres; <= 0 on it).
    pub fn outside(&self, route: &Route, x: f32, z: f32) -> f32 {
        let (road, s) = self.road_distance(route, x, z);
        let mut out = if road.is_finite() {
            let wobble =
                WALL_WOBBLE * perlin(self.seed ^ 0xb0b, x * (1.0 / 40.0), z * (1.0 / 40.0));
            road - self.floor_at(s) + wobble
        } else {
            f32::INFINITY
        };
        let bay = |cx: f32, cz: f32, r: f32| {
            let (dx, dz) = (x - cx, z - cz);
            (dx * dx + dz * dz).sqrt() - r
        };
        for b in route.bays() {
            out = out.min(bay(b[0], b[1], b[2]));
        }
        for spur in &route.spurs {
            out = out.min(spur.distance(x, z) - SPUR_ROOM);
        }
        out
    }

    /// How much the walls lift the ground at a point: a steep rise just past the floor, a
    /// craggy crest, then easing back to the natural ground far away.
    pub fn lift(&self, route: &Route, x: f32, z: f32) -> f32 {
        if !self.in_bounds(x, z) {
            return 0.0;
        }
        let e = self.outside(route, x, z);
        if e <= 0.0 || e >= WALL_BAND + WALL_FADE[1] {
            return 0.0;
        }
        let rise = smoothstep(0.0, WALL_BAND, e);
        let fall = smoothstep(WALL_BAND + WALL_FADE[1], WALL_BAND + WALL_FADE[0], e);
        let n = (0.5 + 0.5 * perlin(self.seed ^ 0x5eed, x * (1.0 / 96.0), z * (1.0 / 96.0)))
            .clamp(0.0, 1.0);
        let crag = WALL_CRAGS
            * perlin(self.seed ^ 0xc4a6, x * (1.0 / 22.0), z * (1.0 / 22.0)).abs()
            * smoothstep(0.6 * WALL_BAND, WALL_BAND + 10.0, e);
        (WALL_HEIGHT + WALL_HEIGHT_VARY * n + crag) * rise * fall
    }
}

fn cell_of(x: f32, z: f32) -> (i32, i32) {
    (
        (x / WALL_GRID).floor() as i32,
        (z / WALL_GRID).floor() as i32,
    )
}

//! Finding the road: several candidate routes are walked east across the terrain, each
//! meandering its own way, and scored; the best becomes the trip. Also the curve helpers
//! (splines, resampling, smoothing, grade limits) the rest of the route uses.

use crate::hash::{sub_seed, sub_seed32};
use crate::noise::perlin;
use crate::rng::Pcg32;
use crate::terrain::TerrainGen;

use super::{SAMPLE, START};

/// Coarse walk step, metres.
const STEP: f32 = 20.0;
/// How many candidate routes are tried. The last `TAME` of them wind less and never break
/// into switchbacks, so there's always one that keeps clear of itself.
pub const CANDIDATES: u32 = 10;
const TAME: u32 = 3;
/// Widest heading off due east (radians): the road always makes progress east, so it never
/// doubles back or loops, but it can wind a long way north and south.
pub const MAX_HEADING: f32 = 1.3;
/// Heading of a switchback's legs, either side of east: steeper than the road ever meanders.
pub const SWITCHBACK_HEADING: f32 = 1.36;
/// Road points further apart than this along the road must be at least `SEPARATION` apart on
/// the ground, so neighbouring stretches never share a valley (no short cuts).
pub const SEPARATION_ARC: f32 = 700.0;
pub const SEPARATION: f32 = 340.0;

/// One candidate: its centreline (every `SAMPLE` metres), its switchbacks (arc length where
/// each starts and ends) and how good it is (lower is better).
pub struct Candidate {
    pub xz: Vec<[f32; 2]>,
    pub switchbacks: Vec<[f32; 2]>,
    pub score: f32,
}

/// Walks candidate `k` east for `total` metres of road.
///
/// Each step the walker picks, among a fan of headings, the one that best trades off staying
/// level (so the road contours round hills instead of ploughing through them), turning
/// gently, and following a meander: two octaves of noise, a broad sweep with tighter bends on
/// top. How hard it meanders is steered so the trip makes the eastward progress the world's
/// personality asks for (its sinuosity), and grows towards home. Where the land ahead rises
/// or falls too steeply to drive straight at, the road may break into switchbacks: a few
/// short legs zig-zagging across the slope.
pub fn candidate(world_seed: u64, k: u32, total: f32, terrain: &TerrainGen) -> Candidate {
    let p = *terrain.personality();
    let tame = k + TAME >= CANDIDATES;
    let mut rng = Pcg32::new(sub_seed(world_seed, "route.path", k as i64, 0), 11);
    let meander = sub_seed32(
        world_seed ^ (k as u64).wrapping_mul(0x9E37_79B9_7F4A_7C15),
        "route.meander",
    );
    let amplitude = rng.range_f32(0.6, 1.0) * if tame { 0.8 } else { 1.0 };
    let wavelength = rng.range_f32(450.0, 850.0) * p.bend_length;
    let lean = rng.range_f32(-0.25, 0.25); // Some routes drift north or south overall.
    let mut coarse = vec![START];
    let mut heading: f32 = rng.range_f32(-0.4, 0.4);
    let steps = (total / STEP) as usize + 6;
    // Now and then the road runs dead straight for a while (where bridges and jumps go). It
    // always leaves the camp straight, so there's room to get going.
    let mut hold = rng.range_f32(12.0, 15.0) as usize;
    let mut until_hold = rng.range_f32(8.0, 30.0) as usize;
    // Switchbacks: legs left, steps left of this leg, which way it heads, steps till the next.
    let (mut legs, mut leg_left, mut side) = (0usize, 0usize, 1.0f32);
    let mut until_switchback = 30usize;
    let mut switchbacks: Vec<[f32; 2]> = Vec::new();
    for step in 0..steps {
        let [x, z] = *coarse.last().unwrap();
        let s = step as f32 * STEP;
        let t = (s / total).min(1.0);
        if hold > 0 {
            hold -= 1;
            let (dx, dz) = dir_of(heading);
            coarse.push([x + dx * STEP, z + dz * STEP]);
            continue;
        }
        if legs > 0 {
            // Swing hard onto the leg's heading, hold it, then swing back the other way.
            let want = side * SWITCHBACK_HEADING;
            heading += (want - heading).clamp(-0.5, 0.5);
            leg_left -= 1;
            if leg_left == 0 {
                legs -= 1;
                side = -side;
                leg_left = rng.range_f32(6.0, 9.0) as usize;
                if legs == 0 {
                    switchbacks.last_mut().unwrap()[1] = s + STEP;
                }
            }
            let (dx, dz) = dir_of(heading);
            coarse.push([x + dx * STEP, z + dz * STEP]);
            continue;
        }
        if until_hold == 0 {
            hold = rng.range_f32(8.0, 13.0) as usize;
            until_hold = (rng.range_f32(8.0, 24.0) * (1.2 - 0.4 * t)) as usize;
        } else {
            until_hold -= 1;
        }
        let h0 = terrain.height_m(x, z);
        // Switchbacks start where the way east is too steep to drive straight at, and now
        // and then just for the fun of it; more of them towards home.
        let roll = rng.next_f32();
        if until_switchback > 0 {
            until_switchback -= 1;
        } else if !tame && s < total - 500.0 {
            let ahead = terrain.height_m(x + 120.0, z) - h0;
            let steep = ahead.abs() > super::MAX_GRADE * 120.0;
            let chance = p.switchbacks * (0.5 + t) * if steep { 0.3 } else { 0.012 };
            if roll < chance {
                legs = 2 + rng.below(3) as usize;
                leg_left = rng.range_f32(6.0, 9.0) as usize;
                // Start by turning the way that's the smaller swing.
                side = if heading >= 0.0 { 1.0 } else { -1.0 };
                until_switchback = (rng.range_f32(30.0, 55.0) * (1.5 - p.switchbacks)) as usize;
                until_hold = until_hold.max(6);
                switchbacks.push([s, s]);
                let (dx, dz) = dir_of(heading);
                coarse.push([x + dx * STEP, z + dz * STEP]);
                continue;
            }
        }
        // Meander harder when the road's been making too much progress east, and ease off
        // when it's made too little: that pins the trip's sinuosity to the world's.
        // (Measured as the crow flies from the camp, so drifting north-east in a straight
        // line doesn't count as winding.)
        let (cx, cz) = (x - START[0], z - START[1]);
        let made = 0.97 * (cx * cx + cz * cz).sqrt() / s.max(300.0);
        // (It aims to be a little ahead early on, so the winding saved up is spent late.)
        let aim = p.directness + 0.08 * (1.0 - t);
        let steer = (1.0 + 9.0 * (made - aim)).clamp(0.3, 3.5);
        let swing = amplitude * steer * (0.7 + 0.6 * t);
        let wave = 0.7 * perlin(meander, s / wavelength, 0.5 + k as f32 * 3.7)
            + 0.45 * perlin(meander ^ 0x51ab, s * 3.0 / wavelength, 7.5 + k as f32 * 1.3);
        let target = (lean + swing * 1.6 * wave).clamp(-MAX_HEADING, MAX_HEADING);
        let mut best = (f32::INFINITY, heading);
        for j in 0..7 {
            let cand = (heading + (j as f32 - 3.0) * 0.1 + rng.range_f32(-0.03, 0.03))
                .clamp(-MAX_HEADING, MAX_HEADING);
            let (dx, dz) = dir_of(cand);
            let h1 = terrain.height_m(x + dx * STEP, z + dz * STEP);
            // Look further on too, so the road goes round a hill, not up to its foot.
            let h3 = terrain.height_m(x + dx * STEP * 3.0, z + dz * STEP * 3.0);
            let cost = (h1 - h0).abs()
                + 0.2 * (h3 - h0).abs()
                + (cand - heading).abs() * 2.0
                + (cand - target).abs() * 1.8;
            if cost < best.0 {
                best = (cost, cand);
            }
        }
        heading = best.1;
        let (dx, dz) = dir_of(heading);
        coarse.push([x + dx * STEP, z + dz * STEP]);
    }
    if let Some(last) = switchbacks.last_mut()
        && last[1] <= last[0]
    {
        last[1] = total;
    }
    let xz = resample(&catmull_rom(&coarse, 8), SAMPLE, total + 40.0);
    // A road that winds as the world's character says (so the biomes change where the
    // stations are), with the switchbacks it calls for, beats a tidier one that doesn't.
    let made = (xz[xz.len() - 1][0] - xz[0][0]) / (xz.len() as f32 * SAMPLE);
    let score = score(&xz, terrain) + 250.0 * (made - p.directness).abs()
        - 4.0 * p.switchbacks * switchbacks.len().min(4) as f32;
    Candidate {
        xz,
        switchbacks,
        score,
    }
}

/// How good a route is (lower is better): little cutting and filling, no mountains looming
/// right over the road, but some real terrain (hills to climb) and some straight runs (for
/// bridges and jumps). Routes whose far-apart stretches come close together are rejected.
fn score(xz: &[[f32; 2]], terrain: &TerrainGen) -> f32 {
    let n = xz.len();
    if n < 10 {
        return f32::INFINITY;
    }
    // Neighbouring stretches must stay apart (checked on a coarse subset).
    let every = (40.0 / SAMPLE) as usize;
    let far = (SEPARATION_ARC / SAMPLE) as usize;
    for i in (0..n).step_by(every) {
        for j in ((i + far)..n).step_by(every) {
            let (dx, dz) = (xz[i][0] - xz[j][0], xz[i][1] - xz[j][1]);
            if dx * dx + dz * dz < SEPARATION * SEPARATION {
                return f32::INFINITY;
            }
        }
    }
    let natural: Vec<f32> = xz.iter().map(|p| terrain.height_m(p[0], p[1])).collect();
    let mut h = moving_average(&natural, 20);
    limit_grade(&mut h, &vec![super::MAX_GRADE * SAMPLE; n]);
    let length = n as f32 * SAMPLE;
    let cut_fill: f32 = h
        .iter()
        .zip(&natural)
        .map(|(a, b)| (a - b).abs())
        .sum::<f32>()
        * SAMPLE
        / length;
    // Mountains right beside the road (the valley walls come later; these would dwarf them).
    let mut looming = 0.0;
    let mut looks = 0.0;
    for i in (0..n).step_by(20) {
        let d = dir(xz, i);
        for side in [-1.0, 1.0] {
            let q = [xz[i][0] - d[1] * side * 90.0, xz[i][1] + d[0] * side * 90.0];
            looming += (terrain.height_m(q[0], q[1]) - h[i] - 30.0).max(0.0);
            looks += 1.0;
        }
    }
    looming /= looks;
    let hills = hill_sites(&natural).len().min(4) as f32;
    let straights = straight_runs(xz, 110).min(5) as f32;
    // Winding is good, up to a point.
    let mut turning = 0.0;
    for i in (every..n - every).step_by(every) {
        let (a, b) = (dir(xz, i - every), dir(xz, i));
        turning += 1.0 - (a[0] * b[0] + a[1] * b[1]);
    }
    let turning = turning / (n / every) as f32;
    let winding = (turning * 400.0).min(3.0);
    cut_fill * 1.0 + looming * 0.4 - hills * 4.0 - straights * 1.5 - winding
}

/// Where the natural ground rises steadily by `HILL_RISE` or more over the next
/// `HILL_LENGTH` metres: good places to send the road straight up a hill. Returns sample
/// indices of the foot of each (at least 400 m apart).
pub fn hill_sites(natural: &[f32]) -> Vec<usize> {
    let span = (super::HILL_LENGTH / SAMPLE) as usize;
    let smooth = moving_average(natural, 5);
    let mut out: Vec<usize> = Vec::new();
    let mut i = (300.0 / SAMPLE) as usize;
    while i + span < smooth.len() {
        let rise = smooth[i + span] - smooth[i];
        // Rising all the way (no dip in the middle), and not too steep to drive.
        let mid = smooth[i + span / 2] - smooth[i];
        if rise > super::HILL_RISE
            && rise < super::HILL_LENGTH * 0.28
            && mid > rise * 0.3
            && mid < rise * 0.75
        {
            out.push(i);
            i += (400.0 / SAMPLE) as usize;
        } else {
            i += 5;
        }
    }
    out
}

/// How many straight runs of `run` samples the road has (for bridges and jumps).
fn straight_runs(xz: &[[f32; 2]], run: usize) -> usize {
    let mut count = 0;
    let mut i = run;
    while i + 1 < xz.len() {
        if is_straight(xz, i - run, i, 0.995) {
            count += 1;
            i += run * 3;
        } else {
            i += 10;
        }
    }
    count
}

/// Whether the road between samples `a` and `b` stays within a narrow cone of its average
/// direction (`min_dot` of each sample's direction with the chord).
pub fn is_straight(xz: &[[f32; 2]], a: usize, b: usize, min_dot: f32) -> bool {
    let (pa, pb) = (xz[a], xz[b.min(xz.len() - 1)]);
    let (cx, cz) = (pb[0] - pa[0], pb[1] - pa[1]);
    let len = (cx * cx + cz * cz).sqrt().max(1e-6);
    let chord = [cx / len, cz / len];
    (a..b.min(xz.len() - 1)).step_by(3).all(|i| {
        let d = dir(xz, i);
        d[0] * chord[0] + d[1] * chord[1] >= min_dot
    })
}

/// Unit direction of travel (x, z) at sample `i`.
pub fn dir(xz: &[[f32; 2]], i: usize) -> [f32; 2] {
    let a = xz[i.saturating_sub(1)];
    let b = xz[(i + 1).min(xz.len() - 1)];
    let (dx, dz) = (b[0] - a[0], b[1] - a[1]);
    let len = (dx * dx + dz * dz).sqrt().max(1e-6);
    [dx / len, dz / len]
}

/// Heading (0 = +x, east; positive turns towards +z) as a unit (x, z), using a polynomial
/// approximation instead of platform trig so every CPU agrees.
pub fn dir_of(heading: f32) -> (f32, f32) {
    let (s, c) = sin_cos(heading);
    (c, s)
}

/// Rotates a direction (x, z) by `a` radians (towards +z), deterministically.
pub fn rotate(d: [f32; 2], a: f32) -> [f32; 2] {
    let (s, c) = sin_cos(a);
    [d[0] * c - d[1] * s, d[0] * s + d[1] * c]
}

/// sin/cos for |a| <= ~1.5, via Taylor series (deterministic, error < 1e-5 there).
pub fn sin_cos(a: f32) -> (f32, f32) {
    let a2 = a * a;
    let s = a
        * (1.0
            - a2 / 6.0
                * (1.0 - a2 / 20.0 * (1.0 - a2 / 42.0 * (1.0 - a2 / 72.0 * (1.0 - a2 / 110.0)))));
    let c = 1.0
        - a2 / 2.0 * (1.0 - a2 / 12.0 * (1.0 - a2 / 30.0 * (1.0 - a2 / 56.0 * (1.0 - a2 / 90.0))));
    (s, c)
}

pub fn catmull_rom(points: &[[f32; 2]], per_segment: usize) -> Vec<[f32; 2]> {
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
pub fn resample(points: &[[f32; 2]], spacing: f32, max_len: f32) -> Vec<[f32; 2]> {
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

pub fn moving_average(v: &[f32], radius: usize) -> Vec<f32> {
    let n = v.len();
    (0..n)
        .map(|i| {
            let (a, b) = (i.saturating_sub(radius), (i + radius).min(n - 1));
            v[a..=b].iter().sum::<f32>() / (b - a + 1) as f32
        })
        .collect()
}

/// Limits the change between neighbouring samples to `max_step[i]` (between `i` and `i + 1`),
/// forwards then backwards.
pub fn limit_grade(h: &mut [f32], max_step: &[f32]) {
    for i in 1..h.len() {
        let m = max_step[i - 1];
        h[i] = h[i].clamp(h[i - 1] - m, h[i - 1] + m);
    }
    for i in (0..h.len() - 1).rev() {
        let m = max_step[i];
        h[i] = h[i].clamp(h[i + 1] - m, h[i + 1] + m);
    }
}

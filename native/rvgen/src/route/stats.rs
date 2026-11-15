//! Measurements of a finished road, for tests and the CLI: how much it winds and climbs.
//! Nothing here feeds back into generation, so platform trig is fine.

use super::{Route, SAMPLE};

#[derive(Clone, Copy, Debug, Default)]
pub struct RouteStats {
    /// Road length over the straight-line distance from camp to home (1 = dead straight).
    pub sinuosity: f32,
    /// Total change of heading, degrees per kilometre.
    pub turning: f32,
    /// Share of the road in bends tighter than an 80 m radius.
    pub tight: f32,
    /// Share of the road that runs straight (under 2° of turn in 40 m).
    pub straight: f32,
    /// Furthest the heading swings off due east, degrees.
    pub swing: f32,
    /// Climbing and descending, metres per kilometre.
    pub climb: f32,
    /// Share of the road steeper than 6 %.
    pub steep: f32,
    /// Highest minus lowest point of the road, metres.
    pub height_range: f32,
    pub switchbacks: usize,
    pub obstacles_per_km: f32,
}

impl Route {
    pub fn stats(&self) -> RouteStats {
        let n = self.xz.len();
        let span = (40.0 / SAMPLE) as usize;
        if n < 2 * span + 2 {
            return RouteStats::default();
        }
        let km = self.length / 1000.0;
        let heading = |i: usize| {
            let d = self.dir(i);
            d[1].atan2(d[0])
        };
        let (mut turning, mut tight, mut straight, mut swing, mut windows) =
            (0.0f32, 0, 0, 0.0f32, 0);
        for i in (0..n - span).step_by(span) {
            let turn = (heading(i + span) - heading(i)).abs();
            turning += turn;
            windows += 1;
            // Radius = arc / angle.
            if turn > 40.0 / 80.0 {
                tight += 1;
            }
            if turn < 2f32.to_radians() {
                straight += 1;
            }
            swing = swing.max(heading(i).abs());
        }
        let (mut climb, mut steep) = (0.0, 0);
        for w in self.h.windows(2) {
            let d = (w[1] - w[0]).abs();
            climb += d;
            if d > 0.06 * SAMPLE {
                steep += 1;
            }
        }
        let (a, b) = (self.xz[0], self.xz[n - 1]);
        let crow = ((b[0] - a[0]).powi(2) + (b[1] - a[1]).powi(2)).sqrt();
        let (lo, hi) = self
            .h
            .iter()
            .fold((f32::MAX, f32::MIN), |(lo, hi), &h| (lo.min(h), hi.max(h)));
        RouteStats {
            sinuosity: self.length / crow.max(1.0),
            turning: turning.to_degrees() / km,
            tight: tight as f32 / windows as f32,
            straight: straight as f32 / windows as f32,
            swing: swing.to_degrees(),
            climb: climb / km,
            steep: steep as f32 / (n - 1) as f32,
            height_range: hi - lo,
            switchbacks: self.switchbacks.len(),
            obstacles_per_km: self.obstacles.len() as f32 / km,
        }
    }
}

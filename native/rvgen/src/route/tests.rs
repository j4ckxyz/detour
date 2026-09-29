use super::*;
use crate::{SeedCode, World};

fn world(seed: u64, trip: TripLength) -> World {
    World::new(SeedCode::new(trip, seed)).unwrap()
}

fn route(seed: u64, trip: TripLength) -> Route {
    world(seed, trip).route().clone()
}

#[test]
fn deterministic() {
    let a = route(5, TripLength::Short);
    let b = route(5, TripLength::Short);
    assert_eq!(a.xz, b.xz);
    assert_eq!(a.h, b.h);
    assert_eq!(a.obstacles, b.obstacles);
    assert_eq!(a.pois, b.pois);
    assert_eq!(a.spurs, b.spurs);
}

#[test]
fn long_winding_roads_that_head_home() {
    let mut turned = 0.0;
    for seed in 0..10 {
        let r = route(seed, TripLength::Short);
        assert!(
            r.length > 3800.0 && r.length < 5600.0,
            "seed {seed}: {} m",
            r.length
        );
        for w in r.xz.windows(2) {
            assert!(
                w[1][0] > w[0][0] - 0.01,
                "seed {seed}: the road always makes progress east"
            );
        }
        // It winds: the heading swings well off east somewhere.
        let most = (0..r.xz.len())
            .map(|i| r.dir(i)[1].abs())
            .fold(0.0, f32::max);
        assert!(most > 0.35, "seed {seed}: the road never turns ({most:.2})");
        turned += most;
    }
    assert!(turned / 10.0 > 0.5, "roads wind ({:.2})", turned / 10.0);
}

#[test]
fn trips_have_stations_and_obstacles() {
    for trip in [TripLength::Short, TripLength::Medium] {
        let r = route(3, trip);
        let stations = r.pads.iter().filter(|p| p.kind == PadKind::Station).count();
        assert_eq!(stations + 1, trip.stations() as usize);
        let per_km = r.obstacles.len() as f32 / (r.length / 1000.0);
        assert!(
            per_km > 2.0,
            "{} obstacles in {:.0} m",
            r.obstacles.len(),
            r.length
        );
    }
}

#[test]
fn many_seeds_validate() {
    let mut kinds = [0; 10];
    let (mut lakes, mut frozen, mut caves, mut pois, mut spurs) = (0, 0, 0, 0, 0);
    for seed in 0..160 {
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
        pois += r.pois.len();
        spurs += r.spurs.len();
    }
    println!(
        "kinds {kinds:?}, {lakes} lakes ({frozen} frozen), {caves} caves, {pois} places, {spurs} spurs"
    );
    assert!(
        kinds.iter().all(|&k| k > 30),
        "every obstacle kind appears: {kinds:?}"
    );
    assert!(
        lakes > 50 && frozen > 10 && caves > 50 && pois > 200 && spurs > 80,
        "{lakes} lakes ({frozen} frozen), {caves} caves, {pois} places, {spurs} spurs"
    );
}

#[test]
fn fords_are_wet_and_ice_is_icy() {
    let (mut fords, mut ice) = (0, 0);
    for seed in 0..40 {
        let w = world(seed, TripLength::Medium);
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
fn crossings_are_trenches_with_a_straight_level_approach() {
    let mut seen = 0;
    for seed in 0..40 {
        let w = world(seed, TripLength::Short);
        let r = w.route();
        for o in r.obstacles.iter().filter(|o| {
            matches!(
                o.kind,
                ObstacleKind::Bridge | ObstacleKind::Beams | ObstacleKind::Jump | ObstacleKind::Gap
            )
        }) {
            seen += 1;
            let at = |along: f32, across: f32| {
                let (x, z) = (
                    o.pos[0] + o.dir[0] * along - o.dir[1] * across,
                    o.pos[2] + o.dir[1] * along + o.dir[0] * across,
                );
                w.height_at(x, z)
            };
            // Deep in the middle, on the road and well off it (no driving round).
            for across in [0.0, 10.0, -10.0] {
                let edge = at(-o.length * 0.5 - 3.0, across).min(at(o.length * 0.5 + 3.0, across));
                let drop = edge - at(0.0, across)
                    + if o.kind == ObstacleKind::Jump {
                        LANDING_DROP
                    } else {
                        0.0
                    };
                assert!(
                    drop > o.size * 0.7,
                    "seed {seed}: {:?} at {:.0} m only {drop:.1} m deep",
                    o.kind,
                    o.s
                );
            }
            // The near side meets the trench at road height.
            let near = at(-o.length * 0.5 - 1.5, 0.0);
            let expect = if o.kind == ObstacleKind::Jump {
                o.pos[1] + KICKER[0]
            } else {
                o.pos[1]
            };
            assert!(
                (near - expect).abs() < 0.45,
                "seed {seed}: {:?} near side at {near:.2}, want {expect:.2}",
                o.kind
            );
        }
    }
    assert!(seen > 40, "{seen} crossings");
}

#[test]
fn a_jump_can_be_made_at_speed() {
    // Ballistics off the kicker's lip: at 45 km/h (third gear) the RV's front wheels clear
    // the gully with room to spare; at a crawl they don't.
    for seed in 0..60 {
        let r = route(seed, TripLength::Short);
        for o in r.obstacles.iter().filter(|o| o.kind == ObstacleKind::Jump) {
            let angle = KICKER[0] / KICKER[1]; // ~ tan of the lip angle
            let reach = |v: f32| {
                let (vx, vy) = (
                    v / (1.0 + angle * angle).sqrt(),
                    v * angle / (1.0 + angle * angle).sqrt(),
                );
                // Time to fall from the lip (KICKER[0] above the near side) to the landing
                // (LANDING_DROP below it): y(t) = K + vy t - g t^2 / 2 = -LANDING_DROP.
                let g = 9.81;
                let drop = KICKER[0] + LANDING_DROP;
                let t = (vy + (vy * vy + 2.0 * g * drop).sqrt()) / g;
                vx * t
            };
            assert!(
                reach(12.5) > o.length + 2.5,
                "seed {seed}: jump of {:.1} m at 45 km/h reaches {:.1}",
                o.length,
                reach(12.5)
            );
            assert!(
                reach(4.0) < o.length,
                "seed {seed}: jump of {:.1} m made at a crawl",
                o.length
            );
        }
    }
}

#[test]
fn hills_climb_and_the_easy_track_goes_nowhere() {
    let mut hills = 0;
    for seed in 0..40 {
        let r = route(seed, TripLength::Short);
        for o in r.obstacles.iter().filter(|o| o.kind == ObstacleKind::Hill) {
            hills += 1;
            let (a, b) = (r.index_at(o.s), r.index_at(o.s + o.length));
            let rise = r.h[b] - r.h[a];
            assert!(
                rise > HILL_RISE * 0.7,
                "seed {seed}: hill at {:.0} m rises {rise:.1} m",
                o.s
            );
            // Somewhere on it the road's steeper than an ordinary road ever is.
            let steepest = r.h[a..b]
                .windows(2)
                .map(|w| (w[1] - w[0]) / SAMPLE)
                .fold(0.0, f32::max);
            assert!(
                steepest > MAX_GRADE,
                "seed {seed}: hill at {:.0} m tops out at {steepest:.2}",
                o.s
            );
        }
        for sp in &r.spurs {
            // It leaves the road at the hill's foot and ends well away from it, lower down.
            let end = sp.xz[sp.xz.len() - 1];
            let from = r.xz[r.index_at(sp.from_s)];
            let away = ((end[0] - from[0]).powi(2) + (end[1] - from[1]).powi(2)).sqrt();
            assert!(away > 100.0, "seed {seed}: spur only {away:.0} m long");
            assert!(
                sp.h[sp.h.len() - 1] < sp.h[0] + 3.0,
                "seed {seed}: the side track climbs"
            );
            assert!(
                r.outside_valley(end[0], end[1]) < 0.0,
                "seed {seed}: spur ends in a wall"
            );
        }
    }
    assert!(hills > 15, "{hills} hills");
}

#[test]
fn road_is_flat_across_and_carved() {
    let w = world(9, TripLength::Short);
    let r = w.route();
    for i in (50..r.xz.len() - 50).step_by(37) {
        let p = r.xz[i];
        if r.obstacles.iter().any(|o| {
            let (a, b) = o.extent();
            let s = i as f32 * SAMPLE;
            s > a - 40.0 && s < b + 40.0
        }) {
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
    for seed in [1, 7] {
        let w = world(seed, TripLength::Short);
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
                if !seen.contains(&n) && standable(n.0, n.1) && (h(n.0, n.1) - h(x, z)).abs() < 1.5
                {
                    seen.insert(n);
                    stack.push(n);
                }
            }
        }
        assert!(
            seen.len() > 8000,
            "seed {seed}: the fill got going ({} cells)",
            seen.len()
        );
    }
}

#[test]
fn the_valley_floor_holds_the_trip() {
    for seed in 0..40 {
        let w = world(seed, TripLength::Short);
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
        for p in &r.pois {
            on_floor(p.pos, "a place");
        }
        // Behind the camp and past home it's walled off.
        let (a, d) = (r.xz[0], r.dir(0));
        let back = r.floor_at(0.0) + WALL_BAND + 20.0;
        let behind = [a[0] - d[0] * back, a[1] - d[1] * back];
        let lift = w.height_at(behind[0], behind[1]) - w.terrain().height_m(behind[0], behind[1]);
        assert!(
            lift > WALL_HEIGHT - 1.0,
            "seed {seed}: walled off behind the camp ({lift:.1} m)"
        );
    }
}

#[test]
fn the_valley_opens_out_between_obstacles() {
    for seed in 0..20 {
        let r = route(seed, TripLength::Short);
        let wide = (0..(r.length as usize))
            .step_by(20)
            .filter(|&s| r.floor_at(s as f32) > 60.0)
            .count();
        let total = (0..(r.length as usize)).step_by(20).count();
        assert!(
            wide * 3 > total,
            "seed {seed}: only {wide} of {total} stretches are wide"
        );
    }
}

#[test]
fn sin_cos_is_accurate() {
    for k in -14..=14 {
        let a = k as f32 * 0.1;
        let (s, c) = sin_cos(a);
        assert!(
            (s - a.sin()).abs() < 2e-5 && (c - a.cos()).abs() < 2e-5,
            "{a}"
        );
    }
}

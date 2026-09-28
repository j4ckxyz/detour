//! Deterministic 2D gradient noise built from integer lattice hashing.
//!
//! Only `+ - * floor abs` are used, so results are bit-identical on every platform.

/// 16 unit gradients at 22.5° steps (literal constants, so there is no trig at runtime).
const GRADIENTS: [(f32, f32); 16] = [
    (1.0, 0.0),
    (0.923_879_5, 0.382_683_43),
    (0.707_106_77, 0.707_106_77),
    (0.382_683_43, 0.923_879_5),
    (0.0, 1.0),
    (-0.382_683_43, 0.923_879_5),
    (-0.707_106_77, 0.707_106_77),
    (-0.923_879_5, 0.382_683_43),
    (-1.0, 0.0),
    (-0.923_879_5, -0.382_683_43),
    (-0.707_106_77, -0.707_106_77),
    (-0.382_683_43, -0.923_879_5),
    (0.0, -1.0),
    (0.382_683_43, -0.923_879_5),
    (0.707_106_77, -0.707_106_77),
    (0.923_879_5, -0.382_683_43),
];

/// Scales 2D gradient noise to roughly `[-1, 1]`.
const PERLIN_SCALE: f32 = core::f32::consts::SQRT_2;

#[inline]
fn lattice_hash(seed: u32, x: i32, z: i32) -> u32 {
    let mut h = seed ^ (x as u32).wrapping_mul(0x27D4_EB2D) ^ (z as u32).wrapping_mul(0x1656_67B1);
    h ^= h >> 15;
    h = h.wrapping_mul(0x2C1B_3C6D);
    h ^= h >> 12;
    h = h.wrapping_mul(0x297A_2D39);
    h ^= h >> 15;
    h
}

#[inline]
fn fade(t: f32) -> f32 {
    t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
}

#[inline]
fn lerp(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}

/// Hermite smoothstep of `x` between `edge0` and `edge1` (either order).
#[inline]
pub fn smoothstep(edge0: f32, edge1: f32, x: f32) -> f32 {
    let t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

/// Gradient (Perlin-style) noise in roughly `[-1, 1]`, with lattice spacing 1.
pub fn perlin(seed: u32, x: f32, z: f32) -> f32 {
    let x0 = x.floor();
    let z0 = z.floor();
    let (fx, fz) = (x - x0, z - z0);
    let (ix, iz) = (x0 as i32, z0 as i32);
    let corner = |dx: i32, dz: i32| {
        let (gx, gz) = GRADIENTS[(lattice_hash(seed, ix + dx, iz + dz) >> 28) as usize];
        gx * (fx - dx as f32) + gz * (fz - dz as f32)
    };
    let u = fade(fx);
    let v = fade(fz);
    let a = lerp(corner(0, 0), corner(1, 0), u);
    let b = lerp(corner(0, 1), corner(1, 1), u);
    lerp(a, b, v) * PERLIN_SCALE
}

/// Fractal settings. Frequencies should be powers of two so scaling stays exact.
#[derive(Clone, Copy, Debug)]
pub struct Fractal {
    pub octaves: u32,
    /// Cycles per metre of the first octave.
    pub frequency: f32,
    pub lacunarity: f32,
    pub gain: f32,
}

#[inline]
fn octave_seed(seed: u32, octave: u32) -> u32 {
    seed.wrapping_add(octave.wrapping_mul(0x9E37_79B9))
}

/// Fractal Brownian motion, normalised to roughly `[-1, 1]`.
pub fn fbm(seed: u32, x: f32, z: f32, p: &Fractal) -> f32 {
    let (mut sum, mut norm) = (0.0, 0.0);
    let (mut amp, mut freq) = (1.0, p.frequency);
    for o in 0..p.octaves {
        sum += amp * perlin(octave_seed(seed, o), x * freq, z * freq);
        norm += amp;
        amp *= p.gain;
        freq *= p.lacunarity;
    }
    sum / norm
}

/// Ridged multifractal in `[0, 1]`: sharp crests, smooth valleys.
pub fn ridged(seed: u32, x: f32, z: f32, p: &Fractal) -> f32 {
    let (mut sum, mut norm) = (0.0, 0.0);
    let (mut amp, mut freq) = (1.0, p.frequency);
    let mut weight = 1.0;
    for o in 0..p.octaves {
        let mut n = 1.0 - perlin(octave_seed(seed, o), x * freq, z * freq).abs();
        n *= n;
        n *= weight;
        weight = (n * 2.0).clamp(0.0, 1.0);
        sum += amp * n;
        norm += amp;
        amp *= p.gain;
        freq *= p.lacunarity;
    }
    sum / norm
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn zero_at_lattice_points() {
        for i in -5..5 {
            assert_eq!(perlin(7, i as f32, (i * 3) as f32), 0.0);
        }
    }

    #[test]
    fn roughly_bounded() {
        let mut lo = f32::MAX;
        let mut hi = f32::MIN;
        for i in 0..20_000 {
            let x = i as f32 * 0.137;
            let v = perlin(99, x, x * 0.71 + 3.3);
            lo = lo.min(v);
            hi = hi.max(v);
        }
        assert!(lo >= -1.05 && hi <= 1.05, "range {lo}..{hi}");
        assert!(lo < -0.5 && hi > 0.5, "range too narrow {lo}..{hi}");
    }

    #[test]
    fn ridged_in_unit_range() {
        let p = Fractal {
            octaves: 5,
            frequency: 1.0 / 256.0,
            lacunarity: 2.0,
            gain: 0.5,
        };
        for i in 0..5_000 {
            let v = ridged(3, i as f32 * 3.7, i as f32 * -1.3, &p);
            assert!((0.0..=1.0).contains(&v), "{v}");
        }
    }
}

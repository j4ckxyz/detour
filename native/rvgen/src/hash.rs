//! Stable, platform-independent hashing.
//!
//! Never use `std::hash::DefaultHasher` for anything that must match across machines: its
//! algorithm is unspecified and it is randomly keyed per process.

/// SplitMix64 finaliser. Strong avalanche for integer inputs.
#[inline]
pub const fn mix64(mut z: u64) -> u64 {
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    z ^ (z >> 31)
}

/// Folds `v` into the running hash `h`.
#[inline]
pub const fn combine(h: u64, v: u64) -> u64 {
    mix64(h ^ mix64(v.wrapping_add(0x9E37_79B9_7F4A_7C15)))
}

/// FNV-1a (64-bit) over a byte slice.
pub const fn fnv1a64(bytes: &[u8]) -> u64 {
    let mut h = Fnv64::OFFSET;
    let mut i = 0;
    while i < bytes.len() {
        h ^= bytes[i] as u64;
        h = h.wrapping_mul(Fnv64::PRIME);
        i += 1;
    }
    h
}

/// Derives an independent seed for one subsystem at one location, e.g.
/// `sub_seed(world, "trees", chunk.x, chunk.z)`.
pub fn sub_seed(seed: u64, label: &str, a: i64, b: i64) -> u64 {
    combine(
        combine(combine(seed, fnv1a64(label.as_bytes())), a as u64),
        b as u64,
    )
}

/// Same as [`sub_seed`] but truncated for 32-bit consumers (noise lattices).
pub fn sub_seed32(seed: u64, label: &str) -> u32 {
    let h = sub_seed(seed, label, 0, 0);
    (h ^ (h >> 32)) as u32
}

/// Streaming FNV-1a hasher for content hashes (chunk data, world-state checks).
#[derive(Clone, Copy, Debug)]
pub struct Fnv64(u64);

impl Fnv64 {
    const OFFSET: u64 = 0xCBF2_9CE4_8422_2325;
    const PRIME: u64 = 0x0000_0100_0000_01B3;

    pub const fn new() -> Self {
        Self(Self::OFFSET)
    }

    pub fn write(&mut self, bytes: &[u8]) {
        for &b in bytes {
            self.0 ^= b as u64;
            self.0 = self.0.wrapping_mul(Self::PRIME);
        }
    }

    pub fn write_u16(&mut self, v: u16) {
        self.write(&v.to_le_bytes());
    }

    pub fn write_i32(&mut self, v: i32) {
        self.write(&v.to_le_bytes());
    }

    pub const fn finish(&self) -> u64 {
        self.0
    }
}

impl Default for Fnv64 {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fnv_known_vectors() {
        // Reference values from the FNV spec test suite.
        assert_eq!(fnv1a64(b""), 0xCBF2_9CE4_8422_2325);
        assert_eq!(fnv1a64(b"a"), 0xAF63_DC4C_8601_EC8C);
        assert_eq!(fnv1a64(b"foobar"), 0x8594_4171_F739_67E8);
    }

    #[test]
    fn streaming_matches_oneshot() {
        let mut h = Fnv64::new();
        h.write(b"foo");
        h.write(b"bar");
        assert_eq!(h.finish(), fnv1a64(b"foobar"));
    }

    #[test]
    fn sub_seeds_differ_by_label_and_location() {
        let s = 12345;
        assert_ne!(sub_seed(s, "trees", 0, 0), sub_seed(s, "rocks", 0, 0));
        assert_ne!(sub_seed(s, "trees", 0, 0), sub_seed(s, "trees", 1, 0));
        assert_ne!(sub_seed(s, "trees", 1, 0), sub_seed(s, "trees", 0, 1));
        assert_eq!(sub_seed(s, "trees", 3, -7), sub_seed(s, "trees", 3, -7));
    }
}

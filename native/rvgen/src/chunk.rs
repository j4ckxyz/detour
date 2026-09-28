//! Terrain chunks: 128 m × 128 m tiles sampled every metre (129 × 129 samples; edges are
//! shared with neighbours so chunks meet without seams).

use crate::World;
use crate::hash::Fnv64;
use crate::seed::GEN_VERSION;
use crate::terrain::q_to_m;

pub const CHUNK_SIZE: i32 = 128;
pub const CHUNK_VERTS: usize = CHUNK_SIZE as usize + 1;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct ChunkCoord {
    pub x: i32,
    pub z: i32,
}

impl ChunkCoord {
    pub const fn new(x: i32, z: i32) -> Self {
        Self { x, z }
    }

    /// World position of the chunk's (0, 0) corner.
    pub const fn origin(self) -> (i32, i32) {
        (self.x * CHUNK_SIZE, self.z * CHUNK_SIZE)
    }

    /// The chunk containing world position `(x, z)`.
    pub fn containing(x: f32, z: f32) -> Self {
        let size = CHUNK_SIZE as f32;
        Self::new((x / size).floor() as i32, (z / size).floor() as i32)
    }
}

#[derive(Clone, Debug)]
pub struct Heightfield {
    pub coord: ChunkCoord,
    /// Row-major (`z` rows of `x` samples), quantised to 2 cm.
    heights: Vec<u16>,
}

impl Heightfield {
    pub(crate) fn generate(world: &World, coord: ChunkCoord) -> Self {
        let (ox, oz) = coord.origin();
        let mut heights = Vec::with_capacity(CHUNK_VERTS * CHUNK_VERTS);
        for z in 0..CHUNK_VERTS as i32 {
            for x in 0..CHUNK_VERTS as i32 {
                heights.push(world.height_q(ox + x, oz + z));
            }
        }
        Self { coord, heights }
    }

    #[inline]
    pub fn get(&self, x: usize, z: usize) -> u16 {
        self.heights[z * CHUNK_VERTS + x]
    }

    #[inline]
    pub fn height_m(&self, x: usize, z: usize) -> f32 {
        q_to_m(self.get(x, z))
    }

    pub fn heights(&self) -> &[u16] {
        &self.heights
    }

    /// Heights in metres, row-major, ready for Godot's `HeightMapShape3D.map_data`.
    pub fn heights_m(&self) -> Vec<f32> {
        self.heights.iter().map(|&q| q_to_m(q)).collect()
    }

    /// Bilinear height at chunk-local position (clamped to the chunk).
    pub fn sample_m(&self, lx: f32, lz: f32) -> f32 {
        let max = CHUNK_SIZE as f32;
        let (lx, lz) = (lx.clamp(0.0, max), lz.clamp(0.0, max));
        let (x0, z0) = (lx.floor(), lz.floor());
        let (fx, fz) = (lx - x0, lz - z0);
        let (ix, iz) = (x0 as usize, z0 as usize);
        let (ix1, iz1) = ((ix + 1).min(CHUNK_VERTS - 1), (iz + 1).min(CHUNK_VERTS - 1));
        let a = self.height_m(ix, iz) + (self.height_m(ix1, iz) - self.height_m(ix, iz)) * fx;
        let b = self.height_m(ix, iz1) + (self.height_m(ix1, iz1) - self.height_m(ix, iz1)) * fx;
        a + (b - a) * fz
    }

    /// Content hash used to check that every client generated identical terrain.
    pub fn content_hash(&self) -> u64 {
        let mut h = Fnv64::new();
        h.write(b"DTHF");
        h.write_u16(GEN_VERSION);
        h.write_i32(self.coord.x);
        h.write_i32(self.coord.z);
        for &q in &self.heights {
            h.write_u16(q);
        }
        h.finish()
    }

    pub fn min_max_m(&self) -> (f32, f32) {
        let (lo, hi) = self
            .heights
            .iter()
            .fold((u16::MAX, 0), |(lo, hi), &q| (lo.min(q), hi.max(q)));
        (q_to_m(lo), q_to_m(hi))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{SeedCode, TripLength};

    fn world() -> World {
        World::new(SeedCode::new(TripLength::Short, 1234)).unwrap()
    }

    #[test]
    fn neighbours_share_edges() {
        let w = world();
        let a = w.heightfield(ChunkCoord::new(0, 0));
        let east = w.heightfield(ChunkCoord::new(1, 0));
        let south = w.heightfield(ChunkCoord::new(0, 1));
        for i in 0..CHUNK_VERTS {
            assert_eq!(a.get(CHUNK_VERTS - 1, i), east.get(0, i));
            assert_eq!(a.get(i, CHUNK_VERTS - 1), south.get(i, 0));
        }
    }

    #[test]
    fn negative_coords_work() {
        let w = world();
        let hf = w.heightfield(ChunkCoord::new(-3, -7));
        assert_eq!(hf.get(0, 0), w.height_q(-3 * 128, -7 * 128));
        assert_eq!(ChunkCoord::containing(-0.5, 127.9), ChunkCoord::new(-1, 0));
    }

    #[test]
    fn deterministic_and_seed_sensitive() {
        let w = world();
        let c = ChunkCoord::new(2, -1);
        assert_eq!(
            w.heightfield(c).content_hash(),
            w.heightfield(c).content_hash()
        );
        let other = World::new(SeedCode::new(TripLength::Short, 1235)).unwrap();
        assert_ne!(
            w.heightfield(c).content_hash(),
            other.heightfield(c).content_hash()
        );
    }

    #[test]
    fn plausible_relief() {
        let w = world();
        let (lo, hi) = w.heightfield(ChunkCoord::new(0, 0)).min_max_m();
        assert!(lo >= 0.0 && hi < 700.0, "{lo}..{hi}");
    }

    #[test]
    fn world_height_matches_grid() {
        let w = world();
        let hf = w.heightfield(ChunkCoord::new(0, 0));
        assert_eq!(w.height_at(10.0, 20.0), hf.height_m(10, 20));
        let mid = w.height_at(10.5, 20.0);
        let (a, b) = (hf.height_m(10, 20), hf.height_m(11, 20));
        assert!(mid >= a.min(b) && mid <= a.max(b));
    }
}

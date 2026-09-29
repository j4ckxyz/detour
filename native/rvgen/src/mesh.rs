//! Terrain chunk meshes with LOD and crack-hiding skirts.
//!
//! Output is engine-neutral; `rvcore` converts it to Godot arrays. Mesh data is visual only
//! (never hashed), but it is still built from the deterministic heightfield.

use crate::World;
use crate::biome::Weights;
use crate::chunk::{CHUNK_SIZE, Heightfield};
use crate::noise::smoothstep;
use crate::terrain::q_to_m;

/// LOD spacings in metres. Each must divide `CHUNK_SIZE`.
pub const LOD_STEPS: [u32; 4] = [1, 2, 4, 8];

#[derive(Clone, Debug, Default)]
pub struct MeshData {
    /// Chunk-local positions (x and z in `0..=128`).
    pub positions: Vec<[f32; 3]>,
    pub normals: Vec<[f32; 3]>,
    /// sRGB vertex colours.
    pub colors: Vec<[f32; 4]>,
    /// Triangle list, clockwise front faces (Godot's convention).
    pub indices: Vec<i32>,
}

// Cozy ground palette (sRGB).
const GRASS_LUSH: [f32; 3] = [0.34, 0.49, 0.23];
const GRASS_DRY: [f32; 3] = [0.56, 0.55, 0.30];
const DIRT: [f32; 3] = [0.47, 0.37, 0.26];
const ROCK: [f32; 3] = [0.52, 0.50, 0.47];
const SNOW: [f32; 3] = [0.93, 0.94, 0.96];
const ROAD: [f32; 3] = [0.58, 0.49, 0.36];
const MUD: [f32; 3] = [0.27, 0.2, 0.13];
const BAYOU: [f32; 3] = [0.30, 0.36, 0.17];
const BAYOU_WET: [f32; 3] = [0.22, 0.26, 0.14];
const SAND: [f32; 3] = [0.78, 0.50, 0.30];
const REDROCK: [f32; 3] = [0.66, 0.34, 0.22];
const PALE_ROCK: [f32; 3] = [0.84, 0.66, 0.48];
const ALPINE_ROCK: [f32; 3] = [0.55, 0.56, 0.58];
const ICE: [f32; 3] = [0.74, 0.87, 0.95];
const RIVERBED: [f32; 3] = [0.30, 0.27, 0.22];

fn mix(a: [f32; 3], b: [f32; 3], t: f32) -> [f32; 3] {
    [
        a[0] + (b[0] - a[0]) * t,
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
    ]
}

/// Ground colour from height, surface normal Y, a low-frequency tint in `[0, 1]` and the
/// biome weights (woods, bayou, canyon, pass).
pub fn ground_color(height_m: f32, normal_y: f32, tint: f32, biomes: &Weights) -> [f32; 4] {
    let steep = smoothstep(0.88, 0.72, normal_y);
    let mut out = [0.0f32; 3];
    let mut add = |c: [f32; 3], w: f32| {
        for k in 0..3 {
            out[k] += c[k] * w;
        }
    };
    if biomes[0] > 0.0 {
        let dryness = (0.6 * tint + 0.4 * smoothstep(150.0, 280.0, height_m)).clamp(0.0, 1.0);
        let mut c = mix(GRASS_LUSH, GRASS_DRY, dryness);
        c = mix(c, DIRT, smoothstep(0.35, 0.1, tint) * 0.6);
        c = mix(c, ROCK, steep);
        let snow = smoothstep(330.0, 370.0, height_m) * smoothstep(0.70, 0.85, normal_y);
        add(mix(c, SNOW, snow), biomes[0]);
    }
    if biomes[1] > 0.0 {
        let c = mix(BAYOU, BAYOU_WET, tint);
        add(mix(c, MUD, steep * 0.8), biomes[1]);
    }
    if biomes[2] > 0.0 {
        // Banded cliffs: pale and red layers every few metres, sand on the benches.
        let band = height_m * (1.0 / 4.5);
        let layer = band - band.floor();
        let wall = mix(REDROCK, PALE_ROCK, smoothstep(0.4, 0.6, layer));
        add(mix(mix(SAND, REDROCK, tint * 0.4), wall, steep), biomes[2]);
    }
    if biomes[3] > 0.0 {
        let snow = smoothstep(0.62, 0.8, normal_y);
        add(mix(ALPINE_ROCK, SNOW, snow), biomes[3]);
    }
    [out[0], out[1], out[2], 1.0]
}

/// Builds the mesh for one chunk at LOD spacing `step` (see [`LOD_STEPS`]).
pub fn chunk_mesh(world: &World, hf: &Heightfield, step: u32) -> MeshData {
    let s = step as i32;
    assert!(s > 0 && CHUNK_SIZE % s == 0, "bad LOD step {step}");
    let n = (CHUNK_SIZE / s) as usize + 1;
    let (ox, oz) = hf.coord.origin();

    // Heights inside the chunk come from the heightfield; normals at the border need
    // neighbouring samples, which we take from the world so lighting is seamless.
    let h = |lx: i32, lz: i32| -> f32 {
        if (0..=CHUNK_SIZE).contains(&lx) && (0..=CHUNK_SIZE).contains(&lz) {
            hf.height_m(lx as usize, lz as usize)
        } else {
            q_to_m(world.height_q(ox + lx, oz + lz))
        }
    };

    let skirt_verts = 4 * n;
    let mut mesh = MeshData {
        positions: Vec::with_capacity(n * n + skirt_verts),
        normals: Vec::with_capacity(n * n + skirt_verts),
        colors: Vec::with_capacity(n * n + skirt_verts),
        indices: Vec::with_capacity((n - 1) * (n - 1) * 6 + (n - 1) * 4 * 12),
    };

    for j in 0..n {
        for i in 0..n {
            let (lx, lz) = (i as i32 * s, j as i32 * s);
            let y = h(lx, lz);
            let nx = h(lx - s, lz) - h(lx + s, lz);
            let nz = h(lx, lz - s) - h(lx, lz + s);
            let ny = 2.0 * s as f32;
            let len = (nx * nx + ny * ny + nz * nz).sqrt();
            let normal = [nx / len, ny / len, nz / len];
            let (wx, wz) = ((ox + lx) as f32, (oz + lz) as f32);
            let tint = world.terrain().tint(wx, wz);
            let weights = world.terrain().biomes().weights(wx, wz);
            let mut color = ground_color(y, normal[1], tint, &weights);
            let route = world.route();
            let road = route.road_at(wx, wz);
            if road > 0.0 {
                let c = mix([color[0], color[1], color[2]], ROAD, road);
                let m = route.mud_at(wx, wz);
                let c = mix(c, MUD, m);
                color = [c[0], c[1], c[2], 1.0];
            }
            let ice = route.ice_at(wx, wz);
            if ice > 0.0 {
                let c = mix([color[0], color[1], color[2]], ICE, ice);
                color = [c[0], c[1], c[2], 1.0];
            }
            if let Some(level) = route.water_at(wx, wz) {
                let under = smoothstep(0.0, 0.6, level - y);
                let c = mix([color[0], color[1], color[2]], RIVERBED, under);
                color = [c[0], c[1], c[2], 1.0];
            }
            mesh.positions.push([lx as f32, y, lz as f32]);
            mesh.normals.push(normal);
            mesh.colors.push(color);
        }
    }

    let idx = |i: usize, j: usize| (j * n + i) as i32;
    for j in 0..n - 1 {
        for i in 0..n - 1 {
            let (a, b, c, d) = (idx(i, j), idx(i + 1, j), idx(i, j + 1), idx(i + 1, j + 1));
            mesh.indices.extend_from_slice(&[a, b, c, b, d, c]);
        }
    }

    // Skirts: a curtain hanging below each edge hides cracks against coarser LODs.
    let depth = 2.0 * s as f32 + 1.0;
    let edges: [Vec<i32>; 4] = [
        (0..n).map(|i| idx(i, 0)).collect(),
        (0..n).map(|i| idx(i, n - 1)).collect(),
        (0..n).map(|j| idx(0, j)).collect(),
        (0..n).map(|j| idx(n - 1, j)).collect(),
    ];
    for edge in &edges {
        let base = mesh.positions.len() as i32;
        for &v in edge {
            let v = v as usize;
            let [x, y, z] = mesh.positions[v];
            mesh.positions.push([x, y - depth, z]);
            mesh.normals.push(mesh.normals[v]);
            mesh.colors.push(mesh.colors[v]);
        }
        for k in 0..edge.len() - 1 {
            let (e0, e1) = (edge[k], edge[k + 1]);
            let (s0, s1) = (base + k as i32, base + k as i32 + 1);
            // Both windings, so the curtain is visible from either side.
            mesh.indices
                .extend_from_slice(&[e0, e1, s0, e1, s1, s0, e0, s0, e1, e1, s0, s1]);
        }
    }

    mesh
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{ChunkCoord, SeedCode, TripLength};

    #[test]
    fn vertex_and_index_counts() {
        let w = World::new(SeedCode::new(TripLength::Short, 7)).unwrap();
        let hf = w.heightfield(ChunkCoord::new(0, 0));
        for step in LOD_STEPS {
            let m = chunk_mesh(&w, &hf, step);
            let n = (128 / step) as usize + 1;
            assert_eq!(m.positions.len(), n * n + 4 * n);
            assert_eq!(m.normals.len(), m.positions.len());
            assert_eq!(m.colors.len(), m.positions.len());
            assert_eq!(m.indices.len(), (n - 1) * (n - 1) * 6 + 4 * (n - 1) * 12);
            let max = m.positions.len() as i32;
            assert!(m.indices.iter().all(|&i| (0..max).contains(&i)));
            assert!(m.normals.iter().all(|n| n[1] > 0.0));
        }
    }

    #[test]
    fn front_faces_point_up() {
        // Godot treats clockwise triangles (seen from the front) as front faces.
        // Seen from above (+Y), a clockwise triangle has a negative Y cross product.
        let w = World::new(SeedCode::new(TripLength::Short, 7)).unwrap();
        let hf = w.heightfield(ChunkCoord::new(0, 0));
        let m = chunk_mesh(&w, &hf, 8);
        let n = 17;
        for tri in m.indices[..(n - 1) * (n - 1) * 6].chunks(3) {
            let [a, b, c] = [0, 1, 2].map(|k| m.positions[tri[k] as usize]);
            let ab = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
            let ac = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
            let cross_y = ab[2] * ac[0] - ab[0] * ac[2];
            assert!(cross_y < 0.0);
        }
    }
}

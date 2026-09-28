//! rvgen data → Godot types. Always runs on the main thread.

use godot::classes::mesh::ArrayType;
use godot::prelude::*;
use rvgen::mesh::MeshData;
use rvgen::scatter::{PropInstance, TREE_KINDS, TreeInstance};

/// Floats per tree in the packed layout: x, y, z, yaw, scale, kind.
pub const TREE_STRIDE: usize = 6;
/// Floats per prop in the packed layout: a 3×4 transform (MultiMesh order), kind, variant.
pub const PROP_STRIDE: usize = 14;

/// Builds the array set for `ArrayMesh.add_surface_from_arrays`.
pub fn mesh_arrays(mesh: &MeshData) -> VarArray {
    let mut arrays = VarArray::new();
    arrays.resize(ArrayType::MAX.ord() as usize, &Variant::nil());

    let vertices: PackedVector3Array = mesh
        .positions
        .iter()
        .map(|p| Vector3::new(p[0], p[1], p[2]))
        .collect();
    let normals: PackedVector3Array = mesh
        .normals
        .iter()
        .map(|n| Vector3::new(n[0], n[1], n[2]))
        .collect();
    let colors: PackedColorArray = mesh
        .colors
        .iter()
        .map(|c| Color::from_rgba(c[0], c[1], c[2], c[3]))
        .collect();
    let indices = PackedInt32Array::from(mesh.indices.as_slice());

    arrays.set(ArrayType::VERTEX.ord() as usize, &vertices.to_variant());
    arrays.set(ArrayType::NORMAL.ord() as usize, &normals.to_variant());
    arrays.set(ArrayType::COLOR.ord() as usize, &colors.to_variant());
    arrays.set(ArrayType::INDEX.ord() as usize, &indices.to_variant());
    arrays
}

/// Packs trees as `[x, y, z, yaw, scale, kind] * n` (chunk-local positions).
pub fn trees_packed(trees: &[TreeInstance]) -> PackedFloat32Array {
    let mut out = Vec::with_capacity(trees.len() * TREE_STRIDE);
    for t in trees {
        out.extend_from_slice(&[t.pos[0], t.pos[1], t.pos[2], t.yaw, t.scale, t.kind as f32]);
    }
    PackedFloat32Array::from(out.as_slice())
}

/// `MultiMesh.buffer` contents for `TRANSFORM_3D`, one buffer per tree kind (12 floats per
/// instance: the 3×4 matrix, row-major). Rotation uses platform `sin`/`cos`, which is fine:
/// this is visual only, the deterministic data is the tree list itself.
pub fn trees_multimesh_buffers(trees: &[TreeInstance]) -> VarArray {
    let mut per_kind: Vec<Vec<f32>> = vec![Vec::new(); TREE_KINDS as usize];
    for t in trees {
        let (s, c) = t.yaw.sin_cos();
        let k = t.scale;
        // Basis(Vector3.UP, yaw) * scale: columns x = (c, 0, -s), y = (0, 1, 0), z = (s, 0, c).
        per_kind[(t.kind % TREE_KINDS) as usize].extend_from_slice(&[
            c * k,
            0.0,
            s * k,
            t.pos[0], //
            0.0,
            k,
            0.0,
            t.pos[1], //
            -s * k,
            0.0,
            c * k,
            t.pos[2],
        ]);
    }
    let mut out = VarArray::new();
    for buf in per_kind {
        out.push(&PackedFloat32Array::from(buf.as_slice()).to_variant());
    }
    out
}

/// Packs props as `[3×4 transform (MultiMesh row-major order), kind, variant] * n`, in
/// chunk-local space. The basis leans the prop's Y axis towards `up`, spins it by `yaw`
/// around that axis and applies `scale`. Visual/physics placement only: the generator's
/// deterministic output is the prop list itself.
pub fn props_packed(props: &[PropInstance]) -> PackedFloat32Array {
    let mut out = Vec::with_capacity(props.len() * PROP_STRIDE);
    for p in props {
        let up = normalized(p.up);
        let (s, c) = p.yaw.sin_cos();
        // Yawed X axis, made perpendicular to `up` (Gram-Schmidt); Z completes the basis.
        let yx = [c, 0.0, -s];
        let d = dot(yx, up);
        let x = normalized([yx[0] - up[0] * d, yx[1] - up[1] * d, yx[2] - up[2] * d]);
        let z = cross(x, up);
        let k = p.scale;
        out.extend_from_slice(&[
            x[0] * k,
            up[0] * k,
            z[0] * k,
            p.pos[0], //
            x[1] * k,
            up[1] * k,
            z[1] * k,
            p.pos[1], //
            x[2] * k,
            up[2] * k,
            z[2] * k,
            p.pos[2], //
            p.kind as u8 as f32,
            p.variant as f32,
        ]);
    }
    PackedFloat32Array::from(out.as_slice())
}

fn dot(a: [f32; 3], b: [f32; 3]) -> f32 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}

fn cross(a: [f32; 3], b: [f32; 3]) -> [f32; 3] {
    [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    ]
}

fn normalized(v: [f32; 3]) -> [f32; 3] {
    let len = dot(v, v).sqrt().max(1e-6);
    [v[0] / len, v[1] / len, v[2] / len]
}

pub fn hash_hex(hash: u64) -> GString {
    GString::from(format!("{hash:016x}").as_str())
}

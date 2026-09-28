"""Nature assets: scanned rocks (Poly Haven, decimated for low-end GPUs), modelled pines,
a stump and a fallen log.

    blender --background --factory-startup --python tools/assets/blender/build_nature.py

Outputs (game/assets/models/):
  rocks.glb   Rock_0..N   origin at the base, sunk 10% so they sit in the ground
  pines.glb   Pine_0..3   origin at the trunk base
  stump.glb, log.glb
Rocks, stumps and logs are also winch anchors in game, so keep their silhouettes chunky.
"""

import json
import math
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bmesh  # noqa: E402
import bpy  # noqa: E402
import lib  # noqa: E402
from lib import Matrix, Vector  # noqa: E402

lib.reset("Detour_Nature")
rng = random.Random(7)

ROCK_TRIS = 900        # per rock; Godot also generates LODs on import
PROP_TRIS = 1200       # stump / log


def import_model(key: str) -> list:
    """Imports a downloaded Poly Haven glTF; returns its meshes with transforms baked."""
    meta = lib.MODEL_CACHE / key / "model.json"
    if not meta.exists():
        print(f"SKIP {key}: not downloaded (run tools/assets/fetch_assets.py)")
        return []
    path = lib.MODEL_CACHE / key / json.loads(meta.read_text())["gltf"]
    before = set(bpy.data.objects)
    with bpy.context.temp_override(scene=lib.SCENE, view_layer=lib.view_layer()):
        bpy.ops.import_scene.gltf(filepath=str(path))
    new = [o for o in bpy.data.objects if o not in before]
    meshes = []
    for o in new:
        if o.type == "MESH":
            o.data = o.data.copy()  # Instances share data; bake each separately.
            mw = o.matrix_world.copy()
            o.parent = None
            o.data.transform(mw)
            o.matrix_world = Matrix()
            meshes.append(o)
    for o in new:
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    return meshes


def ground_origin(obj, sink: float = 0.1) -> None:
    """Moves the origin to the bottom centre, sinking the mesh by `sink` of its height."""
    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    zs = [v.co.z for v in obj.data.vertices]
    h = max(zs) - min(zs)
    offset = Vector(((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, min(zs) + sink * h))
    obj.data.transform(Matrix.Translation(-offset))
    obj.location = (0, 0, 0)


# --- rocks ---------------------------------------------------------------------------------------
rocks_root = lib.empty("Rocks", (0, 0, 0))
rocks = []
for key in ("rocks_a", "rocks_b", "rocks_c"):
    for mesh in import_model(key):
        lib.decimate(mesh, ROCK_TRIS)
        ground_origin(mesh)
        rocks.append(mesh)
if not rocks:
    # Fallback so the pipeline still works offline: a lumpy icosphere.
    rock_mat = lib.material("RockFallback", (0.45, 0.43, 0.40), rough=0.9)
    for i in range(3):
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=2, radius=0.8 + 0.4 * i)
        for v in bm.verts:
            v.co *= 0.8 + 0.4 * rng.random()
            v.co.z *= 0.7
        rocks.append(lib.mesh_object(f"rock{i}", bm, [rock_mat]))
        lib.box_uv(rocks[-1], 1.0)
        ground_origin(rocks[-1])
x = 0.0
for i, r in enumerate(rocks):
    r.name = f"Rock_{i}"
    width = r.dimensions.x
    r.location = (x + width / 2, 0, 0)
    x += width + 1.0
    r.parent = rocks_root
print(f"rocks: {len(rocks)} variants, {lib.tri_count(rocks)} tris total")
lib.export_glb([rocks_root], lib.OUT / "rocks.glb")

# --- pines ---------------------------------------------------------------------------------------
bark = lib.material("Bark", (0.33, 0.23, 0.16), tex="bark", rough=0.9)
needles = lib.material("Needles", (0.16, 0.30, 0.16), tex="needles", recolor=(0.17, 0.31, 0.17), detail=0.9, rough=0.9)
needles_light = lib.material("NeedlesLight", (0.24, 0.40, 0.20), tex="needles", recolor=(0.25, 0.40, 0.20), detail=0.9, rough=0.9)


def skirt(name, z0, z1, radius, segments, mat, twist):
    """A jagged cone of branches: alternating long/short tips around the rim, a concave
    underside so it reads as foliage from below too."""
    bm = bmesh.new()
    rim = []
    for i in range(segments * 2):
        a = twist + math.pi * i / segments
        long = i % 2 == 0
        r = radius * (1.0 if long else 0.72) * (0.9 + 0.2 * rng.random())
        z = z0 + (0.0 if long else 0.18 * (z1 - z0) / 3) - (0.1 * rng.random() if long else 0)
        rim.append(bm.verts.new((r * math.cos(a), r * math.sin(a), z)))
    apex = bm.verts.new((0, 0, z1))
    under = bm.verts.new((0, 0, z0 + 0.35 * (z1 - z0)))
    n = len(rim)
    for i in range(n):
        a, b = rim[i], rim[(i + 1) % n]
        bm.faces.new((a, b, apex))
        bm.faces.new((b, a, under))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return lib.mesh_object(name, bm, [mat])


pines_root = lib.empty("Pines", (0, 0, 0))
pines = []
for i, (height, tiers) in enumerate(((3.2, 3), (8.0, 5), (11.0, 6), (14.0, 7))):
    parts = []
    trunk_r = 0.06 + 0.018 * height
    parts.append(lib.cylinder(f"trunk{i}", trunk_r, height * 0.85, (0, 0, height * 0.425), "z", bark, 8,
                              radius_top=trunk_r * 0.25))
    first = height * 0.18
    for t in range(tiers):
        f = t / max(1, tiers - 1)
        z0 = first + (height * 0.78 - first) * f
        tier_h = height * (0.34 - 0.12 * f)
        radius = height * (0.30 - 0.20 * f)
        mat = needles if t % 2 == 0 else needles_light
        parts.append(skirt(f"tier{i}_{t}", z0, min(height, z0 + tier_h), radius, 9, mat, rng.random() * math.pi))
    for p in parts:
        lib.box_uv(p, 0.8)
    pine = lib.join(parts, f"Pine_{i}")
    lib.smooth_by_angle(pine, 60)
    pine.location = (i * 7.0, 8.0, 0)
    pine.parent = pines_root
    pines.append(pine)
print(f"pines: {[lib.tri_count([p]) for p in pines]} tris")
lib.export_glb([pines_root], lib.OUT / "pines.glb")

# --- stump and log -----------------------------------------------------------------------------------
wood_top = lib.material("WoodEnd", (0.62, 0.48, 0.32), tex="counter", rough=0.8)
for key, fallback in (("stump", "stump"), ("log", "log")):
    meshes = import_model(key)
    if meshes:
        obj = lib.join(meshes, key.capitalize())
        lib.decimate(obj, PROP_TRIS)
    elif fallback == "stump":
        obj = lib.join([
            lib.cylinder("s", 0.38, 0.55, (0, 0, 0.275), "z", bark, 12, radius_top=0.32),
            lib.cylinder("st", 0.315, 0.02, (0, 0, 0.555), "z", wood_top, 12),
        ], "Stump")
        lib.box_uv(obj, 0.8)
    else:
        obj = lib.cylinder("Log", 0.26, 4.0, (0, 0, 0.26), "x", bark, 12)
        lib.cylinder_uv(obj, 0.8)
    ground_origin(obj, sink=0.05)
    lib.smooth_by_angle(obj, 45)
    obj.location = (-6.0 if key == "stump" else -12.0, 8.0, 0)
    lib.export_glb([obj], lib.OUT / f"{key}.glb")

PREV = lib.BUILD / "previews"
lib.render_preview(PREV / "nature.png", target=(8, 4, 3), distance=26, elevation=14, azimuth=20)

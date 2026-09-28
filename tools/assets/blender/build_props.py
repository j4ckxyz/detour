"""Carryable items from PLAN.md §4.4, one GLB each in game/assets/models/props/.

    blender --background --factory-startup --python tools/assets/blender/build_props.py

Every prop has its origin at the bottom centre (so it rests on surfaces) and stays small:
held items are seen up close in first person but many can be loose in the RV at once.
"""

import math
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bmesh  # noqa: E402
import lib  # noqa: E402
from lib import Vector  # noqa: E402

lib.reset("Detour_Props")
rng = random.Random(3)
OUT = lib.OUT / "props"

M = {
    "red": lib.material("PaintRed", (0.72, 0.12, 0.08), tex="paint", recolor=(0.72, 0.12, 0.08), detail=0.4, rough=0.45),
    "white": lib.material("PaintWhite", (0.92, 0.91, 0.87), tex="paint", recolor=(0.92, 0.91, 0.87), detail=0.3, rough=0.5),
    "orange": lib.material("PlasticOrange", (0.95, 0.45, 0.08), rough=0.4),
    "yellow": lib.material("PlasticYellow", (0.93, 0.72, 0.10), rough=0.4),
    "green": lib.material("PlasticGreen", (0.25, 0.60, 0.30), rough=0.4),
    "blue": lib.material("PlasticBlue", (0.15, 0.35, 0.75), rough=0.4),
    "black": lib.material("PlasticBlack", (0.06, 0.06, 0.06), rough=0.5),
    "rubber": lib.material("PropRubber", (0.07, 0.07, 0.07), tex="rubber", recolor=(0.07, 0.07, 0.07), detail=0.8, rough=0.9),
    "rim": lib.material("PropRim", (0.80, 0.80, 0.78), tex="metal", recolor=(0.80, 0.80, 0.78), detail=0.3, rough=0.35, metal=0.8),
    "plank": lib.material("PlankWood", (0.55, 0.42, 0.28), tex="plank", rough=0.8),
    "scrap": lib.material("ScrapMetal", (0.45, 0.35, 0.28), tex="dark_metal", rough=0.75),
    "bun": lib.material("Bun", (0.80, 0.55, 0.25), rough=0.6),
    "patty": lib.material("Patty", (0.30, 0.17, 0.10), rough=0.8),
    "cheese": lib.material("Cheese", (0.98, 0.75, 0.15), rough=0.5),
    "lettuce": lib.material("Lettuce", (0.40, 0.70, 0.20), rough=0.6),
    "button_g": lib.material("ButtonGreen", (0.1, 0.8, 0.2), emission=(0.1, 0.8, 0.2), emission_strength=0.6),
    "button_r": lib.material("ButtonRed", (0.9, 0.1, 0.1), emission=(0.9, 0.1, 0.1), emission_strength=0.6),
}


def finish(name, parts, tile=0.3):
    for p in parts:
        if not p.data.uv_layers:
            lib.box_uv(p, tile)
    obj = lib.join(parts, name)
    lib.smooth_by_angle(obj, 40)
    lib.export_glb([obj], OUT / f"{name.lower()}.glb")
    return obj


built = []

# Jerry can (20 L): 0.35 x 0.17 x 0.47 m.
built.append(finish("JerryCan", [
    lib.box("jc", (-0.175, -0.085, 0), (0.175, 0.085, 0.44), M["red"], bevel=0.03, segments=3),
    *[lib.box(f"jch{x}", (x - 0.012, -0.03, 0.44), (x + 0.012, 0.03, 0.50), M["red"], bevel=0.008) for x in (-0.09, 0.0, 0.09)],
    lib.box("jcg", (-0.1, -0.03, 0.48), (0.1, 0.03, 0.51), M["red"], bevel=0.01),
    lib.cylinder("jcs", 0.03, 0.08, (0.13, 0, 0.47), "z", M["black"], 12),
]))

# Plank for bridges: 5 m, matching rvgen::route::PLANK_LENGTH (gaps are sized to it).
built.append(finish("Plank", [lib.box("pl", (-2.5, -0.15, 0), (2.5, 0.15, 0.07), M["plank"], bevel=0.008)], tile=1.2))

# Engine oil bottle.
bottle = lib.lathe("ob", [(0.0, 0.0), (0.0, 0.09), (0.22, 0.09), (0.25, 0.06), (0.26, 0.03), (0.285, 0.03)], M["yellow"], 16)
bottle.data.transform(lib.Matrix.Rotation(math.radians(-90), 4, "Y"))
built.append(finish("OilBottle", [bottle, lib.cylinder("oc", 0.032, 0.04, (0, 0, 0.30), "z", M["black"], 12)]))

# Spare tyre, lying flat.
tyre = lib.tyre("tt", M["rubber"])
rim_ = lib.cylinder("tr", 0.25, 0.18, (0, 0, 0), "x", M["rim"], 20)
lib.box_uv(rim_, 0.5)
spare = lib.join([tyre, rim_], "SpareTire")
spare.data.transform(lib.Matrix.Rotation(math.radians(90), 4, "Y") @ lib.Matrix.Translation(Vector((-0.12, 0, 0))))
lib.export_glb([spare], OUT / "sparetire.glb")
built.append(spare)

# Scrap metal: a bent, dented plate.
bm = bmesh.new()
bmesh.ops.create_grid(bm, x_segments=4, y_segments=3, size=0.25)
for v in bm.verts:
    v.co.z = 0.04 * math.sin(v.co.x * 9.0) + rng.uniform(-0.015, 0.015)
bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.008)
built.append(finish("ScrapMetal", [lib.mesh_object("sm", bm, [M["scrap"]])], tile=0.5))

# First-aid box.
built.append(finish("FirstAidKit", [
    lib.box("fa", (-0.2, -0.075, 0), (0.2, 0.075, 0.28), M["white"], bevel=0.02),
    lib.box("fah", (-0.08, -0.02, 0.28), (0.08, 0.02, 0.31), M["black"], bevel=0.008),
    *[lib.box(f"fax{s}", (-0.06, s * 0.077 - 0.002, 0.12), (0.06, s * 0.077 + 0.002, 0.16), M["red"]) for s in (-1, 1)],
    *[lib.box(f"fay{s}", (-0.02, s * 0.077 - 0.002, 0.08), (0.02, s * 0.077 + 0.002, 0.20), M["red"]) for s in (-1, 1)],
]))

# Bear spray.
built.append(finish("BearSpray", [
    lib.cylinder("bs", 0.035, 0.20, (0, 0, 0.10), "z", M["orange"], 14),
    lib.cylinder("bsc", 0.028, 0.04, (0, 0, 0.22), "z", M["black"], 12),
    lib.box("bsn", (-0.008, 0.0, 0.225), (0.008, 0.04, 0.24), M["black"]),
]))

# EpiPen and antidote.
built.append(finish("EpiPen", [
    lib.cylinder("ep", 0.012, 0.14, (0, 0, 0.07), "z", M["yellow"], 10),
    lib.cylinder("epc", 0.013, 0.03, (0, 0, 0.155), "z", M["blue"], 10),
]))
antidote = lib.lathe("ad", [(0.0, 0.0), (0.0, 0.035), (0.08, 0.035), (0.10, 0.015), (0.125, 0.015)], M["green"], 14)
antidote.data.transform(lib.Matrix.Rotation(math.radians(-90), 4, "Y"))
built.append(finish("Antidote", [antidote, lib.cylinder("adc", 0.016, 0.02, (0, 0, 0.13), "z", M["white"], 10)]))

# Burger: the healing item, so it should look tasty.
bun_top = lib.lathe("bt", [(0.0, 0.055), (0.012, 0.058), (0.03, 0.05), (0.045, 0.03), (0.052, 0.0)], M["bun"], 16)
bun_top.data.transform(lib.Matrix.Rotation(math.radians(-90), 4, "Y"))
bun_top.location = (0, 0, 0.055)
built.append(finish("Burger", [
    lib.cylinder("bb", 0.055, 0.02, (0, 0, 0.01), "z", M["bun"], 16, bevel=0.006),
    lib.cylinder("bp", 0.058, 0.015, (0, 0, 0.0275), "z", M["patty"], 16, bevel=0.004),
    lib.box("bc", (-0.05, -0.05, 0.035), (0.05, 0.05, 0.039), M["cheese"]),
    lib.cylinder("bl", 0.062, 0.008, (0, 0, 0.043), "z", M["lettuce"], 12),
    lib.cylinder("bm", 0.055, 0.008, (0, 0, 0.051), "z", M["bun"], 16),
    bun_top,
]))

# Winch remote.
built.append(finish("WinchRemote", [
    lib.box("wr", (-0.03, -0.015, 0), (0.03, 0.015, 0.14), M["black"], bevel=0.008),
    lib.cylinder("wrg", 0.011, 0.006, (0, 0.016, 0.10), "y", M["button_g"], 10),
    lib.cylinder("wrr", 0.011, 0.006, (0, 0.016, 0.06), "y", M["button_r"], 10),
    lib.cylinder("wrc", 0.006, 0.05, (0, 0, -0.025), "z", M["black"], 6),
]))

# Line them up for the preview.
x = 0.0
for obj in built:
    obj.location.x = x
    x += max(obj.dimensions.x, 0.3) + 0.25
lib.render_preview(lib.BUILD / "previews" / "props.png", target=(x / 2, 0, 0.2), distance=4.5, elevation=25, azimuth=15)

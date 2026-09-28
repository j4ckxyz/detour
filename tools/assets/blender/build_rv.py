"""Builds the RV: a 1970s-style class C motorhome with a walkable interior.

    blender --background --factory-startup --python tools/assets/blender/build_rv.py

Outputs:
  game/assets/models/rv.glb            visual model (exterior + interior + moving parts + markers)
  game/assets/models/rv_collision.glb  simple boxes: Hull_* (vehicle body), Interior_* (walkable space)
  art-src/build/previews/rv_*.png      preview renders

Moving parts are separate nodes with their pivot at the origin: Wheel_FL/FR/RL/RR, Door_Entry,
SteeringWheel, GearStick, Handbrake, WinchDrum_Front/Rear, SpareTire_1/2 (removable).
Empties mark gameplay points: Eye_Driver, Seat_*, WinchMount_*, Ladder_*, Headlight_*.
Dimensions: 7.4 m long, 2.4 m wide, 3.45 m tall; front axle y=2.9, rear axle y=-1.55.
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lib  # noqa: E402
from lib import Vector  # noqa: E402

lib.reset("Detour_RV")

# --- dimensions (metres, +Y forward, +Z up) ---------------------------------------------------
HW = 1.20            # living box half width
WALL = 0.06
LIV_Y0, LIV_Y1 = -3.60, 1.30
LIV_Z0, LIV_Z1 = 0.75, 3.20
FLOOR = LIV_Z0 + WALL + 0.04       # top of the living floor (0.85)
CAB_HW = 1.10
CAB_Z0, CAB_TOP = 0.60, 2.05
CAB_FLOOR = CAB_Z0 + WALL + 0.04   # 0.70
FRONT_AXLE, REAR_AXLE = 2.90, -1.55
WHEEL_R = 0.40

# --- materials --------------------------------------------------------------------------------
M = {
    "paint": lib.material("Paint", (0.95, 0.86, 0.66), tex="paint", recolor=(0.95, 0.86, 0.66), detail=0.35, rough=0.45),
    "stripe_o": lib.material("StripeOrange", (0.86, 0.47, 0.16), tex="paint", recolor=(0.86, 0.47, 0.16), detail=0.35, rough=0.45),
    "stripe_b": lib.material("StripeBrown", (0.45, 0.26, 0.13), tex="paint", recolor=(0.45, 0.26, 0.13), detail=0.35, rough=0.45),
    "stripe_y": lib.material("StripeMustard", (0.88, 0.68, 0.22), tex="paint", recolor=(0.88, 0.68, 0.22), detail=0.35, rough=0.45),
    "wall": lib.material("WallPanel", (0.55, 0.38, 0.22), tex="wall_panel", rough=0.7),
    "trim": lib.material("Trim", (0.20, 0.18, 0.17), rough=0.7),
    "glass": lib.material("Glass", (0.10, 0.14, 0.16), rough=0.05, alpha=0.35),
    "chrome": lib.material("Chrome", (0.86, 0.87, 0.89), rough=0.18, metal=1.0),
    "rubber": lib.material("Rubber", (0.07, 0.07, 0.07), tex="rubber", recolor=(0.07, 0.07, 0.07), detail=0.8, rough=0.9),
    "rim": lib.material("Rim", (0.80, 0.80, 0.78), tex="metal", recolor=(0.80, 0.80, 0.78), detail=0.3, rough=0.35, metal=0.8),
    "chassis": lib.material("Chassis", (0.16, 0.15, 0.14), tex="dark_metal", recolor=(0.17, 0.16, 0.15), detail=0.6, rough=0.8),
    "grille": lib.material("Grille", (0.12, 0.12, 0.12), tex="metal", recolor=(0.12, 0.12, 0.12), detail=0.6, rough=0.5, metal=0.6),
    "floor": lib.material("Floor", (0.50, 0.40, 0.30), tex="floor", rough=0.6),
    "fabric": lib.material("Upholstery", (0.72, 0.42, 0.20), tex="fabric", rough=0.95),
    "mattress": lib.material("Mattress", (0.86, 0.81, 0.70), tex="fabric", recolor=(0.86, 0.81, 0.70), detail=0.5, rough=0.95),
    "blanket": lib.material("Blanket", (0.35, 0.45, 0.30), tex="fabric_plaid", rough=0.95),
    "counter": lib.material("Counter", (0.60, 0.45, 0.30), tex="counter", rough=0.5),
    "appliance": lib.material("Appliance", (0.90, 0.89, 0.84), tex="paint", recolor=(0.90, 0.89, 0.84), detail=0.25, rough=0.35),
    "plastic": lib.material("DarkPlastic", (0.14, 0.13, 0.12), rough=0.6),
    "headlight": lib.material("Headlight", (1.0, 0.96, 0.85), emission=(1.0, 0.95, 0.80), emission_strength=3.0, rough=0.1),
    "taillight": lib.material("Taillight", (0.70, 0.05, 0.03), emission=(0.85, 0.06, 0.03), emission_strength=1.5, rough=0.2),
    "amber": lib.material("Amber", (0.95, 0.55, 0.10), emission=(0.95, 0.55, 0.10), emission_strength=0.8, rough=0.2),
    "lamp": lib.material("CeilingLamp", (1.0, 0.95, 0.85), emission=(1.0, 0.92, 0.78), emission_strength=1.5),
}
TILES = {
    "Paint": 2.0, "StripeOrange": 2.0, "StripeBrown": 2.0, "StripeMustard": 2.0, "WallPanel": 1.2,
    "Trim": 1.0, "Rubber": 0.5, "Rim": 0.5, "Chassis": 1.0, "Grille": 0.4, "Floor": 1.2, "Upholstery": 0.6,
    "Mattress": 1.0, "Blanket": 0.7, "Counter": 0.8, "Appliance": 1.5,
}

root = lib.empty("RV", (0, 0, 0))
exterior, interior = [], []


def part(obj, bucket, smooth=35.0):
    lib.box_uv(obj, TILES)
    lib.smooth_by_angle(obj, smooth)
    bucket.append(obj)
    return obj


def window_cutter(name, lo, hi):
    return lib.box(name, lo, hi, M["trim"])


# --- living box shell (with the over-cab bunk) --------------------------------------------------
living_profile = [
    (LIV_Y0 + 0.15, LIV_Z0), (LIV_Y1, LIV_Z0), (LIV_Y1, CAB_TOP), (2.55, CAB_TOP),
    (2.80, 2.35), (2.80, 2.95), (2.60, LIV_Z1), (LIV_Y0 + 0.15, LIV_Z1),
    (LIV_Y0, LIV_Z1 - 0.15), (LIV_Y0, LIV_Z0 + 0.15),
]
shell = lib.prism("LivingShell", living_profile, -HW, HW, [M["paint"], M["wall"], M["trim"]], bevel=0.05)
lib.solidify(shell, WALL)

cutters = [
    # Left (-X) side: dinette window, bed window, over-cab side window.
    window_cutter("w1", (-1.4, 0.30, 1.55), (-1.0, 1.15, 2.35)),
    window_cutter("w2", (-1.4, -2.95, 1.75), (-1.0, -2.15, 2.40)),
    window_cutter("w3", (-1.4, 1.75, 2.35), (-1.0, 2.35, 2.80)),
    # Right (+X) side: entry door, kitchen window, bed window, over-cab side window.
    window_cutter("door", (1.0, 0.05, FLOOR), (1.4, 0.80, 2.72)),
    window_cutter("w4", (1.0, -1.45, 1.65), (1.4, -0.55, 2.35)),
    window_cutter("w5", (1.0, -2.95, 1.75), (1.4, -2.15, 2.40)),
    window_cutter("w6", (1.0, 1.75, 2.35), (1.4, 2.35, 2.80)),
    # Rear window and over-cab front window.
    window_cutter("w7", (-0.60, -3.80, 1.95), (0.60, -3.40, 2.55)),
    window_cutter("w8", (-0.85, 2.60, 2.45), (0.85, 3.00, 2.82)),
    # Walk-through into the cab.
    window_cutter("passage", (-0.95, 1.20, FLOOR - 0.02), (0.95, 1.40, CAB_TOP - 0.06)),
    # Rear wheel wells (sides only, so the floor stays intact).
    lib.cylinder("arch_rl", 0.47, 0.8, (-1.2, REAR_AXLE, WHEEL_R), "x", M["trim"], 24),
    lib.cylinder("arch_rr", 0.47, 0.8, (1.2, REAR_AXLE, WHEEL_R), "x", M["trim"], 24),
]
lib.cut(shell, cutters)
part(shell, exterior, 30.0)

# Glass panes sit in the middle of each wall.
panes = [
    ((-HW + 0.03, 0.30, 1.55), (-HW + 0.035, 1.15, 2.35)),
    ((-HW + 0.03, -2.95, 1.75), (-HW + 0.035, -2.15, 2.40)),
    ((-HW + 0.03, 1.75, 2.35), (-HW + 0.035, 2.35, 2.80)),
    ((HW - 0.035, -1.45, 1.65), (HW - 0.03, -0.55, 2.35)),
    ((HW - 0.035, -2.95, 1.75), (HW - 0.03, -2.15, 2.40)),
    ((HW - 0.035, 1.75, 2.35), (HW - 0.03, 2.35, 2.80)),
    ((-0.60, LIV_Y0 + 0.03, 1.95), (0.60, LIV_Y0 + 0.035, 2.55)),
    ((-0.85, 2.765, 2.45), (0.85, 2.77, 2.82)),
]
glass_parts = [lib.box(f"pane{i}", lo, hi, M["glass"]) for i, (lo, hi) in enumerate(panes)]

# --- cab shell ----------------------------------------------------------------------------------
cab_profile = [(LIV_Y1, CAB_Z0), (2.55, CAB_Z0), (2.55, 1.30), (2.20, CAB_TOP), (LIV_Y1, CAB_TOP)]
cab = lib.prism("CabShell", cab_profile, -CAB_HW, CAB_HW, [M["paint"], M["plastic"], M["trim"]], bevel=0.04)
lib.solidify(cab, WALL)
# Windshield: a slab lying in the sloped face, inset from its edges.
p0, p1 = Vector((0, 2.55, 1.30)), Vector((0, 2.20, CAB_TOP))
along = (p1 - p0).normalized()
normal = Vector((0, along.z, -along.y))  # Outward (+Y, +Z).
a, b = p0 + along * 0.07, p1 - along * 0.07
ws_profile = [tuple((q + normal * s).yz) for q, s in ((a, -0.15), (b, -0.15), (b, 0.15), (a, 0.15))]
cab_cutters = [
    lib.prism("windshield_cut", ws_profile, -0.98, 0.98, M["trim"]),
    window_cutter("cw_l", (-1.3, 1.55, 1.35), (-0.9, 2.15, 1.95)),
    window_cutter("cw_r", (0.9, 1.55, 1.35), (1.3, 2.15, 1.95)),
    window_cutter("cab_passage", (-0.95, 1.20, CAB_FLOOR - 0.02), (0.95, 1.40, CAB_TOP - 0.06)),
    lib.cylinder("arch_fl", 0.50, 0.8, (-1.1, FRONT_AXLE, WHEEL_R), "x", M["trim"], 24),
    lib.cylinder("arch_fr", 0.50, 0.8, (1.1, FRONT_AXLE, WHEEL_R), "x", M["trim"], 24),
]
lib.cut(cab, cab_cutters)
part(cab, exterior, 30.0)
ws_mid = (a + b) / 2
ws = lib.prism("windshield", [tuple((q + normal * s).yz) for q, s in ((a, -0.01), (b, -0.01), (b, 0.0), (a, 0.0))], -0.98, 0.98, M["glass"])
glass_parts += [
    ws,
    lib.box("cab_pane_l", (-CAB_HW + 0.03, 1.55, 1.35), (-CAB_HW + 0.035, 2.15, 1.95), M["glass"]),
    lib.box("cab_pane_r", (CAB_HW - 0.035, 1.55, 1.35), (CAB_HW - 0.03, 2.15, 1.95), M["glass"]),
]

# --- hood, grille, lights, bumpers ------------------------------------------------------------------
hood = lib.prism("Hood", [(2.55, 0.55), (3.40, 0.55), (3.46, 0.62), (3.46, 1.10), (3.30, 1.28), (2.55, 1.32)],
                 -1.0, 1.0, M["paint"], bevel=0.06, segments=3)
lib.cut(hood, [
    lib.cylinder("arch_hl", 0.50, 0.6, (-1.0, FRONT_AXLE, WHEEL_R), "x", M["trim"], 24),
    lib.cylinder("arch_hr", 0.50, 0.6, (1.0, FRONT_AXLE, WHEEL_R), "x", M["trim"], 24),
])
part(hood, exterior, 30.0)
part(lib.box("Grille", (-0.55, 3.44, 0.72), (0.55, 3.475, 1.05), M["grille"], bevel=0.01), exterior)
for side in (-1, 1):
    part(lib.cylinder(f"Headlamp{side}", 0.11, 0.05, (side * 0.76, 3.465, 0.92), "y", M["headlight"], 16), exterior)
    part(lib.cylinder(f"HeadlampRing{side}", 0.13, 0.03, (side * 0.76, 3.445, 0.92), "y", M["chrome"], 16), exterior)
    part(lib.box(f"Indicator{side}", (side * 0.92 - 0.06, 3.45, 0.70), (side * 0.92 + 0.06, 3.47, 0.78), M["amber"]), exterior)
    part(lib.box(f"Taillight{side}", (side * 1.02 - 0.08, LIV_Y0 - 0.02, 1.00), (side * 1.02 + 0.08, LIV_Y0, 1.38), M["taillight"]), exterior)
    part(lib.box(f"Marker{side}", (side * HW - 0.01, 1.10, 2.95), (side * HW + 0.01, 1.20, 3.02), M["amber"]), exterior)
part(lib.box("BumperFront", (-1.12, 3.42, 0.42), (1.12, 3.62, 0.66), M["chrome"], bevel=0.03), exterior)
part(lib.box("BumperRear", (-1.15, LIV_Y0 - 0.18, 0.50), (1.15, LIV_Y0, 0.72), M["chassis"], bevel=0.02), exterior)

# --- 70s stripes (skip the door opening on the right) ------------------------------------------------
stripes = [(1.25, "stripe_y"), (1.36, "stripe_o"), (1.47, "stripe_b")]
for z, key in stripes:
    for side in (-1, 1):
        x0, x1 = (side * HW, side * (HW + 0.004)) if side > 0 else (side * (HW + 0.004), side * HW)
        spans = [(LIV_Y0 + 0.1, 1.25)] if side < 0 else [(LIV_Y0 + 0.1, 0.03), (0.82, 1.25)]
        for y0, y1 in spans:
            part(lib.box(f"Stripe{z}{side}{y0}", (x0, y0, z), (x1, y1, z + 0.08), M[key]), exterior)
    part(lib.box(f"StripeRear{z}", (-HW + 0.1, LIV_Y0 - 0.004, z), (HW - 0.1, LIV_Y0, z + 0.08), M[key]), exterior)

# --- chassis, roof gear, ladder, awning -------------------------------------------------------------
for side in (-1, 1):
    part(lib.box(f"FrameRail{side}", (side * 0.55 - 0.06, -3.50, 0.40), (side * 0.55 + 0.06, 3.30, 0.60), M["chassis"]), exterior)
part(lib.cylinder("AxleFront", 0.05, 1.9, (0, FRONT_AXLE, WHEEL_R), "x", M["chassis"], 8), exterior)
part(lib.cylinder("AxleRear", 0.07, 2.0, (0, REAR_AXLE, WHEEL_R), "x", M["chassis"], 8), exterior)
part(lib.box("FuelTank", (-0.95, -0.80, 0.45), (-0.62, 0.20, 0.72), M["chassis"], bevel=0.03), exterior)
part(lib.box("Step", (HW - 0.02, 0.10, 0.45), (HW + 0.25, 0.75, 0.50), M["chassis"]), exterior)
part(lib.box("RoofAC", (-0.40, -0.60, LIV_Z1), (0.40, 0.20, LIV_Z1 + 0.26), M["appliance"], bevel=0.05), exterior)
part(lib.box("RoofVent", (-0.25, -2.4, LIV_Z1), (0.25, -2.0, LIV_Z1 + 0.10), M["plastic"], bevel=0.02), exterior)
for side in (-1, 1):
    part(lib.box(f"RackRail{side}", (side * 0.90 - 0.03, -3.35, LIV_Z1 + 0.05), (side * 0.90 + 0.03, -1.40, LIV_Z1 + 0.10), M["chrome"]), exterior)
    for y in (-3.35, -1.40):
        part(lib.box(f"RackFoot{side}{y}", (side * 0.90 - 0.03, y, LIV_Z1), (side * 0.90 + 0.03, y + 0.05, LIV_Z1 + 0.05), M["chrome"]), exterior)
for y in (-3.1, -2.4, -1.7):
    part(lib.box(f"RackBar{y}", (-0.93, y, LIV_Z1 + 0.05), (0.93, y + 0.05, LIV_Z1 + 0.10), M["chrome"]), exterior)
LADDER_X = (0.55, 0.95)
for x in LADDER_X:
    part(lib.cylinder(f"LadderRail{x}", 0.02, 2.55, (x, LIV_Y0 - 0.08, 0.95 + 2.55 / 2), "z", M["chrome"], 8), exterior)
    for z in (1.1, 3.25):
        part(lib.box(f"LadderStandoff{x}{z}", (x - 0.015, LIV_Y0 - 0.08, z), (x + 0.015, LIV_Y0, z + 0.03), M["chrome"]), exterior)
for i in range(8):
    z = 1.05 + i * 0.30
    part(lib.cylinder(f"Rung{i}", 0.017, LADDER_X[1] - LADDER_X[0], ((LADDER_X[0] + LADDER_X[1]) / 2, LIV_Y0 - 0.08, z), "x", M["chrome"], 8), exterior)
part(lib.cylinder("Awning", 0.07, 3.6, (HW + 0.05, -1.0, 3.02), "y", M["appliance"], 12), exterior)

# --- living interior ------------------------------------------------------------------------------
IN = HW - WALL                     # interior half width
FRONT_IN = LIV_Y1 - WALL           # 1.24
REAR_IN = LIV_Y0 + WALL            # -3.54
part(lib.box("FloorLiving", (-IN, REAR_IN, LIV_Z0 + WALL), (IN, FRONT_IN, FLOOR), M["floor"]), interior)
part(lib.box("FloorCab", (-CAB_HW + WALL, LIV_Y1, CAB_Z0 + WALL), (CAB_HW - WALL, 2.49, CAB_FLOOR), M["floor"]), interior)

# Dinette (left, front): two benches facing a table.
for name, y0, y1, back_y in (("BenchRear", 0.0, 0.42, 0.0), ("BenchFront", 0.82, FRONT_IN, FRONT_IN - 0.1)):
    part(lib.box(f"{name}Base", (-IN, y0, FLOOR), (-0.45, y1, FLOOR + 0.36), M["wall"]), interior)
    part(lib.box(f"{name}Cushion", (-IN, y0, FLOOR + 0.36), (-0.45, y1, FLOOR + 0.46), M["fabric"], bevel=0.03), interior)
    part(lib.box(f"{name}Back", (-IN, back_y, FLOOR + 0.46), (-0.45, back_y + 0.1, FLOOR + 1.0), M["fabric"], bevel=0.03), interior)
part(lib.box("TableTop", (-IN, 0.44, FLOOR + 0.70), (-0.40, 0.80, FLOOR + 0.74), M["counter"], bevel=0.01), interior)
part(lib.cylinder("TableLeg", 0.04, 0.70, (-0.75, 0.62, FLOOR + 0.35), "z", M["chrome"], 10), interior)

# Kitchen (right, middle): counter with sink and stove, upper cabinets.
KY0, KY1 = -1.70, -0.10
part(lib.box("KitchenBase", (0.55, KY0, FLOOR), (IN, KY1, FLOOR + 0.88), M["wall"]), interior)
part(lib.box("KitchenTop", (0.52, KY0, FLOOR + 0.88), (IN, KY1, FLOOR + 0.92), M["counter"], bevel=0.01), interior)
part(lib.box("Sink", (0.62, -0.75, FLOOR + 0.921), (1.02, -0.35, FLOOR + 0.925), M["chrome"]), interior)
part(lib.cylinder("Tap", 0.015, 0.25, (1.05, -0.55, FLOOR + 1.04), "z", M["chrome"], 8), interior)
part(lib.box("Stove", (0.62, -1.55, FLOOR + 0.921), (1.05, -1.05, FLOOR + 0.93), M["plastic"]), interior)
for dx, dy in ((0.72, -1.42), (0.95, -1.42), (0.72, -1.18), (0.95, -1.18)):
    part(lib.cylinder(f"Burner{dx}{dy}", 0.07, 0.01, (dx, dy, FLOOR + 0.935), "z", M["chassis"], 12), interior)
part(lib.box("UpperCabinet", (0.80, KY0, 2.30), (IN, KY1, 2.90), M["wall"], bevel=0.01), interior)

# Fridge and wardrobe (left, middle).
part(lib.box("Fridge", (-IN, -1.00, FLOOR), (-0.50, -0.20, FLOOR + 1.75), M["appliance"], bevel=0.03), interior)
part(lib.box("FridgeHandle", (-0.50, -0.30, FLOOR + 0.9), (-0.47, -0.27, FLOOR + 1.4), M["chrome"]), interior)
part(lib.box("Wardrobe", (-IN, -1.95, FLOOR), (-0.55, -1.05, 2.90), M["wall"], bevel=0.01), interior)

# Bed across the rear.
BED_Y = -2.05
part(lib.box("BedBase", (-IN, REAR_IN, FLOOR), (IN, BED_Y, FLOOR + 0.50), M["wall"]), interior)
part(lib.box("Mattress", (-IN + 0.02, REAR_IN + 0.02, FLOOR + 0.50), (IN - 0.02, BED_Y - 0.02, FLOOR + 0.70), M["mattress"], bevel=0.05, segments=3), interior)
part(lib.box("Blanket", (-IN + 0.01, -3.05, FLOOR + 0.70), (IN - 0.01, BED_Y - 0.01, FLOOR + 0.74), M["blanket"], bevel=0.02), interior)
for x in (-0.55, 0.55):
    part(lib.box(f"Pillow{x}", (x - 0.35, REAR_IN + 0.08, FLOOR + 0.70), (x + 0.35, REAR_IN + 0.48, FLOOR + 0.82), M["mattress"], bevel=0.05, segments=3), interior)

# Over-cab bunk mattress and ceiling lamps.
part(lib.box("BunkMattress", (-IN + 0.02, 1.35, CAB_TOP + WALL), (IN - 0.02, 2.70, CAB_TOP + WALL + 0.14), M["mattress"], bevel=0.04), interior)
for y in (-2.5, -0.8, 0.6):
    part(lib.cylinder(f"Lamp{y}", 0.12, 0.02, (0, y, LIV_Z1 - WALL - 0.01), "z", M["lamp"], 16), interior)

# Cab: seats, dashboard.
for side, name in ((-1, "Driver"), (1, "Passenger")):
    x = side * 0.52
    part(lib.box(f"SeatBase{name}", (x - 0.26, 1.40, CAB_FLOOR), (x + 0.26, 1.85, CAB_FLOOR + 0.42), M["plastic"]), interior)
    part(lib.box(f"SeatCushion{name}", (x - 0.26, 1.40, CAB_FLOOR + 0.42), (x + 0.26, 1.88, CAB_FLOOR + 0.52), M["fabric"], bevel=0.03), interior)
    part(lib.box(f"SeatBack{name}", (x - 0.26, 1.36, CAB_FLOOR + 0.52), (x + 0.26, 1.48, CAB_FLOOR + 1.25), M["fabric"], bevel=0.03), interior)
part(lib.box("Dashboard", (-CAB_HW + WALL, 2.22, 1.05), (CAB_HW - WALL, 2.50, 1.32), M["plastic"], bevel=0.03), interior)
for i, dx in enumerate((-0.68, -0.52, -0.36)):
    part(lib.cylinder(f"Gauge{i}", 0.05, 0.01, (dx, 2.215, 1.22), "y", M["appliance"], 16), interior)
part(lib.cylinder("SteeringColumn", 0.035, 0.45, (-0.52, 2.20, 1.25), "y", M["plastic"], 8), interior)

# --- moving parts (separate nodes, pivot at origin) ----------------------------------------------
movers = []


def mover(obj, name, pivot):
    """Re-centres `obj` so its origin is `pivot`, then parents it to the RV root."""
    pivot = Vector(pivot)
    obj.data.transform(lib.Matrix.Translation(-pivot))
    obj.location = pivot
    obj.name = name
    lib.box_uv(obj, TILES)
    lib.smooth_by_angle(obj, 40)
    obj.parent = root
    movers.append(obj)
    return obj


# Steering wheel: tilted towards the driver.
wheel = lib.torus("sw_ring", 0.19, 0.022, M["plastic"], 24, 6)
spokes = [lib.box(f"sw_spoke{a}", (-0.012, -0.012, -0.012), (0.012, 0.19, 0.012), M["plastic"]) for a in (0, 120, 240)]
for s, a in zip(spokes, (0, 120, 240)):
    s.rotation_euler = (0, 0, math.radians(a))
hub = lib.cylinder("sw_hub", 0.045, 0.04, (0, 0, 0), "z", M["chrome"], 12)
sw = lib.join([wheel, hub, *spokes], "SteeringWheel")
sw.data.transform(lib.Matrix.Rotation(math.radians(-65), 4, "X"))
sw.location = (-0.52, 2.02, 1.52)
lib.box_uv(sw, TILES)
lib.smooth_by_angle(sw, 50)
sw.parent = root
movers.append(sw)

gear = lib.join([
    lib.cylinder("gs_rod", 0.012, 0.42, (0, 0, 0.21), "z", M["chrome"], 8),
    lib.sphere("gs_knob", 0.04, (0, 0, 0.44), M["plastic"]),
    lib.box("gs_boot", (-0.06, -0.06, 0), (0.06, 0.06, 0.05), M["plastic"], bevel=0.02),
], "GearStick")
gear.location = (0.0, 1.98, CAB_FLOOR)
gear.rotation_euler = (math.radians(10), 0, 0)
lib.smooth_by_angle(gear, 40)
gear.parent = root
movers.append(gear)

brake = lib.join([
    lib.box("hb_lever", (-0.015, -0.30, 0), (0.015, 0.0, 0.04), M["plastic"], bevel=0.01),
    lib.box("hb_grip", (-0.02, -0.32, -0.005), (0.02, -0.22, 0.045), M["trim"], bevel=0.01),
], "Handbrake")
brake.location = (-0.20, 1.95, CAB_FLOOR + 0.20)
brake.rotation_euler = (math.radians(-20), 0, 0)
brake.parent = root
movers.append(brake)

# Entry door (hinged at its rear edge), with its own window and stripes.
door = lib.box("door_panel", (HW - 0.045, 0.06, FLOOR + 0.01), (HW - 0.005, 0.79, 2.71), M["paint"], bevel=0.01)
door.data.materials.append(M["wall"])
lib.cut(door, [window_cutter("door_win", (HW - 0.2, 0.25, 2.05), (HW + 0.2, 0.62, 2.50))])
door_parts = [door, lib.box("door_glass", (HW - 0.028, 0.25, 2.05), (HW - 0.022, 0.62, 2.50), M["glass"]),
              lib.box("door_handle", (HW - 0.005, 0.66, 1.55), (HW + 0.03, 0.74, 1.60), M["chrome"])]
for z, key in stripes:
    door_parts.append(lib.box(f"door_stripe{z}", (HW - 0.005, 0.07, z), (HW - 0.001, 0.78, z + 0.08), M[key]))
mover(lib.join(door_parts, "door"), "Door_Entry", (HW - 0.025, 0.06, FLOOR))


def tyre(name):
    return lib.tyre(name, M["rubber"])


def rim(name, x_off, outward):
    r = lib.cylinder(name, 0.25, 0.18, (x_off, 0, 0), "x", M["rim"], 20)
    hub = lib.cylinder(name + "hub", 0.08, 0.06, (x_off + outward * 0.10, 0, 0), "x", M["chrome"], 12)
    lib.box_uv(r, 0.5)
    lib.box_uv(hub, 0.5)
    return [r, hub]


def wheel_node(name, center, dual, outward):
    parts = []
    offsets = (-0.12, 0.12) if dual else (0.0,)
    for i, off in enumerate(offsets):
        t = tyre(f"{name}_t{i}")
        t.location = (off, 0, 0)
        parts.append(t)
        parts += rim(f"{name}_r{i}", off, outward)
    w = lib.join(parts, name)
    w.location = center
    w.parent = root
    movers.append(w)
    return w


wheel_node("Wheel_FL", (-0.92, FRONT_AXLE, WHEEL_R), False, -1)
wheel_node("Wheel_FR", (0.92, FRONT_AXLE, WHEEL_R), False, 1)
wheel_node("Wheel_RL", (-0.90, REAR_AXLE, WHEEL_R), True, -1)
wheel_node("Wheel_RR", (0.90, REAR_AXLE, WHEEL_R), True, 1)

# Spare tyres lying on the roof rack (removable in game).
for i, y in enumerate((-2.85, -1.95)):
    spare = tyre(f"SpareTire_{i + 1}")
    spare.data.transform(lib.Matrix.Rotation(math.radians(90), 4, "Y"))
    spare.location = (0.0, y, LIV_Z1 + 0.10 + 0.12)
    spare.parent = root
    movers.append(spare)

for name, y, sign in (("Front", 3.66, 1), ("Rear", LIV_Y0 - 0.24, -1)):
    drum = lib.join([
        lib.cylinder("wd", 0.08, 0.30, (0, 0, 0), "x", M["chassis"], 16),
        lib.box("wh", (-0.20, -0.07, -0.10), (0.20, 0.07, -0.06), M["chassis"]),
    ], f"WinchDrum_{name}")
    drum.location = (0, y, 0.58)
    drum.parent = root
    movers.append(drum)
    lib.empty(f"WinchMount_{name}", (0, y + sign * 0.14, 0.58), root)

# --- join static geometry -----------------------------------------------------------------------
body = lib.join(exterior, "Body")
body.parent = root
glass = lib.join(glass_parts, "Glass")
lib.box_uv(glass, 1.0)
glass.parent = root
inside = lib.join(interior, "Interior")
inside.parent = root

# --- gameplay markers -------------------------------------------------------------------------------
for name, loc in {
    "Eye_Driver": (-0.52, 1.50, CAB_FLOOR + 1.18),
    "Seat_Driver": (-0.52, 1.64, CAB_FLOOR + 0.52),
    "Seat_Passenger": (0.52, 1.64, CAB_FLOOR + 0.52),
    "Seat_DinetteRear": (-0.8, 0.22, FLOOR + 0.46),
    "Seat_DinetteFront": (-0.8, 1.02, FLOOR + 0.46),
    "Door_Inside": (0.85, 0.42, FLOOR),
    "Door_Outside": (1.75, 0.42, 0.0),
    "Ladder_Bottom": (0.75, LIV_Y0 - 0.45, 0.0),
    "Ladder_Top": (0.75, LIV_Y0 + 0.4, LIV_Z1),
    "Headlight_L": (-0.76, 3.50, 0.92),
    "Headlight_R": (0.76, 3.50, 0.92),
    "CenterOfMass": (0.0, 0.2, 1.05),
}.items():
    lib.empty(name, loc, root)

all_nodes = lib.descendants(root)
print(f"RV: body {lib.tri_count([body])} tris, interior {lib.tri_count([inside])}, "
      f"glass {lib.tri_count([glass])}, moving parts {lib.tri_count(movers)}, total {lib.tri_count(all_nodes)}")
lib.export_glb([root], lib.OUT / "rv.glb")

# --- collision (separate file, never rendered) -----------------------------------------------------
col_mat = lib.material("Collision", (1, 0, 1))
col_root = lib.empty("RVCollision", (0, 0, 0))
hull = {
    "Hull_Living": ((-HW, LIV_Y0, LIV_Z0), (HW, LIV_Y1, LIV_Z1)),
    "Hull_Overcab": ((-HW, LIV_Y1, CAB_TOP), (HW, 2.80, LIV_Z1)),
    "Hull_Cab": ((-CAB_HW, LIV_Y1, CAB_Z0), (CAB_HW, 2.55, CAB_TOP)),
    "Hull_Hood": ((-1.0, 2.55, 0.55), (1.0, 3.46, 1.30)),
    "Hull_Bumper": ((-1.12, 3.42, 0.42), (1.12, 3.62, 0.66)),
}
inner = {
    "Interior_Floor": ((-IN, REAR_IN, LIV_Z0), (IN, FRONT_IN, FLOOR)),
    "Interior_CabFloor": ((-CAB_HW, FRONT_IN, CAB_Z0), (CAB_HW, 2.55, CAB_FLOOR)),
    "Interior_Ceiling": ((-HW, LIV_Y0, LIV_Z1 - WALL), (HW, 2.80, LIV_Z1)),
    "Interior_WallL": ((-HW, LIV_Y0, LIV_Z0), (-IN, LIV_Y1, LIV_Z1)),
    "Interior_WallR_Rear": ((IN, LIV_Y0, LIV_Z0), (HW, 0.05, LIV_Z1)),
    "Interior_WallR_Front": ((IN, 0.80, LIV_Z0), (HW, LIV_Y1, LIV_Z1)),
    "Interior_WallR_AboveDoor": ((IN, 0.05, 2.72), (HW, 0.80, LIV_Z1)),
    "Interior_WallRear": ((-HW, LIV_Y0, LIV_Z0), (HW, REAR_IN, LIV_Z1)),
    "Interior_BunkFloor": ((-HW, FRONT_IN, CAB_TOP), (HW, 2.80, CAB_TOP + WALL)),
    "Interior_CabWallL": ((-CAB_HW, LIV_Y1, CAB_Z0), (-CAB_HW + WALL, 2.55, CAB_TOP)),
    "Interior_CabWallR": ((CAB_HW - WALL, LIV_Y1, CAB_Z0), (CAB_HW, 2.55, CAB_TOP)),
    "Interior_Dash": ((-CAB_HW, 2.22, CAB_Z0), (CAB_HW, 2.55, 1.32)),
    "Interior_BenchRear": ((-IN, 0.0, FLOOR), (-0.45, 0.42, FLOOR + 0.46)),
    "Interior_BenchFront": ((-IN, 0.82, FLOOR), (-0.45, FRONT_IN, FLOOR + 0.46)),
    "Interior_Table": ((-IN, 0.44, FLOOR + 0.70), (-0.40, 0.80, FLOOR + 0.74)),
    "Interior_Kitchen": ((0.52, KY0, FLOOR), (IN, KY1, FLOOR + 0.92)),
    "Interior_Fridge": ((-IN, -1.00, FLOOR), (-0.50, -0.20, FLOOR + 1.75)),
    "Interior_Wardrobe": ((-IN, -1.95, FLOOR), (-0.55, -1.05, 2.90)),
    "Interior_Bed": ((-IN, REAR_IN, FLOOR), (IN, BED_Y, FLOOR + 0.70)),
    "Interior_SeatDriver": ((-0.78, 1.36, CAB_FLOOR), (-0.26, 1.88, CAB_FLOOR + 0.52)),
    "Interior_SeatPassenger": ((0.26, 1.36, CAB_FLOOR), (0.78, 1.88, CAB_FLOOR + 0.52)),
}
for name, (lo, hi) in {**hull, **inner}.items():
    lib.box(name, lo, hi, col_mat).parent = col_root
lib.export_glb([col_root], lib.OUT / "rv_collision.glb")
for o in lib.descendants(col_root):
    o.hide_render = True

# --- previews -------------------------------------------------------------------------------------
PREV = lib.BUILD / "previews"
lib.render_preview(PREV / "rv_front.png", target=(0, 0, 1.6), distance=11, elevation=12, azimuth=40)
lib.render_preview(PREV / "rv_rear.png", target=(0, -0.5, 1.6), distance=11, elevation=18, azimuth=215)
lib.render_preview(PREV / "rv_side_door.png", target=(0.5, 0, 1.5), distance=9, elevation=8, azimuth=95)
# Interior, from just behind the cab looking back towards the bed (preview-only lights).
for i, y in enumerate((-2.4, -0.6, 0.8)):
    light = lib.bpy.data.lights.new(f"PreviewLamp{i}", "POINT")
    light.energy = 60
    lib.link(lib.bpy.data.objects.new(f"PreviewLamp{i}", light)).location = (0, y, 2.6)
lib.render_preview(PREV / "rv_interior.png", target=(-0.1, -2.6, 1.3), camera_loc=(0.35, 1.15, 1.95), lens=16)

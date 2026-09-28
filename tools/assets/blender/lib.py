"""Shared helpers for Detour's Blender asset builders. Runs inside Blender (bpy).

Geometry is built with bmesh and modifiers are applied through the depsgraph rather than
operators, so everything works headless (`blender --background --python ...`).
Conventions: metres, +Z up, **+Y forward** (the glTF exporter turns +Y into Godot's -Z).
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[3]
TEX_CACHE = ROOT / "art-src" / "cache" / "textures"
MODEL_CACHE = ROOT / "art-src" / "cache" / "models"
BUILD = ROOT / "art-src" / "build"
OUT = ROOT / "game" / "assets" / "models"


# --- scene ------------------------------------------------------------------------------------

#: Scene everything is built into. Headless: the factory-fresh scene. Live (driven over the
#: Blender MCP socket): a dedicated scene, so the user's own scenes are never touched.
SCENE: bpy.types.Scene | None = None
LIVE = not bpy.app.background


def reset(name: str = "Detour") -> bpy.types.Scene:
    global SCENE
    if not LIVE:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        SCENE = bpy.context.scene
        return SCENE
    old = bpy.data.scenes.get(name)
    if old is not None:
        for o in list(old.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        bpy.data.scenes.remove(old)
    SCENE = bpy.data.scenes.new(name)
    for window in bpy.context.window_manager.windows:
        window.scene = SCENE
        break
    return SCENE


def view_layer() -> bpy.types.ViewLayer:
    return SCENE.view_layers[0]


def update() -> None:
    view_layer().update()


def link(obj: bpy.types.Object) -> bpy.types.Object:
    SCENE.collection.objects.link(obj)
    return obj


def empty(name: str, loc, parent=None) -> bpy.types.Object:
    obj = link(bpy.data.objects.new(name, None))
    obj.empty_display_type = "PLAIN_AXES"
    obj.empty_display_size = 0.2
    obj.location = Vector(loc)
    if parent is not None:
        obj.parent = parent
    return obj


def parent_keep(child: bpy.types.Object, parent: bpy.types.Object) -> None:
    """Parents without moving the child in world space."""
    mw = child.matrix_world.copy()
    child.parent = parent
    child.matrix_world = mw


# --- textures ---------------------------------------------------------------------------------

def texture_maps(key: str) -> dict[str, Path]:
    meta = TEX_CACHE / key / "maps.json"
    if not meta.exists():
        return {}
    maps = json.loads(meta.read_text())["maps"]
    return {k: TEX_CACHE / key / v for k, v in maps.items() if (TEX_CACHE / key / v).exists()}


def load_image(path: Path, non_color: bool = False) -> bpy.types.Image:
    img = bpy.data.images.load(str(path), check_existing=True)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    return img


def _pixels(img: bpy.types.Image) -> np.ndarray:
    buf = np.empty(len(img.pixels), dtype=np.float32)
    img.pixels.foreach_get(buf)
    return buf.reshape(-1, 4)


def recolored(key: str, tint, name: str, detail: float = 0.6, ao: float = 0.6) -> bpy.types.Image | None:
    """Recolours a texture set's albedo to `tint` (sRGB), keeping its surface detail
    (luminance variation, scaled by `detail`) and multiplying in its AO map."""
    maps = texture_maps(key)
    if "diffuse" not in maps:
        return None
    src = load_image(maps["diffuse"])
    px = _pixels(src)
    lum = px[:, :3] @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    rel = lum / max(float(lum.mean()), 1e-4)
    shade = 1.0 + (rel - 1.0) * detail
    ao_map = maps.get("ao") or maps.get("arm")
    if ao_map is not None and ao > 0.0:
        ao_img = load_image(ao_map, non_color=True)
        if tuple(ao_img.size) == tuple(src.size):
            shade *= 1.0 - ao + ao * _pixels(ao_img)[:, 0]
    out = np.empty_like(px)
    out[:, :3] = np.clip(np.outer(shade, np.array(tint[:3], dtype=np.float32)), 0.0, 1.0)
    out[:, 3] = 1.0
    w, h = src.size
    img = bpy.data.images.new(name, w, h)
    img.pixels.foreach_set(out.ravel())
    path = BUILD / "textures" / f"{name}.jpg"
    path.parent.mkdir(parents=True, exist_ok=True)
    img.filepath_raw = str(path)
    img.file_format = "JPEG"
    img.save()
    return img


# --- materials --------------------------------------------------------------------------------

def _set(node, names, value) -> None:
    for n in names if isinstance(names, (list, tuple)) else [names]:
        if n in node.inputs:
            node.inputs[n].default_value = value
            return


def material(
    name: str,
    color=(0.8, 0.8, 0.8),
    tex: str | None = None,
    recolor=None,
    detail: float = 0.6,
    rough: float = 0.6,
    metal: float = 0.0,
    normal_strength: float = 1.0,
    emission=None,
    emission_strength: float = 2.0,
    alpha: float = 1.0,
) -> bpy.types.Material:
    """Principled material, optionally textured from a downloaded Poly Haven set.
    `recolor` (sRGB tint) recolours the albedo; otherwise the texture's own colours are used."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    _set(bsdf, "Base Color", (*color[:3], 1.0))
    _set(bsdf, "Roughness", rough)
    _set(bsdf, "Metallic", metal)

    maps = texture_maps(tex) if tex else {}
    if "diffuse" in maps:
        img = recolored(tex, recolor, f"{name}_albedo", detail) if recolor else load_image(maps["diffuse"])
        node = nt.nodes.new("ShaderNodeTexImage")
        node.image = img
        nt.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
    if "normal" in maps:
        img_node = nt.nodes.new("ShaderNodeTexImage")
        img_node.image = load_image(maps["normal"], non_color=True)
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nmap.inputs["Strength"].default_value = normal_strength
        nt.links.new(img_node.outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    if "arm" in maps and metal == 0.0:
        # AO/Roughness/Metal packed (R/G/B): the glTF exporter writes it straight through as
        # metallicRoughness. Only for non-metals; metals keep their constant metallic value.
        img_node = nt.nodes.new("ShaderNodeTexImage")
        img_node.image = load_image(maps["arm"], non_color=True)
        sep_type = "ShaderNodeSeparateColor" if hasattr(bpy.types, "ShaderNodeSeparateColor") else "ShaderNodeSeparateRGB"
        sep = nt.nodes.new(sep_type)
        nt.links.new(img_node.outputs["Color"], sep.inputs[0])
        nt.links.new(sep.outputs[1], bsdf.inputs["Roughness"])
        nt.links.new(sep.outputs[2], bsdf.inputs["Metallic"])
    elif "rough" in maps:
        img_node = nt.nodes.new("ShaderNodeTexImage")
        img_node.image = load_image(maps["rough"], non_color=True)
        nt.links.new(img_node.outputs["Color"], bsdf.inputs["Roughness"])

    if emission is not None:
        _set(bsdf, ["Emission Color", "Emission"], (*emission[:3], 1.0))
        _set(bsdf, "Emission Strength", emission_strength)
    if alpha < 1.0:
        _set(bsdf, "Alpha", alpha)
        if hasattr(mat, "surface_render_method"):
            mat.surface_render_method = "BLENDED"
        if hasattr(mat, "blend_method"):
            try:
                mat.blend_method = "BLEND"
            except (TypeError, AttributeError):
                pass
    return mat


# --- mesh construction ------------------------------------------------------------------------

def mesh_object(name: str, bm: bmesh.types.BMesh, mats) -> bpy.types.Object:
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    return link(bpy.data.objects.new(name, me))


def box(name: str, lo, hi, mat, bevel: float = 0.0, segments: int = 2) -> bpy.types.Object:
    """Axis-aligned box from corner `lo` to corner `hi`."""
    lo, hi = Vector(lo), Vector(hi)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=hi - lo, verts=bm.verts)
    bmesh.ops.translate(bm, vec=(lo + hi) / 2, verts=bm.verts)
    obj = mesh_object(name, bm, [mat])
    if bevel > 0.0:
        add_bevel(obj, bevel, segments)
        apply_modifiers(obj)
    return obj


def prism(name: str, profile_yz, x0: float, x1: float, mats, bevel: float = 0.0, segments: int = 2) -> bpy.types.Object:
    """Extrudes a side profile (list of (y, z), counter-clockwise seen from +X) along X."""
    bm = bmesh.new()
    verts = [bm.verts.new((x0, y, z)) for y, z in profile_yz]
    face = bm.faces.new(verts)
    ext = bmesh.ops.extrude_face_region(bm, geom=[face])
    moved = [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(x1 - x0, 0, 0), verts=moved)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = mesh_object(name, bm, mats if isinstance(mats, (list, tuple)) else [mats])
    if bevel > 0.0:
        add_bevel(obj, bevel, segments)
        apply_modifiers(obj)
    return obj


def cylinder(name: str, radius: float, depth: float, center, axis: str, mat, segments: int = 16,
             radius_top: float | None = None, bevel: float = 0.0) -> bpy.types.Object:
    bm = bmesh.new()
    bmesh.ops.create_cone(
        bm, cap_ends=True, cap_tris=False, segments=segments,
        radius1=radius, radius2=radius if radius_top is None else radius_top, depth=depth,
    )
    rot = {"x": Matrix.Rotation(math.radians(90), 4, "Y"), "y": Matrix.Rotation(math.radians(-90), 4, "X"), "z": Matrix()}[axis]
    bmesh.ops.transform(bm, matrix=rot, verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    obj = mesh_object(name, bm, [mat])
    if bevel > 0.0:
        add_bevel(obj, bevel, 2)
        apply_modifiers(obj)
    return obj


def sphere(name: str, radius: float, center, mat, segments: int = 10, rings: int = 6) -> bpy.types.Object:
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=radius)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return mesh_object(name, bm, [mat])


def torus(name: str, major: float, minor: float, mat, seg: int = 20, ring: int = 6) -> bpy.types.Object:
    """Torus around the local Z axis, centred on the origin."""
    bm = bmesh.new()
    grid = []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        row = []
        for j in range(ring):
            b = 2 * math.pi * j / ring
            r = major + minor * math.cos(b)
            row.append(bm.verts.new((r * math.cos(a), r * math.sin(a), minor * math.sin(b))))
        grid.append(row)
    for i in range(seg):
        for j in range(ring):
            a, b = grid[i][j], grid[(i + 1) % seg][j]
            c, d = grid[(i + 1) % seg][(j + 1) % ring], grid[i][(j + 1) % ring]
            bm.faces.new((a, b, c, d))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return mesh_object(name, bm, [mat])


def lathe(name: str, profile_xr, mat, segments: int = 24) -> bpy.types.Object:
    """Spins a profile of (x, radius) points around the X axis (tyres, bottles, drums)."""
    bm = bmesh.new()
    verts = [bm.verts.new((x, 0.0, r)) for x, r in profile_xr]
    edges = [bm.edges.new((verts[i], verts[i + 1])) for i in range(len(verts) - 1)]
    bmesh.ops.spin(
        bm, geom=verts + edges, cent=(0, 0, 0), axis=(1, 0, 0),
        angle=2 * math.pi, steps=segments, use_merge=True,
    )
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return mesh_object(name, bm, [mat])


def tyre(name: str, mat, segments: int = 28) -> bpy.types.Object:
    """0.8 m tyre (0.24 m wide) around the local X axis; open centre, filled by a rim."""
    profile = [(-0.11, 0.25), (-0.12, 0.30), (-0.12, 0.35), (-0.10, 0.39), (-0.06, 0.40),
               (0.06, 0.40), (0.10, 0.39), (0.12, 0.35), (0.12, 0.30), (0.11, 0.25)]
    t = lathe(name, profile, mat, segments)
    cylinder_uv(t, 0.45)
    smooth_by_angle(t, 50)
    return t


# --- modifiers --------------------------------------------------------------------------------

def add_bevel(obj, width: float, segments: int = 2, angle: float = 40.0):
    mod = obj.modifiers.new("Bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    mod.angle_limit = math.radians(angle)
    return mod


def apply_modifiers(obj) -> None:
    dg = view_layer().depsgraph
    dg.update()
    ev = obj.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
    old = obj.data
    obj.modifiers.clear()
    obj.data = me
    me.name = old.name
    bpy.data.meshes.remove(old)


def solidify(obj, thickness: float, inner_offset: int = 1, rim_offset: int = 2) -> None:
    """Hollows a closed mesh inwards. Inner faces use material slot +`inner_offset`,
    rim faces slot +`rim_offset`."""
    mod = obj.modifiers.new("Solidify", "SOLIDIFY")
    mod.thickness = thickness
    mod.offset = -1.0
    mod.use_even_offset = True
    mod.material_offset = inner_offset
    mod.material_offset_rim = rim_offset
    apply_modifiers(obj)


def cut(obj, cutters: list, remove: bool = True) -> None:
    """Boolean-subtracts `cutters`; cut faces take the cutters' materials."""
    coll = bpy.data.collections.new(f"{obj.name}_cutters")
    SCENE.collection.children.link(coll)
    for c in cutters:
        for users in list(c.users_collection):
            users.objects.unlink(c)
        coll.objects.link(c)
    mod = obj.modifiers.new("Cut", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.operand_type = "COLLECTION"
    mod.collection = coll
    mod.solver = "EXACT"
    if hasattr(mod, "material_mode"):
        mod.material_mode = "TRANSFER"
    apply_modifiers(obj)
    if remove:
        for c in list(coll.objects):
            bpy.data.objects.remove(c, do_unlink=True)
        bpy.data.collections.remove(coll)


def decimate(obj, target_tris: int) -> None:
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    if tris <= target_tris:
        return
    # Scans often ship with every triangle unwelded; collapse can't touch those, so weld
    # first. UVs live on face corners, so seams survive the merge.
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bm.to_mesh(obj.data)
    bm.free()
    for _ in range(3):
        tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
        if tris <= target_tris * 1.05:
            break
        mod = obj.modifiers.new("Decimate", "DECIMATE")
        mod.ratio = target_tris / tris
        apply_modifiers(obj)


# --- shading & UVs ----------------------------------------------------------------------------

def smooth_by_angle(obj, degrees: float = 35.0) -> None:
    """Smooth shading with sharp edges above `degrees` (works on all Blender 3.x/4.x versions)."""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    limit = math.radians(degrees)
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        e.smooth = not (len(e.link_faces) == 2 and e.calc_face_angle(0.0) > limit)
    bm.to_mesh(me)
    bm.free()
    if hasattr(me, "use_auto_smooth"):
        me.use_auto_smooth = True
        me.auto_smooth_angle = math.pi


def box_uv(obj, tile=1.0) -> None:
    """World-space box projection. `tile` is metres per texture repeat, either one value or
    a dict {material_name: metres} (default 1.0)."""
    update()
    me = obj.data
    names = [m.name if m else "" for m in me.materials]
    bm = bmesh.new()
    bm.from_mesh(me)
    uv = bm.loops.layers.uv.verify()
    mw = obj.matrix_world
    nmat = mw.to_3x3().inverted().transposed()
    for f in bm.faces:
        t = tile.get(names[f.material_index] if f.material_index < len(names) else "", 1.0) if isinstance(tile, dict) else tile
        n = nmat @ f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for loop in f.loops:
            co = mw @ loop.vert.co
            if ax == 0:
                u, v = (co.y if n.x > 0 else -co.y), co.z
            elif ax == 1:
                u, v = (-co.x if n.y > 0 else co.x), co.z
            else:
                u, v = co.x, (co.y if n.z > 0 else -co.y)
            loop[uv].uv = (u / t, v / t)
    bm.to_mesh(me)
    bm.free()


def cylinder_uv(obj, tile: float = 1.0) -> None:
    """Cylindrical projection around the object's local X axis (tyres, drums)."""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        angs = [math.atan2(l.vert.co.z, l.vert.co.y) for l in f.loops]
        # Keep faces that straddle the seam contiguous.
        if max(angs) - min(angs) > math.pi:
            angs = [a + 2 * math.pi if a < 0 else a for a in angs]
        for loop, a in zip(f.loops, angs):
            r = math.hypot(loop.vert.co.y, loop.vert.co.z)
            loop[uv].uv = (a * r / tile, loop.vert.co.x / tile)
    bm.to_mesh(me)
    bm.free()


# --- joining & export -------------------------------------------------------------------------

def join(objs, name: str) -> bpy.types.Object:
    """Merges objects into one mesh (world space), unifying material slots."""
    update()  # matrix_world is stale after setting location/rotation.
    mats: list = []
    bm = bmesh.new()
    for o in objs:
        remap = []
        for m in o.data.materials:
            if m not in mats:
                mats.append(m)
            remap.append(mats.index(m))
        tmp = bmesh.new()
        tmp.from_mesh(o.data)
        tmp.transform(o.matrix_world)
        for f in tmp.faces:
            f.material_index = remap[f.material_index] if remap else 0
        tmp_me = bpy.data.meshes.new("_join_tmp")
        tmp.to_mesh(tmp_me)
        tmp.free()
        bm.from_mesh(tmp_me)
        bpy.data.meshes.remove(tmp_me)
    for o in objs:
        bpy.data.objects.remove(o, do_unlink=True)
    return mesh_object(name, bm, mats)


def tri_count(objs) -> int:
    return sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs if o.type == "MESH")


def descendants(obj) -> list:
    out = [obj]
    for c in obj.children:
        out += descendants(c)
    return out


def export_glb(roots, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    vl = view_layer()
    for o in SCENE.objects:
        o.select_set(False, view_layer=vl)
    chosen = []
    for r in roots:
        chosen += descendants(r)
    for o in chosen:
        o.select_set(True, view_layer=vl)
    with bpy.context.temp_override(scene=SCENE, view_layer=vl):
        bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True, export_apply=True)
    print(f"EXPORT {path.relative_to(ROOT)}  {tri_count(chosen)} tris, {len(chosen)} nodes")


# --- previews ---------------------------------------------------------------------------------

def render_preview(path: Path, target=(0, 0, 1.2), distance: float = 12.0, elevation: float = 15.0,
                   azimuth: float = 35.0, size=(1280, 720), camera_loc=None, lens: float = 40.0) -> None:
    """Renders a quick look at the scene (EEVEE if available, else Workbench). Skipped in a live
    session, where the viewport itself is the preview."""
    if LIVE:
        return
    scene = SCENE
    engines = {e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items}
    engine = next((e for e in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE") if e in engines), "BLENDER_WORKBENCH")
    scene.render.engine = engine
    if engine == "BLENDER_WORKBENCH":
        scene.display.shading.light = "STUDIO"
        scene.display.shading.color_type = "TEXTURE"
    else:
        if scene.world is None:
            scene.world = bpy.data.worlds.new("World")
        scene.world.use_nodes = True
        bg = scene.world.node_tree.nodes.get("Background")
        bg.inputs["Color"].default_value = (0.55, 0.65, 0.78, 1.0)
        bg.inputs["Strength"].default_value = 0.9
        if "PreviewSun" in bpy.data.objects:
            bpy.data.objects.remove(bpy.data.objects["PreviewSun"], do_unlink=True)
        sun = bpy.data.lights.new("PreviewSun", "SUN")
        sun.energy = 3.5
        sun_obj = link(bpy.data.objects.new("PreviewSun", sun))
        sun_obj.rotation_euler = (math.radians(50), math.radians(10), math.radians(40))
        ground = box("PreviewGround", (-40, -40, -0.02), (40, 40, 0.0), material("PreviewGround", (0.35, 0.42, 0.25), rough=0.9))
        ground.hide_select = True
    t = Vector(target)
    az, el = math.radians(azimuth), math.radians(elevation)
    loc = t + distance * Vector((math.sin(az) * math.cos(el), math.cos(az) * math.cos(el), math.sin(el)))
    if camera_loc is not None:
        loc = Vector(camera_loc)
    cam_data = bpy.data.cameras.new("PreviewCam")
    cam_data.lens = lens
    cam = link(bpy.data.objects.new("PreviewCam", cam_data))
    cam.location = loc
    cam.rotation_euler = (t - loc).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.filepath = str(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.render.render(write_still=True)
    # Remove preview helpers so they never get exported.
    for name in ("PreviewCam", "PreviewSun", "PreviewGround"):
        o = bpy.data.objects.get(name)
        if o is not None:
            bpy.data.objects.remove(o, do_unlink=True)
    print(f"PREVIEW {path}")

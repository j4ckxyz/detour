"""Renders the app icon (game/icon.png, 512 x 512) from the built RV model.

    blender --background --factory-startup --python tools/assets/blender/build_icon.py

Run build_rv.py first. Godot turns this into the macOS .icns; the Linux AppImage uses it as is.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy  # noqa: E402
import lib  # noqa: E402

lib.reset("Detour_Icon")
with bpy.context.temp_override(scene=lib.SCENE, view_layer=lib.view_layer()):
    bpy.ops.import_scene.gltf(filepath=str(lib.OUT / "rv.glb"))
lib.SCENE.render.film_transparent = False
lib.render_preview(lib.ROOT / "game" / "icon.png", target=(0, 0.2, 1.45), distance=10.5,
                   elevation=14, azimuth=38, size=(512, 512), lens=50)

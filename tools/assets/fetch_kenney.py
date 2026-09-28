#!/usr/bin/env python3
"""Fetch the CC0 Kenney (www.kenney.nl) models the game uses into game/assets/models/kenney/<kit>/.

    python3 tools/assets/fetch_kenney.py

Kits are downloaded once into art-src/cache/kenney/ (git-ignored); only the chosen models are
copied into the game (and committed), under the names in MODELS. All Kenney assets are
Creative Commons Zero (public domain); credited in game/assets/CREDITS.md anyway.
"""

from __future__ import annotations

import shutil
import sys
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / "art-src" / "cache" / "kenney"
OUT = ROOT / "game" / "assets" / "models" / "kenney"

KITS = {
    "nature": "https://kenney.nl/media/pages/assets/nature-kit/37ac38a37b-1677698939/kenney_nature-kit.zip",
    "survival": "https://kenney.nl/media/pages/assets/survival-kit/4065a8185b-1712149243/kenney_survival-kit.zip",
    "suburban": "https://kenney.nl/media/pages/assets/city-kit-suburban/2c871b7af2-1745479373/kenney_city-kit-suburban_20.zip",
    "commercial": "https://kenney.nl/media/pages/assets/city-kit-commercial/a742d900eb-1753115042/kenney_city-kit-commercial_2.1.zip",
}

# game name -> (kit, file name inside the kit)
MODELS = {
    # The start camp.
    "tent": ("nature", "tent_detailedOpen.glb"),
    "campfire": ("nature", "campfire_stones.glb"),
    "log_stack": ("nature", "log_stack.glb"),
    "bedroll": ("survival", "bedroll.glb"),
    # Signs.
    "signpost": ("survival", "signpost.glb"),
    "signpost_single": ("survival", "signpost-single.glb"),
    # Gas stations.
    "shop": ("commercial", "low-detail-building-a.glb"),
    "awning": ("commercial", "detail-awning-wide.glb"),
    "workbench": ("survival", "workbench-anvil.glb"),
    "barrel": ("survival", "barrel.glb"),
    "crate": ("survival", "box-large.glb"),
    # Home.
    "house": ("suburban", "building-type-a.glb"),
    "fence": ("suburban", "fence-1x4.glb"),
    "driveway": ("suburban", "driveway-long.glb"),
    # Tools.
    "hammer": ("survival", "tool-hammer.glb"),
    # Scenery.
    "bush": ("nature", "plant_bush.glb"),
    "bush_large": ("nature", "plant_bushLarge.glb"),
    "flowers_red": ("nature", "flower_redA.glb"),
    "flowers_yellow": ("nature", "flower_yellowA.glb"),
    "flowers_purple": ("nature", "flower_purpleA.glb"),
    "mushrooms": ("nature", "mushroom_tanGroup.glb"),
    "grass_tuft": ("nature", "grass_large.glb"),
}


def kit_dir(kit: str) -> Path:
    url = KITS[kit]
    archive = CACHE / Path(url).name
    target = CACHE / archive.stem
    if not target.exists():
        CACHE.mkdir(parents=True, exist_ok=True)
        if not archive.exists():
            print(f"downloading {kit} kit", flush=True)
            with urllib.request.urlopen(url) as r, open(archive, "wb") as f:
                shutil.copyfileobj(r, f)
        with zipfile.ZipFile(archive) as z:
            z.extractall(target)
    return target


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    missing = []
    for name, (kit, file) in MODELS.items():
        found = [p for p in kit_dir(kit).rglob(file) if "GLB" in p.parts or "glb" in str(p.parent).lower() or p.suffix == ".glb"]
        if not found:
            missing.append(f"{kit}/{file}")
            continue
        # Models reference their kit's Textures/colormap.png: keep one folder per kit.
        dest = OUT / kit
        dest.mkdir(parents=True, exist_ok=True)
        shutil.copy2(found[0], dest / f"{name}.glb")
        colormap = found[0].parent / "Textures" / "colormap.png"
        if colormap.exists():
            (dest / "Textures").mkdir(exist_ok=True)
            shutil.copy2(colormap, dest / "Textures" / "colormap.png")
        print(f"  {kit}/{name:16} <- {file}")
    if missing:
        print("missing:", ", ".join(missing))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

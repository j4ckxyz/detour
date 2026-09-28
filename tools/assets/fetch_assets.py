#!/usr/bin/env python3
"""Download the CC0 textures and models listed in manifest.json from Poly Haven.

    python3 tools/assets/fetch_assets.py            # resolve (pinning in assets.lock.json) + download
    python3 tools/assets/fetch_assets.py --search rock --type models   # browse the catalogue

Files land in art-src/cache/ (gitignored, re-downloadable). Every asset used is recorded,
with its licence and source URL, in game/assets/CREDITS.md.
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
MANIFEST = HERE / "manifest.json"
LOCK = HERE / "assets.lock.json"
CACHE = ROOT / "art-src" / "cache"
CREDITS = ROOT / "game" / "assets" / "CREDITS.md"
API = "https://api.polyhaven.com"
# Poly Haven asks API users to send an identifying User-Agent.
HEADERS = {"User-Agent": "detour-game-asset-fetch/0.1 (open-source game)"}

# Texture map aliases in Poly Haven's /files response -> our file names.
MAP_ALIASES = {
    "diffuse": ["diffuse", "diff", "albedo", "col"],
    "normal": ["nor_gl"],
    "arm": ["arm"],
    "rough": ["rough", "roughness"],
    "ao": ["ao"],
    "metal": ["metal", "metallic"],
}


def get_json(url: str):
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def download(url: str, dest: Path) -> None:
    if dest.exists() and dest.stat().st_size > 0:
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=120) as r, open(dest, "wb") as f:
        f.write(r.read())
    print(f"  downloaded {dest.relative_to(ROOT)}")


def catalogue(kind: str) -> dict:
    return get_json(f"{API}/assets?type={kind}")


def haystack(asset_id: str, info: dict) -> str:
    parts = [asset_id, info.get("name", "")]
    parts += info.get("tags", []) + info.get("categories", [])
    return " ".join(parts).lower().replace("_", " ")


def resolve(spec: dict, cat: dict, taken: set[str]) -> str | None:
    for asset_id in spec.get("prefer", []):
        if asset_id in cat and asset_id not in taken:
            return asset_id
    for query in spec.get("search", []):
        words = query.lower().split()
        hits = [
            (info.get("download_count", 0), asset_id)
            for asset_id, info in cat.items()
            if asset_id not in taken and all(w in haystack(asset_id, info) for w in words)
        ]
        if hits:
            return max(hits)[1]
    return None


def pick_url(entry: dict, resolution: str, formats: list[str]) -> str | None:
    by_res = entry.get(resolution) or entry.get("1k") or next(iter(entry.values()), None)
    if not isinstance(by_res, dict):
        return None
    for fmt in formats:
        if fmt in by_res and "url" in by_res[fmt]:
            return by_res[fmt]["url"]
    return None


def fetch_texture(key: str, asset_id: str, resolution: str) -> None:
    files = get_json(f"{API}/files/{asset_id}")
    lower = {k.lower(): v for k, v in files.items()}
    out_dir = CACHE / "textures" / key
    found = {}
    for our_name, aliases in MAP_ALIASES.items():
        for alias in aliases:
            if alias in lower:
                url = pick_url(lower[alias], resolution, ["jpg", "png"])
                if url:
                    ext = Path(url).suffix
                    download(url, out_dir / f"{our_name}{ext}")
                    found[our_name] = f"{our_name}{ext}"
                    break
    if "diffuse" not in found:
        print(f"  WARNING: {asset_id} has no diffuse map; keys were {sorted(files)}")
    (out_dir / "maps.json").write_text(json.dumps({"id": asset_id, "maps": found}, indent=2))


def fetch_model(key: str, asset_id: str, resolution: str) -> None:
    files = get_json(f"{API}/files/{asset_id}")
    gltf = files.get("gltf", {})
    by_res = gltf.get(resolution) or gltf.get("1k") or next(iter(gltf.values()), {})
    entry = by_res.get("gltf") if isinstance(by_res, dict) else None
    if not entry:
        print(f"  WARNING: {asset_id} has no glTF download; keys were {sorted(files)}")
        return
    out_dir = CACHE / "models" / key
    main = out_dir / Path(entry["url"]).name
    download(entry["url"], main)
    for rel_path, inc in entry.get("include", {}).items():
        download(inc["url"], out_dir / rel_path)
    (out_dir / "model.json").write_text(json.dumps({"id": asset_id, "gltf": main.name}, indent=2))


def write_credits(lock: dict, cats: dict) -> None:
    lines = [
        "# Third-party assets",
        "",
        "All assets below are **CC0** (public domain) from [Poly Haven](https://polyhaven.com).",
        "Credit is not required, but we give it gladly. Models built from them live in",
        "`game/assets/models/` and are made by `tools/assets/blender/*.py`.",
        "",
        "| Used as | Asset | Authors |",
        "|---|---|---|",
    ]
    for kind in ("textures", "models"):
        for key, asset_id in sorted(lock.get(kind, {}).items()):
            info = cats[kind].get(asset_id, {})
            authors = ", ".join(info.get("authors", {}).keys()) or "Poly Haven"
            lines.append(
                f"| {kind[:-1]} `{key}` | [{info.get('name', asset_id)}](https://polyhaven.com/a/{asset_id}) | {authors} |"
            )
    CREDITS.parent.mkdir(parents=True, exist_ok=True)
    CREDITS.write_text("\n".join(lines) + "\n")
    print(f"wrote {CREDITS.relative_to(ROOT)}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--search", help="list catalogue entries matching these words")
    ap.add_argument("--type", default="textures", choices=["textures", "models"])
    ap.add_argument("--relock", action="store_true", help="ignore assets.lock.json and resolve again")
    args = ap.parse_args()

    if args.search:
        cat = catalogue(args.type)
        words = args.search.lower().split()
        hits = sorted(
            ((info.get("download_count", 0), aid, info.get("name", "")) for aid, info in cat.items()
             if all(w in haystack(aid, info) for w in words)),
            reverse=True,
        )
        for count, aid, name in hits[:40]:
            print(f"{aid:40} {name:40} {count:>8} downloads")
        return 0

    manifest = json.loads(MANIFEST.read_text())
    lock = {} if args.relock or not LOCK.exists() else json.loads(LOCK.read_text())
    cats = {"textures": catalogue("textures"), "models": catalogue("models")}
    resolution = manifest.get("resolution", "1k")
    missing = []

    for kind in ("textures", "models"):
        pinned = lock.setdefault(kind, {})
        taken: set[str] = set()
        for key, spec in manifest[kind].items():
            asset_id = pinned.get(key)
            if asset_id not in cats[kind]:
                asset_id = resolve(spec, cats[kind], taken)
            if not asset_id:
                missing.append(f"{kind}/{key}")
                continue
            taken.add(asset_id)
            pinned[key] = asset_id
            print(f"{kind[:-1]} {key}: {asset_id}")
            if kind == "textures":
                fetch_texture(key, asset_id, resolution)
            else:
                fetch_model(key, asset_id, resolution)

    LOCK.write_text(json.dumps(lock, indent=2, sort_keys=True) + "\n")
    write_credits(lock, cats)
    if missing:
        print("No match for:", ", ".join(missing), "(builders fall back to plain materials)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

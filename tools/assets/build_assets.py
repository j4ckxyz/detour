#!/usr/bin/env python3
"""Build every game model: fetch CC0 textures/models, run the Blender builders headless,
then (optionally) show the results in a running Blender via the MCP add-on socket.

    python3 tools/assets/build_assets.py            # fetch + build all
    python3 tools/assets/build_assets.py rv props   # only some builders
    python3 tools/assets/build_assets.py --live     # also import results into open Blender
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
BLENDER = os.environ.get("BLENDER", "/Applications/Blender.app/Contents/MacOS/Blender")
BUILDERS = {
    "rv": ["rv.glb", "rv_collision.glb"],
    "nature": ["rocks.glb", "pines.glb", "stump.glb", "log.glb"],
    "props": [],
    "icon": [],  # game/icon.png, rendered from rv.glb (run after "rv")
}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("only", nargs="*", help=f"builders to run ({', '.join(BUILDERS)}); default all")
    ap.add_argument("--no-fetch", action="store_true")
    ap.add_argument("--live", action="store_true", help="import results into the running Blender")
    args = ap.parse_args()
    names = args.only or list(BUILDERS)
    unknown = [n for n in names if n not in BUILDERS]
    if unknown:
        ap.error(f"unknown builders: {', '.join(unknown)}")

    if not args.no_fetch:
        subprocess.run([sys.executable, str(HERE / "fetch_assets.py")], check=True)

    failed = []
    for name in names:
        script = HERE / "blender" / f"build_{name}.py"
        print(f"== {name}", flush=True)
        proc = subprocess.run(
            [BLENDER, "--background", "--factory-startup", "--python-exit-code", "1", "--python", str(script)],
            capture_output=True, text=True,
        )
        for line in proc.stdout.splitlines():
            if line.startswith(("EXPORT", "PREVIEW", "SKIP", "RV:", "rocks:", "pines:")) or "Error" in line:
                print("  " + line)
        if proc.returncode != 0:
            failed.append(name)
            print(proc.stdout[-3000:])
            print(proc.stderr[-3000:])

    if args.live and not failed:
        out = ROOT / "game" / "assets" / "models"
        files = [str(out / f) for n in names for f in BUILDERS[n]]
        files += [str(p) for p in sorted((out / "props").glob("*.glb"))] if "props" in names else []
        subprocess.run([sys.executable, str(HERE / "blender_live.py"), "show", *files])

    if failed:
        print("FAILED:", ", ".join(failed))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

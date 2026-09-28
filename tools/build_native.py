#!/usr/bin/env python3
"""Build the rvcore GDExtension and copy it into game/bin/.

    python3 tools/build_native.py                    # release build for this machine
    python3 tools/build_native.py --check            # also run rvgen tests (incl. golden hashes)
    python3 tools/build_native.py --universal        # macOS: arm64 + x86_64 in one dylib
    python3 tools/build_native.py --target x86_64-unknown-linux-gnu --glibc 2.28
                                                     # Linux via cargo-zigbuild, runs on old distros

Output names match game/bin/rvcore.gdextension.
"""

import argparse
import platform
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BIN = ROOT / "game" / "bin"

# target triple -> (output subdir, file cargo builds, installed file name)
TARGETS = {
    "aarch64-apple-darwin": ("macos", "librvcore.dylib", "librvcore.dylib"),
    "x86_64-apple-darwin": ("macos", "librvcore.dylib", "librvcore.dylib"),
    "x86_64-unknown-linux-gnu": ("linux", "librvcore.so", "librvcore.x86_64.so"),
    "x86_64-pc-windows-msvc": ("windows", "rvcore.dll", "rvcore.x86_64.dll"),
}
MAC_TARGETS = ["aarch64-apple-darwin", "x86_64-apple-darwin"]


def run(cmd: list[str]) -> None:
    print("+", " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=ROOT, check=True)


def host_target() -> str:
    system, machine = platform.system(), platform.machine().lower()
    if system == "Darwin":
        return "aarch64-apple-darwin" if machine == "arm64" else "x86_64-apple-darwin"
    if system == "Linux" and machine in ("x86_64", "amd64"):
        return "x86_64-unknown-linux-gnu"
    if system == "Windows" and machine in ("amd64", "x86_64"):
        return "x86_64-pc-windows-msvc"
    sys.exit(f"No rvcore target for {system}/{machine} yet (see TARGETS in {__file__}).")


def build(triple: str, glibc: str | None) -> Path:
    if glibc:
        # cargo-zigbuild links against an old glibc so the .so loads on older distros.
        run(["cargo", "zigbuild", "--release", "-p", "rvcore", "--target", f"{triple}.{glibc}"])
    else:
        run(["cargo", "build", "--release", "-p", "rvcore", "--target", triple])
    return ROOT / "target" / triple / "release" / TARGETS[triple][1]


def install(src: Path, triple: str) -> Path:
    subdir, _, installed = TARGETS[triple]
    dst_dir = BIN / subdir
    dst_dir.mkdir(parents=True, exist_ok=True)
    dst = dst_dir / installed
    shutil.copy2(src, dst)
    return dst


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="run rvgen tests first")
    parser.add_argument("--target", choices=sorted(TARGETS), help="target triple (default: this machine)")
    parser.add_argument("--universal", action="store_true", help="macOS: build arm64 + x86_64 and lipo them")
    parser.add_argument("--glibc", help="Linux: oldest glibc to support, e.g. 2.28 (needs cargo-zigbuild)")
    args = parser.parse_args()

    if args.check:
        run(["cargo", "test", "-q", "-p", "rvgen"])

    if args.universal:
        if platform.system() != "Darwin":
            sys.exit("--universal needs macOS (lipo).")
        slices = [build(t, None) for t in MAC_TARGETS]
        dst = BIN / "macos" / "librvcore.dylib"
        dst.parent.mkdir(parents=True, exist_ok=True)
        run(["lipo", "-create", *map(str, slices), "-output", str(dst)])
        triple = MAC_TARGETS[0]
    else:
        triple = args.target or host_target()
        dst = install(build(triple, args.glibc), triple)

    if TARGETS[triple][0] == "macos":
        # Ad-hoc signature: required for arm64 code and keeps Gatekeeper quiet locally.
        run(["codesign", "--force", "--sign", "-", str(dst)])
    print(f"installed {dst.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

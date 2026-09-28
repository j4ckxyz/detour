#!/usr/bin/env python3
"""Download the pinned Godot editor and only the export templates one platform needs.

    python3 tools/ci/setup_godot.py --platform linux|macos|windows [--cache DIR] [--templates-only]

The official templates archive is ~1.2 GB; this reads just the needed members out of the
remote zip with HTTP range requests (tens of MB). The editor download is checked against
Godot's published SHA-512 sums; template members are checked by the zip's CRC-32 and come
over HTTPS from the same official release.

Prints the editor path on the last line, and writes `godot=<path>` to $GITHUB_OUTPUT when set.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import os
import platform
import shutil
import subprocess
import sys
import urllib.request
import zipfile
from pathlib import Path

VERSION = "4.7.2"
TAG = f"{VERSION}-stable"
BASE = f"https://github.com/godotengine/godot-builds/releases/download/{TAG}/"
TEMPLATES_ZIP = f"Godot_v{TAG}_export_templates.tpz"

# platform -> (editor zip, editor binary inside it, templates needed)
PLATFORMS = {
    "linux": (f"Godot_v{TAG}_linux.x86_64.zip", f"Godot_v{TAG}_linux.x86_64", ["linux_release.x86_64"]),
    "macos": (f"Godot_v{TAG}_macos.universal.zip", "Godot.app/Contents/MacOS/Godot", ["macos.zip"]),
    "windows": (f"Godot_v{TAG}_win64.exe.zip", f"Godot_v{TAG}_win64_console.exe", ["windows_release_x86_64.exe"]),
}


class RemoteFile(io.RawIOBase):
    """A seekable, read-only view of a URL, using HTTP range requests."""

    def __init__(self, url: str) -> None:
        super().__init__()
        req = urllib.request.Request(url, headers={"Range": "bytes=0-0"})
        with urllib.request.urlopen(req) as r:
            self.url = r.geturl()  # Follow the release redirect once.
            self.size = int(r.headers["Content-Range"].rsplit("/", 1)[1])
        self.pos = 0

    def readable(self) -> bool:
        return True

    def seekable(self) -> bool:
        return True

    def tell(self) -> int:
        return self.pos

    def seek(self, offset: int, whence: int = io.SEEK_SET) -> int:
        base = {io.SEEK_SET: 0, io.SEEK_CUR: self.pos, io.SEEK_END: self.size}[whence]
        self.pos = max(0, base + offset)
        return self.pos

    def readinto(self, buffer) -> int:
        if self.pos >= self.size or len(buffer) == 0:
            return 0
        end = min(self.pos + len(buffer), self.size) - 1
        req = urllib.request.Request(self.url, headers={"Range": f"bytes={self.pos}-{end}"})
        with urllib.request.urlopen(req) as r:
            data = r.read()
        buffer[: len(data)] = data
        self.pos += len(data)
        return len(data)


def templates_dir() -> Path:
    home = Path.home()
    system = platform.system()
    if system == "Darwin":
        root = home / "Library" / "Application Support" / "Godot"
    elif system == "Windows":
        root = Path(os.environ["APPDATA"]) / "Godot"
    else:
        root = Path(os.environ.get("XDG_DATA_HOME", home / ".local" / "share")) / "godot"
    return root / "export_templates" / f"{VERSION}.stable"


def fetch_templates(names: list[str], cache: Path) -> None:
    out = cache / "templates"
    wanted = ["version.txt", *names]
    if all((out / n).exists() for n in wanted):
        print(f"templates cached in {out}")
    else:
        out.mkdir(parents=True, exist_ok=True)
        remote = io.BufferedReader(RemoteFile(BASE + TEMPLATES_ZIP), buffer_size=8 << 20)
        with zipfile.ZipFile(remote) as z:
            for n in wanted:
                info = z.getinfo(f"templates/{n}")
                print(f"extracting {n} ({info.file_size >> 20} MB)", flush=True)
                with z.open(info) as src, open(out / n, "wb") as dst:
                    shutil.copyfileobj(src, dst, 8 << 20)  # CRC-32 is checked at EOF.
    dest = templates_dir()
    dest.mkdir(parents=True, exist_ok=True)
    for n in wanted:
        shutil.copy2(out / n, dest / n)
    print(f"templates installed in {dest}")


def sha512_sums() -> dict[str, str]:
    with urllib.request.urlopen(BASE + "SHA512-SUMS.txt") as r:
        lines = r.read().decode().splitlines()
    return {name.strip(): digest for digest, name in (line.split(maxsplit=1) for line in lines if line.strip())}


def fetch_editor(zip_name: str, binary: str, cache: Path) -> Path:
    editor_dir = cache / "editor"
    path = editor_dir / binary
    if path.exists():
        print(f"editor cached at {path}")
        return path
    editor_dir.mkdir(parents=True, exist_ok=True)
    archive = cache / zip_name
    print(f"downloading {zip_name}", flush=True)
    with urllib.request.urlopen(BASE + zip_name) as r, open(archive, "wb") as f:
        shutil.copyfileobj(r, f, 8 << 20)
    digest = hashlib.sha512(archive.read_bytes()).hexdigest()
    if digest != sha512_sums().get(zip_name):
        sys.exit(f"SHA-512 mismatch for {zip_name}")
    if platform.system() == "Windows":
        with zipfile.ZipFile(archive) as z:
            z.extractall(editor_dir)
    else:
        # `unzip` keeps the executable bits and the .app bundle's symlinks.
        subprocess.run(["unzip", "-q", "-o", str(archive), "-d", str(editor_dir)], check=True)
    archive.unlink()
    path.chmod(path.stat().st_mode | 0o111)
    return path


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--platform", required=True, choices=sorted(PLATFORMS))
    ap.add_argument("--cache", default=str(Path.home() / ".cache" / "detour-godot"))
    ap.add_argument("--templates-only", action="store_true", help="use the Godot already on PATH")
    args = ap.parse_args()
    cache = Path(args.cache) / VERSION
    zip_name, binary, templates = PLATFORMS[args.platform]
    fetch_templates(templates, cache)
    if args.templates_only:
        godot = shutil.which("godot")
        if not godot:
            sys.exit("no godot on PATH")
    else:
        # Forward slashes work in bash and PowerShell alike, Windows included.
        godot = fetch_editor(zip_name, binary, cache).as_posix()
    if "GITHUB_OUTPUT" in os.environ:
        with open(os.environ["GITHUB_OUTPUT"], "a") as f:
            f.write(f"godot={godot}\n")
    print(godot)
    return 0


if __name__ == "__main__":
    sys.exit(main())

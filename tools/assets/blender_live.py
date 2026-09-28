#!/usr/bin/env python3
"""Drive a running Blender through the "MCP for Blender" add-on socket (default port 9876).

Same JSON protocol the blender-mcp server uses, so this works even when the MCP server is
not registered with the current agent session.

    python3 tools/assets/blender_live.py scene                 # scene summary
    python3 tools/assets/blender_live.py show game/assets/models/rv.glb [more.glb ...]
    python3 tools/assets/blender_live.py exec some_script.py   # run Python inside Blender

`show` imports the GLBs into a "Detour Preview" collection (replacing the previous preview),
leaving the rest of your scene untouched.
"""

from __future__ import annotations

import json
import socket
import sys
from pathlib import Path

HOST, PORT = "127.0.0.1", 9876


def send(kind: str, params: dict | None = None, timeout: float = 120.0) -> dict:
    with socket.create_connection((HOST, PORT), timeout=timeout) as s:
        s.sendall(json.dumps({"type": kind, "params": params or {}}).encode())
        buf = b""
        while True:
            chunk = s.recv(65536)
            if not chunk:
                break
            buf += chunk
            try:
                return json.loads(buf)
            except ValueError:
                continue
    return json.loads(buf)


def run_code(code: str) -> dict:
    return send("execute_code", {"code": code})


SHOW_CODE = """
import bpy
paths = {paths!r}
name = "Detour Preview"
coll = bpy.data.collections.get(name)
if coll is None:
    coll = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(coll)
for o in list(coll.all_objects):
    bpy.data.objects.remove(o, do_unlink=True)
x = 0.0
for p in paths:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=p)
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        for c in list(o.users_collection):
            c.objects.unlink(o)
        coll.objects.link(o)
        if o.parent is None:
            o.location.x += x
    x += 12.0
print(f"imported {{len(paths)}} files into '{{name}}'")
"""


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == "scene":
        reply = send("get_scene_info")
    elif cmd == "show":
        paths = [str(Path(a).resolve()) for a in args]
        reply = run_code(SHOW_CODE.format(paths=paths))
    elif cmd == "exec":
        reply = run_code(Path(args[0]).read_text())
    else:
        print(f"unknown command {cmd}")
        return 1
    print(json.dumps(reply, indent=2)[:4000])
    return 0 if reply.get("status") == "success" else 1


if __name__ == "__main__":
    sys.exit(main())

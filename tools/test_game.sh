#!/usr/bin/env bash
# Run the headless Godot tests. Each gets a hard timeout: a GDScript error inside a
# SceneTree script leaves Godot running instead of exiting.
#
# tests/*.gd run as `--script` SceneTree tests (no autoloads); tests/*.tscn run as scenes
# (autoloads available) at a fixed 60 fps, so physics steps once per frame as fast as the
# machine allows.
set -euo pipefail
cd "$(dirname "$0")/../game"
GODOT="${GODOT:-godot}"
status=0
run() {
    local name="$1"
    shift
    echo "== $name"
    if ! perl -e 'alarm shift; exec @ARGV' 120 "$GODOT" --headless --path . "$@"; then
        echo "FAILED: $name"
        status=1
    fi
}
for test in tests/*.gd; do
    [ -f "${test%.gd}.tscn" ] && continue # Driven by its scene.
    run "$test" --script "res://$test"
done
for scene in tests/*.tscn; do
    run "$scene" --fixed-fps 60 "res://$scene"
done
exit $status

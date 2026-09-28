#!/usr/bin/env bash
# Stamps game/build_info.cfg so a release build knows what it is and can update itself
# (see game/src/autoload/build_info.gd). Pushes to main are "nightly", v* tags "stable",
# everything else (PRs, manual runs) "dev", which never auto-updates.
set -euo pipefail
cd "$(dirname "$0")/../.."
base=$(sed -n 's/^config\/version="\(.*\)"$/\1/p' game/project.godot)
ref="${GITHUB_REF:-}"
if [[ "$ref" == refs/tags/v* ]]; then
    channel=stable
    version="${ref#refs/tags/v}"
elif [[ "$ref" == refs/heads/main && "${GITHUB_EVENT_NAME:-}" == push ]]; then
    channel=nightly
    version="$base-nightly.${GITHUB_RUN_NUMBER:-0}"
else
    channel=dev
    version="$base-dev"
fi
cat > game/build_info.cfg <<CFG
[build]

channel="$channel"
version="$version"
commit="${GITHUB_SHA:-$(git rev-parse HEAD)}"
date="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
CFG
cat game/build_info.cfg

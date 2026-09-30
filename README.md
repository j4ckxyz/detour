# Detour (working title)

[![Build](https://github.com/j4ckxyz/detour/actions/workflows/build.yml/badge.svg)](https://github.com/j4ckxyz/detour/actions/workflows/build.yml)
[![Latest release](https://img.shields.io/github/v/release/j4ckxyz/detour?label=download)](https://github.com/j4ckxyz/detour/releases/latest)

**[⬇ Download the latest version](https://github.com/j4ckxyz/detour/releases/latest)** (Windows, macOS, Linux; free and
open source). Once installed it keeps itself up to date.

Open-source co-op road-trip game: up to 4 friends, one fragile RV, a procedurally generated
wilderness between you and home. Inspired by the *RV There Yet?* formula; all names, art and
code here are original. See [PLAN.md](PLAN.md) for the full design and roadmap.

**Status:** early development, but playable: generated trips from a camp to home through
four biomes, with bridges to jump or plank, beams to line up on, gullies, fords, ice, hills,
a fragile RV to keep running (a status panel shows its condition and your health; wreck it
and it's back to the last stop), wildlife, weather, day and night, saves, settings
(interface scale, graphics, window, frame rate), and co-op for up to four (PLAN.md §12 has
what's next).
Everything the game does today, and every control, is listed in [CURRENT_GAME.md](CURRENT_GAME.md).
Downloaded builds update themselves (Esc → *Update now*, or automatically on launch).

## Download

Get the **[latest release](https://github.com/j4ckxyz/detour/releases/latest)**. Automatic
builds of `main` are on the [nightly pre-release](https://github.com/j4ckxyz/detour/releases/tag/nightly)
(a nightly keeps following nightlies). Each has:

| Platform | File | First launch |
|---|---|---|
| Windows 10/11 | `Detour-Setup-x86_64.exe`, or the portable `Detour-windows-x86_64.zip` | Unsigned: SmartScreen → *More info* → *Run anyway* |
| macOS 11+ (Apple Silicon and Intel) | `Detour-macos-universal.zip` → `Detour.app` | Not notarised: right-click → *Open*, or `xattr -dr com.apple.quarantine Detour.app` |
| Linux / Steam Deck | `Detour-x86_64.AppImage`, or `Detour-linux-x86_64.tar.gz` | `chmod +x Detour-x86_64.AppImage` |

Check files against `SHA256SUMS` in the release.

**Controls:** W/S throttle and brake, A/D steer, Space handbrake, Q clutch (hold it and move
the mouse to work the H-pattern), E/Z or the mouse wheel to shift, 1–5 and R to pick a gear,
T for manual/automatic, I to start the engine, L headlights, F to get up, Backspace to
get back on the wheels, Esc menu, F1 help, F3 performance overlay. Full list, including
controller buttons: [CURRENT_GAME.md](CURRENT_GAME.md#controls).

## Layout

| Path | What |
|---|---|
| `game/` | Godot 4.7.2 project (typed GDScript) |
| `native/rvgen` | Deterministic world generator (pure Rust, bit-identical on every platform) |
| `native/rvcore` | GDExtension exposing `rvgen` to Godot (`WorldGen`, threaded `ChunkBuilder`) |
| `native/rvgen-cli` | Seed codes, chunk hashes, heightmap previews, generator benchmark |
| `server/relay` | Tiny self-hosted ENet relay for online play (runs on a Raspberry Pi) |
| `docs/perf.md` | Benchmark method and results |

## Build and run

Needs Rust (1.94+) and Godot 4.7.2 (`brew install --cask godot` on macOS).

```sh
python3 tools/build_native.py --check   # build rvcore into game/bin, run generator tests
godot --path game                       # drive the RV (F5-F8 switch graphics presets)
tools/test_game.sh                      # headless Godot tests (incl. a scripted drive)
godot --path game res://src/debug/drive_tour.tscn -- --shots=/tmp/tour   # screenshot tour
```

Release builds are made by `.github/workflows/build.yml`. To reproduce one locally:
`python3 tools/ci/setup_godot.py --platform macos --templates-only` fetches just the export
templates this platform needs, then
`godot --headless --path game --export-release "macOS" ../export/macos/Detour.zip`
(presets: `Linux`, `macOS`, `Windows`). `tools/package/` holds the AppImage and installer steps.

Benchmark (see `docs/perf.md`):

```sh
cd game && godot --path . res://src/debug/terrain_bench.tscn --resolution 2560x1600 -- --bench=15 --preset=high
```

## Hosting a relay

Online play goes through a relay that only forwards packets. It needs no GPU and very little
CPU, so a Raspberry Pi is plenty. Home upload bandwidth is the limit: about 0.6 Mbit/s per full
room.

```sh
cargo build --release -p detour-relay
./target/release/detour-relay --bind 0.0.0.0:24650 [--password friends-only]
```

Forward **UDP 24650** on your router to that machine. For always-on hosting, use
`server/relay/detour-relay.service` (sandboxed systemd unit) or `server/relay/Dockerfile`.

> **Security note:** this exposes a service on your home network to the internet. The relay
> runs unprivileged, never parses game payloads, and rate-limits connections and joins.
> Forward only that one UDP port. Set a password if only friends should use it.

## License

To be decided (see PLAN.md, Open questions).

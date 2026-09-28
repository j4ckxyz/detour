# Performance log

The benchmark drives a fixed route at 22 m/s (≈80 km/h) at driver eye height through streaming
terrain and trees. It skips 2 s of warm-up, then measures 15–20 s.

```sh
python3 tools/build_native.py
cd game
godot --path . res://src/debug/terrain_bench.tscn --resolution 2560x1600 --rendering-method mobile -- --bench=15 --preset=high
```

Output is one `BENCH {json}` line, also written to `user://bench.json`. It reports frame-time
percentiles and the five worst frames, with how much streaming work happened inside each one.

## 2026-09-28 — Phase 0 baseline, Apple Silicon

**Machine:** Apple A18 Pro (2 performance + 4 efficiency cores), 8 GB, macOS 27, Godot 4.7.2 on
Metal 4. This is the entry-level Mac, so it is our low-end Apple target.

**Scene:** seed `DT1-81YPW-3A7TA`. Chunks load out to the preset's view distance, and up to 12k
instanced pines.

| Renderer | Preset | Resolution | Avg fps | p50 ms | p95 ms | p99 ms | Max ms |
|---|---|---|---|---|---|---|---|
| Forward+ | medium | 1920×1080 | 111.7 | 8.84 | 10.88 | 11.58 | 14.69 |
| Mobile | medium | 1920×1080 | 120.0* | 8.05 | 10.95 | 12.48 | 14.86 |
| Forward+ | medium | 2560×1600 | **57.4** | 17.27 | 19.57 | 20.06 | 21.74 |
| Mobile | medium | 2560×1600 | 120.0* | 8.00 | 10.85 | 11.69 | 13.91 |
| Mobile | high | 2560×1600 | 120.0* | 8.14 | 9.75 | 10.34 | 16.07 |
| Compatibility | potato | 1920×1080 | 162.2 | 5.11 | 11.43 | 15.75 | 42.95 † |

\* The display's 120 Hz cap: these configurations have headroom left.
† This was a first run, so the max is shader compilation; see below.

### Decisions
- **The Mobile renderer is the macOS default** (`rendering_method.macos` in `project.godot`).
  Apple GPUs are tile-based, and at Retina resolutions Mobile runs about twice as fast as
  Forward+ with an indistinguishable look for our style. Forward+ remains available for
  Windows and Linux dGPUs.
- **Apple Silicon starts on the high preset.** Even the entry chip holds the 120 fps cap at
  2560×1600.
- **World-gen workers run at `QOS_CLASS_UTILITY`**, so macOS schedules them on efficiency cores.
  That leaves the performance cores to Godot's main and render threads. It raised Forward+ 1080p
  from 96 to 112 fps and cut p99 from 13.6 to 11.6 ms.

### Known issues / follow-ups
- **First-launch hitches (30–46 ms)** come from Metal pipeline compilation. They disappear once
  the pipeline cache is warm (the second run's max frame was 13.9 ms). *Fix:* a warm-up pass that
  draws every material variant during the loading screen (Phase 9).
- **GPU timing** (`viewport_get_measured_render_time_gpu`) always reads 0 on Metal. Use Xcode's
  Metal frame capture / Instruments for GPU work.
- **Chunk generation** takes 7–11 ms per chunk on efficiency cores and ~2 ms on a performance
  core (`rvgen-cli bench`). That is fine for streaming at RV speed. The terrain function
  (22 noise evaluations per sample) is the hot spot; a coarse warp grid can cut it when the
  Phase 3 generator lands.
- **Frame pacing:** ~1% of frames run 1.5× the median at the 120 Hz cap, which looks like display-
  link jitter rather than game work (nothing was uploaded in those frames). Recheck with a 60 Hz cap.

## 2026-09-28 — Decorated map (real pines, rocks, stumps, logs, saplings)

Same machine and seed, Mobile renderer, high preset, 2560×1600. Near trees are now the
Blender pines (136–280 triangles, real-model within 180 m, ~70-triangle cones beyond), plus
~44 props per chunk (13 scanned rocks + a boulder, stumps, logs, saplings) within 350 m.

| Scene | Avg fps | p50 ms | p95 ms | p99 ms | Max ms | Draws | Trees | Props |
|---|---|---|---|---|---|---|---|---|
| Decorated | 104.1 | 9.55 | 11.50 | 12.58 | 13.92 | 595 | 12,025 | 6,541 |

### Findings
- **Physics interpolation is on project-wide** (smooth RV at 120 Hz), but each node that
  enters an interpolated subtree cost the main thread 5–10 ms once the scene held thousands
  of instances. The terrain streamer's subtree opts out (`PHYSICS_INTERPOLATION_MODE_OFF`):
  everything it creates is static. Before that fix the same run hitched to 20–40 ms.
- Decor MultiMeshes enter the scene through a queue drained within the 2 ms upload budget
  (at least one per frame), so a chunk's ~20 decor nodes never land in a single frame.
- Remaining cost vs. the Phase 0 baseline (p50 8.1 → 9.6 ms) is GPU work for real models.

#!/usr/bin/env python3
"""Measure the game's real mix, captured by the audio tour:

    godot --headless --path game res://src/debug/audio_tour.tscn -- --capture=/tmp/tour.f32 | tee /tmp/tour.log
    python3 tools/audio/check_mix.py /tmp/tour.f32 /tmp/tour.log [--plot /tmp/tour.png]

Prints, per stage of the tour (the `STAGE name seconds` lines of the log), the loudness
(integrated LUFS, and the loudest 3 s), the sample peak and the share of energy above 8 kHz,
and fails if the mix ever clips (peak over -1 dBFS). Needs numpy, scipy, soundfile; the
plot needs matplotlib.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import numpy as np
from scipy import signal

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_sounds import lufs  # noqa: E402

RATE = 44100


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("capture", type=Path)
    parser.add_argument("log", type=Path)
    parser.add_argument("--plot", type=Path)
    args = parser.parse_args()
    x = np.fromfile(args.capture, dtype="<f4").reshape(-1, 2).astype(np.float64)
    stages = [(m.group(1), float(m.group(2))) for m in re.finditer(r"^STAGE (\S+) ([0-9.]+)$", args.log.read_text(), re.M)]
    stages.append(("end", len(x) / RATE))
    print("%-20s %6s %8s %10s %8s %6s" % ("stage", "secs", "LUFS", "loudest 3s", "peak dB", ">8k %"))
    worst = -99.0
    for (name, t0), (_, t1) in zip(stages, stages[1:]):
        seg = x[int((t0 + 1.0) * RATE):int(t1 * RATE)]  # skip the first second (fades from the last stage)
        if len(seg) < RATE:
            continue
        peak = 20 * np.log10(np.max(np.abs(seg)) + 1e-12)
        worst = max(worst, peak)
        f, p = signal.welch(seg.mean(axis=1), RATE, nperseg=8192)
        hi = p[f > 8000].sum() / (p.sum() + 1e-30) * 100
        blocks = [lufs(seg[i:i + 3 * RATE], RATE) for i in range(0, max(1, len(seg) - 3 * RATE), RATE)]
        print("%-20s %6.1f %8.1f %10.1f %8.1f %6.2f" % (name, t1 - t0, lufs(seg, RATE), max(blocks), peak, hi))
    print("overall %.1f LUFS, peak %.1f dBFS" % (lufs(x[RATE:], RATE), 20 * np.log10(np.max(np.abs(x)) + 1e-12)))
    if args.plot:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt

        f, t, s = signal.spectrogram(x.mean(axis=1), RATE, nperseg=4096, noverlap=2048)
        keep = f < 10000
        fig, ax = plt.subplots(figsize=(16, 6))
        ax.pcolormesh(t, f[keep], 10 * np.log10(s[keep] + 1e-14), vmin=-130, vmax=-60, shading="auto")
        for name, t0 in stages[:-1]:
            ax.axvline(t0, color="w", lw=0.6)
            ax.text(t0 + 0.2, 9300, name, color="w", fontsize=7, rotation=90, va="top")
        fig.tight_layout()
        fig.savefig(args.plot, dpi=70)
    return 1 if worst > -1.0 else 0


if __name__ == "__main__":
    sys.exit(main())

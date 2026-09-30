#!/usr/bin/env python3
"""Measure every sound under game/assets/audio/ (decoded from the shipped .ogg files) and
fail if one is out of bounds. Since nobody can listen in CI, this is the objective check:

    python3 tools/audio/check_sounds.py [--plots DIR]

  * peak below -1 dBFS (no clipping), no DC offset;
  * loops: the jump from the last sample to the first is no bigger than the sample-to-sample
    steps inside the sound (so it wraps without a click);
  * how much energy sits above 8 kHz (ambience and engine should be soft: < 1 %), where
    the bulk of it is (spectral centroid), and integrated loudness (LUFS, BS.1770);
  * with --plots, a spectrogram PNG per sound to look at.

Needs numpy, scipy, soundfile (and matplotlib for --plots).
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy import signal

ROOT = Path(__file__).resolve().parents[2]
AUDIO = ROOT / "game" / "assets" / "audio"

LOOPS = {
    "engine_idle", "engine_low", "engine_mid", "engine_high", "starter_crank", "tire_road", "tire_gravel",
    "wind_bed", "wind_trees", "rain_loop", "rain_roof", "crickets_loop",
}
# Sounds that may have bright content (hard knocks); the rest must be soft.
SOFT_LIMIT_PCT = 1.0
BRIGHT_OK = {"gear_clunk", "hammer_clank_1", "hammer_clank_2", "hammer_clank_3", "door_open", "door_close", "crash"}


def k_weight(x: np.ndarray, sr: int) -> np.ndarray:
    """ITU-R BS.1770 K-weighting (shelf + high-pass) for any sample rate."""
    g, q, fc = 3.999843853973347, 0.7071752369554196, 1681.9744509555319
    k = np.tan(np.pi * fc / sr)
    vh = 10 ** (g / 20)
    vb = vh**0.4996667741545416
    a0 = 1 + k / q + k * k
    shelf_b = [(vh + vb * k / q + k * k) / a0, 2 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0]
    shelf_a = [1.0, 2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0]
    fc, q = 38.13547087602444, 0.5003270373238773
    k = np.tan(np.pi * fc / sr)
    d = 1 + k / q + k * k
    hp_a = [1.0, 2 * (k * k - 1) / d, (1 - k / q + k * k) / d]
    y = signal.lfilter(shelf_b, shelf_a, x, axis=0)
    return signal.lfilter([1.0, -2.0, 1.0], hp_a, y, axis=0)


def lufs(x: np.ndarray, sr: int) -> float:
    """Integrated loudness (gated) of (n, channels) audio."""
    y = k_weight(x, sr)
    block, step = int(0.4 * sr), int(0.1 * sr)
    if len(y) < block:
        return float(-0.691 + 10 * np.log10(np.sum(np.mean(y**2, axis=0)) + 1e-12))
    z = np.array([np.sum(np.mean(y[i:i + block] ** 2, axis=0)) for i in range(0, len(y) - block + 1, step)])
    loud = -0.691 + 10 * np.log10(z + 1e-12)
    z = z[loud > -70.0]
    if z.size == 0:
        return -70.0
    rel = -0.691 + 10 * np.log10(np.mean(z)) - 10.0
    z = z[-0.691 + 10 * np.log10(z + 1e-12) > rel]
    return float(-0.691 + 10 * np.log10(np.mean(z) + 1e-12))


def measure(path: Path) -> dict:
    x, sr = sf.read(str(path), always_2d=True)
    name = path.stem
    mono = x.mean(axis=1)
    f, p = signal.welch(mono, sr, nperseg=8192)
    total = p.sum() + 1e-30
    # Loop seam: last->first step versus typical step, worst channel.
    steps = np.diff(x, axis=0)
    seam = np.abs(x[0] - x[-1])
    typical = np.sqrt(np.mean(steps**2, axis=0)) + 1e-9
    return {
        "name": name, "rel": str(path.relative_to(AUDIO)), "sr": sr, "channels": x.shape[1],
        "secs": len(x) / sr, "size_kb": path.stat().st_size / 1024,
        "peak_db": 20 * np.log10(np.max(np.abs(x)) + 1e-12),
        "rms_db": 20 * np.log10(np.sqrt(np.mean(x**2)) + 1e-12),
        "lufs": lufs(x, sr),
        "dc": float(np.max(np.abs(x.mean(axis=0)))),
        "seam": float(np.max(seam / typical)),
        "above8k_pct": float(p[f > 8000].sum() / total * 100.0),
        "above4k_pct": float(p[f > 4000].sum() / total * 100.0),
        "centroid": float((f * p).sum() / total),
        "x": x,
    }


def problems(m: dict) -> list[str]:
    out = []
    if m["peak_db"] > -1.0:
        out.append("peak %.1f dBFS is over -1" % m["peak_db"])
    if m["dc"] > 0.002:
        out.append("DC offset %.4f" % m["dc"])
    if m["name"] in LOOPS and m["seam"] > 4.0:
        out.append("loop seam is %.1fx a normal step" % m["seam"])
    if m["name"] not in BRIGHT_OK and not m["rel"].startswith("birds/") and m["above8k_pct"] > SOFT_LIMIT_PCT:
        out.append("%.2f %% of the energy is above 8 kHz" % m["above8k_pct"])
    return out


def plot(items: list[dict], out: Path) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    out.mkdir(parents=True, exist_ok=True)
    for m in items:
        x = m["x"].mean(axis=1)
        fig, ax = plt.subplots(2, 1, figsize=(10, 5), gridspec_kw={"height_ratios": [1, 2]})
        t = np.arange(len(x)) / m["sr"]
        ax[0].plot(t, x, lw=0.4)
        ax[0].set_ylim(-1, 1)
        ax[0].set_title("%s  %.1fs  peak %.1f dB  rms %.1f dB  %.1f LUFS" % (m["rel"], m["secs"], m["peak_db"], m["rms_db"], m["lufs"]), fontsize=9)
        f, tt, s = signal.spectrogram(x, m["sr"], nperseg=2048, noverlap=1536)
        keep = f < 12000
        ax[1].pcolormesh(tt, f[keep], 10 * np.log10(s[keep] + 1e-14), vmin=-120, vmax=-50, shading="auto")
        ax[1].set_ylabel("Hz")
        fig.tight_layout()
        fig.savefig(out / (m["name"] + ".png"), dpi=70)
        plt.close(fig)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--plots", type=Path, help="write spectrogram PNGs here")
    args = parser.parse_args()
    files = sorted(AUDIO.rglob("*.ogg"))
    if not files:
        print("no sounds under", AUDIO)
        return 1
    items = [measure(p) for p in files]
    print("%-24s %5s %2s %7s %7s %7s %6s %7s %6s %6s %7s %5s" % ("sound", "secs", "ch", "peak", "rms", "LUFS", "seam", "dc", ">8k %", ">4k %", "centre", "KB"))
    bad = 0
    for m in items:
        why = problems(m)
        bad += bool(why)
        print("%-24s %5.1f %2d %7.1f %7.1f %7.1f %6s %7.4f %6.2f %6.1f %7.0f %5.0f %s" % (
            m["rel"].removesuffix(".ogg"), m["secs"], m["channels"], m["peak_db"], m["rms_db"], m["lufs"],
            "%.1f" % m["seam"] if m["name"] in LOOPS else "-", m["dc"], m["above8k_pct"], m["above4k_pct"], m["centroid"], m["size_kb"],
            "FAIL: " + "; ".join(why) if why else ""))
    print("total %.2f MB in %d files, %d with problems" % (sum(m["size_kb"] for m in items) / 1024, len(items), bad))
    if args.plots:
        plot(items, args.plots)
        print("spectrograms in", args.plots)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())

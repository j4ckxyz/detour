"""Small DSP toolbox shared by make_sounds.py and fetch_birds.py (numpy + scipy only).

Everything that has to loop is built with *circular* operations (FFT filtering, periodic
modulation), so the last sample runs straight into the first with no seam.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
import soundfile as sf

SR = 44100


def seconds(x: np.ndarray, sr: int = SR) -> float:
    return len(x) / sr


# --- filters (magnitude responses, applied circularly with the FFT) ----------------------


def lp(f: np.ndarray, fc: float, order: int = 2) -> np.ndarray:
    """Low-pass magnitude (Butterworth shape)."""
    return 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order))


def hp(f: np.ndarray, fc: float, order: int = 2) -> np.ndarray:
    """High-pass magnitude (Butterworth shape)."""
    r = (f + 1e-9) / fc
    return r**order / np.sqrt(1.0 + r ** (2 * order))


def bell(f: np.ndarray, fc: float, width: float) -> np.ndarray:
    """A smooth 0..1 bump centred at fc; `width` is in octaves (1 sigma)."""
    return np.exp(-0.5 * (np.log2((f + 1e-9) / fc) / width) ** 2)


def filt(x: np.ndarray, response, sr: int = SR) -> np.ndarray:
    """Circular FFT filter: `response(freqs_hz) -> gain` (a callable). Keeps the length."""
    n = len(x)
    f = np.fft.rfftfreq(n, 1.0 / sr)
    return np.fft.irfft(np.fft.rfft(x) * response(f), n)


def pinkish(x: np.ndarray, sr: int = SR) -> np.ndarray:
    """-3 dB/octave tilt (pink noise from white)."""
    return filt(x, lambda f: 1.0 / np.sqrt(np.maximum(f, 20.0)), sr)


def white(n: int, rng: np.random.Generator) -> np.ndarray:
    return rng.standard_normal(n)


def slow_random(n: int, rate_hz: float, rng: np.random.Generator, sr: int = SR) -> np.ndarray:
    """A smooth periodic random curve with zero mean and unit deviation; wanders at about
    `rate_hz` (it wraps seamlessly)."""
    y = filt(rng.standard_normal(n), lambda f: lp(f, rate_hz, 2) * hp(f, rate_hz * 0.05, 1), sr)
    return y / (np.std(y) + 1e-12)


def swell(n: int, rate_hz: float, depth: float, rng: np.random.Generator, sr: int = SR) -> np.ndarray:
    """A periodic gain curve around 1 (0..~1+depth) for gusts and breathing: exp of a slow random."""
    return np.exp(depth * slow_random(n, rate_hz, rng, sr) - depth**2 * 0.5)


def periodic_tone(f0: float, mod: np.ndarray, n: int, sr: int = SR, harmonics: tuple[float, ...] = (1.0,)) -> np.ndarray:
    """A tone whose frequency is f0*(1+mod); the phase is nudged so it wraps exactly."""
    inst = f0 * (1.0 + mod)
    phase = np.cumsum(inst) / sr * 2.0 * np.pi
    total = phase[-1] + inst[-1] / sr * 2.0 * np.pi
    target = 2.0 * np.pi * np.round(total / (2.0 * np.pi))
    phase = phase + (target - total) * np.arange(1, n + 1) / n
    out = np.zeros(n)
    for k, a in enumerate(harmonics, start=1):
        out += a * np.sin(k * phase)
    return out


# --- levels ---------------------------------------------------------------------------------


def db(x: float) -> float:
    return 20.0 * np.log10(max(x, 1e-12))


def rms(x: np.ndarray) -> float:
    return float(np.sqrt(np.mean(np.square(x))))


def normalize_rms(x: np.ndarray, target_db: float, peak_db: float = -3.0) -> np.ndarray:
    """Scales to `target_db` RMS; if the peaks would pass `peak_db`, they are squeezed with a
    soft knee (tanh) instead of clipped, and the RMS re-aimed once."""
    y = x * 10.0 ** (target_db / 20.0) / (rms(x) + 1e-12)
    ceiling = 10.0 ** (peak_db / 20.0)
    for _ in range(3):
        peak = np.max(np.abs(y))
        if peak <= ceiling:
            break
        y = ceiling * np.tanh(y / ceiling)
        y *= 10.0 ** (target_db / 20.0) / (rms(y) + 1e-12)
    peak = np.max(np.abs(y))
    if peak > ceiling:
        y *= ceiling / peak
    return y


def fade(x: np.ndarray, fade_in: float = 0.0, fade_out: float = 0.0, sr: int = SR) -> np.ndarray:
    """Raised-cosine fades at the ends (one-shots)."""
    y = x.copy()
    a, b = int(fade_in * sr), int(fade_out * sr)
    if a > 0:
        y[:a] *= 0.5 - 0.5 * np.cos(np.pi * np.arange(a) / a)
    if b > 0:
        y[-b:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(b) / b)
    return y


def remove_dc(x: np.ndarray) -> np.ndarray:
    return x - np.mean(x)


def envelope_exp(n: int, tau: float, sr: int = SR) -> np.ndarray:
    return np.exp(-np.arange(n) / (tau * sr))


def add_at(dst: np.ndarray, src: np.ndarray, at: float, gain: float = 1.0, sr: int = SR, wrap: bool = False) -> None:
    """Mixes `src` into `dst` starting at time `at` (seconds); with `wrap` it wraps round the end."""
    start = int(round(at * sr))
    n = len(dst)
    if wrap:
        idx = (start + np.arange(len(src))) % n
        np.add.at(dst, idx, src * gain)
        return
    if start >= n or start + len(src) <= 0:
        return
    s0 = max(0, -start)
    e0 = min(len(src), n - start)
    dst[start + s0:start + e0] += src[s0:e0] * gain


# --- output ---------------------------------------------------------------------------------


def write_ogg(path: Path, x: np.ndarray, sr: int = SR, quality: float = 0.5) -> None:
    """Writes Ogg Vorbis (`quality` 0..1 ~ q0..q10). `x` is (n,) or (n, 2), float in +-1."""
    path.parent.mkdir(parents=True, exist_ok=True)
    x = np.clip(x, -0.999, 0.999).astype(np.float32)
    sf.write(str(path), x, sr, format="OGG", subtype="VORBIS", compression_level=quality)

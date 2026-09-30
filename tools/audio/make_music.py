#!/usr/bin/env python3
"""Generates the eight cassette tracks into game/assets/audio/music/ (`tape_1.ogg` ... `tape_8.ogg`).

    python3 tools/audio/make_music.py [1 2 ...]       # all, or only the tapes numbered

Every note is synthesized here (plucked strings by Karplus-Strong, pads, bells, a soft bass and
brushed drums) and the tunes are made up: nothing is sampled or borrowed, so, like the other
sounds, they carry the game's licence. Fixed seeds: the same command gives the same music.

Each tape is a short piece in its own style (folk, an easy driving groove, a waltz, night
ambient, a shuffle blues, a slow sunrise, glassy cold bells, a hopeful homecoming), 40-60 seconds
with a reverb tail. Everything is rounded off well under 7 kHz and levelled to -21 LUFS, so it
sits under the engine. Needs numpy, scipy and soundfile.
"""

from __future__ import annotations

import sys
import zlib
from pathlib import Path

import numpy as np
from scipy import signal

sys.path.insert(0, str(Path(__file__).resolve().parent))
import dsp  # noqa: E402
from dsp import SR, bell, filt, hp, lp  # noqa: E402
from check_sounds import lufs  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "game" / "assets" / "audio" / "music"

MAJOR = [0, 2, 4, 5, 7, 9, 11]
MINOR = [0, 2, 3, 5, 7, 8, 10]
PENT_MAJOR = [0, 2, 4, 7, 9]
PENT_MINOR = [0, 3, 5, 7, 10]


def rng_for(name: str) -> np.random.Generator:
    return np.random.default_rng(zlib.crc32(name.encode()))


def freq(m: float) -> float:
    return 440.0 * 2.0 ** ((m - 69.0) / 12.0)


# --- instruments ----------------------------------------------------------------------------------


def pluck(f: float, dur: float, rng: np.random.Generator, decay: float = 0.995, bright: float = 0.5) -> np.ndarray:
    """A plucked string (Karplus-Strong): a burst of noise fed round a delay line one period long,
    averaged with its neighbour and damped each time round. `bright` 0..1 is how sharp the pluck
    is. Worked a period at a time, so it's fast."""
    n = int(dur * SR)
    period = max(4, int(round(SR / f - 0.5)))
    burst = rng.uniform(-1.0, 1.0, period)
    for _ in range(int((1.0 - bright) * 4)):
        burst = np.convolve(burst, [0.5, 0.5], "same")
    y = np.zeros(n + 1)  # y[i + 1] is sample i (a zero in front for the one-sample delay)
    y[1 : min(period, n) + 1] = burst[: min(period, n)]
    for start in range(period, n, period):
        end = min(start + period, n)
        y[start + 1 : end + 1] = 0.5 * decay * (y[start - period + 1 : end - period + 1] + y[start - period : end - period])
    out = y[1:]
    return out / (np.max(np.abs(out)) + 1e-9)


def pad(freqs: list[float], dur: float, attack: float = 0.7, release: float = 0.9, warmth: float = 1800.0) -> np.ndarray:
    """A soft, slowly swelling chord: detuned saw-ish voices through a low-pass."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for f in freqs:
        for cents in (-6.0, 0.0, 6.0):
            g = f * 2.0 ** (cents / 1200.0)
            for k in range(1, 7):
                x += np.sin(2.0 * np.pi * g * k * t + 0.7 * k) / k ** 1.3
    env = np.minimum(1.0, t / attack) * np.minimum(1.0, (dur - t) / release)
    x = x * env
    x = filt(x, lambda f: lp(f, warmth, 2))
    return x / (np.max(np.abs(x)) + 1e-9)


def bell_note(f: float, dur: float, decay: float = 0.9) -> np.ndarray:
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for ratio, tau, g in ((1.0, decay, 1.0), (2.0, decay * 0.55, 0.32), (2.76, decay * 0.3, 0.16), (5.4, decay * 0.12, 0.05)):
        x += g * np.sin(2.0 * np.pi * f * ratio * t) * np.exp(-t / tau)
    x = x * np.minimum(1.0, t / 0.004)
    return x / (np.max(np.abs(x)) + 1e-9)


def bass_note(f: float, dur: float, tone: float = 0.4) -> np.ndarray:
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = (np.sin(2.0 * np.pi * f * t) + tone * np.sin(4.0 * np.pi * f * t)) * np.exp(-t / 0.5) * np.minimum(1.0, t / 0.006)
    x = filt(x, lambda fr: lp(fr, 700.0, 2))
    return x / (np.max(np.abs(x)) + 1e-9)


def kick(rng: np.random.Generator) -> np.ndarray:
    n = int(0.3 * SR)
    t = np.arange(n) / SR
    return np.sin(2.0 * np.pi * np.cumsum(50.0 + 90.0 * np.exp(-t / 0.03)) / SR) * np.exp(-t / 0.11)


def brush(rng: np.random.Generator, dur: float = 0.09) -> np.ndarray:
    n = int(dur * SR)
    x = filt(rng.standard_normal(n), lambda f: hp(f, 2200.0, 2) * lp(f, 5500.0, 2)) * np.exp(-np.arange(n) / SR / (dur * 0.35))
    return x / (np.max(np.abs(x)) + 1e-9)


def soft_snare(rng: np.random.Generator) -> np.ndarray:
    n = int(0.22 * SR)
    t = np.arange(n) / SR
    body = np.sin(2.0 * np.pi * 190.0 * t) * np.exp(-t / 0.05)
    noise = filt(rng.standard_normal(n), lambda f: hp(f, 900.0, 2) * lp(f, 5000.0, 2)) * np.exp(-t / 0.07)
    x = 0.5 * body + 0.6 * noise / (np.max(np.abs(noise)) + 1e-9)
    return x / (np.max(np.abs(x)) + 1e-9)


# --- composing ------------------------------------------------------------------------------------


class Piece:
    """A track being built: notes go in by beat, then it's mixed, reverberated and levelled."""

    def __init__(self, name: str, bpm: float, bars: int, beats_per_bar: int = 4, tail: float = 3.0) -> None:
        self.name = name
        self.rng = rng_for(name)
        self.bpm = bpm
        self.beat = 60.0 / bpm
        self.bars = bars
        self.bpb = beats_per_bar
        self.total = bars * beats_per_bar * self.beat
        self.n = int((self.total + tail) * SR)
        self.dry = np.zeros(self.n)
        self.wet = np.zeros(self.n)

    def at(self, bar: int, beat: float) -> float:
        return (bar * self.bpb + beat) * self.beat

    def put(self, sig: np.ndarray, t: float, gain: float, reverb: float = 0.0) -> None:
        if t < 0 or t >= self.total + 1.0:
            return
        dsp.add_at(self.dry, sig, t, gain)
        if reverb > 0.0:
            dsp.add_at(self.wet, sig, t, gain * reverb)

    def finish(self) -> np.ndarray:
        ir_n = int(1.6 * SR)
        rng = rng_for(self.name + ":reverb")
        ir = rng.standard_normal(ir_n) * np.exp(-np.arange(ir_n) / SR / 0.45)
        ir = filt(ir, lambda f: hp(f, 200.0, 1) * lp(f, 3500.0, 2))
        ir /= np.sqrt(np.sum(ir**2))
        wet = signal.fftconvolve(self.wet, ir)[: self.n]
        x = self.dry + 0.8 * wet
        x = filt(x, lambda f: hp(f, 45.0, 2) * lp(f, 6200.0, 3))
        x = dsp.fade(dsp.remove_dc(x), 0.05, 1.5)
        return normalize(x)


def normalize(x: np.ndarray, target: float = -21.0, peak_db: float = -3.0) -> np.ndarray:
    y = x.reshape(-1, 1)
    ceiling = 10.0 ** (peak_db / 20.0)
    for _ in range(8):
        y = y * 10.0 ** ((target - lufs(y, SR)) / 20.0)
        if np.max(np.abs(y)) <= ceiling:
            break
        y = ceiling * np.tanh(y / ceiling)
    return y.reshape(-1)


def chord(root: int, scale: list[int], degree: int, size: int = 3, octave: int = 0) -> list[int]:
    """The chord built on scale degree `degree` (0-based), as midi notes."""
    notes = []
    for i in range(size):
        d = degree + 2 * i
        notes.append(root + octave * 12 + scale[d % 7] + 12 * (d // 7))
    return notes


def melody(p: Piece, root: int, scale: list[int], per_bar: list[list[tuple[float, float, int]]], instrument, gain: float, reverb: float, octave: int = 1) -> None:
    """Lays a melody: for each bar, a list of (beat, length in beats, scale-step) notes."""
    for bar, notes in enumerate(per_bar):
        for beat, length, step in notes:
            m = root + 12 * octave + scale[step % len(scale)] + 12 * (step // len(scale))
            p.put(instrument(freq(m), length * p.beat), p.at(bar, beat), gain, reverb)


def phrase_bars(rng: np.random.Generator, bars: int, pattern: list[tuple[float, float]], steps_from: list[int], ends_on: int) -> list[list[tuple[float, float, int]]]:
    """A wandering tune: every bar uses a rhythm from `pattern` ((beat, length) pairs), with steps
    drawn from a small set that drift up and down, and the last bar coming home to `ends_on`."""
    out: list[list[tuple[float, float, int]]] = []
    at = int(rng.integers(0, len(steps_from)))
    for b in range(bars):
        notes = []
        rhythm = pattern if (b % 2 == 0 or b == bars - 1) else [(bt, ln) for bt, ln in pattern[::2]] or pattern
        for beat, length in rhythm:
            at = int(np.clip(at + int(rng.integers(-1, 2)), 0, len(steps_from) - 1))
            notes.append((beat, length, steps_from[at]))
        if b == bars - 1:
            notes[-1] = (notes[-1][0], notes[-1][1] * 1.5, ends_on)
        out.append(notes)
    return out


# --- the eight tapes ------------------------------------------------------------------------------


def tape_1() -> np.ndarray:
    """Dust and Gravel: an easy acoustic folk picking pattern in A minor."""
    p = Piece("tape_1", 92.0, 20)
    root = 45  # A2
    prog = [0, 5, 2, 6, 0, 5, 3, 4]  # Am F C G Am F Dm E-ish
    for bar in range(p.bars):
        deg = prog[bar % len(prog)]
        ch = chord(root + 12, MINOR, deg)
        for i, m in enumerate([ch[0], ch[2], ch[1] + 12, ch[2], ch[0] + 12, ch[2], ch[1] + 12, ch[2]]):
            p.put(pluck(freq(m), 1.4, p.rng, 0.996, 0.55), p.at(bar, i * 0.5), 0.5 if i % 2 == 0 else 0.35, 0.3)
        bass = root + MINOR[deg]
        p.put(bass_note(freq(bass), 1.6), p.at(bar, 0.0), 0.7)
        p.put(bass_note(freq(bass + 7), 1.0), p.at(bar, 2.0), 0.45)
        for beat in (1.0, 3.0):
            p.put(brush(p.rng), p.at(bar, beat), 0.16)
    tune = phrase_bars(p.rng, p.bars - 4, [(0.0, 1.5), (1.5, 0.5), (2.0, 1.0), (3.0, 1.0)], [0, 2, 3, 4, 5, 7], 0)
    melody(p, root, MINOR, [[]] * 4 + tune, lambda f, d: pluck(f, d + 0.6, p.rng, 0.997, 0.4), 0.6, 0.45, octave=2)
    return p.finish()


def tape_2() -> np.ndarray:
    """Highway Hum: a steady, warm driving groove."""
    p = Piece("tape_2", 96.0, 24)
    root = 43  # G2
    prog = [0, 3, 4, 3, 0, 3, 5, 4]
    for bar in range(p.bars):
        deg = prog[bar % len(prog)]
        ch = [root + 12 + MAJOR[(deg + 2 * i) % 7] + 12 * ((deg + 2 * i) // 7) for i in range(3)]
        if bar % 8 < 6:
            p.put(pad([freq(m) for m in ch], p.beat * 4.4, 0.9, 1.0, 1400.0), p.at(bar, 0.0), 0.3, 0.5)
        for beat in (0.0, 1.0, 2.0, 3.0):
            p.put(kick(p.rng), p.at(bar, beat), 0.55)
        for beat in (1.0, 3.0):
            p.put(soft_snare(p.rng), p.at(bar, beat), 0.16)
        for i in range(8):
            p.put(brush(p.rng, 0.05), p.at(bar, i * 0.5 + 0.25), 0.07 if i % 2 else 0.1)
        b = root + MAJOR[deg]
        for beat, off in ((0.0, 0), (1.5, 0), (2.5, 7), (3.5, 5)):
            p.put(bass_note(freq(b + off), 0.7, 0.6), p.at(bar, beat), 0.55)
    tune = phrase_bars(p.rng, p.bars - 6, [(0.0, 0.5), (0.5, 0.5), (1.0, 1.0), (2.5, 0.5), (3.0, 1.0)], [0, 1, 2, 4, 5, 7], 0)
    melody(p, root, MAJOR, [[]] * 6 + tune, lambda f, d: pluck(f, d + 0.5, p.rng, 0.996, 0.7), 0.45, 0.35, octave=2)
    return p.finish()


def tape_3() -> np.ndarray:
    """Gas Station Waltz: a music-box tune in three-four."""
    p = Piece("tape_3", 108.0, 24, 3)
    root = 48  # C3
    prog = [0, 3, 4, 0, 5, 3, 4, 0]
    for bar in range(p.bars):
        deg = prog[bar % len(prog)]
        ch = chord(root + 12, MAJOR, deg)
        b = root + MAJOR[deg]
        p.put(bass_note(freq(b), 1.2), p.at(bar, 0.0), 0.6)
        for beat in (1.0, 2.0):
            for m in ch:
                p.put(pluck(freq(m), 0.9, p.rng, 0.992, 0.4), p.at(bar, beat), 0.16, 0.3)
    tune = phrase_bars(p.rng, p.bars - 4, [(0.0, 1.0), (1.0, 0.5), (1.5, 0.5), (2.0, 1.0)], [0, 2, 4, 5, 7, 9], 0)
    melody(p, root, MAJOR, [[]] * 4 + tune, lambda f, d: bell_note(f, d + 1.0, 0.8), 0.5, 0.5, octave=3)
    return p.finish()


def tape_4() -> np.ndarray:
    """Night Drive: slow chords under a few far-off bell notes."""
    p = Piece("tape_4", 64.0, 16, tail=4.0)
    root = 40  # E2
    prog = [0, 5, 3, 4]
    for bar in range(p.bars):
        deg = prog[bar % len(prog)]
        ch = chord(root + 12, MINOR, deg, 4)
        p.put(pad([freq(m) for m in ch], p.beat * 4.8, 1.6, 1.8, 1200.0), p.at(bar, 0.0), 0.5, 0.6)
        p.put(bass_note(freq(root + MINOR[deg]), 3.5, 0.2), p.at(bar, 0.0), 0.5)
    for bar in range(2, p.bars):
        for _ in range(int(p.rng.integers(1, 3))):
            step = int(p.rng.choice([0, 2, 3, 4, 6, 7]))
            m = root + 24 + PENT_MINOR[step % 5] + 12 * (step // 5)
            p.put(bell_note(freq(m), 3.0, 1.4), p.at(bar, float(p.rng.integers(0, 8)) * 0.5), 0.3, 0.8)
    return p.finish()


def tape_5() -> np.ndarray:
    """Bayou Blues: a lazy shuffle over twelve bars in E."""
    p = Piece("tape_5", 84.0, 24)
    root = 40  # E2
    twelve = [0, 0, 0, 0, 3, 3, 0, 0, 4, 3, 0, 4]
    swing = 0.33
    for bar in range(p.bars):
        deg = twelve[bar % 12]
        r = root + {0: 0, 3: 5, 4: 7}[deg]
        for i, off in enumerate((0, 4, 7, 9, 10, 9, 7, 4)):
            beat = (i // 2) + (0.0 if i % 2 == 0 else swing * 2.0)
            p.put(bass_note(freq(r + off), 0.6, 0.5), p.at(bar, beat), 0.5 if i % 2 == 0 else 0.35)
        for beat in (1.0, 3.0):
            for off in (12, 16, 19):
                p.put(pluck(freq(r + 12 + off - 12), 0.5, p.rng, 0.99, 0.6), p.at(bar, beat + swing * 2.0), 0.09, 0.3)
            p.put(soft_snare(p.rng), p.at(bar, beat), 0.13)
        for beat in range(4):
            p.put(brush(p.rng, 0.06), p.at(bar, beat), 0.1)
            p.put(brush(p.rng, 0.05), p.at(bar, beat + swing * 2.0), 0.06)
    blues = [0, 3, 5, 6, 7, 10]  # E blues steps above the root, semitones
    for bar in range(4, p.bars):
        for beat in (0.0, 1.5, 2.0, 3.0):
            if p.rng.random() < 0.65:
                m = root + 24 + int(p.rng.choice(blues)) + (12 if p.rng.random() < 0.2 else 0)
                p.put(pluck(freq(m), 0.9, p.rng, 0.995, 0.65), p.at(bar, beat + (swing * 2.0 if beat % 1 else 0.0)), 0.4, 0.35)
    return p.finish()


def tape_6() -> np.ndarray:
    """Canyon Sunrise: wide open fifths and slow harp-like arpeggios."""
    p = Piece("tape_6", 66.0, 16, tail=4.0)
    root = 38  # D2
    prog = [0, 4, 5, 3]
    for bar in range(p.bars):
        deg = prog[bar % len(prog)]
        r = root + MAJOR[deg]
        p.put(pad([freq(r + 12), freq(r + 19), freq(r + 24)], p.beat * 4.8, 1.8, 2.0, 1500.0), p.at(bar, 0.0), 0.4, 0.6)
        for i in range(8):
            m = r + 24 + (0, 7, 12, 16, 12, 7, 12, 16)[i]
            p.put(pluck(freq(m), 2.0, p.rng, 0.997, 0.35), p.at(bar, i * 0.5), 0.3, 0.55)
        p.put(bass_note(freq(r), 3.5, 0.3), p.at(bar, 0.0), 0.5)
    tune = phrase_bars(p.rng, p.bars - 4, [(0.0, 2.0), (2.0, 1.0), (3.0, 1.0)], [0, 1, 2, 4, 5], 0)
    melody(p, root, MAJOR, [[]] * 4 + tune, lambda f, d: pad([f], d + 0.5, 0.25, 0.6, 2200.0), 0.35, 0.6, octave=3)
    return p.finish()


def tape_7() -> np.ndarray:
    """Frostpeak: glassy bells and a cold, slow pad."""
    p = Piece("tape_7", 72.0, 18, tail=4.0)
    root = 47  # B2
    prog = [0, 5, 2, 4]
    for bar in range(p.bars):
        deg = prog[bar % len(prog)]
        ch = chord(root + 12, MINOR, deg, 4)
        p.put(pad([freq(m) for m in ch], p.beat * 4.8, 1.4, 1.6, 1500.0), p.at(bar, 0.0), 0.35, 0.6)
        p.put(bass_note(freq(root - 12 + MINOR[deg]), 3.5, 0.2), p.at(bar, 0.0), 0.45)
        for i in range(8):
            if p.rng.random() < 0.75:
                m = root + 36 + PENT_MINOR[(i + bar) % 5] + 12 * ((i + bar) % 2)
                p.put(bell_note(freq(m), 2.4, 1.0), p.at(bar, i * 0.5), 0.26, 0.7)
    return p.finish()


def tape_8() -> np.ndarray:
    """Home Again: bright, hopeful, and a little quicker."""
    p = Piece("tape_8", 104.0, 24)
    root = 45  # A2
    prog = [0, 4, 5, 3, 0, 4, 3, 0]
    for bar in range(p.bars):
        deg = prog[bar % len(prog)]
        ch = chord(root + 12, MAJOR, deg)
        for i, m in enumerate([ch[0], ch[1], ch[2], ch[1] + 12, ch[2], ch[1], ch[2] + 12, ch[1] + 12]):
            p.put(pluck(freq(m), 1.0, p.rng, 0.995, 0.7), p.at(bar, i * 0.5), 0.4 if i % 2 == 0 else 0.28, 0.3)
        b = root + MAJOR[deg]
        p.put(bass_note(freq(b), 1.4), p.at(bar, 0.0), 0.6)
        p.put(bass_note(freq(b + 7), 0.8), p.at(bar, 2.0), 0.4)
        for beat in (0.0, 2.0):
            p.put(kick(p.rng), p.at(bar, beat), 0.4)
        for beat in (1.0, 3.0):
            p.put(soft_snare(p.rng), p.at(bar, beat), 0.13)
        for i in range(8):
            p.put(brush(p.rng, 0.05), p.at(bar, i * 0.5 + 0.25), 0.07)
    tune = phrase_bars(p.rng, p.bars - 6, [(0.0, 1.0), (1.0, 0.5), (1.5, 0.5), (2.0, 1.0), (3.0, 1.0)], [2, 4, 5, 7, 9, 11], 0)
    melody(p, root, MAJOR, [[]] * 6 + tune, lambda f, d: pluck(f, d + 0.5, p.rng, 0.996, 0.7), 0.5, 0.4, octave=2)
    return p.finish()


TAPES = {1: tape_1, 2: tape_2, 3: tape_3, 4: tape_4, 5: tape_5, 6: tape_6, 7: tape_7, 8: tape_8}


def main() -> None:
    wanted = [int(a) for a in sys.argv[1:]] or list(TAPES)
    for i in wanted:
        x = TAPES[i]()
        path = OUT / f"tape_{i}.ogg"
        dsp.write_ogg(path, x, quality=0.3)
        print(f"music/tape_{i}.ogg  {len(x) / SR:5.1f} s  {path.stat().st_size / 1024:6.0f} KB  {lufs(x.reshape(-1, 1), SR):.1f} LUFS  peak {20 * np.log10(np.max(np.abs(x))):.1f} dB")


if __name__ == "__main__":
    main()

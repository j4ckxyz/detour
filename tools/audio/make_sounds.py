#!/usr/bin/env python3
"""Generate the game's synthesized sounds into game/assets/audio/ (everything except the
birdsong clips, which are real CC0 recordings: see fetch_birds.py).

    python3 tools/audio/make_sounds.py [name ...]      # all, or only the ones named

Everything here is made from noise and sine waves with fixed seeds, so the same command
gives the same sounds. Needs numpy, scipy and soundfile (`pip install numpy scipy soundfile`).
Nothing is sampled from anywhere: these are our own sounds and carry the game's licence.

Loops are built from circular (FFT) filtering and periodic modulation, and their length
holds a whole number of engine cycles, chirps and so on, so they wrap without a seam
(tools/audio/check_sounds.py measures the jump at the wrap).

Levels: loops are left at a moderate, quiet level (the game's mixers set the rest);
one-shots are peak-normalised. Nothing goes above -3 dBFS. Every high end is rolled off:
this is meant to be soothing, not sharp.
"""

from __future__ import annotations

import sys
import zlib
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import dsp  # noqa: E402
from dsp import SR, bell, filt, hp, lp, pinkish, slow_random, swell  # noqa: E402
from check_sounds import lufs  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "game" / "assets" / "audio"

# name -> (function, output sub-folder)
SOUNDS: dict[str, tuple] = {}


def sound(folder: str):
    def register(fn):
        SOUNDS[fn.__name__] = (fn, folder)
        return fn

    return register


def rng_for(name: str) -> np.random.Generator:
    return np.random.default_rng(zlib.crc32(name.encode()))


def peak_normalize(x: np.ndarray, peak_db: float = -5.0) -> np.ndarray:
    return x * 10.0 ** (peak_db / 20.0) / (np.max(np.abs(x)) + 1e-12)


def normalize_lufs(x: np.ndarray, target: float, peak_db: float = -3.0) -> np.ndarray:
    """Levels a loop to `target` LUFS (BS.1770 loudness, as check_sounds.py measures it);
    peaks that would pass `peak_db` are rounded off with a soft knee, then re-levelled."""
    y = x.reshape(len(x), -1)
    ceiling = 10.0 ** (peak_db / 20.0)
    for _ in range(6):
        y = y * 10.0 ** ((target - lufs(y, SR)) / 20.0)
        if np.max(np.abs(y)) <= ceiling:
            break
        y = ceiling * np.tanh(y / ceiling)
    if np.max(np.abs(y)) > ceiling:
        raise ValueError("cannot reach %.1f LUFS under %.1f dBFS" % (target, peak_db))
    return y.reshape(x.shape)


def stereo(left: np.ndarray, right: np.ndarray) -> np.ndarray:
    return np.stack([left, right], axis=1)


# --- engine (a lazy big-block V8) ------------------------------------------------------------

# A V8 fires eight times every two revolutions. Its uneven firing order gives the burble:
# each firing is a little early or late, and a little stronger or weaker.
FIRE_TIMING = np.array([0.0, 0.06, -0.04, 0.05, -0.03, 0.04, -0.05, 0.02])
FIRE_AMP = np.array([1.0, 0.82, 0.95, 0.74, 1.0, 0.86, 0.92, 0.78])


def _pulses(times: np.ndarray, amps: np.ndarray, n: int, wrap: bool) -> np.ndarray:
    """An impulse train (fractional positions spread over two samples)."""
    x = np.zeros(n)
    pos = times * SR
    i = np.floor(pos).astype(int)
    frac = pos - i
    for k, a in ((0, 1.0 - frac), (1, frac)):
        idx = i + k
        if wrap:
            np.add.at(x, idx % n, amps * a)
        else:
            ok = (idx >= 0) & (idx < n)
            np.add.at(x, idx[ok], (amps * a)[ok])
    return x


def _engine_body(x: np.ndarray, lp_fc: float, noise_level: float, rng: np.random.Generator, wrap: bool) -> np.ndarray:
    """Firing pulses through the exhaust and block: low-passed, with two boomy resonances,
    plus combustion / valve noise that follows the pulses and an intake roar."""
    n = len(x)
    body = filt(x, lambda f: hp(f, 28.0, 2) * lp(f, lp_fc, 2) * (1.0 + 1.6 * bell(f, 90.0, 0.35) + 1.0 * bell(f, 185.0, 0.3)))
    # Noise that swells with each firing (the burst of combustion), 500 Hz - 2.5 kHz.
    burst = filt(x, lambda f: lp(f, 1.0 / (2 * np.pi * 0.012), 1))  # ~12 ms decay: smoothed impulses
    grit = filt(rng.standard_normal(n), lambda f: hp(f, 500.0, 2) * lp(f, 2500.0, 2)) * np.abs(burst) / (np.std(burst) + 1e-9)
    return body + noise_level * grit * (np.std(body) / (np.std(grit) + 1e-9))


def engine_loop(rpm: float, secs: float, lp_fc: float, rough: float, roar: float, target_db: float, name: str) -> np.ndarray:
    rng = rng_for(name)
    n = int(round(secs * SR))
    cycles = int(round(rpm / 120.0 * secs))
    cycle_hz = cycles / secs
    k = np.arange(cycles * 8)
    within = k % 8
    times = (k // 8 + (within + FIRE_TIMING[within] + rng.normal(0.0, 0.012 + rough * 0.05, k.size)) / 8.0) / cycle_hz
    amps = FIRE_AMP[within] * (1.0 + rough * rng.standard_normal(k.size))
    x = _engine_body(_pulses(times, amps, n, wrap=True), lp_fc, 0.22 + 0.15 * (rpm / 3800.0), rng, True)
    # Intake / mechanical roar grows with rpm and drifts a little.
    air = filt(pinkish(rng.standard_normal(n)), lambda f: hp(f, 120.0, 2) * lp(f, 1400.0, 2)) * swell(n, 0.7, 0.25, rng)
    x = x / np.std(x) + roar * air / np.std(air)
    x = np.tanh(1.5 * x)  # a warm bit of saturation
    x = filt(x, lambda f: hp(f, 30.0, 2) * lp(f, 4200.0, 2))
    x = dsp.remove_dc(x)
    return dsp.normalize_rms(x, target_db, -3.0)


@sound("rv")
def engine_idle() -> np.ndarray:
    # 4 s at 750 rpm: 25 engine cycles. The four loops (750, 1320, 2100, 3400 rpm) are
    # crossfaded and re-pitched by the game (see RVAudio); no loop is stretched more than ~1.7x.
    return engine_loop(750.0, 4.0, 380.0, 0.16, 0.10, -24.0, "engine_idle")


@sound("rv")
def engine_low() -> np.ndarray:
    return engine_loop(1320.0, 3.0, 560.0, 0.11, 0.18, -22.5, "engine_low")


@sound("rv")
def engine_mid() -> np.ndarray:
    return engine_loop(2100.0, 4.0, 800.0, 0.08, 0.28, -21.0, "engine_mid")


@sound("rv")
def engine_high() -> np.ndarray:
    return engine_loop(3400.0, 3.0, 1300.0, 0.05, 0.5, -19.0, "engine_high")


def _firings(rpm_of_t: np.ndarray) -> np.ndarray:
    """Firing times (s) of a V8 whose speed follows `rpm_of_t` (one value per sample)."""
    phase = np.cumsum(rpm_of_t / 60.0 * 4.0) / SR  # firings so far
    whole = np.floor(phase).astype(int)
    changes = np.nonzero(np.diff(whole) > 0)[0] + 1
    return changes / SR


def engine_oneshot(secs: float, rpm_of_t, amp_of_t, misfire_of_t, name: str, lp_fc: float = 520.0) -> np.ndarray:
    rng = rng_for(name)
    n = int(secs * SR)
    t = np.arange(n) / SR
    times = _firings(rpm_of_t(t))
    times = times + rng.normal(0.0, 0.004, times.size)
    keep = rng.random(times.size) > misfire_of_t(np.clip(times, 0, secs))
    times = times[keep]
    amps = amp_of_t(np.clip(times, 0, secs)) * (0.75 + 0.5 * rng.random(times.size))
    x = _engine_body(_pulses(times, amps, n, wrap=False), lp_fc, 0.2, rng, False)
    return x


@sound("rv")
def engine_start() -> np.ndarray:
    """The engine catching (played as the crank loop ends): it fires unevenly, flares to
    ~1150 rpm and settles back to idle."""
    secs = 2.2

    def rpm(t: np.ndarray) -> np.ndarray:
        flare = 260.0 + (1150.0 - 260.0) * np.clip(t / 0.5, 0.0, 1.0) ** 0.6
        settle = 750.0 + 400.0 * np.exp(-np.maximum(t - 0.5, 0.0) / 0.4)
        return np.where(t < 0.5, flare, settle)

    x = engine_oneshot(secs, rpm, lambda t: 0.55 + 0.45 * np.clip(t / 0.5, 0, 1), lambda t: np.where(t < 0.35, 0.2, 0.02), "engine_start")
    x = np.tanh(1.3 * x / np.std(x))
    x = dsp.fade(dsp.remove_dc(x), 0.01, 0.5)
    return peak_normalize(x, -6.0)


@sound("rv")
def engine_stall() -> np.ndarray:
    """The engine dying: firings slow and miss, the last few shudder, one soft clunk of the
    block settling."""
    secs = 1.9

    def rpm(t: np.ndarray) -> np.ndarray:
        return 620.0 * np.clip(1.0 - t / 1.3, 0.0, 1.0) ** 1.6 + 25.0

    def amp(t: np.ndarray) -> np.ndarray:
        return np.clip(1.0 - t / 1.35, 0.0, 1.0) ** 0.8

    x = engine_oneshot(secs, rpm, amp, lambda t: np.clip((t - 0.25) / 1.0, 0.0, 0.6), "engine_stall", lp_fc=430.0)
    x = np.tanh(1.3 * x / (np.std(x) + 1e-9))
    rng = rng_for("engine_stall_clunk")
    t = np.arange(int(0.4 * SR)) / SR
    clunk = np.sin(2 * np.pi * (58.0 - 20.0 * t) * t) * np.exp(-t / 0.07) * 0.35
    clunk += filt(rng.standard_normal(t.size), lambda f: hp(f, 150.0, 2) * lp(f, 900.0, 2)) * np.exp(-t / 0.02) * 0.25
    dsp.add_at(x, clunk, 1.32)
    x = dsp.fade(dsp.remove_dc(x), 0.005, 0.25)
    return peak_normalize(x, -6.0)


@sound("rv")
def starter_crank() -> np.ndarray:
    """Cranking: the starter motor's whir and the engine turning over on compression (about
    220 rpm, four compressions a turn), 3 s, loops."""
    rng = rng_for("starter_crank")
    n = 3 * SR
    chug_hz = 220.0 / 60.0 * 4.0
    count = int(round(chug_hz * 3.0))
    chug_hz = count / 3.0
    t = np.arange(int(0.09 * SR)) / SR
    chug = np.sin(2 * np.pi * (46.0 + 25.0 * np.exp(-t / 0.02)) * t) * np.exp(-t / 0.024) * (1.0 - np.exp(-t / 0.004))
    thump = np.zeros(n)
    beat = np.zeros(n)  # 1 at each compression, decaying: ducks the whine
    for i in range(count):
        at = (i + 0.5 * FIRE_TIMING[i % 8]) / chug_hz
        a = FIRE_AMP[i % 8] * (0.9 + 0.2 * rng.random())
        dsp.add_at(thump, chug, at, a, wrap=True)
        dsp.add_at(beat, dsp.envelope_exp(int(0.06 * SR), 0.02), at, 1.0, wrap=True)
    beat = np.minimum(beat, 1.0)
    whine_mod = 0.02 * slow_random(n, 3.0, rng) + 0.05 * (beat - beat.mean())
    whine = dsp.periodic_tone(196.0, whine_mod, n, harmonics=(1.0, 0.55, 0.35, 0.2, 0.1))
    whine = filt(whine, lambda f: lp(f, 2200.0, 2)) * (1.0 - 0.4 * beat) * swell(n, 2.0, 0.08, rng)
    gears = filt(rng.standard_normal(n), lambda f: hp(f, 700.0, 2) * lp(f, 3200.0, 2)) * (0.6 + 0.4 * beat)
    x = 1.0 * thump / np.std(thump) + 0.5 * whine / np.std(whine) + 0.12 * gears / np.std(gears)
    x = np.tanh(1.2 * x)
    x = dsp.remove_dc(filt(x, lambda f: hp(f, 30.0, 2) * lp(f, 4500.0, 2)))
    return dsp.normalize_rms(x, -21.0, -3.0)


@sound("rv")
def gear_clunk() -> np.ndarray:
    """A gearbox going into gear: a low thump and a soft metallic click."""
    rng = rng_for("gear_clunk")
    n = int(0.5 * SR)
    t = np.arange(n) / SR
    thump = np.sin(2 * np.pi * (58.0 + 55.0 * np.exp(-t / 0.03)) * t) * np.exp(-t / 0.07) * (1.0 - np.exp(-t / 0.002))
    click = filt(rng.standard_normal(n), lambda f: hp(f, 400.0, 2) * lp(f, 2600.0, 2)) * np.exp(-t / 0.012)
    ring = (np.sin(2 * np.pi * 640.0 * t) * np.exp(-t / 0.05) + 0.6 * np.sin(2 * np.pi * 1180.0 * t) * np.exp(-t / 0.035)) * 0.16
    x = thump + 0.45 * click / np.std(click) * 0.25 + ring
    x = filt(x, lambda f: lp(f, 5500.0, 2))
    return peak_normalize(dsp.fade(dsp.remove_dc(x), 0.0, 0.05), -6.0)


# --- tires and the road --------------------------------------------------------------------


@sound("rv")
def tire_road() -> np.ndarray:
    """Tires humming on the road: a low, soft rush. 8 s, loops."""
    rng = rng_for("tire_road")
    n = 8 * SR
    x = filt(pinkish(rng.standard_normal(n)), lambda f: hp(f, 70.0, 2) * lp(f, 850.0, 3))
    x = x / np.std(x)
    x = x * swell(n, 1.2, 0.16, rng) * swell(n, 9.0, 0.10, rng)
    # A faint drone of the tread pattern, wobbling so it can't sound like a sine.
    tread = dsp.periodic_tone(118.0, 0.03 * slow_random(n, 2.0, rng), n, harmonics=(1.0, 0.4))
    x = x + 0.12 * tread
    return dsp.normalize_rms(dsp.remove_dc(x), -22.0, -3.0)


@sound("rv")
def tire_gravel() -> np.ndarray:
    """Tires crunching on gravel and dirt: many small pebbles and a rushing bed. 8 s, loops."""
    rng = rng_for("tire_gravel")
    n = 8 * SR
    grains = np.zeros(n)
    count = int(950 * 8)
    pos = rng.integers(0, n, count)
    amp = rng.exponential(1.0, count) ** 1.3
    np.add.at(grains, pos, amp * np.where(rng.random(count) < 0.5, -1.0, 1.0))
    grains = filt(grains, lambda f: hp(f, 700.0, 2) * lp(f, 4200.0, 2))
    bed = filt(pinkish(rng.standard_normal(n)), lambda f: hp(f, 150.0, 2) * lp(f, 2200.0, 2))
    x = grains / np.std(grains) + 0.55 * bed / np.std(bed)
    x = x * swell(n, 0.7, 0.22, rng)
    x = filt(x, lambda f: lp(f, 5200.0, 2))
    return dsp.normalize_rms(dsp.remove_dc(x), -23.0, -3.0)


@sound("rv")
def landing_thud() -> np.ndarray:
    """The body coming down hard on its springs: a deep thump with a short settling rattle."""
    rng = rng_for("landing_thud")
    n = int(0.9 * SR)
    t = np.arange(n) / SR
    thump = np.sin(2 * np.pi * (36.0 + 60.0 * np.exp(-t / 0.05)) * t) * np.exp(-t / 0.13) * (1.0 - np.exp(-t / 0.004))
    body = filt(rng.standard_normal(n), lambda f: hp(f, 60.0, 2) * lp(f, 420.0, 2)) * np.exp(-t / 0.09)
    rattle = filt(rng.standard_normal(n), lambda f: hp(f, 250.0, 2) * lp(f, 1600.0, 2)) * np.exp(-t / 0.08) * (0.5 + 0.5 * np.sin(2 * np.pi * 23.0 * t))
    x = thump + 0.5 * body / np.std(body) * 0.3 + 0.12 * rattle / np.std(rattle) * 0.3
    x = filt(x, lambda f: lp(f, 3000.0, 2))
    return peak_normalize(dsp.fade(dsp.remove_dc(x), 0.0, 0.15), -5.0)


@sound("rv")
def crash() -> np.ndarray:
    """The RV hitting something: a heavy thump and crumpling metal (not a scream: rounded
    off well below 6 kHz)."""
    rng = rng_for("crash")
    n = int(1.6 * SR)
    t = np.arange(n) / SR
    thump = np.sin(2 * np.pi * (44.0 + 70.0 * np.exp(-t / 0.04)) * t) * np.exp(-t / 0.12) * (1.0 - np.exp(-t / 0.003))
    smash = filt(rng.standard_normal(n), lambda f: hp(f, 120.0, 2) * lp(f, 2600.0, 2)) * np.exp(-t / 0.10) * (1.0 - np.exp(-t / 0.003))
    x = thump + 0.42 * smash / np.std(smash) * 0.3
    metal = np.zeros(n)
    for _ in range(26):
        at = float(rng.exponential(0.16))
        f0 = float(rng.uniform(280.0, 2300.0))
        tau = float(rng.uniform(0.02, 0.09))
        k = np.arange(int(tau * 6 * SR)) / SR
        dsp.add_at(metal, np.sin(2 * np.pi * f0 * k) * np.exp(-k / tau), at, float(rng.uniform(0.02, 0.07)))
    x = x + metal
    x = filt(x, lambda f: lp(f, 4200.0, 2))
    return peak_normalize(dsp.fade(dsp.remove_dc(x), 0.0, 0.5), -4.0)


# --- small touches ----------------------------------------------------------------------------


def _hammer(name: str, f0: float) -> np.ndarray:
    rng = rng_for(name)
    n = int(0.7 * SR)
    t = np.arange(n) / SR
    modes = [(1.0, 0.10, 1.0), (2.32, 0.065, 0.55), (4.11, 0.04, 0.3), (6.7, 0.025, 0.14)]
    ring = sum(a * np.sin(2 * np.pi * f0 * m * t * (1.0 + 0.002 * rng.standard_normal())) * np.exp(-t / tau) for m, tau, a in modes)
    click = filt(rng.standard_normal(n), lambda f: hp(f, 500.0, 2) * lp(f, 3800.0, 2)) * np.exp(-t / 0.006)
    thud = np.sin(2 * np.pi * (120.0 + 80.0 * np.exp(-t / 0.01)) * t) * np.exp(-t / 0.035)
    x = 0.5 * ring + 0.7 * click / np.std(click) * 0.25 + 0.8 * thud
    x = filt(x, lambda f: lp(f, 6000.0, 2))
    return peak_normalize(dsp.fade(dsp.remove_dc(x), 0.0, 0.15), -6.0)


@sound("tools")
def hammer_clank_1() -> np.ndarray:
    return _hammer("hammer_clank_1", 720.0)


@sound("tools")
def hammer_clank_2() -> np.ndarray:
    return _hammer("hammer_clank_2", 810.0)


@sound("tools")
def hammer_clank_3() -> np.ndarray:
    return _hammer("hammer_clank_3", 665.0)


def _latch(rng: np.random.Generator, n: int, at: float, gain: float) -> np.ndarray:
    t = np.arange(int(0.05 * SR)) / SR
    click = filt(rng.standard_normal(t.size), lambda f: hp(f, 600.0, 2) * lp(f, 3200.0, 2)) * np.exp(-t / 0.006)
    click = click / np.std(click) * 0.25 + np.sin(2 * np.pi * 420.0 * t) * np.exp(-t / 0.02) * 0.3
    out = np.zeros(n)
    dsp.add_at(out, click, at, gain)
    return out


@sound("rv")
def door_open() -> np.ndarray:
    """The latch, a little push of air, the hinge swinging free."""
    rng = rng_for("door_open")
    n = int(0.8 * SR)
    t = np.arange(n) / SR
    air = filt(pinkish(rng.standard_normal(n)), lambda f: hp(f, 90.0, 2) * lp(f, 900.0, 2)) * np.sin(np.pi * np.clip(t / 0.5, 0.0, 1.0)) ** 2
    x = _latch(rng, n, 0.0, 1.0) + _latch(rng, n, 0.045, 0.6) + 0.5 * air / np.std(air) * 0.2
    x = filt(x, lambda f: lp(f, 4500.0, 2))
    return peak_normalize(dsp.fade(dsp.remove_dc(x), 0.0, 0.2), -7.0)


@sound("rv")
def door_close() -> np.ndarray:
    """The door swinging shut: a solid thump and the latch catching."""
    rng = rng_for("door_close")
    n = int(0.8 * SR)
    t = np.arange(n) / SR
    thump = np.sin(2 * np.pi * (70.0 + 50.0 * np.exp(-t / 0.02)) * t) * np.exp(-t / 0.09) * (1.0 - np.exp(-t / 0.003))
    panel = filt(rng.standard_normal(n), lambda f: hp(f, 100.0, 2) * lp(f, 700.0, 2)) * np.exp(-t / 0.06)
    x = thump + 0.4 * panel / np.std(panel) * 0.25 + _latch(rng, n, 0.06, 0.55)
    x = filt(x, lambda f: lp(f, 4500.0, 2))
    return peak_normalize(dsp.fade(dsp.remove_dc(x), 0.0, 0.25), -6.0)


# --- ambience ----------------------------------------------------------------------------------


def _wind_channel(seed_name: str, secs: float) -> np.ndarray:
    rng = rng_for(seed_name)
    n = int(secs * SR)
    low = filt(rng.standard_normal(n), lambda f: hp(f, 35.0, 2) * lp(f, 240.0, 2)) * swell(n, 0.13, 0.4, rng)
    mid = filt(rng.standard_normal(n), lambda f: hp(f, 220.0, 2) * lp(f, 950.0, 2)) * swell(n, 0.22, 0.45, rng)
    top = filt(rng.standard_normal(n), lambda f: hp(f, 700.0, 1) * lp(f, 2600.0, 2)) * swell(n, 0.35, 0.6, rng) ** 1.5
    x = low / np.std(low) + 0.8 * mid / np.std(mid) + 0.35 * top / np.std(top)
    return filt(x, lambda f: lp(f, 4000.0, 2))


@sound("ambience")
def wind_bed() -> np.ndarray:
    """Wind: a low, breathing rush that swells and eases (bands gust on their own). 20 s, loops."""
    secs = 20.0
    x = stereo(_wind_channel("wind_bed_l", secs), _wind_channel("wind_bed_r", secs))
    return normalize_lufs(x - x.mean(axis=0), -27.0)


def _leaves_channel(seed_name: str, secs: float) -> np.ndarray:
    rng = rng_for(seed_name)
    n = int(secs * SR)
    x = filt(pinkish(rng.standard_normal(n)), lambda f: hp(f, 1000.0, 2) * lp(f, 4200.0, 3))
    x = x / np.std(x) * swell(n, 0.45, 0.6, rng) ** 1.2 * swell(n, 5.0, 0.3, rng)
    soft = filt(rng.standard_normal(n), lambda f: hp(f, 300.0, 2) * lp(f, 1200.0, 2)) * swell(n, 0.3, 0.6, rng)
    return x + 0.3 * soft / np.std(soft)


@sound("ambience")
def wind_trees() -> np.ndarray:
    """Wind in the leaves and needles: a soft airy rustle that comes and goes. 20 s, loops."""
    secs = 20.0
    x = stereo(_leaves_channel("wind_trees_l", secs), _leaves_channel("wind_trees_r", secs))
    return normalize_lufs(x - x.mean(axis=0), -30.0)


def _rain_channel(seed_name: str, secs: float) -> np.ndarray:
    rng = rng_for(seed_name)
    n = int(secs * SR)
    bed = filt(pinkish(rng.standard_normal(n)), lambda f: hp(f, 350.0, 2) * lp(f, 4500.0, 3))
    bed = bed / np.std(bed) * swell(n, 0.6, 0.07, rng)
    # Thousands of tiny drops a second (impulses through a band-pass: each is a soft tick).
    drops = np.zeros(n)
    count = int(2600 * secs)
    np.add.at(drops, rng.integers(0, n, count), rng.exponential(1.0, count) * rng.choice([-1.0, 1.0], count))
    drops = filt(drops, lambda f: hp(f, 1500.0, 2) * lp(f, 5200.0, 3))
    drops = drops / np.std(drops)
    # Now and then a heavier drop landing on a leaf or puddle: a short, soft pitched plink.
    plinks = np.zeros(n)
    for _ in range(int(16 * secs)):
        at = float(rng.uniform(0.0, secs))
        f0 = float(rng.uniform(900.0, 3200.0))
        k = np.arange(int(0.05 * SR)) / SR
        dsp.add_at(plinks, np.sin(2 * np.pi * f0 * k * (1.0 + 0.3 * np.exp(-k / 0.005))) * np.exp(-k / 0.008), at, float(rng.lognormal(-1.0, 0.6)) * 0.3, wrap=True)
    plinks = plinks / (np.std(plinks) + 1e-9)
    x = 0.55 * bed + 1.0 * drops + 0.22 * plinks
    return filt(x, lambda f: lp(f, 5600.0, 3))


@sound("ambience")
def rain_loop() -> np.ndarray:
    """Steady rain falling on leaves and ground: a soft hiss of many tiny drops with a few
    heavier ones. 16 s, loops."""
    secs = 16.0
    x = stereo(_rain_channel("rain_l", secs), _rain_channel("rain_r", secs))
    return normalize_lufs(x - x.mean(axis=0), -27.0)


@sound("ambience")
def rain_roof() -> np.ndarray:
    """Rain drumming on the RV's roof, heard from inside: sparse soft thumps. 12 s, loops."""
    rng = rng_for("rain_roof")
    secs = 12.0
    n = int(secs * SR)
    x = np.zeros(n)
    count = int(75 * secs)
    np.add.at(x, rng.integers(0, n, count), rng.exponential(1.0, count) ** 1.2)
    x = filt(x, lambda f: hp(f, 130.0, 2) * lp(f, 800.0, 2) * (1.0 + 1.5 * bell(f, 260.0, 0.35)))
    ticks = np.zeros(n)
    tc = int(45 * secs)
    np.add.at(ticks, rng.integers(0, n, tc), rng.exponential(1.0, tc))
    ticks = filt(ticks, lambda f: hp(f, 1800.0, 2) * lp(f, 4500.0, 2))
    hiss = filt(pinkish(rng.standard_normal(n)), lambda f: hp(f, 400.0, 2) * lp(f, 2500.0, 2))
    y = x / np.std(x) + 0.16 * ticks / np.std(ticks) + 0.3 * hiss / np.std(hiss)
    y = y * swell(n, 0.5, 0.12, rng)
    return normalize_lufs(dsp.remove_dc(y), -27.0)


def _thunder(name: str, secs: float, lumps: int) -> np.ndarray:
    rng = rng_for(name)
    n = int(secs * SR)
    t = np.arange(n) / SR
    deep = filt(rng.standard_normal(n), lambda f: hp(f, 20.0, 2) * lp(f, 110.0, 2))
    mid = filt(rng.standard_normal(n), lambda f: hp(f, 30.0, 2) * lp(f, 260.0, 2))
    high = filt(rng.standard_normal(n), lambda f: hp(f, 80.0, 2) * lp(f, 900.0, 2))
    deep, mid, high = (v / np.std(v) for v in (deep, mid, high))
    # Brighter at the start, darker as it rolls away.
    b = np.clip(t / (secs * 0.6), 0.0, 1.0)
    x = (1.0 - b) * high * 0.5 + (1.0 - 0.4 * b) * mid * 0.8 + deep * (0.6 + 0.6 * b)
    # A soft-edged onset, then lumps of rumble: the sound coming back off the hills.
    env = 1.0 * np.exp(-0.5 * ((t - 0.2) / 0.4) ** 2)
    for _ in range(lumps):
        at = float(rng.uniform(0.7, secs * 0.6))
        width = float(rng.uniform(0.3, 0.9))
        env += float(rng.uniform(0.35, 0.8)) * np.exp(-at / 5.0) * np.exp(-0.5 * ((t - at) / width) ** 2)
    env += 0.25 * np.exp(-t / 2.8)
    env = env / env.max() * np.exp(-t / 4.5)
    crackle = np.zeros(n)
    for _ in range(9):
        at = float(rng.uniform(0.05, 1.3))
        k = np.arange(int(0.05 * SR)) / SR
        burst = filt(rng.standard_normal(k.size), lambda f: hp(f, 150.0, 2) * lp(f, 1800.0, 2)) * np.exp(-k / 0.012)
        dsp.add_at(crackle, burst, at, float(rng.uniform(0.3, 1.0)))
    attack = 1.0 - np.exp(-t / 0.1)
    y = x * env * attack + 0.45 * crackle / (np.std(crackle) + 1e-9) * np.exp(-t / 0.5) * attack * 0.2
    y = dsp.fade(dsp.remove_dc(y), 0.0, min(2.0, secs * 0.3))
    return normalize_lufs(y, -21.0)


@sound("ambience")
def thunder_1() -> np.ndarray:
    return _thunder("thunder_1", 9.0, 6)


@sound("ambience")
def thunder_2() -> np.ndarray:
    return _thunder("thunder_2", 7.0, 5)


def _crickets_channel(name: str, secs: float, pans: np.ndarray, side: int) -> np.ndarray:
    rng = rng_for(name)
    n = int(secs * SR)
    out = np.zeros(n)
    for i, pan in enumerate(pans):
        carrier = float(rng.uniform(3500.0, 5100.0))
        chirps = int(rng.integers(int(secs * 2.6), int(secs * 3.6)))  # chirps in the loop
        period = secs / chirps
        pulse_hz = float(rng.uniform(38.0, 52.0))
        pulses = int(rng.integers(3, 5))
        k = np.arange(int(0.012 * SR)) / SR
        pulse = np.sin(2 * np.pi * carrier * k) * np.hanning(k.size)
        song = np.zeros(n)
        offset = float(rng.uniform(0.0, period))
        for c in range(chirps):
            base = offset + c * period
            for p in range(pulses):
                dsp.add_at(song, pulse, base + p / pulse_hz, 1.0 - 0.12 * p, wrap=True)
        # Bouts: each cricket sings for a while, rests, sings again.
        bout = np.clip(0.6 + 0.9 * slow_random(n, 0.12, rng), 0.0, 1.0) ** 1.5
        gain = 0.35 + 0.65 * float(rng.random())
        w = pan if side == 1 else 1.0 - pan
        out += song * bout * gain * (0.35 + 0.65 * w)
    return filt(out, lambda f: lp(f, 6500.0, 2) * hp(f, 2500.0, 2))


@sound("ambience")
def crickets_loop() -> np.ndarray:
    """A field of crickets at night: several singers chirping at their own pace, coming and
    going. 12 s, loops."""
    secs = 12.0
    rng = rng_for("crickets_pans")
    pans = rng.random(7)
    x = stereo(_crickets_channel("crickets_l", secs, pans, 0), _crickets_channel("crickets_r", secs, pans, 1))
    return normalize_lufs(x - x.mean(axis=0), -30.0)


# --- main ---------------------------------------------------------------------------------------

# Stronger compression for noise-like beds, which Vorbis spends most of its bits on.
QUALITY = {"wind_bed": 0.35, "wind_trees": 0.35, "rain_loop": 0.4, "rain_roof": 0.35, "crickets_loop": 0.4}


def main() -> None:
    wanted = sys.argv[1:] or list(SOUNDS)
    for name in wanted:
        fn, folder = SOUNDS[name]
        x = fn()
        path = OUT / folder / f"{name}.ogg"
        dsp.write_ogg(path, x, quality=QUALITY.get(name, 0.5))
        print(f"{folder}/{name}.ogg  {len(x) / SR:5.1f} s  {path.stat().st_size / 1024:6.0f} KB")


if __name__ == "__main__":
    main()

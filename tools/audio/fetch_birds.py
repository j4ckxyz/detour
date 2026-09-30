#!/usr/bin/env python3
"""Fetch the birdsong clips (real recordings, CC0) into game/assets/audio/birds/.

    python3 tools/audio/fetch_birds.py

The clips are single songs of a common blackbird and an Eurasian blackcap from BigSoundBank
(https://bigsoundbank.com), recorded in the Centre region of France. Every page says:

    CC0 (public domain): Free and royalty-free

and https://bigsoundbank.com/licenses.html spells it out (Creative Commons CC0 1.0
Universal: share, adapt, use commercially, without restrictions or asking permission). The
script checks that line on each page again before it uses a file and refuses if it's gone.

Each clip is downloaded once (FLAC, into art-src/cache/audio/, git-ignored) and then tidied
for the game: mono, 44.1 kHz, rumble under 180 Hz cut, a soft roll-off above 8.5 kHz (blackbird
songs are punctuated by little broadband ticks that would sound harsh), trimmed to the song
with short fades, and levelled. Only the results are committed.

Needs numpy, scipy and soundfile (`pip install numpy scipy soundfile`) and network access.
"""

from __future__ import annotations

import io
import re
import sys
import time
import urllib.request
from math import gcd
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy import signal

sys.path.insert(0, str(Path(__file__).resolve().parent))
import dsp  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / "art-src" / "cache" / "audio"
OUT = ROOT / "game" / "assets" / "audio" / "birds"
SITE = "https://bigsoundbank.com"
LICENCE_LINE = "CC0 (public domain): Free and royalty-free"
UA = {"User-Agent": "Mozilla/5.0 (Detour game asset script)"}

# game name -> (BigSoundBank page, sound id)
CLIPS: dict[str, tuple[str, int]] = {
    "blackbird_1": ("common-blackbird-3-s3476.html", 3476),
    "blackbird_2": ("common-blackbird-5-s3478.html", 3478),
    "blackbird_3": ("common-blackbird-6-s3479.html", 3479),
    "blackbird_4": ("common-blackbird-7-s3480.html", 3480),
    "blackbird_5": ("common-blackbird-11-s3484.html", 3484),
    "blackbird_6": ("common-blackbird-12-s3485.html", 3485),
    "blackbird_7": ("common-blackbird-14-s3487.html", 3487),
    "blackbird_8": ("common-blackbird-15-s3488.html", 3488),
    "blackbird_9": ("common-blackbird-17-s3490.html", 3490),
    "blackbird_10": ("common-blackbird-22-s3495.html", 3495),
    "blackbird_11": ("common-blackbird-23-s3496.html", 3496),
    "blackcap_1": ("eurasian-blackcap-1-s3466.html", 3466),
    "blackcap_2": ("eurasian-blackcap-5-s3470.html", 3470),
    "blackcap_3": ("eurasian-blackcap-6-s3471.html", 3471),
}
TARGET_RMS_DB = -22.0
PEAK_DB = -4.0


def get(url: str) -> bytes:
    for attempt in range(4):
        try:
            return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60).read()
        except Exception as e:  # noqa: BLE001 (a script: retry, then give up loudly)
            print("  retrying", url, e)
            time.sleep(4 * (attempt + 1))
    raise RuntimeError("could not fetch " + url)


def original(name: str, page: str, sound_id: int) -> tuple[np.ndarray, int]:
    """The downloaded recording (mono float), after checking its page still says CC0."""
    cached = CACHE / f"{sound_id}.flac"
    if not cached.exists():
        html = get(f"{SITE}/{page}").decode("utf8", "replace")
        if LICENCE_LINE not in html:
            raise SystemExit(f"{name}: {page} no longer says '{LICENCE_LINE}' - not using it")
        CACHE.mkdir(parents=True, exist_ok=True)
        cached.write_bytes(get(f"{SITE}/UPLOAD/flac/{sound_id}.flac"))
        time.sleep(1.5)
    x, sr = sf.read(io.BytesIO(cached.read_bytes()), always_2d=True)
    return x.mean(axis=1), sr


def tidy(x: np.ndarray, sr: int) -> np.ndarray:
    if sr != dsp.SR:
        g = gcd(sr, dsp.SR)
        x = signal.resample_poly(x, dsp.SR // g, sr // g)
    # Rumble out, ticks softened.
    x = dsp.filt(x, lambda f: dsp.hp(f, 180.0, 2) * dsp.lp(f, 8500.0, 4))
    # Trim to the song: from 0.1 s before it rises above -45 dB of its peak to 0.35 s after it falls.
    win = int(0.01 * dsp.SR)
    env = np.sqrt(np.convolve(x**2, np.ones(win) / win, mode="same"))
    live = np.nonzero(env > env.max() * 10 ** (-45 / 20))[0]
    a = max(0, live[0] - int(0.1 * dsp.SR))
    b = min(len(x), live[-1] + int(0.35 * dsp.SR))
    x = dsp.remove_dc(x[a:b])
    x = dsp.fade(x, 0.03, 0.3)
    return dsp.normalize_rms(x, TARGET_RMS_DB, PEAK_DB)


def main() -> None:
    for name, (page, sound_id) in CLIPS.items():
        x, sr = original(name, page, sound_id)
        y = tidy(x, sr)
        dsp.write_ogg(OUT / f"{name}.ogg", y, quality=0.5)
        print(f"{name}.ogg  {len(y) / dsp.SR:4.1f} s  from {SITE}/{page}")


if __name__ == "__main__":
    main()

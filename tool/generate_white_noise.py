#!/usr/bin/env python3
"""Generate distinct bundled focus sound assets.

The app needs real environmental loops, not nine copies of broadband noise.
This script synthesizes short, loopable MP3 tracks with different envelopes and
spectral shapes so the in-app choices sound meaningfully different.
"""

from __future__ import annotations

import math
import subprocess
import wave
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "assets" / "sounds" / "white_noise"
SAMPLE_RATE = 44_100
DURATION_SECONDS = 60
SAMPLES = SAMPLE_RATE * DURATION_SECONDS
T = np.arange(SAMPLES, dtype=np.float32) / SAMPLE_RATE


def _rng(seed: int) -> np.random.Generator:
    return np.random.default_rng(seed)


def _lowpass(signal: np.ndarray, alpha: float) -> np.ndarray:
    out = np.empty_like(signal, dtype=np.float32)
    value = np.float32(0.0)
    for i, sample in enumerate(signal):
        value = value + alpha * (sample - value)
        out[i] = value
    return out


def _highpass(signal: np.ndarray, alpha: float) -> np.ndarray:
    return signal - _lowpass(signal, alpha)


def _normalize(signal: np.ndarray, peak: float = 0.88) -> np.ndarray:
    signal = signal.astype(np.float32)
    signal = signal - float(np.mean(signal))
    max_abs = float(np.max(np.abs(signal)))
    if max_abs <= 1e-7:
        return signal
    return np.clip(signal / max_abs * peak, -0.98, 0.98).astype(np.float32)


def _fade_loop(signal: np.ndarray, fade_seconds: float = 2.0) -> np.ndarray:
    fade = int(SAMPLE_RATE * fade_seconds)
    if fade <= 0:
        return signal
    out = signal.copy()
    ramp = np.linspace(0.0, 1.0, fade, dtype=np.float32)
    out[:fade] *= ramp
    out[-fade:] *= ramp[::-1]
    return out


def _pulses(
    signal: np.ndarray,
    count: int,
    rng: np.random.Generator,
    *,
    freq_min: float,
    freq_max: float,
    amp_min: float,
    amp_max: float,
    dur_min: float,
    dur_max: float,
) -> None:
    for _ in range(count):
        start = int(rng.uniform(0, DURATION_SECONDS) * SAMPLE_RATE)
        dur = int(rng.uniform(dur_min, dur_max) * SAMPLE_RATE)
        end = min(SAMPLES, start + dur)
        if end <= start + 2:
            continue
        local_t = np.arange(end - start, dtype=np.float32) / SAMPLE_RATE
        freq = rng.uniform(freq_min, freq_max)
        amp = rng.uniform(amp_min, amp_max)
        envelope = np.hanning(end - start).astype(np.float32)
        signal[start:end] += amp * np.sin(2 * math.pi * freq * local_t) * envelope


def _droplets(
    signal: np.ndarray,
    count: int,
    rng: np.random.Generator,
    *,
    amp: float,
    dur_min: float = 0.012,
    dur_max: float = 0.055,
) -> None:
    for _ in range(count):
        start = int(rng.uniform(0, DURATION_SECONDS) * SAMPLE_RATE)
        dur = int(rng.uniform(dur_min, dur_max) * SAMPLE_RATE)
        end = min(SAMPLES, start + dur)
        if end <= start + 2:
            continue
        decay = np.exp(-np.linspace(0, 5.0, end - start, dtype=np.float32))
        click = rng.normal(0, 1, end - start).astype(np.float32)
        tone_t = np.arange(end - start, dtype=np.float32) / SAMPLE_RATE
        tone = np.sin(2 * math.pi * rng.uniform(1600, 5200) * tone_t).astype(
            np.float32
        )
        signal[start:end] += amp * (0.7 * click + 0.3 * tone) * decay


def rain(seed: int = 101) -> np.ndarray:
    rng = _rng(seed)
    hiss = _highpass(rng.normal(0, 0.23, SAMPLES).astype(np.float32), 0.012)
    mid = _lowpass(rng.normal(0, 0.13, SAMPLES).astype(np.float32), 0.035)
    signal = hiss + mid
    _droplets(signal, 1500, rng, amp=0.09)
    return _fade_loop(_normalize(signal, 0.84))


def night_rain(seed: int = 102) -> np.ndarray:
    rng = _rng(seed)
    base = _highpass(rng.normal(0, 0.16, SAMPLES).astype(np.float32), 0.009)
    rumble = _lowpass(rng.normal(0, 0.08, SAMPLES).astype(np.float32), 0.002)
    signal = base + rumble
    _droplets(signal, 750, rng, amp=0.065, dur_min=0.018, dur_max=0.07)
    distant_thunder = (
        np.sin(2 * math.pi * 33 * T) * (np.sin(2 * math.pi * 0.017 * T) + 1.0)
    ).astype(np.float32)
    signal += 0.02 * distant_thunder
    return _fade_loop(_normalize(signal, 0.72))


def waves(seed: int = 103) -> np.ndarray:
    rng = _rng(seed)
    surf = _lowpass(rng.normal(0, 0.32, SAMPLES).astype(np.float32), 0.018)
    wash = _highpass(rng.normal(0, 0.18, SAMPLES).astype(np.float32), 0.006)
    envelope = (
        0.48
        + 0.36 * (0.5 + 0.5 * np.sin(2 * math.pi * 0.075 * T - 0.8))
        + 0.16 * (0.5 + 0.5 * np.sin(2 * math.pi * 0.041 * T + 1.2))
    ).astype(np.float32)
    signal = surf * envelope + wash * np.maximum(envelope - 0.42, 0)
    _pulses(
        signal,
        35,
        rng,
        freq_min=95,
        freq_max=210,
        amp_min=0.025,
        amp_max=0.06,
        dur_min=0.45,
        dur_max=1.4,
    )
    return _fade_loop(_normalize(signal, 0.86))


def forest(seed: int = 104) -> np.ndarray:
    rng = _rng(seed)
    wind = _lowpass(rng.normal(0, 0.18, SAMPLES).astype(np.float32), 0.012)
    leaf = _highpass(rng.normal(0, 0.05, SAMPLES).astype(np.float32), 0.03)
    signal = wind + leaf
    for _ in range(130):
        start = int(rng.uniform(0, DURATION_SECONDS) * SAMPLE_RATE)
        dur = int(rng.uniform(0.09, 0.32) * SAMPLE_RATE)
        end = min(SAMPLES, start + dur)
        if end <= start + 2:
            continue
        local_t = np.arange(end - start, dtype=np.float32) / SAMPLE_RATE
        f0 = rng.uniform(1450, 3400)
        sweep = f0 + rng.uniform(-500, 700) * local_t
        phase = 2 * math.pi * np.cumsum(sweep) / SAMPLE_RATE
        envelope = np.hanning(end - start).astype(np.float32)
        signal[start:end] += rng.uniform(0.025, 0.07) * np.sin(phase) * envelope
    return _fade_loop(_normalize(signal, 0.76))


def cafe(seed: int = 105) -> np.ndarray:
    rng = _rng(seed)
    murmur = _lowpass(rng.normal(0, 0.24, SAMPLES).astype(np.float32), 0.025)
    room = _highpass(rng.normal(0, 0.06, SAMPLES).astype(np.float32), 0.003)
    signal = murmur + room
    _pulses(
        signal,
        150,
        rng,
        freq_min=320,
        freq_max=1200,
        amp_min=0.015,
        amp_max=0.05,
        dur_min=0.04,
        dur_max=0.2,
    )
    _droplets(signal, 160, rng, amp=0.045, dur_min=0.008, dur_max=0.03)
    return _fade_loop(_normalize(signal, 0.78))


def fan(seed: int = 106) -> np.ndarray:
    rng = _rng(seed)
    base = (
        0.42 * np.sin(2 * math.pi * 118 * T)
        + 0.18 * np.sin(2 * math.pi * 236 * T + 0.4)
        + 0.09 * np.sin(2 * math.pi * 354 * T + 1.1)
    ).astype(np.float32)
    air = _lowpass(rng.normal(0, 0.17, SAMPLES).astype(np.float32), 0.035)
    wobble = (0.88 + 0.12 * np.sin(2 * math.pi * 0.9 * T)).astype(np.float32)
    signal = base * wobble + air
    return _fade_loop(_normalize(signal, 0.74))


def deep_stream(seed: int = 107) -> np.ndarray:
    rng = _rng(seed)
    water = _lowpass(rng.normal(0, 0.32, SAMPLES).astype(np.float32), 0.028)
    sparkle = _highpass(rng.normal(0, 0.06, SAMPLES).astype(np.float32), 0.02)
    flow = (0.72 + 0.18 * np.sin(2 * math.pi * 0.21 * T)).astype(np.float32)
    signal = water * flow + sparkle
    _droplets(signal, 520, rng, amp=0.07, dur_min=0.02, dur_max=0.09)
    _pulses(
        signal,
        80,
        rng,
        freq_min=180,
        freq_max=440,
        amp_min=0.018,
        amp_max=0.052,
        dur_min=0.12,
        dur_max=0.45,
    )
    return _fade_loop(_normalize(signal, 0.82))


def pink_noise(seed: int = 108) -> np.ndarray:
    rng = _rng(seed)
    signal = rng.normal(0, 0.3, SAMPLES).astype(np.float32)
    for alpha in (0.004, 0.012, 0.04):
        signal += _lowpass(rng.normal(0, 0.18, SAMPLES).astype(np.float32), alpha)
    return _fade_loop(_normalize(signal, 0.68))


def brown_noise(seed: int = 109) -> np.ndarray:
    rng = _rng(seed)
    white = rng.normal(0, 0.045, SAMPLES).astype(np.float32)
    signal = np.cumsum(white).astype(np.float32)
    signal = _lowpass(signal, 0.02)
    signal += 0.05 * np.sin(2 * math.pi * 52 * T)
    return _fade_loop(_normalize(signal, 0.7))


TRACKS = {
    "rain": rain,
    "forest": forest,
    "cafe": cafe,
    "waves": waves,
    "brown_noise": brown_noise,
    "night_rain": night_rain,
    "fan": fan,
    "pink_noise": pink_noise,
    "deep_stream": deep_stream,
}


def write_wav(path: Path, signal: np.ndarray) -> None:
    pcm = (_normalize(signal, 0.9) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(pcm.tobytes())


def encode_mp3(wav_path: Path, mp3_path: Path) -> None:
    subprocess.run(
        [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-i",
            str(wav_path),
            "-codec:a",
            "libmp3lame",
            "-q:a",
            "4",
            "-ar",
            str(SAMPLE_RATE),
            "-ac",
            "1",
            str(mp3_path),
        ],
        check=True,
    )


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    tmp_dir = ROOT / "build" / "generated_white_noise"
    tmp_dir.mkdir(parents=True, exist_ok=True)

    for name, factory in TRACKS.items():
        wav = tmp_dir / f"{name}.wav"
        mp3 = OUT_DIR / f"{name}.mp3"
        write_wav(wav, factory())
        encode_mp3(wav, mp3)
        print(f"{name}: {mp3.stat().st_size} bytes")


if __name__ == "__main__":
    main()

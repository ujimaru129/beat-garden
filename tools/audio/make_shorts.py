#!/usr/bin/env python3
"""Cut a long song down to ~90 s: keep the intro, chop the middle, keep the song's real ending.

Songs can drift in tempo, so no single global grid is assumed. Beats are tracked with a dynamic
programming beat tracker, downbeats are estimated locally, and the splice is made between two
downbeats chosen for (a) similar sound before and after the join, (b) clear beats on both sides.
The ending is always the source's actual ending (no fade-out).

Usage: make_shorts.py <in.wav> <out_dir> [target_seconds=90] [bpm_hint] [back_skip_beats=0] [front_skip_beats=0] [sections]
('sections' = only splice at section changes, for songs whose phrases are not whole 4/4 bars)
(skip args nudge the automatic splice by whole beats: +back drops that many beats from the start of the
back part, -front shortens the front part; use multiples of 4 to stay on bar lines.)
Writes <out_dir>/<name>.short.wav and <out_dir>/<name>.short.json (beats of the result, join time).
Needs numpy and ffmpeg only.
"""
import json
import subprocess
import sys
from pathlib import Path

import numpy as np

SR = 22050
HOP = 128
NFFT = 1024
OUT_SR = 48000
FPS = SR / HOP
FRAME_CENTER_S = (NFFT / 2) / SR  # a spectrogram frame is centred half a window after its start


def decode(path: str, sr: int, channels: int) -> np.ndarray:
    raw = subprocess.run(
        ["ffmpeg", "-v", "quiet", "-i", path, "-ac", str(channels), "-ar", str(sr), "-f", "f32le", "-"],
        capture_output=True,
        check=True,
    ).stdout
    y = np.frombuffer(raw, dtype=np.float32)
    return y.reshape(-1, channels) if channels > 1 else y


def spectrogram(y: np.ndarray) -> np.ndarray:
    win = np.hanning(NFFT)
    n = (len(y) - NFFT) // HOP
    idx = np.arange(NFFT)[None, :] + HOP * np.arange(n)[:, None]
    return np.abs(np.fft.rfft(y[idx] * win, axis=1))


def onset_envelopes(spec: np.ndarray):
    """(full-band flux, low-band flux), normalised."""
    log = np.log1p(spec * 10)
    d = np.maximum(0, np.diff(log, axis=0))
    d = np.vstack([d[:1], d])
    freqs = np.fft.rfftfreq(NFFT, 1 / SR)
    norm = lambda x: (x - x.mean()) / (x.std() + 1e-9)
    return norm(d.sum(axis=1)), norm(d[:, freqs < 150].sum(axis=1))


def global_bpm(env: np.ndarray, hint: float | None) -> float:
    """Comb-filter search for the dominant tempo (used only as the tracker's centre period)."""
    cands = np.arange(hint - 8, hint + 8, 0.05) if hint else np.arange(80, 200, 0.1)
    best = (-1e9, 0.0)
    for bpm in cands:
        period = FPS * 60 / bpm
        sc = 0.0
        for ph in np.arange(0, period, period / 16):
            pos = ph + period * np.arange(int((len(env) - ph) / period))
            i = pos.astype(int)
            sc = max(sc, float(env[i[i < len(env)]].mean()))
        if sc > best[0]:
            best = (sc, bpm)
    return best[1]


def track_beats(env: np.ndarray, bpm: float, tightness: float = 100.0) -> np.ndarray:
    """Ellis-style dynamic programming beat tracker. Returns beat times in seconds."""
    period = FPS * 60 / bpm
    n = len(env)
    score = np.zeros(n)
    prev = -np.ones(n, dtype=int)
    for t in range(n):
        lo, hi = t - int(round(2 * period)), t - int(round(period / 2))
        if hi < 0:
            score[t] = env[t]
            continue
        idx = np.arange(max(lo, 0), hi + 1)
        pen = -tightness * np.log((t - idx) / period) ** 2
        cand = score[idx] + pen
        k = int(np.argmax(cand))
        score[t] = env[t] + cand[k]
        prev[t] = idx[k]
    t = int(np.argmax(score[-int(period) :])) + n - int(period)
    frames = []
    while t >= 0:
        frames.append(t)
        t = prev[t]
    frames = np.array(frames[::-1], dtype=float)
    return frames / FPS + FRAME_CENTER_S


def snap_latency(y: np.ndarray, beats: np.ndarray) -> float:
    """Median offset (s) between tracked beats and the sharpest nearby time-domain onset."""
    sm = int(0.002 * SR)
    e = np.convolve(np.abs(y), np.ones(sm) / sm, mode="same")
    d = np.maximum(0, np.diff(e, prepend=e[0]))
    offs = []
    for b in beats:
        a, z = int((b - 0.06) * SR), int((b + 0.06) * SR)
        if a < 0 or z >= len(d):
            continue
        seg = d[a:z]
        if seg.max() > 3 * (np.median(seg) + 1e-9):
            offs.append((a + int(np.argmax(seg))) / SR - b)
    return float(np.median(offs)) if len(offs) > 20 else 0.0


def band_vec(spec: np.ndarray, t0: float, t1: float) -> np.ndarray:
    freqs = np.fft.rfftfreq(NFFT, 1 / SR)
    edges = [0, 100, 200, 400, 800, 1600, 3200, 6400, 11025]
    a, z = max(0, int(t0 * FPS)), min(len(spec), int(t1 * FPS))
    seg = spec[a:z]
    if len(seg) == 0:
        return np.zeros(len(edges) - 1)
    return np.array(
        [np.log1p(seg[:, (freqs >= lo) & (freqs < hi)].mean() * 20) for lo, hi in zip(edges[:-1], edges[1:])]
    )


def main() -> None:
    src = sys.argv[1]
    out_dir = Path(sys.argv[2])
    target = float(sys.argv[3]) if len(sys.argv) > 3 else 90.0
    hint = float(sys.argv[4]) if len(sys.argv) > 4 and sys.argv[4] != "0" else None
    back_skip = int(sys.argv[5]) if len(sys.argv) > 5 else 0
    front_skip = int(sys.argv[6]) if len(sys.argv) > 6 else 0
    sections = len(sys.argv) > 7 and sys.argv[7] == "sections"
    out_dir.mkdir(parents=True, exist_ok=True)
    name = Path(src).stem

    y = decode(src, SR, 1)
    spec = spectrogram(y)
    full, low = onset_envelopes(spec)
    bpm = global_bpm(full, hint)
    beats = track_beats(full, bpm)
    beats = beats + snap_latency(y, beats)
    nb = len(beats)

    # beat clarity: mean onset strength at the beats around each beat (+-8 beats)
    def at(env: np.ndarray) -> np.ndarray:
        out = []
        for b in beats:
            c = int((b - FRAME_CENTER_S) * FPS)
            c = min(max(c, 6), len(env) - 7)
            out.append(env[c - 6 : c + 7].max())
        return np.array(out)

    full_b, low_b = at(full), at(low)
    k = np.ones(17) / 17
    support = np.convolve(full_b, k, mode="same")
    # local downbeat-ness: beats sharing index mod 4 with b, within +-16 beats, vs everyone else
    down = np.zeros(nb)
    for b in range(nb):
        win = np.arange(max(0, b - 16), min(nb, b + 17))
        same = win[(win - b) % 4 == 0]
        down[b] = low_b[same].mean() - low_b[win].mean()

    total = len(y) / SR
    # Section changes: where the sound 8 beats after differs most from the 8 beats before.
    V = np.array([band_vec(spec, beats[b], beats[min(b + 1, nb - 1)]) for b in range(nb)])
    W = 8
    nov = np.zeros(nb)
    for b in range(W, nb - W):
        nov[b] = np.abs(V[b : b + W].mean(0) - V[b - W : b].mean(0)).sum()
    is_section = np.zeros(nb, dtype=bool)
    thr = np.percentile(nov[W : nb - W], 60 if sections else 75)
    for b in range(W, nb - W):
        if nov[b] >= thr and nov[b] == nov[max(0, b - 3) : b + 4].max():
            is_section[b] = True
    best = None
    for i in range(nb):
        t_i = beats[i]
        if t_i < target * 0.25 or t_i > target * 0.7 or i < 8 or (sections and not is_section[i]) or (not sections and down[i] <= 0):
            continue
        for j in range(i + 8, nb - 8):
            dur = t_i + (total - beats[j])
            if abs(dur - target) > (8 if sections else 4) or (sections and not is_section[j]) or (not sections and down[j] <= 0):
                continue
            bar_i, bar_j = 4 * 60 / bpm, 4 * 60 / bpm
            before = np.abs(band_vec(spec, beats[i - 4], beats[i]) - band_vec(spec, beats[j - 4], beats[j])).sum()
            after = np.abs(band_vec(spec, beats[i], beats[min(nb - 1, i + 4)]) - band_vec(spec, beats[j], beats[min(nb - 1, j + 4)])).sum()
            cost = before + after - 0.4 * (support[i] + support[j]) + 0.05 * abs(dur - target)
            cost += -0.6 * (down[i] + down[j]) if not sections else -0.5 * (nov[i] + nov[j])
            if best is None or cost < best[0]:
                best = (cost, i, j)
    assert best, "no splice found"
    _, i, j = best
    j += back_skip
    i -= front_skip

    stereo = decode(src, OUT_SR, 2)
    sr = OUT_SR
    beat_len = float(np.median(np.diff(beats[max(0, i - 8) : i + 1])))
    ov = int(beat_len * 0.5 * sr)  # equal-power crossfade; the back part's downbeat lands exactly on the join
    a_end, b_start = int(beats[i] * sr), int(beats[j] * sr)
    head = stereo[:a_end].copy()
    tail = stereo[b_start - ov :]
    t = np.linspace(0, np.pi / 2, ov)[:, None]
    head[-ov:] = head[-ov:] * np.cos(t) + tail[:ov] * np.sin(t)
    out = np.vstack([head, tail[ov:]])
    # The ending is the song's real ending, untouched (no fade-out). Only the very start gets 10 ms.
    fi = int(0.01 * sr)
    out[:fi] *= np.linspace(0, 1, fi)[:, None]
    out *= 10 ** (-1 / 20) / max(1e-6, float(np.abs(out).max()))

    wav = out_dir / f"{name}.short.wav"
    pcm = (np.clip(out, -1, 1) * 32767).astype("<i2")
    subprocess.run(
        ["ffmpeg", "-v", "quiet", "-y", "-f", "s16le", "-ar", str(sr), "-ac", "2", "-i", "-", str(wav)],
        input=pcm.tobytes(),
        check=True,
    )

    join_s = float(beats[i])
    out_beats = [b for b in beats[:i]] + [join_s + (b - beats[j]) for b in beats[j:]]
    out_down = [bool(d > 0) for d in down[:i]] + [bool(d > 0) for d in down[j:]]
    info = {
        "source": Path(src).name,
        "bpm": round(bpm, 2),
        "durationSeconds": round(len(out) / sr, 2),
        "sourceSeconds": round(total, 2),
        "joinSeconds": round(join_s, 3),
        "joinFromSourceSeconds": round(float(beats[j]), 3),
        "joinCost": round(best[0], 2),
        "downbeatAtJoin": [round(float(down[i]), 2), round(float(down[j]), 2)],
        "sectionBoundaries": [round(float(beats[b]), 2) for b in np.where(is_section)[0]],
        "beatSupportAtJoin": [round(float(support[i]), 2), round(float(support[j]), 2)],
        "beatsMs": [round(b * 1000, 1) for b in out_beats],
        "downbeat": out_down,
    }
    (out_dir / f"{name}.short.json").write_text(json.dumps(info))
    summary = {k: v for k, v in info.items() if k not in ("beatsMs", "downbeat")}
    print(json.dumps(summary))


if __name__ == "__main__":
    main()

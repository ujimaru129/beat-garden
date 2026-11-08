#!/usr/bin/env python3
"""Generate Easy / Normal / Hard tend charts for a short song and write a Luau data module.

Input : audio/shorts/<name>.short.wav and .short.json (from make_shorts.py: beat times of the result)
Output: src/shared/Songs/Data/<SongId>.luau  (segments with the same start/end for all difficulties)

Method
  1. Onsets: spectral flux peaks, each refined to the steepest rise of the waveform.
  2. Segments: ~32 beats (about 13 s) windows starting on a beat, picked by energy and note richness,
     not crossing the splice point of the short edit.
  3. Per difficulty: score each onset (strength + position on the beat grid), keep the best ones with
     a minimum gap and a target density.
  4. Lanes: from the onset's spectral centroid (low -> lane 0 ... high -> lane 3), then smoothed so that
     the same lane is not hammered and jumps across all four lanes do not happen at speed.

Usage: make_charts.py <short.wav> <songId> <displayName> [segments=full]
  segments = "full" (default): one chart over the whole short edit; or a number: that many ~13 s segments.
Needs numpy only (+ ffmpeg through make_shorts.decode).
"""
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
import make_shorts as m  # noqa: E402

SEG_BEATS = 32
# Creator Hub asset ids of the uploaded short edits (keep in sync when a song is re-uploaded)
ASSET_IDS = {
    "kabuki_dance": "102174208355987",
    "dard_aur_dhamaka": "76576411777923",
    "pastel_trip": "86433689428068",
    "kamikaze": "131155520574193",
}
# notes per second to aim for, minimum gap in beats, and which grid positions are allowed
DIFFICULTY = {
    "Easy": {"density": 1.6, "min_gap_beats": 0.9, "min_gap_ms": 380, "grid": {"beat": 1.0}},
    "Normal": {"density": 3.4, "min_gap_beats": 0.45, "min_gap_ms": 190, "grid": {"beat": 1.0, "eighth": 0.8}},
    "Hard": {"density": 6.0, "min_gap_beats": 0.22, "min_gap_ms": 105, "grid": {"beat": 1.0, "eighth": 0.8, "sixteenth": 0.55, "off": 0.15}},
}


def luau_name(song_id: str) -> str:
    return "".join(p.capitalize() for p in song_id.split("_"))


def detect_onsets(y: np.ndarray):
    spec = m.spectrogram(y)
    full, low = m.onset_envelopes(spec)
    log = np.log1p(spec * 10)
    d = np.maximum(0, np.diff(log, axis=0))
    d = np.vstack([d[:1], d])
    freqs = np.fft.rfftfreq(m.NFFT, 1 / m.SR)

    # time-domain onset curve for refining
    sm = int(0.003 * m.SR)
    e = np.convolve(np.abs(y), np.ones(sm) / sm, mode="same")
    de = np.maximum(0, np.diff(e, prepend=e[0]))

    onsets = []
    n = len(full)
    for i in range(3, n - 3):
        if full[i] < 0.9 or full[i] < full[i - 3 : i + 4].max():
            continue
        tc = i / m.FPS + m.FRAME_CENTER_S
        a, z = int((tc - 0.030) * m.SR), int((tc + 0.040) * m.SR)
        seg = de[a:z]
        ref = tc + 0.008
        if len(seg) and seg.max() > 3 * (np.median(de[max(0, a - m.SR // 5) : z + m.SR // 5]) + 1e-9):
            ref = (a + int(np.argmax(seg))) / m.SR
        w = d[i]
        centroid = float((np.log2(np.maximum(freqs, 30)) * w).sum() / (w.sum() + 1e-9))
        onsets.append({"t": ref, "strength": float(full[i]), "centroid": centroid, "low": float(low[i])})
    return onsets, spec


def grid_class(t: float, beats: np.ndarray) -> str:
    k = int(np.searchsorted(beats, t, side="right") - 1)
    if k < 0 or k >= len(beats) - 1:
        return "off"
    f = (t - beats[k]) / (beats[k + 1] - beats[k])
    for name, center in (("beat", 0.0), ("beat", 1.0), ("eighth", 0.5), ("sixteenth", 0.25), ("sixteenth", 0.75)):
        if abs(f - center) < 0.11:
            return name
    return "off"


def pick_segments(y: np.ndarray, beats: np.ndarray, join_s: float, count: int, onsets) -> list:
    rms_t = lambda a, b: float(np.sqrt((y[int(a * m.SR) : int(b * m.SR)] ** 2).mean()))
    times = np.array([o["t"] for o in onsets])
    cands = []
    for k in range(0, len(beats) - SEG_BEATS - 1, 2):
        a, b = float(beats[k]), float(beats[k + SEG_BEATS])
        if a < 1.0 or b > len(y) / m.SR - 0.5 or not (b - a >= 10 and b - a <= 15):
            continue
        if a + 0.3 < join_s < b - 0.3:  # keep the splice out of the middle of a segment
            continue
        inside = ((times >= a) & (times < b)).sum()
        cands.append((rms_t(a, b) * 6 + inside / (b - a) * 0.15, k, a, b))
    cands.sort(reverse=True)
    chosen = []
    for score, k, a, b in cands:
        if all(b <= c[2] - 0.2 or a >= c[3] + 0.2 for c in chosen):
            chosen.append((score, k, a, b))
        if len(chosen) == count:
            break
    chosen.sort(key=lambda c: c[2])
    return chosen


def select_onsets(onsets, beats, a: float, b: float, cfg: dict):
    beat_len = float(np.median(np.diff(beats[(beats >= a) & (beats <= b)])))
    gap = max(cfg["min_gap_ms"] / 1000, cfg["min_gap_beats"] * beat_len)
    # Density is spread in chunks of 8 beats so quiet passages stay quiet and busy ones do not eat the budget.
    inside = beats[(beats > a) & (beats < b)]
    edges = [a] + [float(t) for t in inside[::8]] + [b]
    edges = sorted(set(edges))
    taken: list = []
    for c0, c1 in zip(edges[:-1], edges[1:]):
        if c1 - c0 < 0.5:
            continue
        pool = []
        for o in onsets:
            if not (c0 <= o["t"] < c1):
                continue
            cls = grid_class(o["t"], beats)
            if cls not in cfg["grid"]:
                continue
            score = 0.6 * o["strength"] + 2.0 * cfg["grid"][cls] + (0.4 if o["low"] > 1.2 and cls == "beat" else 0.0)
            pool.append((score, o))
        pool.sort(key=lambda p: -p[0])
        want = int(round(cfg["density"] * (c1 - c0)))
        got = 0
        for score, o in pool:
            if got >= want:
                break
            if all(abs(o["t"] - t["t"]) >= gap for t in taken):
                taken.append(o)
                got += 1
    taken.sort(key=lambda o: o["t"])
    return taken


def assign_lanes(taken, lane_edges):
    notes = []
    prev_lane, run = -1, 0
    prev_t = -10.0
    for o in taken:
        lane = int(np.searchsorted(lane_edges, o["centroid"]))
        lane = min(3, max(0, lane))
        dt = o["t"] - prev_t
        if lane == prev_lane and dt < 0.4 and run >= 2:
            lane = lane + 1 if lane < 3 and (len(notes) % 2 == 0) else lane - 1 if lane > 0 else lane + 1
        if prev_lane >= 0 and abs(lane - prev_lane) > 2 and dt < 0.22:
            lane = prev_lane + (1 if lane > prev_lane else -1)
        run = run + 1 if lane == prev_lane else 1
        notes.append([lane, int(round(o["t"] * 1000))])
        prev_lane, prev_t = lane, o["t"]
    return notes


def main() -> None:
    wav = sys.argv[1]
    song_id = sys.argv[2]
    display = sys.argv[3]
    seg_arg = sys.argv[4] if len(sys.argv) > 4 else "full"
    info = json.loads(Path(wav).with_suffix(".json").read_text())
    beats = np.array(info["beatsMs"]) / 1000
    y = m.decode(wav, m.SR, 1)
    onsets, _ = detect_onsets(y)

    if seg_arg == "full":
        segs = [(0.0, 0, 0.0, len(y) / m.SR)]
    else:
        segs = pick_segments(y, beats, float(info["joinSeconds"]), int(seg_arg), onsets)
    out_segments = []
    picked = {name: [select_onsets(onsets, beats, a, b, cfg) for (_, _, a, b) in segs] for name, cfg in DIFFICULTY.items()}
    # lane thresholds from the notes actually chosen, so all four lanes are used about equally
    edges = {
        name: np.percentile([o["centroid"] for seg in picked[name] for o in seg], [25, 50, 75]) for name in DIFFICULTY
    }
    for idx, (score, k, a, b) in enumerate(segs):
        entry = {"id": idx, "startMs": int(round(a * 1000)), "endMs": int(round(b * 1000)), "anchorMs": int(round(beats[k] * 1000))}
        for name in DIFFICULTY:
            entry[name] = assign_lanes(picked[name][idx], edges[name])
        out_segments.append(entry)

    root = Path(__file__).resolve().parents[2]
    out = root / "src/shared/Songs/Data" / f"{luau_name(song_id)}.luau"
    out.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "--!strict",
        f"-- GENERATED by tools/audio/make_charts.py from {Path(wav).name}. Do not edit by hand; rerun the script.",
        "-- Times are ms from the start of the short edit (the file uploaded to Roblox). Notes are { lane (0-3), ms }.",
        "return {",
        f'\tsongId = "{song_id}",',
        f'\tname = "{display}",',
        f"\tbpm = {info['bpm']},",
        "\toffsetMs = 0, -- shift all notes if the uploaded audio plays early/late",
        f"\taudioAssetId = {json.dumps(ASSET_IDS.get(song_id))} :: string?, -- Creator Hub asset id of the uploaded short edit"
        if song_id in ASSET_IDS
        else "\taudioAssetId = nil :: string?, -- Creator Hub asset id once the short edit is uploaded",
        f"\tdurationMs = {int(round(info['durationSeconds'] * 1000))},",
        "\tbeatsMs = { " + ", ".join(str(int(round(b * 1000))) for b in beats) + " }, -- tracked beats, for the metronome",
        "\tsegments = {",
    ]
    for s in out_segments:
        lines.append("\t\t{")
        lines.append(f"\t\t\tid = {s['id']}, startMs = {s['startMs']}, endMs = {s['endMs']},")
        for name in DIFFICULTY:
            body = ", ".join(f"{{ {l}, {t} }}" for l, t in s[name])
            lines.append(f"\t\t\t{name} = {{ {body} }},")
        lines.append("\t\t},")
    lines += ["\t},", "}", ""]
    out.write_text("\n".join(lines))

    rep = {"song": song_id, "totalNotes": {n: sum(len(s[n]) for s in out_segments) for n in DIFFICULTY}, "file": str(out.relative_to(root)), "segments": []}
    for s in out_segments:
        dur = (s["endMs"] - s["startMs"]) / 1000
        rep["segments"].append(
            {"id": s["id"], "start": round(s["startMs"] / 1000, 1), "sec": round(dur, 1)}
            | {n: f"{len(s[n])} ({len(s[n]) / dur:.1f}/s)" for n in DIFFICULTY}
        )
    print(json.dumps(rep, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()

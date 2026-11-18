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
# Per-song shift of all notes in ms (negative = earlier), found by playing: the audio and the chart can disagree a little
GENRES = {
    "kabuki_dance": "Japan",
    "dard_aur_dhamaka": "Dance",
    "pastel_trip": "Pop",
    "kamikaze": "Rock",
    "gorilla_glue": "Rock",
    "fly_me_to_the_saitama": "Dance",
    "metropolitan_expressway": "Dance",
    "naniwa_march": "Japan",
    "orange_beach": "Pop",
    "blue_samurai": "Japan",
    "shinjuku_deep_romance": "Pop",
    "yokohama_stars": "Pop",
    "popping_popping": "Dance",
    "good_morning_harajuku": "Pop",
    "feels_so_good": "Pop",
}
# Songs cut short (ms): the audio after this is not played and no note is placed in it.
CUT_MS = {"kamikaze": 88000}
OFFSETS_MS = {"pastel_trip": -25, "naniwa_march": -40}
# The beat tracker sometimes locks onto the off-beat. A fraction of a beat to move the tracked beats later, found by
# looking at where the kick drum lands in the grid (0.5 = the kick sits half a beat after the tracked beat).
BEAT_PHASE = {"blue_samurai": 0.53, "naniwa_march": 0.45}
ASSET_IDS = {
    "kabuki_dance": "102174208355987",
    "dard_aur_dhamaka": "76576411777923",
    "pastel_trip": "86433689428068",
    "kamikaze": "76496375818884",
    "gorilla_glue": "115753003413703",
    "fly_me_to_the_saitama": "127786101931228",
    "metropolitan_expressway": "81016210615436",
    "naniwa_march": "117617671462568",
    "orange_beach": "109616336017148",
    "blue_samurai": "113086931885012",
    "shinjuku_deep_romance": "77158663817198",
    "yokohama_stars": "75908588261257",
    "popping_popping": "106085832352727",
    "good_morning_harajuku": "115077507225615",
    "feels_so_good": "119223540667928",
}
# Per difficulty: notes per beat to aim for (so the same fraction of the beats at any tempo), the minimum gap, which grid positions are allowed, and how far the
# lane may jump between two close notes (a phone has no room for wide jumps at speed).
#   Notes between the beats (the "off-beat", 8ths) are only used on slow songs: at 120+ BPM they are too fast to
#   hit on a phone, and Hard is meant to be playable, so it follows the beat (and the melody on it) there.
#   "eighth_min_beat_ms": the 8ths are allowed only if one beat is at least this long (about 111 BPM or slower).
DIFFICULTY = {
    "Easy": {"per_beat": 0.65, "min_gap_beats": 0.9, "min_gap_ms": 380, "grid": {"beat": 1.0}, "max_jump": 3},
    "Normal": {
        "per_beat": 1.3,
        "min_gap_beats": 0.45,
        "min_gap_ms": 200,
        "grid": {"beat": 1.0, "eighth": 0.5},
        "grid_tol": 0.16,
        "burst_cooldown_beats": 1.5,
        "burst_max_run": 2,
        "max_jump": 2,
    },
    "Hard": {
        "per_beat": 2.4,
        "min_gap_beats": 0.36,
        "min_gap_ms": 140,
        "grid": {"beat": 1.0, "eighth": 0.6, "sixteenth": 0.35},
        "grid_tol": 0.16,
        # quick notes (about 200 ms apart) come in bursts of at most six notes, then a short rest
        "burst_cooldown_beats": 0.4,
        "burst_max_run": 5,
        "max_jump": 2,
    },
    # For rhythm-game players: built on the beat grid. Most notes sit on the beat, the 8ths add the off-beat only as a
    # minority (at most `max_offbeat_ratio` of all notes) and the 16ths only a little; notes off the grid are never used.
    "Expert": {
        "per_beat": 3.2,
        "min_gap_beats": 0.22,
        "min_gap_ms": 110,
        "grid": {"beat": 1.0, "eighth": 0.5, "sixteenth": 0.3},
        "grid_tol": 0.13,
        "max_offbeat_ratio": 0.5,
        "burst_cooldown_beats": 0.4,
        "burst_max_run": 6,
        "max_jump": 3,
        # two-finger hits: on strong beats that stand alone, a second note in the next lane at the same time
        "chord_ratio": 0.09,
        "chord_isolation_ms": 280,
    },
}


# Per-song changes to the settings above, found by playing: a very fast song needs a lighter chart.
OVERRIDES = {
    "kamikaze": {
        # fast and busy, and many hits between the beats: keep to the beat, with only some of the others
        "Normal": {"grid": {"beat": 1.0, "eighth": 0.3}, "grid_tol": 0.14, "per_beat": 1.5, "max_offbeat_ratio": 0.3},
        "Hard": {"grid": {"beat": 1.0, "eighth": 0.5, "sixteenth": 0.2}, "grid_tol": 0.14, "per_beat": 2.3, "max_offbeat_ratio": 0.4},
    },
    "pastel_trip": {
        # slow (about 100 BPM) with a lot going on in the 8ths and 16ths: Expert can take more of them
        "Hard": {"min_gap_beats": 0.26, "per_beat": 2.7, "grid_tol": 0.18},
        "Expert": {"per_beat": 4.0, "grid": {"beat": 1.0, "eighth": 0.6, "sixteenth": 0.5}, "grid_tol": 0.15, "max_offbeat_ratio": 0.6, "min_gap_ms": 100},
    },
    "orange_beach": {"Hard": {"min_gap_beats": 0.28, "per_beat": 2.7, "grid_tol": 0.18}},
    "shinjuku_deep_romance": {"Hard": {"min_gap_beats": 0.28, "per_beat": 2.7, "grid_tol": 0.18}},
    "blue_samurai": {
        "Hard": {"per_beat": 1.8, "burst_max_run": 3, "burst_cooldown_beats": 0.9, "min_gap_ms": 160},
    },
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


def grid_class(t: float, beats: np.ndarray, tol: float = 0.11) -> str:
    k = int(np.searchsorted(beats, t, side="right") - 1)
    if k < 0 or k >= len(beats) - 1:
        return "off"
    f = (t - beats[k]) / (beats[k + 1] - beats[k])
    for name, center in (("beat", 0.0), ("beat", 1.0), ("eighth", 0.5), ("sixteenth", 0.25), ("sixteenth", 0.75)):
        if abs(f - center) < tol:
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
    grid = dict(cfg["grid"])
    min_gap_beats = cfg["min_gap_beats"]
    per_beat = cfg["per_beat"]
    gap = max(cfg["min_gap_ms"] / 1000, min_gap_beats * beat_len)
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
            cls = grid_class(o["t"], beats, cfg.get("grid_tol", 0.11))
            if cls not in grid:
                continue
            score = 0.6 * o["strength"] + 2.0 * grid[cls] + (0.4 if o["low"] > 1.2 and cls == "beat" else 0.0)
            pool.append((score, o))
        pool.sort(key=lambda p: -p[0])
        want = int(round(per_beat * (c1 - c0) / beat_len))
        got = 0
        for score, o in pool:
            if got >= want:
                break
            if all(abs(o["t"] - t["t"]) >= gap for t in taken):
                taken.append(o)
                got += 1
    taken.sort(key=lambda o: o["t"])
    # Songs that hit a lot between the beats: keep the notes on the beat, and only as many of the others as this share
    # of all notes (the strongest ones).
    ratio = cfg.get("max_offbeat_ratio")
    if ratio is not None:
        tol = cfg.get("grid_tol", 0.11)
        on = [o for o in taken if grid_class(o["t"], beats, tol) == "beat"]
        off = [o for o in taken if grid_class(o["t"], beats, tol) != "beat"]
        room = int(len(on) * ratio / (1 - ratio))
        off.sort(key=lambda o: -o["strength"])
        taken = sorted(on + off[:room], key=lambda o: o["t"])
    cooldown = cfg.get("burst_cooldown_beats")
    if cooldown:
        # Quick notes (closer than 0.6 beat) come in short bursts: at most `burst_max_run` quick gaps in a row, then
        # a rest of `cooldown` beats before the next burst.
        quick = 0.6 * beat_len
        max_run = cfg.get("burst_max_run", 1)
        kept: list = []
        run = 0
        rest_until = -1e9
        for o in taken:
            if kept and o["t"] - kept[-1]["t"] < quick:
                if o["t"] < rest_until or run >= max_run:
                    continue
                run += 1
                if run >= max_run:
                    rest_until = o["t"] + cooldown * beat_len
            else:
                run = 0
            kept.append(o)
        taken = kept
    return taken


def assign_lanes(taken, lane_edges, max_jump: int = 3):
    notes = []
    prev_lane, run = -1, 0
    prev_t = -10.0
    for o in taken:
        lane = int(np.searchsorted(lane_edges, o["centroid"]))
        lane = min(3, max(0, lane))
        dt = o["t"] - prev_t
        if lane == prev_lane and dt < 0.4 and run >= 2:
            lane = lane + 1 if lane < 3 and (len(notes) % 2 == 0) else lane - 1 if lane > 0 else lane + 1
        if prev_lane >= 0 and abs(lane - prev_lane) > max_jump and dt < 0.5:
            lane = prev_lane + max_jump * (1 if lane > prev_lane else -1)
        elif prev_lane >= 0 and abs(lane - prev_lane) > 2 and dt < 0.22:
            lane = prev_lane + (1 if lane > prev_lane else -1)
        run = run + 1 if lane == prev_lane else 1
        notes.append([lane, int(round(o["t"] * 1000))])
        prev_lane, prev_t = lane, o["t"]
    return notes


def add_chords(notes, taken, beats, cfg):
    """Adds a second note at the same time, in a lane next to the first, to some strong beat notes that stand alone
    (no other note within `chord_isolation_ms` before or after it). At most `chord_ratio` of the notes get a partner,
    never two chords in a row. Two adjacent lanes are always reachable with two fingers on a phone."""
    iso = cfg["chord_isolation_ms"]
    cands = []
    for i, (lane, ms) in enumerate(notes):
        gap_prev = ms - notes[i - 1][1] if i > 0 else 9999
        gap_next = notes[i + 1][1] - ms if i + 1 < len(notes) else 9999
        if min(gap_prev, gap_next) < iso:
            continue
        if grid_class(taken[i]["t"], beats, cfg.get("grid_tol", 0.11)) != "beat":
            continue
        cands.append((taken[i]["strength"], i))
    cands.sort(reverse=True)
    want = int(len(notes) * cfg["chord_ratio"])
    chosen: list = []
    for _, i in cands:
        if len(chosen) >= want:
            break
        if all(abs(i - j) > 4 for j in chosen):  # keep chords apart
            chosen.append(i)
    extra = []
    for n, i in enumerate(sorted(chosen)):
        lane, ms = notes[i]
        partner = lane + 1 if lane < 3 and (lane == 0 or n % 2 == 0) else lane - 1
        extra.append([partner, ms])
    return sorted(notes + extra, key=lambda n: (n[1], n[0]))


def main() -> None:
    wav = sys.argv[1]
    song_id = sys.argv[2]
    display = sys.argv[3]
    seg_arg = sys.argv[4] if len(sys.argv) > 4 else "full"
    info = json.loads(Path(wav).with_suffix(".json").read_text())
    beats = np.array(info["beatsMs"]) / 1000
    y = m.decode(wav, m.SR, 1)
    phase = BEAT_PHASE.get(song_id, 0.0)
    if phase:
        step = np.diff(beats, append=beats[-1] + float(np.median(np.diff(beats))))
        beats = beats + phase * step
        beats = beats[beats < len(y) / m.SR - 0.05]
    onsets, _ = detect_onsets(y)

    cut_ms = CUT_MS.get(song_id)
    if seg_arg == "full":
        segs = [(0.0, 0, 0.0, (cut_ms / 1000 if cut_ms else len(y) / m.SR))]
    else:
        segs = pick_segments(y, beats, float(info["joinSeconds"]), int(seg_arg), onsets)
    out_segments = []
    def config_for(name: str) -> dict:
        return {**DIFFICULTY[name], **OVERRIDES.get(song_id, {}).get(name, {})}

    picked = {name: [select_onsets(onsets, beats, a, b, config_for(name)) for (_, _, a, b) in segs] for name in DIFFICULTY}
    # A note must have sound under it: drop notes that fall in a silence (a break, the tail after the last hit).
    quiet_level = 0.08 * float(np.sqrt((y**2).mean()))

    def audible(t: float) -> bool:
        seg = y[max(0, int((t - 0.02) * m.SR)) : int((t + 0.12) * m.SR)]
        return len(seg) > 0 and float(np.sqrt((seg**2).mean())) >= quiet_level

    picked = {name: [[o for o in seg if audible(o["t"])] for seg in lst] for name, lst in picked.items()}
    if cut_ms:
        picked = {name: [[o for o in seg if o["t"] * 1000 <= cut_ms - 60] for seg in lst] for name, lst in picked.items()}
    # lane thresholds from the notes actually chosen, so all four lanes are used about equally
    edges = {
        name: np.percentile([o["centroid"] for seg in picked[name] for o in seg], [25, 50, 75]) for name in DIFFICULTY
    }
    for idx, (score, k, a, b) in enumerate(segs):
        entry = {"id": idx, "startMs": int(round(a * 1000)), "endMs": int(round(b * 1000)), "anchorMs": int(round(beats[k] * 1000))}
        for name in DIFFICULTY:
            entry[name] = assign_lanes(picked[name][idx], edges[name], DIFFICULTY[name]["max_jump"])
            if "chord_ratio" in DIFFICULTY[name]:
                entry[name] = add_chords(entry[name], picked[name][idx], beats, config_for(name))
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
        f'\tgenre = "{GENRES.get(song_id, "Pop")}",',
        f"\tbpm = {info['bpm']},",
        f"\toffsetMs = {OFFSETS_MS.get(song_id, 0)}, -- shift all notes if the uploaded audio plays early/late (negative = earlier)",
        f"\taudioAssetId = {json.dumps(ASSET_IDS.get(song_id))} :: string?, -- Creator Hub asset id of the uploaded short edit"
        if song_id in ASSET_IDS
        else "\taudioAssetId = nil :: string?, -- Creator Hub asset id once the short edit is uploaded",
        f"\tdurationMs = {cut_ms or int(round(info['durationSeconds'] * 1000))},",
        *([f"\taudioEndMs = {cut_ms} :: number?, -- the song is cut here"] if cut_ms else []),
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

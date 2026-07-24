#!/usr/bin/env python3
"""Turns one game-night session into ranked clip candidates for a VOD.

    ./clipper.py resources/[local]/telemetry/data-20260724-201501.jsonl \
        --transcript ../../transcripts/session-20260724.jsonl \
        --rec-start 2026-07-24T20:14:03+00:00 \
        --video game-night.mkv \
        --out out/

Earshot writes down what everyone *said*; this reads what the game *recorded*.
Telemetry already stamps the good bits - /tmark notes people flagged by hand,
scripted set-pieces the moments director fired, wave clears, chase endings - so
the job here is to line those stamps up against a local OBS recording and hand
you a rank-ordered cut list.

The one number that ties it together is --rec-start: the wall-clock (epoch)
moment OBS started recording. Every telemetry `t` is epoch seconds too, so a
video offset is just `t - rec_start`. Get that one right and everything lands
on the frame; get it wrong and every clip is off by the same amount.

Kept deliberately dependency-light: stdlib only. The only runtime dep is
ffmpeg, and that's just to *run* the cut.sh this emits, not to build it.
"""
import argparse
import csv
import json
import sys
from datetime import datetime, timezone
from pathlib import Path


# ===== config =====
# Config-first, same as the game resources: every lever lives here, the logic
# below reads them and hardcodes nothing. CLI flags override a handful of these
# per-run; the rest you tune by editing this block.
CONFIG = {
    # Padding stitched onto every candidate so a clip opens on the run-up and
    # closes on the reaction, not dead on the trigger frame.
    "lead_in_seconds": 6.0,
    "tail_seconds":    8.0,

    # Base score by signal. A hand-flagged /tmark is the crew shouting "clip
    # THAT", so it wins outright; then a burst of voice (laughter); then the
    # auto game-events, which are plentiful and need a human eye.
    "score_note":     100.0,
    "score_laughter":  55.0,
    "score_event":     35.0,  # default for a game-event with no override below

    # Some set-pieces clip better than a routine wave. Keyed by the bit before
    # the ':' in a telemetry mark (moment:planecrash -> "moment").
    "event_kind_scores": {
        "chase":        50.0,  # a whole round ending - nicked, crashed, clean away
        "moment":       45.0,  # a scripted disaster went off near someone
        "brute-wave":   42.0,  # the every-fifth boss cadence
        "wave-cleared": 30.0,  # routine, but a clean last-second clear can be gold
    },

    # Laughter = a burst of voice. A window counts as a reaction when enough
    # different people talk over each other, OR enough utterances pile up close
    # together. Either is the room reacting to something.
    "laughter_gap_seconds":    8.0,  # utterances closer than this cluster together
    "laughter_min_speakers":   2,    # this many distinct voices overlapping...
    "laughter_min_utterances": 3,    # ...or this many utterances in the burst
    "laughter_speaker_bonus":  8.0,  # per extra voice over the minimum
    "laughter_utterance_bonus": 3.0, # per extra utterance over the minimum

    # A voice burst landing on top of another candidate is the crew reacting to
    # THAT thing - so merge them and reward it, rather than cutting a separate
    # clip of people laughing at nothing on screen.
    "reaction_boost": 25.0,

    # Candidates whose padded windows sit within this gap are one moment.
    "merge_gap_seconds": 3.0,

    # How much transcript to hang on a candidate as a caption/label hint.
    "caption_max_chars": 120,
}

# The three signal names, fixed so clips.csv stays greppable.
SRC_NOTE = "tmark"
SRC_LAUGH = "laughter"
SRC_EVENT = "game-event"


def to_epoch(value: str) -> float:
    """A --rec-start or transcript timestamp, epoch-or-ISO8601, to epoch secs."""
    value = value.strip()
    if value.replace(".", "", 1).isdigit():
        num = float(value)
        return num / 1000 if num > 1e12 else num  # tolerate milliseconds
    # datetime.fromisoformat handles 'Z' from 3.11; be kind to older Pythons.
    iso = value.replace("Z", "+00:00")
    dt = datetime.fromisoformat(iso)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.timestamp()


def hms(seconds: float) -> str:
    """Seconds -> a YouTube-style stamp: 0:00, 12:34, 1:02:03."""
    total = max(0, int(round(seconds)))
    hours, rem = divmod(total, 3600)
    mins, secs = divmod(rem, 60)
    if hours:
        return f"{hours}:{mins:02d}:{secs:02d}"
    return f"{mins}:{secs:02d}"


def slug(text: str, length: int = 28) -> str:
    """A filesystem-safe stub of a label for clip filenames."""
    keep = [c.lower() if c.isalnum() else "-" for c in text]
    out = "".join(keep).strip("-")
    while "--" in out:
        out = out.replace("--", "-")
    return (out[:length].strip("-")) or "clip"


def humanise(mark: str) -> str:
    """A telemetry mark -> a chapter title a viewer will understand."""
    kind, _, rest = mark.partition(":")
    if kind == "moment":
        return f"Set-piece: {rest.replace('_', ' ')}"
    if kind == "wave-cleared":
        return f"Wave {rest} cleared"
    if kind == "brute-wave":
        return f"Brute wave {rest}"
    if kind == "chase":
        nice = {
            "arrested": "nicked", "escaped": "clean getaway",
            "crashed": "wrapped the bike", "shot": "shot (oops)",
            "fled": "rage quit",
        }.get(rest, rest)
        return f"Chase: {nice}"
    if kind == "stage":
        return f"Stage: {rest}"
    # An unrecognised mark still deserves a readable title.
    return mark.replace(":", " ").replace("_", " ").strip().capitalize() or "Moment"


# ===== loading =====

def load_telemetry(path: Path):
    """Split a session file into (events, notes). Position batches are ignored
    for scoring - they describe where people stood, not what was worth watching.
    """
    events, notes = [], []

    for raw in path.read_text(encoding="utf-8").splitlines():
        raw = raw.strip()
        if not raw:
            continue
        try:
            rec = json.loads(raw)
        except json.JSONDecodeError:
            continue

        mark = rec.get("mark")
        if not mark:
            continue  # a position batch (x/y/z/...) or something unlabelled

        when = rec.get("t")
        if not isinstance(when, (int, float)):
            continue

        if mark == "player-note":
            who = rec.get("p") or "someone"
            notes.append({"t": float(when), "who": who, "note": rec.get("note") or "moment"})
        else:
            notes_kind = str(mark).partition(":")[0]
            events.append({"t": float(when), "mark": str(mark), "kind": notes_kind})

    return events, notes


def load_transcript(path: Path):
    """Earshot transcript lines -> [{t (epoch), speaker, text}], time-sorted."""
    utterances = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        raw = raw.strip()
        if not raw:
            continue
        try:
            rec = json.loads(raw)
            when = to_epoch(str(rec["t"]))
        except (json.JSONDecodeError, KeyError, ValueError):
            continue
        utterances.append({
            "t": when,
            "speaker": rec.get("speaker") or "?",
            "text": (rec.get("text") or "").strip(),
        })
    utterances.sort(key=lambda u: u["t"])
    return utterances


# ===== candidate building =====

def caption_for(utterances, t0, t1, cfg):
    """Transcript text overlapping [t0, t1], joined and truncated."""
    picked = [u["text"] for u in utterances if t0 <= u["t"] <= t1 and u["text"]]
    joined = " ".join(picked)
    cap = cfg["caption_max_chars"]
    return (joined[: cap - 1] + "…") if len(joined) > cap else joined


def laughter_clusters(utterances, cfg):
    """Group utterances into bursts and keep the ones that read as a reaction."""
    clusters = []
    if not utterances:
        return clusters

    gap = cfg["laughter_gap_seconds"]
    current = [utterances[0]]

    def flush(group):
        speakers = {u["speaker"] for u in group}
        if (len(speakers) >= cfg["laughter_min_speakers"]
                or len(group) >= cfg["laughter_min_utterances"]):
            score = (cfg["score_laughter"]
                     + cfg["laughter_speaker_bonus"] * max(0, len(speakers) - cfg["laughter_min_speakers"])
                     + cfg["laughter_utterance_bonus"] * max(0, len(group) - cfg["laughter_min_utterances"]))
            clusters.append({
                "t_start": group[0]["t"],
                "t_end": group[-1]["t"],
                "score": score,
                "speakers": len(speakers),
                "count": len(group),
            })

    for u in utterances[1:]:
        if u["t"] - current[-1]["t"] <= gap:
            current.append(u)
        else:
            flush(current)
            current = [u]
    flush(current)
    return clusters


def build_candidates(events, notes, utterances, cfg):
    """One candidate per signal. Each carries the raw moment span (before
    padding), a score, its source, and a human label."""
    cands = []

    # /tmark notes - the strongest signal, straight from the players.
    for n in notes:
        cands.append({
            "t_start": n["t"], "t_end": n["t"],
            "score": cfg["score_note"], "source": SRC_NOTE,
            "label": f'{n["note"]} (/tmark {n["who"]})',
        })

    # Auto game-events - moments, wave clears, brute cadence, chase endings.
    for e in events:
        base = cfg["event_kind_scores"].get(e["kind"], cfg["score_event"])
        cands.append({
            "t_start": e["t"], "t_end": e["t"],
            "score": base, "source": SRC_EVENT,
            "label": humanise(e["mark"]),
        })

    # Laughter - bursts of overlapping voice.
    for c in laughter_clusters(utterances, cfg):
        cap = caption_for(utterances, c["t_start"], c["t_end"], cfg)
        label = f'reaction ({c["speakers"]} talking)'
        if cap:
            label += f': "{cap}"'
        cands.append({
            "t_start": c["t_start"], "t_end": c["t_end"],
            "score": c["score"], "source": SRC_LAUGH,
            "label": label,
        })

    return cands


def merge(cands, rec_start, cfg):
    """Pad each candidate into a video window, then fold overlapping windows
    into one. A voice burst folded onto a different-source candidate is the
    room reacting to it, so that merge earns the reaction boost."""
    lead, tail, gap = cfg["lead_in_seconds"], cfg["tail_seconds"], cfg["merge_gap_seconds"]

    padded = []
    for c in cands:
        start = max(0.0, (c["t_start"] - lead) - rec_start)
        end = (c["t_end"] + tail) - rec_start
        if end <= 0:
            continue  # entirely before the recording rolled - unclippable
        padded.append({**c, "start": start, "end": end, "sources": {c["source"]}})

    padded.sort(key=lambda c: c["start"])

    merged = []
    for c in padded:
        if merged and c["start"] <= merged[-1]["end"] + gap:
            m = merged[-1]
            crossed = bool(c["sources"] - m["sources"])
            m["end"] = max(m["end"], c["end"])
            m["sources"] |= c["sources"]
            # Keep the strongest label as the headline; note the rest.
            if c["score"] > m["score"]:
                m["label"], c["label"] = c["label"], m["label"]
                m["source"] = c["source"]
                m["score"] = c["score"]
            if crossed:
                m["score"] += cfg["reaction_boost"]
        else:
            merged.append(dict(c))

    return merged


# ===== outputs =====

def write_chapters(path, events, notes, rec_start):
    """YouTube-style chapter list from marks + notes, for the VOD description.
    Laughter is deliberately left out - chapters are a table of contents, not a
    highlight reel."""
    marks = []
    for e in events:
        marks.append((e["t"], humanise(e["mark"])))
    for n in notes:
        marks.append((n["t"], n["note"]))

    rows = []
    for when, title in marks:
        off = when - rec_start
        if off < 0:
            off = 0.0  # a mark from before recording started pins to the top
        rows.append((off, title))

    rows.sort(key=lambda r: r[0])

    # YouTube needs the first chapter at 0:00 or it ignores the lot.
    if not rows or rows[0][0] > 0.5:
        rows.insert(0, (0.0, "Kickoff"))

    # Collapse chapters that land on the same stamp - YouTube drops dupes anyway.
    lines, seen = [], set()
    for off, title in rows:
        stamp = hms(off)
        if stamp in seen:
            lines[-1] = f"{lines[-1]} / {title}"
            continue
        seen.add(stamp)
        lines.append(f"{stamp} {title}")

    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return len(lines)


def write_clips_csv(path, ranked):
    with path.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow([
            "rank", "start", "end", "start_offset", "end_offset",
            "score", "source", "label",
        ])
        for i, c in enumerate(ranked, 1):
            writer.writerow([
                i, hms(c["start"]), hms(c["end"]),
                f'{c["start"]:.1f}', f'{c["end"]:.1f}',
                f'{c["score"]:.0f}',
                "+".join(sorted(c["sources"])),
                c["label"],
            ])


def write_cut_sh(path, ranked, video):
    lines = [
        "#!/usr/bin/env bash",
        "# Generated by clipper. Lossless slices out of your LOCAL OBS recording.",
        "#",
        "#   ./cut.sh [INPUT_VIDEO] [OUTDIR]",
        "#",
        "# -ss BEFORE -i is a fast keyframe seek; -c copy streams-copies (no",
        "# re-encode), so cuts land on the nearest keyframe and stay lossless.",
        "# Nudge lead_in/tail in clipper.py if a clip opens a beat early or late.",
        "set -euo pipefail",
        "",
        f'INPUT="${{1:-{video}}}"   # your OBS local recording, NOT the Twitch VOD',
        'OUTDIR="${2:-clips}"',
        'mkdir -p "$OUTDIR"',
        "",
    ]
    for i, c in enumerate(ranked, 1):
        dur = max(0.1, c["end"] - c["start"])
        name = f'clip-{i:02d}-{slug(c["label"])}'
        lines.append(f'# #{i}  score={c["score"]:.0f}  [{hms(c["start"])}-{hms(c["end"])}]  {c["label"]}')
        lines.append(
            f'ffmpeg -y -ss {c["start"]:.2f} -i "$INPUT" -t {dur:.2f} '
            f'-c copy "$OUTDIR/{name}.mkv"'
        )
        lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")
    path.chmod(0o755)


def write_llc(path, ranked, video):
    """A LosslessCut project. Their .llc is JSON with a cutSegments array of
    {start, end, name} in seconds. Field names track a recent LosslessCut; if a
    given version chokes on the import, see the README TODO."""
    project = {
        "version": 1,
        "mediaFileName": video,
        "cutSegments": [
            {
                "start": round(c["start"], 2),
                "end": round(c["end"], 2),
                "name": f'#{i} {c["label"]}',
            }
            for i, c in enumerate(ranked, 1)
        ],
    }
    path.write_text(json.dumps(project, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


# ===== entrypoint =====

def main() -> None:
    ap = argparse.ArgumentParser(description="Rank clip candidates from a game session.")
    ap.add_argument("session", help="telemetry session file (data-*.jsonl)")
    ap.add_argument("--rec-start", required=True,
                    help="when OBS started recording: epoch seconds or ISO8601. "
                         "Maps telemetry t to video offset (offset = t - rec_start).")
    ap.add_argument("--transcript", help="earshot transcript (session-*.jsonl) for laughter + captions")
    ap.add_argument("--out", default="out", help="output directory (default: out/)")
    ap.add_argument("--video", default="recording.mkv",
                    help="recording filename baked into cut.sh / llc (default: recording.mkv)")
    ap.add_argument("--lead-in", type=float, help="seconds of run-up (overrides config)")
    ap.add_argument("--tail", type=float, help="seconds of reaction tail (overrides config)")
    ap.add_argument("--min-score", type=float, default=0.0, help="drop candidates below this score")
    args = ap.parse_args()

    cfg = dict(CONFIG)
    if args.lead_in is not None:
        cfg["lead_in_seconds"] = args.lead_in
    if args.tail is not None:
        cfg["tail_seconds"] = args.tail

    session = Path(args.session)
    if not session.exists():
        print(f"no such session file: {session}", file=sys.stderr)
        raise SystemExit(1)

    try:
        rec_start = to_epoch(args.rec_start)
    except ValueError:
        print(f"couldn't parse --rec-start: {args.rec_start!r}", file=sys.stderr)
        raise SystemExit(2)

    events, notes = load_telemetry(session)
    utterances = load_transcript(Path(args.transcript)) if args.transcript else []

    cands = build_candidates(events, notes, utterances, cfg)
    merged = merge(cands, rec_start, cfg)
    merged = [c for c in merged if c["score"] >= args.min_score]
    ranked = sorted(merged, key=lambda c: (-c["score"], c["start"]))

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    n_ch = write_chapters(out / "chapters.txt", events, notes, rec_start)
    write_clips_csv(out / "clips.csv", ranked)
    write_cut_sh(out / "cut.sh", ranked, args.video)
    write_llc(out / "llsc.llc", ranked, args.video)

    print(f"[clipper] {len(events)} events, {len(notes)} notes, "
          f"{len(utterances)} utterances in.")
    print(f"[clipper] {len(ranked)} clip candidates, {n_ch} chapters -> {out}/")
    if ranked:
        top = ranked[0]
        print(f"[clipper] top pick: {hms(top['start'])} (score {top['score']:.0f}) {top['label']}")


if __name__ == "__main__":
    main()

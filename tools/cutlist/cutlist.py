#!/usr/bin/env python3
"""Turn a session's telemetry (and optional transcript) into an editing sheet.

The night is captured as structured data: the game auto-marks the funny beats
(a wave cleared, someone going down, a moment firing, a wipe, a new record),
players flag their own with /tmark, and the clapperboard drops a sync point.
This fuses all of that into a timecoded shortlist the editor jumps to, plus a
markers file they import straight into the timeline — so a three-hour session is
editable in an evening instead of scrubbed frame by frame.

Everything is anchored to the **clapperboard**: timecodes are seconds after the
clap, which is exactly where the editor has aligned every camera angle. No clap
in the session? It falls back to the first event and says so.

Deterministic on its own. For the deeper pass — ranking the funniest bits,
picking the cold open, writing chapter titles and Short hooks — hand the
`timeline.json` it produces to an agent following CUTLIST.md.

Usage:
    ./cutlist.py                 # newest session on the server
    ./cutlist.py --session 20260724-203000
    ./cutlist.py --list          # list available sessions
"""
import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE / "out"
TRANSCRIPTS = Path(os.environ.get("TRANSCRIPT_DIR", HERE.parent.parent / "transcripts"))

PROX = os.environ.get("PROX", "root@192.168.0.23")
CT = os.environ.get("CT", "212")
TELEM_DIR = "/opt/fivem/server-data/resources/[local]/telemetry"

# Keyword rules for scoring a beat (weight, colour, blurb). Keyword-based, not
# prefix-based, so an embedded wave number ("horde:wave 12 cleared") still
# matches. First rule that hits wins, so order matters most-specific-first.
# Anything unmatched is context: low value, still logged.
SIGNAL_RULES = [
    ("WIPE",        10, "Red",    "total party kill"),
    ("NEW RECORD",   9, "Yellow", "a record fell"),
    ("DOWN",         9, "Red",    "someone's bleeding out"),
    ("REVIVED",      8, "Green",  "clutch rescue"),
    ("WIN",          8, "Green",  "they actually made it"),
    ("player-note",  8, "Purple", "someone flagged this live"),
    ("moment:",      7, "Cyan",   "a scripted disaster"),
    ("chase:END",    7, "Yellow", "the chase resolved"),
    ("cleared",      4, "Blue",   "held the line"),
]


def run(cmd, timeout=40):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout


def list_sessions():
    remote = f'cd "{TELEM_DIR}" 2>/dev/null && ls -1 data-*.jsonl 2>/dev/null || true'
    out = run(["ssh", "-o", "BatchMode=yes", PROX,
               f"pct exec {CT} -- bash -c {json.dumps(remote)}"])
    return [line.strip().replace("data-", "").replace(".jsonl", "")
            for line in out.splitlines() if line.strip()]


def pull_session(session):
    fname = f"data-{session}.jsonl"
    remote = f'cat "{TELEM_DIR}/{fname}" 2>/dev/null || true'
    out = run(["ssh", "-o", "BatchMode=yes", PROX,
               f"pct exec {CT} -- bash -c {json.dumps(remote)}"])
    rows = []
    for line in out.splitlines():
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return rows


def signal_for(label):
    """(weight, colour, blurb) for a mark label; first matching keyword wins."""
    for key, weight, colour, blurb in SIGNAL_RULES:
        if key in label:
            return weight, colour, blurb
    return 1, "", "context"


def is_chapter(label):
    """A stage/mode transition, not a highlight — starts a new chapter."""
    return (" stage " in label
            or label.startswith("chase:START")
            or label.startswith("horde:wave 1 ")
            or label.startswith("GAME:"))


def tc(seconds):
    seconds = max(0, int(round(seconds)))
    return f"{seconds // 3600:02d}:{(seconds % 3600) // 60:02d}:{seconds % 60:02d}"


def load_transcript(zero, start, end):
    """Optional: transcript lines within the session window, as timecodes.

    Earshot writes epoch-ISO timestamps, so they align to the telemetry clock
    directly. Craig-derived transcripts need their recording-start epoch added
    first (set CRAIG_START); left unset, only epoch-aligned transcripts load.
    """
    from datetime import datetime

    craig_start = float(os.environ.get("CRAIG_START", "0") or "0")
    lines = []
    for f in sorted(TRANSCRIPTS.glob("session-*.jsonl")):
        for raw in f.read_text(encoding="utf-8").splitlines():
            try:
                e = json.loads(raw)
                t = datetime.fromisoformat(e["t"]).timestamp() + craig_start
            except (json.JSONDecodeError, KeyError, ValueError):
                continue
            if start - 5 <= t <= end + 5:
                lines.append({"at": tc(t - zero), "who": e.get("speaker", "?"),
                              "text": e.get("text", "")})
    return lines


def build(session):
    rows = pull_session(session)
    if not rows:
        print(f"no data for session {session}", file=sys.stderr)
        return None

    stamps = [r["t"] for r in rows if isinstance(r.get("t"), (int, float))]
    start, end = min(stamps), max(stamps)

    syncs = [r["t"] for r in rows if r.get("kind") == "sync"]
    if syncs:
        zero, zero_note = min(syncs), "clapperboard"
    else:
        zero, zero_note = start, "first event (NO CLAP — align manually)"

    events, chapters = [], []
    for r in rows:
        label = r.get("mark") or (("moment:" + "") if False else None)
        if r.get("mark") is None:
            continue
        # player-note carries its text in .note; others are the label itself.
        text = r.get("note") or label
        weight, colour, blurb = signal_for(label)
        item = {"t": r["t"], "at": tc(r["t"] - zero), "secs": r["t"] - zero,
                "label": label, "text": text, "weight": weight,
                "colour": colour, "blurb": blurb, "who": r.get("p")}
        if is_chapter(label):
            chapters.append(item)
        events.append(item)

    # Short candidates: high-value beats become a padded in/out window; a
    # DOWN quickly followed by a REVIVED collapses into one rescue clip.
    shorts = []
    highs = [e for e in events if e["weight"] >= 7]
    used = set()
    for i, e in enumerate(highs):
        if i in used:
            continue
        lo, hi = e["secs"], e["secs"]
        hook = e["blurb"]
        for j in range(i + 1, len(highs)):
            if highs[j]["secs"] - e["secs"] <= 30:
                used.add(j)
                hi = highs[j]["secs"]
                if e["label"].startswith("pint:DOWN") and highs[j]["label"].startswith("pint:REVIVED"):
                    hook = "down and dragged back — a rescue"
            else:
                break
        shorts.append({"in": tc(max(0, lo - 15)), "out": tc(hi + 15),
                       "hook": hook, "weight": e["weight"]})

    transcript = load_transcript(zero, start, end)

    return {
        "session": session,
        "zero": {"epoch": zero, "note": zero_note},
        "duration": tc(end - zero),
        "events": sorted(events, key=lambda x: x["secs"]),
        "chapters": sorted(chapters, key=lambda x: x["secs"]),
        "shorts": sorted(shorts, key=lambda x: -x["weight"]),
        "transcript": transcript,
    }


def write_outputs(data):
    out = OUT / data["session"]
    out.mkdir(parents=True, exist_ok=True)

    (out / "timeline.json").write_text(json.dumps(data, indent=2), encoding="utf-8")

    # Editor markers: DaVinci Resolve / Premiere import as a simple CSV.
    csv = ["Name,Start,Colour"]
    for e in data["events"]:
        name = (e["text"] or e["label"]).replace(",", " ")
        csv.append(f'{name},{e["at"]},{e["colour"] or "Blue"}')
    (out / "markers.csv").write_text("\n".join(csv) + "\n", encoding="utf-8")

    # Human/agent-readable sheet.
    md = [f"# Editing sheet — {data['session']}", ""]
    md.append(f"- Zero point: **{data['zero']['note']}**")
    md.append(f"- Session length from zero: **{data['duration']}**")
    md.append(f"- Marks: {len(data['events'])} · Short candidates: {len(data['shorts'])}")
    md.append("\nAll timecodes are **seconds after the clapperboard** — put a "
              "marker on the clap flash in your editor and everything lines up.\n")

    md.append("## Short candidates (best first)")
    for s in data["shorts"][:12]:
        md.append(f"- **{s['in']} → {s['out']}** — {s['hook']}")

    md.append("\n## Chapters")
    for c in data["chapters"]:
        md.append(f"- `{c['at']}` {c['text']}")

    md.append("\n## Full timeline")
    for e in data["events"]:
        star = " ⭐" if e["weight"] >= 8 else ""
        who = f" ({e['who']})" if e.get("who") else ""
        md.append(f"- `{e['at']}` [{e['weight']}] {e['text']}{who}{star}")

    if data["transcript"]:
        md.append("\n## Transcript (aligned)")
        for line in data["transcript"]:
            md.append(f"- `{line['at']}` {line['who']}: {line['text']}")
    else:
        md.append("\n_(No aligned transcript found. Transcribe the Craig tracks "
                  "into ../../transcripts/ and set CRAIG_START to include them.)_")

    (out / "editing-sheet.md").write_text("\n".join(md) + "\n", encoding="utf-8")
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--session", help="session id (YYYYMMDD-HHMMSS); default newest")
    ap.add_argument("--list", action="store_true", help="list available sessions")
    args = ap.parse_args()

    sessions = list_sessions()
    if args.list:
        print("\n".join(sessions) or "(none)")
        return
    if not sessions:
        print("no sessions found on the server", file=sys.stderr)
        raise SystemExit(1)

    session = args.session or sessions[-1]
    data = build(session)
    if not data:
        raise SystemExit(1)

    out = write_outputs(data)
    print(f"wrote {out}/")
    print(f"  editing-sheet.md   ({len(data['events'])} marks, "
          f"{len(data['shorts'])} shorts)")
    print(f"  markers.csv        (import into DaVinci/Premiere)")
    print(f"  timeline.json      (feed to an agent via CUTLIST.md)")
    if data["zero"]["note"] != "clapperboard":
        print("  ! no clapperboard in this session — timecodes need manual alignment")


if __name__ == "__main__":
    main()

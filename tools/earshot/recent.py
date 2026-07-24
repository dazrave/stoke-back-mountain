#!/usr/bin/env python3
"""Prints the last N minutes of transcript, ready to be digested into issues.

    ./recent.py 5      # everything said in the last five minutes

Kept deliberately dumb: the digest step is a Claude agent reading this output,
so the only job here is to hand it a clean, speaker-attributed window with a
marker showing where the last digest finished.
"""
import json
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
TRANSCRIPTS = Path(os.environ.get("TRANSCRIPT_DIR", HERE.parent.parent / "transcripts"))
MARKER = TRANSCRIPTS / ".last-digest"


def main() -> None:
    minutes = float(sys.argv[1]) if len(sys.argv) > 1 else 5.0
    cutoff = datetime.now(tz=timezone.utc) - timedelta(minutes=minutes)

    # Never re-digest something already turned into an issue.
    if MARKER.exists():
        try:
            previous = datetime.fromisoformat(MARKER.read_text().strip())
            cutoff = max(cutoff, previous)
        except ValueError:
            pass

    today = TRANSCRIPTS / f"session-{datetime.now().strftime('%Y%m%d')}.jsonl"
    if not today.exists():
        print("(no transcript yet)")
        return

    lines = []
    latest = None

    for raw in today.read_text(encoding="utf-8").splitlines():
        try:
            entry = json.loads(raw)
            when = datetime.fromisoformat(entry["t"])
        except (json.JSONDecodeError, KeyError, ValueError):
            continue

        if when <= cutoff:
            continue

        latest = when
        lines.append(f"[{when.strftime('%H:%M:%S')}] {entry['speaker']}: {entry['text']}")

    if not lines:
        print("(nothing said in the last %g minutes)" % minutes)
        return

    print("\n".join(lines))

    if latest and "--peek" not in sys.argv:
        MARKER.write_text(latest.isoformat())


if __name__ == "__main__":
    main()

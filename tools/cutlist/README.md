# Cut-list

Turns a captured session into an **editing sheet** — a timecoded shortlist of
the good bits, plus a markers file the editor imports — so a three-hour night is
editable in an evening instead of scrubbed by hand.

## How it works

The game captures the night as structured data:
- it **auto-marks** the funny beats (wave cleared, someone down/revived, a
  moment firing, a wipe, a new record) — see `telemetry/server/main.lua`,
- players flag their own with `/tmark`,
- the **clapperboard** (`/clap`) drops a sync point.

`cutlist.py` pulls that session's log off the server, anchors everything to the
clapperboard, ranks the beats, detects Short-worthy windows (a DOWN quickly
followed by a REVIVED becomes one rescue clip), and writes:

```
out/<session>/
├── editing-sheet.md   # ranked shortlist + Short candidates + chapters (read this)
├── markers.csv        # Name,Start,Colour — import into the timeline
└── timeline.json      # feed to an agent for the deeper pass (see CUTLIST.md)
```

**All timecodes are seconds after the clapperboard.** Drop a marker on the clap
flash in your editor and every angle + the sheet line up.

## Use

```bash
./cutlist.py --list                 # sessions available on the server
./cutlist.py                        # newest session
./cutlist.py --session 20260724-203000
```

Then for the AI pass — cold open, episode title, chapter titles, ranked
highlights, Shorts with hooks — hand `out/<session>/timeline.json` to an agent
following [`CUTLIST.md`](CUTLIST.md).

## Transcript (optional but recommended)

The marks say *where* something happened; the transcript says *whether it was
funny*. Transcribe the **Craig** tracks with `tools/earshot/transcribe.py` into
`transcripts/`, and the cut-list folds the aligned lines in. Craig timestamps
are relative to its recording start, so set `CRAIG_START=<epoch>` (Craig's
recording-start time) when the transcript isn't already epoch-aligned.

## Notes

- `markers.csv` is a simple, human-readable format; some editors want a small
  import step or a specific marker format — adapt per tool, the sheet is the
  primary deliverable.
- No clapperboard in a session? It falls back to the first event and says so —
  timecodes then need manual alignment.

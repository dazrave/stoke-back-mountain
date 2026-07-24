# Clipper

Turns a weekly game-night into a rank-ordered cut list. Point it at one
telemetry session (and, if you have one, the earshot transcript), tell it when
OBS started recording, and it hands back the bits worth clipping — newest
disaster first, biggest laugh near the top.

Earshot writes down what everyone *said*. Clipper reads what the game
*recorded*: the `/tmark` notes people flagged mid-session, the scripted
set-pieces the moments director fired, wave clears, brute waves, and how each
chase ended. It lines those up against your video and does the boring part —
finding the timestamps — so you can go straight to trimming.

## The one golden rule

**Clip your own LOCAL OBS recording. Never the Twitch VOD.** The whole tool
hangs on `offset = t - rec_start`, where `rec_start` is the wall-clock moment
*your* recording began. A Twitch VOD starts whenever the stream went live,
drops frames, and gets re-encoded — the maths won't line up and the clips will
drift. Record locally, lossless, and clip that.

## How offsets work

Every telemetry record carries `t` — plain epoch seconds (`os.time()` on the
server). A video offset is just:

```
offset_seconds = t - rec_start
```

So the single thing you *must* get right is `--rec-start`: the epoch (or
ISO8601) moment OBS rolled. Everything else is derived from it. A minute out on
`rec_start` is a minute out on every single clip.

> **Capturing rec_start.** OBS doesn't shout its start time at you. Easiest
> reliable method: the moment you hit *Start Recording*, run `date +%s` in a
> terminal and jot it down — or read it off the recording file's creation time
> (`stat -c %W game-night.mkv`). This is the one manual step; a human should
> sanity-check it against the first thing that happens on screen.

## What it reads

- **A telemetry session file** — `resources/[local]/telemetry/data-*.jsonl`.
  One JSON line per record. Position batches are ignored (they say where people
  *stood*, not what was *good*); the marks and `/tmark` notes are the signal.
- **An earshot transcript** (optional) — `transcripts/session-*.jsonl`. Used two
  ways: as a **laughter/reaction** signal (a burst of overlapping voices scores
  higher), and as **caption text** hung on each candidate so you know what a clip
  is before you open it.

## What it writes

Everything lands in the `--out` directory:

| File | What it's for |
|---|---|
| `chapters.txt` | YouTube-style chapter markers (`0:00 Title`) from marks + notes. Paste into the VOD description. |
| `clips.csv` | Ranked candidates: `rank, start, end, start_offset, end_offset, score, source, label`. |
| `cut.sh` | An ffmpeg script that slices each candidate out of your video **losslessly** (`-c copy`, keyframe seek) into numbered files. |
| `llsc.llc` | A [LosslessCut](https://github.com/mifi/lossless-cut) project — open your recording, File → Import project, and every candidate is a labelled segment. |

## The ranking

Strongest signal wins, exactly as the brief asks:

1. **`/tmark` notes** — someone stopped playing to flag it. Prime.
2. **Laughter** — a burst of overlapping voices. The room reacting *is* the clip.
3. **Auto game-events** — moments, wave clears, brute waves, chase endings.

A laughter burst landing on top of a `/tmark` or a set-piece doesn't spawn its
own clip — it **merges** into that candidate and earns a reaction boost, because
that's the room reacting to *that thing*. Overlapping candidates are folded into
one moment, then padded with a lead-in and a tail so a clip opens on the run-up
and closes on the payoff.

## Commands

```bash
# The full run: session + transcript + when OBS started + the video filename.
./clipper.py resources/[local]/telemetry/data-20260724-201501.jsonl \
    --transcript ../../transcripts/session-20260724.jsonl \
    --rec-start 2026-07-24T20:14:03+00:00 \
    --video game-night.mkv \
    --out out/

# rec-start also takes plain epoch seconds:
./clipper.py data-*.jsonl --rec-start 1753387200 --out out/

# No transcript? Still works — you just lose the laughter signal and captions.
./clipper.py data-*.jsonl --rec-start 1753387200 --out out/

# Then cut the clips out of your recording (needs ffmpeg on PATH):
cd out && ./cut.sh game-night.mkv          # or: ./cut.sh /path/to/recording.mkv clips/
```

Handy flags: `--lead-in` / `--tail` (seconds of padding, override the config),
`--min-score` (drop weak candidates), `--video` (filename baked into `cut.sh`
and `llsc.llc`).

## Config

Dependency-light on purpose: **stdlib only**. The one runtime dependency is
**ffmpeg**, and only to *run* the generated `cut.sh` — nothing to `pip install`.

Every lever lives in the `CONFIG` block at the top of `clipper.py` (config-first,
same as the game resources): lead-in/tail padding, the per-signal scoring
weights, the per-event-kind scores, and how a laughter burst is detected. Tune
them there. `--lead-in` and `--tail` are exposed on the CLI for a quick one-off.
See `.env.example` for the defaults written out.

## Don't commit session data

Telemetry files (`data-*.jsonl`) and transcripts are **git-ignored** and stay on
the machine — same rule as earshot. The `out/` directory you generate is yours;
don't commit it either. The only thing in this repo is the tool.

## TODO / confirm with a human

- **LosslessCut format.** `llsc.llc` is written as `{version, mediaFileName,
  cutSegments:[{start, end, name}]}`, which matches recent LosslessCut. Field
  names have drifted across versions — if an import is rejected, open a `.llc`
  LosslessCut saved itself and diff the keys. `clips.csv` + `cut.sh` are the
  format-independent fallback.
- **rec_start capture** is manual (see above). If OBS logging or a websocket
  hook can emit the start epoch automatically, wire that in and drop the
  jot-it-down step.
- **Laughter tuning** is a first pass — the speaker/utterance thresholds in
  `CONFIG` were set by eye, not against a real session. Expect to nudge them.

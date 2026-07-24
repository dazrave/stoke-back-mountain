# Cut-list instructions

For the agent that turns a session's fused timeline into an editable episode
plan. Run after a session:

```bash
tools/cutlist/cutlist.py            # writes out/<session>/timeline.json etc.
```

Then read `out/<session>/timeline.json` and produce the plan below. Read
[`../../AGENTS.md`](../../AGENTS.md) first for the house voice — the titles and
captions you write are the brand.

## What you're given

- `events` — every auto-marked beat and `/tmark`, each with `at` (timecode,
  seconds after the clapperboard), a `weight` (rough funniness/importance), and
  a `blurb`.
- `chapters` — mode/mission/stage changes.
- `shorts` — pre-detected clip windows around the strongest beats.
- `transcript` — if present, aligned to the same timecodes: what was actually
  said, by whom. **This is your best signal for comedy** — the marks say *where*
  something happened, the transcript says *whether it was funny*.

## What to produce (`out/<session>/cut.md`)

1. **Cold open** — the single best 15–30s beat of the night, no setup. Give in/out
   timecodes and one line on why it lands. This is also your headline Short.
2. **Episode title** — the build-numbered convention:
   `Patch Notes · GTAi · Build NN — <Theme>: "<funniest result/quote>"`.
3. **Chapters** — timecoded, with titles written in the house voice (funny, not
   descriptive). These go straight into the YouTube description.
4. **Ranked highlights** — the beats worth keeping, best first, each with a
   timecode and a one-line reason. Cut ruthlessly; "funny if you were there"
   is the enemy.
5. **Shorts** — 3–5 self-contained clips (in/out timecodes), each with a title in
   the "we told the AI to X, we got Y" style and a suggested caption/hook.
6. **Caption pulls** — the funniest verbatim quotes with timecodes, for on-screen
   text.

## Rules

- **Timecodes are seconds after the clapperboard.** Don't invent absolute times;
  quote `at`/`in`/`out` from the data.
- If `zero.note` is not "clapperboard", say so at the top — the editor has to
  align by hand and your timecodes are approximate.
- Weights are a hint, not gospel. A low-weight beat with a brilliant line in the
  transcript beats a high-weight beat that fell flat. Use the transcript.
- Don't pad. A tight 10-minute episode with four great Shorts beats a
  meandering 25-minute one every time.

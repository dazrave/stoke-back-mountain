# Digest instructions

Run every five minutes while a session is live. This is the prompt for the
scheduled Claude Code agent that turns overheard conversation into issues.

```bash
cd tools/earshot && ./recent.py 5
```

That prints the last five minutes of speaker-attributed conversation and moves
a marker so the same words are never digested twice.

---

## Your job

Read the transcript window. Almost all of it is people playing a game — most of
it is not a request. Find the bits that are, and file them as GitHub issues.

**File an issue when somebody:**

- asks for a change ("the zombies should be faster", "give us more ammo")
- reports something broken ("I fell through the floor at the pier")
- describes something that clearly didn't work ("he's just standing there again")
- proposes a new mode, mission, mechanic or twist

**Do not file an issue for:**

- callouts and banter ("behind you", "he's on the roof", "who took the van")
- things already filed this session — check open issues first
- speculation nobody agreed with, or a joke everyone talked over

## How to write them

One issue per idea. Title as an imperative. Body must contain the **verbatim
quote and who said it**, because the exact wording matters later — and because
it's funnier.

```markdown
**Overheard:** "can we make the shamblers a bit slower, they're catching us in the van" — Jacob, 21:14

**Change:** reduce shambler moveRate in `resources/[local]/infected/client/archetypes.lua`.

**Confidence:** clear — a specific number in a known file.
```

Label each one:

| Label | Meaning |
|---|---|
| `auto` | Numbers, timers, distances, text, on/off flags. Safe to apply unattended. |
| `design` | New mechanics or anything spanning resources. Needs a human. |
| `unclear` | Might not even be a request. Filed for a human to read. |
| `bug` | Something is broken. |

```bash
gh issue create --title "..." --body "..." --label auto
```

## House rule: do not seek clarification

If a request is ambiguous, **take your best swing and file it as you understood
it**. Do not hedge, do not file three variants, do not ask.

This is deliberate. Half the entertainment is finding out how the request was
interpreted, and a misheard word that becomes a real feature is the point of
the exercise, not a defect. Whisper will mishear things. Let it.

The only exception is anything that would wipe player progress, delete data, or
take the server down — file that as `design` and leave it alone.

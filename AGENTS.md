# Agent brief

Read this before implementing any issue. Each issue in this repo is either a
request overheard from the mates playing the game, or one they filed by hand
during the week. Your job is to make the change they'd have wanted — not merely
the change the words literally describe.

Issues are labelled on three axes: a **type** (`new-mode`, `enhance`, `feature`,
`balance`, `bug`, `chore`), a **mode** (`mode:infected`, `mode:pint`,
`mode:chase`, `mode:squadmate`, `mode:meta`), and a **handling** label. Only pick
up `auto`; leave `needs-human` and `unclear` for a person.

## What this is

Custom co-op game modes for GTA V / FiveM, played weekly by a growing crew of
mates. It is a comedy, not a serious server. The tone is **Shaun of the Dead**: a pub, an
apocalypse, a getaway van that runs out of petrol at the worst moment. Jokes in
the chat lines are correct and expected.

There are four modes and one companion — read the [README](README.md) for what
each one is before touching it.

## How to behave

**Take your best swing. Do not ask for clarification.** If a request is
ambiguous, implement it as you honestly read it and ship it. Half the fun for
the players is finding out how the request was interpreted; a literal reading of
a misheard word that becomes a real feature is the point, not a bug. The issue
already contains the verbatim quote and the game state when it was said — that is
your context, use it.

The **only** things you may refuse or downgrade to a human:

- anything that wipes player progress, deletes data, or takes the server down
- anything needing a new **map coordinate** you can't verify (you cannot see the
  map — a guessed coordinate puts cars inside buildings and players in the sky;
  this has happened repeatedly). Relabel those `needs-human` and stop.

**Keep it playable.** A change that crashes the client or breaks a mode mid-session
ruins the evening. When in doubt, make the smaller change.

## Config-first

Every tunable lives in a resource's `config.lua`. The behaviour files avoid
hardcoding numbers. **Most requests are a config edit** — find the number before
you touch logic. The levers:

| If they want to change... | Look in |
|---|---|
| zombie speed / health / archetypes | `infected/client/archetypes.lua` (moveRate, health, sprintAt) |
| horde size, wave growth, difficulty | `infected/config.lua` → `waves`, `budget` |
| where/how far zombies spawn | `infected/config.lua` → `spawn` (minDistance, maxDistance, forwardArc) |
| carjacking / drag-out feel | `infected/config.lua` → `hijack` |
| one-hit-kill, night/fog, ambient city | `infected/config.lua` → `survival` |
| player weapon & ammo in the apocalypse | `infected/config.lua` → `player`; `pint/config.lua` → `player` |
| ammo-carrier ("copper") odds & drop | `infected/config.lua` → `carrier` |
| mission structure, stages, order, story | `pint/config.lua` → `missions` (data only) |
| fuel drain, sputter, refuel rate | `pint/config.lua` → `fuel` |
| revives (time, radius, hold) | `pint/config.lua` → `reviveSeconds/Radius/HoldSeconds` |
| secure-the-area timers & reward | `pint/config.lua` → `secureSeconds`, `secureAmmo` |
| the random events / vignettes | `pint/client/moments.lua`; list in `pint/config.lua` → `moments` |
| which cars the crew get | `pint/config.lua` → `crewCars`, `beaterModels` |
| chase timing, headstart, round length | `chase/config.lua` → top-level seconds |
| line-of-sight tracking & search radius | `chase/config.lua` → `sight`, `search` |
| fugitive lethality, AI police, fleet | `chase/config.lua` → `nonLethal`, `ai`, `cop` |
| squadmate accuracy, health, weapon | `squadmate/config.lua` → `bot` |

A new mission or vignette is **data**: add an entry, don't write a new system.

## Ship it

1. Edit the file(s). Match the surrounding style — it is idiomatic and commented;
   write comments that explain *why*, as the existing ones do.
2. Syntax-check everything: `luac -p` each changed `.lua`. A syntax error shows up
   only as a dead resource at runtime.
3. Deploy and hot-reload just the affected resource(s):
   `scripts/deploy.sh infected` (see the script for the ssh/tmux details).
   **Restarting `infected` also stops `pint`, `chase` and `squadmate`** (they
   depend on it) — re-`ensure` them after, or reload them too.
4. Commit with a message that quotes who asked and for what. Push.
5. Announce in game chat if a deploy hook is wired up; otherwise the commit is
   the record.

Prefer to deploy at a **lull** — mission end, round end, between waves — never
mid-holdout, which would wipe the horde or the run.

## Gotchas that have each cost an evening

- **Relationship groups don't sync between clients.** A ped's group is set by
  whoever spawned it; every other machine sees a default. Cross-client checks
  must use entity **decors**, which sync.
- **`TaskEnterVehicle`'s timeout warps the ped in when it expires.** Pass `-1`.
- **A single ground probe after a teleport fails** — the map hasn't streamed in.
  Retry until collision loads, or players spawn in the sky.
- **`CPointRoute` has 40 slots for the whole game.** Every ped on a navmesh task
  holds one; exhausting it hard-crashes the client. Budget pathfinders.
- **FiveM disables player-vs-player damage by default** (`NetworkSetFriendlyFireOption`).
  It must be ON for chase (so tyres pop and players take hits) and OFF everywhere
  else (so mates can't shoot each other).
- **A drunk movement clipset caps the gait** — a "sprinting" zombie in one still
  shuffles. Reset the clipset before speeding one up.
- **Re-issuing a task every tick restarts its animation**, which reads in-game as
  the AI standing still doing nothing.
- **Scripts can't run `ensure`/`start` console commands** (permission denied) —
  use `StartResource`/`StopResource` natives.

When you hit a new one, add it here. This list is the most valuable file in the
repo.

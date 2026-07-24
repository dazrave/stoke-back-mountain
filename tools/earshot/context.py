#!/usr/bin/env python3
"""What was happening in the game at a given moment?

    ./context.py 2026-07-24T21:14:03+00:00
    ./context.py 1753312443

Given the time an utterance was said, prints the game state that was live then:
which mode and mission were running, the wave and difficulty, and where every
player was standing. Feed it the `t` from a transcript line; paste the output
into the issue.

The state comes from the telemetry resource, which writes a snapshot every few
seconds. Those live on the game server, so we pull them over the same ssh hop
the deploy script uses and cache them briefly to avoid a round trip per lookup.
"""
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
CACHE = HERE / ".telemetry-cache.jsonl"
CACHE_TTL = 30  # seconds

PROX = os.environ.get("PROX", "root@192.168.0.23")
CT = os.environ.get("CT", "212")
TELEM_DIR = "/opt/fivem/server-data/resources/[local]/telemetry"

# A snapshot this far from the utterance is close enough to describe it.
WINDOW = 25


def fetch_snapshots() -> list[dict]:
    """State snapshot lines from the server, cached for a few seconds."""
    if CACHE.exists() and (time.time() - CACHE.stat().st_mtime) < CACHE_TTL:
        raw = CACHE.read_text(encoding="utf-8")
    else:
        # cd into the dir so the [local] glob is a literal path, not a pattern.
        remote = (
            f'cd "{TELEM_DIR}" 2>/dev/null && '
            'grep -h \'"kind":"state"\' data-*.jsonl 2>/dev/null || true'
        )
        try:
            raw = subprocess.run(
                ["ssh", "-o", "BatchMode=yes", PROX,
                 f"pct exec {CT} -- bash -c {json.dumps(remote)}"],
                capture_output=True, text=True, timeout=30,
            ).stdout
            CACHE.write_text(raw, encoding="utf-8")
        except (subprocess.SubprocessError, OSError) as error:
            print(f"(could not reach telemetry: {error})", file=sys.stderr)
            return []

    out = []
    for line in raw.splitlines():
        try:
            entry = json.loads(line)
            if entry.get("kind") == "state":
                out.append(entry)
        except json.JSONDecodeError:
            continue
    return out


def to_epoch(when: str) -> float:
    when = when.strip()
    if when.replace(".", "", 1).isdigit():
        value = float(when)
        return value / 1000 if value > 1e12 else value  # tolerate ms
    return datetime.fromisoformat(when).timestamp()


def describe_mode(snap: dict) -> str:
    mission, chase, horde = snap.get("mission"), snap.get("chase"), snap.get("horde")

    if mission and mission.get("active"):
        bit = f'pint / {mission.get("mission")} — stage {mission.get("stageIndex")}'
        if mission.get("stageTitle"):
            bit += f' "{mission["stageTitle"]}"'
        if mission.get("securing"):
            bit += " (securing)"
        if mission.get("downed"):
            bit += f' — {mission["downed"]} down'
        return bit

    if chase and chase.get("phase") and chase["phase"] != "idle":
        bit = f'chase — {chase["phase"]}, fugitive {chase.get("fugitive")}'
        bit += ", being tracked" if chase.get("tracking") else ", off the radar"
        return bit

    if horde and horde.get("engaged"):
        bit = f'horde — wave {horde.get("wave")}, {horde.get("alive")} alive'
        if horde.get("intensity"):
            bit += f', intensity {horde["intensity"]:.2g}x'
        return bit

    return "free roam (no mode running)"


def main() -> None:
    if len(sys.argv) < 2:
        print("usage: context.py <iso-timestamp|epoch>", file=sys.stderr)
        raise SystemExit(2)

    try:
        target = to_epoch(sys.argv[1])
    except ValueError:
        print(f"(couldn't parse time: {sys.argv[1]!r})", file=sys.stderr)
        raise SystemExit(2)

    snaps = fetch_snapshots()
    near = min(snaps, key=lambda s: abs(s.get("t", 0) - target), default=None)

    if not near or abs(near.get("t", 0) - target) > WINDOW:
        print("**At the time:** _(no game telemetry within "
              f"{WINDOW}s — probably nobody was in-game)_")
        return

    stamp = datetime.fromtimestamp(near["t"], tz=timezone.utc).strftime("%H:%M:%S")
    lines = [f"**At the time ({stamp} UTC):**", f"- Mode: {describe_mode(near)}"]

    players = near.get("players") or []
    if players:
        lines.append("- Players:")
        for p in players:
            where = []
            if p.get("d"):
                where.append("DOWN")
            elif p.get("v"):
                where.append("in a vehicle")
            else:
                where.append("on foot")
            lines.append(
                f'  - {p.get("name")} @ ({p.get("x")}, {p.get("y")}, {p.get("z")})'
                f' — {", ".join(where)}'
            )

    print("\n".join(lines))


if __name__ == "__main__":
    main()

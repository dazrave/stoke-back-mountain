#!/usr/bin/env bash
#
# Starts the listener and the transcriber together. Ctrl-C stops both.
#
#   ./start.sh
#
# The bot drops one WAV per utterance into queue/; the transcriber picks them
# up, writes to ../../transcripts/session-YYYYMMDD.jsonl, and deletes the audio.
# Nothing keeps the recordings.
set -euo pipefail

cd "$(dirname "$0")"

if [[ ! -f .env ]]; then
  echo "No .env - copy .env.example to .env and add your Discord token." >&2
  exit 1
fi

if [[ ! -d .venv ]]; then
  echo "No .venv - run: python3 -m venv .venv && ./.venv/bin/pip install faster-whisper" >&2
  exit 1
fi

cleanup() {
  echo
  echo "[earshot] shutting down"
  kill 0 2>/dev/null || true
}
trap cleanup EXIT INT TERM

./.venv/bin/python transcribe.py &
node bot.mjs &

wait

#!/usr/bin/env bash
#
# Copy new idea submissions off the game-server box for triage.
#
#   web/pull-ideas.sh
#
# Appends the server's queue to the local ./submissions/incoming.jsonl. The
# server file is the source of truth; this is a read-only pull.
set -euo pipefail

PROX="${PROX:-root@192.168.0.23}"
CT="${CT:-212}"
REMOTE="${REMOTE:-/opt/sbm-web/submissions/incoming.jsonl}"

cd "$(dirname "$0")"
mkdir -p submissions

ssh "$PROX" "pct exec $CT -- cat $REMOTE 2>/dev/null" > submissions/incoming.jsonl || {
  echo "no submissions yet"; exit 0;
}

count=$(wc -l < submissions/incoming.jsonl | tr -d ' ')
echo "pulled $count submission(s) to submissions/incoming.jsonl"

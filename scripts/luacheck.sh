#!/usr/bin/env bash
#
# Syntax-check Lua without touching the live server.
#
#   scripts/luacheck.sh                                  # every resource file
#   scripts/luacheck.sh resources/[local]/infected/...   # just these
#
# There's no luac on the dev machine and no root to install one, so the check
# runs on the game server's Lua — the same interpreter that will actually load
# the file. Files go to a scratch directory, never into the live resources, so
# a broken edit can't be picked up by an unrelated restart.
#
# A syntax error otherwise shows up only as a dead resource at runtime, in
# front of everyone.
set -euo pipefail

PROX="${PROX:-root@192.168.0.23}"
CT="${CT:-212}"
SCRATCH="/tmp/luacheck-$$"

cd "$(dirname "$0")/.."

if [ "$#" -gt 0 ]; then
  FILES=("$@")
else
  mapfile -t FILES < <(find 'resources/[local]' -name '*.lua' | sort)
fi

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "nothing to check"
  exit 0
fi

echo "==> checking ${#FILES[@]} file(s) on CT${CT}"

tar czf - "${FILES[@]}" \
  | ssh "$PROX" "pct exec $CT -- bash -c '
      mkdir -p $SCRATCH && cd $SCRATCH && tar xzf - && \
      fail=0
      while IFS= read -r f; do
        if ! out=\$(luac -p \"\$f\" 2>&1); then
          echo \"SYNTAX FAIL: \$f\"
          echo \"  \$out\"
          fail=1
        fi
      done < <(find . -name \"*.lua\")
      rm -rf $SCRATCH
      exit \$fail
    '"

echo "==> all parsed OK"

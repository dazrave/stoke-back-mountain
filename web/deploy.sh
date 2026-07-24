#!/usr/bin/env bash
#
# Push the web app to the game-server box and (re)start it.
#
#   web/deploy.sh
#
# Installs to /opt/sbm-web on CT212 via the prox1 hop, sets up the systemd
# service the first time, and restarts it. The submissions queue in
# /opt/sbm-web/submissions is left untouched.
set -euo pipefail

PROX="${PROX:-root@192.168.0.23}"
CT="${CT:-212}"
DEST="${DEST:-/opt/sbm-web}"

cd "$(dirname "$0")"

echo "==> copying web app to CT${CT}:${DEST}"
ssh "$PROX" "pct exec $CT -- mkdir -p $DEST/submissions"
tar czf - server.py public sbm-web.service \
  | ssh "$PROX" "pct exec $CT -- tar xzf - -C $DEST"

echo "==> installing / refreshing the service"
ssh "$PROX" "pct exec $CT -- bash -c '
  cp $DEST/sbm-web.service /etc/systemd/system/sbm-web.service
  systemctl daemon-reload
  systemctl enable sbm-web >/dev/null 2>&1 || true
  systemctl restart sbm-web
  sleep 1
  systemctl --no-pager --lines=0 status sbm-web | head -3
'"

echo "==> local check"
ssh "$PROX" "pct exec $CT -- bash -c 'curl -s -o /dev/null -w \"health: %{http_code}\n\" http://127.0.0.1:8099/api/health'"

echo "==> done. Origin for Cloudflare: http://192.168.0.212:8099"

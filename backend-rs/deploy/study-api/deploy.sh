#!/usr/bin/env bash
# Build + deploy study-api (run as root on the server). Keeps the previous
# binary for instant rollback.
#
#   From your machine (backend-rs/):
#     tar czf study-api.tgz --force-local Cargo.toml Cargo.lock crates deploy
#     scp study-api.tgz octopilot-vps:/opt/study-api/src.tgz
#   On the server:
#     rm -rf /opt/study-api/src && mkdir -p /opt/study-api/src
#     tar xzf /opt/study-api/src.tgz -C /opt/study-api/src
#     bash /opt/study-api/src/deploy/study-api/deploy.sh
#
#   Rollback:  bash deploy.sh --rollback
set -euo pipefail

APP=/opt/study-api
SRC=$APP/src
BIN=$APP/bin/study-api
SERVICE=study-api
PORT=8110

if [ "${1:-}" = "--rollback" ]; then
  [ -f "$BIN.prev" ] || { echo "no previous binary"; exit 1; }
  cp "$BIN.prev" "$BIN"
  systemctl restart "$SERVICE"
  echo "rolled back"; exit 0
fi

echo "== build (release) in rust:1-slim-bookworm"
docker run --rm -v "$SRC":/app -v octo-cargo:/usr/local/cargo/registry -w /app rust:1-slim-bookworm \
  cargo build --release -p study-api

echo "== install"
[ -f "$BIN" ] && cp "$BIN" "$BIN.prev"
cp "$SRC/target/release/study-api" "$BIN.new"
chmod 755 "$BIN.new"
mv "$BIN.new" "$BIN"
cp "$BIN" "$APP/releases/study-api-$(date +%Y%m%d-%H%M%S)"
ls -1t "$APP"/releases/ | tail -n +6 | sed "s#^#$APP/releases/#" | xargs -r rm -f   # keep 5

echo "== restart (migrations run at startup)"
systemctl restart "$SERVICE"
for i in $(seq 1 30); do
  if curl -fsS "127.0.0.1:$PORT/ready" >/dev/null; then echo "ready"; exit 0; fi
  sleep 1
done
echo "NOT READY — rolling back"; journalctl -u "$SERVICE" -n 50 --no-pager
[ -f "$BIN.prev" ] && cp "$BIN.prev" "$BIN" && systemctl restart "$SERVICE"
exit 1

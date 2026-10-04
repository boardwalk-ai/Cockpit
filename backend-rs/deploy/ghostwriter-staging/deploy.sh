#!/usr/bin/env bash
# Build + deploy GhostWriter staging (run as root on the server from the
# unpacked workspace). Keeps the previous binary for instant rollback.
#
#   From your machine (backend-rs/):
#     tar czf gw-staging.tgz --force-local Cargo.toml Cargo.lock crates deploy
#     scp gw-staging.tgz octopilot-vps:/opt/ghostwriter-staging/src.tgz
#   On the server:
#     rm -rf /opt/ghostwriter-staging/src && mkdir -p /opt/ghostwriter-staging/src
#     tar xzf /opt/ghostwriter-staging/src.tgz -C /opt/ghostwriter-staging/src
#     bash /opt/ghostwriter-staging/src/deploy/ghostwriter-staging/deploy.sh
#
#   Rollback:  bash deploy.sh --rollback
set -euo pipefail

APP=/opt/ghostwriter-staging
SRC=$APP/src
BIN=$APP/bin/ghostwriter-api
SERVICE=ghostwriter-staging
PORT=8795

if [ "${1:-}" = "--rollback" ]; then
  [ -f "$BIN.prev" ] || { echo "no previous binary"; exit 1; }
  cp "$BIN.prev" "$BIN"
  systemctl restart "$SERVICE"
  echo "rolled back"; exit 0
fi

echo "== build (release) in rust:1-slim-bookworm"
docker run --rm -v "$SRC":/app -v octo-cargo:/usr/local/cargo/registry -w /app rust:1-slim-bookworm \
  cargo build --release -p ghostwriter-api

echo "== install"
[ -f "$BIN" ] && cp "$BIN" "$BIN.prev"
cp "$SRC/target/release/ghostwriter-api" "$BIN.new"
chmod 755 "$BIN.new"
mv "$BIN.new" "$BIN"
cp "$BIN" "$APP/releases/ghostwriter-api-$(date +%Y%m%d-%H%M%S)"
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

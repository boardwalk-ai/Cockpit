#!/usr/bin/env bash
# Build + deploy octonotes-api on the server (run as root on the server from
# the unpacked workspace). Keeps the previous binary for instant rollback.
#
#   From your machine:
#     cd backend-rs && tar czf backend-rs.tgz --force-local Cargo.toml Cargo.lock crates deploy
#     pscp backend-rs.tgz root@SERVER:/opt/octonotes-api/src.tgz
#   On the server:
#     mkdir -p /opt/octonotes-api/src && tar xzf /opt/octonotes-api/src.tgz -C /opt/octonotes-api/src
#     bash /opt/octonotes-api/src/deploy/octonotes/deploy.sh
#
#   Rollback:  bash deploy.sh --rollback
set -euo pipefail

APP=/opt/octonotes-api
SRC=$APP/src
BIN=$APP/bin/octonotes-api

if [ "${1:-}" = "--rollback" ]; then
  [ -f "$BIN.prev" ] || { echo "no previous binary"; exit 1; }
  cp "$BIN.prev" "$BIN"
  systemctl restart octonotes-api
  echo "rolled back"; exit 0
fi

echo "== build (release) in rust:1-slim-bookworm"
docker run --rm -v "$SRC":/app -v octo-cargo:/usr/local/cargo/registry -w /app rust:1-slim-bookworm \
  cargo build --release -p octonotes-api

echo "== install"
[ -f "$BIN" ] && cp "$BIN" "$BIN.prev"
cp "$SRC/target/release/octonotes-api" "$BIN.new"
chmod 755 "$BIN.new"
mv "$BIN.new" "$BIN"
cp "$BIN" "$APP/releases/octonotes-api-$(date +%Y%m%d-%H%M%S)"
ls -1t "$APP"/releases/ | tail -n +6 | sed "s#^#$APP/releases/#" | xargs -r rm -f   # keep 5

echo "== restart (migrations run at startup)"
systemctl restart octonotes-api
for i in $(seq 1 30); do
  if curl -fsS 127.0.0.1:8790/ready >/dev/null; then echo "ready"; exit 0; fi
  sleep 1
done
echo "NOT READY — rolling back"; journalctl -u octonotes-api -n 50 --no-pager
[ -f "$BIN.prev" ] && cp "$BIN.prev" "$BIN" && systemctl restart octonotes-api
exit 1

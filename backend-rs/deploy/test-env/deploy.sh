#!/usr/bin/env bash
# Build + deploy the test environment's three services from the unpacked
# workspace (run as root on the server). Keeps the previous binaries.
#
#   From your machine (backend-rs/):
#     tar czf test-env.tgz --force-local --exclude=target Cargo.toml Cargo.lock crates deploy
#     scp test-env.tgz octopilot-vps:/opt/test-env-src.tgz
#   On the server:
#     rm -rf /opt/test-env-src && mkdir -p /opt/test-env-src && tar xzf /opt/test-env-src.tgz -C /opt/test-env-src
#     bash /opt/test-env-src/deploy/test-env/deploy.sh
set -euo pipefail
SRC=$(cd "$(dirname "$0")/../.." && pwd)
echo "== build (release)"
docker run --rm -v "$SRC":/app -v octo-cargo:/usr/local/cargo/registry -w /app rust:1-slim-bookworm \
  cargo build --release -p study-api -p ghostwriter-api -p admin-api
install_bin() { # name bin-path service port
  [ -f "$2" ] && cp "$2" "$2.prev"
  cp "$SRC/target/release/$1" "$2.new"; chmod 755 "$2.new"; mv "$2.new" "$2"
  systemctl restart "$3"
  for i in $(seq 1 30); do curl -fsS -o /dev/null "127.0.0.1:$4/health" 2>/dev/null && { echo "  $3 up"; return; }; sleep 1; done
  echo "  $3 NOT UP — rolling back"; journalctl -u "$3" -n 30 --no-pager
  [ -f "$2.prev" ] && cp "$2.prev" "$2" && systemctl restart "$3"; exit 1
}
install_bin study-api /opt/study-api-staging/bin/study-api study-api-staging 8112
install_bin ghostwriter-api /opt/ghostwriter-staging/bin/ghostwriter-api ghostwriter-staging 8795
install_bin admin-api /opt/admin-api/bin/admin-api admin-api 8796
systemctl reload nginx
echo "done"

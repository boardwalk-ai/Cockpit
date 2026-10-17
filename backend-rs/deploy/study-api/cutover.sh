#!/usr/bin/env bash
# R7: route api.octopilothub.com between the Python stack (Go gateway :8100 →
# cockpit-api) and study-api (:8110). Run as root on the server.
#
#   cutover.sh python   everything to Python; Rust workers off   (rollback)
#   cutover.sh reads    GET /me, /studios, /studios/{id}, activity to Rust
#   cutover.sh all      everything to Rust; Rust ingest/build/notify workers on
#   cutover.sh status   show the current mode
#
# Only one side writes at a time: the Rust workers run only in "all", and in
# "all" Python gets no requests (its builds/uploads start only from requests).
set -euo pipefail

MODE=${1:?usage: cutover.sh python|reads|all|status}
SITE=/etc/nginx/sites-available/cockpit
MAP=/etc/nginx/conf.d/cockpit-cutover.conf
ENV=/opt/study-api/app.env
PY=http://127.0.0.1:8100
RS=http://127.0.0.1:8110

if [ "$MODE" = status ]; then
  head -1 "$MAP" 2>/dev/null || echo "# mode: python (no map)"
  grep -E '^(INGEST|BUILD|NOTIFY)_WORKER=' "$ENV"
  exit 0
fi

# The site proxies through the map's variable (once; original kept).
if ! grep -q 'proxy_pass \$cockpit_upstream;' "$SITE"; then
  cp "$SITE" "$SITE.pre-r7"
  sed -i "s#proxy_pass $PY;#proxy_pass \$cockpit_upstream;#" "$SITE"
fi

case "$MODE" in
  python) default=$PY; rust_reads=""; workers=0 ;;
  reads)  default=$PY; workers=0
          rust_reads=$(printf '    "~^GET /(me|studios)$"                %s;\n    "~^GET /studios/[^/]+$"               %s;\n    "~^GET /studios/[^/]+/activity$"      %s;\n' "$RS" "$RS" "$RS") ;;
  all)    default=$RS; rust_reads=""; workers=1 ;;
  *) echo "unknown mode $MODE"; exit 1 ;;
esac

# Workers first when leaving "all" (stop Rust writing before Python takes over).
set_workers() {
  sed -i -E "s/^(INGEST|BUILD|NOTIFY)_WORKER=.*/\1_WORKER=$1/" "$ENV"
  systemctl restart study-api
  for i in $(seq 1 30); do curl -fsS 127.0.0.1:8110/ready >/dev/null 2>&1 && return; sleep 1; done
  echo "study-api not ready"; exit 1
}
[ "$workers" = 0 ] && grep -q '^BUILD_WORKER=1' "$ENV" && set_workers 0
# The Python/Go stack is stopped after the cutover; bring it back first.
if [ "$MODE" != all ]; then
  for c in cockpit-embed cockpit-api cockpit-worker cockpit-gateway; do
    docker update --restart=always "$c" >/dev/null && docker start "$c" >/dev/null
  done
  for i in $(seq 1 30); do curl -fsS -o /dev/null 127.0.0.1:8100/go/health 2>/dev/null && break; sleep 1; done
fi
[ "$MODE" != python ] && ! curl -fsS 127.0.0.1:8110/ready >/dev/null && { echo "study-api not ready — not switching"; exit 1; }

cp "$MAP" "$MAP.prev" 2>/dev/null || true
cat > "$MAP" <<CONF
# mode: $MODE  ($(date -Is))  — written by deploy/study-api/cutover.sh
map "\$request_method \$uri" \$cockpit_upstream {
    default $default;
$rust_reads
}
CONF
if ! nginx -t 2>/dev/null; then
  nginx -t || true
  [ -f "$MAP.prev" ] && cp "$MAP.prev" "$MAP"
  echo "nginx config bad — kept the previous map"; exit 1
fi
systemctl reload nginx

[ "$workers" = 1 ] && set_workers 1
echo "mode: $MODE"

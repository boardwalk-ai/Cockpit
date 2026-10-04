#!/usr/bin/env bash
# One-time setup of GhostWriter staging, apart from production: its own user,
# Postgres container (5439), service (127.0.0.1:8795) and nginx site. Run as
# root from the unpacked workspace (see README.md). Safe to run again.
#
#   bash install.sh pm@example.com[,other@example.com]
set -euo pipefail

ALLOW=${1:?usage: install.sh <allowed tester emails, comma-separated>}
APP=/opt/ghostwriter-staging
SRC=$APP/src
HERE=$(cd "$(dirname "$0")" && pwd)

echo "== user and folders"
id gw-staging >/dev/null 2>&1 ||
  useradd --system --home /var/lib/gw-staging --shell /usr/sbin/nologin gw-staging
mkdir -p "$APP/bin" "$APP/releases" /var/lib/gw-staging
chown gw-staging:gw-staging /var/lib/gw-staging

echo "== database (own container)"
if [ ! -f "$APP/db.env" ]; then
  (umask 077 && echo "GW_STAGING_DB_PASSWORD=$(openssl rand -hex 24)" > "$APP/db.env")
fi
# shellcheck disable=SC1091
. "$APP/db.env"
cp "$HERE/docker-compose.yml" "$APP/docker-compose.yml"
docker compose -f "$APP/docker-compose.yml" --env-file "$APP/db.env" up -d
for i in $(seq 1 30); do
  docker exec gw-staging-db pg_isready -U gw_staging -d ghostwriter >/dev/null 2>&1 && break
  sleep 2
done
db() { docker exec -i gw-staging-db psql -U gw_staging -v ON_ERROR_STOP=1 -q "$@"; }
db -d ghostwriter -tAc "SELECT 1 FROM pg_database WHERE datname = 'octopilot_staging'" | grep -q 1 ||
  docker exec gw-staging-db createdb -U gw_staging octopilot_staging
# The shared octopilot tables, as the tests and local dev have them.
db -d octopilot_staging < "$SRC/crates/octonotes-api/dev/octopilot_dev.sql"
db -d octopilot_staging -c "DELETE FROM users WHERE firebase_uid = 'dev-user'"

echo "== app.env"
(
  umask 027
  cat > "$APP/app.env" <<ENV
GHOSTWRITER_DATABASE_URL=postgres://gw_staging:${GW_STAGING_DB_PASSWORD}@127.0.0.1:5439/ghostwriter
OCTOPILOT_DATABASE_URL=postgres://gw_staging:${GW_STAGING_DB_PASSWORD}@127.0.0.1:5439/octopilot_staging
FIREBASE_PROJECT_ID=octopilot-ai-7b29e
BIND=127.0.0.1
PORT=8795
CREDITS_ENABLED=true
CREDITS_LEDGER_TYPE=octo
GHOSTWRITER_DRIVER=agent
ACCOUNT_ALLOWLIST=${ALLOW}
STARTING_CREDITS=9999
ENV
)
chown root:gw-staging "$APP/app.env"

echo "== service and site"
cp "$HERE/ghostwriter-staging.service" /etc/systemd/system/ghostwriter-staging.service
systemctl daemon-reload
systemctl enable ghostwriter-staging >/dev/null
cp "$HERE/nginx-gw-staging.conf" /etc/nginx/sites-available/gw-staging
ln -sf /etc/nginx/sites-available/gw-staging /etc/nginx/sites-enabled/gw-staging
nginx -t && systemctl reload nginx

echo "installed. Next: copy-keys.sh, deploy.sh, then certbot (README.md)."

#!/usr/bin/env bash
# One-time server setup for octonotes-api (Ubuntu 24.04). Idempotent — safe to
# re-run. Run as root on the server:  bash install.sh
set -euo pipefail

APP=/opt/octonotes-api
DATA=/var/lib/octonotes

echo "== packages (ffmpeg: audio join/compress; poppler: PDF page renders)"
apt-get update -qq
apt-get install -y -qq ffmpeg poppler-utils postgresql-client
# LibreOffice renders PPTX slides to images (~500 MB). Text extraction works without it.
if [ "${WITH_LIBREOFFICE:-0}" = "1" ]; then apt-get install -y -qq --no-install-recommends libreoffice-impress; fi

echo "== user + folders"
id octonotes >/dev/null 2>&1 || useradd --system --home "$DATA" --shell /usr/sbin/nologin octonotes
mkdir -p "$APP/bin" "$APP/releases" "$DATA/blobs" /var/backups/octonotes
chown -R octonotes:octonotes "$DATA"
chmod 750 "$DATA"

echo "== env files"
if [ ! -f "$APP/.env" ]; then
  cp "$(dirname "$0")/.env.production.example" "$APP/.env"
  echo "   created $APP/.env from the example — fill in every CHANGE_ME before starting"
fi
chown root:octonotes "$APP/.env"; chmod 640 "$APP/.env"
if [ ! -f "$APP/db.env" ]; then
  echo "OCTONOTES_DB_ADMIN_PASSWORD=$(openssl rand -hex 24)" > "$APP/db.env"
  chmod 600 "$APP/db.env"
fi

echo "== notes_db container"
cp "$(dirname "$0")/docker-compose.prod.yml" "$APP/docker-compose.prod.yml"
docker compose -f "$APP/docker-compose.prod.yml" --env-file "$APP/db.env" up -d
until docker exec octonotes-db pg_isready -U octonotes_admin -d octonotes >/dev/null 2>&1; do sleep 1; done

echo "== systemd unit"
cp "$(dirname "$0")/octonotes-api.service" /etc/systemd/system/octonotes-api.service
systemctl daemon-reload
systemctl enable octonotes-api >/dev/null

echo "== backups (nightly 03:15)"
cp "$(dirname "$0")/backup.sh" "$APP/backup.sh"; chmod 750 "$APP/backup.sh"
echo "15 3 * * * root $APP/backup.sh >> /var/log/octonotes-backup.log 2>&1" > /etc/cron.d/octonotes-backup

cat <<'NEXT'
Next steps (manual, once):
  1. Roles: run sql/roles.sql section 1 in octonotes-db, sections 2–4 on the other DBs.
  2. Fill /opt/octonotes-api/.env (all CHANGE_ME).
  3. nginx: include nginx/octonotes.conf in the chosen site, nginx -t && systemctl reload nginx.
  4. Deploy the binary with deploy.sh, then: curl -s 127.0.0.1:8790/ready
NEXT

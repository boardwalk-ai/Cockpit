#!/usr/bin/env bash
# One-time setup of study-api in production (R7): its own user, app.env made
# from the Python service's .env (same databases, MinIO, origins), the systemd
# unit on 127.0.0.1:8110. Workers start OFF; cutover.sh turns them on. Safe to
# run again (keeps an existing app.env). Run as root on the server.
set -euo pipefail

APP=/opt/study-api
HERE=$(cd "$(dirname "$0")" && pwd)
PYENV=/opt/cockpit/Backend/.env

echo "== user and folders"
id study-api >/dev/null 2>&1 ||
  useradd --system --home /var/lib/study-api --shell /usr/sbin/nologin study-api
mkdir -p "$APP/bin" "$APP/releases" /var/lib/study-api
chown study-api:study-api /var/lib/study-api

echo "== app.env"
if [ ! -f "$APP/app.env" ]; then
  py() { grep -E "^$1=" "$PYENV" | tail -1 | cut -d= -f2-; }
  pg() { py "$1" | sed -E 's#^postgresql\+asyncpg://#postgres://#'; }
  (
    umask 027
    cat > "$APP/app.env" <<ENV
COCKPIT_DATABASE_URL=$(pg COCKPIT_DATABASE_URL)
VECTOR_DATABASE_URL=$(pg VECTOR_DATABASE_URL)
SHARED_DATABASE_URL=$(pg SHARED_DATABASE_URL)
EMBED_SERVICE_URL=$(py EMBED_SERVICE_URL)
FIREBASE_PROJECT_ID=$(py FIREBASE_PROJECT_ID)
CORS_ORIGINS=$(py CORS_ORIGINS)
OBJECT_STORE_ENDPOINT=$(py OBJECT_STORE_ENDPOINT)
OBJECT_STORE_REGION=$(py OBJECT_STORE_REGION)
OBJECT_STORE_BUCKET=$(py OBJECT_STORE_BUCKET)
OBJECT_STORE_ACCESS_KEY=$(py OBJECT_STORE_ACCESS_KEY)
OBJECT_STORE_SECRET_KEY=$(py OBJECT_STORE_SECRET_KEY)
HIRARA_HUB_URL=http://127.0.0.1:8080
BIND=127.0.0.1
PORT=8110
LOG_FORMAT=json
MIGRATE=1
INGEST_WORKER=0
BUILD_WORKER=0
NOTIFY_WORKER=0
# FCM_SERVICE_ACCOUNT_FILE=/opt/study-api/fcm.json   (unset = no push)
ENV
  )
  chown root:study-api "$APP/app.env"
fi
grep -q '^FIREBASE_PROJECT_ID=.\+' "$APP/app.env" || { echo "FIREBASE_PROJECT_ID empty — refusing (dev header would be on)"; exit 1; }

echo "== service"
cp "$HERE/study-api.service" /etc/systemd/system/study-api.service
systemctl daemon-reload
systemctl enable study-api >/dev/null
echo "installed. Next: deploy.sh, then cutover.sh reads|all."

#!/usr/bin/env bash
# One-time setup of the test environment (run as root on the server from the
# unpacked workspace), next to production and apart from it:
#
#   - Study Studio staging: study-api-staging on 127.0.0.1:8112 with its own
#     cockpit_staging + vector_staging databases (empty, schema from the last
#     nightly dump), served at https://gw-staging.octopilothub.com/study/
#   - admin-api on 127.0.0.1:8796, at https://gw-staging.octopilothub.com/control/
#   - GhostWriter staging behind the same gate.
#
# All three share octopilot_staging (users, OctoCredits, app_allowlist,
# feature_flags), so a tester has one balance and one invitation.
#
#   bash setup.sh admin@example.com
set -euo pipefail
ADMINS=${1:?admin email(s), comma separated}
SRC=$(cd "$(dirname "$0")/../.." && pwd)
GW_ENV=/opt/ghostwriter-staging/app.env
PROD_ENV=/opt/study-api/app.env
P="docker exec octo-pg psql -U octo_admin -v ON_ERROR_STOP=1 -q"
NIGHT=$(ls -1d /opt/backups/nightly/*/ | tail -1)
get() { grep -E "^$1=" "$2" | head -1 | cut -d= -f2-; }
setenv() { # key value file
  if grep -qE "^$1=" "$3"; then sed -i "s|^$1=.*|$1=$2|" "$3"; else echo "$1=$2" >> "$3"; fi
}

echo "== databases (schema only, from $NIGHT)"
for pair in cockpit_staging:cockpit vector_staging:vector; do
  db=${pair%%:*}; src=${pair##*:}
  if [ "$(docker exec octo-pg psql -U octo_admin -d postgres -Atc "select 1 from pg_database where datname='$db'")" != 1 ]; then
    $P -d postgres -c "CREATE DATABASE $db OWNER $src" </dev/null
    docker exec -i octo-pg pg_restore -U octo_admin -d "$db" --schema-only --exit-on-error < "$NIGHT$src.dump"
    echo "  $db made"
  else
    echo "  $db exists"
  fi
done

echo "== study-api-staging"
mkdir -p /opt/study-api-staging/bin /var/lib/study-api-staging
chown study-api:study-api /var/lib/study-api-staging
ENV=/opt/study-api-staging/app.env
if [ ! -f "$ENV" ]; then
  cp "$PROD_ENV" "$ENV"
  setenv COCKPIT_DATABASE_URL "$(get COCKPIT_DATABASE_URL "$PROD_ENV" | sed -E 's#/[a-z_]+$#/cockpit_staging#')" "$ENV"
  setenv VECTOR_DATABASE_URL "$(get VECTOR_DATABASE_URL "$PROD_ENV" | sed -E 's#/[a-z_]+$#/vector_staging#')" "$ENV"
  setenv SHARED_DATABASE_URL "$(get OCTOPILOT_DATABASE_URL "$GW_ENV")" "$ENV"
  setenv PORT 8112 "$ENV"
  setenv MIGRATE 1 "$ENV"
  setenv INGEST_WORKER 1 "$ENV"
  setenv BUILD_WORKER 1 "$ENV"
  setenv ACCESS_GATE 1 "$ENV"
  setenv ADMIN_EMAILS "$ADMINS" "$ENV"
  setenv STARTING_CREDITS 9999 "$ENV"
  chmod 600 "$ENV"; chown study-api:study-api "$ENV"
fi
sed -e 's#/opt/study-api/#/opt/study-api-staging/#g' -e 's#/var/lib/study-api#/var/lib/study-api-staging#g' \
    -e 's#^Description=.*#Description=Study Studio API, staging (study-api, Rust)#' \
    "$SRC/deploy/study-api/study-api.service" > /etc/systemd/system/study-api-staging.service

echo "== admin-api"
mkdir -p /opt/admin-api/bin
AENV=/opt/admin-api/app.env
if [ ! -f "$AENV" ]; then
  {
    echo "SHARED_DATABASE_URL=$(get OCTOPILOT_DATABASE_URL "$GW_ENV")"
    echo "FIREBASE_PROJECT_ID=$(get FIREBASE_PROJECT_ID "$GW_ENV")"
    echo "ADMIN_EMAILS=$ADMINS"
    echo "BIND=127.0.0.1"
    echo "PORT=8796"
    echo "LOG_FORMAT=json"
    echo "STUDY_DATABASE_URL=$(get COCKPIT_DATABASE_URL "$ENV")"
    echo "GHOSTWRITER_DATABASE_URL=$(get GHOSTWRITER_DATABASE_URL "$GW_ENV")"
    echo "FCM_SERVICE_ACCOUNT_FILE=/opt/admin-api/fcm.json"
    echo "PUBLIC_URL=https://gw-staging.octopilothub.com/control"
  } > "$AENV"
  install -o gw-staging -g gw-staging -m 600 "$(get FCM_SERVICE_ACCOUNT_FILE "$PROD_ENV")" /opt/admin-api/fcm.json
  chmod 600 "$AENV"; chown gw-staging:gw-staging "$AENV"
fi
cp "$SRC/deploy/test-env/admin-api.service" /etc/systemd/system/admin-api.service

echo "== GhostWriter staging behind the gate"
setenv ACCESS_GATE 1 "$GW_ENV"
setenv ADMIN_EMAILS "$ADMINS" "$GW_ENV"

echo "== nginx: /study/ and /control/ on gw-staging"
cp "$SRC/deploy/test-env/nginx-test-env.conf" /etc/nginx/snippets/test-env.conf
SITE=/etc/nginx/sites-enabled/gw-staging
grep -q 'snippets/test-env.conf' "$SITE" || sed -i 's|^\(\s*\)location / {|\1include snippets/test-env.conf;\n\1location / {|' "$SITE"
nginx -t
systemctl daemon-reload
systemctl enable study-api-staging admin-api
echo "now: bash $SRC/deploy/test-env/deploy.sh"

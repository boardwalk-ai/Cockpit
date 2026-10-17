#!/usr/bin/env bash
# Announcements on a throwaway copy of octopilot_staging (dev auth): picture
# upload + public link, checks on what's sent, sending to an account with a
# fake phone (FCM answers: not a valid token — proving the FCM key works), and the
# history. No real phone is notified.
set -euo pipefail
SRC=$(cd "$(dirname "$0")/../.." && pwd)
P="docker exec octo-pg psql -U octo_admin -v ON_ERROR_STOP=1 -q"
$P -d postgres -c "DROP DATABASE IF EXISTS octopilot_t WITH (FORCE)" -c "CREATE DATABASE octopilot_t OWNER gw_staging" </dev/null
docker exec octo-pg pg_dump -U octo_admin -Fc octopilot_staging | docker exec -i octo-pg pg_restore -U octo_admin -d octopilot_t --exit-on-error
$P -d postgres -c "DROP DATABASE IF EXISTS cockpit_t WITH (FORCE)" -c "CREATE DATABASE cockpit_t OWNER cockpit" </dev/null
docker exec octo-pg pg_dump -U octo_admin -Fc cockpit_staging | docker exec -i octo-pg pg_restore -U octo_admin -d cockpit_t --exit-on-error
get() { grep -E "^$1=" /opt/admin-api/app.env | cut -d= -f2-; }
SHARED=$(get SHARED_DATABASE_URL | sed -E 's#/[a-z_]+$#/octopilot_t#'); STUDY=$(get STUDY_DATABASE_URL | sed -E 's#/[a-z_]+$#/cockpit_t#')
U=$(docker exec octo-pg psql -U octo_admin -d octopilot_t -Atc "insert into users (firebase_uid, email, name, octo_credits) values ('boss-uid','boss@t.est','Boss',0) returning id" | head -1)
docker exec octo-pg psql -U octo_admin -d cockpit_t -qc "insert into study_devices (id, user_id, token, platform) values (gen_random_uuid(), '$U', 'fake-token-e2e', 'android')" 2>&1 | grep -v NOTICE || true
mkdir -p /tmp/notify-media
( SHARED_DATABASE_URL=$SHARED STUDY_DATABASE_URL=$STUDY ADMIN_EMAILS=boss@t.est PORT=8195 FIREBASE_PROJECT_ID= \
  FCM_SERVICE_ACCOUNT_FILE=/opt/admin-api/fcm.json MEDIA_DIR=/tmp/notify-media PUBLIC_URL=http://127.0.0.1:8195 \
  nohup "$SRC/target/release/admin-api" > /tmp/notify-e2e.log 2>&1 & echo $! > /tmp/notify-e2e.pid )
trap 'kill $(cat /tmp/notify-e2e.pid) 2>/dev/null; for d in octopilot_t cockpit_t; do $P -d postgres -c "DROP DATABASE IF EXISTS $d WITH (FORCE)" </dev/null; done; rm -rf /tmp/notify-media; echo cleaned up' EXIT
for i in $(seq 1 30); do curl -fsS -o /dev/null 127.0.0.1:8195/health 2>/dev/null && break; sleep 1; done
A=127.0.0.1:8195; H=(-H "X-User-Id: boss-uid" -H "X-User-Email: boss@t.est")
code() { curl -s -o /tmp/r.json -w "%{http_code}" "$@"; }
body() { head -c 200 /tmp/r.json; echo; }
echo "== picture upload → public link"
printf '\x89PNG\r\n\x1a\nfake' > /tmp/p.png
echo "  upload: $(code "${H[@]}" -H 'Content-Type: image/png' --data-binary @/tmp/p.png $A/v1/admin/media) $(body)"
URL=$(python3 -c 'import json; print(json.load(open("/tmp/r.json"))["url"])')
echo "  fetch:  $(curl -s -o /dev/null -w '%{http_code} %{content_type}' "$URL")"
echo "  gif:    $(code "${H[@]}" -H 'Content-Type: image/gif' --data-binary @/tmp/p.png $A/v1/admin/media) $(body)"
echo "== checks"
echo "  no title: $(code "${H[@]}" -H 'Content-Type: application/json' -d '{"title":" ","body":"x","audience":{"kind":"me"}}' $A/v1/admin/notifications) $(body)"
echo "  http pic: $(code "${H[@]}" -H 'Content-Type: application/json' -d '{"title":"t","body":"x","image":"http://x/y.png","audience":{"kind":"me"}}' $A/v1/admin/notifications) $(body)"
echo "  not admin: $(code -H 'X-User-Id: x' -H 'X-User-Email: x@t.est' -H 'Content-Type: application/json' -d '{"title":"t","body":"x","audience":{"kind":"me"}}' $A/v1/admin/notifications)"
echo "== send to me: one fake phone → FCM refuses the made-up token (the key works)"
echo "  $(code "${H[@]}" -H 'Content-Type: application/json' -d '{"title":"Hello testers","body":"e2e","audience":{"kind":"me"}}' $A/v1/admin/notifications) $(body)"
echo "  devices left: $(docker exec octo-pg psql -U octo_admin -d cockpit_t -Atc "select count(*) from study_devices where token='fake-token-e2e'")"
echo "== phones report themselves (registry)"
DEV=$(cat /proc/sys/kernel/random/uuid)
J='Content-Type: application/json'
echo "  no permission: $(code "${H[@]}" -H "$J" -H 'X-Forwarded-For: 49.229.209.215' -X PUT -d '{"id":"'$DEV'","token":null,"status":"permission_denied","error":"notifications not allowed (PermissionStatus.denied)","platform":"android","manufacturer":"OPPO","model":"CPH2591","osVersion":"Android 14 (SDK 34)","appVersion":"1.0.2+2101"}' $A/v1/app/devices) $(body)"
echo "  registered but no token: $(code "${H[@]}" -H "$J" -X PUT -d '{"id":"'$DEV'","status":"registered","platform":"android"}' $A/v1/app/devices) $(body)"
echo "  registered: $(code "${H[@]}" -H "$J" -H 'X-Forwarded-For: 49.229.209.215' -X PUT -d '{"id":"'$DEV'","token":"fake-token-2","status":"registered","platform":"android","manufacturer":"OPPO","model":"CPH2591","osVersion":"Android 14 (SDK 34)","appVersion":"1.0.2+2101"}' $A/v1/app/devices) $(body)"
OTHER=$(cat /proc/sys/kernel/random/uuid)
echo "  same token, another install (token moves): $(code "${H[@]}" -H "$J" -X PUT -d '{"id":"'$OTHER'","token":"fake-token-2","status":"registered","platform":"android"}' $A/v1/app/devices)"
echo "  first install now: $(docker exec octo-pg psql -U octo_admin -d octopilot_t -Atc "select status from app_devices where id='$DEV'") (signed_out)"
code "${H[@]}" -H "$J" -X PUT -d '{"id":"'$DEV'","token":"fake-token-2","status":"registered","platform":"android","manufacturer":"OPPO","model":"CPH2591"}' $A/v1/app/devices >/dev/null
echo "  admin list: $(code "${H[@]}" "$A/v1/admin/devices?email=boss@t.est") $(head -c 260 /tmp/r.json)"
echo "  tester row phones: $(code "${H[@]}" "$A/v1/admin/users?q=boss" >/dev/null; grep -o '"phones[A-Za-z]*":[0-9]*' /tmp/r.json | tr '
' ' ')"
echo "  send to me → FCM refuses the made-up token → marked: $(code "${H[@]}" -H "$J" -d '{"title":"t","body":"x","audience":{"kind":"me"}}' $A/v1/admin/notifications) devices=$(grep -o '"devices":[0-9]*' /tmp/r.json)"
echo "  status now: $(docker exec octo-pg psql -U octo_admin -d octopilot_t -Atc "select status||' / '||coalesce(error,'') from app_devices where id='$DEV'")"
echo "  sign out: $(code "${H[@]}" -X DELETE $A/v1/app/devices/$DEV) → $(docker exec octo-pg psql -U octo_admin -d octopilot_t -Atc "select status||' '||coalesce(email,'(no account)') from app_devices where id='$DEV'")"
echo "== history"
code "${H[@]}" $A/v1/admin/notifications >/dev/null; body

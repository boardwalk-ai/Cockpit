#!/usr/bin/env bash
# R6 on throwaway copies: device + plan endpoints, checks, ownership, the
# outbox row a finished build leaves. No push is sent (no FCM key here).
set -euo pipefail
cd /opt/study-api
NIGHT=$(ls -1d /opt/backups/nightly/*/ | tail -1)
P="docker exec octo-pg psql -U octo_admin -v ON_ERROR_STOP=1 -q"
q() { docker exec octo-pg psql -U octo_admin -d "$1" -Atc "$2" </dev/null; }
for pair in cockpit_t:cockpit vector_t:vector; do
  db=${pair%%:*}; src=${pair##*:}
  $P -d postgres -c "DROP DATABASE IF EXISTS $db WITH (FORCE)" -c "CREATE DATABASE $db OWNER $src" </dev/null
  docker exec -i octo-pg pg_restore -U octo_admin -d "$db" --exit-on-error < "$NIGHT$src.dump"
done
read -r SID OWNER < <(q cockpit_t "select id, user_id from studios order by created_at desc limit 1" | tr '|' ' ')
VBASE=$(sudo -n grep -E '^VECTOR_DATABASE_URL=' /opt/cockpit/Backend/.env | cut -d= -f2- | sed -E 's#^postgresql\+asyncpg://#postgres://#; s#/vector$##')
BASE=$(sudo -n grep -E '^COCKPIT_DATABASE_URL=' /opt/cockpit/Backend/.env | cut -d= -f2- | sed -E 's#^postgresql\+asyncpg://#postgres://#; s#/cockpit$##')
( set -a; . ./shadow.env; set +a
  COCKPIT_DATABASE_URL="$BASE/cockpit_t" VECTOR_DATABASE_URL="$VBASE/vector_t" PORT=8116 MIGRATE=1 nohup ./bin/study-api > notify-e2e.log 2>&1 & echo $! > notify-e2e.pid )
for i in $(seq 1 30); do curl -fsS -o /dev/null 127.0.0.1:8116/health 2>/dev/null && break; sleep 1; done
H=(-H "X-User-Id: $OWNER" -H 'Content-Type: application/json')
ev() { grep -A1 '^event:' | paste - - | grep -v 'event: done' | sed 's/event: //; s/\tdata: / /' | cut -c1-110; }
D=11111111-2222-4333-8444-555555555555
echo "== device: register, again (same row), bad platform"
curl -fsS -X POST "${H[@]}" -d "{\"id\":\"$D\",\"token\":\"tok-a\",\"platform\":\"android\",\"tzMinutes\":390}" 127.0.0.1:8116/devices | ev
curl -fsS -X POST "${H[@]}" -d "{\"id\":\"$D\",\"token\":\"tok-b\",\"platform\":\"android\",\"tzMinutes\":390}" 127.0.0.1:8116/devices | ev
curl -fsS -X POST "${H[@]}" -d "{\"id\":\"$D\",\"token\":\"tok-b\",\"platform\":\"fridge\"}" 127.0.0.1:8116/devices | ev
echo "  rows: $(q cockpit_t "select count(*) || ' ' || max(token) || ' tz ' || max(tz_minutes) from study_devices")"
echo "== plan: save, update, bad, someone else's studio"
curl -fsS -X POST "${H[@]}" -d '{"mode":"exam","exam":"2026-11-02","minutes":30,"days":[5,1,3],"remind":1140,"tzMinutes":390}' "127.0.0.1:8116/studios/$SID/plan" | ev
curl -fsS -X POST "${H[@]}" -d '{"mode":"pace","minutes":45,"days":[2],"remind":null,"tzMinutes":390}' "127.0.0.1:8116/studios/$SID/plan" | ev
curl -fsS -X POST "${H[@]}" -d '{"mode":"exam","minutes":45,"days":[2]}' "127.0.0.1:8116/studios/$SID/plan" | ev
curl -fsS -X POST -H 'X-User-Id: 00000000-0000-0000-0000-000000000009' -H 'Content-Type: application/json' -d '{"mode":"pace","minutes":30,"days":[1]}' "127.0.0.1:8116/studios/$SID/plan" | ev
echo "  row: $(q cockpit_t "select mode || ' ' || coalesce(exam::text,'-') || ' ' || minutes || ' ' || days::text || ' remind ' || coalesce(remind_minute::text,'off') from study_plans where studio_id = '$SID'")"
echo "== a device moves to whoever signs in; delete"
curl -fsS -X POST -H 'X-User-Id: 00000000-0000-0000-0000-000000000009' -H 'Content-Type: application/json' -d "{\"id\":\"$D\",\"token\":\"tok-b\",\"platform\":\"android\"}" 127.0.0.1:8116/devices | ev
echo "  owner now other: $(q cockpit_t "select user_id = '00000000-0000-0000-0000-000000000009' from study_devices where id = '$D'")"
curl -fsS -X DELETE "${H[@]}" 127.0.0.1:8116/devices/$D | ev
echo "  old owner can't delete it: $(q cockpit_t "select count(*) from study_devices")"
curl -fsS -X DELETE -H 'X-User-Id: 00000000-0000-0000-0000-000000000009' 127.0.0.1:8116/devices/$D | ev
echo "  after its owner deletes: $(q cockpit_t "select count(*) from study_devices")"
echo "== outbox dedupe (same key twice)"
for i in 1 2; do q cockpit_t "insert into study_notifications (id, user_id, kind, dedupe_key, title, body) values (gen_random_uuid(), '$OWNER', 'plan', 'plan:$OWNER:2026-10-07', 't', 'b') on conflict (dedupe_key) do nothing" >/dev/null; done
echo "  rows for the key: $(q cockpit_t "select count(*) from study_notifications where dedupe_key = 'plan:$OWNER:2026-10-07'")"
kill "$(cat notify-e2e.pid)"; rm -f notify-e2e.pid
for db in cockpit_t vector_t; do $P -d postgres -c "DROP DATABASE $db WITH (FORCE)" </dev/null; done
echo "cleaned up"
grep -iE "panic|error" notify-e2e.log | tail -3 || true

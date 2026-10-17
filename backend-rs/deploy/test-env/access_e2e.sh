#!/usr/bin/env bash
# The test environment's gate on a throwaway copy of octopilot_staging:
# allowlist, feature flags, credits +/- and settings through admin-api, and
# study-api letting a tester in (or not) within seconds. Dev auth: X-User-Id
# + X-User-Email. Nothing touches the live staging rows.
set -euo pipefail
SRC=$(cd "$(dirname "$0")/../.." && pwd)
REL=$SRC/target/release
P="docker exec octo-pg psql -U octo_admin -v ON_ERROR_STOP=1 -q"
q() { docker exec octo-pg psql -U octo_admin -d octopilot_t -Atc "$1" </dev/null; }
$P -d postgres -c "DROP DATABASE IF EXISTS octopilot_t WITH (FORCE)" -c "CREATE DATABASE octopilot_t OWNER gw_staging" </dev/null
docker exec octo-pg pg_dump -U octo_admin -Fc octopilot_staging | docker exec -i octo-pg pg_restore -U octo_admin -d octopilot_t --exit-on-error
url() { grep -E "^$1=" /opt/study-api-staging/app.env | cut -d= -f2- | sed -E "s#/[a-z_]+\$#/$2#"; }
SHARED=$(url SHARED_DATABASE_URL octopilot_t)
( SHARED_DATABASE_URL=$SHARED ADMIN_EMAILS=boss@t.est PORT=8197 FIREBASE_PROJECT_ID= nohup "$REL/admin-api" > /tmp/admin-e2e.log 2>&1 & echo $! > /tmp/admin-e2e.pid )
( set -a; . /opt/study-api-staging/app.env; set +a
  SHARED_DATABASE_URL=$SHARED PORT=8198 FIREBASE_PROJECT_ID= ADMIN_EMAILS=boss@t.est INGEST_WORKER=0 BUILD_WORKER=0 NOTIFY_WORKER=0 MIGRATE=0 \
  nohup "$REL/study-api" > /tmp/study-e2e.log 2>&1 & echo $! > /tmp/study-e2e.pid )
trap 'kill $(cat /tmp/admin-e2e.pid /tmp/study-e2e.pid) 2>/dev/null; $P -d postgres -c "DROP DATABASE IF EXISTS octopilot_t WITH (FORCE)" </dev/null; echo cleaned up' EXIT
for p in 8197 8198; do for i in $(seq 1 30); do curl -fsS -o /dev/null 127.0.0.1:$p/health 2>/dev/null && break; sleep 1; done; done
A=127.0.0.1:8197; S=127.0.0.1:8198
U=11111111-2222-3333-4444-555555555555
as_admin=(-H "X-User-Id: boss" -H "X-User-Email: boss@t.est")
as_tester=(-H "X-User-Id: $U" -H "X-User-Email: tester@t.est")
code() { curl -s -o /tmp/r.json -w "%{http_code}" "$@"; }
body() { head -c 160 /tmp/r.json; echo; }

echo "== a tester off the list: study-api 403 not_invited; app access says so"
echo "  studios: $(code "${as_tester[@]}" $S/studios) $(body)"
echo "  access:  $(code "${as_tester[@]}" $A/v1/app/access) $(body)"
echo "== not an admin: admin endpoints 403"
echo "  $(code "${as_tester[@]}" $A/v1/admin/users) $(body)"
echo "== admin lets them in → within 5 s study-api answers"
echo "  allow: $(code "${as_admin[@]}" -H 'Content-Type: application/json' -d '{"email":"Tester@T.est","note":"e2e"}' $A/v1/admin/allowlist) $(body)"
sleep 6
echo "  studios: $(code "${as_tester[@]}" $S/studios)"
echo "== study_studio flag off → 403 feature_off; only for them → 200"
echo "  $(code "${as_admin[@]}" -X PUT -H 'Content-Type: application/json' -d '{"enabled":false,"emails":[]}' $A/v1/admin/flags/study_studio)"
sleep 6
echo "  studios: $(code "${as_tester[@]}" $S/studios) $(body)"
echo "  admin still in: $(code "${as_admin[@]}" $A/v1/app/access) $(body)"
code "${as_admin[@]}" -X PUT -H 'Content-Type: application/json' -d '{"enabled":false,"emails":["tester@t.est"]}' $A/v1/admin/flags/study_studio >/dev/null
sleep 6
echo "  studios: $(code "${as_tester[@]}" $S/studios)"
echo "  access:  $(code "${as_tester[@]}" $A/v1/app/access) $(body)"
echo "== credits +/- on an account"
ID=$(q "select id from users order by email limit 1"); B=$(q "select octo_credits from users where id='$ID'")
echo "  before $B"
echo "  +500: $(code "${as_admin[@]}" -H 'Content-Type: application/json' -d '{"delta":500,"reason":"e2e"}' $A/v1/admin/users/$ID/credits) $(body)"
echo "  -999999: $(code "${as_admin[@]}" -H 'Content-Type: application/json' -d '{"delta":-999999}' $A/v1/admin/users/$ID/credits) $(body)"
echo "  ledger: $(q "select entry_type||' '||amount||' '||reason from credit_ledger where user_id='$ID' and entry_type like 'admin%'")"
echo "== settings: prices yes, API keys never"
echo "  put price: $(code "${as_admin[@]}" -X PUT -H 'Content-Type: application/json' -d '{"value":"20"}' $A/v1/admin/settings/study_price_ask) $(body)"
echo "  put key:   $(code "${as_admin[@]}" -X PUT -H 'Content-Type: application/json' -d '{"value":"x"}' $A/v1/admin/settings/stealthgpt_api_key) $(body)"
code "${as_admin[@]}" $A/v1/admin/settings >/dev/null; echo "  keys listed: $(grep -o '"key":"[a-z_]*"' /tmp/r.json | tr '\n' ' ')"
echo "== remove from the list → 403 again"
echo "  $(code "${as_admin[@]}" -X DELETE $A/v1/admin/allowlist/tester@t.est)"
sleep 6
echo "  studios: $(code "${as_tester[@]}" $S/studios)"
echo "== open_access on → anyone signed in"
code "${as_admin[@]}" -X PUT -H "Content-Type: application/json" -d "{\"enabled\":true,\"emails\":[]}" $A/v1/admin/flags/study_studio >/dev/null
code "${as_admin[@]}" -X PUT -H 'Content-Type: application/json' -d '{"enabled":true}' $A/v1/admin/flags/open_access >/dev/null
sleep 6
echo "  stranger: $(code -H "X-User-Id: 99999999-2222-3333-4444-555555555555" -H "X-User-Email: who@t.est" $S/studios) $(body)"
echo "== audit"
code "${as_admin[@]}" "$A/v1/admin/audit?limit=20" >/dev/null; grep -o '"action":"[a-z]*","admin":"[^"]*"\|"action":"[a-z]*"' /tmp/r.json | sort | uniq -c
grep -iE "panic" /tmp/admin-e2e.log /tmp/study-e2e.log || true

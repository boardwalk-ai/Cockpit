#!/usr/bin/env bash
# OctoCredits + Idempotency-Key on throwaway copies (cockpit, vector AND
# octopilot, so no real balance moves): free until a price is set, 402 with
# no AI call when short, metered charge once per answer, fixed price, and a
# retried create / upload returning the first result. Two real Ask AI calls
# (~6 cents).
set -euo pipefail
cd /opt/study-api
NIGHT=$(ls -1d /opt/backups/nightly/*/ | tail -1)
P="docker exec octo-pg psql -U octo_admin -v ON_ERROR_STOP=1 -q"
q() { docker exec octo-pg psql -U octo_admin -d "$1" -Atc "$2" </dev/null; }
for pair in cockpit_t:cockpit vector_t:vector octopilot_t:octopilot; do
  db=${pair%%:*}; src=${pair##*:}
  $P -d postgres -c "DROP DATABASE IF EXISTS $db WITH (FORCE)" -c "CREATE DATABASE $db OWNER $src" </dev/null
  docker exec -i octo-pg pg_restore -U octo_admin -d "$db" --exit-on-error < "$NIGHT$src.dump"
done
read -r OWNER SID < <(q vector_t "select user_id, studio_id from chunks group by 1,2 order by count(*) desc limit 1" | tr '|' ' ')
url() { grep -E "^$1=" app.env | cut -d= -f2- | sed -E "s#/[a-z_]+\$#/$2#"; }
( set -a; . ./app.env; set +a
  COCKPIT_DATABASE_URL=$(url COCKPIT_DATABASE_URL cockpit_t) VECTOR_DATABASE_URL=$(url VECTOR_DATABASE_URL vector_t) \
  SHARED_DATABASE_URL=$(url SHARED_DATABASE_URL octopilot_t) FIREBASE_PROJECT_ID= PORT=8118 MIGRATE=1 \
  INGEST_WORKER=0 BUILD_WORKER=0 NOTIFY_WORKER=0 LOG_FORMAT=text nohup "${BIN:-./bin/study-api}" > credits-e2e.log 2>&1 & echo $! > credits-e2e.pid )
for i in $(seq 1 30); do curl -fsS -o /dev/null 127.0.0.1:8118/health 2>/dev/null && break; sleep 1; done
H=(-H "X-User-Id: $OWNER")
ev() { grep -E '^(event|data):' | paste - - | grep -v 'event: done' | sed 's/event: //; s/\tdata: / /' | cut -c1-140; }
bal() { q octopilot_t "select octo_credits from users where id = '$OWNER'"; }
setting() { q octopilot_t "insert into system_settings (key, value) values ('$1', '$2') on conflict (key) do update set value = excluded.value" >/dev/null; }
calls() { q cockpit_t "select count(*) from llm_usage where feature = 'ask'"; }
ASK="127.0.0.1:8118/ask?studio_id=$SID&q=What%20is%20this%20material%20about%3F"

echo "== free (no price set): balance stays"
q octopilot_t "update users set octo_credits = 100 where id = '$OWNER'" >/dev/null
curl -fsS -N --max-time 120 "${H[@]}" "$ASK" | grep -c '^event: delta' | sed 's/^/  deltas: /'
echo "  balance: $(bal) (100)"

echo "== metered, 1000 credits per \$1, balance 0 → 402, no AI call"
setting study_credits_per_usd 1000
sleep 61   # price cache
q octopilot_t "update users set octo_credits = 0 where id = '$OWNER'" >/dev/null
before=$(calls)
curl -fsS -N --max-time 60 "${H[@]}" "$ASK" | ev
echo "  AI calls made: $(( $(calls) - before )) (0)"

echo "== metered, balance 100 → charged ceil(cost × 1000) once"
q octopilot_t "update users set octo_credits = 100 where id = '$OWNER'" >/dev/null
curl -fsS -N --max-time 120 "${H[@]}" "$ASK" | grep -c '^event: delta' | sed 's/^/  deltas: /'
sleep 1
echo "  cost: $(q cockpit_t "select cost_usd from llm_usage where feature = 'ask' order by created_at desc limit 1") → balance $(bal)"
echo "  ledger: $(q octopilot_t "select entry_type || ' ' || amount || ' ' || left(source_ref, 22) || ' ' || reason from credit_ledger where user_id = '$OWNER' and source_ref like 'study:%'")"

echo "== fixed price for concepts beats the rate; short → 402"
setting study_price_concepts 500
sleep 61
TID=$(q cockpit_t "select payload->>'id' from generated_topics where studio_id = '$SID' order by ordinal limit 1")
q cockpit_t "update generated_topics set payload = payload - 'concepts' where studio_id = '$SID' and payload->>'id' = '$TID'" >/dev/null
curl -fsS -X POST "${H[@]}" "127.0.0.1:8118/studios/$SID/topics/$TID/concepts" | ev

echo "== fixed price ask (20): paid before the answer, kept when the user leaves mid-answer"
setting study_price_ask 20
sleep 61
q octopilot_t "update users set octo_credits = 100 where id = '$OWNER'" >/dev/null
curl -sS -N --max-time 120 "${H[@]}" "$ASK" | grep -m1 -c '^event: delta' | sed 's/^/  left after first delta: /' || true
sleep 20   # the AI call finishes on its own
echo "  balance: $(bal) (80)"
curl -fsS -N --max-time 120 "${H[@]}" "$ASK" | grep -c '^event: delta' | sed 's/^/  full answer deltas: /'
sleep 1
echo "  balance: $(bal) (60)"

echo "== fixed price ask, the AI call fails → credits back"
MODEL=$(q octopilot_t "select value::text from system_settings where key = 'primary_model'")
setting primary_model '"nobody/no-such-model"'
curl -fsS -N --max-time 60 "${H[@]}" "$ASK" | ev
sleep 1
echo "  balance: $(bal) (60)"
setting primary_model "$MODEL"
echo "  ledger (ask):"
q octopilot_t "select '    ' || entry_type || ' ' || amount || ' ' || reason from credit_ledger where user_id = '$OWNER' and source_ref like 'study:ask:%' order by created_at"

echo "== Idempotency-Key: create studio twice"
for i in 1 2; do
  curl -fsS -X POST "${H[@]}" -H 'Content-Type: application/json' -H 'Idempotency-Key: e2e-create-1' \
    -d '{"title":"Idem test"}' 127.0.0.1:8118/studios | grep '^data:' | head -1 | python3 -c 'import json,sys; print("  id", json.loads(sys.stdin.read()[5:])["id"])'
done
echo "  rows: $(q cockpit_t "select count(*) from studios where idempotency_key = 'e2e-create-1'") (1)"
NEW=$(q cockpit_t "select id from studios where idempotency_key = 'e2e-create-1'")

echo "== Idempotency-Key: upload twice"
printf 'Photosynthesis turns light into chemical energy.\n' > /tmp/idem.txt
for i in 1 2; do
  curl -fsS -X POST "${H[@]}" -H 'Idempotency-Key: e2e-file-1' -F 'file=@/tmp/idem.txt;type=text/plain' \
    "127.0.0.1:8118/studios/$NEW/documents" | python3 -c 'import json,sys; j=json.load(sys.stdin); print("  job", j["id"], "doc", j["document_id"])'
done
echo "  documents: $(q cockpit_t "select count(*) from documents where studio_id = '$NEW'") (1)"
curl -fsS -X DELETE "${H[@]}" "127.0.0.1:8118/studios/$NEW" >/dev/null

kill "$(cat credits-e2e.pid)"; rm -f credits-e2e.pid /tmp/idem.txt
for db in cockpit_t vector_t octopilot_t; do $P -d postgres -c "DROP DATABASE $db WITH (FORCE)" </dev/null; done
echo "cleaned up"
grep -iE "panic|error" credits-e2e.log | tail -3 || true

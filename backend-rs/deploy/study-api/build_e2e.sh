#!/usr/bin/env bash
# R5 end to end on throwaway copies: a real studio rebuilt by the Rust build
# worker (real OpenRouter calls on the build model, a few cents), killed
# mid-way and resumed, then the one-build-per-studio guard, ids kept, cost
# per build, connections / concepts made once under a double tap, create +
# delete studio. Prints counts and short excerpts only.
#   STUDIO=<uuid> to pick the studio (default: the smallest one with topics).
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
SID=${STUDIO:-$(q cockpit_t "select t.studio_id from generated_topics t join documents d on d.studio_id = t.studio_id and d.status = 'ready' group by 1 order by (select count(*) from generated_topics x where x.studio_id = t.studio_id) desc, 1 limit 1 offset 4")}
OWNER=$(q cockpit_t "select user_id from studios where id = '$SID'")
echo "studio: ${SID:0:8}… ($(q vector_t "select count(*) || ' passages, ' || sum(length(content)) || ' chars' from chunks where studio_id = '$SID'"))"
echo "before: $(q cockpit_t "select count(*) from generated_topics where studio_id = '$SID'") topics, $(q cockpit_t "select count(*) from generated_scenarios where studio_id = '$SID'") scenarios"
q cockpit_t "select payload->>'id' from generated_topics where studio_id = '$SID'" | sort > /tmp/b_old_topics
q cockpit_t "select c->>'id' from generated_topics t, jsonb_array_elements(t.payload->'flashcards') c where t.studio_id = '$SID'" | sort > /tmp/b_old_cards

BASE=$(sudo -n grep -E '^COCKPIT_DATABASE_URL=' /opt/cockpit/Backend/.env | cut -d= -f2- | sed -E 's#^postgresql\+asyncpg://#postgres://#; s#/cockpit$##')
VBASE=$(sudo -n grep -E '^VECTOR_DATABASE_URL=' /opt/cockpit/Backend/.env | cut -d= -f2- | sed -E 's#^postgresql\+asyncpg://#postgres://#; s#/vector$##')
start() {
  ( set -a; . ./shadow.env; set +a
    COCKPIT_DATABASE_URL="$BASE/cockpit_t" VECTOR_DATABASE_URL="$VBASE/vector_t" PORT=8115 BUILD_WORKER=1 \
    nohup ./bin/study-api >> build-e2e.log 2>&1 & echo $! > build-e2e.pid )
  for i in $(seq 1 30); do curl -fsS -o /dev/null 127.0.0.1:8115/health 2>/dev/null && break; sleep 1; done
}
: > build-e2e.log
start
H=(-H "X-User-Id: $OWNER")
bid() { python3 -c 'import json,sys; [print(json.loads(l[5:])["buildId"]) for l in sys.stdin if l.startswith("data:") and "buildId" in l]'; }

echo "== start twice (A1: one build per studio)"
B1=$(curl -fsS -X POST "${H[@]}" "127.0.0.1:8115/studios/$SID/build" | bid)
B2=$(curl -fsS -X POST "${H[@]}" "127.0.0.1:8115/studios/$SID/build" | bid)
echo "  first ${B1:0:8}  second ${B2:0:8}  same: $([ "$B1" = "$B2" ] && echo yes || echo NO)"
echo "  someone else's studio -> $(curl -fsS -X POST -H 'X-User-Id: 00000000-0000-0000-0000-000000000009' "127.0.0.1:8115/studios/$SID/build" | grep -A1 '^event:' | tr '\n' ' ' | cut -c1-90)"

echo "== kill it once two lessons are in, then restart (resume)"
for i in $(seq 1 240); do
  d=$(q cockpit_t "select lessons_done from studio_builds where id = '$B1'"); [ "${d:-0}" -ge 2 ] && break; sleep 1
done
echo "  at kill: $(q cockpit_t "select status || ' ' || lessons_done || '/' || lessons_total from studio_builds where id = '$B1'"), topics in studio: $(q cockpit_t "select count(*) from generated_topics where studio_id = '$SID'"), previous kept: $(q cockpit_t "select jsonb_array_length(previous) from studio_builds where id = '$B1'")"
kill "$(cat build-e2e.pid)"; sleep 1
start
echo "== progress after restart"
T0=$(date +%s)
curl -fsS -N --max-time 900 "${H[@]}" "127.0.0.1:8115/studios/$SID/build-status/$B1" | grep -E '^data:' | python3 -c '
import json,sys
for l in sys.stdin:
    d=json.loads(l[5:]); print("  ", d.get("status","?"), d.get("progressPct",""), (d.get("stage") or d.get("message",""))[:70])' | awk 'NR<=4 || /done|failed|scenarios|Studio ready/' | tail -8
echo "  finished in $(( $(date +%s) - T0 )) s after restart; snapshot: $(curl -fsS "${H[@]}" "127.0.0.1:8115/studios/$SID/build-status/$B1?snapshot=true" | grep '^data:' | head -1 | cut -c1-120)"

echo "== the rebuilt studio"
q cockpit_t "select payload->>'id' from generated_topics where studio_id = '$SID'" | sort > /tmp/b_new_topics
q cockpit_t "select c->>'id' from generated_topics t, jsonb_array_elements(t.payload->'flashcards') c where t.studio_id = '$SID'" | sort > /tmp/b_new_cards
echo "  topics: $(wc -l < /tmp/b_new_topics) (kept old id: $(comm -12 /tmp/b_old_topics /tmp/b_new_topics | wc -l)), unique ids: $(sort -u /tmp/b_new_topics | wc -l)"
echo "  cards: $(wc -l < /tmp/b_new_cards) (kept old id: $(comm -12 /tmp/b_old_cards /tmp/b_new_cards | wc -l))"
q cockpit_t "select ' ' || count(*) || ' lessons | quiz types ' || (select string_agg(distinct q->>'type', ',') from generated_topics x, jsonb_array_elements(x.payload->'quizQuestions') q where x.studio_id = '$SID') || ' | with concepts ' || count(*) filter (where jsonb_array_length(payload->'concepts') > 0) || ' | sources with page ' || (select count(*) filter (where s->>'page' is not null) || '/' || count(*) from generated_topics y, jsonb_array_elements(y.payload->'sources') s where y.studio_id = '$SID') from generated_topics where studio_id = '$SID'"
echo "  titles: $(q cockpit_t "select string_agg(payload->>'title', ' · ' order by ordinal) from generated_topics where studio_id = '$SID'" | cut -c1-200)"
echo "  scenarios: $(q cockpit_t "select count(*) from generated_scenarios where studio_id = '$SID'"); build row: $(q cockpit_t "select status || ', previous cleared: ' || (previous is null) from studio_builds where id = '$B1'")"
GOT=$(curl -fsS "${H[@]}" "127.0.0.1:8115/studios/$SID" | grep '^data:' | head -1 | python3 -c 'import json,sys; d=json.loads(sys.stdin.read()[5:]); print(len(d["topics"]), "topics,", len(d["scenarios"]), "scenarios")')
echo "  GET /studios/{id} reads back: $GOT"
echo "== cost of this build (both runs)"
q cockpit_t "select '  ' || feature || ' ×' || count(*) || '  ' || sum(prompt_tokens) || ' in / ' || sum(completion_tokens) || ' out  \$' || sum(cost_usd) from llm_usage where build_id = '$B1' group by feature order by feature"
q cockpit_t "select '  total \$' || sum(cost_usd) || ' — ' || max(model) from llm_usage where build_id = '$B1'"

echo "== rebuild once more (new build id; how many lessons and cards keep their ids)"
q cockpit_t "select payload->>'title' from generated_topics where studio_id = '$SID' order by ordinal" > /tmp/b_titles1
B3=$(curl -fsS -X POST "${H[@]}" "127.0.0.1:8115/studios/$SID/build" | bid)
echo "  new id: $([ "$B3" != "$B1" ] && echo yes || echo NO)"
curl -fsS -N --max-time 900 "${H[@]}" "127.0.0.1:8115/studios/$SID/build-status/$B3" | grep -E '^event: (done|error)' -A1 | tail -1 | cut -c1-100 | sed 's/^/  /'
q cockpit_t "select payload->>'id' from generated_topics where studio_id = '$SID'" | sort > /tmp/b_new2_topics
q cockpit_t "select c->>'id' from generated_topics t, jsonb_array_elements(t.payload->'flashcards') c where t.studio_id = '$SID'" | sort > /tmp/b_new2_cards
echo "  topics: $(wc -l < /tmp/b_new2_topics) (kept id: $(comm -12 /tmp/b_new_topics /tmp/b_new2_topics | wc -l)), cards: $(wc -l < /tmp/b_new2_cards) (kept id: $(comm -12 /tmp/b_new_cards /tmp/b_new2_cards | wc -l))"
q cockpit_t "select payload->>'title' from generated_topics where studio_id = '$SID' order by ordinal" > /tmp/b_titles2
echo "  titles 1: $(paste -sd'|' /tmp/b_titles1 | cut -c1-230)"
echo "  titles 2: $(paste -sd'|' /tmp/b_titles2 | cut -c1-230)"
q cockpit_t "select '  this build \$' || sum(cost_usd) || ' (' || count(*) || ' calls, ' || sum(prompt_tokens) || ' in / ' || sum(completion_tokens) || ' out)' from llm_usage where build_id = '$B3'"

echo "== connections, double tap (one call)"
q cockpit_t "update generated_topics set payload = payload - 'prerequisites' - 'relatesTo' where studio_id = '$SID'" >/dev/null
( curl -fsS -X POST "${H[@]}" "127.0.0.1:8115/studios/$SID/connections" | grep '^data:' > /tmp/b_c1 ) &
( curl -fsS -X POST "${H[@]}" "127.0.0.1:8115/studios/$SID/connections" | grep '^data:' > /tmp/b_c2 ) &
wait
echo "  $(cat /tmp/b_c1) | $(cat /tmp/b_c2) | calls: $(q cockpit_t "select count(*) from llm_usage where feature = 'connections' and studio_id = '$SID'")"
echo "== concepts, double tap (one call)"
TID=$(q cockpit_t "select payload->>'id' from generated_topics where studio_id = '$SID' order by ordinal limit 1")
q cockpit_t "update generated_topics set payload = payload - 'concepts' - 'conceptLinks' where payload->>'id' = '$TID'" >/dev/null
( curl -fsS -X POST "${H[@]}" "127.0.0.1:8115/studios/$SID/topics/$TID/concepts" | grep '^data:' > /tmp/b_k1 ) &
( curl -fsS -X POST "${H[@]}" "127.0.0.1:8115/studios/$SID/topics/$TID/concepts" | grep '^data:' > /tmp/b_k2 ) &
wait
echo "  $(cat /tmp/b_k1) | $(cat /tmp/b_k2) | calls: $(q cockpit_t "select count(*) from llm_usage where feature = 'concepts' and studio_id = '$SID'") | concepts now: $(q cockpit_t "select jsonb_array_length(payload->'concepts') from generated_topics where payload->>'id' = '$TID'")"
q cockpit_t "select '  sonnet calls \$' || sum(cost_usd) from llm_usage where feature in ('connections','concepts')"

echo "== create + build with no files + delete"
NEW=$(curl -fsS -X POST "${H[@]}" -H 'Content-Type: application/json' -d '{"title":"  E2E studio ","subject":"Test"}' 127.0.0.1:8115/studios | grep '^data:' | head -1 | python3 -c 'import json,sys; d=json.loads(sys.stdin.read()[5:]); print(d["id"], d["title"], d["subject"], len(d["topics"]), sep="|")')
NID=${NEW%%|*}; echo "  created: $NEW"
B4=$(curl -fsS -X POST "${H[@]}" "127.0.0.1:8115/studios/$NID/build" | bid)
curl -fsS -N --max-time 60 "${H[@]}" "127.0.0.1:8115/studios/$NID/build-status/$B4" | grep -A1 '^event: error' | tail -1 | sed 's/^/  build with no files: /'
echo "  delete: $(curl -fsS -X DELETE "${H[@]}" "127.0.0.1:8115/studios/$NID" | grep '^data:') | again: $(curl -fsS -X DELETE "${H[@]}" "127.0.0.1:8115/studios/$NID" | grep -A1 '^event:' | tail -1)"
echo "  rows left: $(q cockpit_t "select count(*) from studios where id = '$NID'") studio, $(q cockpit_t "select count(*) from studio_builds where studio_id = '$NID'") builds"

kill "$(cat build-e2e.pid)"; rm -f build-e2e.pid /tmp/b_*
for db in cockpit_t vector_t; do $P -d postgres -c "DROP DATABASE $db WITH (FORCE)" </dev/null; done
echo "cleaned up (process, throwaway databases)"
grep -hiE "warn|error|panic" build-e2e.log | cut -c1-220 | tail -5 || true

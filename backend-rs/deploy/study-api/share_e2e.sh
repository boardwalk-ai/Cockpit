#!/usr/bin/env bash
# Share links on throwaway copies: turn on (twice → one link), preview,
# copy by another user (twice with one key → one copy), the copy's ids are
# new and its progress is its own, its passages are searchable, turning the
# link off stops new copies but keeps the made one, deleting the copy leaves
# the original's files alone. No AI calls.
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
read -r OWNER SID < <(q vector_t "select user_id, studio_id from chunks group by 1,2 order by count(*) desc limit 1" | tr '|' ' ')
OTHER=$(q cockpit_t "select user_id from studios where user_id <> '$OWNER' limit 1")
url() { grep -E "^$1=" app.env | cut -d= -f2- | sed -E "s#/[a-z_]+\$#/$2#"; }
( set -a; . ./app.env; set +a
  COCKPIT_DATABASE_URL=$(url COCKPIT_DATABASE_URL cockpit_t) VECTOR_DATABASE_URL=$(url VECTOR_DATABASE_URL vector_t) \
  FIREBASE_PROJECT_ID= PORT=8121 MIGRATE=1 INGEST_WORKER=0 BUILD_WORKER=0 NOTIFY_WORKER=0 LOG_FORMAT=text \
  nohup "${BIN:-./bin/study-api}" > share-e2e.log 2>&1 & echo $! > share-e2e.pid )
for i in $(seq 1 30); do curl -fsS -o /dev/null 127.0.0.1:8121/health 2>/dev/null && break; sleep 1; done
A=(-H "X-User-Id: $OWNER"); B=(-H "X-User-Id: $OTHER")
ev() { grep -E '^(event|data):' | paste - - | grep -v 'event: done' | sed 's/event: //; s/\tdata: / /' | cut -c1-170; }
field() { grep '^data:' | head -1 | python3 -c "import json,sys; print(json.loads(sys.stdin.read()[5:]).get('$1'))"; }

echo "== owner: no link yet, turn on twice, someone else can't"
curl -fsS "${A[@]}" 127.0.0.1:8121/studios/$SID/share | ev
C1=$(curl -fsS -X POST "${A[@]}" 127.0.0.1:8121/studios/$SID/share | field code)
C2=$(curl -fsS -X POST "${A[@]}" 127.0.0.1:8121/studios/$SID/share | field code)
echo "  codes: $C1 $C2 (same: $([ "$C1" = "$C2" ] && echo yes || echo NO))"
curl -fsS -X POST "${B[@]}" 127.0.0.1:8121/studios/$SID/share | ev

echo "== preview by another user"
curl -fsS "${B[@]}" 127.0.0.1:8121/shares/$C1 | ev
curl -fsS "${B[@]}" 127.0.0.1:8121/shares/nope123456 | ev

echo "== copy twice with one key"
N1=$(curl -fsS -X POST "${B[@]}" -H 'Idempotency-Key: k1' 127.0.0.1:8121/shares/$C1/copy | field id)
N2=$(curl -fsS -X POST "${B[@]}" -H 'Idempotency-Key: k1' 127.0.0.1:8121/shares/$C1/copy | field id)
echo "  copies: $N1 $N2 (same: $([ "$N1" = "$N2" ] && echo yes || echo NO)); counter $(q cockpit_t "select copies from studio_shares where code = '$C1'")"
echo "  lessons src/copy: $(q cockpit_t "select count(*) from generated_topics where studio_id = '$SID'") / $(q cockpit_t "select count(*) from generated_topics where studio_id = '$N1' and user_id = '$OTHER'")"
echo "  topic ids shared with the original: $(q cockpit_t "select count(*) from generated_topics a join generated_topics b on a.payload->>'id' = b.payload->>'id' where a.studio_id = '$SID' and b.studio_id = '$N1'") (0)"
echo "  card ids shared: $(q cockpit_t "select count(*) from (select jsonb_array_elements(payload->'flashcards')->>'id' i from generated_topics where studio_id = '$SID') a join (select jsonb_array_elements(payload->'flashcards')->>'id' i from generated_topics where studio_id = '$N1') b using (i)") (0)"
echo "  scenarios src/copy: $(q cockpit_t "select count(*) from generated_scenarios where studio_id = '$SID'") / $(q cockpit_t "select count(*) from generated_scenarios where studio_id = '$N1'")"
echo "  docs: $(q cockpit_t "select count(*) || ' with no file: ' || count(*) filter (where object_key = '') from documents where studio_id = '$N1'")"
echo "  passages src/copy: $(q vector_t "select count(*) from chunks where studio_id = '$SID'") / $(q vector_t "select count(*) from chunks where studio_id = '$N1' and user_id = '$OTHER'")"
echo "  orphan passages (doc not in copy): $(for d in $(q vector_t "select distinct document_id from chunks where studio_id = '$N1'"); do q cockpit_t "select count(*) from documents where id = '$d' and studio_id = '$N1'"; done | grep -c '^0$' || true) (0)"
echo "  shared by: $(curl -fsS "${B[@]}" 127.0.0.1:8121/studios/$N1 | field sharedBy)"
H=$(curl -fsS "127.0.0.1:8121/search?user_id=$OTHER&studio_id=$N1&q=$(python3 -c 'import urllib.parse;print(urllib.parse.quote("what is this about"))')" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["hits"]))')
echo "  search on the copy: $H hits"
curl -fsS "127.0.0.1:8121/search?user_id=$OTHER&studio_id=$N1&q=what%20is%20this%20about" | cut -c1-200; echo

echo "== the copy's progress is its own"
TID=$(q cockpit_t "select payload->>'id' from generated_topics where studio_id = '$N1' order by ordinal limit 1")
curl -fsS -X POST "${B[@]}" "127.0.0.1:8121/studios/$N1/topics/$TID/quiz-result?correct=true" >/dev/null
echo "  progress rows on copy/original: $(q cockpit_t "select count(*) from topic_progress where studio_id = '$N1'") / $(q cockpit_t "select count(*) from topic_progress where studio_id = '$SID' and user_id = '$OTHER'")"

echo "== turn off: no new copies, the made one stays"
curl -fsS -X DELETE "${A[@]}" 127.0.0.1:8121/studios/$SID/share | ev
curl -fsS "${B[@]}" 127.0.0.1:8121/shares/$C1 | ev
curl -fsS -X POST "${B[@]}" -H 'Idempotency-Key: k2' 127.0.0.1:8121/shares/$C1/copy | ev
echo "  copy still there: $(q cockpit_t "select count(*) from studios where id = '$N1'")"
C3=$(curl -fsS -X POST "${A[@]}" 127.0.0.1:8121/studios/$SID/share | field code)
echo "  turned on again → new code: $([ "$C3" != "$C1" ] && echo yes || echo NO)"

echo "== delete the copy: the original's files stay"
before=$(q cockpit_t "select count(*) from documents where studio_id = '$SID' and object_key <> ''")
curl -fsS -X DELETE "${B[@]}" 127.0.0.1:8121/studios/$N1 | ev
echo "  original docs with files: $before → $(q cockpit_t "select count(*) from documents where studio_id = '$SID' and object_key <> ''"); copy passages left: $(q vector_t "select count(*) from chunks where studio_id = '$N1'")"
grep -c "delete object" share-e2e.log | sed 's/^/  object deletes attempted: /'

kill "$(cat share-e2e.pid)"; rm -f share-e2e.pid
for db in cockpit_t vector_t; do $P -d postgres -c "DROP DATABASE $db WITH (FORCE)" </dev/null; done
echo "cleaned up"
grep -iE "panic|error" share-e2e.log | grep -v "delete object" | tail -3 || true

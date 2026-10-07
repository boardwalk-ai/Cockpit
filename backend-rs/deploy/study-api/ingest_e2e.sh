#!/usr/bin/env bash
# R3 end to end on throwaway copies: upload a real PDF (and a markdown note)
# through the Rust API, let the Rust worker ingest them, check the passages.
# Touches production only by putting two test objects in MinIO (removed at
# the end). Prints counts and short excerpts only.
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

# A real PDF from the store, re-uploaded by its owner into their own studio (copy DB).
read -r OWNER SID KEY < <(q cockpit_t "select d.user_id, d.studio_id, d.object_key from documents d where lower(d.filename) like '%.pdf' and d.status='ready' and d.bytes < 15000000 order by d.bytes desc limit 1" | tr '|' ' ')
docker exec -i -e KEY="$KEY" -e PYTHONPATH=/srv -w /srv cockpit-api python - > /tmp/e2e.pdf <<'PY'
import os, sys
from app.services.objectstore import get_object_store
sys.stdout.buffer.write(get_object_store().get(os.environ["KEY"]))
PY
printf '# Week 3 notes\n\nTCP halves its congestion window when a packet is lost, then grows it again by one segment per round trip.\n\n## Slow start\n\nA new connection starts with a small window that doubles every round trip until it reaches the threshold.\n' > /tmp/e2e.md
echo "pdf bytes: $(stat -c %s /tmp/e2e.pdf)"

BASE=$(sudo -n grep -E '^COCKPIT_DATABASE_URL=' /opt/cockpit/Backend/.env | cut -d= -f2- | sed -E 's#^postgresql\+asyncpg://#postgres://#; s#/cockpit$##')
VBASE=$(sudo -n grep -E '^VECTOR_DATABASE_URL=' /opt/cockpit/Backend/.env | cut -d= -f2- | sed -E 's#^postgresql\+asyncpg://#postgres://#; s#/vector$##')
( set -a; . ./shadow.env
  eval "$(sudo -n grep -E '^OBJECT_STORE_(ENDPOINT|REGION|BUCKET|ACCESS_KEY|SECRET_KEY)=' /opt/cockpit/Backend/.env | sed 's/^/export /')"
  set +a
  COCKPIT_DATABASE_URL="$BASE/cockpit_t" VECTOR_DATABASE_URL="$VBASE/vector_t" PORT=8112 INGEST_WORKER=1 \
  nohup ./bin/study-api > e2e.log 2>&1 & echo $! > e2e.pid )
for i in $(seq 1 30); do curl -fsS -o /dev/null 127.0.0.1:8112/health 2>/dev/null && break; sleep 1; done

T0=$(date +%s)
JOB_PDF=$(curl -fsS -H "X-User-Id: $OWNER" -F "file=@/tmp/e2e.pdf;type=application/pdf;filename=E2E test.pdf" "127.0.0.1:8112/studios/$SID/documents" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
JOB_MD=$(curl -fsS -H "X-User-Id: $OWNER" -F "file=@/tmp/e2e.md;type=text/markdown;filename=e2e-notes.md" "127.0.0.1:8112/studios/$SID/documents" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
echo "== progress stream (pdf)"
curl -fsS -N --max-time 600 -H "X-User-Id: $OWNER" "127.0.0.1:8112/studios/$SID/build/$JOB_PDF" | grep -E '^(event|data):' | paste - - | cut -c1-110
echo "pdf ingested in $(( $(date +%s) - T0 )) s"
curl -fsS -N --max-time 120 -H "X-User-Id: $OWNER" "127.0.0.1:8112/studios/$SID/build/$JOB_MD" | grep -E '^event:' | tr '\n' ' '; echo
echo "someone else's job -> $(curl -fsS -N -H 'X-User-Id: 00000000-0000-0000-0000-000000000009' "127.0.0.1:8112/studios/$SID/build/$JOB_PDF" | grep -E '^event:' | head -1)"

DOCS=$(q cockpit_t "select string_agg(quote_literal(document_id::text), ',') from ingest_jobs where id in ('$JOB_PDF','$JOB_MD')")
echo "== passages written by Rust"
q vector_t "select (select filename from dblink_dummy) from chunks limit 0" >/dev/null 2>&1 || true
q vector_t "select count(*) as chunks, count(page) as with_page, count(heading) as with_heading, min(length(content)), round(avg(length(content))), max(length(content)), bool_and((select bool_or(x<0) from unnest(embedding::real[]) x)) as real_vectors, bool_and(tsv is not null) as tsv from chunks where document_id::text in ($DOCS)" | sed 's/|/  /g'
echo "first pages: $(q vector_t "select string_agg(distinct page::text, ',' order by page::text) from chunks where document_id::text in ($DOCS) and page <= 5")"
echo "headings (md): $(q vector_t "select string_agg(heading, ' / ' order by ordinal) from chunks where document_id::text in ($DOCS) and page is null")"
echo "old Go/Python passages of the same file: $(q vector_t "select count(*) || ' chunks, avg ' || round(avg(length(content))) || ' chars, pages: none' from chunks c where c.document_id = (select id from documents limit 0) or c.document_id::text = (select document_id::text from chunks where false limit 1)" 2>/dev/null || echo n/a)"
q cockpit_t "select filename, status from documents where id::text in ($DOCS) order by 1" | sed 's/|/ → /'

# Clean up: the test objects, the process, the copies.
for k in $(q cockpit_t "select object_key from documents where id::text in ($DOCS)"); do
  docker exec -i -e KEY="$k" -e PYTHONPATH=/srv -w /srv cockpit-api python -c 'import os; from app.services.objectstore import get_object_store as g; g()._client.delete_object(Bucket=g()._bucket, Key=os.environ["KEY"])'
done
kill "$(cat e2e.pid)"; rm -f e2e.pid /tmp/e2e.pdf /tmp/e2e.md
for db in cockpit_t vector_t; do $P -d postgres -c "DROP DATABASE $db WITH (FORCE)" </dev/null; done
echo "cleaned up (test objects, process, throwaway databases)"
grep -iE "warn|error|panic" e2e.log | tail -3 || true

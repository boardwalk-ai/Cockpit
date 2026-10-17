#!/usr/bin/env bash
# Runs bench.py on throwaway copies of the cockpit + vector databases with a
# study-api that builds with MODEL (BUILD_MODEL) and has its ingest + build
# workers on. Nothing touches production rows.
#
#   bash bench.sh MODEL LABEL FILE [FILE …]
set -euo pipefail
MODEL=$1; LABEL=$2; shift 2
cd /opt/study-api
NIGHT=$(ls -1d /opt/backups/nightly/*/ | tail -1)
P="docker exec octo-pg psql -U octo_admin -v ON_ERROR_STOP=1 -q"
q() { docker exec octo-pg psql -U octo_admin -d "$1" -Atc "$2" </dev/null; }
for pair in cockpit_t:cockpit vector_t:vector; do
  db=${pair%%:*}; src=${pair##*:}
  $P -d postgres -c "DROP DATABASE IF EXISTS $db WITH (FORCE)" -c "CREATE DATABASE $db OWNER $src" </dev/null 2>&1 | grep -v NOTICE || true
  docker exec -i octo-pg pg_restore -U octo_admin -d "$db" --exit-on-error < "$NIGHT$src.dump"
done
OWNER=$(q cockpit_t "select user_id from studios group by 1 order by count(*) desc limit 1")
url() { grep -E "^$1=" app.env | cut -d= -f2- | sed -E "s#/[a-z_]+\$#/$2#"; }
BENCH_PORT=8122
( set -a; . ./app.env; set +a
  COCKPIT_DATABASE_URL=$(url COCKPIT_DATABASE_URL cockpit_t) VECTOR_DATABASE_URL=$(url VECTOR_DATABASE_URL vector_t) \
  FIREBASE_PROJECT_ID= PORT=$BENCH_PORT MIGRATE=1 INGEST_WORKER=1 BUILD_WORKER=1 NOTIFY_WORKER=0 FCM_SERVICE_ACCOUNT_FILE= \
  BUILD_MODEL="$MODEL" LOG_FORMAT=text nohup "${BIN:-./bin/study-api}" > "bench/$LABEL.log" 2>&1 & echo $! > bench.pid )
trap 'kill "$(cat bench.pid)" 2>/dev/null; rm -f bench.pid; for db in cockpit_t vector_t; do docker exec octo-pg psql -U octo_admin -d postgres -q -c "DROP DATABASE IF EXISTS $db WITH (FORCE)" </dev/null 2>&1 | grep -v NOTICE || true; done' EXIT
for i in $(seq 1 30); do curl -fsS -o /dev/null 127.0.0.1:$BENCH_PORT/health 2>/dev/null && break; sleep 1; done
mkdir -p bench/results
echo "== $LABEL: build model $MODEL"
python3 src/deploy/study-api/bench.py --api http://127.0.0.1:$BENCH_PORT --user "$OWNER" --label "$LABEL" --out bench/results "$@"

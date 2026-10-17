#!/usr/bin/env bash
# Upload → passages → TEI vectors → ready, on throwaway copies (no Python):
# a study-api with its ingest worker takes a small text file, and every
# passage must land with a vector equal to TEI's for the same text.
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
OWNER=$(q cockpit_t "select user_id from studios limit 1")
url() { grep -E "^$1=" app.env | cut -d= -f2- | sed -E "s#/[a-z_]+\$#/$2#"; }
( set -a; . ./app.env; set +a
  COCKPIT_DATABASE_URL=$(url COCKPIT_DATABASE_URL cockpit_t) VECTOR_DATABASE_URL=$(url VECTOR_DATABASE_URL vector_t) \
  FIREBASE_PROJECT_ID= PORT=8120 MIGRATE=1 INGEST_WORKER=1 BUILD_WORKER=0 NOTIFY_WORKER=0 LOG_FORMAT=text \
  nohup ./bin/study-api > embed-e2e.log 2>&1 & echo $! > embed-e2e.pid )
for i in $(seq 1 30); do curl -fsS -o /dev/null 127.0.0.1:8120/health 2>/dev/null && break; sleep 1; done
echo "ready: $(curl -s 127.0.0.1:8120/ready)"
H=(-H "X-User-Id: $OWNER")
SID=$(curl -fsS -X POST "${H[@]}" -H 'Content-Type: application/json' -d '{"title":"Embed test"}' 127.0.0.1:8120/studios \
  | grep '^data:' | head -1 | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()[5:])["id"])')
python3 - > /tmp/embed-e2e.txt <<'PY'
topics = ["Photosynthesis", "Cellular respiration", "The Krebs cycle", "Mitosis"]
for t in topics:
    print(f"# {t}\n")
    print((f"{t} is a core process in biology. " * 3 + "It moves energy and matter through living cells, and each stage depends on the one before. ") * 6)
    print()
PY
T0=$(date +%s)
JOB=$(curl -fsS -X POST "${H[@]}" -F 'file=@/tmp/embed-e2e.txt;type=text/plain' "127.0.0.1:8120/studios/$SID/documents" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
for i in $(seq 1 90); do
  st=$(q cockpit_t "select status from ingest_jobs where id = '$JOB'")
  case $st in done|failed) break;; esac; sleep 2
done
echo "job: $st in $(( $(date +%s) - T0 )) s ($(q cockpit_t "select coalesce(error,'') from ingest_jobs where id = '$JOB'"))"
echo "passages: $(q vector_t "select count(*) || ' (' || count(embedding) || ' with vectors)' from chunks where studio_id = '$SID'")"
# The stored vector of the first passage = TEI's vector for the same text?
read -r CID < <(q vector_t "select id from chunks where studio_id = '$SID' order by ordinal limit 1")
q vector_t "select json_build_object('c', content, 'h', heading, 'e', embedding::text) from chunks where id = '$CID'" > /tmp/embed-e2e.json
python3 - <<'PY'
import json, urllib.request
r = json.load(open("/tmp/embed-e2e.json"))
text = f"{r['h']}\n{r['c']}" if r["h"] else r["c"]
req = urllib.request.Request("http://127.0.0.1:8093/embed", data=json.dumps({"inputs": [text], "normalize": True, "truncate": True}).encode(),
                             headers={"Content-Type": "application/json"})
v = json.load(urllib.request.urlopen(req))[0]
s = json.loads(r["e"])
dot = sum(a * b for a, b in zip(v, s))
print(f"stored vs TEI cosine: {dot:.5f} | heading: {r['h']!r}")
PY
curl -fsS -X DELETE "${H[@]}" "127.0.0.1:8120/studios/$SID" >/dev/null   # its file in MinIO too
kill "$(cat embed-e2e.pid)"; rm -f embed-e2e.pid /tmp/embed-e2e.txt /tmp/embed-e2e.json
for db in cockpit_t vector_t; do $P -d postgres -c "DROP DATABASE $db WITH (FORCE)" </dev/null; done
echo "cleaned up"
grep -iE "panic|error" embed-e2e.log | tail -3 || true

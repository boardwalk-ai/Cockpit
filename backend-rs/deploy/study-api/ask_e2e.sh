#!/usr/bin/env bash
# R4 end to end on throwaway copies: Ask AI through the Rust API (two real
# OpenRouter calls, ~3 cents), the embedder-down fallback, ownership, and
# how the Rust hybrid search overlaps the Go search on the same question.
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
QUESTION=$(q vector_t "select substring(content from 1 for 400) from chunks where studio_id='$SID' order by ordinal limit 1 offset 1" | python3 -c 'import sys,re; t=re.sub(r"\s+"," ",sys.stdin.read()).split(" "); print("Explain: " + " ".join(t[10:22]))')
echo "question: ${QUESTION:0:60}…"

BASE=$(sudo -n grep -E '^COCKPIT_DATABASE_URL=' /opt/cockpit/Backend/.env | cut -d= -f2- | sed -E 's#^postgresql\+asyncpg://#postgres://#; s#/cockpit$##')
VBASE=$(sudo -n grep -E '^VECTOR_DATABASE_URL=' /opt/cockpit/Backend/.env | cut -d= -f2- | sed -E 's#^postgresql\+asyncpg://#postgres://#; s#/vector$##')
start() {  # port embed_url
  ( set -a; . ./shadow.env; set +a
    COCKPIT_DATABASE_URL="$BASE/cockpit_t" VECTOR_DATABASE_URL="$VBASE/vector_t" PORT=$1 MIGRATE=1 EMBED_SERVICE_URL=$2 \
    nohup ./bin/study-api > ask-$1.log 2>&1 & echo $! > ask-$1.pid )
  for i in $(seq 1 30); do curl -fsS -o /dev/null 127.0.0.1:$1/health 2>/dev/null && break; sleep 1; done
}
EMBED=$(grep -E '^EMBED_SERVICE_URL=' shadow.env | cut -d= -f2-)
start 8113 "$EMBED"
start 8114 "http://127.0.0.1:9"   # nothing listens: the embedder is "down"

ENC=$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$QUESTION")
summ() { awk '/^event:/{e=$2} /^data:/{n[e]++; if(e=="meta"||e=="error") m[e]=substr($0,7,90)} END{for(k in n) printf "%s×%d ", k, n[k]; print ""; for(k in m) print "  " k ": " m[k]}'; }
echo "== normal"
T0=$(date +%s.%N); curl -fsS -N --max-time 120 -H "X-User-Id: $OWNER" "127.0.0.1:8113/ask?studio_id=$SID&q=$ENC" > /tmp/ask1.txt
echo "  first byte to done: $(python3 -c "print(round($(date +%s.%N)-$T0,1))") s"; summ < /tmp/ask1.txt
grep -A1 '^event: citations' /tmp/ask1.txt | grep '^data:' | python3 -c 'import json,sys; c=json.loads(sys.stdin.read()[5:]); print("  citations:", len(c), "| fileName set:", all(x.get("fileName") for x in c), "| page key present:", all("page" in x for x in c))'
echo "  answer starts: $(grep '^data:' /tmp/ask1.txt | grep '"text"' | head -12 | python3 -c 'import json,sys; print("".join(json.loads(l[5:])["text"] for l in sys.stdin)[:120])')"
echo "  metered: $(q cockpit_t "select feature, model, prompt_tokens, completion_tokens, cost_usd from llm_usage order by created_at desc limit 1")"
echo "== embedder down"
curl -fsS -N --max-time 120 -H "X-User-Id: $OWNER" "127.0.0.1:8114/ask?studio_id=$SID&q=$ENC" | summ
echo "== someone else's studio"
curl -fsS -N -H "X-User-Id: 00000000-0000-0000-0000-000000000009" "127.0.0.1:8113/ask?studio_id=$SID&q=hello" | summ
echo "== too long"
LONGQ=$(python3 -c 'print("a"*2001)'); curl -fsS -N -H "X-User-Id: $OWNER" "127.0.0.1:8113/ask?studio_id=$SID&q=$LONGQ" | summ

echo "== Rust hybrid vs Go search (top 5, same question)"
GO=$(curl -fsS -X POST 127.0.0.1:8092/search -H 'Content-Type: application/json' -d "{\"user_id\":\"$OWNER\",\"studio_id\":\"$SID\",\"query\":$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$QUESTION"),\"top_k\":5}" | python3 -c 'import json,sys; print(" ".join(sorted(str(h["ordinal"]) for h in json.load(sys.stdin)["hits"] or [])))')
RS=$(grep -A1 '^event: citations' /tmp/ask1.txt | grep '^data:' | python3 -c 'import json,sys; print(" ".join(sorted(str(x["ordinal"]) for x in json.loads(sys.stdin.read()[5:])[:5])))')
echo "  go: $GO"; echo "  rs: $RS"

for p in 8113 8114; do kill "$(cat ask-$p.pid)"; rm -f ask-$p.pid; done
rm -f /tmp/ask1.txt
for db in cockpit_t vector_t; do $P -d postgres -c "DROP DATABASE $db WITH (FORCE)" </dev/null; done
echo "cleaned up"
grep -hiE "warn|error|panic" ask-8113.log ask-8114.log | tail -3 || true

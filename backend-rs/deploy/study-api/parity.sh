#!/usr/bin/env bash
# R2 parity: the same writes through Python and through Rust, each on its
# own throwaway copy of the cockpit DB; compare the resulting rows. Then
# Rust-only checks: a retried event changes nothing; "Got it" counts once.
set -euo pipefail
DUMP=$(ls -1d /opt/backups/nightly/*/ | tail -1)cockpit.dump
P="docker exec octo-pg psql -U octo_admin -v ON_ERROR_STOP=1 -q"
for db in cockpit_py cockpit_rs; do
  $P -d postgres -c "DROP DATABASE IF EXISTS $db WITH (FORCE)" -c "CREATE DATABASE $db OWNER cockpit" </dev/null
  docker exec -i octo-pg pg_restore -U octo_admin -d "$db" --exit-on-error < "$DUMP"
done
q() { docker exec octo-pg psql -U octo_admin -d "$1" -Atc "$2" </dev/null; }

# A studio with a topic that has a flashcard.
read -r SID OWNER TID CID < <(q cockpit_rs "select t.studio_id, s.user_id, t.payload->>'id', t.payload->'flashcards'->0->>'id' from generated_topics t join studios s on s.id=t.studio_id where jsonb_array_length(t.payload->'flashcards')>0 order by t.studio_id, t.ordinal limit 1" | tr '|' ' ')
echo "studio ${SID:0:8} topic $TID card $CID"

BASE=$(sudo -n grep -E '^COCKPIT_DATABASE_URL=' /opt/cockpit/Backend/.env | cut -d= -f2- | sed -E 's#/cockpit$##')

# --- Python ------------------------------------------------------------------
docker exec -i -e COCKPIT_DATABASE_URL="$BASE/cockpit_py" -e PYTHONPATH=/srv -w /srv cockpit-api python - "$SID" "$OWNER" "$TID" "$CID" <<'PY'
import asyncio, sys, uuid
from app.db import CockpitSession
from app.services import activity, progress, schedule
sid, uid, tid, cid = uuid.UUID(sys.argv[1]), uuid.UUID(sys.argv[2]), sys.argv[3], sys.argv[4]
async def main():
    async with CockpitSession() as c:
        for ok in (True, False):
            await progress.record_quiz(c, user_id=uid, studio_id=sid, topic_id=tid, correct=ok)
            await activity.log(c, user_id=uid, studio_id=sid, topic_id=tid, kind="quiz", correct=ok)
        await progress.record_flashcard(c, user_id=uid, studio_id=sid, topic_id=tid, quality=0.75)
        await activity.log(c, user_id=uid, studio_id=sid, topic_id=tid, kind="card", correct=True)
        for g in (2, 2, 3, 0):
            await schedule.record(c, user_id=uid, studio_id=sid, topic_id=tid, card_id=cid, grade=g)
            await progress.record_flashcard(c, user_id=uid, studio_id=sid, topic_id=tid, quality=g / 3)
            await activity.log(c, user_id=uid, studio_id=sid, topic_id=tid, kind="card", correct=g >= 2)
        await progress.record_reviewed(c, user_id=uid, studio_id=sid, topic_id=tid)
asyncio.run(main())
PY

# --- Rust --------------------------------------------------------------------
cd /opt/study-api
( set -a; . ./shadow.env; set +a
  COCKPIT_DATABASE_URL=$(echo "$BASE/cockpit_rs" | sed -E 's#^postgresql\+asyncpg://#postgres://#') PORT=8111 \
  nohup ./bin/study-api > parity.log 2>&1 & echo $! > parity.pid )
for i in $(seq 1 30); do curl -fsS -o /dev/null 127.0.0.1:8111/health 2>/dev/null && break; sleep 1; done
R="curl -fsS -X POST -H X-User-Id:$OWNER"
EV=$(cat /proc/sys/kernel/random/uuid)
$R "127.0.0.1:8111/studios/$SID/topics/$TID/quiz-result?correct=true&event_id=$EV" >/dev/null
$R "127.0.0.1:8111/studios/$SID/topics/$TID/quiz-result?correct=false" >/dev/null
$R "127.0.0.1:8111/studios/$SID/topics/$TID/flashcard-review?quality=0.75" >/dev/null
for g in 2 2 3 0; do $R "127.0.0.1:8111/studios/$SID/flashcards/$CID/review?topic_id=$TID&grade=$g" >/dev/null; done
$R "127.0.0.1:8111/studios/$SID/topics/$TID/mark-reviewed" >/dev/null

echo "== compare (python vs rust)"
PROG="select round(mastery::numeric,6), quiz_attempts, quiz_correct, flashcard_reviews, reviews from topic_progress where user_id='$OWNER' and topic_id='$TID'"
CARD="select reps, interval_days, ease, lapses from flashcard_schedule where user_id='$OWNER' and card_id='$CID'"
EVS="select kind||':'||correct||':'||count(*) from study_events where user_id='$OWNER' and topic_id='$TID' and kind in ('card','quiz') group by kind, correct order by 1"
for name in PROG CARD EVS; do
  a=$(q cockpit_py "${!name}"); b=$(q cockpit_rs "${!name}")
  [ "$a" = "$b" ] && echo "same  $name: $a" | tr '\n' ' ' || { echo "DIFF  $name"; echo " py: $a"; echo " rs: $b"; }
  echo
done
DUE="select abs(extract(epoch from (p.due_at - r.due_at))) < 120 from flashcard_schedule p, flashcard_schedule r where p.card_id='$CID' and r.card_id='$CID'"
echo "due dates within 2 min: $(docker exec octo-pg psql -U octo_admin -d cockpit_py -Atc "select due_at from flashcard_schedule where card_id='$CID'" | head -1 | cut -c1-16) vs $(q cockpit_rs "select due_at from flashcard_schedule where card_id='$CID'" | cut -c1-16)"

echo "== rust only"
before=$(q cockpit_rs "$PROG")
$R "127.0.0.1:8111/studios/$SID/topics/$TID/quiz-result?correct=true&event_id=$EV" >/dev/null
[ "$(q cockpit_rs "$PROG")" = "$before" ] && echo "retried quiz event: no change ✓" || echo "retried quiz event CHANGED ✗"
$R "127.0.0.1:8111/studios/$SID/topics/$TID/mark-reviewed" >/dev/null
[ "$(q cockpit_rs "$PROG")" = "$before" ] && echo "second Got it today: no change ✓" || echo "second Got it CHANGED ✗"
other=$(curl -fsS -X POST -H X-User-Id:00000000-0000-0000-0000-000000000009 "127.0.0.1:8111/studios/$SID/topics/$TID/quiz-result?correct=true" >/dev/null; q cockpit_rs "$PROG")
[ "$other" = "$before" ] && echo "another user's write ignored ✓" || echo "another user's write APPLIED ✗"
echo "activity: $(curl -fsS -H X-User-Id:$OWNER "127.0.0.1:8111/studios/$SID/activity?days=2&tz=390" | grep '^data:' | cut -c1-120)"
echo "rename: $(curl -fsS -X POST -H X-User-Id:$OWNER "127.0.0.1:8111/studios/$SID/rename?title=%20%20Parity%20%20test%20" | grep '^data:')"

kill "$(cat parity.pid)"; rm -f parity.pid
for db in cockpit_py cockpit_rs; do $P -d postgres -c "DROP DATABASE $db WITH (FORCE)" </dev/null; done
echo "throwaway databases dropped"

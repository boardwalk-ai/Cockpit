#!/usr/bin/env bash
# Uploads a big file to the server in 10 MB pieces, each retried, so a slow
# or dropping link only repeats one piece. Joins them and checks the SHA-256.
#   bash upload-chunked.sh LOCAL_FILE REMOTE_PATH
set -euo pipefail
LOCAL=$1; REMOTE=$2; HOST=octopilot-vps
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
split -b 10m -d -a 3 "$LOCAL" "$TMP/p."
RDIR="$REMOTE.chunks"
ssh -o ConnectTimeout=20 $HOST "mkdir -p '$RDIR'"
for f in "$TMP"/p.*; do
  n=$(basename "$f"); size=$(stat -c %s "$f")
  for try in 1 2 3 4 5 6 7 8; do
    have=$(ssh -o ConnectTimeout=20 $HOST "stat -c %s '$RDIR/$n' 2>/dev/null || echo 0" || echo 0)
    [ "$have" = "$size" ] && break
    timeout 600 scp -q -o ConnectTimeout=20 -o ServerAliveInterval=15 "$f" "$HOST:$RDIR/$n" || { echo "  $n try $try failed"; sleep 5; }
  done
  echo "  $n ok"
done
SUM=$(sha256sum "$LOCAL" | cut -d' ' -f1)
ssh $HOST "cat '$RDIR'/p.* > '$REMOTE.part' && echo '$SUM  $REMOTE.part' | sha256sum -c --quiet && mv '$REMOTE.part' '$REMOTE' && rm -rf '$RDIR' && echo joined"

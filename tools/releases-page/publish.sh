#!/usr/bin/env bash
# Puts an Octopilot build on https://octopilothub.com/app/releases/ (and
# refreshes the page itself). Run from your machine:
#
#   bash tools/releases-page/publish.sh APK VERSION BUILD "note" ["note" ...]
#   bash tools/releases-page/publish.sh --page-only
#
# Builds stay forever (rollbacks); the newest build is shown first. The
# admin app is never published here.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
HOST=octopilot-vps
DIR=/var/www/octopilot-releases
ssh $HOST "mkdir -p $DIR/files && test -f $DIR/releases.json || echo '{\"app\":\"Octopilot\",\"releases\":[]}' > $DIR/releases.json"
scp -q "$HERE/index.html" "$HERE/hero.jpg" "$HERE/depth.jpg" "$HOST:$DIR/"
[ "${1:-}" = "--page-only" ] && { echo "page updated"; exit 0; }
APK=$1; VERSION=$2; BUILD=$3; shift 3
case "$APK" in *admin*) echo "refusing: the admin app is not published here"; exit 1;; esac
FILE=octopilot-v$VERSION.apk
ssh $HOST "test ! -e $DIR/files/$FILE" || { echo "$FILE is already published; use a new version"; exit 1; }
scp -q "$APK" "$HOST:$DIR/files/$FILE.part"
NOTES=$(printf '%s\n' "$@" | python -c 'import json,sys; print(json.dumps([l for l in sys.stdin.read().splitlines() if l.strip()]))' 2>/dev/null \
  || printf '%s\n' "$@" | /c/Users/USER/AppData/Local/Python/bin/python -c 'import json,sys; print(json.dumps([l for l in sys.stdin.read().splitlines() if l.strip()]))')
ssh $HOST "cd $DIR && mv files/$FILE.part files/$FILE && python3 - '$VERSION' '$BUILD' 'files/$FILE' '$NOTES'" <<'PY'
import datetime, hashlib, json, os, sys
version, build, path, notes = sys.argv[1], int(sys.argv[2]), sys.argv[3], json.loads(sys.argv[4])
h = hashlib.sha256()
with open(path, "rb") as f:
    for b in iter(lambda: f.read(1 << 20), b""):
        h.update(b)
data = json.load(open("releases.json"))
data["releases"] = [r for r in data["releases"] if r["version"] != version] + [{
    "version": version, "build": build, "date": datetime.date.today().isoformat(), "file": path,
    "bytes": os.path.getsize(path), "sha256": h.hexdigest(), "notes": notes,
}]
json.dump(data, open("releases.json.tmp", "w"), indent=1)
os.replace("releases.json.tmp", "releases.json")
print(f"published v{version} ({os.path.getsize(path) / 1048576:.1f} MB, sha256 {h.hexdigest()[:12]}…)")
PY

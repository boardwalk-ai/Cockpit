#!/usr/bin/env bash
# Share links on studystudio.octopilothub.com: Android App Link verification
# (/.well-known/assetlinks.json) and the page for /s/CODE when the app isn't
# installed. Run as root on the server from this folder. Safe to run again.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
DIR=/var/www/cockpit-share
SITE=/etc/nginx/sites-available/cockpit-app
mkdir -p "$DIR/.well-known"
cp "$HERE/assetlinks.json" "$DIR/.well-known/assetlinks.json"
cp "$HERE/share.html" "$DIR/share.html"
if ! grep -q "cockpit-share" "$SITE"; then
  cp "$SITE" "$SITE.pre-share"
  python3 - "$SITE" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
block = """    location = /.well-known/assetlinks.json {
        root /var/www/cockpit-share;
        default_type application/json;
        add_header Cache-Control "no-cache" always;
    }
    location /s/ {
        root /var/www/cockpit-share;
        add_header Cache-Control "no-cache" always;
        rewrite ^ /share.html break;
    }
    location / {"""
assert s.count("    location / {") == 1
open(p, "w").write(s.replace("    location / {", block, 1))
PY
fi
nginx -t && systemctl reload nginx
echo installed

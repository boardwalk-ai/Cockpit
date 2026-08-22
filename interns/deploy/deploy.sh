#!/usr/bin/env bash
#
# Interns assignment board — publish the static site to interns.octopilothub.com.
# RUN THIS ON THE SERVER (187.124.92.119), after the interns/ folder is present
# (via `git pull`, rsync, or scp).
#
#   ssh root@187.124.92.119
#   cd /opt/cockpit                 # wherever the repo / interns folder lives
#   sudo bash interns/deploy/deploy.sh
#
# Idempotent — safe to re-run to publish task edits.
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"   # the interns/ folder
DEST=/var/www/interns

echo ">> Publishing $SRC -> $DEST"
mkdir -p "$DEST"
# Ship the page + assets only; leave the deploy scripts and READMEs behind.
rsync -a --delete \
  --exclude 'deploy/' \
  --exclude 'README.md' \
  --exclude 'assets/README.md' \
  "$SRC"/ "$DEST"/

if [[ ! -f "$DEST/assets/hero-bg.jpg" ]]; then
  echo "!! WARNING: assets/hero-bg.jpg is missing — the hero background will be blank."
  echo "   It is untracked in git; copy it across manually or commit it to the repo."
fi

echo ">> Installing nginx site…"
CONF=/etc/nginx/sites-available/interns
cp "$SRC/deploy/nginx-interns.conf" "$CONF"
ln -sf "$CONF" /etc/nginx/sites-enabled/interns

echo ">> Testing & reloading nginx…"
nginx -t && systemctl reload nginx

echo
echo ">> Published. Remaining one-time setup (skip if already done):"
echo "   - DNS:  interns.octopilothub.com  A  187.124.92.119"
echo "   - TLS:  sudo certbot --nginx -d interns.octopilothub.com"

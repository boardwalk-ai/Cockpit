#!/usr/bin/env bash
# Makes a fresh snapshot on the server and downloads the zip to this machine
# (default H:/Backups/octopilot). Needs the `octopilot-vps` ssh alias.
#
#   bash tools/backup/pull-snapshot.sh [destination folder]
set -euo pipefail
DEST=${1:-/h/Backups/octopilot}
mkdir -p "$DEST"
HERE=$(cd "$(dirname "$0")" && pwd)
scp -q "$HERE/../../backend-rs/deploy/backup/snapshot.sh" octopilot-vps:/opt/backups/snapshot.sh
ZIP=$(ssh octopilot-vps 'bash /opt/backups/snapshot.sh' | tail -1)
scp "octopilot-vps:$ZIP" "$DEST/"
LOCAL="$DEST/$(basename "$ZIP")"
# Same bytes as on the server?
[ "$(ssh octopilot-vps "sha256sum '$ZIP'" | cut -d' ' -f1)" = "$(sha256sum "$LOCAL" | cut -d' ' -f1)" ] || { echo "checksum mismatch"; exit 1; }
echo "saved $LOCAL ($(du -h "$LOCAL" | cut -f1))"

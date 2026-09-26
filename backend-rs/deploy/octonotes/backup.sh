#!/usr/bin/env bash
# Nightly backup: notes_db dump (14 days kept) + object-storage mirror.
# Recordings and raw transcripts are student source material — never lose them.
#   RESTORE_DRILL=1 backup.sh   → also restores last night's dump into a
#                                 scratch DB and checks it opens.
set -euo pipefail

DIR=${BACKUP_DIR:-/var/backups/octonotes}
DB=${DB_CONTAINER:-octonotes-db}
U=${DB_ADMIN:-octonotes_admin}
STAMP=$(date +%Y%m%d-%H%M%S)
mkdir -p "$DIR"

docker exec "$DB" pg_dump -U "$U" -d octonotes -Fc > "$DIR/notes-$STAMP.dump"
find "$DIR" -name 'notes-*.dump' -mtime +14 -delete
echo "dumped notes-$STAMP.dump ($(du -h "$DIR/notes-$STAMP.dump" | cut -f1))"

# Off-server copy of the bucket (configure the `offsite` alias with `mc alias set`).
if command -v mc >/dev/null && mc alias list offsite >/dev/null 2>&1; then
  mc mirror --overwrite --remove=false local/octonotes offsite/octonotes-backup
fi
# Off-server copy of the dumps (set BACKUP_REMOTE=user@host:/path).
if [ -n "${BACKUP_REMOTE:-}" ]; then
  scp -q "$DIR/notes-$STAMP.dump" "$BACKUP_REMOTE/"
fi

if [ "${RESTORE_DRILL:-0}" = "1" ]; then
  docker exec "$DB" psql -U "$U" -d postgres -qc "DROP DATABASE IF EXISTS restore_drill"
  docker exec "$DB" psql -U "$U" -d postgres -qc "CREATE DATABASE restore_drill"
  docker exec -i "$DB" pg_restore -U "$U" -d restore_drill --no-owner < "$DIR/notes-$STAMP.dump"
  docker exec "$DB" psql -U "$U" -d restore_drill -tAc \
    "SELECT 'sessions=' || count(*) FROM sessions UNION ALL SELECT 'blocks=' || count(*) FROM blocks"
  docker exec "$DB" psql -U "$U" -d postgres -qc "DROP DATABASE restore_drill"
  echo "restore drill OK"
fi

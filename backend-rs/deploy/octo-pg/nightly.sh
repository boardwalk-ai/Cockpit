#!/usr/bin/env bash
# Nightly dump of every database in octo-pg (+ roles), checked with
# pg_restore --list, checksummed, kept 14 days. Off-site copy: TODO (R2/B2).
set -euo pipefail
OUT=/opt/backups/nightly/$(date +%Y%m%d-%H%M)
mkdir -p "$OUT"
dbs=$(docker exec octo-pg psql -U octo_admin -d postgres -Atc "select datname from pg_database where not datistemplate and datname <> 'postgres' order by 1")
for db in $dbs; do
  docker exec octo-pg pg_dump -U octo_admin -Fc "$db" > "$OUT/$db.dump"
  docker exec -i octo-pg pg_restore --list < "$OUT/$db.dump" > /dev/null
done
docker exec octo-pg pg_dumpall -U octo_admin --globals-only > "$OUT/globals.sql"
chmod 600 "$OUT"/*
(cd "$OUT" && sha256sum * > SHA256SUMS)
find /opt/backups/nightly -mindepth 1 -maxdepth 1 -type d -mtime +14 -exec rm -rf {} +
echo "$(date -Is) ok $OUT $(du -sh "$OUT" | cut -f1)" >> /opt/backups/nightly/backup.log

#!/usr/bin/env bash
# One snapshot of everything, as a zip to download (no cloud): every database
# in octo-pg (+ roles), the Postgres instances not moved to it, the uploaded
# files (MinIO) and the service configs. Each dump is checked with
# pg_restore --list. Keeps the last 3 snapshots. Run as root on the server;
# prints the zip's path. Pull it with tools/backup/pull-snapshot.sh.
set -euo pipefail
TS=$(date +%Y%m%d-%H%M)
ROOT=/opt/backups/snapshots
WORK=$ROOT/snapshot-$TS
mkdir -p "$WORK/db" "$WORK/files" "$WORK/config"
chmod 700 "$ROOT"

dump() {  # container user db
  docker exec "$1" pg_dump -U "$2" -Fc "$3" > "$WORK/db/$1__$3.dump"
  docker exec -i "$1" pg_restore --list < "$WORK/db/$1__$3.dump" > /dev/null
}

# octo-pg: every app database.
for db in $(docker exec octo-pg psql -U octo_admin -d postgres -Atc "select datname from pg_database where not datistemplate and datname <> 'postgres' order by 1"); do
  dump octo-pg octo_admin "$db"
done
docker exec octo-pg pg_dumpall -U octo_admin --globals-only > "$WORK/db/octo-pg__globals.sql"

# Instances not moved to octo-pg (each with its own superuser).
for pair in labs-db:labsuser mbr-postgres:mbruser octopilot-legacy-postgres:octopilot gw-staging-db:gw_staging; do
  c=${pair%%:*}; u=${pair##*:}
  docker ps --format '{{.Names}}' | grep -qx "$c" || continue
  for db in $(docker exec "$c" psql -U "$u" -d postgres -Atc "select datname from pg_database where not datistemplate and datname <> 'postgres' order by 1"); do
    dump "$c" "$u" "$db"
  done
done

# Uploaded study files (MinIO data dir, as is).
MINIO=$(docker inspect cockpit-minio --format '{{range .Mounts}}{{.Source}}{{end}}')
tar czf "$WORK/files/minio-cockpit.tgz" -C "$MINIO" .

# Configs (contain secrets: keep the zip private).
cp -r /etc/nginx/sites-available "$WORK/config/nginx-sites"
cp -r /etc/nginx/conf.d "$WORK/config/nginx-conf.d"
for f in /etc/octopilot-api.env /etc/octopilot-legacy-api.env /opt/study-api/app.env /opt/cockpit/Backend/.env \
         /opt/ghostwriter-staging/app.env /opt/octopilot-api/runtime.env /etc/systemd/system/study-api.service; do
  [ -f "$f" ] && cp "$f" "$WORK/config/$(echo "${f#/}" | tr / _)"
done

(cd "$WORK" && find . -type f ! -name SHA256SUMS -exec sha256sum {} + > SHA256SUMS)
ZIP=$ROOT/snapshot-$TS.zip
(cd "$ROOT" && python3 -m zipfile -c "$ZIP" "snapshot-$TS")
rm -rf "$WORK"
chmod 600 "$ZIP"
ls -1t "$ROOT"/snapshot-*.zip | tail -n +4 | xargs -r rm -f
echo "$ZIP"

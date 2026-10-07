#!/usr/bin/env bash
# Rehearsal: restore the Octopilot-family dumps into octo-pg (one database
# each), then compare exact row counts table by table with the live sources.
# Reads the sources only; writes only to octo-pg.
set -euo pipefail
D=/opt/backups/db-20261007-093320
NEW="docker exec -i octo-pg psql -U octo_admin -v ON_ERROR_STOP=1 -q"

# source container | source db | dump file | new db name
PLAN="cockpit-db|cockpit|cockpit-db--cockpit.dump|cockpit
cockpit-vectordb|vector|cockpit-vectordb--vector.dump|vector
octonotes-db|octonotes|octonotes-db--octonotes.dump|octonotes
gw-staging-db|ghostwriter|gw-staging-db--ghostwriter.dump|ghostwriter
gw-staging-db|octopilot_staging|gw-staging-db--octopilot_staging.dump|octopilot_staging
host|octopilot|host-pg16--octopilot.dump|octopilot"

src_sql() {  # container db sql
  if [ "$1" = host ]; then sudo -n -u postgres psql -d "$2" -Atc "$3"
  else docker exec "$1" psql -U "$(docker exec "$1" printenv POSTGRES_USER)" -d "$2" -Atc "$3"; fi
}
new_sql() { docker exec octo-pg psql -U octo_admin -d "$1" -Atc "$2"; }

COUNT_SQL="SELECT string_agg(format('SELECT %L, count(*) FROM %I.%I', schemaname||'.'||tablename, schemaname, tablename), ' UNION ALL ' ORDER BY 1) FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema')"

total_bad=0
while IFS='|' read -r src db file newdb; do
  $NEW -d postgres -c "DROP DATABASE IF EXISTS \"$newdb\"" -c "CREATE DATABASE \"$newdb\""
  docker exec -i octo-pg pg_restore -U octo_admin -d "$newdb" --no-owner --no-privileges --exit-on-error < "$D/$file"
  q=$(src_sql "$src" "$db" "$COUNT_SQL")
  a=$(src_sql "$src" "$db" "$q" | sort)
  b=$(new_sql "$newdb" "$q" | sort)
  tables=$(echo "$a" | grep -c . || true)
  rows=$(echo "$a" | awk -F'|' '{s+=$2} END {print s+0}')
  if [ "$a" = "$b" ]; then
    echo "OK   $newdb: $tables tables, $rows rows match"
  else
    total_bad=$((total_bad+1))
    echo "DIFF $newdb:"; diff <(echo "$a") <(echo "$b") | head -10
  fi
done <<< "$PLAN"
echo "databases with differences: $total_bad"

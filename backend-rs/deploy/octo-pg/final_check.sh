#!/usr/bin/env bash
# After all cutovers: nothing left on the old instances, old DBs read-only,
# grants and extensions in octo-pg, and no DB errors in the apps' logs.
Q="select count(*) from pg_stat_activity where datname = '%s' and pid <> pg_backend_pid() and backend_type = 'client backend'"
printf 'old host/octopilot: clients=%s read_only=%s\n' \
  "$(sudo -n -u postgres psql -Atc "$(printf "$Q" octopilot)")" \
  "$(sudo -n -u postgres psql -d octopilot -Atc 'show default_transaction_read_only')"
for pair in cockpit-db:cockpit cockpit-vectordb:vector octonotes-db:octonotes gw-staging-db:ghostwriter gw-staging-db:octopilot_staging; do
  c=${pair%%:*}; db=${pair##*:}; u=$(docker exec "$c" printenv POSTGRES_USER)
  printf 'old %s/%s: clients=%s read_only=%s\n' "$c" "$db" \
    "$(docker exec "$c" psql -U "$u" -d postgres -Atc "$(printf "$Q" "$db")")" \
    "$(docker exec "$c" psql -U "$u" -d "$db" -Atc 'show default_transaction_read_only')"
done
echo "octo-pg octopilot: extensions=$(docker exec octo-pg psql -U octo_admin -d octopilot -Atc "select string_agg(extname, ',') from pg_extension")"
echo "octo-pg octopilot: octonotes_credits can read users=$(docker exec octo-pg psql -U octo_admin -d octopilot -Atc "select has_table_privilege('octonotes_credits','users','SELECT')")"
echo "octo-pg octopilot: sequences=$(docker exec octo-pg psql -U octo_admin -d octopilot -Atc "select count(*) from pg_sequences where last_value is not null")"
echo "== DB errors in the last 5 minutes"
for u in octopilot-rs octopilot-web octopilot-formatter octonotes-api ghostwriter-staging; do
  n=$(journalctl -u "$u" --since '-5 min' --no-pager 2>/dev/null | grep -ciE 'read-only|password authentication|connection refused|ECONNREFUSED|sqlx|asyncpg.*error|PrismaClient.*Error|database.*error' || true)
  echo "$u: $n"
done
for c in octopilot-api cockpit-api cockpit-worker cockpit-gateway; do
  n=$(docker logs --since 5m "$c" 2>&1 | grep -ciE 'read-only|password authentication|connection refused|database.*error|asyncpg.*error|traceback' || true)
  echo "$c: $n"
done

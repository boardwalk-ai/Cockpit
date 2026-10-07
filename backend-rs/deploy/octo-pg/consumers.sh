#!/usr/bin/env bash
# Every config that points at a Postgres port we are moving, as
# file: KEY -> user@host:port/db (passwords never printed).
PORTS='5432|5433|5434|5438|5439'
files=$(sudo -n find /opt /etc/systemd/system /srv /var/www /home -maxdepth 4 \
  \( -name '.env' -o -name '*.env' -o -name '.env.*' -o -name '*.service' -o -name 'docker-compose*.yml' -o -name 'ecosystem*.js*' \) \
  -not -path '*/node_modules/*' -not -path '*/backup*' -not -path '*/src/*' -not -path '*/.git/*' 2>/dev/null)
for f in $files; do
  sudo -n grep -HnoE "^[[:space:]]*[A-Za-z_]*=?[\"']?postgres(ql)?(\+[a-z]+)?://[^ \"']+" "$f" 2>/dev/null \
    | sed -E 's#://([^:@/]+):[^@]*@#://\1:***@#' \
    | grep -E "[:@](127\.0\.0\.1|localhost|::1|\[::1\]|172\.[0-9.]+|host\.docker\.internal)(:($PORTS))?(/|$)|:($PORTS)/" || true
done
echo "== compose env_file / environment DB keys"
for f in $files; do sudo -n grep -HnE "(DATABASE_URL|DB_URL|PG(HOST|PORT|DATABASE|USER)|POSTGRES_(HOST|PORT|DB))" "$f" 2>/dev/null | sed -E 's#://([^:@/]+):[^@]*@#://\1:***@#; s#(PASSWORD[^=]*=).*#\1***#'; done | grep -vE "POSTGRES_PASSWORD" | head -60

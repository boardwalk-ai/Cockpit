#!/usr/bin/env bash
# Create the app roles in octo-pg with the same SCRAM password hashes as on
# their current instance (so every connection string keeps working with only
# the port changed), but without SUPERUSER: in a shared cluster each app may
# only own its own database. Never prints a password.
set -euo pipefail
D=/opt/backups/db-20261007-093320
SQL=$(mktemp); chmod 600 "$SQL"; trap 'rm -f "$SQL"' EXIT

# role | globals file it comes from
ROLES="cockpit|cockpit-db
octonotes_ro|cockpit-db
amirjon|cockpit-db
anagha|cockpit-db
chris|cockpit-db
sean|cockpit-db
shahaiar|cockpit-db
vector|cockpit-vectordb
gw_staging|gw-staging-db
octonotes_admin|octonotes-db
octonotes_rw|octonotes-db
octopilot|host-pg16
octonotes_credits|host-pg16"

{
  echo "DO \$\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='intern_rw') THEN CREATE ROLE intern_rw NOLOGIN; END IF; END \$\$;"
  while IFS='|' read -r role src; do
    line=$(grep -E "^ALTER ROLE $role WITH .* PASSWORD '" "$D/$src--globals.sql" || true)
    [ -n "$line" ] || { echo "missing password for $role" >&2; exit 1; }
    hash=$(printf '%s' "$line" | sed -E "s/.* PASSWORD '([^']*)'.*/\1/")
    echo "DO \$\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='$role') THEN CREATE ROLE $role; END IF; END \$\$;"
    echo "ALTER ROLE $role WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS INHERIT PASSWORD '$hash';"
  done <<< "$ROLES"
  for i in amirjon anagha chris sean shahaiar; do echo "GRANT intern_rw TO $i;"; done
} > "$SQL"

docker exec -i octo-pg psql -U octo_admin -d postgres -v ON_ERROR_STOP=1 -q < "$SQL"
docker exec octo-pg psql -U octo_admin -d postgres -Atc \
  "select rolname, rolsuper, rolcanlogin, rolpassword is not null from pg_authid where rolname !~ '^pg_' order by 1"

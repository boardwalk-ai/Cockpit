#!/usr/bin/env bash
# Log in to octo-pg with each app's real connection string (port swapped).
# Prints only ok / FAIL per connection.
check() {  # label file key
  local url
  url=$(sudo -n grep -E "^$3=" "$2" | head -1 | cut -d= -f2- | sed -E 's#^postgres(ql)?(\+[a-z]+)?://#postgresql://#; s#@(localhost|127\.0\.0\.1):[0-9]+/#@127.0.0.1:5432/#')
  if docker exec octo-pg psql "$url" -Atc "select current_user||'@'||current_database()" >/dev/null 2>&1; then
    echo "ok   $1"
  else
    echo "FAIL $1"
  fi
}
check "cockpit-api cockpit"          /opt/cockpit/Backend/.env COCKPIT_DATABASE_URL
check "cockpit-api vector"           /opt/cockpit/Backend/.env VECTOR_DATABASE_URL
check "cockpit-api shared octopilot" /opt/cockpit/Backend/.env SHARED_DATABASE_URL
check "octonotes notes"              /opt/octonotes-api/.env NOTES_DATABASE_URL
check "octonotes octopilot credits"  /opt/octonotes-api/.env OCTOPILOT_DATABASE_URL
check "octonotes studio cockpit"     /opt/octonotes-api/.env STUDIO_DATABASE_URL
check "octonotes studio vector"      /opt/octonotes-api/.env STUDIO_VECTOR_DATABASE_URL
check "ghostwriter-staging gw"       /opt/ghostwriter-staging/app.env GHOSTWRITER_DATABASE_URL
check "ghostwriter-staging octo"     /opt/ghostwriter-staging/app.env OCTOPILOT_DATABASE_URL
check "octopilot-api"                /opt/octopilot-api/.env DATABASE_URL
check "octopilot-rs"                 /opt/octopilot-rs/.env DATABASE_URL
check "octopilot-web"                /opt/octopilot-web/.env.production DATABASE_URL
check "octopilot-formatter"          /opt/octopilot-formatter/.env.production DATABASE_URL

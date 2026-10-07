#!/usr/bin/env bash
# Move one group of databases into octo-pg (127.0.0.1:5440) without losing
# data:  stop writers → final dump → restore → verify every table's row
# count → old DB read-only → point configs at 5440 → start → verify.
# If the counts don't match it stops and restarts the apps on the old DB.
#
#   bash cutover.sh <cockpit|ghostwriter|octonotes|octopilot>
#   bash cutover.sh rollback <group> <run dir>
set -euo pipefail
NEWPORT=5440
TS=$(date +%Y%m%d-%H%M%S)

src_psql() {  # instance db sql
  if [ "$1" = host ]; then sudo -n -u postgres psql -d "$2" -v ON_ERROR_STOP=1 -Atc "$3"
  else docker exec "$1" psql -U "$(docker exec "$1" printenv POSTGRES_USER)" -d "$2" -v ON_ERROR_STOP=1 -Atc "$3"; fi
}
src_dump() {  # instance db > file
  if [ "$1" = host ]; then sudo -n -u postgres pg_dump -Fc "$2"
  else docker exec "$1" pg_dump -U "$(docker exec "$1" printenv POSTGRES_USER)" -Fc "$2"; fi
}
new_psql() { docker exec octo-pg psql -U octo_admin -d "$1" -v ON_ERROR_STOP=1 -Atc "$2" </dev/null; }

COUNT_SQL="SELECT string_agg(format('SELECT %L, count(*) FROM %I.%I', schemaname||'.'||tablename, schemaname, tablename), ' UNION ALL ' ORDER BY 1) FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema')"

# --- the groups --------------------------------------------------------------
# DBS: "instance|db|owner" per line. ENVS: "file|KEY|oldport" per line.
group() {
  case "$1" in
  cockpit)
    DBS="cockpit-db|cockpit|cockpit
cockpit-vectordb|vector|vector"
    ENVS="/opt/cockpit/Backend/.env|COCKPIT_DATABASE_URL|5433
/opt/cockpit/Backend/.env|VECTOR_DATABASE_URL|5434
/opt/octonotes-api/.env|STUDIO_DATABASE_URL|5433
/opt/octonotes-api/.env|STUDIO_VECTOR_DATABASE_URL|5434"
    stop_apps()  { (cd /opt/cockpit/Backend && docker compose -f docker-compose.yml -f docker-compose.prod.yml stop cockpit-gateway cockpit-api cockpit-worker); }
    start_apps() { (cd /opt/cockpit/Backend && docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --no-deps --force-recreate cockpit-api cockpit-worker cockpit-gateway); sudo -n systemctl restart octonotes-api; }
    health()     { for i in $(seq 1 40); do curl -fsS -o /dev/null 127.0.0.1:8100/health 2>/dev/null && curl -fsS -o /dev/null 127.0.0.1:8790/ready 2>/dev/null && return 0; sleep 3; done; return 1; }
    ;;
  ghostwriter)
    DBS="gw-staging-db|ghostwriter|gw_staging
gw-staging-db|octopilot_staging|gw_staging"
    ENVS="/opt/ghostwriter-staging/app.env|GHOSTWRITER_DATABASE_URL|5439
/opt/ghostwriter-staging/app.env|OCTOPILOT_DATABASE_URL|5439"
    stop_apps()  { sudo -n systemctl stop ghostwriter-staging; }
    start_apps() { sudo -n systemctl start ghostwriter-staging; }
    health()     { for i in $(seq 1 30); do systemctl is-active --quiet ghostwriter-staging && sleep 5 && systemctl is-active --quiet ghostwriter-staging && return 0; sleep 2; done; return 1; }
    ;;
  octonotes)
    DBS="octonotes-db|octonotes|octonotes_rw"
    ENVS="/opt/octonotes-api/.env|NOTES_DATABASE_URL|5438"
    stop_apps()  { sudo -n systemctl stop octonotes-api; }
    start_apps() { sudo -n systemctl start octonotes-api; }
    health()     { for i in $(seq 1 40); do curl -fsS -o /dev/null 127.0.0.1:8790/ready 2>/dev/null && return 0; sleep 3; done; return 1; }
    ;;
  octopilot)
    DBS="host|octopilot|octopilot"
    ENVS="/opt/octopilot-rs/.env|DATABASE_URL|5432
/opt/octopilot-web/.env.production|DATABASE_URL|5432
/opt/octopilot-formatter/.env.production|DATABASE_URL|5432
/opt/cockpit/Backend/.env|SHARED_DATABASE_URL|5432
/opt/octonotes-api/.env|OCTOPILOT_DATABASE_URL|5432
/opt/study-api/shadow.env|SHARED_DATABASE_URL|5432"
    stop_apps() {
      sudo -n systemctl stop octopilot-web octopilot-formatter octopilot-rs octonotes-api
      docker stop octopilot-api-pre-octopg >/dev/null 2>&1 || docker stop octopilot-api >/dev/null 2>&1 || true
      (cd /opt/cockpit/Backend && docker compose -f docker-compose.yml -f docker-compose.prod.yml stop cockpit-gateway cockpit-api cockpit-worker)
    }
    start_apps() {
      if [ "${ABORT:-0}" = 1 ]; then
        # Back on the old DB: the original container, untouched.
        docker rm -f octopilot-api >/dev/null 2>&1 || true
        docker rename octopilot-api-pre-octopg octopilot-api 2>/dev/null || true
        sudo -n rm -f /opt/octopilot-api/runtime.env
        docker start octopilot-api >/dev/null
      else
        # New container: same image, DATABASE_URL from runtime.env (overrides the baked .env).
        docker rm -f octopilot-api >/dev/null 2>&1 || true
        docker run -d --name octopilot-api --network host --restart unless-stopped \
          --env-file /opt/octopilot-api/runtime.env octopilot-api:latest >/dev/null
      fi
      sudo -n systemctl start octopilot-rs octopilot-web octopilot-formatter octonotes-api
      (cd /opt/cockpit/Backend && docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --no-deps --force-recreate cockpit-api cockpit-worker cockpit-gateway)
    }
    health() {
      for i in $(seq 1 60); do
        ok=1
        for u in 127.0.0.1:8000/health 127.0.0.1:8787/health 127.0.0.1:8100/health 127.0.0.1:8790/ready 127.0.0.1:3000/ 127.0.0.1:3001/; do
          curl -fsS -o /dev/null --max-time 5 "$u" 2>/dev/null || { ok=0; break; }
        done
        [ $ok = 1 ] && return 0; sleep 3
      done
      return 1
    }
    # Before the configs change: keep the old API container for rollback and
    # write the new one's DATABASE_URL (its own value, port swapped).
    pre_config() {  # runs while the API is still up
      url=$(docker exec octopilot-api sh -c 'grep -E "^DATABASE_URL=" /app/.env | head -1 | cut -d= -f2-')
      [ -n "$url" ] || { echo "no DATABASE_URL in the API image"; return 1; }
      umask 077
      printf 'DATABASE_URL=%s\n' "$(printf '%s' "$url" | sed -E "s#@(localhost|127\.0\.0\.1):5432/#@127.0.0.1:$NEWPORT/#")" | sudo -n tee /opt/octopilot-api/runtime.env >/dev/null
      sudo -n chmod 600 /opt/octopilot-api/runtime.env
      sudo -n grep -qE "@127\.0\.0\.1:$NEWPORT/" /opt/octopilot-api/runtime.env || { echo "runtime.env not written"; return 1; }
      docker rename octopilot-api octopilot-api-pre-octopg
    }
    ;;
  *) echo "unknown group $1"; exit 2 ;;
  esac
}

set_env_port() {  # file key from to
  sudo -n sed -i -E "s#^($2=[^@]*@(localhost|127\.0\.0\.1)):$3/#\1:$4/#" "$1"
  sudo -n grep -qE "^$2=[^@]*@(localhost|127\.0\.0\.1):$4/" "$1" || { echo "could not set $2 in $1"; return 1; }
}

if [ "${1:-}" = rollback ]; then
  group "$2"; RUN=$3
  echo "== rollback $2 from $RUN"
  stop_apps || true
  while IFS='|' read -r f key old; do sudo -n cp "$RUN/env/$(echo "$f" | tr / _)" "$f"; done <<< "$ENVS"
  while IFS='|' read -r inst db owner; do src_psql "$inst" postgres "ALTER DATABASE \"$db\" RESET default_transaction_read_only" ; done <<< "$DBS"
  ABORT=1 start_apps; health && echo "rolled back, apps healthy" || echo "rolled back, CHECK APPS"
  exit 0
fi

group "$1"
RUN=/opt/backups/cutover-$1-$TS
sudo -n mkdir -p "$RUN/env"; sudo -n chown -R "$(id -u):$(id -g)" "$RUN"
echo "== $1 → octo-pg ($RUN)"

# Configs saved first (for rollback).
while IFS='|' read -r f key old; do sudo -n cp "$f" "$RUN/env/$(echo "$f" | tr / _)"; done <<< "$ENVS"

if declare -F pre_config >/dev/null; then echo "-- prepare"; pre_config; fi
echo "-- stop writers"; stop_apps
while IFS='|' read -r inst db owner; do
  # Nobody else may write while we copy.
  src_psql "$inst" postgres "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$db' AND pid<>pg_backend_pid()" >/dev/null
  echo "-- dump $db"; src_dump "$inst" "$db" > "$RUN/$db.dump"
  echo "-- restore $db (owner $owner)"
  new_psql postgres "DROP DATABASE IF EXISTS \"$db\" WITH (FORCE)"
  new_psql postgres "CREATE DATABASE \"$db\" OWNER $owner"
  docker exec -i octo-pg pg_restore -U octo_admin -d "$db" --exit-on-error < "$RUN/$db.dump"
  q=$(src_psql "$inst" "$db" "$COUNT_SQL")
  a=$(src_psql "$inst" "$db" "$q" | sort); b=$(new_psql "$db" "$q" | sort)
  if [ "$a" != "$b" ]; then
    echo "!! row counts differ for $db — aborting, apps go back on the old DB"
    diff <(echo "$a") <(echo "$b") | head || true
    ABORT=1 start_apps; exit 1
  fi
  echo "   $db: $(echo "$a" | grep -c .) tables, $(echo "$a" | awk -F'|' '{s+=$2} END {print s+0}') rows — identical"
done <<< "$DBS"

echo "-- old databases read-only"
while IFS='|' read -r inst db owner; do
  src_psql "$inst" postgres "ALTER DATABASE \"$db\" SET default_transaction_read_only = on" >/dev/null
  src_psql "$inst" postgres "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$db' AND pid<>pg_backend_pid()" >/dev/null
done <<< "$DBS"

echo "-- configs → port $NEWPORT"
while IFS='|' read -r f key old; do set_env_port "$f" "$key" "$old" "$NEWPORT"; done <<< "$ENVS"

echo "-- start"; start_apps
if health; then echo "-- apps healthy"; else echo "!! apps not healthy — run: bash $0 rollback $1 $RUN"; exit 1; fi
sleep 5
echo "-- connections on octo-pg now:"
new_psql postgres "select datname, usename, count(*) from pg_stat_activity where datname is not null and usename<>'octo_admin' group by 1,2 order by 1"
echo "RUN=$RUN"

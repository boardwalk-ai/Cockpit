#!/usr/bin/env bash
# Creates the least-privilege DB roles (random passwords) and writes
# /opt/octonotes-api/.env on the server. Reuses the Study Studio Redis, MinIO
# and embed service. Idempotent: re-running rotates the role passwords and
# rewrites the file. Nothing secret is printed. Run as root after install.sh.
set -euo pipefail

APP=/opt/octonotes-api
COCKPIT_ENV=${COCKPIT_ENV:-/opt/cockpit/Backend/.env}
val() { grep -E "^$1=" "$COCKPIT_ENV" | head -1 | cut -d= -f2- | sed -E 's/[[:space:]]+#.*$//; s/^"//; s/"$//'; }
pw() { openssl rand -hex 24; }

RW=$(pw); RO=$(pw); CR=$(pw)

echo "== notes_db role (octonotes-db container)"
docker exec -i octonotes-db psql -v ON_ERROR_STOP=1 -q -U octonotes_admin -d octonotes <<SQL
DO \$\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'octonotes_rw') THEN CREATE ROLE octonotes_rw LOGIN; END IF; END \$\$;
ALTER ROLE octonotes_rw PASSWORD '$RW';
CREATE EXTENSION IF NOT EXISTS vector;
GRANT CONNECT, CREATE ON DATABASE octonotes TO octonotes_rw;
ALTER SCHEMA public OWNER TO octonotes_rw;
SQL

echo "== Study Studio read-only role (cockpit-db, cockpit-vectordb)"
for target in "cockpit-db:cockpit:cockpit:studios, documents, generated_topics, topic_progress, studio_builds" \
              "cockpit-vectordb:vector:vector:chunks"; do
  IFS=: read -r container user db tables <<<"$target"
  docker exec -i "$container" psql -v ON_ERROR_STOP=1 -q -U "$user" -d "$db" <<SQL
DO \$\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'octonotes_ro') THEN CREATE ROLE octonotes_ro LOGIN; END IF; END \$\$;
ALTER ROLE octonotes_ro PASSWORD '$RO';
GRANT CONNECT ON DATABASE $db TO octonotes_ro;
GRANT USAGE ON SCHEMA public TO octonotes_ro;
GRANT SELECT ON $tables TO octonotes_ro;
SQL
done

echo "== octopilot credits role (native Postgres)"
sudo -u postgres psql -v ON_ERROR_STOP=1 -q -d octopilot <<SQL
DO \$\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'octonotes_credits') THEN CREATE ROLE octonotes_credits LOGIN; END IF; END \$\$;
ALTER ROLE octonotes_credits PASSWORD '$CR';
GRANT CONNECT ON DATABASE octopilot TO octonotes_credits;
GRANT USAGE ON SCHEMA public TO octonotes_credits;
GRANT SELECT (id, firebase_uid, email, name, photo_url, plan, is_admin, word_credits, source_credits,
              humanizer_credits, octo_credits, has_completed_wizard) ON users TO octonotes_credits;
GRANT UPDATE (octo_credits) ON users TO octonotes_credits;
GRANT SELECT, INSERT ON credit_ledger TO octonotes_credits;
GRANT SELECT ON api_keys, system_settings TO octonotes_credits;
SQL

echo "== write $APP/.env"
umask 027
cat > "$APP/.env" <<ENV
NOTES_DATABASE_URL=postgres://octonotes_rw:$RW@127.0.0.1:5438/octonotes
OCTOPILOT_DATABASE_URL=postgres://octonotes_credits:$CR@127.0.0.1:5432/octopilot
STUDIO_DATABASE_URL=postgres://octonotes_ro:$RO@127.0.0.1:5433/cockpit
STUDIO_VECTOR_DATABASE_URL=postgres://octonotes_ro:$RO@127.0.0.1:5434/vector
FIREBASE_PROJECT_ID=$(val FIREBASE_PROJECT_ID)
CORS_ORIGINS=${CORS_ORIGINS:-}
CORS_ALLOW_LOCALHOST=false
PUBLIC_BASE_URL=${PUBLIC_BASE_URL:-http://127.0.0.1:8790}
REDIS_URL=$(val REDIS_URL)
S3_ENDPOINT=$(val OBJECT_STORE_ENDPOINT)
S3_BUCKET=octonotes
S3_ACCESS_KEY=$(val OBJECT_STORE_ACCESS_KEY)
S3_SECRET_KEY=$(val OBJECT_STORE_SECRET_KEY)
S3_REGION=$(r=$(val OBJECT_STORE_REGION); echo "${r:-us-east-1}")
EMBED_URL=$(val EMBED_SERVICE_URL)
STUDY_STUDIO_API_URL=http://127.0.0.1:$(val API_PORT)
STUDY_STUDIO_SERVICE_KEY=
SERVICE_KEYS=
CREDITS_ENABLED=true
CREDITS_LEDGER_TYPE=octo
PORT=8790
ROLE=all
WORKERS=4
LOG_FORMAT=json
RUST_LOG=octonotes_api=info,octo_common=info,tower_http=info
METRICS_TOKEN=$(pw)
STORAGE_DIR=/var/lib/octonotes/blobs
STORAGE_SIGNING_KEY=$(pw)
ENV
chown root:octonotes "$APP/.env"
chmod 640 "$APP/.env"
echo "done (values not printed)"

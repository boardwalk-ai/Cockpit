#!/usr/bin/env bash
# Copies production's OpenRouter / OpenAI keys and system settings (models,
# humanizer keys, the content policy, prices) into staging's own database.
# Values go straight from one database to the other; nothing is printed but
# counts. Run as root on the server; run again to refresh.
set -euo pipefail

src() { sudo -u postgres psql -d octopilot -v ON_ERROR_STOP=1 -qAt "$@"; }
dst() { docker exec -i gw-staging-db psql -U gw_staging -d octopilot_staging -v ON_ERROR_STOP=1 -qAt "$@"; }

src -c "\copy (SELECT provider, key, is_active FROM api_keys \
               WHERE is_active AND provider ILIKE ANY (ARRAY['openrouter', 'openai'])) TO STDOUT" |
  dst -c "DELETE FROM api_keys" \
      -c "\copy api_keys (provider, key, is_active) FROM STDIN" \
      -c "SELECT 'api_keys: ' || count(*) FROM api_keys"

src -c "\copy (SELECT key, value FROM system_settings) TO STDOUT" |
  dst -c "CREATE TEMP TABLE incoming (key varchar(128), value text)" \
      -c "\copy incoming FROM STDIN" \
      -c "INSERT INTO system_settings SELECT key, value FROM incoming \
          ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value" \
      -c "SELECT 'system_settings: ' || count(*) FROM system_settings"

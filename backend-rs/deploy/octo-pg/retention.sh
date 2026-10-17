#!/usr/bin/env bash
# Daily retention (tasklist D5). OctoNotes `jobs`: finished jobs kept 3 days,
# failed/cancelled 30 days (their dedupe keys are per minute, so old rows are
# never needed again). Installed as /etc/cron.d/octo-retention.
set -euo pipefail
n=$(docker exec octo-pg psql -U octo_admin -d octonotes -Atc \
  "WITH d AS (DELETE FROM jobs WHERE (status = 'done' AND updated_at < now() - interval '3 days') \
     OR (status IN ('failed', 'cancelled') AND updated_at < now() - interval '30 days') RETURNING 1) SELECT count(*) FROM d")
echo "$(date -Is) octonotes.jobs deleted $n" >> /var/log/octo-retention.log

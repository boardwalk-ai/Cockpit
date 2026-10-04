# GhostWriter staging

For testers (the PM) before release: `https://gw-staging.octopilothub.com`,
on the same VPS as production but **apart from it**: its own system user
(`gw-staging`), Postgres container (`gw-staging-db`, 127.0.0.1:5439, the
`ghostwriter` and `octopilot_staging` databases), service
(`ghostwriter-staging`, 127.0.0.1:8795) and nginx site. Production's
databases are only read, once, by `copy-keys.sh` (keys and settings).

Sign-in is Firebase (project `octopilot-ai-7b29e`). Staging has no sign-up:
a verified email on `ACCOUNT_ALLOWLIST` gets an account with 9999
OctoCredits on its first sign-in; anyone else gets `account_required`.

## First time

1. DNS: `gw-staging.octopilothub.com` A → the VPS.
2. Upload the workspace (see `deploy.sh`), then on the server:

       bash /opt/ghostwriter-staging/src/deploy/ghostwriter-staging/install.sh pm@example.com
       bash /opt/ghostwriter-staging/src/deploy/ghostwriter-staging/copy-keys.sh
       bash /opt/ghostwriter-staging/src/deploy/ghostwriter-staging/deploy.sh
       certbot --nginx -d gw-staging.octopilothub.com

3. The content policy (not in production's settings yet):

       docker exec -i gw-staging-db psql -U gw_staging -d octopilot_staging \
         -c "INSERT INTO system_settings (key, value) VALUES ('ghostwriter_safety_policy', \$p\$$(cat policy.md)\$p\$) \
             ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value"

## Later

- New code: upload and `deploy.sh` (rollback: `deploy.sh --rollback`).
- Another tester: edit `ACCOUNT_ALLOWLIST` in `/opt/ghostwriter-staging/app.env`,
  `systemctl restart ghostwriter-staging`.
- More credits for someone: `UPDATE users SET octo_credits = 9999 WHERE email = '…'`
  in `octopilot_staging`.
- Remove it all: stop and disable the service, remove the nginx site,
  `docker compose -f /opt/ghostwriter-staging/docker-compose.yml down -v`,
  `rm -rf /opt/ghostwriter-staging /var/lib/gw-staging`, `userdel gw-staging`.

# octo-pg — the one Postgres for the Octopilot apps

Postgres 17 + pgvector in Docker, `127.0.0.1:5440`, data in the `octo-pg-data`
volume, admin password in `/opt/octo-pg/.env` on the server (never in git).

Databases (moved in 2026-10-07, row counts verified table by table):
`octopilot` (main app), `cockpit` + `vector` (Study Studio), `octonotes`,
`ghostwriter` + `octopilot_staging` (GhostWriter staging).
App roles keep their old passwords but are **not** superusers.

| Script | What |
|---|---|
| `consumers.sh` | every config that points at a database (passwords masked) |
| `roles.sh` | create the app roles with their existing SCRAM hashes |
| `logintest.sh` | log in with each app's real connection string |
| `rehearse.sh` | restore dumps and compare row counts, apps untouched |
| `cutover.sh <group>` | stop → dump → restore → verify → old DB read-only → configs to 5440 → start → verify |
| `cutover.sh rollback <group> <run dir>` | put a group back on its old database |
| `grants.sh`, `final_check.sh` | grants old vs new; leftovers, read-only, log errors |
| `nightly.sh` | nightly dumps to `/opt/backups/nightly` (14 days), cron 03:15 |

The old instances stay **read-only** until 2026-10-21 (rollback window), then
take a last dump and remove them.

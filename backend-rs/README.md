# backend-rs — Octopilot Rust services

A Cargo workspace. Each app has its own binary; auth, errors, identity and DB
helpers are written once in `octo-common`.

| Crate | Kind | Serves | Port |
|---|---|---|---|
| `crates/octo-common` | library | Firebase auth (`AuthedUser` extractor), `ApiError`, identity + OctoCredits from the shared `users` table, Postgres helpers | — |
| `crates/octopilot-rs` | binary | Doc Oct (octopilotai.app): tools, sources, OctoBot, outline, essays | 8787 |
| `crates/octonotes-api` | binary | OctoNotes: owns `notes_db`, reads the octopilot + Study Studio DBs | 8790 |

```bash
cargo build --workspace
cargo run -p octopilot-rs      # Doc Oct API
cargo run -p octonotes-api     # OctoNotes API
```

## octonotes-api (local)

1. Postgres: the native Postgres 17 (`createdb octonotes`), or
   `docker compose -f docker-compose.dev.yml up -d` (pgvector on 5435).
2. Local stand-in for the shared users table (dev only):
   `createdb octopilot_dev && psql -d octopilot_dev -f crates/octonotes-api/dev/octopilot_dev.sql`
3. Copy `crates/octonotes-api/.env.example` values into your environment, then
   `FIREBASE_PROJECT_ID= cargo run -p octonotes-api` (empty project = dev auth,
   `X-User-Id` header trusted; default user `dev-user`).

`notes_db` migrations live in `crates/octonotes-api/migrations/` and run
automatically at startup (`sqlx migrate`). This service never runs migrations
on the octopilot or Study Studio databases.

| Method | Path | Notes |
|---|---|---|
| GET | `/health` | liveness |
| GET | `/ready` | pings notes_db + configured shared DBs; 503 if any is down |
| GET | `/v1/me` | token identity + central OctoCredits balance; `registered:false` if no octopilot account |

## octopilot-rs

Endpoints are listed in `crates/octopilot-rs/src/main.rs`; env in
`crates/octopilot-rs/.env.example`.

**Deploy change:** the server build now runs from the workspace root, so the
tarball must include the workspace, not just one crate:

```bash
tar czf backend-rs.tgz --force-local Cargo.toml Cargo.lock crates
# on the server, in /opt/octopilot-rs:
docker run --rm -v /opt/octopilot-rs:/app -v octo-cargo:/usr/local/cargo/registry \
  -w /app rust:1-slim-bookworm cargo build --release -p octopilot-rs
# binary path is unchanged: target/release/octopilot-rs
```

## Auth

Send a Firebase ID token as `Authorization: Bearer <token>` — verified against
Google's public keys for `FIREBASE_PROJECT_ID` (RS256, `aud`/`iss`). With the
project empty, auth is disabled and `X-User-Id` is trusted (local dev only).

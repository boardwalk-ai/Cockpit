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

## octonotes-api

The OctoNotes backend: ~100 endpoints over 7 notes_db migrations, a durable
job worker, realtime WebSocket, and the shared OctoCredits protocol. The full
contract is generated at **`GET /v1/openapi.json`**.

| Area | Endpoints (prefix `/v1`) |
|---|---|
| Account | `me`, `me/pricing`, `home` |
| Sessions | `sessions` (list/search/cursor, create, snapshot, edit, delete), `courses`, `devices`, `deck/destinations` |
| Typewriter | `sessions/{id}/blocks` (+`?sinceRev`), `blocks/ops` (sync), `blocks/{id}/history`, `restore`, `blocks/from-source` |
| Magic Pencil | `ink/pages`, `ink/pages/{id}/ops`, `strokes`, `recognize`, `ink/recognitions/{id}` |
| Capture | `recordings` (start, pause/stop, `chunks/{seq}`, `manifest`, `complete`, `audio`), `markers`, `transcription` |
| Transcript | `sessions/{id}/transcript`, `transcript/segments/{id}` (+`restore`) |
| Realtime | `WS sessions/{id}/live`, `join`, `leave`, `finish`, `sessions/{id}/devices` |
| AI | `ai/suggest`, `ai/suggestions/{id}/apply|dismiss`, `ai/command`, `ai/runs/{id}/insert`, `ai/history`, `relevant`, `summarize` |
| Materials | `materials` (upload, upload-url, from-studio), `pages`, `image`, `link`, `active` |
| Research / Organize | `research` (+`apply`, `save`), `organize/preview|apply|undo|dismiss` |
| Review / Finalize | `review/prepare`, `reviews/{id}` (+`decisions`, `draft`), `finalize/summary`, `finalize`, `final-notes` (+`export`), `exports/{id}` |
| Study Studio | `final-notes/{id}/recommendations` (+`selection`), `conversions` (+`generate`, `progress`), `links` |
| The Deck | `deck/search` (service key on behalf of a user) |
| Ops | `/health`, `/ready`, `/metrics` (loopback or `METRICS_TOKEN`) |

### Run locally

```bash
docker compose -f docker-compose.dev.yml up -d          # pgvector :5435, Redis :6380, S3 (RustFS) :9010
createdb octopilot_dev && psql -d octopilot_dev -f crates/octonotes-api/dev/octopilot_dev.sql
createdb studio_dev    && psql -d studio_dev    -f crates/octonotes-api/dev/studio_dev.sql
FIREBASE_PROJECT_ID= NOTES_DATABASE_URL=postgres://octonotes:octonotes@127.0.0.1:5435/octonotes   OCTOPILOT_DATABASE_URL=postgres://…/octopilot_dev STUDIO_DATABASE_URL=postgres://…/studio_dev   REDIS_URL=redis://127.0.0.1:6380 cargo run -p octonotes-api
```

Empty `FIREBASE_PROJECT_ID` = dev auth (the `X-User-Id` header is trusted).
Without an OpenRouter key (in `api_keys`), AI, transcription and OCR use
deterministic offline stand-ins, so the whole pipeline runs offline. Optional
tools: `ffmpeg` (join + compress audio), `pdftoppm` (PDF page images),
`soffice` (PPTX page images).

### Tests

```bash
cargo test --workspace      # needs the dev compose Postgres (TEST_PG_URL) and Redis (TEST_REDIS_URL)
cargo run --release -p octonotes-api --example loadtest -- http://127.0.0.1:8790 20 30 200
```

Every integration test creates its own database, so tests run in parallel.

### Deploy

See `deploy/octonotes/`: `install.sh` (once), `deploy.sh` (build + restart +
auto-rollback if `/ready` fails; `--rollback`), `octonotes-api.service`,
`docker-compose.prod.yml` (notes_db), `sql/roles.sql` (least-privilege roles),
`nginx/octonotes.conf`, `backup.sh` (nightly dump + restore drill),
`monitoring/alerts.yml`, `.env.production.example`.

## octopilot-rs

Endpoints are listed in `crates/octopilot-rs/src/main.rs`; env in
`crates/octopilot-rs/.env.example`.

**`DATABASE_URL` is now required** (the password is no longer compiled in):
add it to `/opt/octopilot-rs/.env` before the next deploy.

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

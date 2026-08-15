# Cockpit Backend

FastAPI service for **Study Studio** — studios/documents API plus the **RAG**
pipeline (upload → embed → retrieve → answer). Built to run as Docker containers
on the existing Octopilot server.

> **Status: foundation / scaffold.** Everything here runs locally end-to-end
> with `docker compose up`. It has **not** been deployed to the production
> server and does **not** touch the live `octopilot` database — see
> [Deploying](#deploying-to-the-server) and [Open decisions](#open-decisions-for-the-lead).
> That step is left for review-then-deploy on purpose (real users + credits live
> in that DB).

---

## The four containers

| Container | Image | Purpose | Dev port |
| --------- | ----- | ------- | -------- |
| `cockpit-api` | this repo | FastAPI app (RAG + studios) | **8100** |
| `cockpit-db` | `postgres:17` | Cockpit business data (studios, documents, jobs) | 5433 |
| `cockpit-vectordb` | `pgvector/pgvector:pg17` | RAG chunks + embeddings | 5434 |
| `cockpit-minio` | `minio/minio` | Object storage for source files | 9000 / 9001 |

Embeddings run **in-process** in the API (local, open-source — no commercial
embedding API). Generation is **OpenRouter** (OpenAI-compatible), reusing the key
Octopilot already has.

---

## Database strategy (the important part)

There are **three** databases, split by ownership — this is the key design
decision you asked me to make.

```
┌─────────────────────────────┐     ┌──────────────────────────────┐
│  octopilot  (SHARED)        │     │  cockpit  (OURS)             │
│  native PG, already running │     │  dockerized PG               │
│  • users        ← identity  │◀────│  • studios   (user_id ref)   │
│  • purchase/promo/referral  │ ref │  • documents (user_id ref)   │
│    ← credits                │     │  • ingest_jobs               │
│  • api_keys (openrouter)    │     └──────────────────────────────┘
│  • system_settings (models) │     ┌──────────────────────────────┐
│  READ-MOSTLY, we don't own  │     │  vector  (OURS)              │
└─────────────────────────────┘     │  dockerized pgvector         │
                                     │  • chunks + embeddings       │
                                     └──────────────────────────────┘
```

**Decision: share, don't split, identity & credits. Separate everything else.**

- **Do NOT duplicate users/credits into Cockpit.** They stay in the one place
  that already owns them — the native `octopilot` Postgres. Copying them would
  create a sync problem and two sources of truth for *money*. Cockpit reads
  users, checks credits, and reuses the existing `api_keys` (OpenRouter key) and
  `system_settings` (model choice) straight from that DB.
- **Cockpit business data gets its own database** (`cockpit`). It references
  `user_id` as a plain UUID with **no cross-DB foreign key** — ownership is
  enforced in the app (every query filters by `user_id`). Separate DB = our own
  migrations, our own backups, and we can rebuild it without any risk to
  Octopilot's data.
- **RAG vectors get their own database** (`vector`, pgvector). Embeddings are a
  different lifecycle from business rows — you re-embed when you change models,
  re-index for performance, etc. Isolating them means none of that touches
  studios/credits.

**Why not one big shared Postgres, or one Cockpit Postgres for everything?**
Money and identity must have a single owner (Octopilot) — so we read, not
mirror. App data and a mutable vector index shouldn't share a blast radius with
that financial DB, so they’re separate containers we fully control. Best of both:
shared truth for users/credits, isolated ownership for everything Cockpit-specific.

### Tenancy
Every Cockpit row (`studios`, `documents`, `chunks`) and every object-storage key
(`{user_id}/{document_id}/{filename}`) carries the `user_id`. Retrieval filters by
user **inside** the SQL, so one user can never read another user's material.
(The model allows scoping by more than user later — e.g. org/team — by extending
the key prefix and the `WHERE` clause.)

---

## RAG pipeline

**Ingest** (background task after upload):
```
object storage → extract text → chunk (512 tok / 64 overlap)
             → embed (local BGE-m3) → pgvector (chunks + tsvector)
```
**Ask** (`POST /ask`):
```
embed question → hybrid search (dense cosine + lexical BM25, fused by RRF,
                 tenant-scoped) → top-k context → OpenRouter → answer + citations
```
Citations are prompt-driven (context blocks numbered `[1..n]`), not a
provider-native feature — portable across models.

---

## Local development

```bash
cd Backend
cp .env.example .env          # defaults work for local; EMBEDDINGS_BACKEND=fallback
make up                       # build + start the 4 containers
make init                     # create schemas (studios/…, chunks + pgvector)
curl localhost:8100/health
open http://localhost:8100/docs   # interactive API
```

The default `.env` uses the **fallback embedder** (deterministic, no model
download) so the stack boots instantly. Flip `EMBEDDINGS_BACKEND=sentence-transformers`
to use the real BGE-m3 model (downloads weights on first call).

Try it:
```bash
UID=$(python -c "import uuid;print(uuid.uuid4())")
SID=$(curl -s -XPOST localhost:8100/studios -H "X-User-Id: $UID" \
      -H 'content-type: application/json' -d '{"title":"Bio"}' | jq -r .id)
echo "hello routing subnet" > note.txt
curl -s -XPOST "localhost:8100/studios/$SID/documents" -H "X-User-Id: $UID" -F file=@note.txt
curl -s -XPOST localhost:8100/ask -H "X-User-Id: $UID" \
     -H 'content-type: application/json' -d "{\"studio_id\":\"$SID\",\"question\":\"routing?\"}"
```

Run tests (offline, no DB/network):
```bash
make test      # or: pytest -q
```

Sample study notes for upload testing (does not call the API):
```bash
python -m scripts.generate_sample_materials \
  --count 4 --subject biology --size short --out ./sample_materials
```
See [scripts/README.md](scripts/README.md) for subjects, sizes, and more examples.

---

## Deploying to the server

The server (`187.124.92.119`, Ubuntu 24.04) already has docker, docker compose,
nginx, and the **native** `octopilot` Postgres on `127.0.0.1:5432`.

1. Copy `Backend/` to the server, create `.env` from `.env.example`, and set:
   - `APP_ENV=prod`
   - `SHARED_DATABASE_URL=postgresql+asyncpg://octopilot:***@host.docker.internal:5432/octopilot`
   - `EMBEDDINGS_BACKEND=sentence-transformers`
2. **Let the API container reach the native Postgres.** It binds `127.0.0.1`
   only, so either:
   - add the docker bridge subnet to `pg_hba.conf` + set
     `listen_addresses` to include the docker gateway, **or**
   - keep PG on loopback and run the API with `network_mode: host`.
   The prod overlay adds `host.docker.internal:host-gateway` for option 1.
   - `FIREBASE_CREDENTIALS=/srv/secrets/firebase-service-account.json` (copy the
     service-account JSON from octopilot) and `ALLOW_DEV_USER_HEADER=false`.
3. Run the deploy script on the server (idempotent — builds, starts the prod
   overlay, creates schemas, checks health):
   ```bash
   bash deploy/deploy.sh
   ```
4. Put nginx in front: `deploy/nginx-cockpit.conf` proxies `127.0.0.1:8100` with
   SSE-friendly settings; then `certbot` for TLS. Only the API is exposed;
   `cockpit-db`, `cockpit-vectordb`, and MinIO stay on the internal docker
   network.

Nothing above has been run against the live server yet — it's the reviewed
go-live step (production data + credits live in the shared DB).

---

## API

| Method | Path | Purpose |
| ------ | ---- | ------- |
| GET | `/health`, `/ready` | liveness / readiness |
| POST | `/studios` | create a studio |
| GET | `/studios`, `/studios/{id}` | list / get |
| POST | `/studios/{id}/documents` | upload file → ingest (202) |
| GET | `/studios/{id}/documents` | list documents |
| POST | `/ask` | RAG question → answer + citations |

Auth is a header (`X-User-Id`) **placeholder** for now — see below.

---

## Open decisions for the Lead

Deliberately **not** guessed — these need your confirmation before go-live:

1. **Auth.** Firebase ID-token verification is wired (`app/auth.py`, reuses
   Octopilot's Firebase). To turn it on: set `FIREBASE_CREDENTIALS` (service
   account from octopilot) + `ALLOW_DEV_USER_HEADER=false`, and on the client
   pass the Firebase web config via `--dart-define` (see study_studio
   `firebase_bootstrap.dart`). Refinement: map the token's uid/email to the real
   octopilot `users.id` (currently a deterministic uuid5 of the uid).
2. **Credits ledger.** The exact credit table/columns weren't confirmed, so
   `CreditsService.debit()` is a **no-op** and `check()` fails open — the backend
   never mutates real financial tables on a guess. Point it at the right ledger
   and implement debit. → `app/services/credits.py`.
3. **Binary text extraction.** `extract_text()` handles text/markdown; PDF/docx
   need pypdf/python-docx wired in. → `app/services/rag.py`.
4. **Embedding model / dim.** Defaulted to BGE-m3 (1024-dim). If you change the
   model, update `EMBEDDING_DIM` and re-create the `chunks` table.

---

## Security notes

- `## Server Access.md` (server + DB credentials) is **gitignored** — do not
  commit it. `.env` is gitignored too. Rotate anything that has been shared in
  plaintext.
- The shared DB should be reached by a **least-privilege** DB role (read users,
  read api_keys/settings, and — once defined — write only the credit ledger),
  not the superuser `octopilot` account.
- Databases and MinIO are not published on public ports in the prod overlay.

## Layout

```
Backend/
  app/
    main.py          config.py   db.py   deps.py   schemas.py
    models/          cockpit.py  vector.py  shared.py
    services/        embeddings.py  vectorstore.py  objectstore.py
                     llm.py  credits.py  rag.py
    routers/         health.py  studios.py  documents.py  ask.py
  scripts/           init_databases.py  generate_sample_materials.py
                     sample_materials_catalog.py  README.md
  tests/             test_units.py  test_generate_sample_materials.py
  docker-compose.yml  docker-compose.prod.yml  Dockerfile  Makefile
  requirements.txt    .env.example
```

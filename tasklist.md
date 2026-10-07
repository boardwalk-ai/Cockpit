# Study Studio — task list

_Last updated: 2026-10-07_

## API hardening (from the endpoint audit)

User/studio scoping is fine: every data endpoint needs a Firebase token (the
`X-User-Id` dev header is off in production), checks the studio's owner or
filters by `user_id`, and RAG retrieval filters `user_id + studio_id` in SQL.
What's left is idempotency and AI-cost abuse. Suggested first: A1, A5, A6.

- [ ] **A1. One build at a time per studio** — `POST /studios/{id}/build` starts a
  new build on every call, so a double tap, a retry or Update studio during a
  running build races two builds (topics mixed/duplicated, double AI cost).
  Fix: if a build for the studio is queued/running, return its `buildId`
  instead of starting another.
- [ ] **A2. Card reviews and quiz answers idempotent** — a retried
  `flashcards/{card}/review`, `quiz-result` or `flashcard-review` advances SM-2
  twice, moves mastery twice and logs `study_events` twice.
  Fix: the app sends an `event_id` (uuid) per answer; unique
  `(user_id, event_id)` on `study_events`; skip duplicates. _(DB index)_
- [ ] **A3. `mark-reviewed` counts once a day** — every "Got it" adds +3%
  mastery. Fix: once per topic per day.
- [ ] **A4. Create studio / upload idempotent** — a retry after a lost response
  makes a second studio or a duplicate document (duplicate chunks in RAG).
  Fix: `Idempotency-Key` header from the app (per studio, per picked file),
  stored on the row; same key → return the existing one. _(DB column)_
- [ ] **A5. Protect AI credit on `/ask`** — no studio-owner check, no length cap on
  `q`, no rate limit, no credit debit: any signed-in user can drain OpenRouter.
  Fix: owned-studio check, `q` ≤ 2000 chars, per-user rate limit
  (e.g. 30 / 10 min); same limit on `/connections` and `/topics/{id}/concepts`.
- [ ] **A6. Tag OpenRouter calls with the user** — pass `user: <cockpit user id>`
  on every LLM call so usage can be traced per user.
- [ ] **A7. Small ones** — auth on `GET /studios/{id}/topics/{tid}` (seed demos
  only today); cap upload size (e.g. 50 MB per file).

## Still to build

- [ ] **Notification system** — build finished, study-plan reminders, cards due
- [ ] **Store** — buying OctoCredits in the app
- [ ] **Credit deduction** — charge OctoCredits for builds, Ask AI, concept
  maps (today `/ask` and builds charge nothing)
- [ ] **Ingestion** — see the next two sections (fix now, then Rust)

## Ingestion — where it stands (checked on production 2026-10-07)

Today's pipeline: upload → MinIO → Redis queue → Go worker (`cockpit-worker`):
extract (Hirara `pdf_read` / `ocr_read` / `office_read`) → split every 512
words (64 overlap) → insert chunks with a **hash placeholder vector**, mark the
document ready → then ask `cockpit-embed` (bge-m3, 1024-d) for the real vectors.
Search: Go `/search` (embeds the query, then pgvector HNSW + English `tsv`,
fused with RRF). Builds: outline from up to 120k chars of material, then each
lesson retrieves its top 8 chunks; on failure it gets all of the material.

| What | Finding |
|---|---|
| Embed service | **Fails every call**: ~94 s, then HTTP 500 ("Cannot copy out of meta tensor" loading bge-m3). Failing since at least 2026-09-12. |
| Vectors | **54 of 62 chunks (87%) are hash placeholders**; 8 real. Never retried. |
| Ask AI | Query embed fails → `/search` 500 → `/ask` swallows it → the AI answers with **no notes**, after a ~94 s wait. |
| Builds | Retrieval fails per lesson → **the whole material (≤120k chars) goes into every lesson**: grounded, but slow and costly; lesson sources come out empty. |
| Chunks | ~3,100 chars each; no headings or page numbers (citations can't say "p.12"). |
| Languages | OCR `en` only; keyword search `english` only (Burmese gets no lexical match). bge-m3 itself is multilingual. |
| Small bugs | `extract.Usable()` always assumes 1 page; lesson Ask AI doesn't send its topic to `/ask`. |
| Indexes | Fine: HNSW (cosine) on `embedding`, GIN on `tsv`, btree on user/studio. |

## Ingestion — fix now (current Python/Go stack)

- [x] **F1. Repair `cockpit-embed`** _(done 2026-10-07: `transformers==4.46.3`, loads at startup, `/ready`; embed 0.19 s)_ — pin `torch` / `transformers` /
  `sentence-transformers` to versions that load bge-m3; load once at startup
  on CPU (no lazy/meta init); `/ready` only after a real test embed; alert if
  it fails.
- [x] **F2. Re-embed the backlog** _(done 2026-10-07: 54 re-embedded, 62/62 real; retrieval spot-check OK)_ — add `embedded boolean` to `chunks`
  (placeholders = false); one-off job embeds them in batches of 32 and flips
  the flag. Recheck: 62/62 real.
- [ ] **F3. Ready only when embedded** — worker sets the document `embedding`
  → `ready` after real vectors land; retry with backoff (3 tries), then
  `failed` with a reason the app can show. No placeholders written.
- [ ] **F4. Fail fast and say so** — 3 s timeout on query embedding; on failure
  search lexical-only and send `retrieval: "degraded"` so the answer can say it
  didn't search the notes. Never swallow silently.
- [ ] **F5. Cap lesson context** — when retrieval fails, pick chunks by title
  words (lexical) and cap at ~16k chars per lesson, not the whole material.
- [ ] **F6. Pages and headings** — extract per page; split on headings /
  paragraphs, 300–500 tokens with ~50 overlap; store `page` and `heading` on
  each chunk; send them with citations ("Lecture 5.pdf · p.12").
- [ ] **F7. Burmese** — OCR languages `en` + `my`; `tsv` with the `simple`
  config (language-neutral) alongside `english`.
- [ ] **F8. Lesson Ask AI sends the topic** (`ApiAiService.teach` → `topic`).
- [ ] **F9. Measure it** — a 30-question set from a real studio (question →
  chunk that answers it); report recall@5 before/after; log the hits used for
  each answer.

## Rust migration plan (Study Studio backend)

**Goal:** one Rust service, `study-api`, a new crate in `backend-rs/`, replaces
`cockpit-api` (Python) and `cockpit-worker` / `cockpit-gateway` (Go). The
HTTP + SSE contract stays the same, so the app doesn't change.

**Reuse what's there:**
- `octo-common`: Firebase auth (`AuthedUser`), identity, OctoCredits, DB helpers
- `octonotes-api` patterns: `idempotency.rs`, durable `jobs.rs` worker,
  `outbox.rs`, `retrieval.rs`, metrics
- Workspace crates: `sqlx` + `pgvector`, `rust-s3` (MinIO), `redis`, `reqwest`
- Push: the FCM sender in `ghostwriter-api` (`push.rs`)

**Keep:**
- The cockpit + vector Postgres schemas (no data migration)
- MinIO
- Hirara (OCR / office extraction)

**Embeddings:** run bge-m3 on Hugging Face **text-embeddings-inference**
(TEI, written in Rust, serves bge-m3 over HTTP) instead of the Python
sentence-transformers sidecar.

| Phase | Scope | Done when |
|---|---|---|
| **R0 Freeze the contract** _(started: studio DTOs compared field by field against Python on all 14 production studios — identical)_ | List every endpoint + SSE event shape; generate OpenAPI (`utoipa`); record golden responses from today's API | Golden tests run against Python |
| **R1 Skeleton + reads** _(in progress: `crates/study-api` — `/health`, `/ready`, `/me`, `/studios`, `/studios/{id}` incl. source files; SM-2 port; 5 unit tests; built on the server, run once in loopback shadow mode, stopped)_ | Crate, config, auth, DB pools, `/health` `/ready`; `/me`, `/studios`, `/studios/{id}` (mastery + SM-2 overlays) | Golden read tests pass on Rust |
| **R2 Progress writes** | quiz-result, card review (SM-2 port), mark-reviewed (once/day), rename, delete, activity, `study_events` — all with `event_id` idempotency (A2, A3) | Retries change nothing |
| **R3 Ingestion** | Upload (Idempotency-Key, 50 MB cap) → Postgres job queue → extract per page → heading-aware chunks → TEI → `ready` only when embedded; re-embed job; metrics (F1–F7) | 100% real vectors; recall@5 at target |
| **R4 Retrieval + AI** | Hybrid search (HNSW + `simple`/`english` tsv, RRF); `/ask` SSE with history + topic; OpenRouter client (`max_tokens`, `user`); OctoCredits check + debit; per-user rate limits (A5, A6) | Ask AI cites pages; credits move |
| **R5 Build pipeline** | Outline / lesson / scenarios / concepts / connections ported with the same prompts; one build per studio (A1); ids kept on rebuild; capped context | Same studio from the same files |
| **R6 Notifications** | Build finished, cards due, plan reminders over FCM (outbox) | Push arrives on the phone |
| **R7 Cut over** | Gateway routes path by path to Rust (reads first), compares responses; then all traffic; Python + Go kept 2 weeks for rollback, then removed | `cockpit-api` / worker / gateway off |

**Risks:**
- **Prompt and JSON parity:** copy prompts verbatim; keep camelCase DTOs and the `"from"` alias.
- **SSE semantics:** keep the event names (`data`, `delta`, `citations`, `meta`, `error`, `done`).
- **SM-2 numbers:** test against the Python implementation with the same inputs.
- **Running both sides:** only one writer per table at a time during the cutover.

## Pricing and credit deduction

The business draft (Study Studio Pricing.pdf) values **100 credits = $1 of AI
cost**. At that rate every pack and plan loses money: 1,000 credits sold for
$4.99 cost $10; Pro ($4.99) can use $20; Premium ($9.99) $50; each Free user
$5/month. "Round $1.40 up to $2" per action would charge an Ask AI turn
(~1.5¢) 100 credits. A 10% markup doesn't cover store fees (15–30%),
payments, servers and free users.

- [ ] **P1. Meter every AI call** — request OpenRouter `usage` (tokens + exact
  USD cost) and send `user`; store in `llm_usage` (user, studio, feature,
  model, tokens in/out, cost_usd, request id). Pairs with A6.
- [ ] **P2. Benchmark** — build ~20 studios of different sizes, run each feature;
  per-feature average and worst-case cost from `llm_usage`.
- [ ] **P3. Re-base the credit** — e.g. 1,000 credits = $1 of AI cost, a ×2–3
  markup; round up to the next credit, not the next dollar; recompute plan
  allowances and packs from P2.
- [ ] **P4. Deduction** — small actions (Ask AI, concept map, regenerate quiz):
  fixed prices; big ones (studio build, PDF analysis, transcription): quote
  before starting (pages / characters) → **hold** → settle at the real cost,
  never above the quote; refund on failure. Reuse the OctoCredits hold/settle
  in `octo-common` / OctoNotes.
- [ ] **P5. Cut costs** — fix retrieval (F1–F5, ~40% off builds); cheaper model
  for flashcards / quiz / concepts, Sonnet for lessons; prompt caching of the
  shared material; per-plan caps on pages and lessons.
- [ ] **P6. Margin dashboard** — monthly revenue vs AI cost per feature and plan.

**Models in production (checked 2026-10-07):**

| Task | Model | OpenRouter price per 1M tokens (in / out / cached in) |
|---|---|---|
| Studio build (outline, lessons, scenarios) | `google/gemini-3.1-flash-lite-preview` (`secondary_model` in `system_settings`) | $0.25 / $1.50 / $0.025 |
| Ask AI, concept maps, connections | `anthropic/claude-sonnet-4-6` (primary key's model) | $3.00 / $15.00 / $0.30 |
| (env default, unused when the DB setting exists) | `anthropic/claude-opus-4.6` | $5 / $25 |

Rough costs (40-page PDF, 10 lessons — estimates until P1/P2): build
**~$0.08** with retrieval working, **~$0.15** as it is now; Ask AI ~$0.015;
concept map ~$0.03; reviewing cards / quizzes / recall $0.

## Pricing survey (one full run — after credit top-up, Rust backend, embedding fix)

Goal: exact cost per feature from OpenRouter's own numbers, and the
quality-vs-cost trade-off of switching models, to set P3/P4.

- [ ] **S1. Ready to measure** — every call records OpenRouter's `id`
  (generation id), model, provider, prompt / completion / cached tokens,
  `usage.cost` (USD), latency, retries, JSON-parse failures, `build_id`,
  feature, user. Cross-check a sample against `GET /api/v1/generation?id=`.
- [ ] **S2. Fixed corpus** (same files for every model): 5-, 20-, 40- and
  100-page PDFs; a slide deck; a scanned PDF (OCR); a DOCX of notes; a
  Burmese document.
- [ ] **S3. Fixed workload** per studio: full build; concept map for every
  lesson; connections; 20 Ask AI questions (incl. follow-ups and one off-topic).
- [ ] **S4. Model matrix**
  - Build (lessons): gemini-3.1-flash-lite (now), gemini-3-flash, gpt-5-mini,
    deepseek-v3.2, qwen3.7-plus, claude-haiku-4.5, claude-sonnet-4.6 (ceiling)
  - Ask AI / concepts: claude-sonnet-4.6 (now), claude-haiku-4.5,
    gemini-3-flash, gpt-5-mini, deepseek-v3.2
- [ ] **S5. Quality** — rubric 1–5: faithful to the source (no invented
  facts), covers the source's key points, clear, quiz answers correct, valid
  JSON, handles Burmese. Scored blind by a strong judge model (random order)
  on everything, plus a human spot-check of 10% (IT + a student / teacher).
- [ ] **S6. Report** — per feature × model: average and p90 cost, latency,
  quality score, failure rate; build cost as *fixed + per page*; the model to
  use for each task; the credit price table (feeds P3, P4 and the boss page).
- [ ] **Budget cap ~$60** (≈56 builds ≈ $17, ≈800 Ask AI answers ≈ $8,
  judging ≈ $30); stop if it passes the cap.

## Data platform (one server: 4 cores, 16 GB, 8 Postgres instances today)

**Decision:** Postgres now for everything. Scylla later, only when there is a
3-node cluster and append-only data reaches TB scale or tens of thousands of
writes/s. Scylla on one shared 4-core box gives no replica, fights the other
services for cores and RAM, and loses its speed edge.

| Data | Postgres | Scylla (later) |
|---|---|---|
| Users, identity, OctoCredits ledger, store / payments | always (ACID) | never |
| Studios, topics, concepts, plans | yes | no |
| RAG chunks + vector search | yes (pgvector + `tsv`) | no |
| Idempotency keys, job queue, outbox | yes (same transaction) | no (LWT is slow) |
| `study_events`, activity, notifications inbox, push log, Ask AI history, LLM usage, OctoNotes realtime ops | yes now (monthly partitions) | candidates |

In Rust, the "candidates" go behind a repository trait so a Scylla store can
replace the Postgres one without touching the API.

**Plan:**
- [ ] **D1. Off-site backups first** _(2026-10-07: all 9 databases dumped to `/opt/backups/db-20261007-093320` + IT PC copy; **nightly dumps of octo-pg at 03:15**, kept 14 days in `/opt/backups/nightly`; cloud copy + WAL still to do)_: pgBackRest or WAL-G →
  Cloudflare R2 / Backblaze B2 — continuous WAL + weekly full, point-in-time
  restore; MinIO → R2 nightly with `rclone`. **Test a restore monthly.**
- [x] **D2. One Postgres 17 cluster (+ pgvector)** — `octo-pg`, `127.0.0.1:5440`
  (`backend-rs/deploy/octo-pg`). One database per app for now (schemas per
  app later, with the Rust services); app roles keep their passwords, no
  superusers. Interns now reach `cockpit` on port **5440** (was 5433).
- [ ] **D3. PgBouncer** (transaction pooling) in front of every app.
- [x] **D4. Databases moved 2026-10-07** — cockpit + vector, ghostwriter +
  octopilot_staging, octonotes, octopilot (main). Each: writers stopped, final
  dump, restore, every table's row count identical, old DB set read-only,
  configs to 5440, apps healthy, no DB errors, grants identical. The
  octopilot-api container was recreated from the same image with
  `DATABASE_URL` from `/opt/octopilot-api/runtime.env` (old container kept as
  `octopilot-api-pre-octopg`). Old instances read-only until **2026-10-21**,
  then last dump and remove. Labs, MBR and octopilot-legacy were not moved.
- [ ] **D5. Retention:** (OctoNotes `jobs` is already ~31k rows and growing — clean up finished jobs.) monthly partitions for `study_events`, notifications,
  LLM usage; after 12 months keep daily rollups, drop raw partitions.
- [ ] **D6. Vectors:** HNSW must fit in RAM (~5 GB per 1M bge-m3 chunks);
  past ~1M chunks use `halfvec` or a separate server.
- [ ] **D7. Monitoring:** `pg_stat_statements`, disk, last successful backup,
  replication lag on `/metrics`, with alerts.
- [ ] **Scale order:** 1) streaming replica on a cheap second VPS (failover +
  read offload); 2) AI embed / build workers on their own box; 3) Scylla
  cluster for the candidate tables.

**Safe move (each database, no data loss):**
1. Fresh off-site backup of the source, plus a restore test of it (D1 done first).
2. Rehearse on a copy: `pg_dump -Fc` → `pg_restore` into the new cluster,
   compare row counts and checksums for every table, run the app's tests
   against it.
3. Real move in a short write freeze: stop the app's writes (maintenance
   mode), final dump/restore (or logical replication for zero downtime),
   verify counts and checksums again.
4. Point the app at the new cluster; smoke-test.
5. Keep the old instance **read-only, untouched, for 2 weeks** — rollback is
   switching the connection string back. Only then remove it (after one more
   backup).

## Ops

- [ ] **Top up OpenRouter credit** — the balance is very low (calls without a
  `max_tokens` cap were refused with 402). All calls are capped now
  (`13b5a2a`), but builds, Ask AI and concept maps will fail once it runs out.

## Not yet tried on a real phone

- [ ] Lightning recall: hold-to-talk (STT) and questions read aloud (TTS)
- [ ] Ask AI: answers stream word by word (the gateway may buffer SSE)
- [ ] Visualize: AI-made concept maps (older studios make them on first open)
- [ ] Studio settings: PDF / Anki export through the share sheet
- [ ] Update studio (add files + rebuild): progress kept on returning lessons
- [ ] Mastery report "This week" (activity log started 2026-10-07)
- [ ] Welcome-back sheet (shows after 3+ days away)

## Follow-ups

- [ ] Push notification when a build finishes; "Building x%" on the home row
- [ ] Server AI grading for spoken Lightning recall answers
- [ ] Cap Quiz me at ~10 questions
- [ ] Study plan reminders (notifications)
- [ ] One name per concept across a studio (merge near-duplicates)
- [ ] Burmese font in the PDF export
- [ ] Desktop pages still on the old design (several show mock data:
  Analytics, Ask AI, Manage, Welcome back, Study plan)

## State

- All work is in local commits in this repo (not pushed).
- Backend changes are deployed to `cockpit-api`; backups under
  `/opt/cockpit/backup-*` on the server.

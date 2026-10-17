# Study Studio — task list

_Last updated: 2026-10-07_

## API hardening (from the endpoint audit)

User/studio scoping is fine: every data endpoint needs a Firebase token (the
`X-User-Id` dev header is off in production), checks the studio's owner or
filters by `user_id`, and RAG retrieval filters `user_id + studio_id` in SQL.
What's left is idempotency and AI-cost abuse. Suggested first: A1, A5, A6.

- [x] **A1. One build at a time per studio** _(2026-10-07, live on Rust)_ _(server side done in Rust R5: a second start returns the running build's id; tested with two starts → same id)_ — `POST /studios/{id}/build` starts a
  new build on every call, so a double tap, a retry or Update studio during a
  running build races two builds (topics mixed/duplicated, double AI cost).
  Fix: if a build for the studio is queued/running, return its `buildId`
  instead of starting another.
- [x] **A2. Card reviews and quiz answers idempotent** _(2026-10-07, live on Rust; app sends `event_id` and retries a dropped answer once)_ _(server side done in Rust R2: `event_id` = `study_events.id`, no schema change; app to send it)_ — a retried
  `flashcards/{card}/review`, `quiz-result` or `flashcard-review` advances SM-2
  twice, moves mastery twice and logs `study_events` twice.
  Fix: the app sends an `event_id` (uuid) per answer; unique
  `(user_id, event_id)` on `study_events`; skip duplicates. _(DB index)_
- [x] **A3. `mark-reviewed` counts once a day** _(Rust R2: once per lesson per 20 h)_ — every "Got it" adds +3%
  mastery. Fix: once per topic per day.
- [x] **A4. Create studio / upload idempotent** _(2026-10-07, live on Rust; `Idempotency-Key` on create studio + each picked file, app retries once; e2e: 2 creates → 1 studio, 2 uploads → 1 document)_ — a retry after a lost response
  makes a second studio or a duplicate document (duplicate chunks in RAG).
  Fix: `Idempotency-Key` header from the app (per studio, per picked file),
  stored on the row; same key → return the existing one. _(DB column)_
- [x] **A5. Protect AI credit on `/ask`** _(2026-10-07, live on Rust; owner check + 2,000-char cap; **no rate limit** (the user's call: every AI call is paid in credits))_ _(in Rust R4)_ — no studio-owner check, no length cap on
  `q`, no rate limit, no credit debit: any signed-in user can drain OpenRouter.
  Fix: owned-studio check, `q` ≤ 2000 chars, per-user rate limit
  (e.g. 30 / 10 min); same limit on `/connections` and `/topics/{id}/concepts`.
- [x] **A6. Tag OpenRouter calls with the user** _(2026-10-07, live on Rust: every call sends `user`)_ _(in Rust R4 for Ask AI)_ — pass `user: <cockpit user id>`
  on every LLM call so usage can be traced per user.
- [x] **A7. Small ones** _(2026-10-07, live on Rust: the demo topic endpoint isn't served any more; 50 MB upload cap)_ — auth on `GET /studios/{id}/topics/{tid}` (seed demos
  only today); cap upload size (e.g. 50 MB per file).

## Still to build

- [x] **Notification system** _(R6; FCM key installed 2026-10-07 — push is on)_ — build finished, study-plan reminders, cards due
- [x] **Store** — buying OctoCredits in the app _(2026-10-07: tap the credits pill → 6 packs ($0.99–$39.99) → Stripe Checkout through octopilot-api `POST /billing/checkout-session`; its webhook adds to the shared `users.octo_credits`; the balance re-reads on return. Not yet tried with a real payment)_
- [x] **Credit deduction** _(2026-10-07: prices come from the admin side, see P4)_ — charge OctoCredits for builds, Ask AI, concept
  maps (today `/ask` and builds charge nothing)
- [x] **Ingestion** _(Rust R3, live)_ — see the next two sections (fix now, then Rust)

## Share links (2026-10-08, live)

- [x] **Share a studio by link** — Studio settings → SHARE → "Share link"
  turns the link on (`https://studystudio.octopilothub.com/s/CODE`, 10
  characters) and opens the share sheet; "Stop sharing" turns it off (no new
  copies; copies made stay). Opening the link (Android App Link, verified)
  shows who shared it and what's in it → "Add to my studios" makes the user's
  own copy: lessons, cards, quizzes, scenarios, concept maps and the passages
  (vectors copied, no AI), every topic/card/quiz id new so progress is
  separate, files not copied (names kept as sources), "Shared by …" kept.
  Copying is free; AI on the copy is paid by its owner. Server:
  `study-api/src/share.rs`, e2e `deploy/study-api/share_e2e.sh`; web:
  `deploy/share-web/` (assetlinks + the page for people without the app).
- [ ] Add the Play / App Store signing key to `assetlinks.json` (today only
  the debug key that signs the staging APKs); iOS Universal Links.
- [ ] Show "Shared by …" on the studio page (the API sends `sharedBy`).

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
- [x] **F3. Ready only when embedded** _(2026-10-07, live on Rust)_ _(in Rust R3)_ — worker sets the document `embedding`
  → `ready` after real vectors land; retry with backoff (3 tries), then
  `failed` with a reason the app can show. No placeholders written.
- [x] **F4. Fail fast and say so** _(2026-10-07, live on Rust)_ — 3 s timeout on query embedding; on failure
  search lexical-only and send `retrieval: "degraded"` so the answer can say it
  didn't search the notes. Never swallow silently.
- [x] **F5. Cap lesson context** _(2026-10-07, live on Rust)_ — when retrieval fails, pick chunks by title
  words (lexical) and cap at ~16k chars per lesson, not the whole material.
- [x] **F6. Pages and headings** _(2026-10-07, live on Rust)_ _(in Rust R3; `chunks.page`/`heading` columns added by the Rust worker)_ — extract per page; split on headings /
  paragraphs, 300–500 tokens with ~50 overlap; store `page` and `heading` on
  each chunk; send them with citations ("Lecture 5.pdf · p.12").
- [~] **F7. Burmese** _(in Rust R3: OCR en+my, `tsv` english+simple)_ — OCR languages `en` + `my`; `tsv` with the `simple` **Dropped: US launch, no Burmese work (Rust OCR still runs en+my)**
  config (language-neutral) alongside `english`.
- [x] **F8. Lesson Ask AI sends the topic** _(2026-10-07: `teach` sends `topic`)_ (`ApiAiService.teach` → `topic`).
- [x] **F9. Measure it** _(2026-10-07 baseline: 30 questions, recall@1 0.70, **recall@5 0.90**, recall@10 0.93, MRR 0.76 — `deploy/study-api/recall_eval.py`, set kept in `/opt/study-api/eval/recall_set.json`; Ask AI logs the passages each answer used)_ — a 30-question set from a real studio (question →
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
_Done 2026-10-07: `study-embed` (TEI cpu-1.9, ONNX) on 127.0.0.1:8093 —
`deploy/embed/run-tei.sh`. Vectors equal the Python ones (cosine 1.00000 on
all 62 stored passages and on queries), so nothing was re-embedded; recall
unchanged (recall@5 0.90). Limits 6 GB / 3 CPUs; inputs capped at 2,048
tokens (an 8,192-token warm-up took 10.7 GB and was OOM-killed — the first
try spiked the box's load to 37 for ~2 minutes; nothing else was killed).
Queries ~0.1 s (Python 0.7–1.8 s). Upload → TEI → ready e2e:
`deploy/study-api/embed_e2e.sh`. The Python `cockpit-embed`, `cockpit-api`,
`cockpit-worker` and `cockpit-gateway` are stopped (restart=no;
`cutover.sh python` starts them again). `cockpit-redis` stays: OctoNotes
uses it._

| Phase | Scope | Done when |
|---|---|---|
| **R0 Freeze the contract** _(started: studio DTOs compared field by field against Python on all 14 production studios — identical)_ | List every endpoint + SSE event shape; generate OpenAPI (`utoipa`); record golden responses from today's API | Golden tests run against Python |
| **R1 Skeleton + reads** _(in progress: `crates/study-api` — `/health`, `/ready`, `/me`, `/studios`, `/studios/{id}` incl. source files; SM-2 port; 5 unit tests; built on the server, run once in loopback shadow mode, stopped)_ | Crate, config, auth, DB pools, `/health` `/ready`; `/me`, `/studios`, `/studios/{id}` (mastery + SM-2 overlays) | Golden read tests pass on Rust |
| **R2 Progress writes** _(done in Rust 2026-10-07: quiz, card review, flashcard-review, mark-reviewed once/20 h, rename, activity; same results as Python on a throwaway copy (`deploy/study-api/parity.sh`); retries with the same `event_id` change nothing — **the app still has to send `event_id`**)_ | quiz-result, card review (SM-2 port), mark-reviewed (once/day), rename, delete, activity, `study_events` — all with `event_id` idempotency (A2, A3) | Retries change nothing |
| **R3 Ingestion** _(done in Rust 2026-10-07, not live: upload (50 MB cap, safe names) → `ingest_jobs` queue with `SKIP LOCKED` workers (no Redis) → PDF text page by page, Hirara OCR en+my for scans/office/images → heading/paragraph passages ~1,600 chars with page + heading → bge-m3 with retries → ready only when embedded; e2e on a copy: 2.5 MB PDF → 32 passages, all with pages, real vectors, 52 s (`deploy/study-api/ingest_e2e.sh`). Idempotency-Key (A4) and `/metrics` done 2026-10-07; a re-embed job isn't needed — only real vectors can be written now; re-embed once if the model ever changes)_ | Upload (Idempotency-Key, 50 MB cap) → Postgres job queue → extract per page → heading-aware chunks → TEI → `ready` only when embedded; re-embed job; metrics (F1–F7) | 100% real vectors; recall@5 at target |
| **R4 Retrieval + AI** _(done in Rust 2026-10-07, not live: in-process hybrid search (same top 5 as Go on a test question), `/ask` SSE with history + topic + pages in citations, owner check, 2,000-char cap, 30 per 10 min, `max_tokens`, `user`, `usage` → `llm_usage`; embedder down → keyword search + `retrieval: degraded`. **Credit debit not wired yet** — waits for P3 prices)_ | Hybrid search (HNSW + `simple`/`english` tsv, RRF); `/ask` SSE with history + topic; OpenRouter client (`max_tokens`, `user`); OctoCredits check + debit; per-user rate limits (A5, A6) | Ask AI cites pages; credits move |
| **R5 Build pipeline** _(done in Rust 2026-10-07, not live: prompts byte-identical to Python (fixture test), builds are DB jobs that resume after a restart (tested: killed at 5/8, finished 8/8), one build per studio, outline made before the studio is cleared and old topics put back if no lesson is written, capped lesson fallback (24k chars, was 120k), every call metered with its `build_id`; connections + concepts made once under a double tap (row lock: 2 taps → 1 call); create / delete studio. Off by default: `BUILD_WORKER=1`)_ | Outline / lesson / scenarios / concepts / connections ported with the same prompts; one build per studio (A1); ids kept on rebuild; capped context | Same studio from the same files |
| **R6 Notifications** _(done in Rust 2026-10-07: outbox for studio ready/failed, plan reminders, evening due-cards nudge; devices + plan endpoints; `notify_e2e.sh`. **No push yet: the Firebase service-account key isn't on the server** (`FCM_SERVICE_ACCOUNT_FILE` in `/opt/study-api/app.env`, then restart))_ | Build finished, cards due, plan reminders over FCM (outbox) | Push arrives on the phone |
| **R7 Cut over** _(2026-10-07: `study-api` runs as systemd on 127.0.0.1:8110 (`deploy/study-api/install.sh`, `deploy.sh`); reads compared on all 14 studios — identical; nginx now sends **all** `api.octopilothub.com` traffic to Rust with its ingest/build workers on (`cutover.sh all`; rollback `cutover.sh python`). Python + Go containers still running, idle, for rollback until **2026-10-21**. Still to do: a real-phone pass on Rust (sign in, open studio, review cards, upload, build, Ask AI), then stop cockpit-api/worker/gateway)_ | Gateway routes path by path to Rust (reads first), compares responses; then all traffic; Python + Go kept 2 weeks for rollback, then removed | `cockpit-api` / worker / gateway off |

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

- [x] **P1. Meter every AI call** _(2026-10-07: every call metered — ask, builds, concepts, connections, grade)_ _(Rust R4: Ask AI metered. First real number on 2026-10-07: one answer = 8,230 prompt + 252 completion tokens = **$0.0285** with today's ~3,100-char chunks; the R3 passages (~950 chars) should cut the prompt by about two thirds)_ — request OpenRouter `usage` (tokens + exact
  USD cost) and send `user`; store in `llm_usage` (user, studio, feature,
  model, tokens in/out, cost_usd, request id). Pairs with A6.
  _Rust R5: builds metered per `build_id`. First build number (2026-10-07,
  copy of a real studio: 2 passages / 5,900 chars → 8 lessons, 50 cards, 4
  scenarios on gemini-3.1-flash-lite): **$0.025 per build**, 10 calls,
  18k tokens in / 14k out; lessons ≈ 85 % of it. Sonnet calls: connections +
  one concept map = $0.017. Bigger studios scale with lesson count — P2
  measures that._
- [ ] **P2. Benchmark** _(2026-10-08 first pass, thinking off, numbers from OpenRouter usage — `deploy/study-api/bench.sh` / `bench.py`, results in `/opt/study-api/bench/results`:
  | run | material | lessons | build $ | time |
  |---|---|---|---|---|
  | Flash Lite, 1 PDF (9 p, 31k chars) | | 7 | 0.0276 (fixed 0.0072 + 7×0.0029) | 17 s |
  | GLM 5.3 Flash, same | | 19 | 0.0349 (fixed 0.0045 + 19×0.0016) | 373 s |
  | Flash Lite, 2 PDFs + JPG + PPTX (63 p, 186k chars) | | 10 | 0.0438 (fixed 0.0165 + 10×0.0027) | 22 s |
  | GLM 5.3 Flash, same | | 17 | 0.0385 (fixed 0.0101 + 17×0.0017) | 416 s |
  Ask AI (Sonnet 4.6) $0.0087–0.0097 an answer; recall grading $0.00004–0.00007. GLM's thinking can't be turned off (400 "Reasoning is mandatory"): the client falls back to `effort: minimal` → ~0 thinking tokens. Found: the 120k-char outline cap left part of chapter 2 without lessons; OCR of a photo can come back empty while the box is busy (now retried); one Flash Lite scenario reply couldn't be parsed (now logged))_ — build ~20 studios of different sizes, run each feature;
  per-feature average and worst-case cost from `llm_usage`.
- [ ] **P3. Re-base the credit** — e.g. 1,000 credits = $1 of AI cost, a ×2–3
  markup; round up to the next credit, not the next dollar; recompute plan
  allowances and packs from P2.
- [x] **P4. Deduction** _(2026-10-07 mechanism live, free until priced. Admin sets `system_settings`: `study_price_<feature>` (fixed: ask, concepts, connections, build, grade) or `study_credits_per_usd` (real OpenRouter cost × rate, rounded up, ≥1). Short → 402 `insufficient_credits` before any AI call; charged once per call (`credit_ledger.source_ref` `study:<feature>:…`); builds charged the sum of their calls only when they succeed, never on failure; the app shows the server's message. e2e: `credits_e2e.sh`)_ — small actions (Ask AI, concept map, regenerate quiz):
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
  100-page PDFs; a slide deck; a scanned PDF (OCR); a DOCX of notes.
- [ ] **S3. Fixed workload** per studio: full build; concept map for every
  lesson; connections; 20 Ask AI questions (incl. follow-ups and one off-topic).
- [ ] **S4. Model matrix**
  - Build (lessons): gemini-3.1-flash-lite (now), gemini-3-flash, gpt-5-mini,
    deepseek-v3.2, qwen3.7-plus, claude-haiku-4.5, claude-sonnet-4.6 (ceiling)
  - Ask AI / concepts: claude-sonnet-4.6 (now), claude-haiku-4.5,
    gemini-3-flash, gpt-5-mini, deepseek-v3.2
- [ ] **S5. Quality** — rubric 1–5: faithful to the source (no invented
  facts), covers the source's key points, clear, quiz answers correct, valid
  JSON. Scored blind by a strong judge model (random order)
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
- [x] **D1. Backups** _(2026-10-07: no cloud — the user's call. `tools/backup/pull-snapshot.sh` makes a zip on the server (every DB in octo-pg + labs/mbr/legacy/gw-staging, MinIO files, configs; dumps checked) and downloads it to `H:/Backups/octopilot`, checksum compared. First: `snapshot-20261007-1453.zip`, 125 MB. Nightly server dumps of octo-pg stay as they were)_  _(2026-10-07: all 9 databases dumped to `/opt/backups/db-20261007-093320` + IT PC copy; **nightly dumps of octo-pg at 03:15**, kept 14 days in `/opt/backups/nightly`; cloud copy + WAL still to do)_: pgBackRest or WAL-G →
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
- [ ] **D5. Retention:** _(OctoNotes `jobs` done 2026-10-07: daily cron `/etc/cron.d/octo-retention` (`deploy/octo-pg/retention.sh`) keeps finished jobs 3 days, failed 30; first run deleted 23,005 of 31,646)_ monthly partitions for `study_events`, notifications,
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

- [x] Push notification when a build finishes; "Building x%" on the home row _(2026-10-07: push in R6 (FCM key on the server); the studio row shows "Building 40%" and refreshes every 5 s while a build runs)_
- [x] Server AI grading for spoken Lightning recall answers _(2026-10-07: `POST /studios/{id}/grade` on the cheap model, asked only when the app's word check misses; paid as `grade`)_
- [x] Cap Quiz me at ~10 questions _(2026-10-07: 10 a round, weakest topics first, one per topic in turn)_
- [x] Study plan reminders (notifications) _(R6)_
- [x] One name per concept across a studio _(2026-10-07: same idea = same name (case, article, plural ignored) after every build and for each new concept map)_(merge near-duplicates)
- [x] **Rebuild keeps too few ids** _(fixed in Rust R5, 2026-10-07)_ — ids carried over
  only on an exact title (two builds of the same files: 3/8 lessons, 8/50
  cards kept). Now the outline is shown the old titles ("reuse where it
  still fits"), lessons are matched one-to-one by word overlap, and each
  matched lesson is shown its old card fronts ("keep the ones still right,
  word for word"); cards matched by word overlap. Measured after the first
  two parts: **8/8 and 7/7 lessons kept**, cards still 14/53 — the card-front
  part is unit-tested but not yet run against the model (OpenRouter credit
  ran out mid-test, 402). Re-run `build_e2e.sh` after the top-up.
- [~] Burmese font in the PDF export **Dropped: US launch**
- [ ] Desktop pages still on the old design (several show mock data:
  Analytics, Ask AI, Manage, Welcome back, Study plan)

## State

- All work is in local commits in this repo (not pushed).
- Backend changes are deployed to `cockpit-api`; backups under
  `/opt/cockpit/backup-*` on the server.

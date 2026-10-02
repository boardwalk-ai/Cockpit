# GhostWriter backend contract

Status: **in progress** — phases 1a to 1d (the whole backend for phases 2 and 3) are built (see section 10).

This is the agreement between the GhostWriter mobile app and its new Rust
backend: what is stored, which endpoints exist, and which events the app
receives. It replaces the Go + Python backend from Cockpit PR #18.

## 1. Decisions already made

| Topic | Decision |
|---|---|
| Language | Rust (axum + sqlx + tokio), same stack as the other Octopilot Rust services |
| Where the code lives | The Cockpit monorepo: the service in `backend-rs/crates/ghostwriter-api`, the Flutter module in `packages/ghostwriter`. |
| Database | Postgres only, in its own database (`ghostwriter`). No Scylla for now. |
| Relation to Doc Oct | None at the data level. GhostWriter projects are not Doc Oct documents. Only the editor **code** is shared. |
| Saving | Same mechanism as Doc Oct: the client picks the id up front, saves are idempotent upserts, autosave. |
| Who writes the document | The agent, on the server. The document lives on the server. |
| Editing while the agent writes | Not allowed. The document is locked; the editor is read-only. |
| What the chat shows while writing | A word-count progress bar (`320 / 800 words`), not the essay text. |
| Live text | Letter by letter, but only to a client that has the editor open. |
| Revisions | The agent re-reads the whole essay and rewrites what was asked. A version is saved before every agent edit so it can be undone. |
| Formatting | Semantic fields + body are stored; the Doc Oct formatters lay them out. |
| Notifications | Push when a question is waiting; Live Activities / ongoing notification for progress. Last phase. |

## 2. Layout

```
backend-rs/
  crates/
    octo-common/             auth, credits, identity, OpenRouter client (shared)
    ghostwriter-api/         this service
      src/                   main.rs  lib.rs  config.rs  ctx.rs  routes/
      migrations/            sqlx migrations for the `ghostwriter` database
      tests/                 integration tests against a real Postgres
packages/
  ghostwriter/               the Flutter module (phone UI)
  doc_oct/                   the editor the module reuses
```

Two connection pools, the same split OctoNotes uses:

- **`ghostwriter` database** — everything in section 3.
- **shared `octopilot` database** — read `users`, `api_keys`,
  `system_settings`; charge OctoCredits. GhostWriter never creates tables there.

## 3. Database (`ghostwriter`)

```sql
-- A project is one essay: its brief, its document, its runs.
CREATE TABLE projects (
  id            uuid PRIMARY KEY,          -- chosen by the client
  user_id       uuid NOT NULL,             -- users.id in the octopilot DB
  folder_id     uuid REFERENCES folders(id) ON DELETE SET NULL,
  title         text NOT NULL DEFAULT 'Untitled essay',
  instruction   text NOT NULL DEFAULT '',  -- the brief the user typed
  status        text NOT NULL DEFAULT 'idle',  -- idle | writing | ready
  target_words  int,
  word_count    int  NOT NULL DEFAULT 0,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX projects_user_updated ON projects (user_id, updated_at DESC);

CREATE TABLE folders (
  id         uuid PRIMARY KEY,
  user_id    uuid NOT NULL,
  name       text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- The one live document per project. `rev` goes up by one on every change.
CREATE TABLE documents (
  project_id     uuid PRIMARY KEY REFERENCES projects(id) ON DELETE CASCADE,
  rev            bigint NOT NULL DEFAULT 0,
  style          text   NOT NULL DEFAULT 'apa',   -- apa | mla | chicago | harvard | ieee | none
  title          text   NOT NULL DEFAULT '',
  fields         jsonb  NOT NULL DEFAULT '{}',    -- studentName, institutionName, courseName, instructorName, date
  body           text   NOT NULL DEFAULT '',      -- plain text, paragraphs separated by a blank line
  delta          jsonb,                           -- rich body (Quill delta) once the user has edited
  bibliography   text   NOT NULL DEFAULT '',
  sources        jsonb  NOT NULL DEFAULT '[]',
  locked_by_run  uuid,                            -- set while the agent is writing
  updated_at     timestamptz NOT NULL DEFAULT now()
);

-- Snapshot taken before the agent changes the document, and on user saves.
CREATE TABLE document_versions (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id  uuid NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  rev         bigint NOT NULL,
  reason      text   NOT NULL,   -- agent_write | agent_revise | humanize | user_save | restore
  snapshot    jsonb  NOT NULL,   -- the whole document row at that rev
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX document_versions_project ON document_versions (project_id, rev DESC);

-- One agent run. Everything needed to resume after a restart is here.
CREATE TABLE runs (
  id                uuid PRIMARY KEY,
  project_id        uuid NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  user_id           uuid NOT NULL,
  status            text NOT NULL,   -- running | waiting_for_user | finished | error | cancelled
  context           jsonb NOT NULL DEFAULT '{}',   -- plan, outlines, sources, settings
  messages          jsonb NOT NULL DEFAULT '[]',   -- the orchestrator's chat history
  pending_question  jsonb,
  last_seq          bigint NOT NULL DEFAULT 0,
  error             text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX runs_one_active_per_project
  ON runs (project_id) WHERE status IN ('running', 'waiting_for_user');

-- Durable event log. The app replays it to rebuild the timeline.
CREATE TABLE run_events (
  run_id      uuid   NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
  seq         bigint NOT NULL,
  type        text   NOT NULL,
  payload     jsonb  NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (run_id, seq)
);
```

`run_events` is kept as its own table with a simple `(run_id, seq)` key so it
can move to another store later without touching anything else.

## 4. Auth

Every request carries `Authorization: Bearer <Firebase ID token>` (project
`octopilot-ai-7b29e`). The token's UID is mapped to `users.id`. With no Firebase
project configured (local dev) the `X-User-Id` header is trusted instead.

Every project, run and document is checked against the caller's `user_id`.

## 5. Endpoints

All under `/v1`. JSON in, JSON out, camelCase.

### Account

| Method | Path | Purpose |
|---|---|---|
| GET | `/me` | `{ id, name, email, photoUrl, octoCredits }` |

### Projects and folders

| Method | Path | Purpose |
|---|---|---|
| GET | `/projects` | The user's projects, newest first, plus folders |
| PUT | `/projects/:id` | Create or update (idempotent): `{ title?, folderId?, instruction? }` |
| GET | `/projects/:id` | One project, with `activeRunId` if a run is in progress and `lastRunId` (the newest run, to replay its timeline) |
| DELETE | `/projects/:id` | Delete a project and everything under it |
| PUT | `/folders/:id` | Create or rename: `{ name }` |
| DELETE | `/folders/:id` | Delete a folder (projects are kept, unfiled) |

### Runs

| Method | Path | Purpose |
|---|---|---|
| POST | `/projects/:id/runs` | Start a run: `{ runId, instruction }` → `{ runId }`. Same `runId` twice is a no-op. 409 if a run is already active. |
| GET | `/runs/:runId/events?sinceSeq=N` | Server-Sent Events (section 6). Replays stored events after `N`, then stays live. |
| POST | `/runs/:runId/answer` | `{ field, value }` — answers the pending question. 409 if that question is not pending. |
| POST | `/runs/:runId/message` | `{ text }` — a free chat message to the agent |
| GET | `/runs/:runId` | `{ status, pendingQuestion, lastSeq, error }` — where the run stands, for an app coming back to it |
| POST | `/runs/:runId/cancel` | Stop the run and release the document lock. Harmless if it already ended. |

A run keeps going when the app disconnects. The app reconnects with the last
`seq` it saw and misses nothing.

A server restart is different: the run's driver dies with the process. At
startup the service closes any run that was still active with a `fatal` event
("The server restarted while this run was in progress.") and unlocks its
document, so the app is told and the project is not stuck. Resuming a run across
a restart is not built.

Runs are driven by the agent loop (section 6.2). `GHOSTWRITER_DRIVER=scripted`
switches to a scripted driver instead: the same steps and questions with canned
content and no model calls, for building and demoing the app without spending
credits. It writes a placeholder essay into the document the way the agent does
(locked, streamed to an open editor, saved as it goes), so the editor can be
built against it too.

### Document

| Method | Path | Purpose |
|---|---|---|
| GET | `/projects/:id/document` | `{ rev, style, title, fields, body, delta, bibliography, sources, locked, wordCount, updatedAt }` |
| PUT | `/projects/:id/document` | Save from the editor (7.2) → `{ rev, wordCount }` |
| GET | `/projects/:id/document/stream` | SSE for an open editor (7.1) |
| GET | `/projects/:id/versions` | `{ versions: [{ id, rev, reason, createdAt, title, preview, wordCount }] }`, newest first, at most 100 |
| POST | `/projects/:id/versions/:versionId/restore` | Put that version back → the document, as `GET` returns it. **409** `document_locked` while a run writes. |

## 6. Run events

Each SSE frame carries `id: <seq>` and `data: <json>`. `seq` starts at 1 and
never repeats within a run. A keep-alive comment is sent every 15 seconds.

Stored and replayed:

| Type | Payload | Shown as |
|---|---|---|
| `user_message` | `text` | User bubble |
| `assistant_message` | `text` | GhostWriter bubble |
| `step_start` | `stepId, tool, title` | A step card, running |
| `step_progress` | `stepId, detail` | Detail line on that card |
| `step_done` | `stepId, summary?` | Card turns to done |
| `step_error` | `stepId, error, retryable` | Card turns to failed |
| `thought` | `stepId?, text` | The agent's short reasoning, attached to the step |
| `question` | see 6.1 | A question card |
| `question_answered` | `field, value` | Question card collapses to the answer |
| `context_update` | a patch: `essayTopic`, `essayType`, `thesis`, `outlines` | What the run has worked out so far |
| `awaiting_reply` | — | GhostWriter asked something in plain text and is waiting on the chat box |
| `sources_ready` | `count`, `sources[]` (`url, title, author, publishedYear, publisher`) | **Sources pill appears** |
| `writing_started` | `targetWords` | **Open Editor pill appears**; progress bar starts |
| `write_progress` | `words, targetWords` | Progress bar. At most one per second. `words` may exceed `targetWords`. |
| `document_updated` | `rev, wordCount` | Editor refetches if it is open and not streaming |
| `credits` | `charged, balance, reason` | OctoCredits pill counts down |
| `done` | — | Run finished; document unlocked |
| `cancelled` | — | Run stopped by the user; document unlocked |
| `fatal` | `error` | Run failed; document unlocked |

Sent live but **not** stored: `assistant_delta { chunk }`, so GhostWriter's
replies type out. On replay the app gets the finished `assistant_message` only.

### 6.1 Questions

```json
{
  "type": "question",
  "field": "citationStyle",
  "question": "Which citation format?",
  "inputType": "select",
  "options": [{ "label": "APA", "value": "APA" }],
  "allowCustom": false,
  "sources": []
}
```

| `inputType` | Control | Answer value |
|---|---|---|
| `text` | Text field | string |
| `number` | Number field + chips | number |
| `select` | Chips, one choice | string |
| `multiselect` | Checkboxes + "Suggest more" + custom | array of strings, or `"__suggest_more__"` |
| `sourceReview` | Source review sheet | array of `{ url, focusNote?, rejected? }` |

Fields, in the order the agent asks them:

| Field | Type | Notes |
|---|---|---|
| `essayFocus` | multiselect | Options come from the plan |
| `sourceReviewChoice` | select | `Review Sources` / `One Shot` (phase 4) |
| `sourceReview` | sourceReview | Only after `Review Sources` (phase 4) |
| `wordCount` | number | Chips 500 / 800 / 1200 / 2000 / 3000 |
| `citationStyle` | select | APA / MLA / Chicago / Harvard / IEEE / None |
| `studentName`, `instructorName`, `institutionName`, `courseInfo`, `essayDate` | text | Only the ones the chosen style needs |
| `humanizerChoice` | select | StealthGPT / UndetectableAI / Skip (phase 4) |
| `paragraphSplitChoice` | select | After StealthGPT only (phase 4) |

A chat message sent while `essayFocus` is pending is treated as a direction for
new focus options, as on the web: the app answers the question with
`"__chat_refinement__:<text>"`.

### 6.2 The agent loop

The orchestrator model is given the tools below and the workflow in
`agent/prompt.rs`, and decides each next step itself. It is a port of
OctopilotWeb's loop.

| Tool | Does | Model |
|---|---|---|
| `plan_essay` | Topic, type, thesis, focus options; names the project | orchestrator |
| `ask_user` | A question (6.1); the run waits | — |
| `generate_outlines` | Introduction, body paragraphs, conclusion | orchestrator |
| `search_sources` | Candidate sources; PDFs and duplicates dropped | source search |
| `scrape_sources` | Fetches each source's text; charges for research | — |
| `compact_sources` | A citable brief per source; emits `sources_ready` | secondary |
| `write_essay` | Streams the essay into the document (section 7); charges for generation | writer |
| `finalize_document` | Puts the title-page answers on the document; the run then ends | — |

A tool that fails is shown as a failed step and its error goes back to the
model, which retries or tells the user. A run stops after 40 model round-trips.
Not ported yet: evaluating sources, source review, critique and revision, the
humanizer (phase 4).

## 7. The document and the lock

1. When `write_essay` starts, the run takes the lock (`locked_by_run`), saves a
   version, and emits `writing_started`.
2. The writer streams from the model. The server keeps the text in memory,
   counts words, and emits `write_progress` once a second.
3. The text is saved to `documents` every 2 seconds, bumping `rev` and
   emitting `document_updated`.
4. When writing ends the lock is released. From then on the editor can save.
5. A revision takes the lock again, saves a version, rewrites, and releases.

The writer returns plain prose: the essay, a `===BIBLIOGRAPHY===` line, then the
bibliography. Only the text before the marker is the body, so the stream is
clean prose.

The lock is enforced on the server: a `PUT /document` or a restore during a
write gets 409.

A restore keeps the document it replaces as a `restore` version first, so a
restore can itself be undone.

### 7.1 The editor's stream

`GET /projects/:id/document/stream` stays open for as long as the editor is.
Each frame is `data: <json>` with a `type`:

| Event | Payload | What the editor does |
|---|---|---|
| `snapshot` | the document as `GET` returns it | Replace everything it shows. Sent first, when a write begins (`locked: true`, empty body), and after any other change. |
| `delta` | `text` | Append to the body. Batched about every 50 ms. |
| `committed` | `rev` | The text so far is saved |
| `unlocked` | `rev` | Follows the final `snapshot` of a write: the editor may become editable |

While a write is in progress the snapshot carries the text streamed so far,
which is ahead of the database, so an editor opened mid-write starts from there
and misses nothing. If an editor falls too far behind, it is sent a fresh
`snapshot` and carries on.

An editor's own save comes back to it as a `snapshot` with the `rev` the save
returned. An unlocked snapshot with a `rev` the editor already has can be
ignored; this keeps typing done since the save from being overwritten.

Deleting the project ends the stream. Text is only pushed to clients connected
to this stream, so a chat-only client costs nothing extra.

### 7.2 Saving from the editor

`PUT /projects/:id/document` with `{ baseRev, style?, title?, fields?, body?, delta?, bibliography? }`:

- `baseRev` is the `rev` the editor's copy was loaded at. Fields left out are
  kept. `delta` is the Quill delta for `body`; a `body` sent without one clears
  the stored delta, since it would no longer match.
- **409 `document_locked`** while a run writes; **409 `stale_rev`** if the
  document changed since `baseRev`. Both carry `details.rev`, the current `rev`.
- Sending what is already saved changes nothing and succeeds, so a save whose
  reply was lost can simply be retried.
- A save first keeps the document as it was as a `user_save` version, unless
  the newest version is a `user_save` less than 10 minutes old. So the agent's
  text is always kept before the first edit, and autosave adds at most one
  version every 10 minutes.

## 8. Credits

OctoCredits are charged through the shared ledger (`octo-common::credits`),
idempotent on `ghostwriter:<action>:<runId>[:n]`.

The pricing is the Finance-approved table in `pricing.py` on octopilot-api
(read 2026-10-02): 100 OC = $1; 30,000 generated words = $1; 3,000 humanized
words = $1; 50 sources = $1. Each operation is charged on its own, rounded up to
the next 100 OC, with a minimum of 100 OC.

| Action | When | Amount |
|---|---|---|
| Source search | After `search_sources` succeeds | `ceil100(sources / 50 * 100)`, min 100 |
| Essay generation | After `write_essay` succeeds | `ceil100(words / 30000 * 100)`, min 100 |
| Humanize | After `humanize_essay` succeeds | `ceil100(words / 3000 * 100)`, min 100 |

The balance is pre-checked before each paid step. If it is too low the step
fails with a clear message and the run waits for the user rather than dying.

## 9. Deployment and open points

Deployment follows octonotes-api on the VPS: a release binary under
`/opt/ghostwriter-api`, a systemd unit running as its own user, its own
Postgres container, nginx in front. Port **8791** is free.

Models and keys come from the shared DB: `api_keys` (OpenRouter) and
`system_settings` (`ghostwriter_orchestrator_model`, `ghostwriter_write_model`,
`secondary_model`, `source_search_model`).

Open:

1. **Firebase on mobile.** The app needs its own Android and iOS apps registered
   in the Firebase project to get `google-services.json` and
   `GoogleService-Info.plist`.
2. **Public URL.** Which domain and path nginx serves this API on.
3. **Buying OctoCredits in the app.** Stores do not allow Stripe for digital
   goods; either in-app purchase or no purchase button.

## 10. Build order

| Phase | Scope |
|---|---|
| 1a ✅ | Service skeleton, migrations, auth, `/me`, projects and folders |
| 1b ✅ | Runs: start, durable events, SSE with replay, answer, message, cancel |
| 1c ✅ | Agent loop + core tools: plan, focus question, outlines, search, scrape, compact, word count and citation questions, write, formatting questions. Also the document lock, version snapshots, progress events and credits. |
| 1d ✅ | Document: saving from the editor, the live text stream, version list and restore. The scripted driver writes a placeholder essay. |
| 2 | Mobile chat: timeline, question cards, progress bar, pills |
| 3 | Editor: shared core from `doc_oct`, mobile editor, read-only live text |
| 4 | Revision mode, source review, humanizer |
| 5 | Push notifications, Live Activities, Android ongoing notification |

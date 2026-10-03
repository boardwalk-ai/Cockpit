# GhostWriter backend contract

Status: **in progress** — phases 1a to 1d, revisions (4a) and source review (4b) are built (see section 10).

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
  status            text NOT NULL,   -- queued | running | waiting_for_user | finished | error | cancelled
  context           jsonb NOT NULL DEFAULT '{}',   -- plan, outlines, sources, settings
  messages          jsonb NOT NULL DEFAULT '[]',   -- the orchestrator's chat history
  pending_question  jsonb,
  last_seq          bigint NOT NULL DEFAULT 0,
  error             text,
  worker            text,            -- the worker driving it
  lease_until       timestamptz,     -- NULL = no worker holds it (queued or parked)
  pending_call      text,            -- the model's tool call the pending question answers
  resume            jsonb,           -- { field, value }: the answer that woke a parked run
  inbox             jsonb NOT NULL DEFAULT '[]',  -- chat messages no worker has taken yet
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX runs_one_active_per_project
  ON runs (project_id) WHERE status IN ('queued', 'running', 'waiting_for_user');

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
| PUT | `/devices/:id` | Register this install for push, or refresh its token. `{ token, platform }` (`android`, `ios`, `web`). `id` is made once by the app. 204. |
| DELETE | `/devices/:id` | Stop pushing to this install (sign-out). 204. |
| GET | `/ai/catalog` | `{ pro, models: [{ id, name, tagline, pro, locked, default }], personalities: [{ id, name, description, default }] }`. Never the real models. |
| GET | `/ai/preferences` | `{ scopes: { global, ghostwriter, study_studio }, effective: { ghostwriter, study_studio } }`; each `{ model, personality }` or `null` |
| PUT | `/ai/preferences/:scope` | `{ model?, personality? }`: an id, `null` (follow the wider scope) or absent (leave it). 403 `pro_required` for a Pro model off Pro |
| POST | `/octo/ask` | Ask Octo. `{ question }` (max 500 characters) → `{ answer }`. Answers questions about using the app only; not saved, not charged. 503 when no model is available. |

### Projects and folders

| Method | Path | Purpose |
|---|---|---|
| GET | `/projects` | The user's projects, newest first, plus folders |
| PUT | `/projects/:id` | Create or update (idempotent): `{ title?, folderId?, instruction? }` |
| GET | `/projects/:id` | One project, with `activeRunId` if a run is in progress, `lastRunId`, and `runIds` (every run, oldest first, to replay the whole conversation) |
| DELETE | `/projects/:id` | Delete a project and everything under it |
| PUT | `/folders/:id` | Create or rename: `{ name }` |
| DELETE | `/folders/:id` | Delete a folder (projects are kept, unfiled) |

### Runs

| Method | Path | Purpose |
|---|---|---|
| POST | `/projects/:id/runs` | Start a run: `{ runId, instruction }` → `{ runId }`. Same `runId` twice is a no-op. 409 if a run is already active. |
| GET | `/runs/:runId/events?sinceSeq=N` | Server-Sent Events (section 6). Replays stored events after `N`, then stays live. |
| POST | `/runs/:runId/answer` | `{ field, value }` — answers the pending question. 409 if that question is not pending. |
| POST | `/runs/:runId/message` | `{ text }` — a chat message to the run while it goes. Answered at once (6.8), then handed to the agent |
| GET | `/runs/:runId` | `{ status, pendingQuestion, lastSeq, error }` — where the run stands, for an app coming back to it |
| POST | `/runs/:runId/cancel` | Stop the run and release the document lock. Harmless if it already ended. |

A run keeps going when the app disconnects. The app reconnects with the last
`seq` it saw and misses nothing.

**Runs are jobs.** A started run is `queued`. A worker (inside the API process)
claims it with `FOR UPDATE SKIP LOCKED`, drives it, and renews a lease on it
(`RUN_LEASE_MS`, default 30 s) while it does. The run's context and the model's
conversation are saved after every tool call.

- **Parked.** A run that has waited `PARK_AFTER_MS` (default 0: at once) on a question
  or a chat reply is let go: still `waiting_for_user`, but no worker holds it and
  it uses no memory. It never times out. Answering it (or, when it waits on a
  plain question, sending a message) queues it with the answer, and a worker
  resumes it from the step it stopped at. Nothing is redone or charged twice.
- **Restarts and crashes.** A worker that dies stops renewing its leases. Once a
  lease has run out, a `running` run goes back to `queued` and is resumed; a
  waiting one is parked. A tool that was cut off is closed with `step_error`
  ("Interrupted. Picking up from here."), the model is told it was interrupted,
  and it calls the tool again.
- **Following a run that no worker here holds** (queued, parked): the event
  stream stays open and reads the log until a worker picks the run up.
- Chat messages sent while no worker holds the run are kept in `inbox` and given
  to the model when it resumes.
- `WORKER_SLOTS` (default 32) caps the runs one worker drives at once. A run
  waiting on its user gives its place back and takes one again when answered,
  so waiting runs never hold anyone else up.
- Nothing is logged after a run's terminal event.
- One user may run any number of essays at once; each project has at most one
  active run. Projects carry `needsAnswer` (a run on it waits for the user).

Today the worker runs inside the API process. Running workers as separate
processes needs one more piece: answers and messages reach a live run through
memory, so they would have to go through the database (LISTEN/NOTIFY) instead.

**Revisions.** A run started on a project whose document already has an essay
is a revision (6.3): the user asks for a change, or asks about the essay. It
ends once the agent has answered; the next request is another run. The app
shows a project's runs one after another as one conversation.

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
| `assistant_message` | `text`, `aside?` | GhostWriter bubble. `aside: true` = the quick reply to a mid-run message (its own bubble) |
| `step_start` | `stepId, tool, title` | A step card, running |
| `step_progress` | `stepId, detail` | Detail line on that card |
| `step_done` | `stepId, summary?` | Card turns to done |
| `step_error` | `stepId, error, retryable` | Card turns to failed |
| `thought` | `stepId?, text` | The agent's short reasoning, attached to the step |
| `question` | see 6.1 | A question card |
| `question_answered` | `field, value, skipped?` | Question card collapses to the answer. `skipped: true` = the user wrote a message instead; the question is asked again |
| `context_update` | a patch: `essayTopic`, `essayType`, `thesis`, `outlines`, `critiqueIssues` | What the run has worked out so far |
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
| `sourceReview` | The sources, each with a keep/leave-out toggle and an optional focus note | array of `{ url, focusNote?, rejected? }`, one entry per source |

Fields, in the order the agent asks them:

| Field | Type | Notes |
|---|---|---|
| `essayFocus` | multiselect | Options come from the plan |
| `sourceReviewChoice` | select | `Review Sources` / `One Shot` |
| `sourceReview` | sourceReview | Only after `Review Sources`. The question carries `sources[]` (the ones that were read). A source marked `rejected` is not summarised or cited; a `focusNote` steers that source's summary. |
| `wordCount` | number | Chips 500 / 800 / 1200 / 2000 / 3000 |
| `citationStyle` | select | APA / MLA / Chicago / Harvard / IEEE / None |
| `studentName`, `instructorName`, `institutionName`, `courseInfo`, `essayDate` | text | Only the ones the chosen style needs |
| `humanizerChoice` | select | StealthGPT / UndetectableAI / Skip. Asked after the essay is delivered. |
| `critiqueChoice` | select | `Fix them` / `Leave it`, or a typed answer. Revision runs, after a review found issues. |
| `paragraphSplitChoice` | select | `AI split` / `Skip split`. Only when the humanizer merged the paragraphs. |

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
| `revise_essay` | Revision runs only (6.3) | writer |
| `evaluate_sources` | Judges whether the summarised sources can carry the essay. First run only, after `compact_sources` | secondary |
| `critique_essay` | Reviews the essay in the document and lists its weaknesses by paragraph. Revision runs only. Changes nothing, costs nothing | orchestrator |
| `humanize_essay` | Sends the essay as it stands through StealthGPT or UndetectableAI and puts the result in the document; charges for humanizing | — |
| `split_paragraphs` | Restores paragraph breaks a humanizer merged. A split that changes any wording is thrown away. | secondary |

A tool that fails is shown as a failed step and its error goes back to the
model, which retries or tells the user. A run stops after 40 model round-trips.
Not ported: the web's automatic removal of junk pages after scraping.

### 6.9 AI settings (models, personalities, prices)

The catalog lives in the shared octopilot DB (`backend-rs/shared-sql/`), written
by admins directly: `ai_models` (a name such as "Octo v2 Pro" for a bundle of an
orchestrator, a writer and a fast model; `min_plan`; `credit_multiplier`),
`ai_personalities` (a chat voice), `user_ai_preferences` (per user, per scope:
`global` or an app) and `pricing_config` (one row, every change logged by a
trigger in `pricing_audit`). Services read them through octo-common `ai` with a
one-minute cache.

- A user's choice for an app wins over their global one, which wins over the
  admin default. A Pro model off Pro, or a turned-off one, falls back the same way.
- A run fixes the model and voice when it starts (`context.ai`) and keeps them
  through parking and restarts.
- The voice goes into the chat-facing prompts only (orchestrators, quick
  reply, Ask Octo), never the writer's.
- The AI calls itself by the model's name. Model and company names are masked
  in chat replies, quick replies, Ask Octo, step errors and failures
  (`system_settings.ai_masked_terms` overrides the list); model errors never
  carry the provider's message.
- Charges use `pricing_config` times the model's `credit_multiplier`.
- With no catalog, runs use the old `system_settings` models and default prices.

### 6.8 Messages while a run goes

A message the user sends while a run is going is answered at once by the fast
model, without stopping the run (`assistant_message` with `aside: true`; no
credits; at most 10 a minute per run). The model also reads it as one of:

- **instruction** ("keep it formal"): kept in `runs.directives`; every later
  outline, writer and reviser brief on the project carries all of them. If the
  essay is being written, the writer stops, the document goes back to what it
  was, nothing is charged, and the agent writes again with the instruction.
- **stop**: the run is cancelled.
- **question / chat**: answered, nothing else.

Then the agent hears it, marked as already answered, so it does not answer it
again. If the run was waiting on a question and the message is an instruction,
the question is set aside (`question_answered` with `skipped: true`) and asked
again in its light; a question or chat leaves the card alone (the agent hears
it once the card is answered). A reply to a
question the agent asked in plain text is just the reply (no quick answer).
Without a model available the message goes to the agent as it is.

### 6.7 Push notifications

A run notifies the project owner's devices through Firebase Cloud Messaging when
**no client is connected to its event stream** at that moment:

| When | `data.type` | Body |
|---|---|---|
| `question` is emitted | `question` | the question |
| the run ends `done` | `done` | "GhostWriter has finished. Tap to open." |
| the run ends `fatal` | `fatal` | "GhostWriter stopped. <reason>" |

The title is the project's title; `data` also has `projectId` and `runId`. A
cancelled run sends nothing. A token FCM reports as unregistered is deleted.
The app closes its event stream when it goes to the background, which is what
makes the server notify. With `FCM_SERVICE_ACCOUNT_FILE` unset nothing is sent.

### 6.5 Evaluating the sources

`evaluate_sources` returns `{ sufficient, quality, gaps, recommendation, searchAgain }`.
`searchAgain` is true only on the run's first evaluation and only when the sources
are not sufficient: the agent then searches with `recommendation` as the
refinement, scrapes and compacts once more, and writes. An evaluator that fails
or answers nonsense never stops the run: three or more sources count as enough.

### 6.6 Reviewing the essay

In a revision run, "review my essay" or "make it better" calls `critique_essay`.
It emits `context_update { critiqueIssues: [{ paragraph, type, description, major }] }`
(`paragraph` from 1; `type` is thesis, evidence, clarity, citations, length or
structure) and gives the model the same list. The agent tells the user the main
issues, asks `critiqueChoice`, and only on a yes calls `revise_essay`, which is
what costs credits.

### 6.4 Humanizing

After `finalize_document` the agent asks `humanizerChoice`. On StealthGPT or
UndetectableAI it calls `humanize_essay`, which:

1. reads the essay body from the document (the bibliography is left alone);
2. pre-checks the balance, locks the document and keeps a version (`humanize`);
3. sends the text to the provider, saves the result, unlocks, emits
   `document_updated`, and charges "Humanizing".

Its result tells the model whether the paragraphs came back merged
(`paragraphsMerged`). If so the agent asks `paragraphSplitChoice` and, on
`AI split`, calls `split_paragraphs`. The split is not charged.

A revision run has both tools too, so "humanize it" works on a finished essay,
including the user's own edits. A provider that fails, or has no key in
`system_settings` (`stealthgpt_api_key`, `undetectable_api_key`), is a failed
step with a plain message; the essay and the balance are untouched.

### 6.3 Revisions

A revision run gets its own instructions (`agent/prompt.rs`, `revision_orchestrator`)
and two tools: `revise_essay(instructions)` and `ask_user`. Its first message
is the user's request and the essay as it stands, paragraphs numbered from 1.

- A change: `revise_essay` reads the document as it is now (with the user's own
  edits), takes the lock, keeps an `agent_revise` version, and streams the whole
  revised essay into the document exactly like `write_essay` (`writing_started`
  with the current word count as the target, `write_progress`,
  `document_updated`). Title, style and title-page fields are left alone. It is
  charged as essay generation for the words written ("Essay revision").
- A question about the essay: the agent answers in the chat and the run ends
  without touching the document.
- The scripted driver revises too: it appends a "Revision note" quoting the
  request, so the app's revision flow can be built without a model.

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
| 2 ✅ | Mobile chat: timeline, question cards, progress bar, pills, Google sign-in (desktop page: later) |
| 3 ✅ | Editor: mobile editor on Doc Oct's foundation, read-only live text, autosave, history |
| 4 | Revision mode ✅, source review ✅, humanizer ✅, evaluating sources ✅, critique ✅, Ask Octo ✅ |
| 5 | Push notifications, Live Activities, Android ongoing notification |

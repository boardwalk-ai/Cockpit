-- GhostWriter core schema. `user_id` everywhere is `users.id` in the shared
-- octopilot database; there is no foreign key because it is a different
-- database.

CREATE TABLE folders (
    id          uuid PRIMARY KEY,               -- chosen by the client
    user_id     uuid NOT NULL,
    name        text NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX folders_user ON folders (user_id, created_at);

-- A project is one essay: its brief, its document, its runs.
CREATE TABLE projects (
    id            uuid PRIMARY KEY,             -- chosen by the client
    user_id       uuid NOT NULL,
    folder_id     uuid REFERENCES folders (id) ON DELETE SET NULL,
    title         text NOT NULL DEFAULT 'Untitled essay',
    instruction   text NOT NULL DEFAULT '',     -- the brief the user typed
    status        text NOT NULL DEFAULT 'idle'
                  CHECK (status IN ('idle', 'writing', 'ready')),
    target_words  integer,
    word_count    integer NOT NULL DEFAULT 0,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX projects_user_updated ON projects (user_id, updated_at DESC);

-- The one live document per project. `rev` goes up by one on every change.
CREATE TABLE documents (
    project_id     uuid PRIMARY KEY REFERENCES projects (id) ON DELETE CASCADE,
    rev            bigint NOT NULL DEFAULT 0,
    style          text NOT NULL DEFAULT 'apa'
                   CHECK (style IN ('apa', 'mla', 'chicago', 'harvard', 'ieee', 'none')),
    title          text NOT NULL DEFAULT '',
    fields         jsonb NOT NULL DEFAULT '{}',
    body           text NOT NULL DEFAULT '',
    delta          jsonb,
    bibliography   text NOT NULL DEFAULT '',
    sources        jsonb NOT NULL DEFAULT '[]',
    locked_by_run  uuid,                        -- set while the agent is writing
    updated_at     timestamptz NOT NULL DEFAULT now()
);

-- Snapshot taken before the agent changes the document, and on user saves.
CREATE TABLE document_versions (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id  uuid NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
    rev         bigint NOT NULL,
    reason      text NOT NULL
                CHECK (reason IN ('agent_write', 'agent_revise', 'humanize', 'user_save', 'restore')),
    snapshot    jsonb NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX document_versions_project ON document_versions (project_id, rev DESC);

-- One agent run. Everything needed to resume after a restart is here.
CREATE TABLE runs (
    id                uuid PRIMARY KEY,         -- chosen by the client
    project_id        uuid NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
    user_id           uuid NOT NULL,
    status            text NOT NULL
                      CHECK (status IN ('running', 'waiting_for_user', 'finished', 'error', 'cancelled')),
    context           jsonb NOT NULL DEFAULT '{}',
    messages          jsonb NOT NULL DEFAULT '[]',
    pending_question  jsonb,
    last_seq          bigint NOT NULL DEFAULT 0,
    error             text,
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now()
);
-- At most one live run per project.
CREATE UNIQUE INDEX runs_one_active_per_project
    ON runs (project_id) WHERE status IN ('running', 'waiting_for_user');

-- Durable event log. The app replays it to rebuild the timeline. Keyed simply
-- by (run_id, seq) so it can move to another store without touching the rest.
CREATE TABLE run_events (
    run_id      uuid NOT NULL REFERENCES runs (id) ON DELETE CASCADE,
    seq         bigint NOT NULL,
    type        text NOT NULL,
    payload     jsonb NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (run_id, seq)
);

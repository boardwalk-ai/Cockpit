-- Files attached to a project (src/attachments.rs). Only the text taken
-- out of the file and a card describing it are kept, never the file.
-- `role` is set once a run decides what the file is for: the essay to
-- revise, a source, or the assignment sheet.
CREATE TABLE attachments (
    id          uuid PRIMARY KEY,              -- chosen by the client
    project_id  uuid NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
    user_id     uuid NOT NULL,
    kind        text NOT NULL,                 -- pdf | docx | text | image
    pages       integer NOT NULL,
    card        jsonb NOT NULL,
    text        text NOT NULL,
    role        text,                          -- essay | source | brief
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX attachments_project ON attachments (project_id, created_at);

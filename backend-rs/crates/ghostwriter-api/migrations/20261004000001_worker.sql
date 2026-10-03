-- Runs become jobs: queued until a worker claims them, held by a lease while
-- a worker drives them, and parked (waiting, held by no one) while the user
-- takes their time. A run can be resumed from what is saved here.

ALTER TABLE runs DROP CONSTRAINT runs_status_check;
ALTER TABLE runs ADD CONSTRAINT runs_status_check
    CHECK (status IN ('queued', 'running', 'waiting_for_user', 'finished', 'error', 'cancelled'));

ALTER TABLE runs
    ADD COLUMN worker        text,            -- the worker driving it, if any
    ADD COLUMN lease_until   timestamptz,     -- NULL = no worker holds it
    ADD COLUMN pending_call  text,            -- the model's tool call the pending question answers
    ADD COLUMN resume        jsonb,           -- the answer that woke a parked run: { field, value }
    ADD COLUMN inbox         jsonb NOT NULL DEFAULT '[]';  -- chat messages no worker has taken yet

DROP INDEX runs_one_active_per_project;
CREATE UNIQUE INDEX runs_one_active_per_project
    ON runs (project_id) WHERE status IN ('queued', 'running', 'waiting_for_user');

CREATE INDEX runs_queued ON runs (updated_at) WHERE status = 'queued';
CREATE INDEX runs_leased ON runs (lease_until) WHERE lease_until IS NOT NULL;

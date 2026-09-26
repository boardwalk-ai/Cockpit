-- notes_db — platform tables shared by every OctoNotes feature.
--
-- `user_id` everywhere is the shared octopilot `users.id`. There is no
-- cross-database foreign key on purpose (separate databases); every query is
-- scoped by user_id in the API layer.

CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Durable background work, claimed with FOR UPDATE SKIP LOCKED.
CREATE TABLE jobs (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       uuid,
    kind          text NOT NULL,
    payload       jsonb NOT NULL DEFAULT '{}'::jsonb,
    status        text NOT NULL DEFAULT 'queued'
                  CHECK (status IN ('queued', 'running', 'done', 'failed', 'cancelled')),
    attempts      integer NOT NULL DEFAULT 0,
    max_attempts  integer NOT NULL DEFAULT 5,
    run_after     timestamptz NOT NULL DEFAULT now(),
    locked_by     text,
    locked_at     timestamptz,
    error         text,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_jobs_ready ON jobs (run_after) WHERE status = 'queued';
CREATE INDEX idx_jobs_user ON jobs (user_id, created_at DESC);
CREATE TRIGGER trg_jobs_updated BEFORE UPDATE ON jobs
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Stored responses for writes sent with an Idempotency-Key header
-- (finalize, generate, charges), so a retry replays instead of repeating.
CREATE TABLE idempotency_keys (
    user_id       uuid NOT NULL,
    key           text NOT NULL,
    request_hash  text NOT NULL,
    status_code   integer,
    response      jsonb,
    created_at    timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, key)
);

-- Outbox of domain events (session finished, final notes ready, conversion
-- done, dated exam hints …) for The Deck's calendar and notifications.
CREATE TABLE domain_events (
    id            bigserial PRIMARY KEY,
    user_id       uuid NOT NULL,
    kind          text NOT NULL,
    subject_id    uuid,
    payload       jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at   timestamptz NOT NULL DEFAULT now(),
    published_at  timestamptz
);
CREATE INDEX idx_domain_events_unpublished ON domain_events (id) WHERE published_at IS NULL;
CREATE INDEX idx_domain_events_user ON domain_events (user_id, occurred_at DESC);

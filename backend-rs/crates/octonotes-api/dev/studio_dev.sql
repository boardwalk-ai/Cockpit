-- LOCAL DEV / TESTS ONLY — a minimal stand-in for the Study Studio business DB
-- (owned by the Study Studio backend). Only the columns octonotes-api reads.
-- Never run this against the real Study Studio database.

CREATE TABLE IF NOT EXISTS studios (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid NOT NULL,
    title       varchar(200) NOT NULL,
    subject     varchar(120),
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS documents (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    studio_id   uuid NOT NULL REFERENCES studios (id) ON DELETE CASCADE,
    user_id     uuid NOT NULL,
    filename    varchar(500) NOT NULL,
    mime        varchar(120) NOT NULL,
    bytes       integer NOT NULL DEFAULT 0,
    object_key  varchar(1024) NOT NULL,
    status      varchar(32) NOT NULL DEFAULT 'ready',
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS generated_topics (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    studio_id   uuid NOT NULL REFERENCES studios (id) ON DELETE CASCADE,
    user_id     uuid NOT NULL,
    ordinal     integer NOT NULL DEFAULT 0,
    payload     jsonb NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS topic_progress (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id            uuid NOT NULL,
    studio_id          uuid NOT NULL REFERENCES studios (id) ON DELETE CASCADE,
    topic_id           varchar(64) NOT NULL,
    mastery            double precision NOT NULL DEFAULT 0,
    quiz_attempts      integer NOT NULL DEFAULT 0,
    quiz_correct       integer NOT NULL DEFAULT 0,
    flashcard_reviews  integer NOT NULL DEFAULT 0,
    reviews            integer NOT NULL DEFAULT 0,
    updated_at         timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS studio_builds (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    studio_id      uuid NOT NULL REFERENCES studios (id) ON DELETE CASCADE,
    user_id        uuid NOT NULL,
    status         varchar(32) NOT NULL DEFAULT 'queued',
    stage          varchar(160) NOT NULL DEFAULT '',
    lessons_total  integer NOT NULL DEFAULT 0,
    lessons_done   integer NOT NULL DEFAULT 0,
    error          text,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now()
);

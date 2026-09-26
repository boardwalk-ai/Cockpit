-- notes_db — courses, devices and sessions (Panels 1, 2, 3, 12).

CREATE TABLE courses (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid NOT NULL,
    name        text NOT NULL,
    code        text,
    color       text,
    -- Optional link to a Study Studio studio for the same course.
    studio_id   uuid,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    deleted_at  timestamptz
);
CREATE UNIQUE INDEX ux_courses_user_name ON courses (user_id, lower(name)) WHERE deleted_at IS NULL;
CREATE TRIGGER trg_courses_updated BEFORE UPDATE ON courses
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- A physical device of the user ("Hein's iPhone").
CREATE TABLE devices (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       uuid NOT NULL,
    name          text NOT NULL,
    platform      text NOT NULL
                  CHECK (platform IN ('web', 'android', 'ios', 'macos', 'windows', 'linux')),
    push_token    text,
    last_seen_at  timestamptz,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_devices_user ON devices (user_id);
CREATE TRIGGER trg_devices_updated BEFORE UPDATE ON devices
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE sessions (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         uuid NOT NULL,
    course_id       uuid REFERENCES courses (id) ON DELETE SET NULL,
    title           text NOT NULL DEFAULT 'Untitled session',
    workspace_mode  text NOT NULL DEFAULT 'typewriter'
                    CHECK (workspace_mode IN ('typewriter', 'pencil', 'both')),
    -- New Session toggles: record, liveTranscription, smartOrganization, liveSuggestions.
    config          jsonb NOT NULL DEFAULT
                    '{"record":true,"liveTranscription":true,"smartOrganization":true,"liveSuggestions":true}'::jsonb,
    status          text NOT NULL DEFAULT 'draft'
                    CHECK (status IN ('draft', 'live', 'paused', 'ended', 'reviewing', 'finalized', 'archived')),
    -- Save destination: a Study Studio studio today ("studio:<uuid>"), a Deck
    -- folder once The Deck exists.
    deck_ref        text,
    started_at      timestamptz,
    ended_at        timestamptz,
    duration_ms     bigint NOT NULL DEFAULT 0,
    layout_prefs    jsonb NOT NULL DEFAULT '{}'::jsonb,
    revision        bigint NOT NULL DEFAULT 1,
    search          tsvector GENERATED ALWAYS AS (to_tsvector('simple', coalesce(title, ''))) STORED,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    deleted_at      timestamptz
);
CREATE INDEX idx_sessions_user_updated ON sessions (user_id, updated_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_sessions_user_status ON sessions (user_id, status) WHERE deleted_at IS NULL;
CREATE INDEX idx_sessions_search ON sessions USING gin (search);
CREATE TRIGGER trg_sessions_updated BEFORE UPDATE ON sessions
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Which devices take part in a session, and in what role (Panel 12).
CREATE TABLE session_devices (
    session_id    uuid NOT NULL REFERENCES sessions (id) ON DELETE CASCADE,
    device_id     uuid NOT NULL REFERENCES devices (id) ON DELETE CASCADE,
    user_id       uuid NOT NULL,
    role          text NOT NULL DEFAULT 'editor'
                  CHECK (role IN ('recorder', 'editor', 'viewer')),
    is_recording  boolean NOT NULL DEFAULT false,
    joined_at     timestamptz NOT NULL DEFAULT now(),
    last_seen_at  timestamptz,
    PRIMARY KEY (session_id, device_id)
);
CREATE INDEX idx_session_devices_recording ON session_devices (session_id) WHERE is_recording;

-- notes_db — Phase 2: recording, audio chunks, transcript, markers, links.

CREATE TABLE recordings (
    id           uuid PRIMARY KEY,
    session_id   uuid NOT NULL REFERENCES sessions (id) ON DELETE CASCADE,
    user_id      uuid NOT NULL,
    device_id    uuid REFERENCES devices (id) ON DELETE SET NULL,
    codec        text NOT NULL DEFAULT 'opus',
    container    text NOT NULL DEFAULT 'ogg' CHECK (container IN ('ogg', 'webm', 'mp4', 'wav')),
    sample_rate  integer NOT NULL DEFAULT 48000,
    chunk_ms     integer NOT NULL DEFAULT 10000,
    state        text NOT NULL DEFAULT 'recording'
                 CHECK (state IN ('recording', 'paused', 'stopped', 'uploaded', 'assembled')),
    started_at   timestamptz NOT NULL DEFAULT now(),
    stopped_at   timestamptz,
    duration_ms  bigint NOT NULL DEFAULT 0,
    -- The joined, compressed recording (kept until the user deletes it).
    audio_key    text,
    audio_bytes  bigint,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_recordings_session ON recordings (session_id, started_at);
CREATE TRIGGER trg_recordings_updated BEFORE UPDATE ON recordings
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE audio_chunks (
    recording_id  uuid NOT NULL REFERENCES recordings (id) ON DELETE CASCADE,
    seq           integer NOT NULL CHECK (seq >= 0),
    object_key    text NOT NULL,
    bytes         integer NOT NULL,
    start_ms      bigint NOT NULL,
    duration_ms   integer NOT NULL,
    sha256        text NOT NULL,
    asr_status    text NOT NULL DEFAULT 'pending' CHECK (asr_status IN ('pending', 'done', 'failed', 'skipped')),
    received_at   timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (recording_id, seq)
);

CREATE TABLE markers (
    id          uuid PRIMARY KEY,
    session_id  uuid NOT NULL REFERENCES sessions (id) ON DELETE CASCADE,
    user_id     uuid NOT NULL,
    type        text NOT NULL CHECK (type IN ('important', 'question', 'confusing', 'examHint', 'slideChange')),
    at_ms       bigint NOT NULL CHECK (at_ms >= 0),
    device_id   uuid,
    note        text,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_markers_session ON markers (session_id, at_ms);

-- Three layers: raw_text (ASR, never overwritten) · faithful_text (post-class
-- pass) · corrected_text (student). Display = corrected ?? faithful ?? raw.
CREATE TABLE transcript_segments (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id        uuid NOT NULL REFERENCES sessions (id) ON DELETE CASCADE,
    recording_id      uuid NOT NULL REFERENCES recordings (id) ON DELETE CASCADE,
    user_id           uuid NOT NULL,
    chunk_seq         integer NOT NULL,
    ordinal           integer NOT NULL DEFAULT 0,
    start_ms          bigint NOT NULL,
    end_ms            bigint NOT NULL,
    raw_text          text NOT NULL,
    faithful_text     text,
    corrected_text    text,
    speaker           text NOT NULL DEFAULT 'unknown' CHECK (speaker IN ('professor', 'student', 'speaker1', 'unknown')),
    speaker_original  text NOT NULL DEFAULT 'unknown',
    speaker_conf      real NOT NULL DEFAULT 0,
    asr_conf          real NOT NULL DEFAULT 0,
    status            text NOT NULL DEFAULT 'stable' CHECK (status IN ('partial', 'stable')),
    language          text,
    slide_ref         jsonb,
    words             jsonb,
    revision          bigint NOT NULL DEFAULT 1,
    layer_rev         bigint NOT NULL,
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now(),
    UNIQUE (recording_id, chunk_seq, ordinal)
);
CREATE INDEX idx_segments_time ON transcript_segments (session_id, start_ms);
CREATE INDEX idx_segments_sync ON transcript_segments (session_id, layer_rev);
CREATE INDEX idx_segments_search ON transcript_segments
    USING gin (to_tsvector('simple', coalesce(corrected_text, faithful_text, raw_text)));
CREATE TRIGGER trg_segments_updated BEFORE UPDATE ON transcript_segments
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE transcript_revisions (
    id            bigserial PRIMARY KEY,
    segment_id    uuid NOT NULL REFERENCES transcript_segments (id) ON DELETE CASCADE,
    field         text NOT NULL CHECK (field IN ('text', 'speaker')),
    old_value     text,
    new_value     text,
    corrected_by  uuid NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now()
);

-- Cross-layer links: block ↔ transcript segment ↔ slide page ↔ ink page.
CREATE TABLE links (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id  uuid NOT NULL REFERENCES sessions (id) ON DELETE CASCADE,
    user_id     uuid NOT NULL,
    from_kind   text NOT NULL CHECK (from_kind IN ('block', 'segment', 'slide', 'inkPage')),
    from_id     text NOT NULL,
    to_kind     text NOT NULL CHECK (to_kind IN ('block', 'segment', 'slide', 'inkPage')),
    to_id       text NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (from_kind, from_id, to_kind, to_id)
);
CREATE INDEX idx_links_session ON links (session_id);
CREATE INDEX idx_links_to ON links (to_kind, to_id);

-- Metered usage (transcription seconds …), charged in batches.
CREATE TABLE usage_meter (
    id          bigserial PRIMARY KEY,
    session_id  uuid REFERENCES sessions (id) ON DELETE SET NULL,
    user_id     uuid NOT NULL,
    kind        text NOT NULL,
    quantity    double precision NOT NULL,
    ref         text NOT NULL,
    charged_at  timestamptz,
    created_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (kind, ref)
);
CREATE INDEX idx_usage_uncharged ON usage_meter (user_id) WHERE charged_at IS NULL;

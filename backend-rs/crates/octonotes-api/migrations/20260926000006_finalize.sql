-- notes_db — Phase 4: review, final notes, exports, Study Studio conversion.

CREATE TABLE reviews (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id   uuid NOT NULL REFERENCES sessions (id) ON DELETE CASCADE,
    user_id      uuid NOT NULL,
    status       text NOT NULL DEFAULT 'preparing' CHECK (status IN ('preparing', 'ready', 'draft', 'finalized')),
    checklist    jsonb NOT NULL DEFAULT '[]'::jsonb,
    -- Smart Notes: the AI-organized reading of the session (sections → block ids).
    smart_notes  jsonb,
    draft        jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_reviews_session ON reviews (session_id, created_at DESC);
CREATE TRIGGER trg_reviews_updated BEFORE UPDATE ON reviews
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE review_decisions (
    review_id    uuid NOT NULL REFERENCES reviews (id) ON DELETE CASCADE,
    block_key    text NOT NULL,
    decision     text NOT NULL CHECK (decision IN ('accepted', 'excluded', 'edited')),
    edited_text  text,
    updated_at   timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (review_id, block_key)
);

-- Immutable, versioned result of finalizing a session.
CREATE TABLE final_notes (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id       uuid NOT NULL REFERENCES sessions (id) ON DELETE CASCADE,
    user_id          uuid NOT NULL,
    version          integer NOT NULL,
    title            text NOT NULL,
    content          jsonb NOT NULL,
    summary_topics   jsonb,
    deck_ref         text,
    review_id        uuid REFERENCES reviews (id) ON DELETE SET NULL,
    idempotency_key  text,
    finalized_at     timestamptz NOT NULL DEFAULT now(),
    UNIQUE (session_id, version)
);
CREATE UNIQUE INDEX ux_final_notes_idem ON final_notes (user_id, idempotency_key) WHERE idempotency_key IS NOT NULL;

CREATE TABLE exports (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    final_notes_id  uuid NOT NULL REFERENCES final_notes (id) ON DELETE CASCADE,
    user_id         uuid NOT NULL,
    format          text NOT NULL CHECK (format IN ('pdf', 'md', 'docx', 'txt')),
    options         jsonb NOT NULL DEFAULT '{}'::jsonb,
    status          text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'done', 'failed')),
    object_key      text,
    error           text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_exports_updated BEFORE UPDATE ON exports
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE recommendations (
    final_notes_id    uuid PRIMARY KEY REFERENCES final_notes (id) ON DELETE CASCADE,
    user_id           uuid NOT NULL,
    status            text NOT NULL DEFAULT 'building' CHECK (status IN ('building', 'ready', 'failed')),
    topics            jsonb NOT NULL DEFAULT '[]'::jsonb,
    selection         jsonb NOT NULL DEFAULT '{"mode": "topics", "topicIds": []}'::jsonb,
    manual_block_ids  uuid[] NOT NULL DEFAULT '{}',
    updated_at        timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_recommendations_updated BEFORE UPDATE ON recommendations
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE conversions (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    final_notes_id    uuid NOT NULL REFERENCES final_notes (id) ON DELETE CASCADE,
    user_id           uuid NOT NULL,
    topic_ids         text[] NOT NULL DEFAULT '{}',
    manual_block_ids  uuid[] NOT NULL DEFAULT '{}',
    activities        jsonb NOT NULL,
    level             text NOT NULL DEFAULT 'balanced' CHECK (level IN ('foundation', 'balanced', 'challenging')),
    destination       text NOT NULL DEFAULT 'createNew' CHECK (destination IN ('createNew', 'updateExisting')),
    target_studio_id  uuid,
    strategy          text NOT NULL DEFAULT 'updateMatching' CHECK (strategy IN ('addNew', 'updateMatching', 'keepExisting')),
    status            text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'building', 'done', 'failed')),
    studio_build_id   uuid,
    error             text,
    credits_charged   integer NOT NULL DEFAULT 0,
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_conversions_final ON conversions (final_notes_id);
CREATE TRIGGER trg_conversions_updated BEFORE UPDATE ON conversions
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Reverse links: Study Studio topic → the final notes and blocks it came from.
CREATE TABLE studio_links (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         uuid NOT NULL,
    studio_id       uuid NOT NULL,
    topic_id        text,
    topic_title     text,
    final_notes_id  uuid NOT NULL REFERENCES final_notes (id) ON DELETE CASCADE,
    conversion_id   uuid REFERENCES conversions (id) ON DELETE SET NULL,
    block_ids       uuid[] NOT NULL DEFAULT '{}',
    created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_studio_links_studio ON studio_links (user_id, studio_id);

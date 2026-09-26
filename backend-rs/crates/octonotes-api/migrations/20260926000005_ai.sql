-- notes_db — Phase 3: materials, retrieval, AI runs/suggestions, research,
-- organization passes, handwriting recognition.

CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE materials (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id          uuid NOT NULL REFERENCES sessions (id) ON DELETE CASCADE,
    user_id             uuid NOT NULL,
    filename            text NOT NULL,
    type                text NOT NULL CHECK (type IN ('pdf', 'pptx', 'image', 'whiteboardPhoto', 'handout')),
    mime                text NOT NULL,
    bytes               bigint NOT NULL DEFAULT 0,
    object_key          text,
    state               text NOT NULL DEFAULT 'uploading' CHECK (state IN ('uploading', 'processing', 'done', 'fail')),
    error               text,
    page_count          integer NOT NULL DEFAULT 0,
    origin              text NOT NULL DEFAULT 'upload' CHECK (origin IN ('upload', 'studio')),
    studio_id           uuid,
    studio_document_id  uuid,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    deleted_at          timestamptz
);
CREATE INDEX idx_materials_session ON materials (session_id) WHERE deleted_at IS NULL;
CREATE TRIGGER trg_materials_updated BEFORE UPDATE ON materials
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE material_pages (
    material_id     uuid NOT NULL REFERENCES materials (id) ON DELETE CASCADE,
    number          integer NOT NULL CHECK (number >= 1),
    title           text NOT NULL DEFAULT '',
    ocr_text        text NOT NULL DEFAULT '',
    ocr_confidence  text NOT NULL DEFAULT 'low' CHECK (ocr_confidence IN ('high', 'medium', 'low')),
    render_key      text,
    active_from_ms  bigint,
    active_to_ms    bigint,
    PRIMARY KEY (material_id, number)
);

-- Retrieval index over this user's session content (BGE-m3, 1024-dim — the
-- same space as Study Studio's chunks, so both can be searched together).
CREATE TABLE note_chunks (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id    uuid NOT NULL REFERENCES sessions (id) ON DELETE CASCADE,
    user_id       uuid NOT NULL,
    source_kind   text NOT NULL CHECK (source_kind IN ('transcript', 'slide', 'block', 'research')),
    source_id     text NOT NULL,
    content       text NOT NULL,
    content_hash  text NOT NULL,
    locator       jsonb NOT NULL DEFAULT '{}'::jsonb,
    embedding     vector(1024) NOT NULL,
    embedder      text NOT NULL,
    tsv           tsvector GENERATED ALWAYS AS (to_tsvector('simple', content)) STORED,
    created_at    timestamptz NOT NULL DEFAULT now(),
    UNIQUE (session_id, source_kind, source_id)
);
CREATE INDEX idx_note_chunks_user ON note_chunks (user_id, session_id);
CREATE INDEX idx_note_chunks_embedding ON note_chunks USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);
CREATE INDEX idx_note_chunks_tsv ON note_chunks USING gin (tsv);

-- Every AI call: what was asked, with what context, what came back, what it cost.
CREATE TABLE ai_runs (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id       uuid REFERENCES sessions (id) ON DELETE CASCADE,
    user_id          uuid NOT NULL,
    kind             text NOT NULL CHECK (kind IN ('suggest', 'command', 'missing', 'research', 'organize', 'summarize', 'recognize', 'smartNotes', 'recommend')),
    command          text,
    contexts         jsonb NOT NULL DEFAULT '[]'::jsonb,
    response         jsonb,
    model            text,
    tokens_in        integer NOT NULL DEFAULT 0,
    tokens_out       integer NOT NULL DEFAULT 0,
    credits_charged  integer NOT NULL DEFAULT 0,
    status           text NOT NULL DEFAULT 'running' CHECK (status IN ('running', 'done', 'failed', 'cancelled')),
    error            text,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_ai_runs_session ON ai_runs (session_id, created_at DESC);
CREATE TRIGGER trg_ai_runs_updated BEFORE UPDATE ON ai_runs
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- AI content waiting for the student's approval — never written into a block.
CREATE TABLE ai_suggestions (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id         uuid NOT NULL REFERENCES sessions (id) ON DELETE CASCADE,
    user_id            uuid NOT NULL,
    source_block_id    uuid,
    action             text NOT NULL,
    context_label      text NOT NULL DEFAULT '',
    body               text NOT NULL,
    sources            jsonb NOT NULL DEFAULT '[]'::jsonb,
    status             text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'inserted', 'dismissed')),
    inserted_block_id  uuid,
    ai_run_id          uuid REFERENCES ai_runs (id) ON DELETE SET NULL,
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_ai_suggestions_session ON ai_suggestions (session_id, status);
CREATE TRIGGER trg_ai_suggestions_updated BEFORE UPDATE ON ai_suggestions
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE research_runs (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id     uuid NOT NULL REFERENCES sessions (id) ON DELETE CASCADE,
    user_id        uuid NOT NULL,
    question       text NOT NULL,
    scope          text NOT NULL CHECK (scope IN ('courseFirst', 'external', 'both')),
    depth          text NOT NULL CHECK (depth IN ('quick', 'standard', 'deep')),
    explanation    text,
    sources_agree  boolean,
    conflict       text,
    low_evidence   boolean NOT NULL DEFAULT false,
    saved          boolean NOT NULL DEFAULT false,
    ai_run_id      uuid REFERENCES ai_runs (id) ON DELETE SET NULL,
    created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_research_session ON research_runs (session_id, created_at DESC);

CREATE TABLE research_sources (
    id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id    uuid NOT NULL REFERENCES research_runs (id) ON DELETE CASCADE,
    ordinal   integer NOT NULL,
    kind      text NOT NULL CHECK (kind IN ('lectureTranscript', 'courseSlide', 'studentNotes', 'studyStudio', 'external')),
    title     text NOT NULL,
    excerpt   text NOT NULL,
    locator   text NOT NULL DEFAULT '',
    url       text,
    ref       jsonb,
    trust     text NOT NULL DEFAULT 'course' CHECK (trust IN ('course', 'high', 'medium', 'low'))
);

-- One reversible Smart Organization pass (Panel 11).
CREATE TABLE org_passes (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id       uuid NOT NULL REFERENCES sessions (id) ON DELETE CASCADE,
    user_id          uuid NOT NULL,
    scope            text NOT NULL CHECK (scope IN ('selectedBlocks', 'currentSection', 'entireNote')),
    proposals        jsonb NOT NULL,
    applied_ids      text[] NOT NULL DEFAULT '{}',
    before_snapshot  jsonb,
    status           text NOT NULL DEFAULT 'preview' CHECK (status IN ('preview', 'applied', 'undone', 'dismissed')),
    ai_run_id        uuid REFERENCES ai_runs (id) ON DELETE SET NULL,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_org_passes_session ON org_passes (session_id, created_at DESC);
CREATE TRIGGER trg_org_passes_updated BEFORE UPDATE ON org_passes
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Handwriting recognition — a separate layer; ink is never changed.
CREATE TABLE ink_recognitions (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    page_id     uuid NOT NULL REFERENCES ink_pages (id) ON DELETE CASCADE,
    session_id  uuid NOT NULL REFERENCES sessions (id) ON DELETE CASCADE,
    user_id     uuid NOT NULL,
    stroke_ids  uuid[] NOT NULL,
    text        text NOT NULL,
    confidence  real NOT NULL DEFAULT 0,
    status      text NOT NULL DEFAULT 'proposed' CHECK (status IN ('proposed', 'confirmed', 'corrected')),
    ai_run_id   uuid REFERENCES ai_runs (id) ON DELETE SET NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_ink_recognitions_page ON ink_recognitions (page_id);
CREATE TRIGGER trg_ink_recognitions_updated BEFORE UPDATE ON ink_recognitions
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

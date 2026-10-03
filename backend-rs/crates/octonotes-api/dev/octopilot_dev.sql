-- LOCAL DEV ONLY — a minimal stand-in for the shared octopilot `users` table,
-- so /v1/me works without touching production. It holds only the columns
-- octo-common reads; the real table is owned by octopilot-api and has more.
-- Never run this against the real octopilot database.

CREATE TABLE IF NOT EXISTS users (
    id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    firebase_uid          varchar(128) UNIQUE NOT NULL,
    email                 varchar(255) UNIQUE,
    name                  varchar(255),
    photo_url             varchar(500),
    plan                  varchar(50) DEFAULT 'Unauthenticated Plan',
    is_admin              boolean DEFAULT false,
    word_credits          integer DEFAULT 0,
    source_credits        integer DEFAULT 0,
    humanizer_credits     integer DEFAULT 0,
    octo_credits          integer DEFAULT 0,
    has_completed_wizard  boolean DEFAULT false
);

-- The user the API resolves when auth is disabled (X-User-Id: dev-user).
INSERT INTO users (firebase_uid, email, name, plan, octo_credits)
VALUES ('dev-user', 'dev@octonotes.local', 'Dev Student', 'Pro Monthly', 5000)
ON CONFLICT (firebase_uid) DO NOTHING;

-- Ledger, keys and settings, shaped like the octopilot-api models
-- LIVE octopilot DB (checked 2026-09-26): ledger id has no default and
-- source_ref is indexed but not unique (3 duplicates exist in production).
CREATE TABLE IF NOT EXISTS credit_ledger (
    id                uuid PRIMARY KEY,   -- no default, like production
    user_id           uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    credit_type       varchar(20) NOT NULL,
    entry_type        varchar(50) NOT NULL,
    amount            integer NOT NULL,
    available_amount  integer NOT NULL,
    expires_at        timestamptz,
    source_ref        varchar(255),
    reason            text,
    admin_email       varchar(255),
    metadata_json     text,
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_credit_ledger_source_ref ON credit_ledger (source_ref);

CREATE TABLE IF NOT EXISTS api_keys (
    id           serial PRIMARY KEY,
    provider     varchar(64) NOT NULL,
    key          text NOT NULL,
    is_active    boolean NOT NULL DEFAULT true,
    usage_count  integer DEFAULT 0
);

CREATE TABLE IF NOT EXISTS system_settings (
    key    varchar(128) PRIMARY KEY,
    value  text
);

-- AI settings (shared tables, see backend-rs/shared-sql/2026-10-05_ai_settings.sql).

-- What users choose from: one name ("Octo v2 Pro") for a bundle of real
-- models. The OpenRouter ids never reach a user.
CREATE TABLE IF NOT EXISTS ai_models (
    id                  text PRIMARY KEY,                 -- 'octo-v2-pro'
    display_name        text NOT NULL,                    -- 'Octo v2 Pro'
    tagline             text NOT NULL DEFAULT '',
    orchestrator_model  text NOT NULL,                    -- drives the work; must support tool calling
    writer_model        text NOT NULL,                    -- writes and revises
    fast_model          text NOT NULL,                    -- summaries, checks, quick replies
    min_plan            text NOT NULL DEFAULT 'free' CHECK (min_plan IN ('free', 'pro')),
    credit_multiplier   numeric NOT NULL DEFAULT 1 CHECK (credit_multiplier > 0),
    enabled             boolean NOT NULL DEFAULT true,
    is_default          boolean NOT NULL DEFAULT false,
    sort                integer NOT NULL DEFAULT 0,
    updated_at          timestamptz NOT NULL DEFAULT now()
);
-- At most one default.
CREATE UNIQUE INDEX IF NOT EXISTS ai_models_one_default ON ai_models (is_default) WHERE is_default;

-- How the AI talks in chat. Never applied to the essay itself.
CREATE TABLE IF NOT EXISTS ai_personalities (
    id            text PRIMARY KEY,                       -- 'gen-z'
    display_name  text NOT NULL,                          -- 'Gen Z'
    description   text NOT NULL DEFAULT '',
    prompt        text NOT NULL,
    enabled       boolean NOT NULL DEFAULT true,
    is_default    boolean NOT NULL DEFAULT false,
    sort          integer NOT NULL DEFAULT 0,
    updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS ai_personalities_one_default
    ON ai_personalities (is_default) WHERE is_default;

-- Each user's choice. scope: 'global' (every app) or an app ('ghostwriter',
-- 'study_studio'). A NULL field follows the wider scope.
CREATE TABLE IF NOT EXISTS user_ai_preferences (
    user_id         uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    scope           text NOT NULL CHECK (scope IN ('global', 'ghostwriter', 'study_studio')),
    model_id        text REFERENCES ai_models (id) ON DELETE SET NULL,
    personality_id  text REFERENCES ai_personalities (id) ON DELETE SET NULL,
    updated_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, scope)
);

-- The OctoCredit price table: one row. Defaults = Pricing Final v1.0.
CREATE TABLE IF NOT EXISTS pricing_config (
    id                    boolean PRIMARY KEY DEFAULT true CHECK (id),
    gen_words_per_dollar  numeric NOT NULL DEFAULT 30000 CHECK (gen_words_per_dollar > 0),
    hum_words_per_dollar  numeric NOT NULL DEFAULT 3000 CHECK (hum_words_per_dollar > 0),
    sources_per_dollar    numeric NOT NULL DEFAULT 50 CHECK (sources_per_dollar > 0),
    oc_per_dollar         numeric NOT NULL DEFAULT 100 CHECK (oc_per_dollar > 0),
    min_charge            integer NOT NULL DEFAULT 100 CHECK (min_charge >= 0),
    round_to              integer NOT NULL DEFAULT 100 CHECK (round_to > 0),
    updated_at            timestamptz NOT NULL DEFAULT now()
);
INSERT INTO pricing_config (id) VALUES (true) ON CONFLICT (id) DO NOTHING;

-- Every change to the price table, kept by the database itself (admins write
-- the table directly, so no service can be relied on to log it).
CREATE TABLE IF NOT EXISTS pricing_audit (
    id          bigserial PRIMARY KEY,
    changed_at  timestamptz NOT NULL DEFAULT now(),
    changed_by  text NOT NULL DEFAULT current_user,
    old_row     jsonb,
    new_row     jsonb
);

CREATE OR REPLACE FUNCTION pricing_config_audit() RETURNS trigger AS $$
BEGIN
    NEW.updated_at := now();
    INSERT INTO pricing_audit (old_row, new_row) VALUES (to_jsonb(OLD), to_jsonb(NEW));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS pricing_config_audit ON pricing_config;
CREATE TRIGGER pricing_config_audit
    BEFORE UPDATE ON pricing_config
    FOR EACH ROW EXECUTE FUNCTION pricing_config_audit();

-- Deleted accounts and app status (see backend-rs/shared-sql/2026-10-06_accounts_and_app_status.sql).
CREATE TABLE IF NOT EXISTS deleted_users (
    user_id       uuid PRIMARY KEY,           -- the deleted users.id
    firebase_uid  text,                       -- so services can drop cached sign-ins
    deleted_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS deleted_users_at ON deleted_users (deleted_at);

CREATE OR REPLACE FUNCTION users_record_deleted() RETURNS trigger AS $$
BEGIN
    INSERT INTO deleted_users (user_id, firebase_uid)
    VALUES (OLD.id, OLD.firebase_uid)
    ON CONFLICT (user_id) DO NOTHING;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS users_record_deleted ON users;
CREATE TRIGGER users_record_deleted
    AFTER DELETE ON users
    FOR EACH ROW EXECUTE FUNCTION users_record_deleted();

-- What the apps check when they open: is this version still supported, is
-- there a newer one, is the service down for maintenance. Admins write it.
--   app:      'ghostwriter' (the GhostWriter build), later the main app
--   platform: 'android' | 'ios' | 'web', or '*' for every platform
-- A platform's own row wins over '*'.
CREATE TABLE IF NOT EXISTS app_status (
    app                  text NOT NULL,
    platform             text NOT NULL DEFAULT '*'
                         CHECK (platform IN ('*', 'android', 'ios', 'web')),
    min_version          text,               -- older than this must update
    latest_version       text,               -- older than this may update
    store_url            text,
    maintenance          boolean NOT NULL DEFAULT false,
    maintenance_message  text,
    updated_at           timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (app, platform)
);

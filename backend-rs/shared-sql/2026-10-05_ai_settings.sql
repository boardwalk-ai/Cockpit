-- AI settings for every app (GhostWriter, Study Studio, …), in the SHARED
-- octopilot database. Admins write these tables directly; the services only
-- read them (octo-common `ai`).
--
-- NOT applied automatically. Running this on the production octopilot DB
-- changes a database other services use: get approval first. It only adds
-- tables and a trigger; it touches no existing table.

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

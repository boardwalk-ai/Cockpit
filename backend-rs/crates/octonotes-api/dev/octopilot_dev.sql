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
-- (_backend_snapshot/models.py). The unique index on source_ref is what the
-- shared charging protocol relies on; production needs it added too.
CREATE TABLE IF NOT EXISTS credit_ledger (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id           uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    credit_type       varchar(20) NOT NULL,
    entry_type        varchar(50) NOT NULL,
    amount            integer NOT NULL,
    available_amount  integer NOT NULL DEFAULT 0,
    expires_at        timestamptz,
    source_ref        varchar(255),
    reason            text,
    admin_email       varchar(255),
    metadata_json     text,
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_credit_ledger_source_ref ON credit_ledger (source_ref) WHERE source_ref IS NOT NULL;

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

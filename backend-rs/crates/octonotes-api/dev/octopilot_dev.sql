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

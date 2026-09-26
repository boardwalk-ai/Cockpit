-- Least-privilege roles for octonotes-api. Run each section against its own
-- database as that database's owner (passwords via psql variables):
--
--   psql -d octonotes  -v pw="'…'" -f roles.sql   (section 1, as octonotes_admin)
--   psql -d cockpit    -v pw="'…'" …             (section 2)
--   psql -d vectors    -v pw="'…'" …             (section 3)
--   psql -d octopilot  -v pw="'…'" …             (section 4, as the octopilot owner)
--
-- Split the file per section when running it; each section is idempotent.

-- ── 1. notes_db (owned by OctoNotes) ───────────────────────────────────────
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'octonotes_rw') THEN
    CREATE ROLE octonotes_rw LOGIN;
  END IF;
END $$;
ALTER ROLE octonotes_rw PASSWORD :pw;
GRANT CONNECT, CREATE ON DATABASE octonotes TO octonotes_rw;
GRANT USAGE, CREATE ON SCHEMA public TO octonotes_rw;
-- The API runs migrations at startup, so it owns its tables.
ALTER SCHEMA public OWNER TO octonotes_rw;
CREATE EXTENSION IF NOT EXISTS vector;

-- ── 2. Study Studio business DB (read-only) ────────────────────────────────
-- DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'octonotes_ro') THEN CREATE ROLE octonotes_ro LOGIN; END IF; END $$;
-- ALTER ROLE octonotes_ro PASSWORD :pw;
-- GRANT CONNECT ON DATABASE cockpit TO octonotes_ro;
-- GRANT USAGE ON SCHEMA public TO octonotes_ro;
-- GRANT SELECT ON studios, documents, generated_topics, topic_progress, studio_builds TO octonotes_ro;

-- ── 3. Study Studio vector DB (read-only) ──────────────────────────────────
-- DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'octonotes_ro') THEN CREATE ROLE octonotes_ro LOGIN; END IF; END $$;
-- ALTER ROLE octonotes_ro PASSWORD :pw;
-- GRANT CONNECT ON DATABASE vectors TO octonotes_ro;
-- GRANT USAGE ON SCHEMA public TO octonotes_ro;
-- GRANT SELECT ON chunks TO octonotes_ro;

-- ── 4. octopilot DB (identity + central OctoCredits) ───────────────────────
-- Reads identity, keys and settings; writes ONLY ledger rows and the balance.
-- DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'octonotes_credits') THEN CREATE ROLE octonotes_credits LOGIN; END IF; END $$;
-- ALTER ROLE octonotes_credits PASSWORD :pw;
-- GRANT CONNECT ON DATABASE octopilot TO octonotes_credits;
-- GRANT USAGE ON SCHEMA public TO octonotes_credits;
-- GRANT SELECT (id, firebase_uid, email, name, photo_url, plan, is_admin, word_credits, source_credits,
--               humanizer_credits, octo_credits, has_completed_wizard) ON users TO octonotes_credits;
-- GRANT UPDATE (octo_credits) ON users TO octonotes_credits;      -- also allows SELECT … FOR UPDATE
-- GRANT SELECT, INSERT ON credit_ledger TO octonotes_credits;
-- GRANT SELECT ON api_keys, system_settings TO octonotes_credits;
--
-- The shared charging protocol needs source_ref unique (every app relies on it):
-- CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS ux_credit_ledger_source_ref
--     ON credit_ledger (source_ref) WHERE source_ref IS NOT NULL;
-- Production already has 3 duplicate source_refs (2026-09-26): resolve them with
-- the octopilot-api owners first. OctoNotes does not depend on this index (it
-- checks under the user row lock); the index is extra safety.
-- Check duplicates:
--   SELECT source_ref, count(*) FROM credit_ledger WHERE source_ref IS NOT NULL GROUP BY 1 HAVING count(*) > 1;

-- Deleted accounts and app status, in the SHARED octopilot database.
--
-- NOT applied automatically. Running this on the production octopilot DB
-- changes a database other services use: get approval first. It adds two
-- tables and a trigger on `users`; it changes no existing row or column.

-- Deleted accounts. Each service sweeps its own data for these users (their
-- data lives in other databases, so a cascade cannot reach it). Filled by
-- the database when a `users` row is deleted, whoever deletes it, so no
-- service has to remember to.
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

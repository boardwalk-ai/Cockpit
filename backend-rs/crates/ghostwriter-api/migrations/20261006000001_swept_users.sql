-- Deleted accounts (shared `deleted_users`) whose GhostWriter data is gone.
-- `deleted_at` is copied from the tombstone, so a sweep can start where the
-- last one ended.
CREATE TABLE swept_users (
    user_id     uuid PRIMARY KEY,
    deleted_at  timestamptz NOT NULL,
    swept_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX swept_users_deleted ON swept_users (deleted_at);

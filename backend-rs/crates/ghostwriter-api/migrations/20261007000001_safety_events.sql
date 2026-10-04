-- Content checks that stopped a run (src/safety.rs): who, where, which
-- category. The text itself is never kept.
CREATE TABLE safety_events (
    id          bigserial PRIMARY KEY,
    user_id     uuid NOT NULL,
    run_id      uuid,
    stage       text NOT NULL,
    category    text NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX safety_events_user ON safety_events (user_id, created_at);

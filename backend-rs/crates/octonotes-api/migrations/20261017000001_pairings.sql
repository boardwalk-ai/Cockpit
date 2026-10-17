-- Pairing another phone as a session's recorder: the receiver shows a 6-digit
-- code (or a QR with the secret), the phone claims it, and when the receiver
-- starts the session the phone learns its id and records into it.
CREATE TABLE session_pairings (
    id                  uuid PRIMARY KEY,
    user_id             uuid NOT NULL,
    code                text NOT NULL,
    secret              text NOT NULL UNIQUE,
    receiver_device_id      uuid NOT NULL,
    recorder_device_id  uuid,
    session_id          uuid,
    created_at          timestamptz NOT NULL DEFAULT now(),
    claimed_at          timestamptz,
    started_at          timestamptz,
    cancelled_at        timestamptz,
    expires_at          timestamptz NOT NULL
);
CREATE INDEX session_pairings_user_code ON session_pairings (user_id, code);

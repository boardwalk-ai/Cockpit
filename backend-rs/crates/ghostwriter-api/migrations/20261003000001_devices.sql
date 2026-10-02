-- The installs that receive a user's push notifications.

CREATE TABLE devices (
    id          uuid PRIMARY KEY,               -- chosen by the app, once per install
    user_id     uuid NOT NULL,                  -- whoever is signed in on it
    token       text NOT NULL UNIQUE,           -- FCM registration token
    platform    text NOT NULL CHECK (platform IN ('android', 'ios', 'web')),
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX devices_user ON devices (user_id);

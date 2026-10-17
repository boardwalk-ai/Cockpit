//! Who may use the app, and which parts of it are on — for the test
//! environment. One allowlist and one set of feature flags in the shared
//! octopilot DB, read by every service and changed from the admin app.
//! Each service re-reads them every few seconds, so a change lands almost at
//! once without a restart.
//!
//! Flags: on for everyone (`enabled`), on only for the listed `emails`
//! (`enabled = false`), or off. A flag nobody has made yet counts as on, so
//! a new module is never shut by accident. `open_access` (off by default)
//! lets anyone signed in past the allowlist.

use std::collections::{BTreeMap, HashMap, HashSet};
use std::sync::Arc;
use std::time::{Duration, Instant};

use axum::http::StatusCode;
use serde::Serialize;
use serde_json::json;
use sqlx::{PgPool, Row};
use tokio::sync::RwLock;

use crate::auth::AuthedUser;
use crate::error::ApiError;

/// How long a read of the allowlist and flags is trusted.
const FRESH: Duration = Duration::from_secs(5);

/// The flag that opens the app to anyone signed in.
pub const OPEN_ACCESS: &str = "open_access";

const SCHEMA: &str = r#"
CREATE TABLE IF NOT EXISTS app_allowlist (
    email      text PRIMARY KEY,
    note       text,
    added_by   text,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS feature_flags (
    key         text PRIMARY KEY,
    enabled     boolean NOT NULL DEFAULT true,
    emails      text[] NOT NULL DEFAULT '{}',
    description text,
    updated_by  text,
    updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS admin_audit (
    id          bigserial PRIMARY KEY,
    admin_email text NOT NULL,
    action      text NOT NULL,
    target      text,
    detail      jsonb,
    created_at  timestamptz NOT NULL DEFAULT now()
);
INSERT INTO feature_flags (key, enabled, description) VALUES
    ('open_access',  false, 'Anyone signed in may use the app, not only the allowlist'),
    ('study_studio', true,  'Study Studio'),
    ('study_share',  true,  'Study Studio share links'),
    ('ghostwriter',  true,  'GhostWriter'),
    ('main_chat',    true,  'The main chat on Home'),
    ('voice',        true,  'Voice in the main chat')
ON CONFLICT (key) DO NOTHING;
"#;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Flag {
    pub enabled: bool,
    pub emails: Vec<String>,
}

impl Flag {
    pub fn on_for(&self, email: Option<&str>) -> bool {
        self.enabled || email.is_some_and(|e| self.emails.iter().any(|x| x == e))
    }
}

/// The allowlist and flags as last read.
#[derive(Debug, Clone, Default)]
pub struct Snapshot {
    pub allow: HashSet<String>,
    pub flags: HashMap<String, Flag>,
}

impl Snapshot {
    /// Off only when the flag exists and isn't on for this email.
    pub fn flag(&self, key: &str, email: Option<&str>) -> bool {
        self.flags.get(key).is_none_or(|f| f.on_for(email))
    }

    pub fn invited(&self, email: Option<&str>) -> bool {
        // `open_access` is off unless it was made and switched on.
        self.flags.get(OPEN_ACCESS).is_some_and(|f| f.on_for(email))
            || email.is_some_and(|e| self.allow.contains(e))
    }

    /// Every flag as on/off for one user (what the app shows or hides).
    pub fn flags_for(&self, email: Option<&str>) -> BTreeMap<String, bool> {
        self.flags.iter().map(|(k, f)| (k.clone(), f.on_for(email))).collect()
    }
}

/// The verified, lower-cased email of a sign-in (None if unverified).
pub fn email_of(user: &AuthedUser) -> Option<String> {
    user.email.as_deref().filter(|_| user.email_verified).map(|e| e.trim().to_lowercase())
}

type Cached = Arc<RwLock<Option<(Instant, Arc<Snapshot>)>>>;

/// The gate. Cheap to clone.
#[derive(Clone)]
pub struct Access {
    pool: PgPool,
    admins: Arc<Vec<String>>,
    cache: Cached,
}

impl Access {
    /// `admins`: emails that always get in (they run the admin app).
    pub fn new(pool: PgPool, admins: Vec<String>) -> Self {
        let admins = admins.into_iter().map(|e| e.trim().to_lowercase()).filter(|e| !e.is_empty()).collect();
        Self { pool, admins: Arc::new(admins), cache: Arc::default() }
    }

    pub async fn ensure_schema(&self) -> Result<(), sqlx::Error> {
        sqlx::raw_sql(SCHEMA).execute(&self.pool).await.map(|_| ())
    }

    pub fn is_admin(&self, email: Option<&str>) -> bool {
        email.is_some_and(|e| self.admins.iter().any(|a| a == e))
    }

    /// The allowlist and flags, re-read when older than a few seconds. If
    /// the DB can't be read, the last good read stands; with none, nobody
    /// but an admin gets in.
    pub async fn snapshot(&self) -> Arc<Snapshot> {
        if let Some((at, s)) = self.cache.read().await.as_ref() {
            if at.elapsed() < FRESH {
                return s.clone();
            }
        }
        match self.load().await {
            Ok(s) => {
                let s = Arc::new(s);
                *self.cache.write().await = Some((Instant::now(), s.clone()));
                s
            }
            Err(e) => {
                tracing::warn!("access: {e}");
                self.cache.read().await.as_ref().map(|(_, s)| s.clone()).unwrap_or_default()
            }
        }
    }

    /// Forget the last read (after the admin app changed something here).
    pub async fn refresh(&self) {
        *self.cache.write().await = None;
    }

    async fn load(&self) -> Result<Snapshot, sqlx::Error> {
        let allow = sqlx::query_scalar::<_, String>("SELECT lower(email) FROM app_allowlist")
            .fetch_all(&self.pool)
            .await?
            .into_iter()
            .collect();
        let flags = sqlx::query("SELECT key, enabled, emails FROM feature_flags")
            .fetch_all(&self.pool)
            .await?
            .into_iter()
            .map(|r| {
                let emails: Vec<String> = r.get("emails");
                (
                    r.get::<String, _>("key"),
                    Flag { enabled: r.get("enabled"), emails: emails.into_iter().map(|e| e.to_lowercase()).collect() },
                )
            })
            .collect();
        Ok(Snapshot { allow, flags })
    }

    /// May this sign-in use the app, and `feature` (when given)?
    /// 403 `not_invited` off the allowlist, 403 `feature_off` for a flag
    /// that's off for them. Admins always pass.
    pub async fn admit(&self, user: &AuthedUser, feature: Option<&str>) -> Result<(), ApiError> {
        let email = email_of(user);
        if self.is_admin(email.as_deref()) {
            return Ok(());
        }
        let s = self.snapshot().await;
        if !s.invited(email.as_deref()) {
            return Err(not_invited());
        }
        if let Some(f) = feature {
            if !s.flag(f, email.as_deref()) {
                return Err(feature_off(f));
            }
        }
        Ok(())
    }

    /// Is `feature` on for this sign-in? (For parts of a module.)
    pub async fn flag(&self, user: &AuthedUser, feature: &str) -> bool {
        let email = email_of(user);
        self.is_admin(email.as_deref()) || self.snapshot().await.flag(feature, email.as_deref())
    }
}

pub fn not_invited() -> ApiError {
    ApiError::new(StatusCode::FORBIDDEN, "This account isn't on the test list yet.").with_code("not_invited")
}

pub fn feature_off(feature: &str) -> ApiError {
    ApiError::new(StatusCode::FORBIDDEN, "This part of the app is switched off for now.")
        .with_code("feature_off")
        .with_details(json!({ "feature": feature }))
}

/// Makes an octopilot account with `credits` OctoCredits for a first
/// sign-in that has none (the test environment has no sign-up). True if one
/// was made. Call it only for a sign-in the gate let through.
pub async fn provision(pool: &PgPool, user: &AuthedUser, credits: i32) -> Result<bool, ApiError> {
    let Some(email) = email_of(user) else { return Ok(false) };
    let made = sqlx::query(
        "INSERT INTO users (firebase_uid, email, name, plan, octo_credits) \
         VALUES ($1, $2, $3, 'Tester', $4) ON CONFLICT DO NOTHING",
    )
    .bind(&user.uid)
    .bind(&email)
    .bind(user.name.as_deref().unwrap_or(&email))
    .bind(credits)
    .execute(pool)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "could not make a tester account");
        ApiError::internal("could not make the account")
    })?
    .rows_affected()
        > 0;
    if made {
        tracing::info!(%email, "tester account made");
    }
    Ok(made)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn snap(allow: &[&str], flags: &[(&str, bool, &[&str])]) -> Snapshot {
        Snapshot {
            allow: allow.iter().map(|s| s.to_string()).collect(),
            flags: flags
                .iter()
                .map(|(k, on, e)| (k.to_string(), Flag { enabled: *on, emails: e.iter().map(|s| s.to_string()).collect() }))
                .collect(),
        }
    }

    #[test]
    fn only_the_allowlist_gets_in_until_the_app_is_opened() {
        let s = snap(&["a@x.com"], &[(OPEN_ACCESS, false, &[])]);
        assert!(s.invited(Some("a@x.com")));
        assert!(!s.invited(Some("b@x.com")));
        assert!(!s.invited(None));
        let s = snap(&["a@x.com"], &[(OPEN_ACCESS, true, &[])]);
        assert!(s.invited(Some("b@x.com")));
        // No open_access row at all: still closed.
        assert!(!snap(&[], &[]).invited(Some("b@x.com")));
    }

    #[test]
    fn flags_are_on_off_or_for_some() {
        let s = snap(&[], &[("voice", false, &["a@x.com"]), ("share", false, &[]), ("gw", true, &[])]);
        assert!(s.flag("voice", Some("a@x.com")));
        assert!(!s.flag("voice", Some("b@x.com")));
        assert!(!s.flag("share", Some("a@x.com")));
        assert!(s.flag("gw", None));
        assert!(s.flag("never_made", Some("b@x.com")));
    }
}

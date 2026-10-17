//! Admin API for the test environment. The admin app manages, in the shared
//! octopilot DB that every service of the test app reads:
//!
//! - the app-wide allowlist (`app_allowlist`),
//! - OctoCredits (+/- written to `credit_ledger` as `admin_grant` /
//!   `admin_deduct`, the balance in `users.octo_credits`),
//! - feature flags (`feature_flags`),
//! - prices and models in `system_settings` (only those keys),
//!
//! and every change is written to `admin_audit`. The services re-read the
//! allowlist and flags every few seconds (`octo_common::access`).
//!
//! The Octopilot app itself asks `GET /v1/app/access` (or its stream) whether
//! it's let in, which flags are on and its balance.

pub mod devices;
pub mod notify;

use std::convert::Infallible;
use std::sync::Arc;
use std::time::Duration;

use axum::extract::{FromRequestParts, Path, Query, State};
use axum::http::request::Parts;
use axum::http::{HeaderName, StatusCode};
use axum::response::sse::{Event, KeepAlive, Sse};
use axum::extract::DefaultBodyLimit;
use axum::routing::{delete, get, post, put};
use axum::{async_trait, Json, Router};
use futures::Stream;
use octo_common::access::{email_of, Access};
use octo_common::{ApiError, AuthedUser, FirebaseAuth, HasFirebase};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::{PgPool, Row};
use tower_http::request_id::{MakeRequestUuid, PropagateRequestIdLayer, SetRequestIdLayer};
use tower_http::trace::TraceLayer;
use uuid::Uuid;

#[derive(Debug, Clone)]
pub struct Config {
    pub bind: String,
    pub port: u16,
    pub database_url: String,
    pub firebase_project_id: String,
    pub admin_emails: Vec<String>,
    pub log_format: String,
    /// Where the test app's phones are registered (announcements).
    pub study_database_url: Option<String>,
    pub ghostwriter_database_url: Option<String>,
    pub fcm_service_account_file: Option<String>,
    /// Uploaded notification pictures, served at `{public_url}/media/…`.
    pub media_dir: String,
    /// This API as the world reaches it.
    pub public_url: String,
}

fn var(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|v| !v.trim().is_empty())
}

impl Config {
    pub fn from_env() -> Self {
        Self {
            bind: var("BIND").unwrap_or_else(|| "127.0.0.1".into()),
            port: var("PORT").and_then(|p| p.parse().ok()).unwrap_or(8796),
            database_url: var("SHARED_DATABASE_URL").expect("SHARED_DATABASE_URL"),
            firebase_project_id: var("FIREBASE_PROJECT_ID").unwrap_or_default(),
            admin_emails: var("ADMIN_EMAILS")
                .map(|v| v.split(',').map(|s| s.trim().to_lowercase()).filter(|s| !s.is_empty()).collect())
                .unwrap_or_default(),
            log_format: var("LOG_FORMAT").unwrap_or_else(|| "text".into()),
            study_database_url: var("STUDY_DATABASE_URL"),
            ghostwriter_database_url: var("GHOSTWRITER_DATABASE_URL"),
            fcm_service_account_file: var("FCM_SERVICE_ACCOUNT_FILE"),
            media_dir: var("MEDIA_DIR").unwrap_or_else(|| "/var/lib/admin-api/media".into()),
            public_url: var("PUBLIC_URL").unwrap_or_else(|| "https://gw-staging.octopilothub.com/control".into()),
        }
    }
}

#[derive(Clone)]
pub struct AppState {
    pub config: Arc<Config>,
    pub db: PgPool,
    pub firebase: FirebaseAuth,
    pub access: Access,
    pub pusher: Arc<dyn octo_common::push::Pusher>,
    pub devices: notify::DeviceSources,
}

impl HasFirebase for AppState {
    fn firebase(&self) -> &FirebaseAuth {
        &self.firebase
    }
}

impl AppState {
    pub async fn connect(config: &Config) -> Result<Self, sqlx::Error> {
        let db = octo_common::db::connect(&config.database_url, 5).await?;
        let access = Access::new(db.clone(), config.admin_emails.clone());
        access.ensure_schema().await?;
        sqlx::raw_sql(notify::SCHEMA).execute(&db).await?;
        sqlx::raw_sql(devices::SCHEMA).execute(&db).await?;
        let http = reqwest::Client::new();
        let pusher: Arc<dyn octo_common::push::Pusher> = match &config.fcm_service_account_file {
            Some(path) => match octo_common::push::FcmPusher::from_file(http.clone(), path, notify::CHANNEL) {
                Ok(p) => Arc::new(p),
                Err(e) => {
                    tracing::warn!("push off: {e}");
                    Arc::new(octo_common::push::NoPusher)
                }
            },
            None => Arc::new(octo_common::push::NoPusher),
        };
        let pool = |url: &Option<String>| {
            let url = url.clone();
            async move {
                match url {
                    Some(u) => octo_common::db::connect(&u, 2).await.map(Some),
                    None => Ok(None),
                }
            }
        };
        let devices = notify::DeviceSources {
            study: pool(&config.study_database_url).await?,
            ghostwriter: pool(&config.ghostwriter_database_url).await?,
        };
        Ok(Self {
            firebase: FirebaseAuth::new(config.firebase_project_id.clone(), http),
            config: Arc::new(config.clone()),
            db,
            access,
            pusher,
            devices,
        })
    }
}

pub fn app(state: AppState) -> Router {
    let request_id = HeaderName::from_static("x-request-id");
    Router::new()
        .route("/health", get(|| async { Json(json!({ "ok": true })) }))
        .route("/v1/app/access", get(app_access))
        .route("/v1/app/access/stream", get(app_access_stream))
        .route("/v1/app/devices", put(devices::report))
        .route("/v1/app/devices/:id", delete(devices::signed_out))
        .route("/v1/admin/devices", get(devices::list))
        .route("/v1/admin/me", get(admin_me))
        .route("/v1/admin/users", get(users))
        .route("/v1/admin/users/:id/credits", post(credits))
        .route("/v1/admin/allowlist", get(allowlist).post(allow))
        .route("/v1/admin/allowlist/:email", delete(disallow))
        .route("/v1/admin/flags", get(flags))
        .route("/v1/admin/flags/:key", put(put_flag))
        .route("/v1/admin/settings", get(settings))
        .route("/v1/admin/settings/:key", put(put_setting))
        .route("/v1/admin/audit", get(audit))
        .route("/v1/admin/notifications", get(notify::history).post(notify::send))
        .route("/v1/admin/media", post(notify::upload).layer(DefaultBodyLimit::max(2 * 1024 * 1024)))
        .route("/media/:file", get(notify::media))
        .layer(PropagateRequestIdLayer::new(request_id.clone()))
        .layer(TraceLayer::new_for_http())
        .layer(SetRequestIdLayer::new(request_id, MakeRequestUuid))
        .with_state(state)
}

// ------------------------------------------------------------ the app ---

/// Is this sign-in let in, what's on for it, and its balance.
async fn access_of(st: &AppState, user: &AuthedUser) -> Value {
    let email = email_of(user);
    let admin = st.access.is_admin(email.as_deref());
    let s = st.access.snapshot().await;
    let mut flags = s.flags_for(email.as_deref());
    if admin {
        flags.values_mut().for_each(|v| *v = true);
    }
    flags.remove(octo_common::access::OPEN_ACCESS);
    let credits: Option<i32> = sqlx::query_scalar("SELECT COALESCE(octo_credits, 0) FROM users WHERE firebase_uid = $1")
        .bind(&user.uid)
        .fetch_optional(&st.db)
        .await
        .ok()
        .flatten();
    json!({
        "email": email,
        "invited": admin || s.invited(email.as_deref()),
        "admin": admin,
        "flags": flags,
        "credits": credits,
    })
}

/// `GET /v1/app/access`
async fn app_access(State(st): State<AppState>, user: AuthedUser) -> Json<Value> {
    Json(access_of(&st, &user).await)
}

/// `GET /v1/app/access/stream` — the same, again whenever it changes (an
/// admin let them in, switched a flag, moved their balance).
async fn app_access_stream(
    State(st): State<AppState>,
    user: AuthedUser,
) -> Sse<impl Stream<Item = Result<Event, Infallible>>> {
    let stream = async_stream::stream! {
        let mut last = Value::Null;
        loop {
            let now = access_of(&st, &user).await;
            if now != last {
                yield Ok(Event::default().event("access").data(now.to_string()));
                last = now;
            }
            tokio::time::sleep(Duration::from_secs(3)).await;
        }
    };
    Sse::new(stream).keep_alive(KeepAlive::default())
}

// ------------------------------------------------------------- admins ---

/// An admin of the test environment (ADMIN_EMAILS).
pub struct Admin(pub String);

#[async_trait]
impl FromRequestParts<AppState> for Admin {
    type Rejection = ApiError;

    async fn from_request_parts(parts: &mut Parts, st: &AppState) -> Result<Self, ApiError> {
        let user = AuthedUser::from_request_parts(parts, st).await?;
        match email_of(&user) {
            Some(e) if st.access.is_admin(Some(&e)) => Ok(Admin(e)),
            _ => Err(ApiError::new(StatusCode::FORBIDDEN, "Admins only.").with_code("not_admin")),
        }
    }
}

pub(crate) async fn log(st: &AppState, admin: &str, action: &str, target: &str, detail: Value) {
    let r = sqlx::query("INSERT INTO admin_audit (admin_email, action, target, detail) VALUES ($1, $2, $3, $4)")
        .bind(admin)
        .bind(action)
        .bind(target)
        .bind(detail)
        .execute(&st.db)
        .await;
    if let Err(e) = r {
        tracing::warn!("audit: {e}");
    }
}

async fn admin_me(Admin(email): Admin) -> Json<Value> {
    Json(json!({ "email": email }))
}

#[derive(Deserialize)]
struct Search {
    q: Option<String>,
}

/// `GET /v1/admin/users?q=` — accounts, and allowlisted emails that haven't
/// signed in yet (no `id`).
async fn users(State(st): State<AppState>, _: Admin, Query(s): Query<Search>) -> Result<Json<Value>, ApiError> {
    let q = s.q.unwrap_or_default().trim().to_lowercase();
    let rows = sqlx::query(
        "SELECT u.id::text AS id, lower(COALESCE(u.email, a.email)) AS email, u.name, u.photo_url, \
                COALESCE(u.octo_credits, 0) AS credits, a.email IS NOT NULL AS invited, a.note \
         FROM users u FULL JOIN app_allowlist a ON lower(a.email) = lower(u.email) \
         WHERE $1 = '' OR lower(COALESCE(u.email, a.email)) LIKE '%' || $1 || '%' OR lower(COALESCE(u.name, '')) LIKE '%' || $1 || '%' \
         ORDER BY 2 LIMIT 300",
    )
    .bind(&q)
    .fetch_all(&st.db)
    .await?;
    let snap = st.access.snapshot().await;
    let open = snap.invited(None);
    let phones = devices::counts(&st.db).await;
    Ok(Json(json!({
        "openAccess": open,
        "users": rows.iter().map(|r| json!({
            "id": r.get::<Option<String>, _>("id"),
            "email": r.get::<Option<String>, _>("email"),
            "name": r.get::<Option<String>, _>("name"),
            "photoUrl": r.get::<Option<String>, _>("photo_url"),
            "credits": r.get::<i32, _>("credits"),
            "invited": r.get::<bool, _>("invited"),
            "note": r.get::<Option<String>, _>("note"),
            "admin": st.access.is_admin(r.get::<Option<String>, _>("email").as_deref()),
            "phones": r.get::<Option<String>, _>("email").and_then(|e| phones.get(&e)).map_or(0, |p| p.0),
            "phonesSeen": r.get::<Option<String>, _>("email").and_then(|e| phones.get(&e)).map_or(0, |p| p.1),
        })).collect::<Vec<_>>(),
    })))
}

#[derive(Deserialize)]
struct CreditMove {
    delta: i32,
    reason: Option<String>,
}

/// `POST /v1/admin/users/{id}/credits` `{ delta, reason }` — adds (delta > 0)
/// or takes away OctoCredits; never below 0.
async fn credits(
    State(st): State<AppState>,
    Admin(admin): Admin,
    Path(id): Path<Uuid>,
    Json(m): Json<CreditMove>,
) -> Result<Json<Value>, ApiError> {
    if m.delta == 0 || m.delta.abs() > 1_000_000 {
        return Err(ApiError::bad_request("delta must be between -1,000,000 and 1,000,000, not 0"));
    }
    let reason = m.reason.as_deref().map(str::trim).filter(|r| !r.is_empty()).unwrap_or("admin");
    let mut tx = st.db.begin().await?;
    let row = sqlx::query("SELECT COALESCE(octo_credits, 0) AS c, email FROM users WHERE id = $1 FOR UPDATE")
        .bind(id)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or_else(|| ApiError::not_found("no such account"))?;
    let (balance, email): (i32, Option<String>) = (row.get("c"), row.get("email"));
    let after = balance + m.delta;
    if after < 0 {
        return Err(ApiError::bad_request(format!("They have {balance}; can't take {}.", -m.delta)));
    }
    let (entry, available) = if m.delta > 0 { ("admin_grant", m.delta) } else { ("admin_deduct", 0) };
    sqlx::query(
        "INSERT INTO credit_ledger (id, user_id, credit_type, entry_type, amount, available_amount, source_ref, reason, metadata_json) \
         VALUES (gen_random_uuid(), $1, 'octo', $2, $3, $4, $5, $6, $7)",
    )
    .bind(id)
    .bind(entry)
    .bind(m.delta.abs())
    .bind(available)
    .bind(format!("admin:{}", Uuid::new_v4()))
    .bind(format!("admin: {reason}"))
    .bind(json!({ "admin": admin, "before": balance }).to_string())
    .execute(&mut *tx)
    .await?;
    sqlx::query("UPDATE users SET octo_credits = $2 WHERE id = $1").bind(id).bind(after).execute(&mut *tx).await?;
    tx.commit().await?;
    let target = email.unwrap_or_else(|| id.to_string());
    log(&st, &admin, "credits", &target, json!({ "delta": m.delta, "before": balance, "after": after, "reason": reason })).await;
    Ok(Json(json!({ "balance": after })))
}

/// `GET /v1/admin/allowlist`
async fn allowlist(State(st): State<AppState>, _: Admin) -> Result<Json<Value>, ApiError> {
    let rows = sqlx::query(
        "SELECT a.email, a.note, a.added_by, a.created_at::text AS at, u.id IS NOT NULL AS signed_in \
         FROM app_allowlist a LEFT JOIN users u ON lower(u.email) = lower(a.email) ORDER BY a.created_at DESC",
    )
    .fetch_all(&st.db)
    .await?;
    Ok(Json(json!(rows
        .iter()
        .map(|r| json!({
            "email": r.get::<String, _>("email"),
            "note": r.get::<Option<String>, _>("note"),
            "addedBy": r.get::<Option<String>, _>("added_by"),
            "addedAt": r.get::<String, _>("at"),
            "signedIn": r.get::<bool, _>("signed_in"),
        }))
        .collect::<Vec<_>>())))
}

#[derive(Deserialize)]
struct Allow {
    email: String,
    note: Option<String>,
}

fn clean_email(e: &str) -> Result<String, ApiError> {
    let e = e.trim().to_lowercase();
    let ok = e.len() <= 254 && e.split_once('@').is_some_and(|(a, b)| !a.is_empty() && b.contains('.') && !b.contains('@'));
    if ok {
        Ok(e)
    } else {
        Err(ApiError::bad_request("That isn't an email address."))
    }
}

/// `POST /v1/admin/allowlist` `{ email, note? }`
async fn allow(State(st): State<AppState>, Admin(admin): Admin, Json(a): Json<Allow>) -> Result<Json<Value>, ApiError> {
    let email = clean_email(&a.email)?;
    sqlx::query(
        "INSERT INTO app_allowlist (email, note, added_by) VALUES ($1, $2, $3) \
         ON CONFLICT (email) DO UPDATE SET note = COALESCE(EXCLUDED.note, app_allowlist.note)",
    )
    .bind(&email)
    .bind(a.note.as_deref().map(str::trim).filter(|n| !n.is_empty()))
    .bind(&admin)
    .execute(&st.db)
    .await?;
    st.access.refresh().await;
    log(&st, &admin, "allow", &email, json!({ "note": a.note })).await;
    Ok(Json(json!({ "email": email })))
}

/// `DELETE /v1/admin/allowlist/{email}`
async fn disallow(State(st): State<AppState>, Admin(admin): Admin, Path(email): Path<String>) -> Result<StatusCode, ApiError> {
    let email = email.trim().to_lowercase();
    let n = sqlx::query("DELETE FROM app_allowlist WHERE lower(email) = $1").bind(&email).execute(&st.db).await?.rows_affected();
    if n == 0 {
        return Err(ApiError::not_found("not on the list"));
    }
    st.access.refresh().await;
    log(&st, &admin, "disallow", &email, Value::Null).await;
    Ok(StatusCode::NO_CONTENT)
}

/// `GET /v1/admin/flags`
async fn flags(State(st): State<AppState>, _: Admin) -> Result<Json<Value>, ApiError> {
    let rows = sqlx::query("SELECT key, enabled, emails, description, updated_by, updated_at::text AS at FROM feature_flags ORDER BY key")
        .fetch_all(&st.db)
        .await?;
    Ok(Json(json!(rows
        .iter()
        .map(|r| json!({
            "key": r.get::<String, _>("key"),
            "enabled": r.get::<bool, _>("enabled"),
            "emails": r.get::<Vec<String>, _>("emails"),
            "description": r.get::<Option<String>, _>("description"),
            "updatedBy": r.get::<Option<String>, _>("updated_by"),
            "updatedAt": r.get::<String, _>("at"),
        }))
        .collect::<Vec<_>>())))
}

#[derive(Deserialize)]
struct PutFlag {
    enabled: bool,
    emails: Option<Vec<String>>,
    description: Option<String>,
}

/// `PUT /v1/admin/flags/{key}` `{ enabled, emails?, description? }` — makes
/// the flag if it's new.
async fn put_flag(
    State(st): State<AppState>,
    Admin(admin): Admin,
    Path(key): Path<String>,
    Json(f): Json<PutFlag>,
) -> Result<Json<Value>, ApiError> {
    let key = key.trim().to_lowercase();
    if key.is_empty() || key.len() > 64 || !key.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') {
        return Err(ApiError::bad_request("A flag key is letters, digits and _."));
    }
    let emails = match &f.emails {
        Some(list) => Some(list.iter().map(|e| clean_email(e)).collect::<Result<Vec<_>, _>>()?),
        None => None,
    };
    sqlx::query(
        "INSERT INTO feature_flags (key, enabled, emails, description, updated_by, updated_at) \
         VALUES ($1, $2, COALESCE($3, '{}'), $4, $5, now()) \
         ON CONFLICT (key) DO UPDATE SET enabled = EXCLUDED.enabled, \
             emails = COALESCE($3, feature_flags.emails), \
             description = COALESCE($4, feature_flags.description), \
             updated_by = EXCLUDED.updated_by, updated_at = now()",
    )
    .bind(&key)
    .bind(f.enabled)
    .bind(&emails)
    .bind(&f.description)
    .bind(&admin)
    .execute(&st.db)
    .await?;
    st.access.refresh().await;
    log(&st, &admin, "flag", &key, json!({ "enabled": f.enabled, "emails": emails })).await;
    Ok(Json(json!({ "key": key, "enabled": f.enabled })))
}

/// The settings the admin app may see and change: credit prices and the
/// models. (Never API keys, which also live in `system_settings`.)
fn editable(key: &str) -> bool {
    key.starts_with("study_price_") || key == "study_credits_per_usd" || key.ends_with("_model")
}

/// `GET /v1/admin/settings`
async fn settings(State(st): State<AppState>, _: Admin) -> Result<Json<Value>, ApiError> {
    let rows = sqlx::query("SELECT key, value FROM system_settings ORDER BY key").fetch_all(&st.db).await?;
    Ok(Json(json!(rows
        .iter()
        .filter(|r| editable(&r.get::<String, _>("key")))
        .map(|r| json!({ "key": r.get::<String, _>("key"), "value": r.get::<Option<String>, _>("value") }))
        .collect::<Vec<_>>())))
}

#[derive(Deserialize)]
struct PutSetting {
    /// None removes the setting (a price then falls back to free).
    value: Option<String>,
}

/// `PUT /v1/admin/settings/{key}` `{ value }` (null removes it).
async fn put_setting(
    State(st): State<AppState>,
    Admin(admin): Admin,
    Path(key): Path<String>,
    Json(s): Json<PutSetting>,
) -> Result<Json<Value>, ApiError> {
    if !editable(&key) {
        return Err(ApiError::bad_request("Only prices and models can be changed here."));
    }
    let value = s.value.as_deref().map(str::trim).filter(|v| !v.is_empty());
    if key.starts_with("study_price_") || key == "study_credits_per_usd" {
        if let Some(v) = value {
            if v.parse::<f64>().map_or(true, |n| n < 0.0) {
                return Err(ApiError::bad_request("A price is a number, 0 or more."));
            }
        }
    }
    match value {
        Some(v) => {
            sqlx::query("INSERT INTO system_settings (key, value) VALUES ($1, $2) ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value")
                .bind(&key)
                .bind(v)
                .execute(&st.db)
                .await?;
        }
        None => {
            sqlx::query("DELETE FROM system_settings WHERE key = $1").bind(&key).execute(&st.db).await?;
        }
    }
    log(&st, &admin, "setting", &key, json!({ "value": value })).await;
    Ok(Json(json!({ "key": key, "value": value })))
}

#[derive(Deserialize)]
struct Limit {
    limit: Option<i64>,
}

/// `GET /v1/admin/audit?limit=`
async fn audit(State(st): State<AppState>, _: Admin, Query(l): Query<Limit>) -> Result<Json<Value>, ApiError> {
    let rows = sqlx::query(
        "SELECT admin_email, action, target, detail, created_at::text AS at FROM admin_audit ORDER BY id DESC LIMIT $1",
    )
    .bind(l.limit.unwrap_or(100).clamp(1, 500))
    .fetch_all(&st.db)
    .await?;
    Ok(Json(json!(rows
        .iter()
        .map(|r| json!({
            "admin": r.get::<String, _>("admin_email"),
            "action": r.get::<String, _>("action"),
            "target": r.get::<Option<String>, _>("target"),
            "detail": r.get::<Option<Value>, _>("detail"),
            "at": r.get::<String, _>("at"),
        }))
        .collect::<Vec<_>>())))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn emails_are_checked_and_lowered() {
        assert_eq!(clean_email(" Pm@Example.COM ").unwrap(), "pm@example.com");
        assert!(clean_email("nope").is_err());
        assert!(clean_email("a@b").is_err());
        assert!(clean_email("@b.com").is_err());
    }

    #[test]
    fn api_keys_are_never_editable() {
        assert!(editable("study_price_ask"));
        assert!(editable("study_credits_per_usd"));
        assert!(editable("primary_model"));
        assert!(!editable("stealthgpt_api_key"));
        assert!(!editable("beta_access_list"));
    }
}

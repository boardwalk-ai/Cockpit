//! The test app's phones, one row per install. The app reports here every
//! time it opens and whenever its push token or permission changes — also
//! when it *can't* get notifications (permission off, no token), with why —
//! so an admin sees each phone's real state: model, Android version, app
//! version, IP, last seen, and whether announcements can reach it.

use axum::extract::{Path, Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::Json;
use octo_common::access::email_of;
use octo_common::{ApiError, AuthedUser};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::{PgPool, Row};
use uuid::Uuid;

use crate::{Admin, AppState};

pub const SCHEMA: &str = r#"
CREATE TABLE IF NOT EXISTS app_devices (
    id            uuid PRIMARY KEY,              -- made once per install by the app
    firebase_uid  text,                          -- who is signed in on it (null: signed out)
    email         text,
    user_id       uuid,
    token         text UNIQUE,                   -- FCM token; null when there is none
    status        text NOT NULL,                 -- registered | permission_denied | token_error | signed_out
    error         text,
    platform      text NOT NULL,
    manufacturer  text,
    model         text,
    os_version    text,
    app_version   text,
    ip            text,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    last_seen     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS app_devices_user ON app_devices (user_id);
CREATE INDEX IF NOT EXISTS app_devices_email ON app_devices (lower(email));
"#;

const STATUSES: &[&str] = &["registered", "permission_denied", "token_error"];

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Report {
    id: Uuid,
    /// Null when the phone has none (see `status`).
    token: Option<String>,
    status: String,
    error: Option<String>,
    platform: String,
    manufacturer: Option<String>,
    model: Option<String>,
    os_version: Option<String>,
    app_version: Option<String>,
}

fn cut(s: Option<String>, n: usize) -> Option<String> {
    s.map(|s| s.trim().chars().take(n).collect::<String>()).filter(|s| !s.is_empty())
}

/// The caller's address as nginx saw it.
fn ip_of(headers: &HeaderMap) -> Option<String> {
    headers
        .get("x-forwarded-for")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.split(',').next())
        .or_else(|| headers.get("x-real-ip").and_then(|v| v.to_str().ok()))
        .map(|s| s.trim().chars().take(64).collect())
}

/// `PUT /v1/app/devices` — this install's state. The token belongs to this
/// install only (another row that had it loses it), and the install to
/// whoever is signed in now.
pub async fn report(
    State(st): State<AppState>,
    user: AuthedUser,
    headers: HeaderMap,
    Json(r): Json<Report>,
) -> Result<Json<Value>, ApiError> {
    if !STATUSES.contains(&r.status.as_str()) {
        return Err(ApiError::bad_request("unknown status"));
    }
    if !matches!(r.platform.as_str(), "android" | "ios") {
        return Err(ApiError::bad_request("unknown platform"));
    }
    let token = cut(r.token, 4096).filter(|_| r.status == "registered");
    if r.status == "registered" && token.is_none() {
        return Err(ApiError::bad_request("a registered phone needs its token"));
    }
    let email = email_of(&user);
    let user_id: Option<Uuid> = sqlx::query_scalar("SELECT id FROM users WHERE firebase_uid = $1")
        .bind(&user.uid)
        .fetch_optional(&st.db)
        .await?;
    let mut tx = st.db.begin().await?;
    if let Some(t) = &token {
        sqlx::query("UPDATE app_devices SET token = NULL, status = 'signed_out', updated_at = now() WHERE token = $1 AND id <> $2")
            .bind(t)
            .bind(r.id)
            .execute(&mut *tx)
            .await?;
    }
    sqlx::query(
        "INSERT INTO app_devices (id, firebase_uid, email, user_id, token, status, error, platform, manufacturer, model, os_version, app_version, ip) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13) \
         ON CONFLICT (id) DO UPDATE SET firebase_uid = EXCLUDED.firebase_uid, email = EXCLUDED.email, user_id = EXCLUDED.user_id, \
             token = EXCLUDED.token, status = EXCLUDED.status, error = EXCLUDED.error, platform = EXCLUDED.platform, \
             manufacturer = EXCLUDED.manufacturer, model = EXCLUDED.model, os_version = EXCLUDED.os_version, \
             app_version = EXCLUDED.app_version, ip = EXCLUDED.ip, updated_at = now(), last_seen = now()",
    )
    .bind(r.id)
    .bind(&user.uid)
    .bind(&email)
    .bind(user_id)
    .bind(&token)
    .bind(&r.status)
    .bind(cut(r.error, 500))
    .bind(&r.platform)
    .bind(cut(r.manufacturer, 80))
    .bind(cut(r.model, 80))
    .bind(cut(r.os_version, 40))
    .bind(cut(r.app_version, 40))
    .bind(ip_of(&headers))
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(Json(json!({ "id": r.id, "status": r.status, "registered": token.is_some() })))
}

/// `DELETE /v1/app/devices/{id}` — signing out: the phone stops getting
/// this account's announcements, and stays listed as signed out.
pub async fn signed_out(State(st): State<AppState>, user: AuthedUser, Path(id): Path<Uuid>) -> Result<StatusCode, ApiError> {
    sqlx::query(
        "UPDATE app_devices SET token = NULL, status = 'signed_out', firebase_uid = NULL, email = NULL, user_id = NULL, \
             error = NULL, updated_at = now() WHERE id = $1 AND firebase_uid = $2",
    )
    .bind(id)
    .bind(&user.uid)
    .execute(&st.db)
    .await?;
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Deserialize)]
pub struct Filter {
    email: Option<String>,
}

fn row_json(r: &sqlx::postgres::PgRow) -> Value {
    json!({
        "id": r.get::<Uuid, _>("id"),
        "email": r.get::<Option<String>, _>("email"),
        "status": r.get::<String, _>("status"),
        "error": r.get::<Option<String>, _>("error"),
        "platform": r.get::<String, _>("platform"),
        "manufacturer": r.get::<Option<String>, _>("manufacturer"),
        "model": r.get::<Option<String>, _>("model"),
        "osVersion": r.get::<Option<String>, _>("os_version"),
        "appVersion": r.get::<Option<String>, _>("app_version"),
        "ip": r.get::<Option<String>, _>("ip"),
        "createdAt": r.get::<String, _>("created"),
        "lastSeen": r.get::<String, _>("seen"),
    })
}

/// `GET /v1/admin/devices?email=` — phones, newest seen first.
pub async fn list(State(st): State<AppState>, _: Admin, Query(f): Query<Filter>) -> Result<Json<Value>, ApiError> {
    let email = f.email.map(|e| e.trim().to_lowercase()).filter(|e| !e.is_empty());
    let rows = sqlx::query(
        "SELECT *, created_at::text AS created, last_seen::text AS seen FROM app_devices \
         WHERE $1::text IS NULL OR lower(email) = $1 ORDER BY last_seen DESC LIMIT 300",
    )
    .bind(&email)
    .fetch_all(&st.db)
    .await?;
    Ok(Json(json!(rows.iter().map(row_json).collect::<Vec<_>>())))
}

/// Registered phones per email (for the Testers list).
pub async fn counts(db: &PgPool) -> std::collections::HashMap<String, (i64, i64)> {
    sqlx::query(
        "SELECT lower(email) AS e, count(*) FILTER (WHERE status = 'registered') AS ok, count(*) AS all \
         FROM app_devices WHERE email IS NOT NULL GROUP BY 1",
    )
    .fetch_all(db)
    .await
    .map(|rows| rows.iter().map(|r| (r.get("e"), (r.get("ok"), r.get("all")))).collect())
    .unwrap_or_default()
}

/// The tokens of these users' registered phones.
pub async fn tokens(db: &PgPool, users: &[Uuid]) -> Vec<String> {
    sqlx::query_scalar(
        "SELECT d.token FROM app_devices d LEFT JOIN users u ON u.firebase_uid = d.firebase_uid \
         WHERE d.status = 'registered' AND d.token IS NOT NULL AND (d.user_id = ANY($1) OR u.id = ANY($1))",
    )
    .bind(users)
    .fetch_all(db)
    .await
    .unwrap_or_default()
}

/// FCM says a token is dead: the phone needs to register again.
pub async fn token_dead(db: &PgPool, token: &str) {
    let _ = sqlx::query("UPDATE app_devices SET token = NULL, status = 'token_error', error = 'FCM: token no longer valid', updated_at = now() WHERE token = $1")
        .bind(token)
        .execute(db)
        .await;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ip_is_the_first_forwarded_address() {
        let mut h = HeaderMap::new();
        h.insert("x-forwarded-for", "49.229.209.215, 10.0.0.1".parse().unwrap());
        assert_eq!(ip_of(&h).as_deref(), Some("49.229.209.215"));
        let mut h = HeaderMap::new();
        h.insert("x-real-ip", "1.2.3.4".parse().unwrap());
        assert_eq!(ip_of(&h).as_deref(), Some("1.2.3.4"));
        assert_eq!(ip_of(&HeaderMap::new()), None);
    }
}

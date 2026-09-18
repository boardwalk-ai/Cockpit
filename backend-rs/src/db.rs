//! Shared-Postgres access. Keys and models live in the DB (not env), matching
//! the FastAPI side: `api_keys` holds the OpenRouter key(s); `system_settings`
//! holds model choices and the humanizer keys; `users` holds credits; `essays`
//! is the saved-document store.

use sqlx::postgres::PgPoolOptions;
use sqlx::{PgPool, Row};

use crate::error::ApiError;

pub async fn connect(url: &str) -> Result<PgPool, sqlx::Error> {
    PgPoolOptions::new()
        .max_connections(5)
        .acquire_timeout(std::time::Duration::from_secs(10))
        .connect(url)
        .await
}

/// An active OpenRouter API key (round-robins loosely by least-used).
pub async fn openrouter_key(pool: &PgPool) -> Result<String, ApiError> {
    let row = sqlx::query(
        "SELECT key FROM api_keys \
         WHERE provider ILIKE 'openrouter' AND is_active = true \
         ORDER BY usage_count ASC NULLS FIRST LIMIT 1",
    )
    .fetch_optional(pool)
    .await
    .map_err(db_err)?;
    match row {
        Some(r) => Ok(r.get::<String, _>("key")),
        None => Err(ApiError::new(
            axum::http::StatusCode::SERVICE_UNAVAILABLE,
            "no active OpenRouter key configured",
        )),
    }
}

/// A `system_settings` value by key.
pub async fn setting(pool: &PgPool, key: &str) -> Option<String> {
    sqlx::query("SELECT value FROM system_settings WHERE key = $1")
        .bind(key)
        .fetch_optional(pool)
        .await
        .ok()
        .flatten()
        .map(|r| r.get::<String, _>("value"))
}

/// The model to use for a role, falling back to a sensible default.
pub async fn model(pool: &PgPool, key: &str, default: &str) -> String {
    setting(pool, key)
        .await
        .filter(|s| !s.trim().is_empty())
        .unwrap_or_else(|| default.to_string())
}

// ── Users / credits ──────────────────────────────────────────────────────────
#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UserRow {
    pub id: String,
    pub email: Option<String>,
    pub name: Option<String>,
    pub photo_url: Option<String>,
    pub plan: Option<String>,
    pub word_credits: i32,
    pub source_credits: i32,
    pub humanizer_credits: i32,
    pub octo_credits: i32,
    pub is_admin: bool,
    pub has_completed_wizard: bool,
}

/// Looks up a user by Firebase UID (the account the ID token belongs to).
pub async fn user_by_firebase_uid(
    pool: &PgPool,
    uid: &str,
) -> Result<Option<UserRow>, ApiError> {
    let row = sqlx::query(
        "SELECT id::text AS id, email, name, photo_url, plan, \
                COALESCE(word_credits,0) AS word_credits, \
                COALESCE(source_credits,0) AS source_credits, \
                COALESCE(humanizer_credits,0) AS humanizer_credits, \
                COALESCE(octo_credits,0) AS octo_credits, \
                COALESCE(is_admin,false) AS is_admin, \
                COALESCE(has_completed_wizard,false) AS has_completed_wizard \
         FROM users WHERE firebase_uid = $1",
    )
    .bind(uid)
    .fetch_optional(pool)
    .await
    .map_err(db_err)?;

    Ok(row.map(|r| UserRow {
        id: r.get("id"),
        email: r.get("email"),
        name: r.get("name"),
        photo_url: r.get("photo_url"),
        plan: r.get("plan"),
        word_credits: r.get("word_credits"),
        source_credits: r.get("source_credits"),
        humanizer_credits: r.get("humanizer_credits"),
        octo_credits: r.get("octo_credits"),
        is_admin: r.get("is_admin"),
        has_completed_wizard: r.get("has_completed_wizard"),
    }))
}

pub fn db_err(e: sqlx::Error) -> ApiError {
    ApiError::new(
        axum::http::StatusCode::INTERNAL_SERVER_ERROR,
        format!("database error: {e}"),
    )
}

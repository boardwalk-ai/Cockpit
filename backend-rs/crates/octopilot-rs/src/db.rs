//! Shared-Postgres access. Keys and models live in the DB (not env), matching
//! the FastAPI side: `api_keys` holds the OpenRouter key(s); `system_settings`
//! holds model choices and the humanizer keys; `users` holds credits; `essays`
//! is the saved-document store.

use sqlx::{PgPool, Row};

use crate::error::ApiError;

pub async fn connect(url: &str) -> Result<PgPool, sqlx::Error> {
    octo_common::db::connect(url, 5).await
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
    ?;
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
// Identity lives in `octo-common` (shared with octonotes-api).
pub use octo_common::error::db_err;
pub use octo_common::identity::user_by_firebase_uid;

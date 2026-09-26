//! `Idempotency-Key` support: the first response for a (user, key) is stored and
//! replayed on retries, so a create/finalize/charge happens at most once.

use axum::http::{HeaderMap, StatusCode};
use octo_common::ApiError;
use serde::Serialize;
use serde_json::Value;
use sqlx::PgPool;
use uuid::Uuid;

pub fn key(headers: &HeaderMap) -> Option<String> {
    headers
        .get("idempotency-key")
        .and_then(|v| v.to_str().ok())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty() && s.len() <= 200)
}

/// A stable hash of the request body, so a key reused with a different body is
/// rejected instead of silently replaying the wrong response.
pub fn hash(body: &impl Serialize) -> String {
    let bytes = serde_json::to_vec(body).unwrap_or_default();
    // FNV-1a 64 — collision resistance is not a security property here.
    let mut h: u64 = 0xcbf29ce484222325;
    for b in bytes {
        h ^= b as u64;
        h = h.wrapping_mul(0x100000001b3);
    }
    format!("{h:016x}")
}

/// The stored response for this key, if any. Errors with 422 when the key was
/// used for a different request body.
pub async fn replay(pool: &PgPool, user_id: Uuid, key: &str, request_hash: &str) -> Result<Option<(StatusCode, Value)>, ApiError> {
    let row: Option<(String, Option<i32>, Option<Value>)> = sqlx::query_as(
        "SELECT request_hash, status_code, response FROM idempotency_keys WHERE user_id = $1 AND key = $2",
    )
    .bind(user_id)
    .bind(key)
    .fetch_optional(pool)
    .await?;
    match row {
        None => Ok(None),
        Some((h, _, _)) if h != request_hash => Err(ApiError::new(
            StatusCode::UNPROCESSABLE_ENTITY,
            "Idempotency-Key was already used with a different request",
        )
        .with_code("idempotency_mismatch")),
        Some((_, Some(code), Some(resp))) => Ok(Some((
            StatusCode::from_u16(code as u16).unwrap_or(StatusCode::OK),
            resp,
        ))),
        // Reserved but not finished (a concurrent first attempt).
        Some(_) => Err(ApiError::new(StatusCode::CONFLICT, "request with this Idempotency-Key is in progress")
            .with_code("idempotency_in_progress")),
    }
}

pub async fn store(pool: &PgPool, user_id: Uuid, key: &str, request_hash: &str, status: StatusCode, response: &Value) -> Result<(), ApiError> {
    sqlx::query(
        "INSERT INTO idempotency_keys (user_id, key, request_hash, status_code, response) VALUES ($1, $2, $3, $4, $5) \
         ON CONFLICT (user_id, key) DO NOTHING",
    )
    .bind(user_id)
    .bind(key)
    .bind(request_hash)
    .bind(status.as_u16() as i32)
    .bind(response)
    .execute(pool)
    .await?;
    Ok(())
}

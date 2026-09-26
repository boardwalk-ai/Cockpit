//! The user's devices (Panel 12 / Panel 4).

use axum::extract::State;
use axum::Json;
use chrono::{DateTime, Utc};
use octo_common::ApiError;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::ctx::Caller;
use crate::AppState;

const PLATFORMS: &[&str] = &["web", "android", "ios", "macos", "windows", "linux"];

#[derive(Debug, Serialize, sqlx::FromRow, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct Device {
    pub id: Uuid,
    pub name: String,
    pub platform: String,
    pub last_seen_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct RegisterDevice {
    /// Client-generated and stored on the device; re-registering updates it.
    pub id: Uuid,
    pub name: String,
    pub platform: String,
    pub push_token: Option<String>,
}

#[utoipa::path(post, path = "/v1/devices", tag = "devices", request_body = RegisterDevice,
    responses((status = 200, body = Device)))]
pub async fn register(State(st): State<AppState>, caller: Caller, Json(req): Json<RegisterDevice>) -> Result<Json<Device>, ApiError> {
    if !PLATFORMS.contains(&req.platform.as_str()) {
        return Err(ApiError::bad_request("unknown platform"));
    }
    let name = req.name.trim();
    if name.is_empty() || name.chars().count() > 80 {
        return Err(ApiError::bad_request("name must be 1..80 chars"));
    }
    let row = sqlx::query_as::<_, Device>(
        "INSERT INTO devices (id, user_id, name, platform, push_token, last_seen_at) VALUES ($1, $2, $3, $4, $5, now()) \
         ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, platform = EXCLUDED.platform, \
             push_token = COALESCE(EXCLUDED.push_token, devices.push_token), last_seen_at = now() \
         WHERE devices.user_id = EXCLUDED.user_id \
         RETURNING id, name, platform, last_seen_at, created_at",
    )
    .bind(req.id)
    .bind(caller.user_id)
    .bind(name)
    .bind(&req.platform)
    .bind(&req.push_token)
    .fetch_optional(&st.notes)
    .await?;
    // No row = the id belongs to another user's device.
    row.map(Json).ok_or_else(|| ApiError::bad_request("device id already in use"))
}

#[utoipa::path(get, path = "/v1/devices", tag = "devices", responses((status = 200, body = Vec<Device>)))]
pub async fn list(State(st): State<AppState>, caller: Caller) -> Result<Json<Vec<Device>>, ApiError> {
    let rows = sqlx::query_as::<_, Device>(
        "SELECT id, name, platform, last_seen_at, created_at FROM devices WHERE user_id = $1 ORDER BY last_seen_at DESC NULLS LAST",
    )
    .bind(caller.user_id)
    .fetch_all(&st.notes)
    .await?;
    Ok(Json(rows))
}

/// The caller's device, or 400 (used wherever a request names a device).
pub async fn ensure_owned(conn: &mut sqlx::PgConnection, caller: &Caller, device_id: Uuid) -> Result<(), ApiError> {
    let ok: Option<Uuid> = sqlx::query_scalar("SELECT id FROM devices WHERE id = $1 AND user_id = $2")
        .bind(device_id)
        .bind(caller.user_id)
        .fetch_optional(conn)
        .await?;
    ok.map(|_| ()).ok_or_else(|| ApiError::bad_request("unknown deviceId — register it with POST /v1/devices"))
}

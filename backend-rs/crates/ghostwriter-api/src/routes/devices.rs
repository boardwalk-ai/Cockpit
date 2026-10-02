//! The phones that get a user's push notifications.

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;
use octo_common::ApiError;
use serde::Deserialize;
use uuid::Uuid;

use super::clean_text;
use crate::ctx::Caller;
use crate::AppState;

#[derive(Deserialize)]
pub struct PutDevice {
    /// The FCM registration token.
    pub token: Option<String>,
    /// `android`, `ios` or `web`.
    pub platform: Option<String>,
}

/// `PUT /v1/devices/:id` — register this install for push, or refresh its
/// token. `id` is made once by the app and kept for the life of the install.
/// Whoever is signed in on the install owns it: signing in as someone else
/// moves the device to them.
pub async fn put(
    State(st): State<AppState>,
    caller: Caller,
    Path(id): Path<Uuid>,
    Json(body): Json<PutDevice>,
) -> Result<StatusCode, ApiError> {
    let token = clean_text(body.token, 4096, "token")?
        .ok_or_else(|| ApiError::bad_request("token is required"))?;
    let platform = body.platform.unwrap_or_default();
    if !matches!(platform.as_str(), "android" | "ios" | "web") {
        return Err(ApiError::bad_request(
            "platform must be android, ios or web",
        ));
    }

    let mut tx = st.db.begin().await?;
    // A token belongs to one install: a reinstall gets a new id but may be
    // handed the same token.
    sqlx::query("DELETE FROM devices WHERE token = $1 AND id <> $2")
        .bind(&token)
        .bind(id)
        .execute(&mut *tx)
        .await?;
    sqlx::query(
        "INSERT INTO devices (id, user_id, token, platform) VALUES ($1, $2, $3, $4) \
         ON CONFLICT (id) DO UPDATE SET user_id = EXCLUDED.user_id, token = EXCLUDED.token, \
             platform = EXCLUDED.platform, updated_at = now()",
    )
    .bind(id)
    .bind(caller.user_id)
    .bind(&token)
    .bind(&platform)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

/// `DELETE /v1/devices/:id` — stop pushing to this install (sign-out).
/// Deleting one that is not there is not an error.
pub async fn remove(
    State(st): State<AppState>,
    caller: Caller,
    Path(id): Path<Uuid>,
) -> Result<StatusCode, ApiError> {
    sqlx::query("DELETE FROM devices WHERE id = $1 AND user_id = $2")
        .bind(id)
        .bind(caller.user_id)
        .execute(&st.db)
        .await?;
    Ok(StatusCode::NO_CONTENT)
}

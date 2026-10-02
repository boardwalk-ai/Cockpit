//! Folders group a user's projects in the sidebar.

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{DateTime, Utc};
use octo_common::ApiError;
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use uuid::Uuid;

use super::clean_text;
use crate::ctx::Caller;
use crate::AppState;

#[derive(Serialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
pub struct Folder {
    pub id: Uuid,
    pub name: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Deserialize)]
pub struct PutFolder {
    pub name: Option<String>,
}

/// The user's folders, oldest first (the order they were made in).
pub async fn for_user(db: &PgPool, user_id: Uuid) -> Result<Vec<Folder>, ApiError> {
    Ok(sqlx::query_as(
        "SELECT id, name, created_at FROM folders WHERE user_id = $1 ORDER BY created_at, id",
    )
    .bind(user_id)
    .fetch_all(db)
    .await?)
}

/// True when `folder_id` exists and belongs to `user_id`.
pub async fn owned(db: &PgPool, user_id: Uuid, folder_id: Uuid) -> Result<bool, ApiError> {
    Ok(
        sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM folders WHERE id = $1 AND user_id = $2)")
            .bind(folder_id)
            .bind(user_id)
            .fetch_one(db)
            .await?,
    )
}

/// `PUT /v1/folders/:id` — create the folder, or rename it if it exists.
pub async fn put(
    State(st): State<AppState>,
    caller: Caller,
    Path(id): Path<Uuid>,
    Json(body): Json<PutFolder>,
) -> Result<Json<Folder>, ApiError> {
    let name = clean_text(body.name, 80, "name")?
        .ok_or_else(|| ApiError::bad_request("name is required"))?;

    // The WHERE on the update keeps another user's folder with the same id
    // from being renamed: no row comes back, which reads as "not found".
    let folder: Option<Folder> = sqlx::query_as(
        "INSERT INTO folders (id, user_id, name) VALUES ($1, $2, $3) \
         ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name \
             WHERE folders.user_id = EXCLUDED.user_id \
         RETURNING id, name, created_at",
    )
    .bind(id)
    .bind(caller.user_id)
    .bind(&name)
    .fetch_optional(&st.db)
    .await?;

    folder
        .map(Json)
        .ok_or_else(|| ApiError::not_found("folder not found"))
}

/// `DELETE /v1/folders/:id` — the folder goes; its projects stay, unfiled.
pub async fn remove(
    State(st): State<AppState>,
    caller: Caller,
    Path(id): Path<Uuid>,
) -> Result<StatusCode, ApiError> {
    let deleted = sqlx::query("DELETE FROM folders WHERE id = $1 AND user_id = $2")
        .bind(id)
        .bind(caller.user_id)
        .execute(&st.db)
        .await?
        .rows_affected();
    if deleted == 0 {
        return Err(ApiError::not_found("folder not found"));
    }
    Ok(StatusCode::NO_CONTENT)
}

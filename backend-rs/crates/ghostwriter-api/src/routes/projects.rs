//! Projects — one essay each: its brief, its document, its runs.
//!
//! Saving follows Doc Oct: the client picks the id up front, so the first save
//! is an idempotent upsert and a retried or overlapping save cannot create a
//! second copy.

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{DateTime, Utc};
use octo_common::ApiError;
use serde::{Deserialize, Deserializer, Serialize};
use serde_json::{json, Value};
use uuid::Uuid;

use super::{clean_text, folders, runs};
use crate::ctx::Caller;
use crate::AppState;

const COLUMNS: &str = "id, folder_id, title, instruction, status, target_words, word_count, \
                       created_at, updated_at";

#[derive(Serialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
pub struct Project {
    pub id: Uuid,
    pub folder_id: Option<Uuid>,
    pub title: String,
    pub instruction: String,
    pub status: String,
    pub target_words: Option<i32>,
    pub word_count: i32,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PutProject {
    pub title: Option<String>,
    pub instruction: Option<String>,
    /// Absent ⇒ leave the folder alone; `null` ⇒ unfile; an id ⇒ move there.
    #[serde(default, deserialize_with = "present")]
    pub folder_id: Option<Option<Uuid>>,
}

/// Tells a field that was sent as `null` apart from one that was not sent.
fn present<'de, T, D>(deserializer: D) -> Result<Option<Option<T>>, D::Error>
where
    T: Deserialize<'de>,
    D: Deserializer<'de>,
{
    Option::<T>::deserialize(deserializer).map(Some)
}

/// `GET /v1/projects` — the user's projects (newest first) and folders.
pub async fn list(State(st): State<AppState>, caller: Caller) -> Result<Json<Value>, ApiError> {
    let projects: Vec<Project> = sqlx::query_as(&format!(
        "SELECT {COLUMNS} FROM projects WHERE user_id = $1 ORDER BY updated_at DESC, id"
    ))
    .bind(caller.user_id)
    .fetch_all(&st.db)
    .await?;
    let folders = folders::for_user(&st.db, caller.user_id).await?;

    Ok(Json(json!({ "projects": projects, "folders": folders })))
}

/// `PUT /v1/projects/:id` — create the project, or update the fields sent.
pub async fn put(
    State(st): State<AppState>,
    caller: Caller,
    Path(id): Path<Uuid>,
    Json(body): Json<PutProject>,
) -> Result<Json<Project>, ApiError> {
    let title = clean_text(body.title, 200, "title")?;
    let instruction = clean_text(body.instruction, 20_000, "instruction")?;

    let folder_sent = body.folder_id.is_some();
    let folder_id = body.folder_id.flatten();
    if let Some(folder_id) = folder_id {
        if !folders::owned(&st.db, caller.user_id, folder_id).await? {
            return Err(ApiError::not_found("folder not found"));
        }
    }

    let mut tx = st.db.begin().await?;

    // The WHERE on the update keeps another user's project with the same id
    // from being overwritten: no row comes back, which reads as "not found".
    let project: Option<Project> = sqlx::query_as(&format!(
        "INSERT INTO projects (id, user_id, title, instruction, folder_id) \
         VALUES ($1, $2, COALESCE($3, 'Untitled essay'), COALESCE($4, ''), $5) \
         ON CONFLICT (id) DO UPDATE SET \
             title = COALESCE($3, projects.title), \
             instruction = COALESCE($4, projects.instruction), \
             folder_id = CASE WHEN $6 THEN $5 ELSE projects.folder_id END, \
             updated_at = now() \
             WHERE projects.user_id = $2 \
         RETURNING {COLUMNS}"
    ))
    .bind(id)
    .bind(caller.user_id)
    .bind(&title)
    .bind(&instruction)
    .bind(folder_id)
    .bind(folder_sent)
    .fetch_optional(&mut *tx)
    .await?;
    let project = project.ok_or_else(|| ApiError::not_found("project not found"))?;

    // Every project has exactly one document from the moment it exists.
    sqlx::query("INSERT INTO documents (project_id) VALUES ($1) ON CONFLICT DO NOTHING")
        .bind(id)
        .execute(&mut *tx)
        .await?;

    tx.commit().await?;
    Ok(Json(project))
}

/// `GET /v1/projects/:id` — one project, with `activeRunId` when a run is
/// still going so the app can reconnect to it.
pub async fn get_one(
    State(st): State<AppState>,
    caller: Caller,
    Path(id): Path<Uuid>,
) -> Result<Json<Value>, ApiError> {
    let project: Option<Project> = sqlx::query_as(&format!(
        "SELECT {COLUMNS} FROM projects WHERE id = $1 AND user_id = $2"
    ))
    .bind(id)
    .bind(caller.user_id)
    .fetch_optional(&st.db)
    .await?;
    let project = project.ok_or_else(|| ApiError::not_found("project not found"))?;

    let active_run = runs::active_run_id(&st, id).await?;

    let mut value = serde_json::to_value(project).map_err(|_| ApiError::internal("encode"))?;
    value["activeRunId"] = json!(active_run);
    Ok(Json(value))
}

/// `DELETE /v1/projects/:id` — the project and everything under it.
pub async fn remove(
    State(st): State<AppState>,
    caller: Caller,
    Path(id): Path<Uuid>,
) -> Result<StatusCode, ApiError> {
    let deleted = sqlx::query("DELETE FROM projects WHERE id = $1 AND user_id = $2")
        .bind(id)
        .bind(caller.user_id)
        .execute(&st.db)
        .await?
        .rows_affected();
    if deleted == 0 {
        return Err(ApiError::not_found("project not found"));
    }
    Ok(StatusCode::NO_CONTENT)
}

/// `GET /v1/projects/:id/document` — the project's document as it stands.
/// `locked` is true while a run is writing it.
pub async fn document(
    State(st): State<AppState>,
    caller: Caller,
    Path(id): Path<Uuid>,
) -> Result<Json<Value>, ApiError> {
    let document: Option<Value> = sqlx::query_scalar(
        "SELECT jsonb_build_object(             'rev', d.rev, 'style', d.style, 'title', d.title, 'fields', d.fields,              'body', d.body, 'delta', d.delta, 'bibliography', d.bibliography,              'sources', d.sources, 'locked', d.locked_by_run IS NOT NULL,              'wordCount', p.word_count, 'updatedAt', d.updated_at)          FROM documents d JOIN projects p ON p.id = d.project_id          WHERE d.project_id = $1 AND p.user_id = $2",
    )
    .bind(id)
    .bind(caller.user_id)
    .fetch_optional(&st.db)
    .await?;
    document
        .map(Json)
        .ok_or_else(|| ApiError::not_found("project not found"))
}

//! Saved documents — the `documents` table (the canonical saved-project store,
//! shared with the web app), scoped to the authed user (Firebase UID →
//! `users.id`). `state` (JSONB) holds the full serialized editor document.

use axum::extract::{Path, State};
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::Row;

use crate::auth::AuthedUser;
use crate::db::{self, db_err};
use crate::error::ApiError;
use crate::AppState;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Essay {
    pub id: String,
    pub title: String,
    pub content: String,
    pub word_count: i32,
    pub citation_style: Option<String>,
    pub updated_at: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EssaySummary {
    pub id: String,
    pub title: String,
    pub word_count: i32,
    pub citation_style: Option<String>,
    pub updated_at: Option<String>,
    pub snippet: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SaveBody {
    pub id: Option<String>,
    pub title: String,
    pub content: String,
    #[serde(default)]
    pub word_count: i32,
    pub citation_style: Option<String>,
}

/// Resolves the authed user's `users.id`, or 404 if they have no row yet.
async fn user_id(st: &AppState, user: &AuthedUser) -> Result<String, ApiError> {
    db::user_by_firebase_uid(&st.db, &user.uid)
        .await?
        .map(|u| u.id)
        .ok_or_else(|| ApiError::not_found("no account for this user"))
}

/// GET /v1/essays — the user's saved documents (newest first).
pub async fn list(
    State(st): State<AppState>,
    user: AuthedUser,
) -> Result<Json<Vec<EssaySummary>>, ApiError> {
    let uid = user_id(&st, &user).await?;
    let rows = sqlx::query(
        "SELECT id::text AS id, title, COALESCE(word_count,0) AS word_count, \
                format_style AS citation_style, updated_at::text AS updated_at, \
                COALESCE(preview,'') AS snippet \
         FROM documents WHERE user_id = $1::uuid ORDER BY updated_at DESC NULLS LAST \
         LIMIT 100",
    )
    .bind(&uid)
    .fetch_all(&st.db)
    .await
    .map_err(db_err)?;

    let out = rows
        .into_iter()
        .map(|r| EssaySummary {
            id: r.get("id"),
            title: r.get("title"),
            word_count: r.get("word_count"),
            citation_style: r.get("citation_style"),
            updated_at: r.get("updated_at"),
            snippet: r.get::<String, _>("snippet"),
        })
        .collect();
    Ok(Json(out))
}

/// GET /v1/essays/:id — one document (must belong to the user).
pub async fn get_one(
    State(st): State<AppState>,
    user: AuthedUser,
    Path(id): Path<String>,
) -> Result<Json<Essay>, ApiError> {
    let uid = user_id(&st, &user).await?;
    let row = sqlx::query(
        "SELECT id::text AS id, title, COALESCE(state::text,'') AS content, \
                COALESCE(word_count,0) AS word_count, format_style AS citation_style, \
                updated_at::text AS updated_at \
         FROM documents WHERE id = $1::uuid AND user_id = $2::uuid",
    )
    .bind(&id)
    .bind(&uid)
    .fetch_optional(&st.db)
    .await
    .map_err(db_err)?
    .ok_or_else(|| ApiError::not_found("document not found"))?;

    Ok(Json(Essay {
        id: row.get("id"),
        title: row.get("title"),
        content: row.get("content"),
        word_count: row.get("word_count"),
        citation_style: row.get("citation_style"),
        updated_at: row.get("updated_at"),
    }))
}

/// POST /v1/essays — create or update (when `id` is supplied) a document.
pub async fn save(
    State(st): State<AppState>,
    user: AuthedUser,
    Json(body): Json<SaveBody>,
) -> Result<Json<Essay>, ApiError> {
    let uid = user_id(&st, &user).await?;
    let title = if body.title.trim().is_empty() {
        "Untitled document".to_string()
    } else {
        body.title.trim().to_string()
    };

    let row = match body.id {
        Some(id) => sqlx::query(
            "UPDATE documents SET title=$1, format_style=$2, word_count=$3, \
                    preview=left(COALESCE($4::jsonb->>'body',''),200), \
                    state=$4::jsonb, updated_at=now() \
             WHERE id=$5::uuid AND user_id=$6::uuid \
             RETURNING id::text AS id, title, COALESCE(state::text,'') AS content, \
                    COALESCE(word_count,0) AS word_count, format_style AS citation_style, \
                    updated_at::text AS updated_at",
        )
        .bind(&title)
        .bind(&body.citation_style)
        .bind(body.word_count)
        .bind(&body.content)
        .bind(&id)
        .bind(&uid)
        .fetch_optional(&st.db)
        .await
        .map_err(db_err)?
        .ok_or_else(|| ApiError::not_found("document not found"))?,
        None => sqlx::query(
            "INSERT INTO documents (id, user_id, title, format_style, word_count, \
                    preview, state, created_at, updated_at) \
             VALUES (gen_random_uuid(), $1::uuid, $2, $3, $4, \
                    left(COALESCE($5::jsonb->>'body',''),200), $5::jsonb, now(), now()) \
             RETURNING id::text AS id, title, COALESCE(state::text,'') AS content, \
                    COALESCE(word_count,0) AS word_count, format_style AS citation_style, \
                    updated_at::text AS updated_at",
        )
        .bind(&uid)
        .bind(&title)
        .bind(&body.citation_style)
        .bind(body.word_count)
        .bind(&body.content)
        .fetch_one(&st.db)
        .await
        .map_err(db_err)?,
    };

    Ok(Json(Essay {
        id: row.get("id"),
        title: row.get("title"),
        content: row.get("content"),
        word_count: row.get("word_count"),
        citation_style: row.get("citation_style"),
        updated_at: row.get("updated_at"),
    }))
}

/// DELETE /v1/essays/:id
pub async fn remove(
    State(st): State<AppState>,
    user: AuthedUser,
    Path(id): Path<String>,
) -> Result<Json<serde_json::Value>, ApiError> {
    let uid = user_id(&st, &user).await?;
    let res = sqlx::query("DELETE FROM documents WHERE id=$1::uuid AND user_id=$2::uuid")
        .bind(&id)
        .bind(&uid)
        .execute(&st.db)
        .await
        .map_err(db_err)?;
    Ok(Json(serde_json::json!({ "deleted": res.rows_affected() })))
}

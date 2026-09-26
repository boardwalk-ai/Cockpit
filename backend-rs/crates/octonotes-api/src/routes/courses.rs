//! Courses (Home filters, New Session picker).

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{DateTime, Utc};
use octo_common::ApiError;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::ctx::Caller;
use crate::AppState;

#[derive(Debug, Serialize, sqlx::FromRow, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct Course {
    pub id: Uuid,
    pub name: String,
    pub code: Option<String>,
    pub color: Option<String>,
    pub studio_id: Option<Uuid>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

const COLUMNS: &str = "id, name, code, color, studio_id, created_at, updated_at";

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct CourseInput {
    pub name: Option<String>,
    pub code: Option<String>,
    /// `#RRGGBB` or `#AARRGGBB`.
    pub color: Option<String>,
    pub studio_id: Option<Uuid>,
}

fn validate(input: &CourseInput) -> Result<(), ApiError> {
    if let Some(n) = &input.name {
        if n.trim().is_empty() || n.chars().count() > 120 {
            return Err(ApiError::bad_request("name must be 1..120 chars"));
        }
    }
    if let Some(c) = &input.color {
        let hex = c.strip_prefix('#').unwrap_or("");
        if !(hex.len() == 6 || hex.len() == 8) || !hex.chars().all(|ch| ch.is_ascii_hexdigit()) {
            return Err(ApiError::bad_request("color must be #RRGGBB or #AARRGGBB"));
        }
    }
    Ok(())
}

fn map_unique(e: sqlx::Error) -> ApiError {
    if let sqlx::Error::Database(db) = &e {
        if db.is_unique_violation() {
            return ApiError::new(StatusCode::CONFLICT, "a course with this name already exists").with_code("course_exists");
        }
    }
    e.into()
}

#[utoipa::path(get, path = "/v1/courses", tag = "courses", responses((status = 200, body = Vec<Course>)))]
pub async fn list(State(st): State<AppState>, caller: Caller) -> Result<Json<Vec<Course>>, ApiError> {
    let rows = sqlx::query_as::<_, Course>(&format!(
        "SELECT {COLUMNS} FROM courses WHERE user_id = $1 AND deleted_at IS NULL ORDER BY lower(name)"
    ))
    .bind(caller.user_id)
    .fetch_all(&st.notes)
    .await?;
    Ok(Json(rows))
}

#[utoipa::path(post, path = "/v1/courses", tag = "courses", request_body = CourseInput,
    responses((status = 201, body = Course)))]
pub async fn create(State(st): State<AppState>, caller: Caller, Json(req): Json<CourseInput>) -> Result<(StatusCode, Json<Course>), ApiError> {
    validate(&req)?;
    let name = req.name.as_deref().map(str::trim).filter(|n| !n.is_empty()).ok_or_else(|| ApiError::bad_request("name is required"))?;
    let row = sqlx::query_as::<_, Course>(&format!(
        "INSERT INTO courses (user_id, name, code, color, studio_id) VALUES ($1, $2, $3, $4, $5) RETURNING {COLUMNS}"
    ))
    .bind(caller.user_id)
    .bind(name)
    .bind(&req.code)
    .bind(&req.color)
    .bind(req.studio_id)
    .fetch_one(&st.notes)
    .await
    .map_err(map_unique)?;
    Ok((StatusCode::CREATED, Json(row)))
}

#[utoipa::path(patch, path = "/v1/courses/{id}", tag = "courses", params(("id" = Uuid, Path)),
    request_body = CourseInput, responses((status = 200, body = Course)))]
pub async fn update(State(st): State<AppState>, caller: Caller, Path(id): Path<Uuid>, Json(req): Json<CourseInput>) -> Result<Json<Course>, ApiError> {
    validate(&req)?;
    let row = sqlx::query_as::<_, Course>(&format!(
        "UPDATE courses SET name = COALESCE($3, name), code = COALESCE($4, code), color = COALESCE($5, color), \
             studio_id = COALESCE($6, studio_id) \
         WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL RETURNING {COLUMNS}"
    ))
    .bind(id)
    .bind(caller.user_id)
    .bind(req.name.as_deref().map(str::trim))
    .bind(&req.code)
    .bind(&req.color)
    .bind(req.studio_id)
    .fetch_optional(&st.notes)
    .await
    .map_err(map_unique)?;
    row.map(Json).ok_or_else(|| ApiError::not_found("course not found"))
}

#[utoipa::path(delete, path = "/v1/courses/{id}", tag = "courses", params(("id" = Uuid, Path)),
    responses((status = 204)))]
pub async fn delete(State(st): State<AppState>, caller: Caller, Path(id): Path<Uuid>) -> Result<StatusCode, ApiError> {
    let res = sqlx::query("UPDATE courses SET deleted_at = now() WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL")
        .bind(id)
        .bind(caller.user_id)
        .execute(&st.notes)
        .await?;
    if res.rows_affected() == 0 {
        return Err(ApiError::not_found("course not found"));
    }
    Ok(StatusCode::NO_CONTENT)
}

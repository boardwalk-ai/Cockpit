//! Uploads: `POST /studios/{id}/documents` (multipart `file`, JSON job back,
//! as the Python route), `GET /studios/{id}/documents`, and
//! `GET /studios/{id}/build/{job}` — the ingest job's progress as SSE until
//! it is done or failed.

use std::convert::Infallible;
use std::time::Duration;

use axum::extract::{Multipart, Path, State};
use axum::http::StatusCode;
use axum::response::sse::{Event, KeepAlive, Sse};
use axum::Json;
use chrono::{DateTime, Utc};
use futures::Stream;
use octo_common::error::ApiError;
use serde::Serialize;
use serde_json::json;
use sqlx::Row;
use uuid::Uuid;

use crate::identity::UserId;
use crate::progress::owned_studio;
use crate::sse;
use crate::storage::key_for;
use crate::AppState;

#[derive(Serialize)]
pub struct JobOut {
    id: Uuid,
    document_id: Uuid,
    status: String,
    chunks_written: i32,
    error: Option<String>,
    created_at: DateTime<Utc>,
}

#[derive(Serialize)]
pub struct DocumentOut {
    id: Uuid,
    studio_id: Uuid,
    filename: String,
    mime: String,
    bytes: i32,
    status: String,
    created_at: DateTime<Utc>,
}

/// A filename safe for an object key: no folders, no control characters.
fn clean_name(name: &str) -> String {
    let base = name.rsplit(['/', '\\']).next().unwrap_or("");
    let s: String = base.chars().filter(|c| !c.is_control()).take(200).collect();
    let s = s.trim().to_string();
    if s.is_empty() || s == "." || s == ".." {
        "upload.bin".into()
    } else {
        s
    }
}

pub async fn upload(
    State(state): State<AppState>,
    UserId(user): UserId,
    Path(studio): Path<String>,
    mut form: Multipart,
) -> Result<(StatusCode, Json<JobOut>), ApiError> {
    let sid = owned_studio(&state.cockpit, &studio, user)
        .await
        .ok_or_else(|| ApiError::not_found("Studio not found"))?;
    let store = state.store.as_ref().ok_or_else(|| ApiError::unavailable("Uploads are off"))?;
    let max = state.config.max_upload_mb * 1024 * 1024;

    let mut file: Option<(String, String, Vec<u8>)> = None;
    while let Some(field) = form.next_field().await.map_err(|e| ApiError::bad_request(e.to_string()))? {
        if field.name() != Some("file") {
            continue;
        }
        let name = clean_name(field.file_name().unwrap_or("upload.bin"));
        let mime = field.content_type().unwrap_or("application/octet-stream").to_string();
        let bytes = field.bytes().await.map_err(|e| ApiError::bad_request(e.to_string()))?;
        if bytes.len() > max {
            return Err(ApiError::new(
                StatusCode::PAYLOAD_TOO_LARGE,
                format!("Files can be up to {} MB.", state.config.max_upload_mb),
            ));
        }
        file = Some((name, mime, bytes.to_vec()));
        break;
    }
    let (name, mime, bytes) = file.ok_or_else(|| ApiError::bad_request("No file"))?;
    if bytes.is_empty() {
        return Err(ApiError::bad_request("The file is empty."));
    }

    let doc = Uuid::new_v4();
    let key = key_for(user, doc, &name);
    store.put(&key, &bytes, &mime).await.map_err(ApiError::bad_gateway)?;

    let mut tx = state.cockpit.begin().await?;
    sqlx::query(
        "INSERT INTO documents (id, studio_id, user_id, filename, mime, bytes, object_key, status) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, 'uploaded')",
    )
    .bind(doc)
    .bind(sid)
    .bind(user)
    .bind(&name)
    .bind(&mime)
    .bind(bytes.len() as i32)
    .bind(&key)
    .execute(&mut *tx)
    .await?;
    let job = Uuid::new_v4();
    let created: DateTime<Utc> = sqlx::query_scalar(
        "INSERT INTO ingest_jobs (id, document_id, user_id, status, chunks_written) \
         VALUES ($1, $2, $3, 'queued', 0) RETURNING created_at",
    )
    .bind(job)
    .bind(doc)
    .bind(user)
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;
    state.jobs.notify_one();

    Ok((
        StatusCode::ACCEPTED,
        Json(JobOut {
            id: job,
            document_id: doc,
            status: "queued".into(),
            chunks_written: 0,
            error: None,
            created_at: created,
        }),
    ))
}

pub async fn list(
    State(state): State<AppState>,
    UserId(user): UserId,
    Path(studio): Path<String>,
) -> Result<Json<Vec<DocumentOut>>, ApiError> {
    let sid = Uuid::parse_str(&studio).map_err(|_| ApiError::not_found("Studio not found"))?;
    let rows = sqlx::query(
        "SELECT id, studio_id, filename, mime, bytes, status, created_at FROM documents \
         WHERE studio_id = $1 AND user_id = $2 ORDER BY created_at DESC",
    )
    .bind(sid)
    .bind(user)
    .fetch_all(&state.cockpit)
    .await?;
    Ok(Json(
        rows.iter()
            .map(|r| DocumentOut {
                id: r.get("id"),
                studio_id: r.get("studio_id"),
                filename: r.get("filename"),
                mime: r.get("mime"),
                bytes: r.get("bytes"),
                status: r.get("status"),
                created_at: r.get("created_at"),
            })
            .collect(),
    ))
}

/// `GET /studios/{id}/build/{job}` — `progress` on each change, then `done`
/// (or `error`). Polls with a short-lived query each time (no connection is
/// held for the life of the stream). Gives up after ~5 minutes.
pub async fn progress(
    State(state): State<AppState>,
    UserId(user): UserId,
    Path((_studio, job)): Path<(String, String)>,
) -> Sse<impl Stream<Item = Result<Event, Infallible>>> {
    let job = Uuid::parse_str(&job).ok();
    let stream = async_stream::stream! {
        let Some(job) = job else {
            yield Ok(sse::error("Job not found"));
            return;
        };
        let mut last: Option<String> = None;
        for _ in 0..600 {
            let row = sqlx::query("SELECT status, chunks_written, error, user_id FROM ingest_jobs WHERE id = $1")
                .bind(job)
                .fetch_optional(&state.cockpit)
                .await
                .ok()
                .flatten();
            let Some(r) = row.filter(|r| r.get::<Uuid, _>("user_id") == user) else {
                yield Ok(sse::error("Job not found"));
                return;
            };
            let status: String = r.get("status");
            if last.as_deref() != Some(&status) {
                last = Some(status.clone());
                let chunks: i32 = r.get("chunks_written");
                yield Ok(sse::event("progress", &json!({ "status": status, "chunks": chunks })));
            }
            match status.as_str() {
                "done" => { yield Ok(sse::done()); return; }
                "failed" => {
                    let e: Option<String> = r.get("error");
                    yield Ok(sse::error(e.unwrap_or_else(|| "Ingestion failed".into())));
                    return;
                }
                _ => tokio::time::sleep(Duration::from_millis(500)).await,
            }
        }
        yield Ok(sse::error("Ingestion timed out"));
    };
    Sse::new(stream).keep_alive(KeepAlive::default())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names() {
        assert_eq!(clean_name("../../etc/passwd"), "passwd");
        assert_eq!(clean_name("C:\\Users\\x\\Lecture 5.pdf"), "Lecture 5.pdf");
        assert_eq!(clean_name(".."), "upload.bin");
        assert_eq!(clean_name(""), "upload.bin");
    }
}

//! The document over HTTP: read it, save it from the editor, follow it live
//! while the agent writes, and roll it back to an earlier version.
//!
//! Editor saves are checked against `rev`: a save names the `rev` it was
//! based on and loses to any change made since. While a run holds the lock
//! nothing but the run can change the document.

use std::convert::Infallible;
use std::time::Duration;

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::response::sse::{Event, KeepAlive, Sse};
use axum::Json;
use chrono::{DateTime, Utc};
use futures::Stream;
use octo_common::ApiError;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sqlx::PgPool;
use tokio::sync::broadcast::error::RecvError;
use uuid::Uuid;

use super::present;
use crate::ctx::Caller;
use crate::documents;
use crate::live_docs::DocSignal;
use crate::pricing::count_words;
use crate::AppState;

const STYLES: [&str; 6] = ["apa", "mla", "chicago", "harvard", "ieee", "none"];

/// Editor saves closer together than this share one version: the first save
/// after a quiet spell (or after the agent wrote) keeps what was there before.
const USER_SAVE_WINDOW: &str = "10 minutes";

fn conflict(message: &str, code: &'static str, rev: i64) -> ApiError {
    ApiError::new(StatusCode::CONFLICT, message)
        .with_code(code)
        .with_details(json!({ "rev": rev }))
}

/// The document as clients see it, if the project is the caller's.
async fn read(db: &PgPool, project_id: Uuid, user_id: Uuid) -> Result<Option<Value>, sqlx::Error> {
    sqlx::query_scalar(
        "SELECT jsonb_build_object( \
             'rev', d.rev, 'style', d.style, 'title', d.title, 'fields', d.fields, \
             'body', d.body, 'delta', d.delta, 'bibliography', d.bibliography, \
             'sources', d.sources, 'locked', d.locked_by_run IS NOT NULL, \
             'wordCount', p.word_count, 'updatedAt', d.updated_at) \
         FROM documents d JOIN projects p ON p.id = d.project_id \
         WHERE d.project_id = $1 AND p.user_id = $2",
    )
    .bind(project_id)
    .bind(user_id)
    .fetch_optional(db)
    .await
}

async fn owned(db: &PgPool, project_id: Uuid, user_id: Uuid) -> Result<(), ApiError> {
    let found: bool =
        sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM projects WHERE id = $1 AND user_id = $2)")
            .bind(project_id)
            .bind(user_id)
            .fetch_one(db)
            .await?;
    if found {
        Ok(())
    } else {
        Err(ApiError::not_found("project not found"))
    }
}

/// `GET /v1/projects/:id/document` — the document as it stands. `locked` is
/// true while a run is writing it.
pub async fn get_one(
    State(st): State<AppState>,
    caller: Caller,
    Path(id): Path<Uuid>,
) -> Result<Json<Value>, ApiError> {
    read(&st.db, id, caller.user_id)
        .await?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("project not found"))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SaveDocument {
    /// The `rev` the editor's copy was loaded at.
    pub base_rev: i64,
    pub style: Option<String>,
    pub title: Option<String>,
    pub fields: Option<Value>,
    /// Plain text, paragraphs separated by a blank line.
    pub body: Option<String>,
    /// The rich body (a Quill delta). Absent with a `body` ⇒ cleared, since
    /// it would no longer match.
    #[serde(default, deserialize_with = "present")]
    pub delta: Option<Option<Value>>,
    pub bibliography: Option<String>,
}

#[derive(sqlx::FromRow)]
struct Current {
    rev: i64,
    locked: bool,
    style: String,
    title: String,
    fields: Value,
    body: String,
    delta: Option<Value>,
    bibliography: String,
}

fn too_long(value: &Option<String>, max: usize, name: &str) -> Result<(), ApiError> {
    match value {
        Some(v) if v.chars().count() > max => Err(ApiError::bad_request(format!(
            "{name} is longer than {max} characters"
        ))),
        _ => Ok(()),
    }
}

/// `PUT /v1/projects/:id/document` — save from the editor. Sending what is
/// already saved is a no-op, so a retried save succeeds.
pub async fn save(
    State(st): State<AppState>,
    caller: Caller,
    Path(id): Path<Uuid>,
    Json(save): Json<SaveDocument>,
) -> Result<Json<Value>, ApiError> {
    if save.style.as_deref().is_some_and(|s| !STYLES.contains(&s)) {
        return Err(ApiError::bad_request(format!(
            "style must be one of {}",
            STYLES.join(", ")
        )));
    }
    let title = save.title.map(|t| t.trim().to_string());
    too_long(&title, 300, "title")?;
    too_long(&save.body, 300_000, "body")?;
    too_long(&save.bibliography, 100_000, "bibliography")?;
    if save.fields.as_ref().is_some_and(|f| !f.is_object()) {
        return Err(ApiError::bad_request("fields must be an object"));
    }
    let replaces_delta = save.delta.is_some() || save.body.is_some();
    let delta = save.delta.flatten();
    if delta
        .as_ref()
        .is_some_and(|d| !d.is_object() && !d.is_array())
    {
        return Err(ApiError::bad_request("delta must be a Quill delta"));
    }

    let mut tx = st.db.begin().await?;
    let current: Option<Current> = sqlx::query_as(
        "SELECT d.rev, d.locked_by_run IS NOT NULL AS locked, d.style, d.title, d.fields, \
                d.body, d.delta, d.bibliography \
         FROM documents d JOIN projects p ON p.id = d.project_id \
         WHERE d.project_id = $1 AND p.user_id = $2 \
         FOR UPDATE OF d",
    )
    .bind(id)
    .bind(caller.user_id)
    .fetch_optional(&mut *tx)
    .await?;
    let current = current.ok_or_else(|| ApiError::not_found("project not found"))?;

    if current.locked {
        return Err(conflict(
            "GhostWriter is writing this document; it can be edited when it finishes",
            "document_locked",
            current.rev,
        ));
    }
    let unchanged = save.style.as_ref().is_none_or(|v| *v == current.style)
        && title.as_ref().is_none_or(|v| *v == current.title)
        && save.fields.as_ref().is_none_or(|v| *v == current.fields)
        && save.body.as_ref().is_none_or(|v| *v == current.body)
        && (!replaces_delta || delta == current.delta)
        && save
            .bibliography
            .as_ref()
            .is_none_or(|v| *v == current.bibliography);
    if unchanged {
        return Ok(Json(json!({
            "rev": current.rev,
            "wordCount": count_words(&current.body),
        })));
    }
    if current.rev != save.base_rev {
        return Err(conflict(
            "the document changed since it was loaded",
            "stale_rev",
            current.rev,
        ));
    }

    let recent_save: Option<bool> = sqlx::query_scalar(&format!(
        "SELECT reason = 'user_save' AND created_at > now() - interval '{USER_SAVE_WINDOW}' \
         FROM document_versions WHERE project_id = $1 \
         ORDER BY created_at DESC LIMIT 1"
    ))
    .bind(id)
    .fetch_optional(&mut *tx)
    .await?;
    let has_content = !current.body.is_empty() || current.delta.is_some();
    if has_content && !recent_save.unwrap_or(false) {
        documents::snapshot(&mut tx, id, "user_save").await?;
    }

    let (rev, body): (i64, String) = sqlx::query_as(
        "UPDATE documents SET \
             style = COALESCE($2, style), \
             title = COALESCE($3, title), \
             fields = COALESCE($4, fields), \
             body = COALESCE($5, body), \
             delta = CASE WHEN $6 THEN $7 ELSE delta END, \
             bibliography = COALESCE($8, bibliography), \
             rev = rev + 1, updated_at = now() \
         WHERE project_id = $1 \
         RETURNING rev, body",
    )
    .bind(id)
    .bind(&save.style)
    .bind(&title)
    .bind(&save.fields)
    .bind(&save.body)
    .bind(replaces_delta)
    .bind(&delta)
    .bind(&save.bibliography)
    .fetch_one(&mut *tx)
    .await?;
    let words = count_words(&body);
    set_word_count(&mut tx, id, words).await?;
    tx.commit().await?;

    st.docs.changed(id);
    Ok(Json(json!({ "rev": rev, "wordCount": words })))
}

/// Keeps the project's word count (shown in the sidebar) in step with its body.
async fn set_word_count(
    conn: &mut sqlx::PgConnection,
    project_id: Uuid,
    words: i64,
) -> Result<(), sqlx::Error> {
    // A project mid-run keeps `writing`; otherwise words make it `ready`.
    sqlx::query(
        "UPDATE projects SET word_count = $2, updated_at = now(), status = \
             CASE WHEN status = 'writing' THEN status \
                  WHEN $2 > 0 THEN 'ready' ELSE 'idle' END \
         WHERE id = $1",
    )
    .bind(project_id)
    .bind(words as i32)
    .execute(conn)
    .await?;
    Ok(())
}

fn data(value: &Value) -> Event {
    Event::default().data(value.to_string())
}

/// `GET /v1/projects/:id/document/stream` — the document for an open editor,
/// as Server-Sent Events: a `snapshot` first, then `delta`s while the agent
/// writes, `committed` as its text is saved, and `unlocked` when it is done.
/// Any other change sends a fresh `snapshot`.
pub async fn stream(
    State(st): State<AppState>,
    caller: Caller,
    Path(id): Path<Uuid>,
) -> Result<Sse<impl Stream<Item = Result<Event, Infallible>>>, ApiError> {
    owned(&st.db, id, caller.user_id).await?;

    let stream = async_stream::stream! {
        // Subscribe before reading the document, so nothing falls between.
        let (mut signals, mut live) = st.docs.subscribe(id);
        let mut locked = false;

        'outer: loop {
            // Send the document whole. A write in progress is ahead of the
            // database: its streamed text stands in for the saved body.
            let Ok(Some(mut document)) = read(&st.db, id, caller.user_id).await else {
                break;
            };
            if let Some(body) = live.take() {
                document["body"] = json!(body);
                document["delta"] = Value::Null;
                document["locked"] = json!(true);
            }
            let now_locked = document["locked"] == true;
            let rev = document["rev"].clone();
            document["type"] = json!("snapshot");
            yield Ok(data(&document));
            if locked && !now_locked {
                yield Ok(data(&json!({ "type": "unlocked", "rev": rev })));
            }
            locked = now_locked;

            // Then follow it until it has to be sent whole again.
            loop {
                match signals.recv().await {
                    Ok(DocSignal::Delta(text)) => {
                        yield Ok(data(&json!({ "type": "delta", "text": text })));
                    }
                    Ok(DocSignal::Committed(rev)) => {
                        yield Ok(data(&json!({ "type": "committed", "rev": rev })));
                    }
                    Ok(DocSignal::Began { body }) => {
                        live = Some(body);
                        continue 'outer;
                    }
                    Ok(DocSignal::Changed) => continue 'outer,
                    // Fell behind: start over from the text as it is now.
                    Err(RecvError::Lagged(_)) => {
                        (signals, live) = st.docs.subscribe(id);
                        continue 'outer;
                    }
                    Err(RecvError::Closed) => break 'outer,
                }
            }
        }
    };

    Ok(Sse::new(stream).keep_alive(KeepAlive::new().interval(Duration::from_secs(15))))
}

#[derive(Serialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
pub struct Version {
    pub id: Uuid,
    pub rev: i64,
    pub reason: String,
    pub created_at: DateTime<Utc>,
    pub title: String,
    /// The start of the body, to tell versions apart.
    pub preview: String,
    pub word_count: i32,
}

/// `GET /v1/projects/:id/versions/:version_id` — one saved version's text,
/// to compare with the document (reviewing a revision).
pub async fn version(
    State(st): State<AppState>,
    caller: Caller,
    Path((id, version_id)): Path<(Uuid, Uuid)>,
) -> Result<Json<Value>, ApiError> {
    owned(&st.db, id, caller.user_id).await?;
    let found: Option<(Uuid, i64, String, Value)> = sqlx::query_as(
        "SELECT id, rev, reason, snapshot FROM document_versions \
         WHERE id = $1 AND project_id = $2",
    )
    .bind(version_id)
    .bind(id)
    .fetch_optional(&st.db)
    .await?;
    let (version_id, rev, reason, snapshot) =
        found.ok_or_else(|| ApiError::not_found("version not found"))?;
    let text = |key: &str| snapshot[key].as_str().unwrap_or_default().to_string();
    Ok(Json(json!({
        "id": version_id,
        "rev": rev,
        "reason": reason,
        "title": text("title"),
        "body": text("body"),
        "bibliography": text("bibliography"),
    })))
}

/// `GET /v1/projects/:id/versions` — saved versions, newest first.
pub async fn versions(
    State(st): State<AppState>,
    caller: Caller,
    Path(id): Path<Uuid>,
) -> Result<Json<Value>, ApiError> {
    owned(&st.db, id, caller.user_id).await?;
    let versions: Vec<Version> = sqlx::query_as(
        "SELECT id, rev, reason, created_at, \
                 COALESCE(snapshot->>'title', '') AS title, \
                 left(COALESCE(snapshot->>'body', ''), 160) AS preview, \
                 CASE WHEN btrim(COALESCE(snapshot->>'body', '')) = '' THEN 0 \
                      ELSE array_length(regexp_split_to_array( \
                               btrim(snapshot->>'body'), '\\s+'), 1) END AS word_count \
          FROM document_versions WHERE project_id = $1 \
          ORDER BY created_at DESC, rev DESC LIMIT 100",
    )
    .bind(id)
    .fetch_all(&st.db)
    .await?;
    Ok(Json(json!({ "versions": versions })))
}

/// `POST /v1/projects/:id/versions/:versionId/restore` — put an earlier
/// version back. What it replaces is saved as a version first, so a restore
/// can itself be undone.
pub async fn restore(
    State(st): State<AppState>,
    caller: Caller,
    Path((id, version_id)): Path<(Uuid, Uuid)>,
) -> Result<Json<Value>, ApiError> {
    let mut tx = st.db.begin().await?;
    let current: Option<(i64, bool)> = sqlx::query_as(
        "SELECT d.rev, d.locked_by_run IS NOT NULL \
         FROM documents d JOIN projects p ON p.id = d.project_id \
         WHERE d.project_id = $1 AND p.user_id = $2 \
         FOR UPDATE OF d",
    )
    .bind(id)
    .bind(caller.user_id)
    .fetch_optional(&mut *tx)
    .await?;
    let (rev, locked) = current.ok_or_else(|| ApiError::not_found("project not found"))?;
    if locked {
        return Err(conflict(
            "GhostWriter is writing this document; restore it when it finishes",
            "document_locked",
            rev,
        ));
    }

    let snapshot: Option<Value> = sqlx::query_scalar(
        "SELECT snapshot FROM document_versions WHERE id = $1 AND project_id = $2",
    )
    .bind(version_id)
    .bind(id)
    .fetch_optional(&mut *tx)
    .await?;
    let snapshot = snapshot.ok_or_else(|| ApiError::not_found("version not found"))?;
    let text = |key: &str| snapshot[key].as_str().unwrap_or_default().to_string();
    let fields = Some(&snapshot["fields"])
        .filter(|v| v.is_object())
        .cloned()
        .unwrap_or_else(|| json!({}));
    let sources = Some(&snapshot["sources"])
        .filter(|v| v.is_array())
        .cloned()
        .unwrap_or_else(|| json!([]));
    let delta = Some(&snapshot["delta"]).filter(|v| !v.is_null()).cloned();
    let body = text("body");

    documents::snapshot(&mut tx, id, "restore").await?;
    sqlx::query(
        "UPDATE documents SET style = $2, title = $3, fields = $4, body = $5, delta = $6, \
             bibliography = $7, sources = $8, rev = rev + 1, updated_at = now() \
         WHERE project_id = $1",
    )
    .bind(id)
    .bind(documents::style_key(&text("style")))
    .bind(text("title"))
    .bind(&fields)
    .bind(&body)
    .bind(&delta)
    .bind(text("bibliography"))
    .bind(&sources)
    .execute(&mut *tx)
    .await?;
    set_word_count(&mut tx, id, count_words(&body)).await?;
    tx.commit().await?;

    st.docs.changed(id);
    read(&st.db, id, caller.user_id)
        .await?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("project not found"))
}

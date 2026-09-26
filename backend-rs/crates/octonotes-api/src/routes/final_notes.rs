//! Finalize (redesigned hub `/notes/finalize` and Panel 13) → immutable,
//! versioned Final Notes, exports, and the input to Study Studio (Panel 14).

use axum::extract::{Path, Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::Json;
use chrono::{DateTime, Utc};
use octo_common::ApiError;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sqlx::Row;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::ctx::Caller;
use crate::jobs::{self, Job, JobResult};
use crate::realtime::Event;
use crate::routes::blocks;
use crate::{access, export, idempotency, outbox, AppState};

#[derive(Debug, Serialize, sqlx::FromRow, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct FinalNotes {
    pub id: Uuid,
    pub session_id: Uuid,
    pub version: i32,
    pub title: String,
    #[schema(value_type = Object)]
    pub content: Value,
    #[schema(value_type = Option<Vec<Object>>)]
    pub summary_topics: Option<Value>,
    pub deck_ref: Option<String>,
    pub finalized_at: DateTime<Utc>,
}

const COLUMNS: &str =
    "id, session_id, version, title, content, summary_topics, deck_ref, finalized_at";

/// Headings as a tree (h1 › h2 › h3).
fn outline(blocks: &[blocks::Block]) -> Value {
    let mut roots: Vec<Value> = Vec::new();
    for b in blocks {
        let node = json!({ "title": b.text, "blockId": b.id, "children": [] });
        match b.kind.as_str() {
            "h1" => roots.push(node),
            "h2" | "h3" => match roots.last_mut() {
                Some(r) if b.kind == "h2" => {
                    r["children"].as_array_mut().expect("children").push(node)
                }
                Some(r) => match r["children"].as_array_mut().and_then(|c| c.last_mut()) {
                    Some(h2) => h2["children"].as_array_mut().expect("children").push(node),
                    None => r["children"].as_array_mut().expect("children").push(node),
                },
                None => roots.push(node),
            },
            _ => {}
        }
    }
    Value::Array(roots)
}

fn categories(blocks: &[blocks::Block]) -> Value {
    let count = |kinds: &[&str]| {
        blocks
            .iter()
            .filter(|b| kinds.contains(&b.kind.as_str()))
            .count()
    };
    json!([
        { "key": "topics", "count": count(&["h1", "h2", "h3"]) },
        { "key": "definitions", "count": count(&["definition", "keyIdea"]) },
        { "key": "questions", "count": count(&["question"]) },
        { "key": "examHints", "count": count(&["examHint"]) },
        { "key": "formulas", "count": count(&["formula"]) },
        { "key": "examples", "count": count(&["example"]) },
    ])
}

/// The Finalize screen's data: the latest topic summary (with whether the
/// notes changed since), the outline and categories. A read — to refresh the
/// summary call `POST /v1/sessions/{id}/summarize`.
#[utoipa::path(get, path = "/v1/sessions/{id}/finalize/summary", tag = "finalize", params(("id" = Uuid, Path)),
    responses((status = 200, description = "{topics|null, summarizedAt, stale, outline, categories}")))]
pub async fn summary(
    State(st): State<AppState>,
    caller: Caller,
    Path(session_id): Path<Uuid>,
) -> Result<Json<Value>, ApiError> {
    let mut conn = st.notes.acquire().await?;
    access::session(&mut conn, &caller, session_id).await?;
    let all = blocks::load_blocks(&mut conn, session_id, None).await?;
    let run = sqlx::query("SELECT response, updated_at FROM ai_runs WHERE session_id = $1 AND kind = 'summarize' AND status = 'done' ORDER BY updated_at DESC LIMIT 1")
        .bind(session_id).fetch_optional(&mut *conn).await?;
    let last_change: Option<DateTime<Utc>> =
        sqlx::query_scalar("SELECT max(updated_at) FROM blocks WHERE session_id = $1")
            .bind(session_id)
            .fetch_one(&mut *conn)
            .await?;
    let (topics, at) = match &run {
        Some(r) => (
            r.get::<Option<Value>, _>("response")
                .map(|v| v["topics"].clone()),
            Some(r.get::<DateTime<Utc>, _>("updated_at")),
        ),
        None => (None, None),
    };
    let stale = match (at, last_change) {
        (Some(a), Some(c)) => c > a,
        (None, _) => true,
        _ => false,
    };
    Ok(Json(
        json!({ "topics": topics, "summarizedAt": at, "stale": stale, "outline": outline(&all), "categories": categories(&all) }),
    ))
}

#[derive(Debug, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct FinalizeRequest {
    pub title: Option<String>,
    /// Topic (heading) titles to include; everything when omitted. Blocks
    /// before the first heading are always kept.
    pub included_topics: Option<Vec<String>>,
    /// Apply this review's accept/exclude/edit decisions (latest review when omitted).
    pub review_id: Option<Uuid>,
    pub deck_ref: Option<String>,
}

#[utoipa::path(post, path = "/v1/sessions/{id}/finalize", tag = "finalize", params(("id" = Uuid, Path)), request_body = FinalizeRequest,
    responses((status = 201, body = FinalNotes)))]
pub async fn finalize(
    State(st): State<AppState>,
    caller: Caller,
    Path(session_id): Path<Uuid>,
    headers: HeaderMap,
    Json(req): Json<FinalizeRequest>,
) -> Result<(StatusCode, Json<Value>), ApiError> {
    let idem = idempotency::key(&headers);
    let hash = idempotency::hash(&(&req, session_id));
    if let Some(k) = &idem {
        if let Some((code, body)) = idempotency::replay(&st.notes, caller.user_id, k, &hash).await?
        {
            return Ok((code, Json(body)));
        }
    }
    if let Some(r) = &req.deck_ref {
        crate::routes::sessions::validate_deck_ref(r)?;
    }
    let mut tx = st.notes.begin().await?;
    access::writable_session(&mut tx, &caller, session_id).await?;
    let session = crate::routes::sessions::owned(&mut tx, &caller, session_id).await?;
    let all = blocks::load_blocks(&mut tx, session_id, None).await?;
    if all.is_empty() {
        return Err(
            ApiError::bad_request("nothing to finalize — the notes are empty")
                .with_code("empty_notes"),
        );
    }
    let review_id: Option<Uuid> = match req.review_id {
        Some(r) => Some(
            sqlx::query_scalar("SELECT id FROM reviews WHERE id = $1 AND session_id = $2")
                .bind(r)
                .bind(session_id)
                .fetch_optional(&mut *tx)
                .await?
                .ok_or_else(|| ApiError::not_found("review not found"))?,
        ),
        None => {
            sqlx::query_scalar(
                "SELECT id FROM reviews WHERE session_id = $1 ORDER BY created_at DESC LIMIT 1",
            )
            .bind(session_id)
            .fetch_optional(&mut *tx)
            .await?
        }
    };
    let decisions: std::collections::HashMap<String, (String, Option<String>)> = match review_id {
        Some(r) => sqlx::query(
            "SELECT block_key, decision, edited_text FROM review_decisions WHERE review_id = $1",
        )
        .bind(r)
        .fetch_all(&mut *tx)
        .await?
        .into_iter()
        .map(|x| {
            (
                x.get::<String, _>("block_key"),
                (
                    x.get::<String, _>("decision"),
                    x.get::<Option<String>, _>("edited_text"),
                ),
            )
        })
        .collect(),
        None => Default::default(),
    };
    let wanted: Option<Vec<String>> = req
        .included_topics
        .as_ref()
        .map(|t| t.iter().map(|s| s.trim().to_lowercase()).collect());
    let mut include_section = true;
    let mut out = Vec::new();
    for b in &all {
        if matches!(b.kind.as_str(), "h1" | "h2") {
            include_section = wanted
                .as_ref()
                .is_none_or(|w| w.iter().any(|t| *t == b.text.trim().to_lowercase()));
        }
        if !include_section {
            continue;
        }
        let text = match decisions.get(&b.id.to_string()) {
            Some((d, _)) if d == "excluded" => continue,
            Some((d, Some(t))) if d == "edited" => t.clone(),
            _ => b.text.clone(),
        };
        out.push(json!({
            "id": b.id, "type": b.kind, "text": text, "indent": b.indent, "origin": b.origin,
            "provenance": { "sourceRef": b.source_ref, "transcriptAnchor": b.transcript_anchor, "aiSources": b.ai_sources, "audioTsMs": b.audio_ts_ms },
        }));
    }
    let summary: Option<Value> = sqlx::query_scalar("SELECT response->'topics' FROM ai_runs WHERE session_id = $1 AND kind = 'summarize' AND status = 'done' ORDER BY updated_at DESC LIMIT 1")
        .bind(session_id).fetch_optional(&mut *tx).await?.flatten();
    let summary = summary.map(|topics| match &wanted {
        Some(w) => Value::Array(
            topics
                .as_array()
                .cloned()
                .unwrap_or_default()
                .into_iter()
                .filter(|t| {
                    t["title"]
                        .as_str()
                        .is_some_and(|x| w.contains(&x.trim().to_lowercase()))
                })
                .collect(),
        ),
        None => topics,
    });
    let version: i32 = sqlx::query_scalar(
        "SELECT COALESCE(max(version), 0) + 1 FROM final_notes WHERE session_id = $1",
    )
    .bind(session_id)
    .fetch_one(&mut *tx)
    .await?;
    let title = req
        .title
        .as_deref()
        .map(str::trim)
        .filter(|t| !t.is_empty())
        .unwrap_or(&session.title)
        .to_string();
    let deck_ref = req.deck_ref.clone().or(session.deck_ref.clone());
    let fin = sqlx::query_as::<_, FinalNotes>(&format!(
        "INSERT INTO final_notes (session_id, user_id, version, title, content, summary_topics, deck_ref, review_id, idempotency_key) \
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING {COLUMNS}"))
        .bind(session_id).bind(caller.user_id).bind(version).bind(&title)
        .bind(json!({ "blocks": out, "sessionTitle": session.title, "durationMs": session.duration_ms }))
        .bind(&summary).bind(&deck_ref).bind(review_id).bind(&idem)
        .fetch_one(&mut *tx).await?;
    sqlx::query(
        "UPDATE sessions SET status = 'finalized', deck_ref = COALESCE($2, deck_ref) WHERE id = $1",
    )
    .bind(session_id)
    .bind(&deck_ref)
    .execute(&mut *tx)
    .await?;
    if let Some(r) = review_id {
        sqlx::query("UPDATE reviews SET status = 'finalized' WHERE id = $1")
            .bind(r)
            .execute(&mut *tx)
            .await?;
    }
    sqlx::query("INSERT INTO recommendations (final_notes_id, user_id) VALUES ($1, $2)")
        .bind(fin.id)
        .bind(caller.user_id)
        .execute(&mut *tx)
        .await?;
    jobs::enqueue_tx(
        &mut tx,
        Some(caller.user_id),
        "recommendations.build",
        json!({ "finalNotesId": fin.id, "sessionId": session_id }),
        Some(&format!("reco:{}", fin.id)),
    )
    .await?;
    outbox::record(
        &mut tx,
        caller.user_id,
        "finalNotes.ready",
        Some(fin.id),
        json!({ "sessionId": session_id, "title": title, "version": version }),
    )
    .await?;
    tx.commit().await?;
    let body = serde_json::to_value(&fin).unwrap_or_default();
    if let Some(k) = &idem {
        idempotency::store(
            &st.notes,
            caller.user_id,
            k,
            &hash,
            StatusCode::CREATED,
            &body,
        )
        .await?;
    }
    st.hub
        .session(
            session_id,
            Event::new(
                "session.finalized",
                json!({ "finalNotesId": fin.id, "version": version }),
                None,
            ),
        )
        .await;
    Ok((StatusCode::CREATED, Json(body)))
}

pub async fn owned(st: &AppState, caller: &Caller, id: Uuid) -> Result<FinalNotes, ApiError> {
    sqlx::query_as::<_, FinalNotes>(&format!(
        "SELECT f.{} FROM final_notes f JOIN sessions s ON s.id = f.session_id WHERE f.id = $1 AND f.user_id = $2 AND s.deleted_at IS NULL",
        COLUMNS.replace(", ", ", f.")))
        .bind(id).bind(caller.user_id).fetch_optional(&st.notes).await?
        .ok_or_else(|| ApiError::not_found("final notes not found"))
}

#[utoipa::path(get, path = "/v1/final-notes/{id}", tag = "finalize", params(("id" = Uuid, Path)), responses((status = 200, body = FinalNotes)))]
pub async fn get(
    State(st): State<AppState>,
    caller: Caller,
    Path(id): Path<Uuid>,
) -> Result<Json<FinalNotes>, ApiError> {
    Ok(Json(owned(&st, &caller, id).await?))
}

#[derive(Debug, Deserialize, utoipa::IntoParams)]
#[serde(rename_all = "camelCase")]
pub struct ListQuery {
    pub session_id: Uuid,
}

#[utoipa::path(get, path = "/v1/final-notes", tag = "finalize", params(ListQuery), responses((status = 200, body = Vec<FinalNotes>)))]
pub async fn list(
    State(st): State<AppState>,
    caller: Caller,
    Query(q): Query<ListQuery>,
) -> Result<Json<Vec<FinalNotes>>, ApiError> {
    let mut conn = st.notes.acquire().await?;
    access::session(&mut conn, &caller, q.session_id).await?;
    Ok(Json(
        sqlx::query_as::<_, FinalNotes>(&format!(
            "SELECT {COLUMNS} FROM final_notes WHERE session_id = $1 ORDER BY version DESC"
        ))
        .bind(q.session_id)
        .fetch_all(&mut *conn)
        .await?,
    ))
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct ExportRequest {
    /// `pdf` | `md` | `docx` | `txt`
    pub format: String,
}

#[utoipa::path(post, path = "/v1/final-notes/{id}/export", tag = "finalize", params(("id" = Uuid, Path)), request_body = ExportRequest,
    responses((status = 202, description = "{exportId, status}")))]
pub async fn export(
    State(st): State<AppState>,
    caller: Caller,
    Path(id): Path<Uuid>,
    Json(req): Json<ExportRequest>,
) -> Result<(StatusCode, Json<Value>), ApiError> {
    if !["pdf", "md", "docx", "txt"].contains(&req.format.as_str()) {
        return Err(ApiError::bad_request("format must be pdf, md, docx or txt"));
    }
    owned(&st, &caller, id).await?;
    let export_id: Uuid = sqlx::query_scalar(
        "INSERT INTO exports (final_notes_id, user_id, format) VALUES ($1,$2,$3) RETURNING id",
    )
    .bind(id)
    .bind(caller.user_id)
    .bind(&req.format)
    .fetch_one(&st.notes)
    .await?;
    jobs::enqueue(
        &st.notes,
        Some(caller.user_id),
        "export.render",
        json!({ "exportId": export_id }),
        Some(&format!("export:{export_id}")),
    )
    .await?;
    Ok((
        StatusCode::ACCEPTED,
        Json(json!({ "exportId": export_id, "status": "queued" })),
    ))
}

#[utoipa::path(get, path = "/v1/exports/{id}", tag = "finalize", params(("id" = Uuid, Path)),
    responses((status = 200, description = "{exportId, format, status, url?, error?}")))]
pub async fn export_status(
    State(st): State<AppState>,
    caller: Caller,
    Path(id): Path<Uuid>,
) -> Result<Json<Value>, ApiError> {
    let row = sqlx::query(
        "SELECT format, status, object_key, error FROM exports WHERE id = $1 AND user_id = $2",
    )
    .bind(id)
    .bind(caller.user_id)
    .fetch_optional(&st.notes)
    .await?
    .ok_or_else(|| ApiError::not_found("export not found"))?;
    let key: Option<String> = row.get("object_key");
    let url = match (&key, row.get::<String, _>("status").as_str()) {
        (Some(k), "done") => Some(
            st.storage
                .url(k, 900)
                .await
                .map_err(ApiError::unavailable)?,
        ),
        _ => None,
    };
    Ok(Json(
        json!({ "exportId": id, "format": row.get::<String, _>("format"), "status": row.get::<String, _>("status"), "url": url, "error": row.get::<Option<String>, _>("error") }),
    ))
}

pub async fn job_export(st: AppState, job: Job) -> JobResult {
    let id: Uuid =
        serde_json::from_value(job.payload["exportId"].clone()).map_err(|e| e.to_string())?;
    let row = sqlx::query("SELECT e.format, e.user_id, f.id AS fid, f.session_id, f.title, f.content, f.version FROM exports e JOIN final_notes f ON f.id = e.final_notes_id WHERE e.id = $1")
        .bind(id).fetch_optional(&st.notes).await.map_err(|e| e.to_string())?;
    let Some(row) = row else { return Ok(()) };
    let (format, user, fid, session, title, content, version): (
        String,
        Uuid,
        Uuid,
        Uuid,
        String,
        Value,
        i32,
    ) = (
        row.get("format"),
        row.get("user_id"),
        row.get("fid"),
        row.get("session_id"),
        row.get("title"),
        row.get("content"),
        row.get("version"),
    );
    let rendered: Result<(Vec<u8>, &str), String> = match format.as_str() {
        "md" => Ok((
            export::markdown(&title, &content).into_bytes(),
            "text/markdown",
        )),
        "txt" => Ok((export::text(&title, &content).into_bytes(), "text/plain")),
        "docx" => export::docx(&title, &content).map(|b| {
            (
                b,
                "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            )
        }),
        _ => {
            let (t, c) = (title.clone(), content.clone());
            tokio::task::spawn_blocking(move || export::pdf(&t, &c))
                .await
                .map_err(|e| e.to_string())?
                .map(|b| (b, "application/pdf"))
        }
    };
    match rendered {
        Ok((bytes, mime)) => {
            let slug: String = title
                .chars()
                .map(|c| if c.is_alphanumeric() { c } else { '-' })
                .collect::<String>()
                .trim_matches('-')
                .chars()
                .take(60)
                .collect();
            let key = format!("{user}/{session}/exports/{fid}/{slug}-v{version}.{format}");
            st.storage.put(&key, &bytes, mime).await?;
            sqlx::query("UPDATE exports SET status = 'done', object_key = $2 WHERE id = $1")
                .bind(id)
                .bind(&key)
                .execute(&st.notes)
                .await
                .map_err(|e| e.to_string())?;
        }
        Err(e) => {
            sqlx::query("UPDATE exports SET status = 'failed', error = $2 WHERE id = $1")
                .bind(id)
                .bind(&e)
                .execute(&st.notes)
                .await
                .map_err(|e| e.to_string())?;
        }
    }
    st.hub
        .user(
            user,
            Event::new(
                "export.ready",
                json!({ "exportId": id, "finalNotesId": fid }),
                None,
            ),
        )
        .await;
    Ok(())
}

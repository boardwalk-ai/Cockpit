//! Session Review (Panel 13). Preparing a review checks the capture is
//! complete (devices, audio, final transcript) and builds Smart Notes; the
//! student then accepts / excludes / edits blocks before finalizing. Nothing
//! here changes the original notes — decisions apply only to the final copy.

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{DateTime, Utc};
use octo_common::llm::{parse_json_loose, ChatOptions, Message};
use octo_common::ApiError;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sqlx::Row;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::ai::{self, clip, Llm, Role};
use crate::ctx::Caller;
use crate::jobs::{self, Job, JobResult};
use crate::realtime::Event;
use crate::routes::blocks::{self, Block};
use crate::{access, pricing, AppState};

#[derive(Debug, Serialize, sqlx::FromRow, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct Review {
    pub id: Uuid,
    pub session_id: Uuid,
    pub status: String,
    #[schema(value_type = Vec<Object>)]
    pub checklist: Value,
    #[schema(value_type = Option<Object>)]
    pub smart_notes: Option<Value>,
    #[schema(value_type = Object)]
    pub draft: Value,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

const COLUMNS: &str =
    "id, session_id, status, checklist, smart_notes, draft, created_at, updated_at";

#[utoipa::path(post, path = "/v1/sessions/{id}/review/prepare", tag = "review", params(("id" = Uuid, Path)),
    responses((status = 202, body = Review)))]
pub async fn prepare(
    State(st): State<AppState>,
    caller: Caller,
    Path(session_id): Path<Uuid>,
) -> Result<(StatusCode, Json<Review>), ApiError> {
    let mut tx = st.notes.begin().await?;
    access::writable_session(&mut tx, &caller, session_id).await?;
    let price = pricing::price(&st, "smart_notes").await;
    ai::guard(&st, &caller, price).await?;
    let review = sqlx::query_as::<_, Review>(&format!(
        "INSERT INTO reviews (session_id, user_id) VALUES ($1, $2) RETURNING {COLUMNS}"
    ))
    .bind(session_id)
    .bind(caller.user_id)
    .fetch_one(&mut *tx)
    .await?;
    sqlx::query("UPDATE sessions SET status = 'reviewing' WHERE id = $1 AND status NOT IN ('finalized', 'archived')")
        .bind(session_id).execute(&mut *tx).await?;
    jobs::enqueue_tx(
        &mut tx,
        Some(caller.user_id),
        "review.prepare",
        json!({ "reviewId": review.id, "sessionId": session_id }),
        Some(&format!("review:{}", review.id)),
    )
    .await?;
    tx.commit().await?;
    Ok((StatusCode::ACCEPTED, Json(review)))
}

/// The review checklist, computed from the session's real state.
async fn checklist(st: &AppState, session_id: Uuid) -> Result<Value, sqlx::Error> {
    let r = sqlx::query(
        "SELECT \
           (SELECT count(*) FROM session_devices WHERE session_id = $1 AND is_recording) AS recording, \
           (SELECT count(*) FROM recordings WHERE session_id = $1 AND state <> 'assembled') AS unassembled, \
           (SELECT count(*) FROM recordings WHERE session_id = $1) AS recordings, \
           (SELECT count(*) FROM audio_chunks c JOIN recordings r ON r.id = c.recording_id WHERE r.session_id = $1 AND c.asr_status = 'pending') AS asr_pending, \
           (SELECT count(*) FROM transcript_segments WHERE session_id = $1 AND (asr_conf < 0.6 OR (speaker <> 'unknown' AND speaker_conf < 0.6)) AND corrected_text IS NULL) AS low_conf, \
           (SELECT count(*) FROM ai_suggestions WHERE session_id = $1 AND status = 'pending') AS pending_ai, \
           (SELECT count(*) FROM org_passes WHERE session_id = $1 AND status = 'preview') AS pending_org, \
           (SELECT count(*) FROM ink_recognitions WHERE session_id = $1 AND status = 'proposed') AS pending_ink, \
           (SELECT count(*) FROM materials WHERE session_id = $1 AND state IN ('uploading', 'processing') AND deleted_at IS NULL) AS materials_pending, \
           (SELECT count(*) FROM blocks WHERE session_id = $1 AND deleted_at IS NULL) AS blocks, \
           (SELECT count(*) FROM transcript_segments WHERE session_id = $1) AS segments",
    )
    .bind(session_id)
    .fetch_one(&st.notes)
    .await?;
    let n = |c: &str| r.get::<i64, _>(c);
    let item = |key: &str, ok: bool, count: i64, layer: Option<&str>| json!({ "key": key, "state": if ok { "done" } else { "warning" }, "count": count, "layer": layer });
    Ok(json!([
        item("devicesSynced", n("recording") == 0, n("recording"), None),
        item(
            "audioUploaded",
            n("unassembled") == 0,
            n("unassembled"),
            Some("transcript")
        ),
        item(
            "transcriptFinal",
            n("asr_pending") == 0,
            n("asr_pending"),
            Some("transcript")
        ),
        item(
            "lowConfidenceTranscript",
            n("low_conf") == 0,
            n("low_conf"),
            Some("transcript")
        ),
        item(
            "aiSuggestionsReviewed",
            n("pending_ai") == 0,
            n("pending_ai"),
            Some("ai")
        ),
        item(
            "organizationReviewed",
            n("pending_org") == 0,
            n("pending_org"),
            Some("smartNotes")
        ),
        item(
            "handwritingConfirmed",
            n("pending_ink") == 0,
            n("pending_ink"),
            Some("ink")
        ),
        item(
            "materialsProcessed",
            n("materials_pending") == 0,
            n("materials_pending"),
            Some("materials")
        ),
        json!({ "key": "totals", "state": "info", "blocks": n("blocks"), "segments": n("segments"), "recordings": n("recordings") }),
    ]))
}

/// Smart Notes: sections → block ids. Offline: sections from the headings.
fn offline_smart(blocks: &[Block]) -> Value {
    let mut sections: Vec<Value> = Vec::new();
    for b in blocks {
        if matches!(b.kind.as_str(), "h1" | "h2") || sections.is_empty() {
            let title = if matches!(b.kind.as_str(), "h1" | "h2") {
                b.text.clone()
            } else {
                "Notes".into()
            };
            sections.push(json!({ "title": title, "blockIds": [] }));
        }
        sections.last_mut().expect("section")["blockIds"]
            .as_array_mut()
            .expect("ids")
            .push(json!(b.id));
    }
    json!({ "sections": sections })
}

pub async fn job_prepare(st: AppState, job: Job) -> JobResult {
    let review_id: Uuid =
        serde_json::from_value(job.payload["reviewId"].clone()).map_err(|e| e.to_string())?;
    let row = sqlx::query("SELECT r.session_id, r.user_id, r.status, s.status AS session_status FROM reviews r JOIN sessions s ON s.id = r.session_id WHERE r.id = $1")
        .bind(review_id).fetch_optional(&st.notes).await.map_err(|e| e.to_string())?;
    let Some(row) = row else { return Ok(()) };
    let (session_id, user_id): (Uuid, Uuid) = (row.get("session_id"), row.get("user_id"));
    if row.get::<String, _>("status") != "preparing" {
        return Ok(());
    }
    let caller = Caller {
        uid: String::new(),
        email: None,
        user_id,
    };
    st.hub
        .session(
            session_id,
            Event::new(
                "job.progress",
                json!({ "kind": "review.checking", "reviewId": review_id }),
                None,
            ),
        )
        .await;
    let checks = checklist(&st, session_id)
        .await
        .map_err(|e| e.to_string())?;

    // Smart Notes over the current blocks.
    let mut conn = st.notes.acquire().await.map_err(|e| e.to_string())?;
    let all = blocks::load_blocks(&mut conn, session_id, None)
        .await
        .map_err(|e| e.to_string())?;
    drop(conn);
    let listing = all
        .iter()
        .map(|b| format!("{} | {} | {}", b.id, b.kind, clip(&b.text, 160)))
        .collect::<Vec<_>>()
        .join("\n");
    let messages = vec![
        Message::system("Group a student's lecture-note blocks into clear sections for review. Never rewrite text. Reply with JSON only: \
{\"sections\": [{\"title\": string, \"blockIds\": [string]}]} using every block id exactly once, in reading order."),
        Message::user(format!("Blocks (id | type | text):\n{listing}")),
    ];
    let price = pricing::price(&st, "smart_notes").await;
    let run = ai::start_run(
        &st,
        &caller,
        Some(session_id),
        "smartNotes",
        None,
        &json!([{ "type": "session" }]),
    )
    .await
    .map_err(|e| e.message)?;
    let llm = Llm::for_role(&st, Role::Primary).await;
    let model = llm.model_name();
    let plan = offline_smart(&all).to_string();
    let (text, usage) = llm
        .complete(
            &messages,
            &ChatOptions {
                temperature: Some(0.1),
                max_tokens: Some(3000),
                json: true,
            },
            || plan,
        )
        .await
        .map_err(|e| e.message)?;
    // Keep only known ids; anything the model dropped goes to a final section.
    let known: std::collections::HashSet<String> = all.iter().map(|b| b.id.to_string()).collect();
    let mut seen = std::collections::HashSet::new();
    let mut sections: Vec<Value> = parse_json_loose(&text)
        .and_then(|v| v["sections"].as_array().cloned())
        .unwrap_or_default()
        .into_iter()
        .map(|s| {
            let ids: Vec<Value> = s["blockIds"]
                .as_array()
                .cloned()
                .unwrap_or_default()
                .into_iter()
                .filter(|i| {
                    i.as_str()
                        .is_some_and(|x| known.contains(x) && seen.insert(x.to_string()))
                })
                .collect();
            json!({ "title": s["title"], "blockIds": ids })
        })
        .filter(|s| !s["blockIds"].as_array().is_none_or(|a| a.is_empty()))
        .collect();
    let leftover: Vec<Value> = all
        .iter()
        .filter(|b| !seen.contains(&b.id.to_string()))
        .map(|b| json!(b.id))
        .collect();
    if !leftover.is_empty() {
        sections.push(json!({ "title": "More notes", "blockIds": leftover }));
    }
    let smart = json!({ "sections": sections });
    ai::finish_run(
        &st,
        &caller,
        run,
        ai::Outcome {
            kind: "smartNotes",
            response: &smart,
            model: &model,
            usage: &usage,
            price,
        },
    )
    .await
    .map_err(|e| e.message)?;
    sqlx::query(
        "UPDATE reviews SET status = 'ready', checklist = $2, smart_notes = $3 WHERE id = $1",
    )
    .bind(review_id)
    .bind(&checks)
    .bind(&smart)
    .execute(&st.notes)
    .await
    .map_err(|e| e.to_string())?;
    st.hub
        .session(
            session_id,
            Event::new(
                "job.progress",
                json!({ "kind": "review.ready", "reviewId": review_id }),
                None,
            ),
        )
        .await;
    Ok(())
}

async fn owned(st: &AppState, caller: &Caller, id: Uuid) -> Result<Review, ApiError> {
    sqlx::query_as::<_, Review>(&format!(
        "SELECT {COLUMNS} FROM reviews WHERE id = $1 AND user_id = $2"
    ))
    .bind(id)
    .bind(caller.user_id)
    .fetch_optional(&st.notes)
    .await?
    .ok_or_else(|| ApiError::not_found("review not found"))
}

#[utoipa::path(get, path = "/v1/reviews/{id}", tag = "review", params(("id" = Uuid, Path)),
    responses((status = 200, description = "{review, layers{studentNotes, smartNotes, transcript, ink, ai, research}, decisions}")))]
pub async fn get(
    State(st): State<AppState>,
    caller: Caller,
    Path(id): Path<Uuid>,
) -> Result<Json<Value>, ApiError> {
    let mut review = owned(&st, &caller, id).await?;
    if review.status != "preparing" {
        // Keep the checklist live while the student works through it.
        review.checklist = checklist(&st, review.session_id).await?;
    }
    let mut conn = st.notes.acquire().await?;
    let notes = blocks::load_blocks(&mut conn, review.session_id, None).await?;
    let decisions: Value = sqlx::query_scalar("SELECT COALESCE(json_object_agg(block_key, json_build_object('decision', decision, 'editedText', edited_text)), '{}') FROM review_decisions WHERE review_id = $1")
        .bind(id).fetch_one(&mut *conn).await?;
    let transcript: Value = sqlx::query_scalar(
        "SELECT COALESCE(json_agg(json_build_object('id', id, 'startMs', start_ms, 'speaker', speaker, 'text', COALESCE(corrected_text, faithful_text, raw_text), \
             'corrected', corrected_text IS NOT NULL, 'lowConfidence', asr_conf < 0.6) ORDER BY start_ms), '[]') FROM transcript_segments WHERE session_id = $1")
        .bind(review.session_id).fetch_one(&mut *conn).await?;
    let ink: Value = sqlx::query_scalar(
        "SELECT COALESCE(json_agg(json_build_object('pageId', p.id, 'ordinal', p.ordinal, \
             'strokes', (SELECT count(*) FROM ink_strokes s WHERE s.page_id = p.id AND s.deleted_at IS NULL), \
             'recognitions', (SELECT COALESCE(json_agg(json_build_object('id', r.id, 'text', r.text, 'status', r.status)), '[]') FROM ink_recognitions r WHERE r.page_id = p.id)) \
             ORDER BY p.ordinal), '[]') FROM ink_pages p WHERE p.session_id = $1 AND p.deleted_at IS NULL")
        .bind(review.session_id).fetch_one(&mut *conn).await?;
    let ai_pending: Value = sqlx::query_scalar(
        "SELECT COALESCE(json_agg(json_build_object('id', id, 'sourceBlockId', source_block_id, 'action', action, 'body', body, 'sources', sources)), '[]') \
         FROM ai_suggestions WHERE session_id = $1 AND status = 'pending'")
        .bind(review.session_id).fetch_one(&mut *conn).await?;
    let research: Value = sqlx::query_scalar(
        "SELECT COALESCE(json_agg(json_build_object('researchId', id, 'question', question, 'explanation', explanation)), '[]') FROM research_runs WHERE session_id = $1 AND saved")
        .bind(review.session_id).fetch_one(&mut *conn).await?;
    let smart = review.smart_notes.clone();
    Ok(Json(json!({
        "review": review,
        "layers": { "studentNotes": notes, "smartNotes": smart, "transcript": transcript, "ink": ink, "ai": ai_pending, "research": research },
        "decisions": decisions,
    })))
}

#[utoipa::path(get, path = "/v1/sessions/{id}/review", tag = "review", params(("id" = Uuid, Path)), responses((status = 200, body = Review)))]
pub async fn latest(
    State(st): State<AppState>,
    caller: Caller,
    Path(session_id): Path<Uuid>,
) -> Result<Json<Review>, ApiError> {
    let mut conn = st.notes.acquire().await?;
    access::session(&mut conn, &caller, session_id).await?;
    sqlx::query_as::<_, Review>(&format!(
        "SELECT {COLUMNS} FROM reviews WHERE session_id = $1 ORDER BY created_at DESC LIMIT 1"
    ))
    .bind(session_id)
    .fetch_optional(&mut *conn)
    .await?
    .map(Json)
    .ok_or_else(|| ApiError::not_found("no review yet"))
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct Decision {
    /// Block id (or another layer's item key).
    pub block_key: String,
    /// `accepted` | `excluded` | `edited`
    pub decision: String,
    pub edited_text: Option<String>,
}

#[utoipa::path(post, path = "/v1/reviews/{id}/decisions", tag = "review", params(("id" = Uuid, Path)), request_body = Vec<Decision>,
    responses((status = 204)))]
pub async fn decide(
    State(st): State<AppState>,
    caller: Caller,
    Path(id): Path<Uuid>,
    Json(req): Json<Vec<Decision>>,
) -> Result<StatusCode, ApiError> {
    let review = owned(&st, &caller, id).await?;
    if review.status == "finalized" {
        return Err(
            ApiError::new(StatusCode::CONFLICT, "review already finalized")
                .with_code("review_finalized"),
        );
    }
    if req.len() > 2000 {
        return Err(ApiError::bad_request("at most 2000 decisions per request"));
    }
    let mut tx = st.notes.begin().await?;
    for d in req {
        match (d.decision.as_str(), d.edited_text.as_deref()) {
            ("accepted" | "excluded", _) => {}
            ("edited", Some(t)) if !t.trim().is_empty() && t.len() <= 100_000 => {}
            ("edited", _) => return Err(ApiError::bad_request("edited needs editedText")),
            _ => {
                return Err(ApiError::bad_request(
                    "decision must be accepted, excluded or edited",
                ))
            }
        }
        sqlx::query("INSERT INTO review_decisions (review_id, block_key, decision, edited_text) VALUES ($1,$2,$3,$4) \
                     ON CONFLICT (review_id, block_key) DO UPDATE SET decision = EXCLUDED.decision, edited_text = EXCLUDED.edited_text, updated_at = now()")
            .bind(id).bind(&d.block_key).bind(&d.decision).bind(&d.edited_text).execute(&mut *tx).await?;
    }
    if review.status == "ready" {
        sqlx::query("UPDATE reviews SET status = 'draft' WHERE id = $1")
            .bind(id)
            .execute(&mut *tx)
            .await?;
    }
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

#[utoipa::path(put, path = "/v1/reviews/{id}/draft", tag = "review", params(("id" = Uuid, Path)), request_body = Object,
    responses((status = 204)))]
pub async fn save_draft(
    State(st): State<AppState>,
    caller: Caller,
    Path(id): Path<Uuid>,
    Json(draft): Json<Value>,
) -> Result<StatusCode, ApiError> {
    if !draft.is_object() || draft.to_string().len() > 100_000 {
        return Err(ApiError::bad_request(
            "draft must be an object under 100 KB",
        ));
    }
    let review = owned(&st, &caller, id).await?;
    if review.status == "finalized" {
        return Err(
            ApiError::new(StatusCode::CONFLICT, "review already finalized")
                .with_code("review_finalized"),
        );
    }
    sqlx::query("UPDATE reviews SET draft = $2, status = CASE WHEN status = 'ready' THEN 'draft' ELSE status END WHERE id = $1")
        .bind(id).bind(draft).execute(&st.notes).await?;
    Ok(StatusCode::NO_CONTENT)
}

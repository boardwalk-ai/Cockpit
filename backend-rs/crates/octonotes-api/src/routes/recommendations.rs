//! Study Studio Recommendations (Panel 14): topics detected in the final
//! notes, how ready each is to study, which activities fit, and whether the
//! student already has it in a studio (with their mastery). Deterministic —
//! built from the notes' structure and provenance, so it costs nothing.

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;
use octo_common::ApiError;
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::ctx::Caller;
use crate::jobs::{Job, JobResult};
use crate::realtime::Event;
use crate::routes::final_notes;
use crate::AppState;

/// Splits the final notes into topics at h1/h2 headings.
pub fn topics_of(content: &Value) -> Vec<Value> {
    let blocks = content["blocks"].as_array().cloned().unwrap_or_default();
    let mut topics: Vec<(String, Vec<Value>)> = Vec::new();
    for b in blocks {
        let kind = b["type"].as_str().unwrap_or("");
        if matches!(kind, "h1" | "h2") {
            topics.push((b["text"].as_str().unwrap_or("Untitled").to_string(), vec![b]));
        } else {
            match topics.last_mut() {
                Some(t) => t.1.push(b),
                None => topics.push(("Session notes".into(), vec![b])),
            }
        }
    }
    topics
        .into_iter()
        .enumerate()
        .map(|(i, (title, blocks))| {
            let body: Vec<&Value> = blocks.iter().filter(|b| !matches!(b["type"].as_str(), Some("h1" | "h2"))).collect();
            let has = |k: &str| body.iter().filter(|b| b["type"] == k).count();
            let material = |b: &&Value| b["provenance"]["sourceRef"]["material"].as_str().unwrap_or("").to_lowercase();
            let transcript = body.iter().filter(|b| !b["provenance"]["transcriptAnchor"].is_null() || b["origin"] == "fromTranscript" || material(b) == "transcript").count();
            let slides = body.iter().filter(|b| b["origin"] == "fromSlide" || b["type"] == "slideRef" || (!material(b).is_empty() && material(b) != "transcript")).count();
            let ai = body.iter().filter(|b| b["provenance"]["aiSources"].as_array().is_some_and(|a| !a.is_empty())).count();
            let sourced = transcript + slides + ai;
            let ready = body.len() >= 2 && (sourced > 0 || body.len() >= 4);
            let mut activities = vec!["teachMe"];
            if body.len() >= 3 { activities.push("quizMe"); }
            if has("definition") + has("keyIdea") > 0 || body.len() >= 2 { activities.push("flashcards"); }
            if has("examHint") > 0 || has("formula") > 0 { activities.push("lightningRecall"); }
            if body.len() >= 5 { activities.push("scenarios"); }
            let mut sources = vec!["Student notes"];
            if transcript > 0 { sources.push("Lecture transcript"); }
            if slides > 0 { sources.push("Course slides"); }
            if ai > 0 { sources.push("Approved AI explanations"); }
            json!({
                "id": format!("t{}", i + 1),
                "title": title,
                "readiness": if ready { "ready" } else { "needsReview" },
                "counts": { "blocks": body.len(), "transcriptRefs": transcript, "slideRefs": slides, "questions": has("question"),
                            "examHints": has("examHint"), "definitions": has("definition") + has("keyIdea") },
                "activities": activities,
                "sources": sources,
                "reasonWhy": format!("{} note block(s){}", body.len(), if sourced > 0 { format!(" backed by {sourced} lecture source link(s)") } else { String::new() }),
                "reviewReason": if ready { Value::Null } else if body.len() < 2 { json!("Only a little material on this topic") } else { json!("No lecture source linked yet") },
                "blockIds": blocks.iter().map(|b| b["id"].clone()).collect::<Vec<_>>(),
                "alreadyInStudio": Value::Null,
            })
        })
        .collect()
}

/// Marks topics the student already has in a studio (title match), with mastery.
async fn match_existing(st: &AppState, user_id: Uuid, topics: &mut [Value]) {
    let Some(studio) = &st.studio else { return };
    for t in topics.iter_mut() {
        let title = t["title"].as_str().unwrap_or("").trim().to_lowercase();
        let row = sqlx::query(
            "SELECT g.studio_id, s.title AS studio_title, g.payload->>'id' AS topic_id, \
                    (SELECT p.mastery FROM topic_progress p WHERE p.user_id = g.user_id AND p.topic_id = g.payload->>'id' LIMIT 1) AS mastery \
             FROM generated_topics g JOIN studios s ON s.id = g.studio_id \
             WHERE g.user_id = $1 AND lower(trim(g.payload->>'title')) = $2 ORDER BY s.updated_at DESC LIMIT 1")
            .bind(user_id).bind(&title).fetch_optional(studio).await.ok().flatten();
        if let Some(r) = row {
            t["alreadyInStudio"] = json!({ "studioId": r.get::<Uuid, _>("studio_id"), "studioTitle": r.get::<String, _>("studio_title"),
                                           "topicId": r.get::<Option<String>, _>("topic_id"), "mastery": r.get::<Option<f64>, _>("mastery") });
        }
    }
}

pub async fn job_build(st: AppState, job: Job) -> JobResult {
    let fid: Uuid = serde_json::from_value(job.payload["finalNotesId"].clone()).map_err(|e| e.to_string())?;
    let row = sqlx::query("SELECT user_id, session_id, content FROM final_notes WHERE id = $1").bind(fid).fetch_optional(&st.notes).await.map_err(|e| e.to_string())?;
    let Some(row) = row else { return Ok(()) };
    let (user, session): (Uuid, Uuid) = (row.get("user_id"), row.get("session_id"));
    let mut topics = topics_of(&row.get::<Value, _>("content"));
    match_existing(&st, user, &mut topics).await;
    let selected: Vec<Value> = topics.iter().filter(|t| t["readiness"] == "ready").map(|t| t["id"].clone()).collect();
    sqlx::query("UPDATE recommendations SET status = 'ready', topics = $2, selection = $3 WHERE final_notes_id = $1")
        .bind(fid).bind(Value::Array(topics)).bind(json!({ "mode": "topics", "topicIds": selected })).execute(&st.notes).await.map_err(|e| e.to_string())?;
    st.hub.session(session, Event::new("recommendations.ready", json!({ "finalNotesId": fid }), None)).await;
    Ok(())
}

#[utoipa::path(get, path = "/v1/final-notes/{id}/recommendations", tag = "studyStudio", params(("id" = Uuid, Path)),
    responses((status = 200, description = "{status, topics[], selection, summary{topics, ready, needsReview}}")))]
pub async fn get(State(st): State<AppState>, caller: Caller, Path(id): Path<Uuid>) -> Result<Json<Value>, ApiError> {
    final_notes::owned(&st, &caller, id).await?;
    let row = sqlx::query("SELECT status, topics, selection, manual_block_ids FROM recommendations WHERE final_notes_id = $1")
        .bind(id).fetch_optional(&st.notes).await?.ok_or_else(|| ApiError::not_found("recommendations not found"))?;
    let topics: Value = row.get("topics");
    let ready = topics.as_array().map(|a| a.iter().filter(|t| t["readiness"] == "ready").count()).unwrap_or(0);
    let total = topics.as_array().map(|a| a.len()).unwrap_or(0);
    Ok(Json(json!({
        "status": row.get::<String, _>("status"), "topics": topics, "selection": row.get::<Value, _>("selection"),
        "manualBlockIds": row.get::<Vec<Uuid>, _>("manual_block_ids"),
        "summary": { "topics": total, "ready": ready, "needsReview": total - ready },
    })))
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct Selection {
    /// `topics` | `manual`
    pub mode: String,
    #[serde(default)]
    pub topic_ids: Vec<String>,
    #[serde(default)]
    pub manual_block_ids: Vec<Uuid>,
}

#[utoipa::path(put, path = "/v1/final-notes/{id}/recommendations/selection", tag = "studyStudio", params(("id" = Uuid, Path)),
    request_body = Selection, responses((status = 204)))]
pub async fn select(State(st): State<AppState>, caller: Caller, Path(id): Path<Uuid>, Json(req): Json<Selection>) -> Result<StatusCode, ApiError> {
    if !["topics", "manual"].contains(&req.mode.as_str()) || req.topic_ids.len() > 200 || req.manual_block_ids.len() > 5000 {
        return Err(ApiError::bad_request("mode must be topics or manual"));
    }
    final_notes::owned(&st, &caller, id).await?;
    sqlx::query("UPDATE recommendations SET selection = $2, manual_block_ids = $3 WHERE final_notes_id = $1")
        .bind(id).bind(json!({ "mode": req.mode, "topicIds": req.topic_ids })).bind(&req.manual_block_ids).execute(&st.notes).await?;
    Ok(StatusCode::NO_CONTENT)
}

/// Home "Recommended for Study Studio": finalized notes with ready topics and
/// no successful conversion yet.
pub async fn home_items(st: &AppState, caller: &Caller) -> Result<Value, ApiError> {
    Ok(sqlx::query_scalar(
        "SELECT COALESCE(json_agg(x ORDER BY x->>'finalizedAt' DESC), '[]') FROM ( \
           SELECT json_build_object('finalNotesId', f.id, 'sessionId', f.session_id, 'title', f.title, 'finalizedAt', f.finalized_at, \
                  'readyTopics', (SELECT count(*) FROM jsonb_array_elements(r.topics) t WHERE t->>'readiness' = 'ready')) AS x \
           FROM final_notes f JOIN recommendations r ON r.final_notes_id = f.id JOIN sessions s ON s.id = f.session_id \
           WHERE f.user_id = $1 AND r.status = 'ready' AND s.deleted_at IS NULL \
             AND NOT EXISTS (SELECT 1 FROM conversions c WHERE c.final_notes_id = f.id AND c.status IN ('building', 'done')) \
           ORDER BY f.finalized_at DESC LIMIT 5) q")
        .bind(caller.user_id).fetch_one(&st.notes).await?)
}

//! Study Studio Conversion (Panel 15) + reverse links. Nothing is created
//! and the source notes are never changed until the student presses
//! Generate; then OctoNotes charges once, hands the selected notes (Markdown
//! with source markers) to Study Studio's own pipeline, and follows the build.

use std::convert::Infallible;
use std::time::Duration;

use axum::extract::{Path, Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::sse::Event as SseEvent;
use axum::Json;
use octo_common::ApiError;
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::ai::{self, event, SseStream};
use crate::ctx::Caller;
use crate::jobs::{self, Job, JobResult};
use crate::realtime::Event;
use crate::routes::final_notes;
use crate::studio_client::{OnBehalf, StudioClient};
use crate::{outbox, pricing, AppState};

const ACTIVITIES: &[(&str, &str, i32)] = &[
    ("teachMe", "lessons", 0), // 0 = one per topic
    ("quizMe", "questions", 10),
    ("flashcards", "cards", 20),
    ("lightningRecall", "items", 10),
    ("scenarios", "scenarios", 3),
    ("mockExam", "exams", 1),
];
const MOCK_EXAM_MIN_BLOCKS: usize = 30;

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct CreateConversion {
    pub final_notes_id: Uuid,
    /// Defaults to the saved recommendation selection.
    pub topic_ids: Option<Vec<String>>,
    pub manual_block_ids: Option<Vec<Uuid>>,
}

async fn recommendation(st: &AppState, fid: Uuid) -> Result<(Value, Value, Vec<Uuid>), ApiError> {
    let r = sqlx::query("SELECT topics, selection, manual_block_ids FROM recommendations WHERE final_notes_id = $1 AND status = 'ready'")
        .bind(fid).fetch_optional(&st.notes).await?
        .ok_or_else(|| ApiError::new(StatusCode::CONFLICT, "recommendations are still being prepared").with_code("recommendations_pending"))?;
    Ok((
        r.get("topics"),
        r.get("selection"),
        r.get("manual_block_ids"),
    ))
}

#[utoipa::path(post, path = "/v1/conversions", tag = "studyStudio", request_body = CreateConversion,
    responses((status = 201, description = "The draft conversion (see GET)")))]
pub async fn create(
    State(st): State<AppState>,
    caller: Caller,
    Json(req): Json<CreateConversion>,
) -> Result<(StatusCode, Json<Value>), ApiError> {
    let fin = final_notes::owned(&st, &caller, req.final_notes_id).await?;
    let (topics, selection, manual) = recommendation(&st, fin.id).await?;
    let topic_ids: Vec<String> = req.topic_ids.unwrap_or_else(|| {
        selection["topicIds"]
            .as_array()
            .cloned()
            .unwrap_or_default()
            .into_iter()
            .filter_map(|v| v.as_str().map(str::to_string))
            .collect()
    });
    let manual = req.manual_block_ids.unwrap_or(manual);
    let chosen: Vec<&Value> = topics
        .as_array()
        .into_iter()
        .flatten()
        .filter(|t| {
            t["id"]
                .as_str()
                .is_some_and(|i| topic_ids.iter().any(|x| x == i))
        })
        .collect();
    if chosen.is_empty() && manual.is_empty() {
        return Err(ApiError::bad_request("select at least one topic or block"));
    }
    let blocks = fin.content["blocks"]
        .as_array()
        .map(|a| a.len())
        .unwrap_or(0);
    let activities: Vec<Value> = ACTIVITIES.iter().map(|(t, unit, n)| {
        let available = *t != "mockExam" || blocks >= MOCK_EXAM_MIN_BLOCKS;
        let count = if *n == 0 { chosen.len().max(1) as i32 } else { *n };
        json!({ "type": t, "unit": unit, "count": count, "enabled": available && *t != "mockExam", "available": available,
                "unavailableReason": if available { Value::Null } else { json!("Not enough material") } })
    }).collect();
    // Suggest updating a studio the student already has for these topics.
    let existing = chosen.iter().find_map(|t| {
        t["alreadyInStudio"]["studioId"]
            .as_str()
            .and_then(|s| Uuid::parse_str(s).ok())
    });
    let id: Uuid = sqlx::query_scalar(
        "INSERT INTO conversions (final_notes_id, user_id, topic_ids, manual_block_ids, activities, destination, target_studio_id) \
         VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING id")
        .bind(fin.id).bind(caller.user_id).bind(&topic_ids).bind(&manual).bind(Value::Array(activities))
        .bind(if existing.is_some() { "updateExisting" } else { "createNew" }).bind(existing)
        .fetch_one(&st.notes).await?;
    Ok((StatusCode::CREATED, Json(view(&st, &caller, id).await?)))
}

struct Conv {
    final_notes_id: Uuid,
    topic_ids: Vec<String>,
    manual: Vec<Uuid>,
    activities: Value,
    level: String,
    destination: String,
    target: Option<Uuid>,
    strategy: String,
    status: String,
    build: Option<Uuid>,
    error: Option<String>,
    charged: i32,
}

async fn load(st: &AppState, caller: &Caller, id: Uuid) -> Result<Conv, ApiError> {
    let r = sqlx::query("SELECT * FROM conversions WHERE id = $1 AND user_id = $2")
        .bind(id)
        .bind(caller.user_id)
        .fetch_optional(&st.notes)
        .await?
        .ok_or_else(|| ApiError::not_found("conversion not found"))?;
    Ok(Conv {
        final_notes_id: r.get("final_notes_id"),
        topic_ids: r.get("topic_ids"),
        manual: r.get("manual_block_ids"),
        activities: r.get("activities"),
        level: r.get("level"),
        destination: r.get("destination"),
        target: r.get("target_studio_id"),
        strategy: r.get("strategy"),
        status: r.get("status"),
        build: r.get("studio_build_id"),
        error: r.get("error"),
        charged: r.get("credits_charged"),
    })
}

fn learning_items(activities: &Value) -> i32 {
    activities
        .as_array()
        .into_iter()
        .flatten()
        .filter(|a| a["enabled"] == true)
        .map(|a| a["count"].as_i64().unwrap_or(0) as i32)
        .sum()
}

async fn estimate(st: &AppState, activities: &Value) -> i32 {
    pricing::price(st, "conversion_base").await
        + pricing::price(st, "conversion_item").await * learning_items(activities)
}

/// The selected blocks (topic sections + manual picks), in note order.
fn selected_blocks(
    content: &Value,
    topics: &Value,
    topic_ids: &[String],
    manual: &[Uuid],
) -> Vec<Value> {
    let mut ids: std::collections::HashSet<String> = manual.iter().map(|u| u.to_string()).collect();
    for t in topics.as_array().into_iter().flatten() {
        if t["id"]
            .as_str()
            .is_some_and(|i| topic_ids.iter().any(|x| x == i))
        {
            for b in t["blockIds"].as_array().into_iter().flatten() {
                if let Some(s) = b.as_str() {
                    ids.insert(s.to_string());
                }
            }
        }
    }
    content["blocks"]
        .as_array()
        .cloned()
        .unwrap_or_default()
        .into_iter()
        .filter(|b| b["id"].as_str().is_some_and(|i| ids.contains(i)))
        .collect()
}

async fn view(st: &AppState, caller: &Caller, id: Uuid) -> Result<Value, ApiError> {
    let c = load(st, caller, id).await?;
    let fin = final_notes::owned(st, caller, c.final_notes_id).await?;
    let (topics, _, _) = recommendation(st, fin.id).await?;
    let blocks = selected_blocks(&fin.content, &topics, &c.topic_ids, &c.manual);
    let count = |f: &dyn Fn(&Value) -> bool| blocks.iter().filter(|b| f(b)).count();
    let transcript = count(&|b| {
        !b["provenance"]["transcriptAnchor"].is_null() || b["origin"] == "fromTranscript"
    });
    let slides = count(&|b| b["origin"] == "fromSlide" || b["type"] == "slideRef");
    let diagrams = count(&|b| b["type"] == "diagram" || b["origin"] == "fromInk");
    let selected_topics: Vec<Value> = topics.as_array().into_iter().flatten()
        .filter(|t| t["id"].as_str().is_some_and(|i| c.topic_ids.iter().any(|x| x == i)))
        .map(|t| {
            let refs = t["counts"]["transcriptRefs"].as_i64().unwrap_or(0) + t["counts"]["slideRefs"].as_i64().unwrap_or(0);
            let coverage = if t["readiness"] == "ready" && refs >= 2 { "strong" } else if t["readiness"] == "ready" { "partial" } else { "weak" };
            json!({ "id": t["id"], "title": t["title"], "coverage": coverage, "counts": t["counts"], "alreadyInStudio": t["alreadyInStudio"] })
        }).collect();
    let existing = match (c.target, &st.studio) {
        (Some(sid), Some(pool)) => sqlx::query(
            "SELECT s.title, s.updated_at, (SELECT count(*) FROM generated_topics g WHERE g.studio_id = s.id) AS topics, \
                    (SELECT avg(p.mastery) FROM topic_progress p WHERE p.studio_id = s.id AND p.user_id = s.user_id) AS mastery, \
                    (SELECT max(p.updated_at) FROM topic_progress p WHERE p.studio_id = s.id) AS last_studied \
             FROM studios s WHERE s.id = $1 AND s.user_id = $2")
            .bind(sid).bind(caller.user_id).fetch_optional(pool).await?
            .map(|r| json!({ "studioId": sid, "title": r.get::<String, _>("title"), "topics": r.get::<i64, _>("topics"),
                             "mastery": r.get::<Option<f64>, _>("mastery"), "lastStudied": r.get::<Option<chrono::DateTime<chrono::Utc>>, _>("last_studied") })),
        _ => None,
    };
    let est = estimate(st, &c.activities).await;
    let balance = st.credits.balance(caller.user_id).await?;
    let enabled = c
        .activities
        .as_array()
        .map(|a| a.iter().filter(|x| x["enabled"] == true).count())
        .unwrap_or(0);
    Ok(json!({
        "id": id, "finalNotesId": c.final_notes_id, "status": c.status, "error": c.error, "studioBuildId": c.build, "creditsCharged": c.charged,
        "selection": { "topicIds": c.topic_ids, "manualBlockIds": c.manual },
        "materialStats": { "topics": selected_topics.len(), "blocks": blocks.len(), "transcriptRefs": transcript, "slides": slides, "diagrams": diagrams },
        "topics": selected_topics,
        "activities": c.activities, "level": c.level,
        "destination": c.destination, "targetStudioId": c.target, "existingStudio": existing, "strategy": c.strategy,
        "summary": { "topics": selected_topics.len(), "activityTypes": enabled, "learningItems": learning_items(&c.activities), "sourceConnections": transcript + slides },
        "creditEstimate": est, "balance": balance,
    }))
}

#[utoipa::path(get, path = "/v1/conversions/{id}", tag = "studyStudio", params(("id" = Uuid, Path)), responses((status = 200)))]
pub async fn get(
    State(st): State<AppState>,
    caller: Caller,
    Path(id): Path<Uuid>,
) -> Result<Json<Value>, ApiError> {
    Ok(Json(view(&st, &caller, id).await?))
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct UpdateConversion {
    /// `foundation` | `balanced` | `challenging`
    pub level: Option<String>,
    /// `[{type, count, enabled}]` — only the listed activities change.
    #[schema(value_type = Option<Vec<Object>>)]
    pub activities: Option<Vec<Value>>,
    /// `createNew` | `updateExisting`
    pub destination: Option<String>,
    pub target_studio_id: Option<Uuid>,
    /// `addNew` | `updateMatching` | `keepExisting`
    pub strategy: Option<String>,
}

#[utoipa::path(patch, path = "/v1/conversions/{id}", tag = "studyStudio", params(("id" = Uuid, Path)), request_body = UpdateConversion,
    responses((status = 200)))]
pub async fn update(
    State(st): State<AppState>,
    caller: Caller,
    Path(id): Path<Uuid>,
    Json(req): Json<UpdateConversion>,
) -> Result<Json<Value>, ApiError> {
    let c = load(&st, &caller, id).await?;
    if c.status != "draft" {
        return Err(
            ApiError::new(StatusCode::CONFLICT, "conversion already started")
                .with_code("conversion_started"),
        );
    }
    if req
        .level
        .as_deref()
        .is_some_and(|l| !["foundation", "balanced", "challenging"].contains(&l))
    {
        return Err(ApiError::bad_request(
            "level must be foundation, balanced or challenging",
        ));
    }
    if req
        .destination
        .as_deref()
        .is_some_and(|d| !["createNew", "updateExisting"].contains(&d))
    {
        return Err(ApiError::bad_request(
            "destination must be createNew or updateExisting",
        ));
    }
    if req
        .strategy
        .as_deref()
        .is_some_and(|s| !["addNew", "updateMatching", "keepExisting"].contains(&s))
    {
        return Err(ApiError::bad_request(
            "strategy must be addNew, updateMatching or keepExisting",
        ));
    }
    if let Some(sid) = req.target_studio_id {
        let pool = st
            .studio
            .as_ref()
            .ok_or_else(|| ApiError::unavailable("Study Studio is not connected"))?;
        let ok: Option<Uuid> =
            sqlx::query_scalar("SELECT id FROM studios WHERE id = $1 AND user_id = $2")
                .bind(sid)
                .bind(caller.user_id)
                .fetch_optional(pool)
                .await?;
        ok.ok_or_else(|| ApiError::not_found("studio not found"))?;
    }
    let mut activities = c.activities.clone();
    for change in req.activities.unwrap_or_default() {
        let kind = change["type"]
            .as_str()
            .ok_or_else(|| ApiError::bad_request("activity type missing"))?;
        let a = activities
            .as_array_mut()
            .and_then(|l| l.iter_mut().find(|x| x["type"] == kind))
            .ok_or_else(|| ApiError::bad_request(format!("unknown activity '{kind}'")))?;
        if let Some(n) = change.get("count").and_then(Value::as_i64) {
            if !(1..=100).contains(&n) {
                return Err(ApiError::bad_request("count must be 1..100"));
            }
            a["count"] = json!(n);
        }
        if let Some(e) = change.get("enabled").and_then(Value::as_bool) {
            if e && a["available"] == false {
                return Err(ApiError::bad_request(format!(
                    "{kind} is not available: {}",
                    a["unavailableReason"]
                ))
                .with_code("activity_unavailable"));
            }
            a["enabled"] = json!(e);
        }
    }
    let destination = req.destination.unwrap_or(c.destination);
    let target = req.target_studio_id.or(c.target);
    if destination == "updateExisting" && target.is_none() {
        return Err(ApiError::bad_request("updateExisting needs targetStudioId"));
    }
    sqlx::query("UPDATE conversions SET level = $2, activities = $3, destination = $4, target_studio_id = $5, strategy = $6 WHERE id = $1")
        .bind(id).bind(req.level.unwrap_or(c.level)).bind(&activities).bind(&destination)
        .bind(if destination == "createNew" { None } else { target }).bind(req.strategy.unwrap_or(c.strategy))
        .execute(&st.notes).await?;
    Ok(Json(view(&st, &caller, id).await?))
}

/// Markdown for Study Studio's ingest, with source markers so generated
/// lessons keep provenance.
pub fn markdown_for_studio(title: &str, blocks: &[Value]) -> String {
    let mut out = format!("# {title}\n\n");
    for b in blocks {
        let text = b["text"].as_str().unwrap_or("");
        let mut marker = String::new();
        if let Some(t) = b["provenance"]["transcriptAnchor"]["time"].as_str() {
            marker = format!(" [Transcript {t}]");
        } else if let Some(loc) = b["provenance"]["sourceRef"]["location"].as_str() {
            marker = format!(" [{loc}]");
        }
        let line = match b["type"].as_str().unwrap_or("") {
            "h1" => format!("## {text}"),
            "h2" => format!("### {text}"),
            "h3" => format!("#### {text}"),
            "bulleted" | "numbered" | "checklist" => format!("- {text}{marker}"),
            "definition" => format!("**Definition:** {text}{marker}"),
            "examHint" => format!("**Exam hint:** {text}{marker}"),
            "question" => format!("**Question:** {text}{marker}"),
            _ => format!("{text}{marker}"),
        };
        out.push_str(&line);
        out.push_str("\n\n");
    }
    out
}

#[utoipa::path(post, path = "/v1/conversions/{id}/generate", tag = "studyStudio", params(("id" = Uuid, Path)),
    responses((status = 202, description = "{studioId, buildId, creditsCharged}"), (status = 402, description = "insufficient_credits")))]
pub async fn generate(
    State(st): State<AppState>,
    caller: Caller,
    Path(id): Path<Uuid>,
    headers: HeaderMap,
) -> Result<(StatusCode, Json<Value>), ApiError> {
    let c = load(&st, &caller, id).await?;
    if c.status != "draft" {
        // Retried request: report what already happened.
        return Ok((
            StatusCode::ACCEPTED,
            Json(
                json!({ "status": c.status, "studioId": c.target, "buildId": c.build, "creditsCharged": c.charged }),
            ),
        ));
    }
    let client = StudioClient::new(
        st.http.clone(),
        st.config.study_studio_api_url.clone(),
        st.config.study_studio_service_key.clone(),
    );
    if matches!(client, StudioClient::None) {
        return Err(
            ApiError::unavailable("Study Studio is not connected").with_code("studio_unavailable")
        );
    }
    let fin = final_notes::owned(&st, &caller, c.final_notes_id).await?;
    let (topics, _, _) = recommendation(&st, fin.id).await?;
    let blocks = selected_blocks(&fin.content, &topics, &c.topic_ids, &c.manual);
    let price = estimate(&st, &c.activities).await;
    st.credits.precheck(caller.user_id, price).await?;
    // Claim the draft so a double click can't start two builds.
    let claimed = sqlx::query(
        "UPDATE conversions SET status = 'building' WHERE id = $1 AND status = 'draft'",
    )
    .bind(id)
    .execute(&st.notes)
    .await?;
    if claimed.rows_affected() == 0 {
        return Err(
            ApiError::new(StatusCode::CONFLICT, "conversion already started")
                .with_code("conversion_started"),
        );
    }
    let charge_ref = format!("octonotes:conversion:{id}");
    let charged = match pricing::charge(
        &st,
        caller.user_id,
        price,
        &charge_ref,
        "OctoNotes → Study Studio conversion",
    )
    .await
    {
        Ok(n) => n,
        Err(e) => {
            sqlx::query("UPDATE conversions SET status = 'draft' WHERE id = $1")
                .bind(id)
                .execute(&st.notes)
                .await?;
            return Err(e);
        }
    };
    let who = OnBehalf {
        bearer: headers
            .get("authorization")
            .and_then(|v| v.to_str().ok())
            .and_then(|s| s.strip_prefix("Bearer "))
            .map(str::to_string),
        user_id: Some(caller.user_id),
    };
    let result: Result<(Uuid, Uuid), String> = async {
        let studio = match (c.destination.as_str(), c.target) {
            ("updateExisting", Some(t)) => t,
            _ => client.create_studio(&who, &fin.title, None).await?,
        };
        let slug: String = fin
            .title
            .chars()
            .map(|c| {
                if c.is_alphanumeric() {
                    c.to_ascii_lowercase()
                } else {
                    '-'
                }
            })
            .collect::<String>()
            .trim_matches('-')
            .chars()
            .take(50)
            .collect();
        client
            .upload(
                &who,
                studio,
                &format!("octonotes-{slug}-v{}.md", fin.version),
                markdown_for_studio(&fin.title, &blocks).into_bytes(),
            )
            .await?;
        let build = client.start_build(&who, studio).await?;
        Ok((studio, build))
    }
    .await;
    match result {
        Ok((studio, build)) => {
            let mut tx = st.notes.begin().await?;
            sqlx::query("UPDATE conversions SET target_studio_id = $2, studio_build_id = $3, credits_charged = $4, error = NULL WHERE id = $1")
                .bind(id).bind(studio).bind(build).bind(charged).execute(&mut *tx).await?;
            for t in topics.as_array().into_iter().flatten().filter(|t| {
                t["id"]
                    .as_str()
                    .is_some_and(|i| c.topic_ids.iter().any(|x| x == i))
            }) {
                let ids: Vec<Uuid> = t["blockIds"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .filter_map(|b| b.as_str().and_then(|s| Uuid::parse_str(s).ok()))
                    .collect();
                sqlx::query("INSERT INTO studio_links (user_id, studio_id, topic_title, final_notes_id, conversion_id, block_ids) VALUES ($1,$2,$3,$4,$5,$6)")
                    .bind(caller.user_id).bind(studio).bind(t["title"].as_str()).bind(fin.id).bind(id).bind(&ids).execute(&mut *tx).await?;
            }
            if !c.manual.is_empty() {
                sqlx::query("INSERT INTO studio_links (user_id, studio_id, topic_title, final_notes_id, conversion_id, block_ids) VALUES ($1,$2,NULL,$3,$4,$5)")
                    .bind(caller.user_id).bind(studio).bind(fin.id).bind(id).bind(&c.manual).execute(&mut *tx).await?;
            }
            outbox::record(
                &mut tx,
                caller.user_id,
                "conversion.started",
                Some(id),
                json!({ "studioId": studio, "finalNotesId": fin.id }),
            )
            .await?;
            jobs::enqueue_tx(
                &mut tx,
                Some(caller.user_id),
                "conversion.follow",
                json!({ "conversionId": id }),
                Some(&format!("follow:{id}:0")),
            )
            .await?;
            tx.commit().await?;
            Ok((
                StatusCode::ACCEPTED,
                Json(
                    json!({ "status": "building", "studioId": studio, "buildId": build, "creditsCharged": charged }),
                ),
            ))
        }
        Err(e) => {
            let _ = st
                .credits
                .refund(
                    caller.user_id,
                    &charge_ref,
                    "Study Studio build could not start",
                )
                .await;
            sqlx::query("UPDATE conversions SET status = 'failed', error = $2 WHERE id = $1")
                .bind(id)
                .bind(&e)
                .execute(&st.notes)
                .await?;
            Err(ApiError::bad_gateway(e).with_code("studio_failed"))
        }
    }
}

/// Follows the Study Studio build (read-only on its DB) until it ends;
/// refunds if it failed.
pub async fn job_follow(st: AppState, job: Job) -> JobResult {
    let id: Uuid =
        serde_json::from_value(job.payload["conversionId"].clone()).map_err(|e| e.to_string())?;
    let row = sqlx::query(
        "SELECT user_id, status, studio_build_id, created_at FROM conversions WHERE id = $1",
    )
    .bind(id)
    .fetch_optional(&st.notes)
    .await
    .map_err(|e| e.to_string())?;
    let Some(row) = row else { return Ok(()) };
    let (user, status, build): (Uuid, String, Option<Uuid>) = (
        row.get("user_id"),
        row.get("status"),
        row.get("studio_build_id"),
    );
    if status != "building" {
        return Ok(());
    }
    let (Some(build), Some(pool)) = (build, &st.studio) else {
        return Ok(());
    };
    let b = sqlx::query("SELECT status, error FROM studio_builds WHERE id = $1")
        .bind(build)
        .fetch_optional(pool)
        .await
        .map_err(|e| e.to_string())?;
    let (bstatus, berror): (String, Option<String>) = match b {
        Some(r) => (r.get("status"), r.get("error")),
        None => ("queued".into(), None),
    };
    let old = chrono::Utc::now() - row.get::<chrono::DateTime<chrono::Utc>, _>("created_at")
        > chrono::Duration::hours(2);
    let finished = match bstatus.as_str() {
        "done" => Some(("done", None)),
        "failed" => Some((
            "failed",
            berror.or(Some("Study Studio build failed".into())),
        )),
        _ if old => Some(("failed", Some("Study Studio build timed out".into()))),
        _ => None,
    };
    match finished {
        Some((s, err)) => {
            if s == "failed" {
                let _ = st
                    .credits
                    .refund(
                        user,
                        &format!("octonotes:conversion:{id}"),
                        "Study Studio build failed",
                    )
                    .await;
            }
            let mut tx = st.notes.begin().await.map_err(|e| e.to_string())?;
            sqlx::query("UPDATE conversions SET status = $2, error = $3 WHERE id = $1")
                .bind(id)
                .bind(s)
                .bind(&err)
                .execute(&mut *tx)
                .await
                .map_err(|e| e.to_string())?;
            outbox::record(
                &mut tx,
                user,
                if s == "done" {
                    "conversion.done"
                } else {
                    "conversion.failed"
                },
                Some(id),
                json!({ "error": err }),
            )
            .await
            .map_err(|e| e.to_string())?;
            tx.commit().await.map_err(|e| e.to_string())?;
            st.hub
                .user(
                    user,
                    Event::new(
                        "conversion.state",
                        json!({ "conversionId": id, "status": s, "error": err }),
                        None,
                    ),
                )
                .await;
        }
        None => {
            // Check again in 10 s (a fresh job, so retries/backoff don't apply).
            jobs::enqueue_at(
                &st.notes,
                Some(user),
                "conversion.follow",
                json!({ "conversionId": id }),
                10,
            )
            .await
            .map_err(|e| e.to_string())?;
        }
    }
    Ok(())
}

#[utoipa::path(get, path = "/v1/conversions/{id}/progress", tag = "studyStudio", params(("id" = Uuid, Path)),
    responses((status = 200, description = "SSE: progress {status, stage, lessonsDone, lessonsTotal} … done | error")))]
pub async fn progress(
    State(st): State<AppState>,
    caller: Caller,
    Path(id): Path<Uuid>,
) -> Result<SseStream, ApiError> {
    let c = load(&st, &caller, id).await?;
    let studio = c.target;
    let build = c.build;
    let stream = async_stream::stream! {
        let mut last = Value::Null;
        for _ in 0..1800 {
            let conv: Option<(String, Option<String>)> = sqlx::query_as("SELECT status, error FROM conversions WHERE id = $1").bind(id).fetch_optional(&st.notes).await.ok().flatten();
            let Some((status, err)) = conv else { yield Ok::<SseEvent, Infallible>(SseEvent::default().event("error").data("{}")); return; };
            let mut p = json!({ "status": status, "studioId": studio, "buildId": build });
            if let (Some(b), Some(pool)) = (build, &st.studio) {
                if let Ok(Some(r)) = sqlx::query("SELECT status, stage, lessons_done, lessons_total FROM studio_builds WHERE id = $1").bind(b).fetch_optional(pool).await {
                    p["stage"] = json!(r.get::<String, _>("stage"));
                    p["buildStatus"] = json!(r.get::<String, _>("status"));
                    p["lessonsDone"] = json!(r.get::<i32, _>("lessons_done"));
                    p["lessonsTotal"] = json!(r.get::<i32, _>("lessons_total"));
                }
            }
            if p != last { last = p.clone(); yield event("progress", p); }
            match status.as_str() {
                "done" => { yield event("done", json!({ "studioId": studio, "openPath": studio.map(|s| format!("/study/studios/{s}")) })); return; }
                "failed" => { yield event("error", json!({ "message": err })); return; }
                "draft" => { yield event("error", json!({ "message": "not started" })); return; }
                _ => tokio::time::sleep(Duration::from_millis(1000)).await,
            }
        }
    };
    Ok(ai::sse(stream))
}

#[derive(Debug, Deserialize, utoipa::IntoParams)]
#[serde(rename_all = "camelCase")]
pub struct LinksQuery {
    pub studio_id: Uuid,
    /// Match by Study Studio topic id or topic title.
    pub topic_id: Option<String>,
    pub topic_title: Option<String>,
}

/// Study Studio's "View in Notes": which final notes and blocks a studio
/// (or one of its topics) came from.
#[utoipa::path(get, path = "/v1/links", tag = "studyStudio", params(LinksQuery), responses((status = 200)))]
pub async fn links(
    State(st): State<AppState>,
    caller: Caller,
    Query(q): Query<LinksQuery>,
) -> Result<Json<Value>, ApiError> {
    Ok(Json(sqlx::query_scalar(
        "SELECT COALESCE(json_agg(json_build_object('finalNotesId', l.final_notes_id, 'sessionId', f.session_id, 'title', f.title, \
             'version', f.version, 'topicTitle', l.topic_title, 'blockIds', l.block_ids, 'openPath', '/notes/final?id=' || l.final_notes_id) \
             ORDER BY l.created_at DESC), '[]') \
         FROM studio_links l JOIN final_notes f ON f.id = l.final_notes_id \
         WHERE l.user_id = $1 AND l.studio_id = $2 \
           AND ($3::text IS NULL OR l.topic_id = $3) AND ($4::text IS NULL OR lower(l.topic_title) = lower($4))")
        .bind(caller.user_id).bind(q.studio_id).bind(&q.topic_id).bind(&q.topic_title).fetch_one(&st.notes).await?))
}

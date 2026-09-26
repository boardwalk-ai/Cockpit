//! Smart Organization (Panel 11): preview-based and reversible. A preview
//! never moves anything; Apply moves the chosen blocks as ONE pass that Undo
//! reverses (blocks the student edited since are left alone and reported).

use std::collections::{HashMap, HashSet};

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;
use octo_common::llm::{parse_json_loose, ChatOptions, Message};
use octo_common::ApiError;
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::ai::{self, clip, Llm, Role};
use crate::ctx::Caller;
use crate::realtime::Event;
use crate::routes::blocks::{self, Block, BLOCK_COLUMNS};
use crate::{access, positions, pricing, revs, AppState};

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct PreviewRequest {
    /// `selectedBlocks` | `currentSection` | `entireNote` (default)
    pub scope: Option<String>,
    pub block_ids: Option<Vec<Uuid>>,
}

/// Deterministic proposal used without a model: outline from headings,
/// categories by block type, and "questions go to a Student Questions
/// section at the end".
fn offline_plan(blocks: &[Block]) -> Value {
    let outline: Vec<Value> = blocks.iter().filter(|b| b.kind == "h1" || b.kind == "h2").map(|b| json!({ "title": b.text, "children": [] })).collect();
    let count = |kinds: &[&str]| blocks.iter().filter(|b| kinds.contains(&b.kind.as_str())).count();
    let categories = json!([
        { "label": "Topics", "count": count(&["h1", "h2", "h3"]) },
        { "label": "Definitions", "count": count(&["definition", "keyIdea"]) },
        { "label": "Questions", "count": count(&["question"]) },
        { "label": "Exam Hints", "count": count(&["examHint"]) },
    ]);
    let last = blocks.last().map(|b| b.id);
    let questions: Vec<&Block> = blocks.iter().filter(|b| b.kind == "question" && Some(b.id) != last).collect();
    let suggestions: Vec<Value> = if questions.is_empty() {
        Vec::new()
    } else {
        let mut after = last;
        let moves: Vec<Value> = questions.iter().map(|q| { let m = json!({ "blockId": q.id, "afterBlockId": after }); after = Some(q.id); m }).collect();
        vec![json!({ "title": "Group student questions at the end", "reason": "Questions are easier to review together.", "confidence": "high", "moves": moves })]
    };
    json!({ "outline": outline, "categories": categories, "suggestions": suggestions })
}

#[utoipa::path(post, path = "/v1/sessions/{id}/organize/preview", tag = "organize", params(("id" = Uuid, Path)), request_body = PreviewRequest,
    responses((status = 200, description = "{passId, outline, categories, suggestions[{id,title,reason,confidence,moves,blockLabels}], summary}")))]
pub async fn preview(State(st): State<AppState>, caller: Caller, Path(session_id): Path<Uuid>, Json(req): Json<PreviewRequest>) -> Result<Json<Value>, ApiError> {
    let scope = req.scope.unwrap_or_else(|| "entireNote".into());
    if !["selectedBlocks", "currentSection", "entireNote"].contains(&scope.as_str()) {
        return Err(ApiError::bad_request("scope must be selectedBlocks, currentSection or entireNote"));
    }
    let mut conn = st.notes.acquire().await?;
    access::session(&mut conn, &caller, session_id).await?;
    let all = blocks::load_blocks(&mut conn, session_id, None).await?;
    drop(conn);
    let in_scope: Vec<Block> = match (&scope[..], &req.block_ids) {
        ("selectedBlocks" | "currentSection", Some(ids)) => all.iter().filter(|b| ids.contains(&b.id)).cloned().collect(),
        _ => all.clone(),
    };
    if in_scope.len() < 2 {
        return Err(ApiError::bad_request("need at least two blocks to organize"));
    }
    let price = pricing::price(&st, "organize").await;
    ai::guard(&st, &caller, price).await?;
    let listing = in_scope.iter().enumerate().map(|(i, b)| format!("{} | {} | {} | {}", i + 1, b.id, b.kind, clip(&b.text, 160))).collect::<Vec<_>>().join("\n");
    let messages = vec![
        Message::system("You organize a student's lecture notes. Never rewrite text; only propose moving whole blocks. Reply with JSON only: \
{\"outline\": [{\"title\": string, \"children\": [{\"title\": string}]}], \"categories\": [{\"label\": string, \"count\": number}], \
\"suggestions\": [{\"title\": string, \"reason\": string, \"confidence\": \"high\"|\"medium\"|\"low\", \"moves\": [{\"blockId\": string, \"afterBlockId\": string|null}]}]}. \
Use only block ids from the list; afterBlockId null means move to the very top. Propose at most 8 suggestions; mark uncertain placements low."),
        Message::user(format!("Blocks (n | id | type | text):\n{listing}")),
    ];
    let run = ai::start_run(&st, &caller, Some(session_id), "organize", Some(&scope), &json!([{ "type": "blocks", "count": in_scope.len() }])).await?;
    let llm = Llm::for_role(&st, Role::Primary).await;
    let model = llm.model_name();
    let plan = offline_plan(&in_scope).to_string();
    let (text, usage) = match llm.complete(&messages, &ChatOptions { temperature: Some(0.2), max_tokens: Some(2000), json: true }, || plan).await {
        Ok(r) => r,
        Err(e) => { ai::fail_run(&st, run, &e.message).await; return Err(e); }
    };
    let raw = parse_json_loose(&text).unwrap_or_else(|| json!({}));

    // Keep only moves on real blocks of this session.
    let known: HashSet<Uuid> = all.iter().map(|b| b.id).collect();
    let label: HashMap<Uuid, String> = all.iter().enumerate().map(|(i, b)| (b.id, format!("Block {} · {}", i + 1, clip(&b.text, 40)))).collect();
    let mut suggestions = Vec::new();
    for (i, s) in raw["suggestions"].as_array().cloned().unwrap_or_default().into_iter().enumerate() {
        let moves: Vec<Value> = s["moves"].as_array().cloned().unwrap_or_default().into_iter().filter(|m| {
            let b = m["blockId"].as_str().and_then(|x| Uuid::parse_str(x).ok());
            let a = m["afterBlockId"].as_str().map(|x| Uuid::parse_str(x).ok());
            matches!(b, Some(b) if known.contains(&b)) && !matches!(a, Some(None)) && a.flatten().is_none_or(|a| known.contains(&a) && Some(a) != b)
        }).collect();
        if moves.is_empty() {
            continue;
        }
        let confidence = s["confidence"].as_str().filter(|c| ["high", "medium", "low"].contains(c)).unwrap_or("medium");
        let labels: Vec<String> = moves.iter().filter_map(|m| m["blockId"].as_str().and_then(|x| Uuid::parse_str(x).ok()).and_then(|b| label.get(&b).cloned())).collect();
        suggestions.push(json!({
            "id": format!("s{}", i + 1), "title": s["title"], "reason": s["reason"], "confidence": confidence,
            // Low confidence starts unchecked: "Placement uncertain — review recommended".
            "selected": confidence != "low", "moves": moves, "blockLabels": labels,
        }));
    }
    let moved: HashSet<String> = suggestions.iter().flat_map(|s| s["moves"].as_array().cloned().unwrap_or_default()).filter_map(|m| m["blockId"].as_str().map(str::to_string)).collect();
    let proposals = json!({ "outline": raw["outline"], "categories": raw["categories"], "suggestions": suggestions });
    let pass_id: Uuid = sqlx::query_scalar("INSERT INTO org_passes (session_id, user_id, scope, proposals, ai_run_id) VALUES ($1,$2,$3,$4,$5) RETURNING id")
        .bind(session_id).bind(caller.user_id).bind(&scope).bind(&proposals).bind(run).fetch_one(&st.notes).await?;
    let result = json!({
        "passId": pass_id, "outline": proposals["outline"], "categories": proposals["categories"], "suggestions": proposals["suggestions"],
        "summary": { "suggestions": proposals["suggestions"].as_array().map(|a| a.len()).unwrap_or(0), "blocksMoved": moved.len(),
                     "sections": proposals["outline"].as_array().map(|a| a.len()).unwrap_or(0),
                     "categories": proposals["categories"].as_array().map(|a| a.len()).unwrap_or(0) },
    });
    let charged = ai::finish_run(&st, &caller, run, ai::Outcome { kind: "organize", response: &result, model: &model, usage: &usage, price }).await?;
    Ok(Json(json!({ "creditsCharged": charged, "preview": result })))
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ApplyRequest {
    /// Which suggestions (`s1`, `s2` …). Omit with `all: true` for Apply All.
    pub suggestion_ids: Option<Vec<String>>,
    #[serde(default)]
    pub all: bool,
}

#[utoipa::path(post, path = "/v1/organize/{id}/apply", tag = "organize", params(("id" = Uuid, Path)), request_body = ApplyRequest,
    responses((status = 200, description = "{moved: blockId[], rev}")))]
pub async fn apply(State(st): State<AppState>, caller: Caller, Path(pass_id): Path<Uuid>, Json(req): Json<ApplyRequest>) -> Result<Json<Value>, ApiError> {
    let mut tx = st.notes.begin().await?;
    let row = sqlx::query("SELECT session_id, proposals, status FROM org_passes WHERE id = $1 AND user_id = $2 FOR UPDATE")
        .bind(pass_id).bind(caller.user_id).fetch_optional(&mut *tx).await?.ok_or_else(|| ApiError::not_found("organization pass not found"))?;
    let (session_id, proposals, status): (Uuid, Value, String) = (row.get("session_id"), row.get("proposals"), row.get("status"));
    if status != "preview" {
        return Err(ApiError::new(StatusCode::CONFLICT, format!("pass already {status}")).with_code("pass_closed"));
    }
    access::writable_session(&mut tx, &caller, session_id).await?;
    let chosen: Vec<Value> = proposals["suggestions"].as_array().cloned().unwrap_or_default().into_iter()
        .filter(|s| req.all || req.suggestion_ids.as_ref().is_some_and(|ids| ids.iter().any(|i| Some(i.as_str()) == s["id"].as_str())))
        .collect();
    if chosen.is_empty() {
        return Err(ApiError::bad_request("no suggestions selected"));
    }
    revs::lock(&mut tx, session_id, revs::BLOCKS).await?;
    let before: Vec<(Uuid, String)> = sqlx::query_as("SELECT id, position FROM blocks WHERE session_id = $1 AND deleted_at IS NULL")
        .bind(session_id).fetch_all(&mut *tx).await?;
    let mut moved = Vec::new();
    let mut after_revision: HashMap<String, i64> = HashMap::new();
    for m in chosen.iter().flat_map(|s| s["moves"].as_array().cloned().unwrap_or_default()) {
        let Some(block_id) = m["blockId"].as_str().and_then(|x| Uuid::parse_str(x).ok()) else { continue };
        let anchor = m["afterBlockId"].as_str().and_then(|x| Uuid::parse_str(x).ok());
        let anchor_pos: Option<String> = match anchor {
            Some(a) => sqlx::query_scalar("SELECT position FROM blocks WHERE id = $1 AND session_id = $2 AND deleted_at IS NULL").bind(a).bind(session_id).fetch_optional(&mut *tx).await?,
            None => None,
        };
        if anchor.is_some() && anchor_pos.is_none() {
            continue; // anchor deleted since the preview
        }
        let next: Option<String> = sqlx::query_scalar(
            "SELECT position FROM blocks WHERE session_id = $1 AND deleted_at IS NULL AND id <> $2 AND ($3::text IS NULL OR position > $3) ORDER BY position LIMIT 1")
            .bind(session_id).bind(block_id).bind(&anchor_pos).fetch_optional(&mut *tx).await?;
        let pos = positions::between(anchor_pos.as_deref(), next.as_deref());
        let rev = revs::bump(&mut tx, session_id, revs::BLOCKS).await?;
        let b = sqlx::query_as::<_, Block>(&format!(
            "UPDATE blocks SET position = $2, revision = revision + 1, layer_rev = $3 WHERE id = $1 AND session_id = $4 AND deleted_at IS NULL RETURNING {BLOCK_COLUMNS}"))
            .bind(block_id).bind(&pos).bind(rev).bind(session_id).fetch_optional(&mut *tx).await?;
        if let Some(b) = b {
            blocks::snapshot(&mut tx, &caller, &b, "move", None).await?;
            after_revision.insert(b.id.to_string(), b.revision);
            moved.push(b.id);
        }
    }
    let snapshot = json!({ "positions": before.iter().map(|(id, p)| (id.to_string(), json!(p))).collect::<serde_json::Map<_, _>>(), "afterRevision": after_revision });
    let applied: Vec<String> = chosen.iter().filter_map(|s| s["id"].as_str().map(str::to_string)).collect();
    sqlx::query("UPDATE org_passes SET status = 'applied', applied_ids = $2, before_snapshot = $3 WHERE id = $1")
        .bind(pass_id).bind(&applied).bind(&snapshot).execute(&mut *tx).await?;
    let rev = revs::current(&mut tx, session_id, revs::BLOCKS).await?;
    tx.commit().await?;
    st.hub.session(session_id, Event::new("block.changed", json!({ "blockIds": moved, "organizePassId": pass_id }), Some(rev))).await;
    Ok(Json(json!({ "moved": moved, "rev": rev })))
}

#[utoipa::path(post, path = "/v1/organize/{id}/undo", tag = "organize", params(("id" = Uuid, Path)),
    responses((status = 200, description = "{restored: blockId[], skipped: blockId[] (edited since)}")))]
pub async fn undo(State(st): State<AppState>, caller: Caller, Path(pass_id): Path<Uuid>) -> Result<Json<Value>, ApiError> {
    let mut tx = st.notes.begin().await?;
    let row = sqlx::query("SELECT session_id, before_snapshot, status FROM org_passes WHERE id = $1 AND user_id = $2 FOR UPDATE")
        .bind(pass_id).bind(caller.user_id).fetch_optional(&mut *tx).await?.ok_or_else(|| ApiError::not_found("organization pass not found"))?;
    let (session_id, snap, status): (Uuid, Option<Value>, String) = (row.get("session_id"), row.get("before_snapshot"), row.get("status"));
    if status != "applied" {
        return Err(ApiError::new(StatusCode::CONFLICT, "only an applied pass can be undone").with_code("pass_not_applied"));
    }
    access::writable_session(&mut tx, &caller, session_id).await?;
    revs::lock(&mut tx, session_id, revs::BLOCKS).await?;
    let snap = snap.unwrap_or_default();
    let (mut restored, mut skipped) = (Vec::new(), Vec::new());
    for (id, after_rev) in snap["afterRevision"].as_object().cloned().unwrap_or_default() {
        let block_id = Uuid::parse_str(&id).map_err(|_| ApiError::internal("bad snapshot"))?;
        let Some(old_pos) = snap["positions"][&id].as_str() else { continue };
        let rev = revs::bump(&mut tx, session_id, revs::BLOCKS).await?;
        let b = sqlx::query_as::<_, Block>(&format!(
            "UPDATE blocks SET position = $2, revision = revision + 1, layer_rev = $3 WHERE id = $1 AND revision = $4 AND deleted_at IS NULL RETURNING {BLOCK_COLUMNS}"))
            .bind(block_id).bind(old_pos).bind(rev).bind(after_rev.as_i64().unwrap_or(-1)).fetch_optional(&mut *tx).await?;
        match b {
            Some(b) => { blocks::snapshot(&mut tx, &caller, &b, "move", None).await?; restored.push(block_id); }
            None => skipped.push(block_id),
        }
    }
    sqlx::query("UPDATE org_passes SET status = 'undone' WHERE id = $1").bind(pass_id).execute(&mut *tx).await?;
    let rev = revs::current(&mut tx, session_id, revs::BLOCKS).await?;
    tx.commit().await?;
    st.hub.session(session_id, Event::new("block.changed", json!({ "blockIds": restored }), Some(rev))).await;
    Ok(Json(json!({ "restored": restored, "skipped": skipped })))
}

#[utoipa::path(post, path = "/v1/organize/{id}/dismiss", tag = "organize", params(("id" = Uuid, Path)), responses((status = 204)))]
pub async fn dismiss(State(st): State<AppState>, caller: Caller, Path(pass_id): Path<Uuid>) -> Result<StatusCode, ApiError> {
    let res = sqlx::query("UPDATE org_passes SET status = 'dismissed' WHERE id = $1 AND user_id = $2 AND status = 'preview'")
        .bind(pass_id).bind(caller.user_id).execute(&st.notes).await?;
    if res.rows_affected() == 0 {
        return Err(ApiError::not_found("preview not found"));
    }
    Ok(StatusCode::NO_CONTENT)
}

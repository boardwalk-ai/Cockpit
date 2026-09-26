//! AI in the notes (Panels 5, 9) + Relevant Data + Summarize (Panel 3 hub).
//!
//! AI output never lands in the notes by itself: suggestions and command
//! results are stored separately, and only an explicit apply/insert creates
//! (or, for "Replace Selection", edits with the block's current revision) a
//! block — always marked `aiInsertedByStudent` with its sources kept.

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{DateTime, Utc};
use futures::StreamExt;
use octo_common::llm::{parse_json_loose, ChatOptions, Message, Usage};
use octo_common::ApiError;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sqlx::Row;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::ai::{self, clip, event, Llm, Role, SseStream};
use crate::ctx::Caller;
use crate::realtime::Event;
use crate::retrieval::{self, Passage};
use crate::routes::blocks::{self, Block, NewServerBlock, BLOCK_COLUMNS};
use crate::{access, pricing, revs, AppState};

const SUGGEST_ACTIONS: &[&str] = &["explain", "expand", "simplify", "keyword", "summarize"];

fn sources_json(passages: &[Passage]) -> Value {
    Value::Array(
        passages
            .iter()
            .map(|p| json!({ "kind": p.kind, "sourceId": p.source_id, "label": retrieval::label(p), "locator": p.locator, "excerpt": clip(&p.content, 280) }))
            .collect(),
    )
}

fn context_text(passages: &[Passage]) -> String {
    passages
        .iter()
        .enumerate()
        .map(|(i, p)| {
            format!(
                "[{}] ({}) {}",
                i + 1,
                retrieval::label(p),
                clip(&p.content, 1200)
            )
        })
        .collect::<Vec<_>>()
        .join("\n\n")
}

const GROUNDING: &str = "You help a university student with their lecture notes. Use ONLY the numbered sources; \
cite them like [1]. If the sources don't cover something, say so briefly instead of guessing. Write clearly, like an \
academic study note — no chit-chat, no preamble.";

async fn owned_block(
    st: &AppState,
    caller: &Caller,
    session_id: Uuid,
    block_id: Uuid,
) -> Result<Block, ApiError> {
    let b = sqlx::query_as::<_, Block>(&format!("SELECT {BLOCK_COLUMNS} FROM blocks WHERE id = $1 AND session_id = $2 AND deleted_at IS NULL"))
        .bind(block_id)
        .bind(session_id)
        .fetch_optional(&st.notes)
        .await?
        .ok_or_else(|| ApiError::not_found("block not found"))?;
    let mut conn = st.notes.acquire().await?;
    access::session(&mut conn, caller, session_id).await?;
    Ok(b)
}

/// Transcript around a moment (± 60 s), as display text.
async fn transcript_near(
    st: &AppState,
    session_id: Uuid,
    at_ms: i64,
) -> Result<Option<Passage>, ApiError> {
    let text: Option<String> = sqlx::query_scalar(
        "SELECT string_agg(COALESCE(corrected_text, faithful_text, raw_text), ' ' ORDER BY start_ms) FROM transcript_segments \
         WHERE session_id = $1 AND end_ms > $2 AND start_ms < $3",
    )
    .bind(session_id)
    .bind(at_ms - 60_000)
    .bind(at_ms + 60_000)
    .fetch_one(&st.notes)
    .await?;
    Ok(text.filter(|t| !t.is_empty()).map(|t| Passage {
        kind: "transcript".into(),
        source_id: format!("t{at_ms}"),
        content: t,
        locator: json!({ "fromMs": (at_ms - 60_000).max(0), "toMs": at_ms + 60_000 }),
        score: 1.0,
    }))
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct SuggestRequest {
    pub block_id: Uuid,
    /// `explain` | `expand` | `simplify` | `keyword` | `summarize`
    pub action: String,
}

#[utoipa::path(post, path = "/v1/sessions/{id}/ai/suggest", tag = "ai", params(("id" = Uuid, Path)), request_body = SuggestRequest,
    responses((status = 200, description = "SSE: delta… source… result {suggestion} · done")))]
pub async fn suggest(
    State(st): State<AppState>,
    caller: Caller,
    Path(session_id): Path<Uuid>,
    Json(req): Json<SuggestRequest>,
) -> Result<SseStream, ApiError> {
    if !SUGGEST_ACTIONS.contains(&req.action.as_str()) {
        return Err(ApiError::bad_request(
            "action must be explain, expand, simplify, keyword or summarize",
        ));
    }
    let block = owned_block(&st, &caller, session_id, req.block_id).await?;
    let price = pricing::price(&st, "suggest").await;
    ai::guard(&st, &caller, price).await?;

    let mut passages = retrieval::search(&st, caller.user_id, session_id, &block.text, 4)
        .await
        .map_err(ApiError::internal)?;
    if let Some(at) = block.audio_ts_ms {
        if let Some(p) = transcript_near(&st, session_id, at).await? {
            passages.insert(0, p);
        }
    }
    let context_label = match (
        block.audio_ts_ms,
        passages.iter().find(|p| p.kind == "slide"),
    ) {
        (Some(at), Some(s)) => format!(
            "Based on transcript at {} and {}",
            crate::routes::transcript::format_ms(at),
            retrieval::label(s)
        ),
        (Some(at), None) => format!(
            "Based on transcript at {}",
            crate::routes::transcript::format_ms(at)
        ),
        (None, Some(s)) => format!("Based on {}", retrieval::label(s)),
        (None, None) if passages.is_empty() => "No lecture sources yet".into(),
        _ => "Based on your session sources".into(),
    };
    let task = match req.action.as_str() {
        "explain" => "Explain the student's note in 2–4 sentences.",
        "expand" => "Add 2–4 bullet points of detail the lecture gave that the note leaves out.",
        "simplify" => "Rewrite the note in simpler words (one short paragraph).",
        "keyword" => "Define the note's key term in 1–2 sentences.",
        _ => "Summarize the note in one sentence.",
    };
    let messages = vec![
        Message::system(GROUNDING),
        Message::user(format!(
            "Sources:\n{}\n\nStudent note ({}):\n{}\n\nTask: {task}",
            context_text(&passages),
            block.kind,
            block.text
        )),
    ];
    let contexts = json!([{ "type": "block", "id": block.id }]);
    let run = ai::start_run(
        &st,
        &caller,
        Some(session_id),
        "suggest",
        Some(&req.action),
        &contexts,
    )
    .await?;
    let llm = Llm::for_role(&st, Role::Primary).await;
    let offline_text = format!(
        "{} (offline suggestion for: {})",
        task,
        clip(&block.text, 80)
    );
    let mut deltas = llm
        .stream(
            &messages,
            &ChatOptions {
                temperature: Some(0.3),
                max_tokens: Some(500),
                json: false,
            },
            || offline_text,
        )
        .await?;
    let sources = sources_json(&passages);
    let model = llm.model_name();

    Ok(ai::sse(async_stream::stream! {
        for s in sources.as_array().into_iter().flatten() {
            yield event("source", s.clone());
        }
        let mut body = String::new();
        while let Some(d) = deltas.next().await {
            match d {
                Ok(t) => { body.push_str(&t); yield event("delta", json!({ "text": t })); }
                Err(e) => { ai::fail_run(&st, run, &e).await; yield event("error", json!({ "message": e })); return; }
            }
        }
        let body = body.trim().to_string();
        let saved = sqlx::query_scalar::<_, Uuid>(
            "INSERT INTO ai_suggestions (session_id, user_id, source_block_id, action, context_label, body, sources, ai_run_id) \
             VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id")
            .bind(session_id).bind(caller.user_id).bind(block.id).bind(&req.action).bind(&context_label).bind(&body).bind(&sources).bind(run)
            .fetch_one(&st.notes).await;
        let Ok(suggestion_id) = saved else { yield event("error", json!({ "message": "could not save suggestion" })); return; };
        let suggestion = json!({ "id": suggestion_id, "sourceBlockId": block.id, "action": req.action, "contextLabel": context_label, "body": body, "sources": sources, "status": "pending" });
        match ai::finish_run(&st, &caller, run, ai::Outcome { kind: "suggest", response: &suggestion, model: &model, usage: &Usage::default(), price }).await {
            Ok(charged) => {
                yield event("result", json!({ "suggestion": suggestion }));
                yield event("done", json!({ "runId": run, "creditsCharged": charged }));
            }
            Err(e) => { ai::fail_run(&st, run, &e.message).await; yield event("error", ai::error_data(&e)); }
        }
    }))
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ApplySuggestion {
    /// `insertBelow` | `asExplanation` | `replaceSelection`
    pub mode: String,
    /// For `replaceSelection`: the exact text the student selected.
    pub selection: Option<String>,
    /// For `replaceSelection`: the block revision the student saw.
    pub base_revision: Option<i64>,
}

#[utoipa::path(post, path = "/v1/ai/suggestions/{id}/apply", tag = "ai", params(("id" = Uuid, Path)), request_body = ApplySuggestion,
    responses((status = 200, body = Block)))]
pub async fn apply(
    State(st): State<AppState>,
    caller: Caller,
    Path(id): Path<Uuid>,
    Json(req): Json<ApplySuggestion>,
) -> Result<Json<Block>, ApiError> {
    let mut tx = st.notes.begin().await?;
    let row = sqlx::query("SELECT session_id, source_block_id, body, sources, status FROM ai_suggestions WHERE id = $1 AND user_id = $2 FOR UPDATE")
        .bind(id)
        .bind(caller.user_id)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or_else(|| ApiError::not_found("suggestion not found"))?;
    let (session_id, source_block, body, sources, status): (
        Uuid,
        Option<Uuid>,
        String,
        Value,
        String,
    ) = (
        row.get("session_id"),
        row.get("source_block_id"),
        row.get("body"),
        row.get("sources"),
        row.get("status"),
    );
    if status != "pending" {
        return Err(
            ApiError::new(StatusCode::CONFLICT, format!("suggestion already {status}"))
                .with_code("suggestion_closed"),
        );
    }
    access::writable_session(&mut tx, &caller, session_id).await?;
    let source_indent: i32 = match source_block {
        Some(b) => sqlx::query_scalar("SELECT indent FROM blocks WHERE id = $1")
            .bind(b)
            .fetch_optional(&mut *tx)
            .await?
            .unwrap_or(0),
        None => 0,
    };
    let block = match req.mode.as_str() {
        "insertBelow" | "asExplanation" => {
            blocks::insert_server_block(
                &mut tx,
                &caller,
                NewServerBlock {
                    session_id,
                    after: source_block,
                    kind: "paragraph".into(),
                    text: body,
                    origin: "aiInsertedByStudent".into(),
                    audio_ts_ms: None,
                    transcript_anchor: None,
                    source_ref: None,
                    ai_sources: Some(sources),
                    indent: if req.mode == "asExplanation" {
                        source_indent + 1
                    } else {
                        source_indent
                    },
                },
            )
            .await?
        }
        "replaceSelection" => {
            // Explicit student approval: edits the block only at the revision they saw.
            let (Some(target), Some(sel), Some(base)) =
                (source_block, req.selection.as_deref(), req.base_revision)
            else {
                return Err(ApiError::bad_request(
                    "replaceSelection needs selection and baseRevision",
                ));
            };
            revs::lock(&mut tx, session_id, revs::BLOCKS).await?;
            let cur = sqlx::query_as::<_, Block>(&format!(
                "SELECT {BLOCK_COLUMNS} FROM blocks WHERE id = $1 FOR UPDATE"
            ))
            .bind(target)
            .fetch_one(&mut *tx)
            .await?;
            if cur.revision != base || cur.deleted_at.is_some() {
                return Err(ApiError::new(
                    StatusCode::CONFLICT,
                    "the block changed since you selected text",
                )
                .with_code("block_changed"));
            }
            if sel.is_empty() || !cur.text.contains(sel) {
                return Err(ApiError::bad_request("selection is not in the block"));
            }
            let mut ai_sources = cur.ai_sources.as_array().cloned().unwrap_or_default();
            ai_sources.extend(sources.as_array().cloned().unwrap_or_default());
            let rev = revs::bump(&mut tx, session_id, revs::BLOCKS).await?;
            let b = sqlx::query_as::<_, Block>(&format!(
                "UPDATE blocks SET text = $2, ai_sources = $3, revision = revision + 1, layer_rev = $4 WHERE id = $1 RETURNING {BLOCK_COLUMNS}"
            ))
            .bind(target)
            .bind(cur.text.replacen(sel, &body, 1))
            .bind(Value::Array(ai_sources))
            .bind(rev)
            .fetch_one(&mut *tx)
            .await?;
            blocks::snapshot(&mut tx, &caller, &b, "update", None).await?;
            b
        }
        _ => {
            return Err(ApiError::bad_request(
                "mode must be insertBelow, asExplanation or replaceSelection",
            ))
        }
    };
    sqlx::query(
        "UPDATE ai_suggestions SET status = 'inserted', inserted_block_id = $2 WHERE id = $1",
    )
    .bind(id)
    .bind(block.id)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    st.hub
        .session(
            session_id,
            Event::new(
                "block.changed",
                json!({ "blockIds": [block.id] }),
                Some(block.layer_rev),
            ),
        )
        .await;
    Ok(Json(block))
}

#[utoipa::path(post, path = "/v1/ai/suggestions/{id}/dismiss", tag = "ai", params(("id" = Uuid, Path)), responses((status = 204)))]
pub async fn dismiss(
    State(st): State<AppState>,
    caller: Caller,
    Path(id): Path<Uuid>,
) -> Result<StatusCode, ApiError> {
    let res = sqlx::query("UPDATE ai_suggestions SET status = 'dismissed' WHERE id = $1 AND user_id = $2 AND status = 'pending'")
        .bind(id)
        .bind(caller.user_id)
        .execute(&st.notes)
        .await?;
    if res.rows_affected() == 0 {
        return Err(ApiError::not_found("pending suggestion not found"));
    }
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Debug, Clone, Deserialize, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct AiContext {
    /// `block` | `transcript` | `slide` | `section` | `session` | `selection`
    #[serde(rename = "type")]
    pub kind: String,
    pub id: Option<String>,
    pub from_ms: Option<i64>,
    pub to_ms: Option<i64>,
    pub text: Option<String>,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct CommandRequest {
    /// Free text, or a quick command: explain, expand, simplify, summarize, whatDidIMiss.
    pub command: String,
    #[serde(default)]
    pub contexts: Vec<AiContext>,
}

async fn resolve_contexts(
    st: &AppState,
    session_id: Uuid,
    contexts: &[AiContext],
) -> Result<Vec<Passage>, ApiError> {
    let mut out = Vec::new();
    for c in contexts {
        match c.kind.as_str() {
            "block" => {
                if let Some(id) = c.id.as_deref().and_then(|i| Uuid::parse_str(i).ok()) {
                    if let Some(t) = sqlx::query_scalar::<_, String>("SELECT text FROM blocks WHERE id = $1 AND session_id = $2 AND deleted_at IS NULL")
                        .bind(id).bind(session_id).fetch_optional(&st.notes).await?
                    {
                        out.push(Passage { kind: "block".into(), source_id: id.to_string(), content: t, locator: json!({ "blockId": id }), score: 1.0 });
                    }
                }
            }
            "transcript" => {
                let (from, to) = (c.from_ms.unwrap_or(0), c.to_ms.unwrap_or(i64::MAX));
                let t: Option<String> = sqlx::query_scalar(
                    "SELECT string_agg(COALESCE(corrected_text, faithful_text, raw_text), ' ' ORDER BY start_ms) FROM transcript_segments \
                     WHERE session_id = $1 AND end_ms > $2 AND start_ms < $3")
                    .bind(session_id).bind(from).bind(to).fetch_one(&st.notes).await?;
                if let Some(t) = t.filter(|t| !t.is_empty()) {
                    out.push(Passage {
                        kind: "transcript".into(),
                        source_id: format!("{from}-{to}"),
                        content: t,
                        locator: json!({ "fromMs": from, "toMs": to.min(i64::MAX / 2) }),
                        score: 1.0,
                    });
                }
            }
            "slide" => {
                if let Some((mid, page)) =
                    c.id.as_deref()
                        .and_then(|i| crate::routes::materials::parse_page_ref(i).ok())
                {
                    let row = sqlx::query("SELECT p.title, p.ocr_text, m.filename FROM material_pages p JOIN materials m ON m.id = p.material_id \
                                           WHERE p.material_id = $1 AND p.number = $2 AND m.session_id = $3")
                        .bind(mid).bind(page).bind(session_id).fetch_optional(&st.notes).await?;
                    if let Some(r) = row {
                        out.push(Passage { kind: "slide".into(), source_id: format!("{mid}:{page}"),
                            content: format!("{}\n{}", r.get::<String, _>("title"), r.get::<String, _>("ocr_text")),
                            locator: json!({ "materialId": mid, "page": page, "filename": r.get::<String, _>("filename") }), score: 1.0 });
                    }
                }
            }
            "section" | "session" => {
                let t: Option<String> = sqlx::query_scalar("SELECT string_agg(text, '\n' ORDER BY position) FROM blocks WHERE session_id = $1 AND deleted_at IS NULL")
                    .bind(session_id).fetch_one(&st.notes).await?;
                if let Some(t) = t.filter(|t| !t.is_empty()) {
                    out.push(Passage {
                        kind: "block".into(),
                        source_id: "session".into(),
                        content: clip(&t, 12_000),
                        locator: json!({ "scope": c.kind }),
                        score: 1.0,
                    });
                }
            }
            "selection" => {
                if let Some(t) = c.text.as_ref().filter(|t| !t.trim().is_empty()) {
                    out.push(Passage {
                        kind: "block".into(),
                        source_id: "selection".into(),
                        content: clip(t, 4000),
                        locator: json!({ "selection": true }),
                        score: 1.0,
                    });
                }
            }
            other => {
                return Err(ApiError::bad_request(format!(
                    "unknown context type '{other}'"
                )))
            }
        }
    }
    Ok(out)
}

fn is_missing_command(c: &str) -> bool {
    let c = c.to_lowercase().replace(['?', ' ', '\''], "");
    c == "whatdidimiss" || c == "whatdidimis"
}

#[utoipa::path(post, path = "/v1/sessions/{id}/ai/command", tag = "ai", params(("id" = Uuid, Path)), request_body = CommandRequest,
    responses((status = 200, description = "SSE: source… delta… result {title, body, points, sources, sourcesAgree, conflict} · done")))]
pub async fn command(
    State(st): State<AppState>,
    caller: Caller,
    Path(session_id): Path<Uuid>,
    Json(req): Json<CommandRequest>,
) -> Result<SseStream, ApiError> {
    let cmd = req.command.trim().to_string();
    if cmd.is_empty() || cmd.chars().count() > 2000 {
        return Err(ApiError::bad_request("command must be 1..2000 chars"));
    }
    {
        let mut conn = st.notes.acquire().await?;
        access::session(&mut conn, &caller, session_id).await?;
    }
    let price = pricing::price(&st, "command").await;
    ai::guard(&st, &caller, price).await?;
    let missing = is_missing_command(&cmd);
    let mut passages = resolve_contexts(&st, session_id, &req.contexts).await?;
    let query = passages
        .first()
        .map(|p| clip(&p.content, 400))
        .unwrap_or_else(|| cmd.clone());
    for p in retrieval::search(
        &st,
        caller.user_id,
        session_id,
        &format!("{cmd} {query}"),
        5,
    )
    .await
    .map_err(ApiError::internal)?
    {
        if !passages
            .iter()
            .any(|x| x.kind == p.kind && x.source_id == p.source_id)
        {
            passages.push(p);
        }
    }
    let contexts_json = serde_json::to_value(&req.contexts).unwrap_or_default();
    let run = ai::start_run(
        &st,
        &caller,
        Some(session_id),
        if missing { "missing" } else { "command" },
        Some(&cmd),
        &contexts_json,
    )
    .await?;
    let llm = Llm::for_role(&st, Role::Primary).await;
    let model = llm.model_name();
    let sources = sources_json(&passages);

    if missing {
        // Structured checklist: compare the notes with what the lecture covered.
        let notes: Option<String> = sqlx::query_scalar("SELECT string_agg(text, '\n' ORDER BY position) FROM blocks WHERE session_id = $1 AND deleted_at IS NULL")
            .bind(session_id).fetch_one(&st.notes).await?;
        let lecture: Option<String> = sqlx::query_scalar("SELECT string_agg(COALESCE(corrected_text, faithful_text, raw_text), ' ' ORDER BY start_ms) FROM transcript_segments WHERE session_id = $1")
            .bind(session_id).fetch_one(&st.notes).await?;
        let messages = vec![
            Message::system(format!("{GROUNDING} Reply with JSON only: {{\"title\": string, \"contextSummary\": string, \"points\": [{{\"text\": string, \"source\": number}}], \"sourcesAgree\": boolean, \"conflict\": string|null}}. `source` is the number of the source that supports the point.")),
            Message::user(format!("Sources:\n{}\n\n[L] Lecture transcript:\n{}\n\nStudent notes:\n{}\n\nList the important points the lecture covered that the notes miss.",
                context_text(&passages), clip(lecture.as_deref().unwrap_or(""), 12_000), clip(notes.as_deref().unwrap_or(""), 8000))),
        ];
        let offline_points: Vec<Value> = passages.iter().take(3).enumerate()
            .map(|(i, p)| json!({ "text": format!("Review: {}", clip(&p.content, 120)), "source": i + 1 })).collect();
        let offline = json!({ "title": "What did I miss?", "contextSummary": "Compared your notes with the lecture (offline)", "points": offline_points, "sourcesAgree": true, "conflict": null }).to_string();
        return Ok(ai::sse(async_stream::stream! {
            for s in sources.as_array().into_iter().flatten() { yield event("source", s.clone()); }
            let res = llm.complete(&messages, &ChatOptions { temperature: Some(0.2), max_tokens: Some(1200), json: true }, || offline).await;
            let (text, usage) = match res { Ok(r) => r, Err(e) => { ai::fail_run(&st, run, &e.message).await; yield event("error", ai::error_data(&e)); return; } };
            let v = parse_json_loose(&text).unwrap_or_else(|| json!({ "title": "What did I miss?", "points": [] }));
            let points: Vec<Value> = v["points"].as_array().cloned().unwrap_or_default().into_iter().map(|p| {
                let idx = p["source"].as_u64().unwrap_or(0) as usize;
                let src = sources.get(idx.saturating_sub(1)).cloned().unwrap_or(Value::Null);
                json!({ "text": p["text"], "sourceLabel": src["label"], "source": src })
            }).collect();
            let result = json!({ "title": v["title"], "contextSummary": v["contextSummary"], "body": Value::Null, "points": points,
                                 "sources": sources, "sourcesAgree": v["sourcesAgree"], "conflict": v["conflict"] });
            match ai::finish_run(&st, &caller, run, ai::Outcome { kind: "missing", response: &result, model: &model, usage: &usage, price }).await {
                Ok(charged) => { yield event("result", result); yield event("done", json!({ "runId": run, "creditsCharged": charged })); }
                Err(e) => { ai::fail_run(&st, run, &e.message).await; yield event("error", ai::error_data(&e)); }
            }
        }));
    }

    let messages = vec![
        Message::system(format!("{GROUNDING} Answer in short Markdown. On the very last line write exactly `SOURCES: agree` or `SOURCES: conflict — <one sentence>`.")),
        Message::user(format!("Sources:\n{}\n\nCommand: {cmd}", context_text(&passages))),
    ];
    let offline_body = format!(
        "{cmd}: offline answer based on {} source(s).\nSOURCES: agree",
        passages.len()
    );
    let mut deltas = llm
        .stream(
            &messages,
            &ChatOptions {
                temperature: Some(0.3),
                max_tokens: Some(1200),
                json: false,
            },
            || offline_body,
        )
        .await?;
    Ok(ai::sse(async_stream::stream! {
        for s in sources.as_array().into_iter().flatten() { yield event("source", s.clone()); }
        let mut body = String::new();
        while let Some(d) = deltas.next().await {
            match d {
                Ok(t) => { body.push_str(&t); yield event("delta", json!({ "text": t })); }
                Err(e) => { ai::fail_run(&st, run, &e).await; yield event("error", json!({ "message": e })); return; }
            }
        }
        let (clean, agree, conflict) = split_sources_line(&body);
        let result = json!({ "title": clip(&cmd, 80), "contextSummary": format!("{} source(s)", passages.len()), "body": clean,
                             "points": [], "sources": sources, "sourcesAgree": agree, "conflict": conflict });
        match ai::finish_run(&st, &caller, run, ai::Outcome { kind: "command", response: &result, model: &model, usage: &Usage::default(), price }).await {
            Ok(charged) => { yield event("result", result); yield event("done", json!({ "runId": run, "creditsCharged": charged })); }
            Err(e) => { ai::fail_run(&st, run, &e.message).await; yield event("error", ai::error_data(&e)); }
        }
    }))
}

/// Strips the trailing `SOURCES: …` line → (body, sourcesAgree, conflict).
pub fn split_sources_line(body: &str) -> (String, Option<bool>, Option<String>) {
    let trimmed = body.trim_end();
    if let Some(i) = trimmed.rfind("SOURCES:") {
        let tail = trimmed[i + 8..].trim();
        let clean = trimmed[..i].trim_end().to_string();
        if tail.to_lowercase().starts_with("agree") {
            return (clean, Some(true), None);
        }
        if tail.to_lowercase().starts_with("conflict") {
            let reason = tail
                .trim_start_matches(|c: char| c.is_alphabetic())
                .trim_start_matches([' ', '—', '-', ':'])
                .trim();
            return (
                clean,
                Some(false),
                Some(reason.to_string()).filter(|r| !r.is_empty()),
            );
        }
        return (clean, None, None);
    }
    (trimmed.to_string(), None, None)
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct InsertRun {
    /// `insertBelow` (blocks now) | `asSuggestions` (review later)
    pub mode: String,
    pub after_block_id: Option<Uuid>,
    /// For "What did I miss?": which points (0-based). All when omitted.
    pub point_indexes: Option<Vec<usize>>,
}

#[utoipa::path(post, path = "/v1/ai/runs/{id}/insert", tag = "ai", params(("id" = Uuid, Path)), request_body = InsertRun,
    responses((status = 200, description = "{ blocks: Block[] } or { suggestions: [] }")))]
pub async fn insert_run(
    State(st): State<AppState>,
    caller: Caller,
    Path(run_id): Path<Uuid>,
    Json(req): Json<InsertRun>,
) -> Result<Json<Value>, ApiError> {
    let mut tx = st.notes.begin().await?;
    let row = sqlx::query(
        "SELECT session_id, kind, response, status FROM ai_runs WHERE id = $1 AND user_id = $2",
    )
    .bind(run_id)
    .bind(caller.user_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(|| ApiError::not_found("run not found"))?;
    let (session_id, kind, response, status): (Option<Uuid>, String, Option<Value>, String) = (
        row.get("session_id"),
        row.get("kind"),
        row.get("response"),
        row.get("status"),
    );
    let session_id = session_id.ok_or_else(|| ApiError::bad_request("run has no session"))?;
    if status != "done" {
        return Err(
            ApiError::new(StatusCode::CONFLICT, "run not finished").with_code("run_not_done")
        );
    }
    access::writable_session(&mut tx, &caller, session_id).await?;
    let response = response.unwrap_or_default();
    // (text, sources) items to insert.
    let items: Vec<(String, Value)> = if kind == "missing" {
        let points = response["points"].as_array().cloned().unwrap_or_default();
        let pick: Vec<usize> = req
            .point_indexes
            .clone()
            .unwrap_or_else(|| (0..points.len()).collect());
        pick.into_iter()
            .filter_map(|i| points.get(i))
            .map(|p| {
                (
                    p["text"].as_str().unwrap_or("").to_string(),
                    json!([p["source"]]),
                )
            })
            .collect()
    } else {
        vec![(
            response["body"].as_str().unwrap_or("").to_string(),
            response["sources"].clone(),
        )]
    };
    let items: Vec<(String, Value)> = items
        .into_iter()
        .filter(|(t, _)| !t.trim().is_empty())
        .collect();
    if items.is_empty() {
        return Err(ApiError::bad_request("nothing to insert"));
    }
    match req.mode.as_str() {
        "insertBelow" => {
            let mut after = req.after_block_id;
            let mut out = Vec::new();
            for (text, sources) in items {
                let b = blocks::insert_server_block(
                    &mut tx,
                    &caller,
                    NewServerBlock {
                        session_id,
                        after,
                        kind: if kind == "missing" {
                            "bulleted".into()
                        } else {
                            "paragraph".into()
                        },
                        text,
                        origin: "aiInsertedByStudent".into(),
                        audio_ts_ms: None,
                        transcript_anchor: None,
                        source_ref: None,
                        ai_sources: Some(sources),
                        indent: 0,
                    },
                )
                .await?;
                after = Some(b.id);
                out.push(b);
            }
            tx.commit().await?;
            let ids: Vec<Uuid> = out.iter().map(|b| b.id).collect();
            let rev = out.last().map(|b| b.layer_rev);
            st.hub
                .session(
                    session_id,
                    Event::new("block.changed", json!({ "blockIds": ids }), rev),
                )
                .await;
            Ok(Json(json!({ "blocks": out })))
        }
        "asSuggestions" => {
            let mut ids = Vec::new();
            for (text, sources) in items {
                let id: Uuid = sqlx::query_scalar(
                    "INSERT INTO ai_suggestions (session_id, user_id, source_block_id, action, context_label, body, sources, ai_run_id) \
                     VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id")
                    .bind(session_id).bind(caller.user_id).bind(req.after_block_id).bind(&kind).bind("From the AI assistant")
                    .bind(&text).bind(&sources).bind(run_id).fetch_one(&mut *tx).await?;
                ids.push(id);
            }
            tx.commit().await?;
            Ok(Json(json!({ "suggestions": ids })))
        }
        _ => Err(ApiError::bad_request(
            "mode must be insertBelow or asSuggestions",
        )),
    }
}

#[derive(Debug, Serialize, sqlx::FromRow, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct HistoryItem {
    pub id: Uuid,
    pub kind: String,
    pub command: Option<String>,
    pub status: String,
    pub credits_charged: i32,
    #[schema(value_type = Option<Object>)]
    pub response: Option<Value>,
    pub created_at: DateTime<Utc>,
}

#[utoipa::path(get, path = "/v1/sessions/{id}/ai/history", tag = "ai", params(("id" = Uuid, Path)), responses((status = 200, body = Vec<HistoryItem>)))]
pub async fn history(
    State(st): State<AppState>,
    caller: Caller,
    Path(session_id): Path<Uuid>,
) -> Result<Json<Vec<HistoryItem>>, ApiError> {
    let mut conn = st.notes.acquire().await?;
    access::session(&mut conn, &caller, session_id).await?;
    Ok(Json(sqlx::query_as::<_, HistoryItem>(
        "SELECT id, kind, command, status, credits_charged, response, created_at FROM ai_runs WHERE session_id = $1 ORDER BY created_at DESC LIMIT 100")
        .bind(session_id).fetch_all(&mut *conn).await?))
}

#[utoipa::path(get, path = "/v1/sessions/{id}/ai/suggestions", tag = "ai", params(("id" = Uuid, Path)), responses((status = 200)))]
pub async fn pending_suggestions(
    State(st): State<AppState>,
    caller: Caller,
    Path(session_id): Path<Uuid>,
) -> Result<Json<Value>, ApiError> {
    let mut conn = st.notes.acquire().await?;
    access::session(&mut conn, &caller, session_id).await?;
    Ok(Json(sqlx::query_scalar(
        "SELECT COALESCE(json_agg(json_build_object('id', id, 'sourceBlockId', source_block_id, 'action', action, 'contextLabel', context_label, \
             'body', body, 'sources', sources, 'status', status, 'createdAt', created_at) ORDER BY created_at), '[]') \
         FROM ai_suggestions WHERE session_id = $1 AND status = 'pending'")
        .bind(session_id).fetch_one(&mut *conn).await?))
}

#[derive(Debug, Deserialize, utoipa::IntoParams)]
pub struct RelevantQuery {
    pub q: Option<String>,
    pub limit: Option<usize>,
}

/// Search + "Relevant Data" cards (no AI call, free).
#[utoipa::path(get, path = "/v1/sessions/{id}/relevant", tag = "ai", params(("id" = Uuid, Path), RelevantQuery),
    responses((status = 200, description = "Passages with label, excerpt and locator")))]
pub async fn relevant(
    State(st): State<AppState>,
    caller: Caller,
    Path(session_id): Path<Uuid>,
    Query(q): Query<RelevantQuery>,
) -> Result<Json<Value>, ApiError> {
    {
        let mut conn = st.notes.acquire().await?;
        access::session(&mut conn, &caller, session_id).await?;
    }
    let query = match q.q.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
        Some(s) => s.to_string(),
        // No query: what's relevant to the last few things the student wrote.
        None => sqlx::query_scalar::<_, Option<String>>(
            "SELECT string_agg(text, ' ') FROM (SELECT text FROM blocks WHERE session_id = $1 AND deleted_at IS NULL ORDER BY updated_at DESC LIMIT 3) b")
            .bind(session_id).fetch_one(&st.notes).await?.unwrap_or_default(),
    };
    if query.is_empty() {
        return Ok(Json(json!({ "query": "", "items": [] })));
    }
    let passages = retrieval::search(
        &st,
        caller.user_id,
        session_id,
        &query,
        q.limit.unwrap_or(8).clamp(1, 20),
    )
    .await
    .map_err(ApiError::internal)?;
    Ok(Json(
        json!({ "query": query, "items": sources_json(&passages) }),
    ))
}

/// Topic-divided gist of the session (hub Summarize; reused by Finalize).
pub async fn build_summary(
    st: &AppState,
    caller: &Caller,
    session_id: Uuid,
) -> Result<(Value, Usage, String), ApiError> {
    let notes: Vec<(String, String)> = sqlx::query_as("SELECT type, text FROM blocks WHERE session_id = $1 AND deleted_at IS NULL ORDER BY position")
        .bind(session_id).fetch_all(&st.notes).await?;
    let lecture: Option<String> = sqlx::query_scalar("SELECT string_agg(COALESCE(corrected_text, faithful_text, raw_text), ' ' ORDER BY start_ms) FROM transcript_segments WHERE session_id = $1")
        .bind(session_id).fetch_one(&st.notes).await?;
    let notes_text = notes
        .iter()
        .map(|(k, t)| format!("[{k}] {t}"))
        .collect::<Vec<_>>()
        .join("\n");
    let messages = vec![
        Message::system("Summarize a lecture session for a student. Reply with JSON only: {\"topics\": [{\"title\": string, \"gist\": string, \"points\": [string], \"sources\": [\"notes\"|\"transcript\"|\"slides\"]}]}. 2–6 topics in lecture order; gist is 1–2 sentences; 2–4 points each; use only the given material."),
        Message::user(format!("Student notes:\n{}\n\nLecture transcript:\n{}", clip(&notes_text, 12_000), clip(lecture.as_deref().unwrap_or(""), 16_000))),
    ];
    let llm = Llm::for_role(st, Role::Fast).await;
    let model = llm.model_name();
    let offline = || offline_topics(&notes);
    let (text, usage) = llm
        .complete(
            &messages,
            &ChatOptions {
                temperature: Some(0.2),
                max_tokens: Some(1500),
                json: true,
            },
            offline,
        )
        .await?;
    let v = parse_json_loose(&text).unwrap_or_else(|| json!({ "topics": [] }));
    let _ = caller;
    Ok((json!({ "topics": v["topics"] }), usage, model))
}

/// Offline summary: one topic per heading, gist from the text under it.
fn offline_topics(notes: &[(String, String)]) -> String {
    let mut topics: Vec<Value> = Vec::new();
    for (kind, text) in notes {
        if matches!(kind.as_str(), "h1" | "h2") || topics.is_empty() {
            let title = if matches!(kind.as_str(), "h1" | "h2") {
                text.clone()
            } else {
                "Session notes".into()
            };
            topics.push(json!({ "title": title, "gist": "", "points": [], "sources": ["notes"] }));
            if matches!(kind.as_str(), "h1" | "h2") {
                continue;
            }
        }
        let t = topics.last_mut().expect("topic");
        if t["gist"].as_str().unwrap_or("").is_empty() {
            t["gist"] = json!(clip(text, 160));
        } else if t["points"].as_array().map(|a| a.len() < 4).unwrap_or(false) {
            t["points"]
                .as_array_mut()
                .expect("points")
                .push(json!(clip(text, 120)));
        }
    }
    json!({ "topics": topics }).to_string()
}

#[utoipa::path(post, path = "/v1/sessions/{id}/summarize", tag = "ai", params(("id" = Uuid, Path)),
    responses((status = 200, description = "SSE: result {topics[]} · done")))]
pub async fn summarize(
    State(st): State<AppState>,
    caller: Caller,
    Path(session_id): Path<Uuid>,
) -> Result<SseStream, ApiError> {
    {
        let mut conn = st.notes.acquire().await?;
        access::session(&mut conn, &caller, session_id).await?;
    }
    let price = pricing::price(&st, "summarize").await;
    ai::guard(&st, &caller, price).await?;
    let run = ai::start_run(
        &st,
        &caller,
        Some(session_id),
        "summarize",
        None,
        &json!([{ "type": "session" }]),
    )
    .await?;
    Ok(ai::sse(async_stream::stream! {
        yield event("progress", json!({ "stage": "summarizing" }));
        match build_summary(&st, &caller, session_id).await {
            Ok((result, usage, model)) => match ai::finish_run(&st, &caller, run, ai::Outcome { kind: "summarize", response: &result, model: &model, usage: &usage, price }).await {
                Ok(charged) => { yield event("result", result); yield event("done", json!({ "runId": run, "creditsCharged": charged })); }
                Err(e) => { ai::fail_run(&st, run, &e.message).await; yield event("error", ai::error_data(&e)); }
            },
            Err(e) => { ai::fail_run(&st, run, &e.message).await; yield event("error", ai::error_data(&e)); }
        }
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sources_line() {
        assert_eq!(
            split_sources_line("Body text\nSOURCES: agree"),
            ("Body text".into(), Some(true), None)
        );
        let (b, a, c) =
            split_sources_line("Body\nSOURCES: conflict — slide 7 says 36 ATP, transcript says 30");
        assert_eq!((b.as_str(), a), ("Body", Some(false)));
        assert_eq!(
            c.as_deref(),
            Some("slide 7 says 36 ATP, transcript says 30")
        );
        assert_eq!(split_sources_line("no marker").1, None);
        assert!(is_missing_command("What did I miss?"));
    }
}

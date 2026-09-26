//! Research & Explanations (Panel 10): course sources first (this session +
//! the linked Study Studio), then the web when asked or when course evidence
//! is thin. Every claim is tied to numbered evidence; nothing enters the notes
//! until the student applies it.

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;
use futures::StreamExt;
use octo_common::llm::{parse_json_loose, ChatOptions, Message, Usage};
use octo_common::ApiError;
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::ai::{self, clip, event, Llm, Role, SseStream};
use crate::ctx::Caller;
use crate::realtime::Event;
use crate::retrieval::{self, Passage};
use crate::routes::ai::split_sources_line;
use crate::routes::blocks::{self, NewServerBlock};
use crate::{access, jobs, pricing, AppState};

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ResearchRequest {
    pub question: String,
    /// `courseFirst` (default) | `external` | `both`
    pub scope: Option<String>,
    /// `quick` | `standard` (default) | `deep`
    pub depth: Option<String>,
}

fn kind_of(p: &Passage) -> &'static str {
    match p.kind.as_str() {
        "transcript" => "lectureTranscript",
        "slide" => "courseSlide",
        "studyStudio" => "studyStudio",
        _ => "studentNotes",
    }
}

fn trust_of(url: &str) -> &'static str {
    let host = url.split("//").nth(1).unwrap_or(url).split('/').next().unwrap_or("").to_lowercase();
    if host.ends_with(".edu") || host.ends_with(".gov") || host.contains("nih.gov") || host.contains("britannica") || host.contains("khanacademy") {
        "high"
    } else if host.contains("wikipedia") || host.contains("openstax") {
        "medium"
    } else {
        "low"
    }
}

#[utoipa::path(post, path = "/v1/sessions/{id}/research", tag = "research", params(("id" = Uuid, Path)), request_body = ResearchRequest,
    responses((status = 200, description = "SSE: evidence… delta… result {researchId, explanation, evidence, sourcesAgree, conflict, lowEvidence} · done")))]
pub async fn run(State(st): State<AppState>, caller: Caller, Path(session_id): Path<Uuid>, Json(req): Json<ResearchRequest>) -> Result<SseStream, ApiError> {
    let question = req.question.trim().to_string();
    if question.is_empty() || question.chars().count() > 1000 {
        return Err(ApiError::bad_request("question must be 1..1000 chars"));
    }
    let scope = req.scope.unwrap_or_else(|| "courseFirst".into());
    let depth = req.depth.unwrap_or_else(|| "standard".into());
    if !["courseFirst", "external", "both"].contains(&scope.as_str()) || !["quick", "standard", "deep"].contains(&depth.as_str()) {
        return Err(ApiError::bad_request("scope: courseFirst|external|both · depth: quick|standard|deep"));
    }
    {
        let mut conn = st.notes.acquire().await?;
        access::session(&mut conn, &caller, session_id).await?;
    }
    let price = pricing::price(&st, &format!("research_{depth}")).await;
    ai::guard(&st, &caller, price).await?;
    let k = match depth.as_str() { "quick" => 4, "deep" => 10, _ => 6 };

    // Course evidence first.
    let course: Vec<Passage> = if scope != "external" {
        retrieval::search(&st, caller.user_id, session_id, &question, k).await.map_err(ApiError::internal)?
    } else {
        Vec::new()
    };
    let mut evidence: Vec<Value> = course
        .iter()
        .map(|p| json!({ "kind": kind_of(p), "title": retrieval::label(p), "excerpt": clip(&p.content, 500), "locator": p.locator, "url": null, "trust": "course", "ref": { "kind": p.kind, "sourceId": p.source_id } }))
        .collect();
    let low_course = course.len() < 2;

    // Web evidence: on request, or when the course material is thin.
    if scope != "courseFirst" || low_course {
        let search = Llm::for_role(&st, Role::Search).await;
        let messages = vec![
            Message::system("Find reliable sources for a student's question. Reply with JSON only: {\"sources\": [{\"title\": string, \"url\": string, \"excerpt\": string}]} — 2–5 sources, excerpt = a short quote or faithful summary of what the page says."),
            Message::user(question.clone()),
        ];
        if let Ok((text, _)) = search.complete(&messages, &ChatOptions { temperature: Some(0.1), max_tokens: Some(1200), json: true }, || json!({ "sources": [] }).to_string()).await {
            for s in parse_json_loose(&text).and_then(|v| v["sources"].as_array().cloned()).unwrap_or_default().into_iter().take(k) {
                let url = s["url"].as_str().unwrap_or("").to_string();
                if !url.starts_with("http") {
                    continue;
                }
                evidence.push(json!({ "kind": "external", "title": s["title"].as_str().unwrap_or(&url), "excerpt": clip(s["excerpt"].as_str().unwrap_or(""), 500),
                                      "locator": url, "url": url, "trust": trust_of(&url), "ref": null }));
            }
        }
    }

    let numbered = evidence
        .iter()
        .enumerate()
        .map(|(i, e)| format!("[{}] ({}{}) {}", i + 1, e["title"].as_str().unwrap_or(""), if e["kind"] == "external" { ", external" } else { "" }, e["excerpt"].as_str().unwrap_or("")))
        .collect::<Vec<_>>()
        .join("\n\n");
    let messages = vec![
        Message::system("You explain lecture topics to a university student. Use ONLY the numbered evidence and cite every claim like [2]. Prefer course sources; say when only external sources support a point. Keep it to 1–3 short paragraphs. On the very last line write exactly `SOURCES: agree` or `SOURCES: conflict — <one sentence>`."),
        Message::user(format!("Evidence:\n{numbered}\n\nQuestion: {question}")),
    ];
    let llm = Llm::for_role(&st, Role::Primary).await;
    let model = llm.model_name();
    let offline = format!("{question} — offline explanation from {} piece(s) of evidence [1].\nSOURCES: agree", evidence.len());
    let mut deltas = llm.stream(&messages, &ChatOptions { temperature: Some(0.2), max_tokens: Some(1200), json: false }, || offline).await?;
    let run = ai::start_run(&st, &caller, Some(session_id), "research", Some(&question), &json!([{ "scope": scope, "depth": depth }])).await?;

    Ok(ai::sse(async_stream::stream! {
        for e in &evidence { yield event("evidence", e.clone()); }
        let mut body = String::new();
        while let Some(d) = deltas.next().await {
            match d {
                Ok(t) => { body.push_str(&t); yield event("delta", json!({ "text": t })); }
                Err(e) => { ai::fail_run(&st, run, &e).await; yield event("error", json!({ "message": e })); return; }
            }
        }
        let (explanation, agree, conflict) = split_sources_line(&body);
        let low_evidence = evidence.len() < 2;
        let saved: Result<Uuid, sqlx::Error> = async {
            let mut tx = st.notes.begin().await?;
            let id: Uuid = sqlx::query_scalar(
                "INSERT INTO research_runs (session_id, user_id, question, scope, depth, explanation, sources_agree, conflict, low_evidence, ai_run_id) \
                 VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING id")
                .bind(session_id).bind(caller.user_id).bind(&question).bind(&scope).bind(&depth).bind(&explanation)
                .bind(agree).bind(&conflict).bind(low_evidence).bind(run).fetch_one(&mut *tx).await?;
            for (i, e) in evidence.iter().enumerate() {
                sqlx::query("INSERT INTO research_sources (run_id, ordinal, kind, title, excerpt, locator, url, ref, trust) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)")
                    .bind(id).bind(i as i32 + 1).bind(e["kind"].as_str()).bind(e["title"].as_str()).bind(e["excerpt"].as_str())
                    .bind(e["locator"].as_str().map(str::to_string).unwrap_or_else(|| e["locator"].to_string()))
                    .bind(e["url"].as_str()).bind(&e["ref"]).bind(e["trust"].as_str()).execute(&mut *tx).await?;
            }
            tx.commit().await?;
            Ok(id)
        }.await;
        let Ok(research_id) = saved else { yield event("error", json!({ "message": "could not save research" })); return; };
        let result = json!({ "researchId": research_id, "question": question, "explanation": explanation, "evidence": evidence,
                             "sourcesAgree": agree, "conflict": conflict, "lowEvidence": low_evidence, "courseSearchedFirst": scope != "external" });
        match ai::finish_run(&st, &caller, run, ai::Outcome { kind: "research", response: &result, model: &model, usage: &Usage::default(), price }).await {
            Ok(charged) => { yield event("result", result); yield event("done", json!({ "runId": run, "creditsCharged": charged })); }
            Err(e) => { ai::fail_run(&st, run, &e.message).await; yield event("error", ai::error_data(&e)); }
        }
    }))
}

async fn owned_run(st: &AppState, caller: &Caller, id: Uuid) -> Result<(Uuid, String, Option<String>), ApiError> {
    let row = sqlx::query("SELECT session_id, question, explanation FROM research_runs WHERE id = $1 AND user_id = $2")
        .bind(id).bind(caller.user_id).fetch_optional(&st.notes).await?
        .ok_or_else(|| ApiError::not_found("research not found"))?;
    Ok((row.get("session_id"), row.get("question"), row.get("explanation")))
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ApplyResearch {
    /// `asExplanation` (nested under `afterBlockId`) | `insertBelow`
    pub mode: String,
    pub after_block_id: Option<Uuid>,
}

#[utoipa::path(post, path = "/v1/research/{id}/apply", tag = "research", params(("id" = Uuid, Path)), request_body = ApplyResearch,
    responses((status = 201, body = crate::routes::blocks::Block)))]
pub async fn apply(State(st): State<AppState>, caller: Caller, Path(id): Path<Uuid>, Json(req): Json<ApplyResearch>) -> Result<(StatusCode, Json<crate::routes::blocks::Block>), ApiError> {
    if !["asExplanation", "insertBelow"].contains(&req.mode.as_str()) {
        return Err(ApiError::bad_request("mode must be asExplanation or insertBelow"));
    }
    let (session_id, _, explanation) = owned_run(&st, &caller, id).await?;
    let explanation = explanation.filter(|e| !e.trim().is_empty()).ok_or_else(|| ApiError::bad_request("research has no explanation"))?;
    let sources: Value = sqlx::query_scalar(
        "SELECT COALESCE(json_agg(json_build_object('kind', kind, 'label', title, 'excerpt', excerpt, 'locator', locator, 'url', url, 'trust', trust) ORDER BY ordinal), '[]') \
         FROM research_sources WHERE run_id = $1")
        .bind(id).fetch_one(&st.notes).await?;
    let mut tx = st.notes.begin().await?;
    access::writable_session(&mut tx, &caller, session_id).await?;
    let indent = match (req.mode.as_str(), req.after_block_id) {
        ("asExplanation", Some(b)) => sqlx::query_scalar::<_, i32>("SELECT indent + 1 FROM blocks WHERE id = $1").bind(b).fetch_optional(&mut *tx).await?.unwrap_or(1),
        _ => 0,
    };
    let block = blocks::insert_server_block(&mut tx, &caller, NewServerBlock {
        session_id, after: req.after_block_id, kind: "paragraph".into(), text: explanation, origin: "aiInsertedByStudent".into(),
        audio_ts_ms: None, transcript_anchor: None, source_ref: None, ai_sources: Some(sources), indent,
    }).await?;
    tx.commit().await?;
    st.hub.session(session_id, Event::new("block.changed", json!({ "blockIds": [block.id] }), Some(block.layer_rev))).await;
    Ok((StatusCode::CREATED, Json(block)))
}

#[utoipa::path(post, path = "/v1/research/{id}/save", tag = "research", params(("id" = Uuid, Path)), responses((status = 204)))]
pub async fn save(State(st): State<AppState>, caller: Caller, Path(id): Path<Uuid>) -> Result<StatusCode, ApiError> {
    let (session_id, _, _) = owned_run(&st, &caller, id).await?;
    sqlx::query("UPDATE research_runs SET saved = true WHERE id = $1").bind(id).execute(&st.notes).await?;
    jobs::enqueue(&st.notes, Some(caller.user_id), "embed.session", json!({ "sessionId": session_id }), None).await?;
    Ok(StatusCode::NO_CONTENT)
}

#[utoipa::path(get, path = "/v1/sessions/{id}/research", tag = "research", params(("id" = Uuid, Path)), responses((status = 200)))]
pub async fn list(State(st): State<AppState>, caller: Caller, Path(session_id): Path<Uuid>) -> Result<Json<Value>, ApiError> {
    let mut conn = st.notes.acquire().await?;
    access::session(&mut conn, &caller, session_id).await?;
    Ok(Json(sqlx::query_scalar(
        "SELECT COALESCE(json_agg(json_build_object('researchId', r.id, 'question', r.question, 'scope', r.scope, 'depth', r.depth, \
             'explanation', r.explanation, 'sourcesAgree', r.sources_agree, 'conflict', r.conflict, 'lowEvidence', r.low_evidence, \
             'saved', r.saved, 'createdAt', r.created_at, \
             'evidence', (SELECT COALESCE(json_agg(json_build_object('kind', s.kind, 'title', s.title, 'excerpt', s.excerpt, 'locator', s.locator, \
                 'url', s.url, 'trust', s.trust) ORDER BY s.ordinal), '[]') FROM research_sources s WHERE s.run_id = r.id)) \
             ORDER BY r.created_at DESC), '[]') FROM research_runs r WHERE r.session_id = $1")
        .bind(session_id).fetch_one(&mut *conn).await?))
}

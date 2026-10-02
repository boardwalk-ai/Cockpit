//! Ask Octo: one question about the app, one short answer. Not part of a
//! run, not saved, not charged.

use std::sync::Arc;

use axum::extract::State;
use axum::Json;
use octo_common::llm::parse_json_loose;
use octo_common::ApiError;
use serde::Deserialize;
use serde_json::{json, Value};

use super::clean_text;
use crate::agent::prompt;
use crate::ctx::Caller;
use crate::llm::{system, user, ChatRequest, Llm, OpenRouter};
use crate::AppState;

const QUESTION_LIMIT: usize = 500;
const DEFAULT_MODEL: &str = "google/gemini-3.1-flash-lite-preview";

#[derive(Deserialize)]
pub struct Ask {
    question: Option<String>,
}

/// `POST /v1/octo/ask` — `{ question }` → `{ answer }`.
pub async fn ask(
    State(st): State<AppState>,
    _caller: Caller,
    Json(body): Json<Ask>,
) -> Result<Json<Value>, ApiError> {
    let question = clean_text(body.question, QUESTION_LIMIT, "question")?
        .ok_or_else(|| ApiError::bad_request("question is required"))?;
    let unavailable = || ApiError::unavailable("Octo cannot answer right now.");

    let (llm, model): (Arc<dyn Llm>, String) = match (&st.llm, &st.octopilot) {
        (Some(llm), _) => (llm.clone(), DEFAULT_MODEL.to_string()),
        (None, Some(pool)) => {
            let key = octo_common::llm::openrouter_key(pool)
                .await
                .ok_or_else(unavailable)?;
            let model = octo_common::llm::model(pool, "secondary_model", DEFAULT_MODEL).await;
            (Arc::new(OpenRouter::new(st.http.clone(), key)), model)
        }
        (None, None) => return Err(unavailable()),
    };

    let reply = llm
        .chat(ChatRequest {
            model,
            messages: vec![system(prompt::OCTO), user(question)],
            temperature: Some(0.2),
            json: true,
            tools: Vec::new(),
        })
        .await
        .map_err(|error| {
            tracing::warn!(%error, "octo: the model failed");
            unavailable()
        })?;

    // The model is asked for {"answer": "..."}; one that replies in plain
    // text is taken at its word.
    let answer = parse_json_loose(&reply.content)
        .and_then(|value| value["answer"].as_str().map(str::trim).map(str::to_string))
        .unwrap_or_else(|| reply.content.trim().to_string());
    if answer.is_empty() {
        return Err(unavailable());
    }
    Ok(Json(json!({ "answer": answer })))
}

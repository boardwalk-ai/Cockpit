//! Ask Octo: one question about the app, one short answer. Not part of a
//! run, not saved, not charged. With `scope: "app"` it is the app's main
//! chat instead (Octopilot, about the whole app), which also sends the last
//! few turns of the conversation.

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
/// Earlier turns sent with a question, at most.
const HISTORY_TURNS: usize = 12;
const DEFAULT_MODEL: &str = "google/gemini-3.1-flash-lite-preview";

#[derive(Deserialize)]
pub struct Ask {
    question: Option<String>,
    /// `app`: the main chat. Otherwise Ask Octo inside GhostWriter.
    #[serde(default)]
    scope: Option<String>,
    /// Earlier turns, oldest first.
    #[serde(default)]
    history: Vec<Turn>,
}

#[derive(Deserialize)]
pub struct Turn {
    role: String,
    text: String,
}

/// `POST /v1/octo/ask` — `{ question, scope?, history? }` → `{ answer }`.
pub async fn ask(
    State(st): State<AppState>,
    caller: Caller,
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
    // The user's chosen fast model and voice. Octo keeps its own name.
    let ai = crate::agent::snapshot_for(&st, caller.user_id).await;
    let model = if st.llm.is_some() {
        model
    } else {
        ai.fast.clone().unwrap_or(model)
    };
    let main_chat = body.scope.as_deref() == Some("app");
    let name = if main_chat { "Octopilot" } else { "Octo" };
    let system_prompt = format!(
        "{}{}",
        if main_chat {
            prompt::MAIN_CHAT
        } else {
            prompt::OCTO
        },
        prompt::persona(name, ai.voice.as_deref())
    );
    let mut messages = vec![system(system_prompt)];
    let skip = body.history.len().saturating_sub(HISTORY_TURNS);
    for turn in body.history.into_iter().skip(skip) {
        let text: String = turn.text.chars().take(QUESTION_LIMIT * 2).collect();
        messages.push(match turn.role.as_str() {
            // Its own earlier answers, in the shape it is asked to reply in.
            "assistant" => json!({
                "role": "assistant",
                "content": json!({ "answer": text }).to_string(),
            }),
            _ => user(text),
        });
    }
    messages.push(user(question));

    let reply = llm
        .chat(ChatRequest {
            model,
            messages,
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
    let terms = octo_common::ai::masked_terms(st.octopilot.as_ref()).await;
    let (answer, _) = octo_common::ai::mask(&answer, &terms, name);
    Ok(Json(json!({ "answer": answer })))
}

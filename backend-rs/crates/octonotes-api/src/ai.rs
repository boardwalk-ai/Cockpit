//! Shared AI plumbing: model per role, offline stand-in, per-user rate limit,
//! `ai_runs` bookkeeping, and the SSE response shape.
//!
//! SSE events: `delta` {text} · `source` {…} · `result` {…} · `done`
//! {runId, creditsCharged} · `error` {message, code}. If the client
//! disconnects mid-stream the stream is dropped and nothing is charged.

use std::collections::{HashMap, VecDeque};
use std::convert::Infallible;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use axum::http::StatusCode;
use axum::response::sse::{Event as SseEvent, KeepAlive, Sse};
use futures::stream::BoxStream;
use futures::{Stream, StreamExt};
use octo_common::llm::{self, ChatOptions, Message, OpenRouter, Usage};
use octo_common::ApiError;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::ctx::Caller;
use crate::AppState;

/// Which model a feature uses. Each maps to a `system_settings` key so admins
/// can switch models without a deploy.
#[derive(Clone, Copy)]
pub enum Role {
    /// Explanations, commands, organization (quality).
    Primary,
    /// Bulk / fast work (summaries of long input, recommendations).
    Fast,
    /// Images (handwriting, board photos, scanned slides).
    Vision,
    /// Web research with citations.
    Search,
}

impl Role {
    fn setting(self) -> (&'static str, &'static str, &'static str) {
        match self {
            Role::Primary => (
                "octonotes_model_primary",
                "primary_model",
                "anthropic/claude-sonnet-4-6",
            ),
            Role::Fast => (
                "octonotes_model_fast",
                "secondary_model",
                "google/gemini-3.1-flash-lite-preview",
            ),
            Role::Vision => (
                "octonotes_model_vision",
                "secondary_model",
                "google/gemini-3.1-flash-lite-preview",
            ),
            Role::Search => (
                "octonotes_model_search",
                "source_search_model",
                "perplexity/sonar-pro-search",
            ),
        }
    }
}

pub enum Llm {
    Remote {
        client: OpenRouter,
        model: String,
    },
    /// No key configured (dev/tests): deterministic output supplied by the caller.
    Offline,
}

impl Llm {
    pub async fn for_role(st: &AppState, role: Role) -> Llm {
        let Some(pool) = &st.octopilot else {
            return Llm::Offline;
        };
        let Some(key) = llm::openrouter_key(pool).await else {
            return Llm::Offline;
        };
        let (own, shared, default) = role.setting();
        let model = match llm::setting(pool, own).await {
            Some(m) => m,
            None => llm::model(pool, shared, default).await,
        };
        Llm::Remote {
            client: OpenRouter::new(st.http.clone(), key),
            model,
        }
    }

    pub fn model_name(&self) -> String {
        match self {
            Llm::Remote { model, .. } => model.clone(),
            Llm::Offline => "offline".into(),
        }
    }

    /// One completion; `offline` is the answer when no model is configured.
    pub async fn complete(
        &self,
        messages: &[Message],
        o: &ChatOptions,
        offline: impl FnOnce() -> String,
    ) -> Result<(String, Usage), ApiError> {
        match self {
            Llm::Remote { client, model } => client
                .chat(model, messages, o)
                .await
                .map_err(ApiError::bad_gateway),
            Llm::Offline => Ok((offline(), Usage::default())),
        }
    }

    /// Streamed completion as text deltas.
    pub async fn stream(
        &self,
        messages: &[Message],
        o: &ChatOptions,
        offline: impl FnOnce() -> String,
    ) -> Result<BoxStream<'static, Result<String, String>>, ApiError> {
        match self {
            Llm::Remote { client, model } => Ok(client
                .chat_stream(model, messages, o)
                .await
                .map_err(ApiError::bad_gateway)?
                .boxed()),
            Llm::Offline => {
                let text = offline();
                // Word-sized deltas, like a real stream.
                let parts: Vec<Result<String, String>> = text
                    .split_inclusive(' ')
                    .map(|w| Ok(w.to_string()))
                    .collect();
                Ok(futures::stream::iter(parts).boxed())
            }
        }
    }
}

/// Sliding-window limit: at most `max` AI calls per user per minute.
#[derive(Clone, Default)]
pub struct RateLimiter {
    inner: Arc<Mutex<HashMap<Uuid, VecDeque<Instant>>>>,
}

impl RateLimiter {
    pub fn check(&self, user: Uuid, max: usize) -> Result<(), ApiError> {
        let mut map = self.inner.lock().expect("rate lock");
        let q = map.entry(user).or_default();
        let now = Instant::now();
        while q
            .front()
            .is_some_and(|t| now.duration_since(*t) > Duration::from_secs(60))
        {
            q.pop_front();
        }
        if q.len() >= max {
            return Err(ApiError::new(
                StatusCode::TOO_MANY_REQUESTS,
                "Too many AI requests — try again in a minute.",
            )
            .with_code("rate_limited"));
        }
        q.push_back(now);
        Ok(())
    }
}

pub const AI_PER_MINUTE: usize = 30;

/// Rate limit + credit pre-check before any paid AI work.
pub async fn guard(st: &AppState, caller: &Caller, price: i32) -> Result<(), ApiError> {
    st.rate.check(caller.user_id, AI_PER_MINUTE)?;
    st.credits.precheck(caller.user_id, price).await
}

pub async fn start_run(
    st: &AppState,
    caller: &Caller,
    session_id: Option<Uuid>,
    kind: &str,
    command: Option<&str>,
    contexts: &Value,
) -> Result<Uuid, ApiError> {
    Ok(sqlx::query_scalar("INSERT INTO ai_runs (session_id, user_id, kind, command, contexts) VALUES ($1,$2,$3,$4,$5) RETURNING id")
        .bind(session_id)
        .bind(caller.user_id)
        .bind(kind)
        .bind(command)
        .bind(contexts)
        .fetch_one(&st.notes)
        .await?)
}

/// What a finished AI run produced.
pub struct Outcome<'a> {
    pub kind: &'a str,
    pub response: &'a Value,
    pub model: &'a str,
    pub usage: &'a Usage,
    pub price: i32,
}

/// Marks a run done, charges its price once (`octonotes:{kind}:{run}`), and
/// returns the credits charged.
pub async fn finish_run(
    st: &AppState,
    caller: &Caller,
    run: Uuid,
    o: Outcome<'_>,
) -> Result<i32, ApiError> {
    let Outcome {
        kind,
        response,
        model,
        usage,
        price,
    } = o;
    let charged = crate::pricing::charge(
        st,
        caller.user_id,
        price,
        &format!("octonotes:{kind}:{run}"),
        &format!("OctoNotes {kind}"),
    )
    .await?;
    sqlx::query(
        "UPDATE ai_runs SET status = 'done', response = $2, model = $3, tokens_in = $4, tokens_out = $5, credits_charged = $6 WHERE id = $1",
    )
    .bind(run)
    .bind(response)
    .bind(model)
    .bind(usage.prompt_tokens as i32)
    .bind(usage.completion_tokens as i32)
    .bind(charged)
    .execute(&st.notes)
    .await?;
    Ok(charged)
}

pub async fn fail_run(st: &AppState, run: Uuid, error: &str) {
    let _ = sqlx::query("UPDATE ai_runs SET status = 'failed', error = $2 WHERE id = $1")
        .bind(run)
        .bind(error)
        .execute(&st.notes)
        .await;
}

pub fn event(name: &str, data: Value) -> Result<SseEvent, Infallible> {
    Ok(SseEvent::default().event(name).data(data.to_string()))
}

pub type SseStream = Sse<BoxStream<'static, Result<SseEvent, Infallible>>>;

pub fn sse(stream: impl Stream<Item = Result<SseEvent, Infallible>> + Send + 'static) -> SseStream {
    Sse::new(stream.boxed()).keep_alive(KeepAlive::new().interval(Duration::from_secs(15)))
}

/// Truncates to at most `max` chars on a char boundary.
pub fn clip(s: &str, max: usize) -> String {
    if s.chars().count() <= max {
        s.to_string()
    } else {
        s.chars().take(max).collect::<String>() + "…"
    }
}

/// Error payload for an SSE `error` event.
pub fn error_data(e: &ApiError) -> Value {
    json!({ "message": e.message, "code": e.code, "details": e.details })
}

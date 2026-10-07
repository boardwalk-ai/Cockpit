//! Study Studio backend: the Rust replacement for `Backend/` (Python
//! cockpit-api) and the Go worker/gateway. It speaks the same HTTP + SSE
//! contract, so the app needs no change at the cutover.
//!
//! So far: R1 reads (health, readiness, `/me`, studios) and R2 progress
//! writes (quiz, cards, "Got it", rename, activity) — idempotent with the
//! app's `event_id`. Against the cockpit + vector databases in octo-pg.

pub mod config;
pub mod dto;
pub mod identity;
pub mod progress;
pub mod schedule;
pub mod sse;
pub mod studios;

use axum::{
    extract::State,
    http::StatusCode,
    routing::{get, post},
    Json, Router,
};
use octo_common::{identity::UserIdCache, FirebaseAuth, HasFirebase};
use serde_json::json;
use sqlx::PgPool;
use tower_http::trace::TraceLayer;

use crate::config::Config;

#[derive(Clone)]
pub struct AppState {
    pub config: Config,
    pub cockpit: PgPool,
    pub vector: PgPool,
    /// The octopilot DB (users, credits). None in dev without it.
    pub shared: Option<PgPool>,
    pub firebase: FirebaseAuth,
    pub user_ids: UserIdCache,
    pub http: reqwest::Client,
}

impl HasFirebase for AppState {
    fn firebase(&self) -> &FirebaseAuth {
        &self.firebase
    }
}

impl AppState {
    pub async fn connect(config: Config) -> Result<Self, sqlx::Error> {
        let cockpit = octo_common::db::connect(&config.cockpit_database_url, 10).await?;
        let vector = octo_common::db::connect(&config.vector_database_url, 5).await?;
        let shared = match &config.shared_database_url {
            Some(url) => Some(octo_common::db::connect(url, 5).await?),
            None => None,
        };
        let http = reqwest::Client::new();
        Ok(Self {
            firebase: FirebaseAuth::new(config.firebase_project_id.clone(), http.clone()),
            config,
            cockpit,
            vector,
            shared,
            user_ids: UserIdCache::default(),
            http,
        })
    }
}

async fn health() -> Json<serde_json::Value> {
    Json(json!({ "ok": true }))
}

/// Ready when every database answers and the embedder has a model loaded.
async fn ready(State(state): State<AppState>) -> (StatusCode, Json<serde_json::Value>) {
    let cockpit = octo_common::db::ping(&state.cockpit).await;
    let vector = octo_common::db::ping(&state.vector).await;
    let shared = match &state.shared {
        Some(p) => octo_common::db::ping(p).await,
        None => true,
    };
    let embed = if state.config.embed_service_url.is_empty() {
        false
    } else {
        state
            .http
            .get(format!("{}/ready", state.config.embed_service_url.trim_end_matches('/')))
            .timeout(std::time::Duration::from_secs(3))
            .send()
            .await
            .map(|r| r.status().is_success())
            .unwrap_or(false)
    };
    let ok = cockpit && vector && shared && embed;
    (
        if ok { StatusCode::OK } else { StatusCode::SERVICE_UNAVAILABLE },
        Json(json!({ "ok": ok, "cockpit": cockpit, "vector": vector, "shared": shared, "embed": embed })),
    )
}

pub fn app(state: AppState) -> Router {
    Router::new()
        .route("/health", get(health))
        .route("/ready", get(ready))
        .route("/me", get(studios::me))
        .route("/studios", get(studios::list))
        .route("/studios/:studio_id", get(studios::get))
        .route("/studios/:studio_id/rename", post(progress::rename))
        .route("/studios/:studio_id/activity", get(progress::activity))
        .route("/studios/:studio_id/topics/:topic_id/quiz-result", post(progress::quiz_result))
        .route("/studios/:studio_id/topics/:topic_id/flashcard-review", post(progress::flashcard_review))
        .route("/studios/:studio_id/topics/:topic_id/mark-reviewed", post(progress::mark_reviewed))
        .route("/studios/:studio_id/flashcards/:card_id/review", post(progress::card_review))
        .layer(TraceLayer::new_for_http())
        .with_state(state)
}

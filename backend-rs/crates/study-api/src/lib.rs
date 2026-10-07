//! Study Studio backend: the Rust replacement for `Backend/` (Python
//! cockpit-api) and the Go worker/gateway. It speaks the same HTTP + SSE
//! contract, so the app needs no change at the cutover.
//!
//! So far: R1 reads (health, readiness, `/me`, studios), R2 progress writes
//! (quiz, cards, "Got it", rename, activity — idempotent with the app's
//! `event_id`), R3 ingestion, R4 search + Ask AI, R5 studio builds (and
//! create / delete studio), R6 notifications. Against the cockpit + vector databases in octo-pg.

pub mod ask;
pub mod build;
pub mod chunk;
pub mod config;
pub mod documents;
pub mod dto;
pub mod extract;
pub mod gen;
pub mod identity;
pub mod ingest;
pub mod llm;
pub mod notify;
pub mod progress;
pub mod schedule;
pub mod search;
pub mod sse;
pub mod storage;
pub mod studios;

use std::sync::Arc;

use axum::{
    extract::{DefaultBodyLimit, State},
    http::StatusCode,
    routing::{get, post},
    Json, Router,
};
use octo_common::push::{FcmPusher, NoPusher, Pusher};
use octo_common::{identity::UserIdCache, FirebaseAuth, HasFirebase};
use serde_json::json;
use sqlx::PgPool;
use tokio::sync::Notify;
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
    /// Uploaded files (None if MinIO isn't configured).
    pub store: Option<storage::Store>,
    /// Wakes an ingest worker when a job is queued.
    pub jobs: Arc<Notify>,
    /// Wakes a build worker when a build is queued.
    pub builds: Arc<Notify>,
    /// Push notifications (does nothing without an FCM key file).
    pub pusher: Arc<dyn Pusher>,
    /// Wakes the notification sender when one is queued.
    pub notices: Arc<Notify>,
    /// Ask AI questions per user per 10 minutes.
    pub ask_limit: Arc<ask::RateLimit>,
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
        let config_store = config.clone();
        let pusher: Arc<dyn Pusher> = match &config.fcm_service_account_file {
            Some(path) => match FcmPusher::from_file(http.clone(), path, notify::CHANNEL) {
                Ok(p) => Arc::new(p),
                Err(e) => {
                    tracing::warn!("push off: {e}");
                    Arc::new(NoPusher)
                }
            },
            None => Arc::new(NoPusher),
        };
        Ok(Self {
            firebase: FirebaseAuth::new(config.firebase_project_id.clone(), http.clone()),
            config,
            cockpit,
            vector,
            shared,
            user_ids: UserIdCache::default(),
            store: storage::Store::new(&config_store).ok(),
            jobs: Arc::new(Notify::new()),
            builds: Arc::new(Notify::new()),
            pusher,
            notices: Arc::new(Notify::new()),
            ask_limit: Arc::new(ask::RateLimit::default()),
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
        .route("/ask", get(ask::ask))
        .route("/studios", get(studios::list).post(studios::create))
        .route("/studios/:studio_id", get(studios::get).delete(studios::delete))
        .route("/studios/:studio_id/build", post(build::start))
        .route("/studios/:studio_id/build-status/:build_id", get(build::status))
        .route("/studios/:studio_id/connections", post(build::connections))
        .route("/studios/:studio_id/plan", post(notify::put_plan))
        .route("/devices", post(notify::put_device))
        .route("/devices/:device_id", axum::routing::delete(notify::remove_device))
        .route("/studios/:studio_id/topics/:topic_id/concepts", post(build::concepts))
        .route("/studios/:studio_id/rename", post(progress::rename))
        .route("/studios/:studio_id/activity", get(progress::activity))
        .route("/studios/:studio_id/topics/:topic_id/quiz-result", post(progress::quiz_result))
        .route("/studios/:studio_id/topics/:topic_id/flashcard-review", post(progress::flashcard_review))
        .route("/studios/:studio_id/topics/:topic_id/mark-reviewed", post(progress::mark_reviewed))
        .route("/studios/:studio_id/flashcards/:card_id/review", post(progress::card_review))
        .route(
            "/studios/:studio_id/documents",
            get(documents::list)
                .post(documents::upload)
                .layer(DefaultBodyLimit::max((state.config.max_upload_mb + 1) * 1024 * 1024)),
        )
        .route("/studios/:studio_id/build/:job_id", get(documents::progress))
        .layer(TraceLayer::new_for_http())
        .with_state(state)
}

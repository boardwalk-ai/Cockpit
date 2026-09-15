//! Octopilot Rust backend.
//!
//! First slice: the stateless tool proxies (Dictionary · Thesaurus ·
//! Paraphraser) plus Firebase auth (reused from the FastAPI). Source search and
//! the outline service land next. No credits are charged yet.

mod auth;
mod config;
mod error;
mod openrouter;
mod sources;
mod tools;

use std::sync::Arc;

use axum::routing::{get, post};
use axum::{Json, Router};
use serde_json::json;
use tokio::net::TcpListener;
use tokio::sync::RwLock;
use tower_http::cors::CorsLayer;

#[derive(Clone)]
pub struct AppState {
    pub http: reqwest::Client,
    pub config: Arc<config::Config>,
    pub jwks: auth::SharedJwks,
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "octopilot_rs=info,tower_http=info".into()),
        )
        .init();

    let config = config::Config::from_env();
    let port = config.port;
    let state = AppState {
        http: reqwest::Client::builder()
            .user_agent("octopilot-rs/0.1")
            .timeout(std::time::Duration::from_secs(20))
            .build()
            .expect("http client"),
        config: Arc::new(config),
        jwks: Arc::new(RwLock::new(auth::JwksCache::default())),
    };

    let app = Router::new()
        .route("/health", get(health))
        .route("/v1/dictionary", get(tools::dictionary))
        .route("/v1/thesaurus", get(tools::thesaurus))
        .route("/v1/paraphrase", post(tools::paraphrase))
        .route("/v1/scrape", get(sources::scrape))
        .route("/v1/sources/search", post(sources::search))
        .route("/v1/me", get(me))
        .layer(CorsLayer::permissive())
        .with_state(state);

    let addr = ("0.0.0.0", port);
    let listener = TcpListener::bind(addr).await.expect("bind");
    tracing::info!("octopilot-rs listening on http://0.0.0.0:{port}");
    axum::serve(listener, app).await.expect("serve");
}

async fn health() -> Json<serde_json::Value> {
    Json(json!({ "status": "ok" }))
}

/// Whoami — proves Firebase auth works end to end (no credits attached yet).
async fn me(user: auth::AuthedUser) -> Json<serde_json::Value> {
    Json(json!({ "uid": user.uid, "email": user.email }))
}

//! Octopilot Rust backend.
//!
//! Serves the Flutter app (octopilotai.app): stateless tools (Dictionary ·
//! Thesaurus · Paraphraser), source search + scrape, OctoBot chat, outline
//! generation, saved essays, and a credits-aware whoami. Keys, models, users,
//! credits and essays all come from the shared Postgres (same DB as the FastAPI
//! side); Firebase ID tokens are verified the same way.

mod auth;
mod config;
mod db;
mod error;
mod essays;
mod octobot;
mod openrouter;
mod outline;
mod sources;
mod tools;

use std::sync::Arc;

use axum::routing::{delete, get, post};
use axum::{Json, Router};
use serde_json::json;
use sqlx::PgPool;
use tokio::net::TcpListener;
use tokio::sync::RwLock;
use tower_http::cors::CorsLayer;

#[derive(Clone)]
pub struct AppState {
    pub http: reqwest::Client,
    pub config: Arc<config::Config>,
    pub jwks: auth::SharedJwks,
    pub db: PgPool,
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

    let pool = db::connect(&config.database_url)
        .await
        .expect("connect to Postgres");
    tracing::info!("connected to Postgres");

    let state = AppState {
        http: reqwest::Client::builder()
            .user_agent("octopilot-rs/0.1")
            .timeout(std::time::Duration::from_secs(30))
            .build()
            .expect("http client"),
        config: Arc::new(config),
        jwks: Arc::new(RwLock::new(auth::JwksCache::default())),
        db: pool,
    };

    let app = Router::new()
        .route("/health", get(health))
        .route("/v1/dictionary", get(tools::dictionary))
        .route("/v1/thesaurus", get(tools::thesaurus))
        .route("/v1/paraphrase", post(tools::paraphrase))
        .route("/v1/scrape", get(sources::scrape))
        .route("/v1/sources/search", post(sources::search))
        .route("/v1/octobot/chat", post(octobot::chat))
        .route("/v1/outline", post(outline::outline))
        .route("/v1/me", get(me))
        .route("/v1/essays", get(essays::list).post(essays::save))
        .route("/v1/essays/:id", get(essays::get_one).delete(essays::remove))
        .route("/v1/essays/:id/", delete(essays::remove))
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

/// Whoami + credits — the account the Firebase token belongs to, joined to the
/// shared `users` row. Unknown users (no row yet) return just the token identity.
async fn me(
    axum::extract::State(st): axum::extract::State<AppState>,
    user: auth::AuthedUser,
) -> Result<Json<serde_json::Value>, error::ApiError> {
    let row = db::user_by_firebase_uid(&st.db, &user.uid).await?;
    match row {
        Some(u) => Ok(Json(json!({ "uid": user.uid, "email": user.email, "user": u }))),
        None => Ok(Json(json!({ "uid": user.uid, "email": user.email, "user": null }))),
    }
}

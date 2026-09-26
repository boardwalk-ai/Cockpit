pub mod config;
mod routes;

use std::sync::Arc;

use axum::http::{header, HeaderName, HeaderValue, Method};
use axum::routing::get;
use axum::Router;
use octo_common::identity::UserIdCache;
use octo_common::{FirebaseAuth, HasFirebase};
use sqlx::PgPool;
use tower_http::cors::{AllowOrigin, CorsLayer};
use tower_http::trace::TraceLayer;

use crate::config::Config;

/// Embedded `notes_db` migrations (see `migrations/`).
pub static MIGRATOR: sqlx::migrate::Migrator = sqlx::migrate!("./migrations");

#[derive(Clone)]
pub struct AppState {
    pub config: Arc<Config>,
    pub http: reqwest::Client,
    pub firebase: FirebaseAuth,
    /// `notes_db`, owned by this service.
    pub notes: PgPool,
    /// Shared octopilot DB (users + OctoCredits), read-only in Phase 0.
    pub octopilot: Option<PgPool>,
    /// Study Studio business DB, read-only.
    pub studio: Option<PgPool>,
    pub user_ids: UserIdCache,
}

impl HasFirebase for AppState {
    fn firebase(&self) -> &FirebaseAuth {
        &self.firebase
    }
}

impl AppState {
    /// Connects every pool and brings `notes_db` up to date.
    pub async fn connect(config: Config) -> Result<Self, Box<dyn std::error::Error>> {
        let notes = octo_common::db::connect(&config.notes_database_url, 20).await?;
        MIGRATOR.run(&notes).await?;
        tracing::info!("notes_db connected and migrated");

        let octopilot = match &config.octopilot_database_url {
            Some(url) => Some(octo_common::db::connect(url, 5).await?),
            None => {
                tracing::warn!("OCTOPILOT_DATABASE_URL not set — /v1/me returns token identity only");
                None
            }
        };
        let studio = match &config.studio_database_url {
            Some(url) => Some(octo_common::db::connect(url, 5).await?),
            None => None,
        };

        let http = reqwest::Client::builder()
            .user_agent("octonotes-api/0.1")
            .timeout(std::time::Duration::from_secs(30))
            .build()?;
        if config.firebase_project_id.trim().is_empty() {
            tracing::warn!("FIREBASE_PROJECT_ID empty — auth disabled, X-User-Id trusted (dev only)");
        }

        Ok(Self {
            firebase: FirebaseAuth::new(config.firebase_project_id.clone(), http.clone()),
            http,
            config: Arc::new(config),
            notes,
            octopilot,
            studio,
            user_ids: UserIdCache::default(),
        })
    }
}

pub fn app(state: AppState) -> Router {
    Router::new()
        .route("/health", get(routes::health))
        .route("/ready", get(routes::ready))
        .route("/v1/me", get(routes::me))
        .layer(cors(&state.config))
        .layer(TraceLayer::new_for_http())
        .with_state(state)
}

/// Only the configured app origins (plus localhost in dev) — never permissive.
fn cors(config: &Config) -> CorsLayer {
    let allowed = config.cors_origins.clone();
    let localhost = config.cors_allow_localhost;
    CorsLayer::new()
        .allow_origin(AllowOrigin::predicate(move |origin: &HeaderValue, _| {
            let Ok(o) = origin.to_str() else { return false };
            allowed.iter().any(|a| a == o)
                || (localhost
                    && (o.starts_with("http://localhost:") || o.starts_with("http://127.0.0.1:")))
        }))
        .allow_methods([Method::GET, Method::POST, Method::PUT, Method::PATCH, Method::DELETE])
        .allow_headers([
            header::AUTHORIZATION,
            header::CONTENT_TYPE,
            HeaderName::from_static("x-user-id"),
            HeaderName::from_static("idempotency-key"),
        ])
}

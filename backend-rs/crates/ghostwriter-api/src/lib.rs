pub mod config;
pub mod ctx;
pub mod routes;
pub mod runs;

use std::sync::Arc;
use std::time::Duration;

use axum::http::{header, HeaderName, HeaderValue, Method};
use axum::routing::{get, post, put};
use axum::Router;
use octo_common::identity::UserIdCache;
use octo_common::{FirebaseAuth, HasFirebase};
use sqlx::PgPool;
use tower_http::cors::{AllowOrigin, CorsLayer};
use tower_http::request_id::{MakeRequestUuid, PropagateRequestIdLayer, SetRequestIdLayer};
use tower_http::trace::TraceLayer;

use crate::config::Config;
use crate::routes::{folders, projects, runs as run_routes, system};
use crate::runs::Hub;

/// Embedded `ghostwriter` migrations (see `migrations/`).
pub static MIGRATOR: sqlx::migrate::Migrator = sqlx::migrate!("./migrations");

#[derive(Clone)]
pub struct AppState {
    pub config: Arc<Config>,
    pub http: reqwest::Client,
    pub firebase: FirebaseAuth,
    /// The `ghostwriter` database, owned by this service.
    pub db: PgPool,
    /// Shared octopilot DB (users, OctoCredits, keys, models).
    pub octopilot: Option<PgPool>,
    pub user_ids: UserIdCache,
    /// The central OctoCredits balance (shared protocol, octo-common).
    pub credits: octo_common::credits::Credits,
    /// The runs this process is driving.
    pub hub: Hub,
}

impl HasFirebase for AppState {
    fn firebase(&self) -> &FirebaseAuth {
        &self.firebase
    }
}

impl AppState {
    /// Connects the pools and brings the `ghostwriter` database up to date.
    pub async fn connect(config: Config) -> Result<Self, Box<dyn std::error::Error>> {
        let db = octo_common::db::connect(&config.ghostwriter_database_url, 20).await?;
        MIGRATOR.run(&db).await?;
        tracing::info!("ghostwriter database connected and migrated");
        let interrupted = runs::recover_interrupted(&db).await?;
        if interrupted > 0 {
            tracing::warn!("closed {interrupted} runs interrupted by a restart");
        }

        let octopilot = match &config.octopilot_database_url {
            Some(url) => Some(octo_common::db::connect(url, 5).await?),
            None => {
                tracing::warn!("OCTOPILOT_DATABASE_URL not set — dev identities, no credits");
                None
            }
        };

        let http = reqwest::Client::builder()
            .user_agent("ghostwriter-api/0.1")
            .timeout(Duration::from_secs(120))
            .build()?;
        if config.firebase_project_id.trim().is_empty() {
            tracing::warn!(
                "FIREBASE_PROJECT_ID empty — auth disabled, X-User-Id trusted (dev only)"
            );
        }

        let credits = octo_common::credits::Credits::new(
            octopilot.clone(),
            config.credits_ledger_type.clone(),
            config.credits_enabled,
        );
        Ok(Self {
            credits,
            firebase: FirebaseAuth::new(config.firebase_project_id.clone(), http.clone()),
            http,
            db,
            octopilot,
            user_ids: UserIdCache::default(),
            hub: Hub::default(),
            config: Arc::new(config),
        })
    }
}

pub fn app(state: AppState) -> Router {
    let request_id = HeaderName::from_static("x-request-id");
    Router::new()
        .route("/health", get(system::health))
        .route("/ready", get(system::ready))
        .route("/v1/me", get(system::me))
        .route("/v1/projects", get(projects::list))
        .route(
            "/v1/projects/:id",
            put(projects::put)
                .get(projects::get_one)
                .delete(projects::remove),
        )
        .route("/v1/folders/:id", put(folders::put).delete(folders::remove))
        .route("/v1/projects/:id/runs", post(run_routes::start))
        .route("/v1/runs/:run_id", get(run_routes::get_one))
        .route("/v1/runs/:run_id/events", get(run_routes::events))
        .route("/v1/runs/:run_id/answer", post(run_routes::answer))
        .route("/v1/runs/:run_id/message", post(run_routes::message))
        .route("/v1/runs/:run_id/cancel", post(run_routes::cancel))
        .layer(cors(&state.config))
        .layer(PropagateRequestIdLayer::new(request_id.clone()))
        .layer(TraceLayer::new_for_http())
        .layer(SetRequestIdLayer::new(request_id, MakeRequestUuid))
        .with_state(state)
}

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
        .allow_methods([Method::GET, Method::POST, Method::PUT, Method::DELETE])
        .allow_headers([
            header::AUTHORIZATION,
            header::CONTENT_TYPE,
            HeaderName::from_static("x-user-id"),
            HeaderName::from_static("x-client-version"),
            HeaderName::from_static("last-event-id"),
        ])
        .expose_headers([HeaderName::from_static("x-request-id")])
}

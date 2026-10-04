pub mod agent;
pub mod app_status;
pub mod attachments;
pub mod config;
pub mod ctx;
pub mod documents;
pub mod humanize;
pub mod live_docs;
pub mod llm;
pub mod pricing;
pub mod push;
pub mod routes;
pub mod runs;
pub mod safety;
pub mod scrape;
pub mod sweeper;

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
use crate::humanize::{HttpHumanizer, Humanizer};
use crate::live_docs::LiveDocs;
use crate::llm::Llm;
use crate::push::{FcmPusher, NoPusher, Pusher};
use crate::routes::{
    ai as ai_routes, attachments as attachment_routes, devices, documents as doc_routes, folders,
    octo, projects, runs as run_routes, system,
};
use crate::runs::worker::WorkerHandle;
use crate::runs::Hub;
use crate::scrape::{HttpScraper, Scraper};

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
    /// This process's place in the run queue.
    pub worker: WorkerHandle,
    /// Live text for open editors while the agent writes.
    pub docs: LiveDocs,
    /// A model to use instead of OpenRouter. Tests set this; production
    /// leaves it empty and each run takes a key from the shared pool.
    pub llm: Option<Arc<dyn Llm>>,
    pub scraper: Arc<dyn Scraper>,
    pub humanizer: Arc<dyn Humanizer>,
    /// Content checks on what runs are asked to write (src/safety.rs).
    pub screen: Arc<dyn safety::Screen>,
    /// Sends push notifications; does nothing when FCM is not configured.
    pub pusher: Arc<dyn Pusher>,
    /// Models, personalities and prices from the shared DB (cached).
    pub ai: octo_common::ai::AiSettings,
    /// Update and maintenance settings from the shared DB (cached).
    pub app_status: app_status::AppStatus,
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

        let pusher: Arc<dyn Pusher> = match &config.fcm_service_account_file {
            Some(path) => Arc::new(FcmPusher::from_file(http.clone(), path)?),
            None => {
                tracing::warn!("FCM_SERVICE_ACCOUNT_FILE not set — no push notifications");
                Arc::new(NoPusher)
            }
        };

        let credits = octo_common::credits::Credits::new(
            octopilot.clone(),
            config.credits_ledger_type.clone(),
            config.credits_enabled,
        );
        Ok(Self {
            credits,
            firebase: FirebaseAuth::new(config.firebase_project_id.clone(), http.clone()),
            scraper: Arc::new(HttpScraper::new(http.clone(), config.scraper_url.clone())),
            humanizer: Arc::new(HttpHumanizer::new(http.clone(), octopilot.clone())),
            screen: Arc::new(safety::Moderation::new(http.clone(), octopilot.clone())),
            pusher,
            ai: octo_common::ai::AiSettings::default(),
            app_status: app_status::AppStatus::default(),
            http,
            db,
            octopilot,
            user_ids: UserIdCache::default(),
            hub: Hub::default(),
            worker: WorkerHandle::default(),
            docs: LiveDocs::default(),
            llm: None,
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
        .route("/v1/app/status", get(system::app_status))
        .route("/v1/octo/ask", post(octo::ask))
        .route("/v1/ai/catalog", get(ai_routes::catalog))
        .route("/v1/ai/preferences", get(ai_routes::preferences))
        .route("/v1/ai/preferences/:scope", put(ai_routes::put_preference))
        .route("/v1/projects", get(projects::list))
        .route(
            "/v1/projects/:id",
            put(projects::put)
                .get(projects::get_one)
                .delete(projects::remove),
        )
        .route("/v1/folders/:id", put(folders::put).delete(folders::remove))
        .route("/v1/devices/:id", put(devices::put).delete(devices::remove))
        .route(
            "/v1/projects/:id/document",
            get(doc_routes::get_one).put(doc_routes::save),
        )
        .route("/v1/projects/:id/document/stream", get(doc_routes::stream))
        .route("/v1/projects/:id/versions", get(doc_routes::versions))
        .route(
            "/v1/projects/:id/versions/:version_id/restore",
            post(doc_routes::restore),
        )
        .route(
            "/v1/projects/:id/attachments",
            post(attachment_routes::upload)
                .get(attachment_routes::list)
                // A 20 MB file, as base64 in JSON.
                .layer(axum::extract::DefaultBodyLimit::max(28 * 1024 * 1024)),
        )
        .route(
            "/v1/attachments/:id",
            axum::routing::delete(attachment_routes::remove),
        )
        .route("/v1/projects/:id/runs", post(run_routes::start))
        .route("/v1/runs/:run_id", get(run_routes::get_one))
        .route("/v1/runs/:run_id/events", get(run_routes::events))
        .route("/v1/runs/:run_id/answer", post(run_routes::answer))
        .route("/v1/runs/:run_id/message", post(run_routes::message))
        .route("/v1/runs/:run_id/cancel", post(run_routes::cancel))
        .layer(axum::middleware::from_fn_with_state(
            state.clone(),
            app_status::guard,
        ))
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

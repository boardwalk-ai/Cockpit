pub mod access;
pub mod ai;
pub mod asr;
pub mod config;
pub mod ctx;
pub mod export;
pub mod idempotency;
pub mod jobs;
pub mod metrics;
pub mod openapi;
pub mod outbox;
pub mod positions;
pub mod pricing;
pub mod realtime;
pub mod retrieval;
pub mod revs;
pub mod routes;
pub mod storage;
pub mod studio_client;

use std::sync::Arc;
use std::time::Duration;

use axum::extract::DefaultBodyLimit;
use axum::http::{header, HeaderName, HeaderValue, Method, Request};
use axum::routing::{get, patch, post};
use axum::Router;
use octo_common::identity::UserIdCache;
use octo_common::{FirebaseAuth, HasFirebase};
use sqlx::PgPool;
use tower_http::cors::{AllowOrigin, CorsLayer};
use tower_http::request_id::{MakeRequestUuid, PropagateRequestIdLayer, SetRequestIdLayer};
use tower_http::trace::TraceLayer;

use crate::config::Config;
use crate::realtime::Hub;
use crate::routes::*;
use crate::storage::Storage;

/// Embedded `notes_db` migrations (see `migrations/`).
pub static MIGRATOR: sqlx::migrate::Migrator = sqlx::migrate!("./migrations");

#[derive(Clone)]
pub struct AppState {
    pub config: Arc<Config>,
    pub http: reqwest::Client,
    pub firebase: FirebaseAuth,
    /// `notes_db`, owned by this service.
    pub notes: PgPool,
    /// Shared octopilot DB (users, OctoCredits, keys, models).
    pub octopilot: Option<PgPool>,
    /// Study Studio business DB, read-only.
    pub studio: Option<PgPool>,
    /// Study Studio RAG vectors, read-only.
    pub studio_vector: Option<PgPool>,
    pub user_ids: UserIdCache,
    pub hub: Hub,
    pub storage: Storage,
    /// The central OctoCredits balance (shared protocol, octo-common).
    pub credits: octo_common::credits::Credits,
    pub rate: ai::RateLimiter,
    /// Uploads (audio chunks, materials) per user per minute.
    pub upload_rate: ai::RateLimiter,
    pub prices: pricing::PriceCache,
    pub metrics: metrics::Metrics,
}

impl HasFirebase for AppState {
    fn firebase(&self) -> &FirebaseAuth {
        &self.firebase
    }
}

impl AppState {
    /// Connects every pool and store and brings `notes_db` up to date.
    pub async fn connect(config: Config) -> Result<Self, Box<dyn std::error::Error>> {
        let notes = octo_common::db::connect(&config.notes_database_url, 20).await?;
        MIGRATOR.run(&notes).await?;
        tracing::info!("notes_db connected and migrated");

        let optional = |url: &Option<String>| {
            let url = url.clone();
            async move {
                match url {
                    Some(u) => octo_common::db::connect(&u, 5).await.map(Some),
                    None => Ok(None),
                }
            }
        };
        let octopilot = optional(&config.octopilot_database_url).await?;
        if octopilot.is_none() {
            tracing::warn!("OCTOPILOT_DATABASE_URL not set — dev identities, no credits");
        }
        let studio = optional(&config.studio_database_url).await?;
        let studio_vector = optional(&config.studio_vector_database_url).await?;

        let http = reqwest::Client::builder()
            .user_agent("octonotes-api/0.1")
            .timeout(Duration::from_secs(120))
            .build()?;
        if config.firebase_project_id.trim().is_empty() {
            tracing::warn!(
                "FIREBASE_PROJECT_ID empty — auth disabled, X-User-Id trusted (dev only)"
            );
        }

        let hub = match &config.redis_url {
            Some(url) => Hub::with_redis(url).await?,
            None => Hub::local(),
        };
        let storage = match &config.s3_endpoint {
            Some(endpoint) => {
                Storage::s3(storage::S3Config {
                    endpoint: endpoint.clone(),
                    bucket: config.s3_bucket.clone(),
                    access_key: config.s3_access_key.clone(),
                    secret_key: config.s3_secret_key.clone(),
                    region: config.s3_region.clone(),
                })
                .await?
            }
            None => Storage::fs(
                &config.storage_dir,
                &config.public_base_url,
                config.storage_signing_key.as_bytes().to_vec(),
            ),
        };

        let credits = octo_common::credits::Credits::new(
            octopilot.clone(),
            config.credits_ledger_type.clone(),
            config.credits_enabled,
        );
        Ok(Self {
            credits,
            rate: ai::RateLimiter::default(),
            upload_rate: ai::RateLimiter::default(),
            prices: pricing::PriceCache::default(),
            metrics: metrics::Metrics::default(),
            firebase: FirebaseAuth::new(config.firebase_project_id.clone(), http.clone()),
            http,
            config: Arc::new(config),
            notes,
            octopilot,
            studio,
            studio_vector,
            user_ids: UserIdCache::default(),
            hub,
            storage,
        })
    }
}

pub fn app(state: AppState) -> Router {
    let request_id = HeaderName::from_static("x-request-id");
    Router::new()
        .route("/health", get(system::health))
        .route("/ready", get(system::ready))
        .route("/v1/openapi.json", get(system::openapi))
        .route("/metrics", get(crate::metrics::render))
        .route("/v1/blobs/*key", get(system::blob))
        .route("/v1/me", get(system::me))
        .route("/v1/home", get(home::home))
        // Sessions, courses, devices, destinations
        .route("/v1/sessions", get(sessions::list).post(sessions::create))
        .route(
            "/v1/sessions/:id",
            get(sessions::get)
                .patch(sessions::update)
                .delete(sessions::delete),
        )
        .route("/v1/courses", get(courses::list).post(courses::create))
        .route(
            "/v1/courses/:id",
            patch(courses::update).delete(courses::delete),
        )
        .route("/v1/devices", get(devices::list).post(devices::register))
        .route("/v1/deck/destinations", get(deck::destinations))
        // Typewriter blocks
        .route("/v1/sessions/:id/blocks", get(blocks::list))
        .route("/v1/sessions/:id/blocks/ops", post(blocks::ops))
        .route("/v1/blocks/:id/history", get(blocks::history))
        .route("/v1/blocks/:id/restore", post(blocks::restore))
        // Magic Pencil
        .route(
            "/v1/sessions/:id/ink/pages",
            get(ink::list_pages).post(ink::create_page),
        )
        .route("/v1/sessions/:id/ink/strokes", get(ink::session_strokes))
        .route(
            "/v1/ink/pages/:id",
            patch(ink::update_page).delete(ink::delete_page),
        )
        .route("/v1/ink/pages/:id/strokes", get(ink::page_strokes))
        .route("/v1/ink/pages/:id/ops", post(ink::stroke_ops))
        // Recording + transcript + realtime (Phase 2)
        .route(
            "/v1/sessions/:id/recordings",
            get(recordings::list).post(recordings::start),
        )
        .route("/v1/recordings/:id", patch(recordings::update))
        .route(
            "/v1/recordings/:id/chunks/:seq",
            axum::routing::put(recordings::put_chunk),
        )
        .route("/v1/recordings/:id/manifest", get(recordings::manifest))
        .route("/v1/recordings/:id/complete", post(recordings::complete))
        .route("/v1/recordings/:id/audio", get(recordings::audio))
        .route(
            "/v1/sessions/:id/markers",
            get(recordings::list_markers).post(recordings::add_marker),
        )
        .route("/v1/sessions/:id/transcript", get(transcript::list))
        .route("/v1/sessions/:id/transcription", post(transcript::toggle))
        .route("/v1/transcript/segments/:id", patch(transcript::correct))
        .route(
            "/v1/transcript/segments/:id/restore",
            post(transcript::restore),
        )
        .route(
            "/v1/sessions/:id/blocks/from-source",
            post(transcript::from_source),
        )
        .route("/v1/sessions/:id/live", get(live::ws))
        .route("/v1/sessions/:id/devices", get(live::session_devices))
        .route("/v1/sessions/:id/devices/:device_id", patch(live::set_role))
        .route("/v1/sessions/:id/join", post(live::join))
        .route("/v1/sessions/:id/leave", post(live::leave))
        .route("/v1/sessions/:id/finish", post(live::finish))
        // AI, materials, research, organization, handwriting (Phase 3)
        .route("/v1/me/pricing", get(crate::pricing::list))
        .route("/v1/sessions/:id/ai/suggest", post(routes::ai::suggest))
        .route(
            "/v1/sessions/:id/ai/suggestions",
            get(routes::ai::pending_suggestions),
        )
        .route("/v1/ai/suggestions/:id/apply", post(routes::ai::apply))
        .route("/v1/ai/suggestions/:id/dismiss", post(routes::ai::dismiss))
        .route("/v1/sessions/:id/ai/command", post(routes::ai::command))
        .route("/v1/ai/runs/:id/insert", post(routes::ai::insert_run))
        .route("/v1/sessions/:id/ai/history", get(routes::ai::history))
        .route("/v1/sessions/:id/relevant", get(routes::ai::relevant))
        .route("/v1/sessions/:id/summarize", post(routes::ai::summarize))
        .route(
            "/v1/sessions/:id/materials",
            get(materials::list).post(materials::upload),
        )
        .route(
            "/v1/sessions/:id/materials/upload-url",
            post(materials::upload_url),
        )
        .route(
            "/v1/sessions/:id/materials/from-studio",
            post(materials::from_studio),
        )
        .route(
            "/v1/materials/:id",
            axum::routing::delete(materials::delete),
        )
        .route("/v1/materials/:id/uploaded", post(materials::uploaded))
        .route("/v1/materials/:id/pages", get(materials::pages))
        .route(
            "/v1/materials/:id/pages/:n/image",
            get(materials::page_image),
        )
        .route("/v1/materials/:id/pages/:n/link", post(materials::link))
        .route(
            "/v1/materials/:id/pages/:n/active",
            post(materials::set_active),
        )
        .route(
            "/v1/sessions/:id/research",
            get(research::list).post(research::run),
        )
        .route("/v1/research/:id/apply", post(research::apply))
        .route("/v1/research/:id/save", post(research::save))
        .route("/v1/sessions/:id/organize/preview", post(organize::preview))
        .route("/v1/organize/:id/apply", post(organize::apply))
        .route("/v1/organize/:id/undo", post(organize::undo))
        .route("/v1/organize/:id/dismiss", post(organize::dismiss))
        .route("/v1/ink/pages/:id/recognize", post(ink_ai::recognize))
        .route("/v1/ink/recognitions/:id", patch(ink_ai::review))
        // Review, finalize, Study Studio, The Deck (Phase 4)
        .route("/v1/sessions/:id/review", get(review::latest))
        .route("/v1/sessions/:id/review/prepare", post(review::prepare))
        .route("/v1/reviews/:id", get(review::get))
        .route("/v1/reviews/:id/decisions", post(review::decide))
        .route(
            "/v1/reviews/:id/draft",
            axum::routing::put(review::save_draft),
        )
        .route(
            "/v1/sessions/:id/finalize/summary",
            get(final_notes::summary),
        )
        .route("/v1/sessions/:id/finalize", post(final_notes::finalize))
        .route("/v1/final-notes", get(final_notes::list))
        .route("/v1/final-notes/:id", get(final_notes::get))
        .route("/v1/final-notes/:id/export", post(final_notes::export))
        .route("/v1/exports/:id", get(final_notes::export_status))
        .route(
            "/v1/final-notes/:id/recommendations",
            get(recommendations::get),
        )
        .route(
            "/v1/final-notes/:id/recommendations/selection",
            axum::routing::put(recommendations::select),
        )
        .route("/v1/conversions", post(conversions::create))
        .route(
            "/v1/conversions/:id",
            get(conversions::get).patch(conversions::update),
        )
        .route("/v1/conversions/:id/generate", post(conversions::generate))
        .route("/v1/conversions/:id/progress", get(conversions::progress))
        .route("/v1/links", get(conversions::links))
        .route("/v1/deck/search", post(deck::search))
        // PHASE-ROUTES
        .layer(axum::middleware::from_fn_with_state(
            state.clone(),
            crate::metrics::track,
        ))
        .layer(DefaultBodyLimit::max(52 * 1024 * 1024))
        .layer(cors(&state.config))
        .layer(PropagateRequestIdLayer::new(request_id.clone()))
        .layer(
            TraceLayer::new_for_http().make_span_with(|req: &Request<_>| {
                let header = |name: &str| {
                    req.headers()
                        .get(name)
                        .and_then(|v| v.to_str().ok())
                        .unwrap_or("")
                        .to_string()
                };
                tracing::info_span!(
                    "request",
                    method = %req.method(),
                    path = %req.uri().path(),
                    request_id = %header("x-request-id"),
                    client_version = %header("x-client-version"),
                    user_id = tracing::field::Empty,
                )
            }),
        )
        .layer(SetRequestIdLayer::new(request_id, MakeRequestUuid))
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
        .allow_methods([
            Method::GET,
            Method::POST,
            Method::PUT,
            Method::PATCH,
            Method::DELETE,
        ])
        .allow_headers([
            header::AUTHORIZATION,
            header::CONTENT_TYPE,
            header::RANGE,
            HeaderName::from_static("x-user-id"),
            HeaderName::from_static("x-client-version"),
            HeaderName::from_static("idempotency-key"),
        ])
        .expose_headers([HeaderName::from_static("x-request-id")])
}

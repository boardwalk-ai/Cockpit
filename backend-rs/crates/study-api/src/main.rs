//! Study Studio API (Rust). See `lib.rs` for what is served so far.

use study_api::{app, config::Config, AppState};
use tokio::net::TcpListener;

#[tokio::main]
async fn main() {
    let config = Config::from_env();
    let filter = tracing_subscriber::EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| "study_api=info,octo_common=info,tower_http=info".into());
    if config.log_format == "json" {
        tracing_subscriber::fmt().json().with_env_filter(filter).init();
    } else {
        tracing_subscriber::fmt().with_env_filter(filter).init();
    }
    let (bind, port) = (config.bind.clone(), config.port);
    let state = AppState::connect(config).await.expect("connect databases");
    if state.config.migrate || state.config.ingest_worker {
        study_api::ingest::ensure_schema(&state).await.expect("chunks schema");
        study_api::llm::ensure_schema(&state.cockpit).await.expect("llm_usage schema");
    }
    if state.config.ingest_worker {
        study_api::ingest::spawn(&state);
        tracing::info!("ingest workers: {}", state.config.ingest_workers);
    }
    let listener = TcpListener::bind((bind.as_str(), port)).await.expect("bind");
    tracing::info!("study-api listening on http://{bind}:{port}");
    axum::serve(listener, app(state))
        .with_graceful_shutdown(async {
            let _ = tokio::signal::ctrl_c().await;
        })
        .await
        .expect("serve");
}

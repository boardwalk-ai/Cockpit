//! GhostWriter backend.
//!
//! Owns the `ghostwriter` database (sqlx migrations run at startup) and reads
//! the shared octopilot DB for identity, the central OctoCredits balance, keys
//! and models.

use ghostwriter_api::{app, config::Config, AppState};
use tokio::net::TcpListener;

#[tokio::main]
async fn main() {
    let config = Config::from_env();
    let filter = tracing_subscriber::EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| "ghostwriter_api=info,octo_common=info,tower_http=info".into());
    if config.log_format == "json" {
        tracing_subscriber::fmt()
            .json()
            .with_current_span(true)
            .with_env_filter(filter)
            .init();
    } else {
        tracing_subscriber::fmt().with_env_filter(filter).init();
    }

    let port = config.port;
    let bind = config.bind.clone();
    let state = AppState::connect(config)
        .await
        .expect("start ghostwriter-api");

    // Drives queued runs, and picks up the ones a restart cut off.
    let _worker = ghostwriter_api::runs::worker::start(state.clone());

    let listener = TcpListener::bind((bind.as_str(), port))
        .await
        .expect("bind");
    tracing::info!("ghostwriter-api listening on http://{bind}:{port}");
    axum::serve(listener, app(state))
        .with_graceful_shutdown(shutdown())
        .await
        .expect("serve");
}

/// Ctrl-C or SIGTERM (systemd stop): stop accepting, finish in-flight requests.
async fn shutdown() {
    let ctrl_c = async {
        let _ = tokio::signal::ctrl_c().await;
    };
    #[cfg(unix)]
    let term = async {
        if let Ok(mut s) = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
        {
            s.recv().await;
        }
    };
    #[cfg(not(unix))]
    let term = std::future::pending::<()>();
    tokio::select! { _ = ctrl_c => {}, _ = term => {} }
    tracing::info!("shutting down");
}

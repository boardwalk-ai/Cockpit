//! OctoNotes backend.
//!
//! Owns `notes_db` (sqlx migrations run at startup) and reads the shared
//! databases: the octopilot DB (identity, the central OctoCredits balance,
//! keys and models) and the Study Studio DBs. `ROLE=api|worker|all` picks which
//! loops this process runs, so workers can be split out later.

use octonotes_api::{app, config::Config, jobs, AppState};
use tokio::net::TcpListener;

#[tokio::main]
async fn main() {
    let config = Config::from_env();
    let filter = tracing_subscriber::EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| "octonotes_api=info,octo_common=info,tower_http=info".into());
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
    let (runs_api, runs_worker, workers) =
        (config.runs_api(), config.runs_worker(), config.workers);
    let state = AppState::connect(config)
        .await
        .expect("start octonotes-api");

    if runs_worker {
        jobs::spawn(state.clone(), workers);
        tracing::info!("started {workers} job workers");
    }
    if runs_api {
        let listener = TcpListener::bind(("0.0.0.0", port)).await.expect("bind");
        tracing::info!("octonotes-api listening on http://0.0.0.0:{port}");
        axum::serve(
            listener,
            app(state).into_make_service_with_connect_info::<std::net::SocketAddr>(),
        )
        .with_graceful_shutdown(shutdown())
        .await
        .expect("serve");
    } else {
        shutdown().await;
    }
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

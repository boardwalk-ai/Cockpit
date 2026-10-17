//! Admin API for the test environment. See `lib.rs`.

use admin_api::{app, AppState, Config};
use tokio::net::TcpListener;

#[tokio::main]
async fn main() {
    let config = Config::from_env();
    let filter = tracing_subscriber::EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| "admin_api=info,octo_common=info,tower_http=info".into());
    if config.log_format == "json" {
        tracing_subscriber::fmt().json().with_env_filter(filter).init();
    } else {
        tracing_subscriber::fmt().with_env_filter(filter).init();
    }
    if config.admin_emails.is_empty() {
        tracing::warn!("ADMIN_EMAILS empty — nobody can use the admin endpoints");
    }
    let state = AppState::connect(&config).await.expect("connect database");
    let listener = TcpListener::bind((config.bind.as_str(), config.port)).await.expect("bind");
    tracing::info!("admin-api listening on http://{}:{}", config.bind, config.port);
    axum::serve(listener, app(state))
        .with_graceful_shutdown(async {
            let _ = tokio::signal::ctrl_c().await;
        })
        .await
        .expect("serve");
}

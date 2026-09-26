//! OctoNotes backend.
//!
//! Owns `notes_db` (sqlx migrations run at startup) and reads the two shared
//! databases: the octopilot DB (identity + the central OctoCredits balance) and,
//! from Phase 1, the Study Studio DB. Firebase ID tokens are verified with the
//! shared `octo-common` auth, the same way octopilot-rs and the FastAPI do.

use octonotes_api::{app, config::Config, AppState};
use tokio::net::TcpListener;

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "octonotes_api=info,octo_common=info,tower_http=info".into()),
        )
        .init();

    let config = Config::from_env();
    let port = config.port;
    let state = AppState::connect(config).await.expect("start octonotes-api");

    let listener = TcpListener::bind(("0.0.0.0", port)).await.expect("bind");
    tracing::info!("octonotes-api listening on http://0.0.0.0:{port}");
    axum::serve(listener, app(state)).await.expect("serve");
}

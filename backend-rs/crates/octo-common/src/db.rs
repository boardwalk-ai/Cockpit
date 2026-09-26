//! Postgres pool helpers.

use std::time::Duration;

use sqlx::postgres::PgPoolOptions;
use sqlx::PgPool;

/// Opens a pool of at most `max` connections.
pub async fn connect(url: &str, max: u32) -> Result<PgPool, sqlx::Error> {
    PgPoolOptions::new()
        .max_connections(max)
        .acquire_timeout(Duration::from_secs(10))
        .connect(url)
        .await
}

/// A cheap round-trip used by readiness checks.
pub async fn ping(pool: &PgPool) -> bool {
    sqlx::query("SELECT 1").execute(pool).await.is_ok()
}

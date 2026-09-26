//! Per-session, per-layer monotonic revisions (`session_layer_revs`).
//!
//! Writers take the layer row lock first, so changes to one layer of one
//! session are serialized and `layer_rev` never goes backwards.

use sqlx::PgConnection;
use uuid::Uuid;

pub const BLOCKS: &str = "blocks";
pub const INK: &str = "ink";
pub const TRANSCRIPT: &str = "transcript";

/// Locks the layer row (creating it at 0) and returns the current rev.
pub async fn lock(
    conn: &mut PgConnection,
    session_id: Uuid,
    layer: &str,
) -> Result<i64, sqlx::Error> {
    sqlx::query("INSERT INTO session_layer_revs (session_id, layer, rev) VALUES ($1, $2, 0) ON CONFLICT DO NOTHING")
        .bind(session_id)
        .bind(layer)
        .execute(&mut *conn)
        .await?;
    sqlx::query_scalar(
        "SELECT rev FROM session_layer_revs WHERE session_id = $1 AND layer = $2 FOR UPDATE",
    )
    .bind(session_id)
    .bind(layer)
    .fetch_one(conn)
    .await
}

/// Advances the (already locked) layer and returns the new rev.
pub async fn bump(
    conn: &mut PgConnection,
    session_id: Uuid,
    layer: &str,
) -> Result<i64, sqlx::Error> {
    sqlx::query_scalar(
        "INSERT INTO session_layer_revs (session_id, layer, rev) VALUES ($1, $2, 1) \
         ON CONFLICT (session_id, layer) DO UPDATE SET rev = session_layer_revs.rev + 1 RETURNING rev",
    )
    .bind(session_id)
    .bind(layer)
    .fetch_one(conn)
    .await
}

pub async fn current(
    conn: &mut PgConnection,
    session_id: Uuid,
    layer: &str,
) -> Result<i64, sqlx::Error> {
    Ok(sqlx::query_scalar::<_, i64>(
        "SELECT rev FROM session_layer_revs WHERE session_id = $1 AND layer = $2",
    )
    .bind(session_id)
    .bind(layer)
    .fetch_optional(conn)
    .await?
    .unwrap_or(0))
}

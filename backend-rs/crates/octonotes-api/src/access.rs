//! Ownership checks. Another user's row answers 404, never 403, so ids can't
//! be probed.

use octo_common::ApiError;
use sqlx::PgConnection;
use uuid::Uuid;

use crate::ctx::Caller;

/// The caller's live (not deleted) session, or 404.
pub async fn session(conn: &mut PgConnection, caller: &Caller, session_id: Uuid) -> Result<SessionAccess, ApiError> {
    sqlx::query_as::<_, SessionAccess>(
        "SELECT id, status FROM sessions WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL",
    )
    .bind(session_id)
    .bind(caller.user_id)
    .fetch_optional(conn)
    .await?
    .ok_or_else(|| ApiError::not_found("session not found"))
}

/// Same, but refuses writes to archived sessions.
pub async fn writable_session(
    conn: &mut PgConnection,
    caller: &Caller,
    session_id: Uuid,
) -> Result<SessionAccess, ApiError> {
    let s = session(conn, caller, session_id).await?;
    if s.status == "archived" {
        return Err(ApiError::new(axum::http::StatusCode::CONFLICT, "session is archived").with_code("session_archived"));
    }
    Ok(s)
}

#[derive(sqlx::FromRow)]
pub struct SessionAccess {
    pub id: Uuid,
    pub status: String,
}

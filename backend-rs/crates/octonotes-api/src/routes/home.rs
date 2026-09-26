//! `GET /v1/home` — a thin, disposable aggregate for Panel 1. It only reads
//! what the resource endpoints already expose; no business logic lives here,
//! so the Home screen can change freely.

use axum::extract::State;
use axum::Json;
use octo_common::ApiError;
use serde::Serialize;
use serde_json::Value;
use utoipa::ToSchema;

use crate::ctx::Caller;
use crate::routes::sessions::{Session, SESSION_COLUMNS};
use crate::AppState;

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct Home {
    /// Sessions recording or paused right now (possibly on another device).
    pub live: Vec<Session>,
    /// Unfinished sessions, most recent first.
    #[serde(rename = "continue")]
    pub continue_: Vec<Session>,
    /// Finalized notes, most recent first.
    pub recent: Vec<Session>,
    /// Background work in progress (transcription, processing, builds).
    #[schema(value_type = Vec<Object>)]
    pub processing: Value,
    /// Final notes with Study Studio recommendations not yet converted.
    #[schema(value_type = Vec<Object>)]
    pub recommended: Value,
}

#[utoipa::path(get, path = "/v1/home", tag = "home", responses((status = 200, body = Home)))]
pub async fn home(State(st): State<AppState>, caller: Caller) -> Result<Json<Home>, ApiError> {
    let by_status = |statuses: &'static [&'static str], limit: i64| {
        let pool = st.notes.clone();
        let user = caller.user_id;
        async move {
            sqlx::query_as::<_, Session>(&format!(
                "SELECT {SESSION_COLUMNS} FROM sessions WHERE user_id = $1 AND deleted_at IS NULL AND status = ANY($2) \
                 ORDER BY updated_at DESC LIMIT $3"
            ))
            .bind(user)
            .bind(statuses.iter().map(|s| s.to_string()).collect::<Vec<_>>())
            .bind(limit)
            .fetch_all(&pool)
            .await
        }
    };
    let (live, continue_, recent) = tokio::try_join!(
        by_status(&["live", "paused"], 5),
        by_status(&["draft", "ended", "reviewing"], 5),
        by_status(&["finalized"], 10),
    )?;
    let processing: Value = sqlx::query_scalar(
        "SELECT COALESCE(json_agg(json_build_object('jobId', id, 'kind', kind, 'status', status, \
             'sessionId', payload->>'sessionId', 'updatedAt', updated_at) ORDER BY updated_at DESC), '[]') \
         FROM (SELECT * FROM jobs WHERE user_id = $1 AND status IN ('queued', 'running') \
               AND kind NOT LIKE 'system.%' ORDER BY updated_at DESC LIMIT 10) j",
    )
    .bind(caller.user_id)
    .fetch_one(&st.notes)
    .await?;
    let recommended = crate::routes::recommendations::home_items(&st, &caller).await?;
    Ok(Json(Home { live, continue_, recent, processing, recommended }))
}

//! Save destinations ("Save in The Deck"). The Deck isn't built yet, so the
//! destinations are the user's Study Studio studios (`studio:<uuid>`); when the
//! Deck exists this returns its folders (`deck:<uuid>`) — same shape.

use axum::extract::State;
use axum::Json;
use chrono::{DateTime, Utc};
use octo_common::ApiError;
use serde::Serialize;
use sqlx::Row;
use utoipa::ToSchema;

use crate::ctx::Caller;
use crate::AppState;

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct Destination {
    /// Stored on the session as `deckRef`.
    #[serde(rename = "ref")]
    pub reference: String,
    /// `studyStudio` today, `deckFolder` later.
    pub kind: String,
    pub title: String,
    pub subtitle: Option<String>,
    pub updated_at: Option<DateTime<Utc>>,
}

#[utoipa::path(get, path = "/v1/deck/destinations", tag = "deck", responses((status = 200, body = Vec<Destination>)))]
pub async fn destinations(State(st): State<AppState>, caller: Caller) -> Result<Json<Vec<Destination>>, ApiError> {
    let Some(studio) = &st.studio else { return Ok(Json(Vec::new())) };
    let rows = sqlx::query(
        "SELECT id::text AS id, title, subject, updated_at FROM studios WHERE user_id = $1 ORDER BY updated_at DESC LIMIT 200",
    )
    .bind(caller.user_id)
    .fetch_all(studio)
    .await?;
    Ok(Json(
        rows.into_iter()
            .map(|r| Destination {
                reference: format!("studio:{}", r.get::<String, _>("id")),
                kind: "studyStudio".into(),
                title: r.get("title"),
                subtitle: r.get("subject"),
                updated_at: r.get("updated_at"),
            })
            .collect(),
    ))
}

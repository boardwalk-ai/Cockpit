use axum::extract::State;
use axum::http::StatusCode;
use axum::Json;
use octo_common::identity::user_by_firebase_uid;
use octo_common::{ApiError, AuthedUser};
use serde::Serialize;
use serde_json::{json, Value};

use crate::AppState;

/// Liveness — the process is up.
pub async fn health() -> Json<Value> {
    Json(json!({ "status": "ok" }))
}

/// Readiness — every configured database answers. 503 if any is down.
pub async fn ready(State(st): State<AppState>) -> (StatusCode, Json<Value>) {
    let notes = octo_common::db::ping(&st.notes).await;
    let octopilot = match &st.octopilot {
        Some(p) => Some(octo_common::db::ping(p).await),
        None => None,
    };
    let studio = match &st.studio {
        Some(p) => Some(octo_common::db::ping(p).await),
        None => None,
    };
    let ok = notes && octopilot.unwrap_or(true) && studio.unwrap_or(true);
    let status = if ok { StatusCode::OK } else { StatusCode::SERVICE_UNAVAILABLE };
    (
        status,
        Json(json!({
            "status": if ok { "ready" } else { "degraded" },
            "notesDb": notes,
            "octopilotDb": octopilot,
            "studioDb": studio,
        })),
    )
}

/// `GET /v1/me` — the account behind the token and its central OctoCredits
/// balance (the pill). `registered: false` when the Firebase account has no
/// octopilot `users` row yet, or the shared DB isn't configured (dev).
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Me {
    pub uid: String,
    pub email: Option<String>,
    pub registered: bool,
    pub user_id: Option<String>,
    pub name: Option<String>,
    pub photo_url: Option<String>,
    pub plan: Option<String>,
    pub octo_credits: Option<i32>,
    pub is_admin: bool,
}

pub async fn me(State(st): State<AppState>, user: AuthedUser) -> Result<Json<Me>, ApiError> {
    let row = match &st.octopilot {
        Some(pool) => user_by_firebase_uid(pool, &user.uid).await?,
        None => None,
    };
    Ok(Json(match row {
        Some(u) => Me {
            uid: user.uid,
            email: u.email.or(user.email),
            registered: true,
            user_id: Some(u.id),
            name: u.name,
            photo_url: u.photo_url,
            plan: u.plan,
            octo_credits: Some(u.octo_credits),
            is_admin: u.is_admin,
        },
        None => Me {
            uid: user.uid,
            email: user.email,
            registered: false,
            user_id: None,
            name: None,
            photo_url: None,
            plan: None,
            octo_credits: None,
            is_admin: false,
        },
    }))
}

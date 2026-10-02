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
    let ghostwriter = octo_common::db::ping(&st.db).await;
    let octopilot = match &st.octopilot {
        Some(p) => Some(octo_common::db::ping(p).await),
        None => None,
    };
    let ok = ghostwriter && octopilot.unwrap_or(true);
    let status = if ok {
        StatusCode::OK
    } else {
        StatusCode::SERVICE_UNAVAILABLE
    };
    (
        status,
        Json(json!({
            "status": if ok { "ready" } else { "degraded" },
            "ghostwriterDb": ghostwriter,
            "octopilotDb": octopilot,
        })),
    )
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Me {
    pub id: Option<String>,
    pub name: Option<String>,
    pub email: Option<String>,
    pub photo_url: Option<String>,
    pub plan: Option<String>,
    /// The central OctoCredits balance, always read fresh.
    pub octo_credits: i32,
}

/// `GET /v1/me` — the account behind the token and its OctoCredits balance
/// (the pill). 403 `account_required` when the sign-in has no octopilot
/// `users` row yet.
pub async fn me(State(st): State<AppState>, user: AuthedUser) -> Result<Json<Me>, ApiError> {
    let Some(pool) = &st.octopilot else {
        // Dev without the shared DB: an identity with no balance.
        return Ok(Json(Me {
            id: None,
            name: None,
            email: user.email,
            photo_url: None,
            plan: None,
            octo_credits: 0,
        }));
    };
    let row = user_by_firebase_uid(pool, &user.uid)
        .await?
        .ok_or_else(|| {
            ApiError::new(
                StatusCode::FORBIDDEN,
                "no Octopilot account for this sign-in",
            )
            .with_code("account_required")
        })?;
    Ok(Json(Me {
        id: Some(row.id),
        name: row.name,
        email: row.email,
        photo_url: row.photo_url,
        plan: row.plan,
        octo_credits: row.octo_credits,
    }))
}

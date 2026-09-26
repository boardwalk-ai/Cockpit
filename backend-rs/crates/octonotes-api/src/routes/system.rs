use axum::body::Body;
use axum::extract::{Path, Query, State};
use axum::http::{Request, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::Json;
use octo_common::identity::user_by_firebase_uid;
use octo_common::{ApiError, AuthedUser};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tower::ServiceExt;
use tower_http::services::ServeFile;
use utoipa::ToSchema;

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
    let status = if ok {
        StatusCode::OK
    } else {
        StatusCode::SERVICE_UNAVAILABLE
    };
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
#[derive(Serialize, ToSchema)]
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

#[utoipa::path(get, path = "/v1/me", tag = "account", responses((status = 200, body = Me)))]
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

#[derive(Deserialize)]
pub struct BlobQuery {
    exp: u64,
    sig: String,
}

/// Serves a local-store file behind an expiring signed link (dev storage; in
/// production clients get MinIO presigned URLs instead). Supports Range.
pub async fn blob(
    State(st): State<AppState>,
    Path(key): Path<String>,
    Query(q): Query<BlobQuery>,
    req: Request<Body>,
) -> Response {
    match st.storage.verify_local(&key, q.exp, &q.sig) {
        Some(path) => match ServeFile::new(path).oneshot(req).await {
            Ok(res) => res.into_response(),
            Err(_) => StatusCode::INTERNAL_SERVER_ERROR.into_response(),
        },
        None => ApiError::new(StatusCode::FORBIDDEN, "link expired or invalid").into_response(),
    }
}

/// The API contract (OpenAPI 3.1), generated from the Rust types.
pub async fn openapi() -> Json<utoipa::openapi::OpenApi> {
    Json(crate::openapi::spec())
}

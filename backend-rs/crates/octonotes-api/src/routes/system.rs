use axum::body::Body;
use axum::extract::{Path, Query, State};
use axum::http::{header, Request, StatusCode};
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

/// Serves a stored file behind an expiring signed link: from the local
/// folder (dev) or from MinIO (production, which is loopback only). Supports
/// a single byte range, so players can seek.
pub async fn blob(
    State(st): State<AppState>,
    Path(key): Path<String>,
    Query(q): Query<BlobQuery>,
    req: Request<Body>,
) -> Response {
    if !st.storage.verify(&key, q.exp, &q.sig) {
        return ApiError::new(StatusCode::FORBIDDEN, "link expired or invalid").into_response();
    }
    if let Some(path) = st.storage.local_path(&key) {
        return match ServeFile::new(path).oneshot(req).await {
            Ok(res) => res.into_response(),
            Err(_) => StatusCode::INTERNAL_SERVER_ERROR.into_response(),
        };
    }
    let bytes = match st.storage.get(&key).await {
        Ok(b) => b,
        Err(e) => {
            tracing::warn!(error = %e, "blob not readable");
            return ApiError::not_found("file not found").into_response();
        }
    };
    let range = req
        .headers()
        .get(header::RANGE)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| byte_range(v, bytes.len()));
    let base = Response::builder()
        .header(header::CONTENT_TYPE, content_type(&key))
        .header(header::ACCEPT_RANGES, "bytes")
        .header(header::CACHE_CONTROL, "private, max-age=600");
    let res = match range {
        Some((a, b)) => base
            .status(StatusCode::PARTIAL_CONTENT)
            .header(header::CONTENT_RANGE, format!("bytes {a}-{b}/{}", bytes.len()))
            .body(Body::from(bytes[a..=b].to_vec())),
        None => base.body(Body::from(bytes)),
    };
    res.unwrap_or_else(|_| StatusCode::INTERNAL_SERVER_ERROR.into_response())
}

/// `bytes=a-b`, `bytes=a-` or `bytes=-n` within `len`; one range only.
fn byte_range(v: &str, len: usize) -> Option<(usize, usize)> {
    let r = v.strip_prefix("bytes=")?;
    if len == 0 || r.contains(',') {
        return None;
    }
    let (a, b) = r.split_once('-')?;
    let (a, b) = match (a.trim(), b.trim()) {
        ("", n) => {
            let n: usize = n.parse().ok()?;
            (len.saturating_sub(n), len - 1)
        }
        (a, "") => (a.parse().ok()?, len - 1),
        (a, b) => (a.parse().ok()?, b.parse::<usize>().ok()?.min(len - 1)),
    };
    (a <= b && a < len).then_some((a, b))
}

fn content_type(key: &str) -> &'static str {
    match key.rsplit('.').next().unwrap_or("") {
        "opus" | "ogg" => "audio/ogg",
        "wav" => "audio/wav",
        "m4a" => "audio/mp4",
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "webp" => "image/webp",
        "pdf" => "application/pdf",
        "json" => "application/json",
        _ => "application/octet-stream",
    }
}

#[cfg(test)]
mod blob_tests {
    use super::byte_range;

    #[test]
    fn ranges() {
        assert_eq!(byte_range("bytes=0-99", 1000), Some((0, 99)));
        assert_eq!(byte_range("bytes=900-", 1000), Some((900, 999)));
        assert_eq!(byte_range("bytes=-100", 1000), Some((900, 999)));
        assert_eq!(byte_range("bytes=500-5000", 1000), Some((500, 999)));
        assert_eq!(byte_range("bytes=2000-", 1000), None);
        assert_eq!(byte_range("bytes=0-1,5-9", 1000), None);
    }
}

/// The API contract (OpenAPI 3.1), generated from the Rust types.
pub async fn openapi() -> Json<utoipa::openapi::OpenApi> {
    Json(crate::openapi::spec())
}

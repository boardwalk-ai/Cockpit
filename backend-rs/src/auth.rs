//! Firebase ID-token verification — a direct port of the FastAPI `auth.py`.
//!
//! The Flutter client signs in with Firebase (project `octopilot-ai-7b29e`) and
//! sends the ID token as `Authorization: Bearer <token>`. We verify it against
//! Google's public signing keys (RS256), checking `aud` (= project id) and
//! `iss` — no service-account JSON required. When no project is configured
//! (local dev) we trust the `X-User-Id` header instead so the stack runs
//! offline.

use std::sync::Arc;
use std::time::{Duration, Instant};

use axum::async_trait;
use axum::extract::FromRequestParts;
use axum::http::request::Parts;
use jsonwebtoken::{decode, decode_header, Algorithm, DecodingKey, Validation};
use serde::Deserialize;
use tokio::sync::RwLock;

use crate::error::ApiError;
use crate::AppState;

const JWKS_URL: &str = "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com";

#[derive(Debug, Clone)]
pub struct AuthedUser {
    pub uid: String,
    pub email: Option<String>,
}

#[derive(Deserialize)]
struct Claims {
    sub: String,
    #[serde(default)]
    email: Option<String>,
    #[serde(default)]
    user_id: Option<String>,
}

#[derive(Deserialize, Clone)]
struct Jwk {
    kid: String,
    n: String,
    e: String,
}

#[derive(Deserialize)]
struct Jwks {
    keys: Vec<Jwk>,
}

/// Cached JWKS set, refreshed hourly or on an unknown `kid`.
#[derive(Default)]
pub struct JwksCache {
    keys: Vec<Jwk>,
    fetched: Option<Instant>,
}

pub type SharedJwks = Arc<RwLock<JwksCache>>;

async fn key_for(state: &AppState, kid: &str) -> Option<Jwk> {
    {
        let cache = state.jwks.read().await;
        let fresh = cache
            .fetched
            .map(|t| t.elapsed() < Duration::from_secs(3600))
            .unwrap_or(false);
        if fresh {
            if let Some(k) = cache.keys.iter().find(|k| k.kid == kid) {
                return Some(k.clone());
            }
        }
    }
    // Miss or stale → refetch.
    let jwks: Jwks = state.http.get(JWKS_URL).send().await.ok()?.json().await.ok()?;
    let mut cache = state.jwks.write().await;
    cache.keys = jwks.keys;
    cache.fetched = Some(Instant::now());
    cache.keys.iter().find(|k| k.kid == kid).cloned()
}

/// Verify a bearer token → the authenticated user (or an error).
pub async fn verify_bearer(state: &AppState, token: &str) -> Result<AuthedUser, ApiError> {
    let project = state.config.firebase_project_id.trim().to_string();
    if project.is_empty() {
        return Err(ApiError::unauthorized("auth disabled"));
    }
    let header = decode_header(token)
        .map_err(|_| ApiError::unauthorized("malformed token"))?;
    let kid = header.kid.ok_or_else(|| ApiError::unauthorized("token has no kid"))?;
    let jwk = key_for(state, &kid)
        .await
        .ok_or_else(|| ApiError::unauthorized("unknown signing key"))?;

    let key = DecodingKey::from_rsa_components(&jwk.n, &jwk.e)
        .map_err(|_| ApiError::unauthorized("bad signing key"))?;
    let mut validation = Validation::new(Algorithm::RS256);
    validation.set_audience(&[project.clone()]);
    validation.set_issuer(&[format!("https://securetoken.google.com/{project}")]);

    let data = decode::<Claims>(token, &key, &validation)
        .map_err(|_| ApiError::unauthorized("invalid or expired token"))?;
    let c = data.claims;
    Ok(AuthedUser {
        uid: c.user_id.unwrap_or(c.sub),
        email: c.email,
    })
}

/// Axum extractor: requires a valid Firebase token (or, in dev with auth
/// disabled, an `X-User-Id` header).
#[async_trait]
impl FromRequestParts<AppState> for AuthedUser {
    type Rejection = ApiError;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        if state.config.firebase_project_id.trim().is_empty() {
            let uid = parts
                .headers
                .get("x-user-id")
                .and_then(|v| v.to_str().ok())
                .unwrap_or("dev-user")
                .to_string();
            return Ok(AuthedUser { uid, email: None });
        }
        let token = parts
            .headers
            .get("authorization")
            .and_then(|v| v.to_str().ok())
            .and_then(|s| s.strip_prefix("Bearer "))
            .ok_or_else(|| ApiError::unauthorized("missing bearer token"))?;
        verify_bearer(state, token).await
    }
}

//! Firebase ID-token verification — a direct port of the FastAPI `auth.py`,
//! shared by every Rust service.
//!
//! Flutter clients sign in with Firebase (project `octopilot-ai-7b29e`) and send
//! the ID token as `Authorization: Bearer <token>`. We verify it against
//! Google's public signing keys (RS256), checking `aud` (= project id) and
//! `iss` — no service-account JSON required. When no project is configured
//! (local dev) the `X-User-Id` header is trusted instead so the stack runs
//! offline.
//!
//! A service opts in by holding a [`FirebaseAuth`] in its state and
//! implementing [`HasFirebase`]; [`AuthedUser`] then works as an extractor.

use std::sync::Arc;
use std::time::{Duration, Instant};

use axum::async_trait;
use axum::extract::FromRequestParts;
use axum::http::request::Parts;
use jsonwebtoken::{decode, decode_header, Algorithm, DecodingKey, Validation};
use serde::Deserialize;
use tokio::sync::RwLock;

use crate::error::ApiError;

const JWKS_URL: &str =
    "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com";

#[derive(Debug, Clone)]
pub struct AuthedUser {
    /// Firebase UID (maps to `users.firebase_uid` in the shared octopilot DB).
    pub uid: String,
    pub email: Option<String>,
    /// Firebase has confirmed the user owns [email] (true for Google sign-in).
    pub email_verified: bool,
    pub name: Option<String>,
}

#[derive(Deserialize)]
struct Claims {
    sub: String,
    #[serde(default)]
    email: Option<String>,
    #[serde(default)]
    email_verified: Option<bool>,
    #[serde(default)]
    name: Option<String>,
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
struct JwksCache {
    keys: Vec<Jwk>,
    fetched: Option<Instant>,
}

/// Verifier for one Firebase project. Cheap to clone (shared cache).
#[derive(Clone)]
pub struct FirebaseAuth {
    project_id: String,
    http: reqwest::Client,
    jwks: Arc<RwLock<JwksCache>>,
}

impl FirebaseAuth {
    /// `project_id` empty ⇒ auth disabled (dev): `X-User-Id` is trusted.
    pub fn new(project_id: impl Into<String>, http: reqwest::Client) -> Self {
        Self {
            project_id: project_id.into().trim().to_string(),
            http,
            jwks: Arc::new(RwLock::new(JwksCache::default())),
        }
    }

    pub fn enabled(&self) -> bool {
        !self.project_id.is_empty()
    }

    async fn key_for(&self, kid: &str) -> Option<Jwk> {
        {
            let cache = self.jwks.read().await;
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
        let jwks: Jwks = self
            .http
            .get(JWKS_URL)
            .send()
            .await
            .ok()?
            .json()
            .await
            .ok()?;
        let mut cache = self.jwks.write().await;
        cache.keys = jwks.keys;
        cache.fetched = Some(Instant::now());
        cache.keys.iter().find(|k| k.kid == kid).cloned()
    }

    /// Verify a bearer token → the authenticated user (or an error).
    pub async fn verify_bearer(&self, token: &str) -> Result<AuthedUser, ApiError> {
        if !self.enabled() {
            return Err(ApiError::unauthorized("auth disabled"));
        }
        let header = decode_header(token).map_err(|_| ApiError::unauthorized("malformed token"))?;
        let kid = header
            .kid
            .ok_or_else(|| ApiError::unauthorized("token has no kid"))?;
        let jwk = self
            .key_for(&kid)
            .await
            .ok_or_else(|| ApiError::unauthorized("unknown signing key"))?;

        let key = DecodingKey::from_rsa_components(&jwk.n, &jwk.e)
            .map_err(|_| ApiError::unauthorized("bad signing key"))?;
        let mut validation = Validation::new(Algorithm::RS256);
        validation.set_audience(std::slice::from_ref(&self.project_id));
        validation.set_issuer(&[format!(
            "https://securetoken.google.com/{}",
            self.project_id
        )]);

        let data = decode::<Claims>(token, &key, &validation)
            .map_err(|_| ApiError::unauthorized("invalid or expired token"))?;
        let c = data.claims;
        Ok(AuthedUser {
            uid: c.user_id.unwrap_or(c.sub),
            email: c.email,
            email_verified: c.email_verified.unwrap_or(false),
            name: c.name,
        })
    }

    /// Resolve the caller from request headers (Bearer token, or `X-User-Id`
    /// when auth is disabled).
    pub async fn authenticate(
        &self,
        headers: &axum::http::HeaderMap,
    ) -> Result<AuthedUser, ApiError> {
        if !self.enabled() {
            let uid = headers
                .get("x-user-id")
                .and_then(|v| v.to_str().ok())
                .unwrap_or("dev-user")
                .to_string();
            return Ok(AuthedUser {
                uid,
                email: None,
                email_verified: false,
                name: None,
            });
        }
        let token = headers
            .get("authorization")
            .and_then(|v| v.to_str().ok())
            .and_then(|s| s.strip_prefix("Bearer "))
            .ok_or_else(|| ApiError::unauthorized("missing bearer token"))?;
        self.verify_bearer(token).await
    }
}

/// Implemented by a service's state so [`AuthedUser`] can be extracted.
pub trait HasFirebase {
    fn firebase(&self) -> &FirebaseAuth;
}

/// Axum extractor: requires a valid Firebase token (or, in dev with auth
/// disabled, an `X-User-Id` header).
#[async_trait]
impl<S> FromRequestParts<S> for AuthedUser
where
    S: HasFirebase + Send + Sync,
{
    type Rejection = ApiError;

    async fn from_request_parts(parts: &mut Parts, state: &S) -> Result<Self, Self::Rejection> {
        state.firebase().authenticate(&parts.headers).await
    }
}

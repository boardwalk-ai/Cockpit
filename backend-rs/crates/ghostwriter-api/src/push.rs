//! Push notifications: a run tells the user's phones when it needs them and
//! nobody is watching it.
//!
//! Sent through Firebase Cloud Messaging (HTTP v1), which reaches Android and
//! iOS alike. Behind a trait so tests need no network.

use std::collections::BTreeMap;
use std::time::{Duration, Instant};

use axum::async_trait;
use jsonwebtoken::{Algorithm, EncodingKey, Header};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use uuid::Uuid;

use crate::AppState;

const SCOPE: &str = "https://www.googleapis.com/auth/firebase.messaging";
const DEFAULT_TOKEN_URI: &str = "https://oauth2.googleapis.com/token";
/// The Android notification channel the app creates.
const ANDROID_CHANNEL: &str = "ghostwriter";
/// Notification text is cut to this many characters.
const BODY_LIMIT: usize = 180;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Notice {
    pub title: String,
    pub body: String,
    /// What the app needs to open the right screen. FCM data is all strings.
    pub data: BTreeMap<String, String>,
}

#[derive(Debug)]
pub enum PushError {
    /// The token is dead (app removed, token rotated): forget the device.
    Unregistered,
    Other(String),
}

#[async_trait]
pub trait Pusher: Send + Sync {
    /// False when nothing can be sent, so callers skip the work.
    fn enabled(&self) -> bool {
        true
    }
    async fn send(&self, token: &str, notice: &Notice) -> Result<(), PushError>;
}

/// Used when no Firebase service account is configured.
pub struct NoPusher;

#[async_trait]
impl Pusher for NoPusher {
    fn enabled(&self) -> bool {
        false
    }
    async fn send(&self, _token: &str, _notice: &Notice) -> Result<(), PushError> {
        Ok(())
    }
}

/// The parts of a Google service-account key file that are used.
#[derive(Deserialize)]
struct ServiceAccount {
    project_id: String,
    client_email: String,
    private_key: String,
    token_uri: Option<String>,
}

#[derive(Serialize)]
struct Claims<'a> {
    iss: &'a str,
    scope: &'a str,
    aud: &'a str,
    iat: u64,
    exp: u64,
}

pub struct FcmPusher {
    http: reqwest::Client,
    project_id: String,
    client_email: String,
    token_uri: String,
    key: EncodingKey,
    /// The OAuth access token and when to stop using it.
    access: tokio::sync::Mutex<Option<(String, Instant)>>,
}

impl FcmPusher {
    /// Reads the service-account key file (the JSON Firebase lets you download).
    pub fn from_file(http: reqwest::Client, path: &str) -> Result<Self, String> {
        let text = std::fs::read_to_string(path)
            .map_err(|e| format!("cannot read the FCM service account file: {e}"))?;
        let account: ServiceAccount = serde_json::from_str(&text)
            .map_err(|e| format!("the FCM service account file is not valid: {e}"))?;
        let key = EncodingKey::from_rsa_pem(account.private_key.as_bytes())
            .map_err(|e| format!("the FCM service account key is not valid: {e}"))?;
        Ok(Self {
            http,
            project_id: account.project_id,
            client_email: account.client_email,
            token_uri: account
                .token_uri
                .unwrap_or_else(|| DEFAULT_TOKEN_URI.to_string()),
            key,
            access: tokio::sync::Mutex::new(None),
        })
    }

    async fn access_token(&self) -> Result<String, PushError> {
        let mut access = self.access.lock().await;
        if let Some((token, until)) = access.as_ref() {
            if Instant::now() < *until {
                return Ok(token.clone());
            }
        }

        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or_default();
        let claims = Claims {
            iss: &self.client_email,
            scope: SCOPE,
            aud: &self.token_uri,
            iat: now,
            exp: now + 3600,
        };
        let assertion = jsonwebtoken::encode(&Header::new(Algorithm::RS256), &claims, &self.key)
            .map_err(|e| PushError::Other(format!("could not sign the FCM request: {e}")))?;
        let reply: Value = self
            .http
            .post(&self.token_uri)
            .form(&[
                ("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer"),
                ("assertion", assertion.as_str()),
            ])
            .timeout(Duration::from_secs(20))
            .send()
            .await
            .map_err(|e| PushError::Other(format!("Google sign-in did not answer: {e}")))?
            .json()
            .await
            .map_err(|e| PushError::Other(format!("Google sign-in sent an odd reply: {e}")))?;
        let token = reply["access_token"]
            .as_str()
            .ok_or_else(|| PushError::Other("Google sign-in gave no access token".into()))?
            .to_string();
        let lifetime = reply["expires_in"].as_u64().unwrap_or(3600);
        // Renew a minute early.
        let until = Instant::now() + Duration::from_secs(lifetime.saturating_sub(60));
        *access = Some((token.clone(), until));
        Ok(token)
    }
}

#[async_trait]
impl Pusher for FcmPusher {
    async fn send(&self, token: &str, notice: &Notice) -> Result<(), PushError> {
        let access = self.access_token().await?;
        let response = self
            .http
            .post(format!(
                "https://fcm.googleapis.com/v1/projects/{}/messages:send",
                self.project_id
            ))
            .bearer_auth(access)
            .timeout(Duration::from_secs(20))
            .json(&json!({ "message": {
                "token": token,
                "notification": { "title": notice.title, "body": notice.body },
                "data": notice.data,
                "android": {
                    "priority": "HIGH",
                    "notification": { "channel_id": ANDROID_CHANNEL },
                },
                "apns": { "payload": { "aps": { "sound": "default" } } },
            }}))
            .send()
            .await
            .map_err(|e| PushError::Other(format!("FCM did not answer: {e}")))?;

        let status = response.status();
        if status.is_success() {
            return Ok(());
        }
        let body: Value = response.json().await.unwrap_or_default();
        let unregistered = status == reqwest::StatusCode::NOT_FOUND
            || body["error"]["details"]
                .as_array()
                .is_some_and(|details| details.iter().any(|d| d["errorCode"] == "UNREGISTERED"));
        if unregistered {
            return Err(PushError::Unregistered);
        }
        Err(PushError::Other(format!(
            "FCM refused the message ({status}): {}",
            body["error"]["message"].as_str().unwrap_or("no reason")
        )))
    }
}

/// What happened in a run that is worth a notification.
pub enum RunNews<'a> {
    /// The agent asked something and waits.
    Question(&'a str),
    Finished,
    Failed(&'a str),
}

fn shorten(text: &str) -> String {
    let text = text.trim();
    if text.chars().count() <= BODY_LIMIT {
        return text.to_string();
    }
    let cut: String = text.chars().take(BODY_LIMIT - 1).collect();
    format!("{}…", cut.trim_end())
}

/// Tells the project owner's devices about `news`, in the background. The
/// caller decides whether anyone is watching; this only delivers.
pub fn notify_run(st: &AppState, project_id: Uuid, run_id: Uuid, news: RunNews<'_>) {
    if !st.pusher.enabled() {
        return;
    }
    let (kind, body) = match news {
        RunNews::Question(question) => ("question", shorten(question)),
        RunNews::Finished => ("done", "GhostWriter has finished. Tap to open.".to_string()),
        RunNews::Failed(message) => ("fatal", shorten(&format!("GhostWriter stopped. {message}"))),
    };
    let st = st.clone();
    tokio::spawn(async move {
        if let Err(error) = deliver(&st, project_id, run_id, kind, body).await {
            tracing::warn!(%run_id, %error, "push: could not look up the devices");
        }
    });
}

async fn deliver(
    st: &AppState,
    project_id: Uuid,
    run_id: Uuid,
    kind: &str,
    body: String,
) -> Result<(), sqlx::Error> {
    let Some((user_id, title)): Option<(Uuid, String)> =
        sqlx::query_as("SELECT user_id, title FROM projects WHERE id = $1")
            .bind(project_id)
            .fetch_optional(&st.db)
            .await?
    else {
        return Ok(());
    };
    let devices: Vec<(Uuid, String)> =
        sqlx::query_as("SELECT id, token FROM devices WHERE user_id = $1 ORDER BY updated_at")
            .bind(user_id)
            .fetch_all(&st.db)
            .await?;
    if devices.is_empty() {
        return Ok(());
    }

    let notice = Notice {
        title,
        body,
        data: BTreeMap::from([
            ("type".to_string(), kind.to_string()),
            ("projectId".to_string(), project_id.to_string()),
            ("runId".to_string(), run_id.to_string()),
        ]),
    };
    for (device_id, token) in devices {
        match st.pusher.send(&token, &notice).await {
            Ok(()) => {}
            Err(PushError::Unregistered) => {
                sqlx::query("DELETE FROM devices WHERE id = $1 AND token = $2")
                    .bind(device_id)
                    .bind(&token)
                    .execute(&st.db)
                    .await?;
            }
            Err(PushError::Other(error)) => {
                tracing::warn!(%run_id, %device_id, %error, "push: not delivered");
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn long_text_is_cut_with_an_ellipsis() {
        assert_eq!(shorten("  Short.  "), "Short.");
        let long = "word ".repeat(100);
        let cut = shorten(&long);
        assert_eq!(cut.chars().count(), BODY_LIMIT);
        assert!(cut.ends_with("word…"));
    }
}

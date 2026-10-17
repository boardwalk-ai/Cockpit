//! Push notifications through Firebase Cloud Messaging (HTTP v1), which
//! reaches Android and iOS alike. Shared by the services that notify phones
//! (GhostWriter, Study Studio). Behind a trait so tests need no network.

use std::collections::BTreeMap;
use std::time::{Duration, Instant};

use axum::async_trait;
use jsonwebtoken::{Algorithm, EncodingKey, Header};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

const SCOPE: &str = "https://www.googleapis.com/auth/firebase.messaging";
const DEFAULT_TOKEN_URI: &str = "https://oauth2.googleapis.com/token";

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Notice {
    pub title: String,
    pub body: String,
    /// What the app needs to open the right screen. FCM data is all strings.
    pub data: BTreeMap<String, String>,
    /// A picture shown with it (a public https URL).
    pub image: Option<String>,
    /// Another Android channel than the sender's own.
    pub channel: Option<String>,
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
    /// The Android notification channel messages are shown in.
    channel: String,
    /// The OAuth access token and when to stop using it.
    access: tokio::sync::Mutex<Option<(String, Instant)>>,
}

impl FcmPusher {
    /// Reads the service-account key file (the JSON Firebase lets you
    /// download). Notifications go to the Android `channel` the app made.
    pub fn from_file(http: reqwest::Client, path: &str, channel: &str) -> Result<Self, String> {
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
            channel: channel.to_string(),
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
        let mut shown = json!({ "title": notice.title, "body": notice.body });
        if let Some(image) = &notice.image {
            shown["image"] = json!(image);
        }
        let channel = notice.channel.as_deref().unwrap_or(&self.channel);
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
                "notification": shown,
                "data": notice.data,
                "android": {
                    "priority": "HIGH",
                    "notification": { "channel_id": channel },
                },
                "apns": { "payload": { "aps": { "sound": "default", "mutable-content": 1 } } },
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

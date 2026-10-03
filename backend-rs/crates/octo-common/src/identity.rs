//! Identity + OctoCredits balance from the shared octopilot `users` table.
//!
//! The octopilot service owns this table (and its migrations); Rust services
//! only read it here. `octo_credits` is the single, central OctoCredits balance
//! shared by OctoNotes, Study Studio and OctopilotWeb.

use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};

use serde::Serialize;
use sqlx::{PgPool, Row};
use tokio::sync::RwLock;

use crate::error::ApiError;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UserRow {
    pub id: String,
    pub email: Option<String>,
    pub name: Option<String>,
    pub photo_url: Option<String>,
    pub plan: Option<String>,
    pub word_credits: i32,
    pub source_credits: i32,
    pub humanizer_credits: i32,
    pub octo_credits: i32,
    pub is_admin: bool,
    pub has_completed_wizard: bool,
}

/// Looks up a user by Firebase UID (the account the ID token belongs to).
pub async fn user_by_firebase_uid(pool: &PgPool, uid: &str) -> Result<Option<UserRow>, ApiError> {
    let row = sqlx::query(
        "SELECT id::text AS id, email, name, photo_url, plan, \
                COALESCE(word_credits,0) AS word_credits, \
                COALESCE(source_credits,0) AS source_credits, \
                COALESCE(humanizer_credits,0) AS humanizer_credits, \
                COALESCE(octo_credits,0) AS octo_credits, \
                COALESCE(is_admin,false) AS is_admin, \
                COALESCE(has_completed_wizard,false) AS has_completed_wizard \
         FROM users WHERE firebase_uid = $1",
    )
    .bind(uid)
    .fetch_optional(pool)
    .await?;

    Ok(row.map(|r| UserRow {
        id: r.get("id"),
        email: r.get("email"),
        name: r.get("name"),
        photo_url: r.get("photo_url"),
        plan: r.get("plan"),
        word_credits: r.get("word_credits"),
        source_credits: r.get("source_credits"),
        humanizer_credits: r.get("humanizer_credits"),
        octo_credits: r.get("octo_credits"),
        is_admin: r.get("is_admin"),
        has_completed_wizard: r.get("has_completed_wizard"),
    }))
}

/// Caches Firebase UID → `users.id`, which never changes for an account, so
/// every authed request doesn't cost a query against the shared DB. Balances
/// are NOT cached here — always read them fresh.
#[derive(Clone, Default)]
pub struct UserIdCache {
    inner: Arc<RwLock<HashMap<String, (String, Instant)>>>,
}

const USER_ID_TTL: Duration = Duration::from_secs(300);

impl UserIdCache {
    /// The caller's `users.id`, or `None` if they have no octopilot account yet.
    pub async fn user_id(
        &self,
        pool: &PgPool,
        firebase_uid: &str,
    ) -> Result<Option<String>, ApiError> {
        if let Some((id, at)) = self.inner.read().await.get(firebase_uid) {
            if at.elapsed() < USER_ID_TTL {
                return Ok(Some(id.clone()));
            }
        }
        let id: Option<String> =
            sqlx::query_scalar("SELECT id::text FROM users WHERE firebase_uid = $1")
                .bind(firebase_uid)
                .fetch_optional(pool)
                .await?;
        if let Some(id) = &id {
            self.inner
                .write()
                .await
                .insert(firebase_uid.to_string(), (id.clone(), Instant::now()));
        }
        Ok(id)
    }

    /// Drops a cached sign-in (the account was deleted).
    pub async fn forget(&self, firebase_uid: &str) {
        self.inner.write().await.remove(firebase_uid);
    }
}

//! Who is calling: the Firebase uid mapped to the octopilot `users.id`, or —
//! with no octopilot account (or no shared DB) — the same deterministic
//! uuid5 the Python service uses, so both resolve one person to one id.

use axum::{extract::FromRequestParts, http::request::Parts};
use octo_common::{auth::AuthedUser, error::ApiError};
use uuid::Uuid;

use crate::AppState;

/// `uuid5(NAMESPACE_URL, "https://cockpit.octopilot.ai/firebase")`, as in
/// `Backend/app/auth.py`.
fn firebase_ns() -> Uuid {
    Uuid::new_v5(&Uuid::NAMESPACE_URL, b"https://cockpit.octopilot.ai/firebase")
}

/// The fallback id for a Firebase uid with no octopilot account.
pub fn uid_to_user_id(firebase_uid: &str) -> Uuid {
    Uuid::new_v5(&firebase_ns(), firebase_uid.as_bytes())
}

/// The caller's user id (an axum extractor).
#[derive(Debug, Clone, Copy)]
pub struct UserId(pub Uuid);

#[axum::async_trait]
impl FromRequestParts<AppState> for UserId {
    type Rejection = ApiError;

    async fn from_request_parts(parts: &mut Parts, state: &AppState) -> Result<Self, ApiError> {
        let user = AuthedUser::from_request_parts(parts, state).await?;
        if !state.firebase.enabled() {
            // Dev: X-User-Id carries the id itself.
            return Uuid::parse_str(&user.uid)
                .map(UserId)
                .map_err(|_| ApiError::bad_request("Invalid X-User-Id"));
        }
        if let Some(shared) = &state.shared {
            if let Ok(Some(id)) = state.user_ids.user_id(shared, &user.uid).await {
                if let Ok(id) = Uuid::parse_str(&id) {
                    return Ok(UserId(id));
                }
            }
        }
        Ok(UserId(uid_to_user_id(&user.uid)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn same_fallback_as_python() {
        // python: uuid.uuid5(uuid.uuid5(uuid.NAMESPACE_URL,
        //   "https://cockpit.octopilot.ai/firebase"), "abc123")
        assert_eq!(
            uid_to_user_id("abc123").to_string(),
            include_str!("../tests/fixtures/uuid5_abc123.txt").trim()
        );
    }
}

//! Request context: who is calling, resolved to the shared `users.id`.

use axum::async_trait;
use axum::extract::FromRequestParts;
use axum::http::request::Parts;
use axum::http::StatusCode;
use octo_common::ApiError;
use uuid::Uuid;

use crate::AppState;

/// The authenticated caller. `user_id` is the octopilot `users.id` every
/// OctoNotes row is scoped by.
#[derive(Debug, Clone)]
pub struct Caller {
    pub uid: String,
    pub email: Option<String>,
    pub user_id: Uuid,
}

#[async_trait]
impl FromRequestParts<AppState> for Caller {
    type Rejection = ApiError;

    async fn from_request_parts(parts: &mut Parts, st: &AppState) -> Result<Self, Self::Rejection> {
        let user = st.firebase.authenticate(&parts.headers).await?;
        let user_id = match &st.octopilot {
            Some(pool) => {
                let id = st.user_ids.user_id(pool, &user.uid).await?.ok_or_else(|| {
                    ApiError::new(StatusCode::FORBIDDEN, "no Octopilot account for this sign-in")
                        .with_code("account_required")
                })?;
                Uuid::parse_str(&id).map_err(|_| ApiError::internal("bad users.id"))?
            }
            // Dev without the shared DB: a stable id derived from the header uid.
            None if !st.firebase.enabled() => Uuid::new_v5(&Uuid::NAMESPACE_OID, user.uid.as_bytes()),
            None => return Err(ApiError::unavailable("identity database not configured")),
        };
        Ok(Caller { uid: user.uid, email: user.email, user_id })
    }
}

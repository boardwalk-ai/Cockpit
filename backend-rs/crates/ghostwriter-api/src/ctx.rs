//! Request context: who is calling, resolved to the shared `users.id`.

use axum::async_trait;
use axum::extract::FromRequestParts;
use axum::http::request::Parts;
use axum::http::StatusCode;
use octo_common::ApiError;
use uuid::Uuid;

use crate::AppState;

/// The authenticated caller. `user_id` is the octopilot `users.id` every
/// GhostWriter row is scoped by.
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
        if let Some(access) = &st.access {
            // Test environment: the allowlist, and the GhostWriter flag for
            // its own routes (the main chat checks its flag in octo::ask).
            let path = parts.uri.path();
            let gw = ["/v1/projects", "/v1/runs", "/v1/folders"].iter().any(|p| path.starts_with(p));
            access.admit(&user, gw.then_some("ghostwriter")).await?;
        }
        let user_id = match &st.octopilot {
            Some(pool) => {
                let mut id = st.user_ids.user_id(pool, &user.uid).await?;
                // Staging: an allowed tester gets an account on first sign-in.
                if id.is_none() && provision(st, pool, &user).await? {
                    id = st.user_ids.user_id(pool, &user.uid).await?;
                }
                let id = id.ok_or_else(|| {
                    ApiError::new(
                        StatusCode::FORBIDDEN,
                        "no Octopilot account for this sign-in",
                    )
                    .with_code("account_required")
                })?;
                Uuid::parse_str(&id).map_err(|_| ApiError::internal("bad users.id"))?
            }
            // Dev without the shared DB: a stable id derived from the header uid.
            None if !st.firebase.enabled() => {
                Uuid::new_v5(&Uuid::NAMESPACE_OID, user.uid.as_bytes())
            }
            None => return Err(ApiError::unavailable("identity database not configured")),
        };
        Ok(Caller {
            uid: user.uid,
            email: user.email,
            user_id,
        })
    }
}

/// Makes an account for a first sign-in whose verified email is on the
/// allowlist (`ACCOUNT_ALLOWLIST`, staging only), with the starting
/// OctoCredits. True if one was made. Production leaves the list empty:
/// accounts come from the Octopilot sign-up.
pub async fn provision(
    st: &AppState,
    pool: &sqlx::PgPool,
    user: &octo_common::auth::AuthedUser,
) -> Result<bool, ApiError> {
    // Behind the access gate every caller here was already let in.
    if st.access.is_some() {
        return octo_common::access::provision(pool, user, st.config.starting_credits).await;
    }
    let allowed = &st.config.account_allowlist;
    let Some(email) = user.email.as_deref().map(str::to_lowercase) else {
        return Ok(false);
    };
    if allowed.is_empty() || !user.email_verified || !allowed.contains(&email) {
        return Ok(false);
    }
    let made = sqlx::query(
        "INSERT INTO users (firebase_uid, email, name, plan, octo_credits) \
         VALUES ($1, $2, $3, 'Staging Tester', $4) \
         ON CONFLICT DO NOTHING",
    )
    .bind(&user.uid)
    .bind(&email)
    .bind(user.name.as_deref().unwrap_or(&email))
    .bind(st.config.starting_credits)
    .execute(pool)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "could not make a tester account");
        ApiError::internal("could not make the account")
    })?
    .rows_affected()
        > 0;
    if made {
        tracing::info!(%email, "tester account made");
    }
    Ok(made)
}

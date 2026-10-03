//! What the app checks when it opens: must it update, may it, and is the
//! service down for maintenance. Admins write the shared `app_status`
//! table; this reads it (cached briefly, it is read on every request while
//! maintenance is checked).

use std::cmp::Ordering;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use axum::extract::{Request, State};
use axum::http::StatusCode;
use axum::middleware::Next;
use axum::response::{IntoResponse, Response};
use octo_common::ApiError;
use sqlx::PgPool;

use crate::AppState;

const CACHE_FOR: Duration = Duration::from_secs(30);

/// The `app` this service answers for in `app_status`.
pub const APP: &str = "ghostwriter";

#[derive(Clone, Debug, Default, sqlx::FromRow)]
pub struct Status {
    pub min_version: Option<String>,
    pub latest_version: Option<String>,
    pub store_url: Option<String>,
    pub maintenance: bool,
    pub maintenance_message: Option<String>,
}

type Key = (String, String);

#[derive(Clone, Default)]
pub struct AppStatus {
    cache: Arc<Mutex<HashMap<Key, (Instant, Status)>>>,
}

impl AppStatus {
    /// The row for `app` on `platform`, else its `*` row, else nothing set.
    pub async fn get(&self, pool: &PgPool, app: &str, platform: &str) -> Status {
        let key = (app.to_string(), platform.to_string());
        if let Some((at, status)) = self.cache.lock().unwrap().get(&key) {
            if at.elapsed() < CACHE_FOR {
                return status.clone();
            }
        }
        let status = sqlx::query_as::<_, Status>(
            "SELECT min_version, latest_version, store_url, maintenance, maintenance_message \
             FROM app_status WHERE app = $1 AND platform IN ($2, '*') \
             ORDER BY platform = '*' LIMIT 1",
        )
        .bind(app)
        .bind(platform)
        .fetch_optional(pool)
        .await
        .unwrap_or_else(|error| {
            tracing::warn!(%error, "app status: not readable");
            None
        })
        .unwrap_or_default();
        self.cache
            .lock()
            .unwrap()
            .insert(key, (Instant::now(), status.clone()));
        status
    }

    /// Drops the cache, so the next read sees the table as it is now.
    pub fn refresh(&self) {
        self.cache.lock().unwrap().clear();
    }
}

/// What `version` should do given `status`: `required`, `available` or `none`.
/// A version that cannot be read is never forced to update.
pub fn update(status: &Status, version: Option<&str>) -> &'static str {
    let Some(version) = version else {
        return "none";
    };
    let older = |than: &Option<String>| {
        than.as_deref()
            .and_then(|than| compare(version, than))
            .is_some_and(|o| o == Ordering::Less)
    };
    if older(&status.min_version) {
        "required"
    } else if older(&status.latest_version) {
        "available"
    } else {
        "none"
    }
}

/// Compares `1.2.3` style versions (a `+build` or `-pre` suffix is ignored,
/// missing parts are 0). `None` if either is not a version.
pub fn compare(a: &str, b: &str) -> Option<Ordering> {
    fn parts(v: &str) -> Option<Vec<u64>> {
        // An unencoded `+` arrives in a query string as a space.
        let core = v.trim().split(['+', '-', ' ']).next()?;
        core.split('.').map(|p| p.parse().ok()).collect()
    }
    let (mut a, mut b) = (parts(a)?, parts(b)?);
    let len = a.len().max(b.len());
    a.resize(len, 0);
    b.resize(len, 0);
    Some(a.cmp(&b))
}

/// While GhostWriter is in maintenance (its `*` row), every API call but the
/// status check gets 503 `maintenance` with the admin's message. Runs
/// already going carry on.
pub async fn guard(State(st): State<AppState>, req: Request, next: Next) -> Response {
    let open = !req.uri().path().starts_with("/v1/") || req.uri().path() == "/v1/app/status";
    if let (false, Some(pool)) = (open, &st.octopilot) {
        let status = st.app_status.get(pool, APP, "*").await;
        if status.maintenance {
            let message = status
                .maintenance_message
                .unwrap_or_else(|| "GhostWriter is down for maintenance. Back soon.".into());
            return ApiError::new(StatusCode::SERVICE_UNAVAILABLE, message)
                .with_code("maintenance")
                .into_response();
        }
    }
    next.run(req).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn versions_compare_by_number() {
        assert_eq!(compare("1.10.0", "1.9.9"), Some(Ordering::Greater));
        assert_eq!(compare("1.2", "1.2.0"), Some(Ordering::Equal));
        assert_eq!(compare("1.2.0+45", "1.2.0"), Some(Ordering::Equal));
        assert_eq!(compare("2.0.0-beta", "1.9.0"), Some(Ordering::Greater));
        assert_eq!(compare("dev", "1.0.0"), None);
    }

    #[test]
    fn update_follows_the_two_versions() {
        let status = Status {
            min_version: Some("1.2.0".into()),
            latest_version: Some("1.4.0".into()),
            ..Status::default()
        };
        assert_eq!(update(&status, Some("1.1.9")), "required");
        assert_eq!(update(&status, Some("1.2.0")), "available");
        assert_eq!(update(&status, Some("1.4.0")), "none");
        assert_eq!(update(&status, Some("nightly")), "none");
        assert_eq!(update(&status, None), "none");
        assert_eq!(update(&Status::default(), Some("0.0.1")), "none");
    }
}

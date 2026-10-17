//! Announcements from the admin app to testers' phones: a title, a text and
//! an optional picture, sent now through FCM to every phone the test app
//! registered (Study Studio's and GhostWriter's device tables). Tapping one
//! opens the app's Home.

use std::collections::{BTreeMap, BTreeSet};
use std::path::PathBuf;

use axum::body::Bytes;
use axum::extract::{Path, State};
use axum::http::{header, HeaderMap, StatusCode};
use axum::response::IntoResponse;
use axum::Json;
use futures::{stream, StreamExt};
use octo_common::push::{Notice, PushError};
use octo_common::ApiError;
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::{PgPool, Row};
use uuid::Uuid;

use crate::{log, Admin, AppState};

/// The Android channel the test app shows announcements in.
pub const CHANNEL: &str = "announcements";
const MAX_IMAGE: usize = 1024 * 1024;

pub const SCHEMA: &str = r#"
CREATE TABLE IF NOT EXISTS admin_notifications (
    id          uuid PRIMARY KEY,
    title       text NOT NULL,
    body        text NOT NULL,
    image       text,
    audience    jsonb NOT NULL,
    users       int NOT NULL DEFAULT 0,
    devices     int NOT NULL DEFAULT 0,
    sent        int NOT NULL DEFAULT 0,
    failed      int NOT NULL DEFAULT 0,
    created_by  text NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);
"#;

/// The device tables of the services the test app registers with.
#[derive(Clone)]
pub struct DeviceSources {
    /// Study Studio's DB (`study_devices`).
    pub study: Option<PgPool>,
    /// GhostWriter's DB (`devices`).
    pub ghostwriter: Option<PgPool>,
}

impl DeviceSources {
    /// Every token of these users, once each.
    async fn tokens(&self, users: &[Uuid]) -> BTreeSet<String> {
        let mut out = BTreeSet::new();
        for (pool, table) in [(&self.study, "study_devices"), (&self.ghostwriter, "devices")] {
            let Some(pool) = pool else { continue };
            let q = format!("SELECT token FROM {table} WHERE user_id = ANY($1)");
            match sqlx::query_scalar::<_, String>(&q).bind(users).fetch_all(pool).await {
                Ok(t) => out.extend(t),
                Err(e) => tracing::warn!("{table}: {e}"),
            }
        }
        out
    }

    /// A phone that's gone (app removed): forget it everywhere.
    async fn forget(&self, token: &str) {
        for (pool, table) in [(&self.study, "study_devices"), (&self.ghostwriter, "devices")] {
            if let Some(pool) = pool {
                let _ = sqlx::query(&format!("DELETE FROM {table} WHERE token = $1")).bind(token).execute(pool).await;
            }
        }
    }
}

// --------------------------------------------------------------- media

fn media_dir(st: &AppState) -> PathBuf {
    PathBuf::from(&st.config.media_dir)
}

/// `POST /v1/admin/media` (the image bytes, `Content-Type: image/png|jpeg|webp`)
/// → `{ url }`, a public link FCM can fetch.
pub async fn upload(State(st): State<AppState>, Admin(admin): Admin, headers: HeaderMap, body: Bytes) -> Result<Json<Value>, ApiError> {
    let kind = headers.get(header::CONTENT_TYPE).and_then(|v| v.to_str().ok()).unwrap_or("");
    let ext = match kind {
        "image/png" => "png",
        "image/jpeg" | "image/jpg" => "jpg",
        "image/webp" => "webp",
        _ => return Err(ApiError::bad_request("Send a PNG, JPEG or WebP picture.")),
    };
    if body.is_empty() || body.len() > MAX_IMAGE {
        return Err(ApiError::bad_request("A picture up to 1 MB."));
    }
    let name = format!("{}.{ext}", Uuid::new_v4().simple());
    let dir = media_dir(&st);
    tokio::fs::create_dir_all(&dir).await.map_err(|e| ApiError::internal(format!("media dir: {e}")))?;
    tokio::fs::write(dir.join(&name), &body).await.map_err(|e| ApiError::internal(format!("save: {e}")))?;
    log(&st, &admin, "media", &name, json!({ "bytes": body.len() })).await;
    Ok(Json(json!({ "url": format!("{}/media/{name}", st.config.public_url.trim_end_matches('/')) })))
}

/// `GET /media/{file}` — public, for FCM and the phones.
pub async fn media(State(st): State<AppState>, Path(file): Path<String>) -> impl IntoResponse {
    let ok = file.len() <= 40
        && file.split_once('.').is_some_and(|(id, ext)| {
            id.len() == 32 && id.chars().all(|c| c.is_ascii_hexdigit()) && matches!(ext, "png" | "jpg" | "webp")
        });
    if !ok {
        return StatusCode::NOT_FOUND.into_response();
    }
    match tokio::fs::read(media_dir(&st).join(&file)).await {
        Ok(bytes) => {
            let kind = match file.rsplit('.').next() {
                Some("png") => "image/png",
                Some("webp") => "image/webp",
                _ => "image/jpeg",
            };
            ([(header::CONTENT_TYPE, kind), (header::CACHE_CONTROL, "public, max-age=31536000, immutable")], bytes).into_response()
        }
        Err(_) => StatusCode::NOT_FOUND.into_response(),
    }
}

// ------------------------------------------------------------- sending

#[derive(Deserialize)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum Audience {
    /// The admin's own phones (to try one out).
    Me,
    Emails { emails: Vec<String> },
    /// Every account in the test environment.
    All,
}

#[derive(Deserialize)]
pub struct Compose {
    title: String,
    body: String,
    image: Option<String>,
    audience: Audience,
}

async fn users_for(st: &AppState, admin: &str, a: &Audience) -> Result<Vec<Uuid>, ApiError> {
    let rows = match a {
        Audience::Me => sqlx::query_scalar("SELECT id FROM users WHERE lower(email) = $1").bind(admin).fetch_all(&st.db).await?,
        Audience::Emails { emails } => {
            let emails: Vec<String> = emails.iter().map(|e| e.trim().to_lowercase()).filter(|e| !e.is_empty()).collect();
            if emails.is_empty() {
                return Err(ApiError::bad_request("Add at least one email."));
            }
            sqlx::query_scalar("SELECT id FROM users WHERE lower(email) = ANY($1)").bind(&emails).fetch_all(&st.db).await?
        }
        Audience::All => sqlx::query_scalar("SELECT id FROM users").fetch_all(&st.db).await?,
    };
    Ok(rows)
}

/// `POST /v1/admin/notifications` `{ title, body, image?, audience }` —
/// sends now; answers how many phones got it.
pub async fn send(State(st): State<AppState>, Admin(admin): Admin, Json(c): Json<Compose>) -> Result<Json<Value>, ApiError> {
    let title = c.title.trim().to_string();
    let body = c.body.trim().to_string();
    if title.is_empty() || title.chars().count() > 80 {
        return Err(ApiError::bad_request("A title of 1–80 characters."));
    }
    if body.chars().count() > 400 {
        return Err(ApiError::bad_request("The text is up to 400 characters."));
    }
    let image = c.image.map(|s| s.trim().to_string()).filter(|s| !s.is_empty());
    if image.as_deref().is_some_and(|u| !u.starts_with("https://")) {
        return Err(ApiError::bad_request("The picture must be an https link."));
    }
    if !st.pusher.enabled() {
        return Err(ApiError::unavailable("Push isn't set up on the server (FCM key)."));
    }
    let users = users_for(&st, &admin, &c.audience).await?;
    let mut tokens = st.devices.tokens(&users).await;
    tokens.extend(crate::devices::tokens(&st.db, &users).await);
    let id = Uuid::new_v4();
    let notice = Notice {
        title: title.clone(),
        body: body.clone(),
        data: BTreeMap::from([("type".into(), "announcement".into()), ("id".into(), id.to_string())]),
        image: image.clone(),
        channel: Some(CHANNEL.into()),
    };
    let results: Vec<Result<(), (String, PushError)>> = stream::iter(tokens.iter().cloned())
        .map(|t| {
            let (p, n) = (st.pusher.clone(), notice.clone());
            async move { p.send(&t, &n).await.map_err(|e| (t, e)) }
        })
        .buffer_unordered(16)
        .collect()
        .await;
    let mut sent = 0;
    let mut errors = Vec::new();
    for r in results {
        match r {
            Ok(()) => sent += 1,
            Err((t, PushError::Unregistered)) => {
                st.devices.forget(&t).await;
                crate::devices::token_dead(&st.db, &t).await;
                errors.push("a phone no longer has the app (forgotten)".to_string());
            }
            Err((t, PushError::Other(e))) => {
                if e.contains("not a valid FCM registration token") {
                    crate::devices::token_dead(&st.db, &t).await;
                }
                errors.push(e)
            }
        }
    }
    let failed = tokens.len() - sent;
    let audience = match &c.audience {
        Audience::Me => json!({ "kind": "me" }),
        Audience::Emails { emails } => json!({ "kind": "emails", "emails": emails }),
        Audience::All => json!({ "kind": "all" }),
    };
    sqlx::query(
        "INSERT INTO admin_notifications (id, title, body, image, audience, users, devices, sent, failed, created_by) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)",
    )
    .bind(id)
    .bind(&title)
    .bind(&body)
    .bind(&image)
    .bind(&audience)
    .bind(users.len() as i32)
    .bind(tokens.len() as i32)
    .bind(sent as i32)
    .bind(failed as i32)
    .bind(&admin)
    .execute(&st.db)
    .await?;
    log(&st, &admin, "notify", &title, json!({ "audience": audience, "devices": tokens.len(), "sent": sent })).await;
    errors.dedup();
    Ok(Json(json!({
        "id": id, "users": users.len(), "devices": tokens.len(), "sent": sent, "failed": failed,
        "errors": errors.into_iter().take(3).collect::<Vec<_>>(),
    })))
}

/// `GET /v1/admin/notifications` — what was sent, newest first.
pub async fn history(State(st): State<AppState>, _: Admin) -> Result<Json<Value>, ApiError> {
    let rows = sqlx::query(
        "SELECT id, title, body, image, audience, users, devices, sent, failed, created_by, created_at::text AS at \
         FROM admin_notifications ORDER BY created_at DESC LIMIT 100",
    )
    .fetch_all(&st.db)
    .await?;
    Ok(Json(json!(rows
        .iter()
        .map(|r| json!({
            "id": r.get::<Uuid, _>("id"),
            "title": r.get::<String, _>("title"),
            "body": r.get::<String, _>("body"),
            "image": r.get::<Option<String>, _>("image"),
            "audience": r.get::<Value, _>("audience"),
            "users": r.get::<i32, _>("users"),
            "devices": r.get::<i32, _>("devices"),
            "sent": r.get::<i32, _>("sent"),
            "failed": r.get::<i32, _>("failed"),
            "by": r.get::<String, _>("created_by"),
            "at": r.get::<String, _>("at"),
        }))
        .collect::<Vec<_>>())))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn audiences_parse() {
        assert!(matches!(serde_json::from_value::<Audience>(json!({ "kind": "me" })).unwrap(), Audience::Me));
        assert!(matches!(serde_json::from_value::<Audience>(json!({ "kind": "all" })).unwrap(), Audience::All));
        match serde_json::from_value::<Audience>(json!({ "kind": "emails", "emails": ["a@b.co"] })).unwrap() {
            Audience::Emails { emails } => assert_eq!(emails, ["a@b.co"]),
            _ => panic!(),
        }
    }
}

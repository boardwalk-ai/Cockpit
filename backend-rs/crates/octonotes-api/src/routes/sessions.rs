//! Sessions (Panels 1–3): create, list/search, open (snapshot), edit, delete.

use axum::extract::{Path, Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::Json;
use base64::Engine;
use chrono::{DateTime, Utc};
use octo_common::ApiError;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sqlx::{PgConnection, Postgres, QueryBuilder};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::ctx::Caller;
use crate::routes::blocks::{self, Block};
use crate::routes::ink::{self, InkPage};
use crate::{access, idempotency, revs, AppState};

const WORKSPACE_MODES: &[&str] = &["typewriter", "pencil", "both"];
const STATUSES: &[&str] = &[
    "draft",
    "live",
    "paused",
    "ended",
    "reviewing",
    "finalized",
    "archived",
];

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct Session {
    pub id: Uuid,
    pub course_id: Option<Uuid>,
    pub title: String,
    pub workspace_mode: String,
    #[schema(value_type = Object)]
    pub config: Value,
    pub status: String,
    pub deck_ref: Option<String>,
    pub started_at: Option<DateTime<Utc>>,
    pub ended_at: Option<DateTime<Utc>>,
    pub duration_ms: i64,
    #[schema(value_type = Object)]
    pub layout_prefs: Value,
    pub revision: i64,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

pub const SESSION_COLUMNS: &str =
    "id, course_id, title, workspace_mode, config, status, deck_ref, started_at, \
    ended_at, duration_ms, layout_prefs, revision, created_at, updated_at";

#[derive(Debug, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct CreateSession {
    pub id: Option<Uuid>,
    pub title: Option<String>,
    pub course_id: Option<Uuid>,
    pub workspace_mode: Option<String>,
    /// New Session toggles; merged over the defaults.
    #[schema(value_type = Option<Object>)]
    pub config: Option<Value>,
    pub deck_ref: Option<String>,
}

#[utoipa::path(post, path = "/v1/sessions", tag = "sessions", request_body = CreateSession,
    responses((status = 201, body = Session)))]
pub async fn create(
    State(st): State<AppState>,
    caller: Caller,
    headers: HeaderMap,
    Json(req): Json<CreateSession>,
) -> Result<(StatusCode, Json<Value>), ApiError> {
    let idem = idempotency::key(&headers);
    let hash = idempotency::hash(&req);
    if let Some(k) = &idem {
        if let Some((code, body)) = idempotency::replay(&st.notes, caller.user_id, k, &hash).await?
        {
            return Ok((code, Json(body)));
        }
    }
    let mode = req.workspace_mode.unwrap_or_else(|| "typewriter".into());
    if !WORKSPACE_MODES.contains(&mode.as_str()) {
        return Err(ApiError::bad_request(
            "workspaceMode must be typewriter, pencil or both",
        ));
    }
    let title = clean_title(req.title.as_deref())?;
    let mut conn = st.notes.acquire().await?;
    if let Some(course) = req.course_id {
        ensure_course(&mut conn, &caller, course).await?;
    }
    if let Some(r) = &req.deck_ref {
        validate_deck_ref(r)?;
    }
    let config = merge_config(
        json!({
            "record": true, "liveTranscription": true, "smartOrganization": true, "liveSuggestions": true
        }),
        req.config,
    )?;

    let session = sqlx::query_as::<_, Session>(&format!(
        "INSERT INTO sessions (id, user_id, course_id, title, workspace_mode, config, deck_ref) \
         VALUES (COALESCE($1, gen_random_uuid()), $2, $3, $4, $5, $6, $7) \
         ON CONFLICT (id) DO NOTHING RETURNING {SESSION_COLUMNS}"
    ))
    .bind(req.id)
    .bind(caller.user_id)
    .bind(req.course_id)
    .bind(&title)
    .bind(&mode)
    .bind(&config)
    .bind(&req.deck_ref)
    .fetch_optional(&mut *conn)
    .await?;
    let session = match session {
        Some(s) => s,
        // Same client id sent twice (offline retry): return the existing one.
        None => owned(&mut conn, &caller, req.id.expect("conflict implies id")).await?,
    };
    drop(conn);
    let body = serde_json::to_value(&session).unwrap_or(Value::Null);
    if let Some(k) = &idem {
        idempotency::store(
            &st.notes,
            caller.user_id,
            k,
            &hash,
            StatusCode::CREATED,
            &body,
        )
        .await?;
    }
    Ok((StatusCode::CREATED, Json(body)))
}

fn clean_title(t: Option<&str>) -> Result<String, ApiError> {
    let t = t
        .map(str::trim)
        .filter(|t| !t.is_empty())
        .unwrap_or("Untitled session");
    if t.chars().count() > 300 {
        return Err(ApiError::bad_request("title too long"));
    }
    Ok(t.to_string())
}

pub fn validate_deck_ref(r: &str) -> Result<(), ApiError> {
    let ok = r
        .split_once(':')
        .is_some_and(|(kind, id)| matches!(kind, "studio" | "deck") && Uuid::parse_str(id).is_ok());
    if ok {
        Ok(())
    } else {
        Err(ApiError::bad_request(
            "deckRef must be 'studio:<uuid>' or 'deck:<uuid>'",
        ))
    }
}

/// Shallow merge of the known boolean toggles; unknown keys are rejected so a
/// typo can't silently disable a feature.
fn merge_config(mut base: Value, patch: Option<Value>) -> Result<Value, ApiError> {
    let Some(patch) = patch else { return Ok(base) };
    let obj = patch
        .as_object()
        .ok_or_else(|| ApiError::bad_request("config must be an object"))?;
    for (k, v) in obj {
        if !matches!(
            k.as_str(),
            "record" | "liveTranscription" | "smartOrganization" | "liveSuggestions"
        ) {
            return Err(ApiError::bad_request(format!("unknown config key '{k}'")));
        }
        if !v.is_boolean() {
            return Err(ApiError::bad_request(format!(
                "config.{k} must be a boolean"
            )));
        }
        base[k] = v.clone();
    }
    Ok(base)
}

async fn ensure_course(
    conn: &mut PgConnection,
    caller: &Caller,
    course: Uuid,
) -> Result<(), ApiError> {
    let ok: Option<Uuid> = sqlx::query_scalar(
        "SELECT id FROM courses WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL",
    )
    .bind(course)
    .bind(caller.user_id)
    .fetch_optional(conn)
    .await?;
    ok.map(|_| ())
        .ok_or_else(|| ApiError::bad_request("unknown courseId"))
}

pub async fn owned(
    conn: &mut PgConnection,
    caller: &Caller,
    id: Uuid,
) -> Result<Session, ApiError> {
    sqlx::query_as::<_, Session>(&format!(
        "SELECT {SESSION_COLUMNS} FROM sessions WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL"
    ))
    .bind(id)
    .bind(caller.user_id)
    .fetch_optional(conn)
    .await?
    .ok_or_else(|| ApiError::not_found("session not found"))
}

#[derive(Debug, Deserialize, utoipa::IntoParams)]
#[serde(rename_all = "camelCase")]
pub struct ListQuery {
    /// Full-text search over the title.
    pub q: Option<String>,
    pub course_id: Option<Uuid>,
    /// Comma-separated statuses.
    pub status: Option<String>,
    /// Workspace mode filter (`typewriter`, `pencil`, `both`).
    #[serde(rename = "type")]
    pub kind: Option<String>,
    pub from: Option<DateTime<Utc>>,
    pub to: Option<DateTime<Utc>>,
    pub cursor: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct SessionList {
    pub items: Vec<Session>,
    pub next_cursor: Option<String>,
}

#[utoipa::path(get, path = "/v1/sessions", tag = "sessions", params(ListQuery),
    responses((status = 200, body = SessionList)))]
pub async fn list(
    State(st): State<AppState>,
    caller: Caller,
    Query(q): Query<ListQuery>,
) -> Result<Json<SessionList>, ApiError> {
    let limit = q.limit.unwrap_or(20).clamp(1, 100);
    let mut qb: QueryBuilder<Postgres> = QueryBuilder::new(format!(
        "SELECT {SESSION_COLUMNS} FROM sessions WHERE deleted_at IS NULL AND user_id = "
    ));
    qb.push_bind(caller.user_id);
    if let Some(text) = q.q.as_deref().map(str::trim).filter(|t| !t.is_empty()) {
        qb.push(" AND (search @@ plainto_tsquery('simple', ")
            .push_bind(text.to_string())
            .push(") OR title ILIKE ")
            .push_bind(format!("%{}%", text.replace('%', "\\%")))
            .push(")");
    }
    if let Some(c) = q.course_id {
        qb.push(" AND course_id = ").push_bind(c);
    }
    if let Some(statuses) = &q.status {
        let list: Vec<String> = statuses
            .split(',')
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect();
        if let Some(bad) = list.iter().find(|s| !STATUSES.contains(&s.as_str())) {
            return Err(ApiError::bad_request(format!("unknown status '{bad}'")));
        }
        qb.push(" AND status = ANY(").push_bind(list).push(")");
    }
    if let Some(k) = &q.kind {
        qb.push(" AND workspace_mode = ").push_bind(k.clone());
    }
    if let Some(f) = q.from {
        qb.push(" AND updated_at >= ").push_bind(f);
    }
    if let Some(t) = q.to {
        qb.push(" AND updated_at < ").push_bind(t);
    }
    if let Some(c) = &q.cursor {
        let (ts, id) = decode_cursor(c)?;
        qb.push(" AND (updated_at, id) < (")
            .push_bind(ts)
            .push(", ")
            .push_bind(id)
            .push(")");
    }
    qb.push(" ORDER BY updated_at DESC, id DESC LIMIT ")
        .push_bind(limit + 1);
    let mut items: Vec<Session> = qb.build_query_as().fetch_all(&st.notes).await?;
    let next_cursor = if items.len() as i64 > limit {
        items.truncate(limit as usize);
        items.last().map(|s| encode_cursor(s.updated_at, s.id))
    } else {
        None
    };
    Ok(Json(SessionList { items, next_cursor }))
}

pub fn encode_cursor(ts: DateTime<Utc>, id: Uuid) -> String {
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(format!("{}|{}", ts.to_rfc3339(), id))
}

pub fn decode_cursor(c: &str) -> Result<(DateTime<Utc>, Uuid), ApiError> {
    let bad = || ApiError::bad_request("invalid cursor");
    let raw = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(c)
        .map_err(|_| bad())?;
    let s = String::from_utf8(raw).map_err(|_| bad())?;
    let (ts, id) = s.split_once('|').ok_or_else(bad)?;
    Ok((
        DateTime::parse_from_rfc3339(ts)
            .map_err(|_| bad())?
            .with_timezone(&Utc),
        Uuid::parse_str(id).map_err(|_| bad())?,
    ))
}

/// Everything needed to open a session in one call.
#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct SessionSnapshot {
    pub session: Session,
    pub blocks: Vec<Block>,
    pub ink_pages: Vec<InkPage>,
    #[schema(value_type = Vec<Object>)]
    pub devices: Value,
    /// Current revision per layer (`blocks`, `ink`, `transcript` …).
    #[schema(value_type = Object)]
    pub revs: Value,
}

#[utoipa::path(get, path = "/v1/sessions/{id}", tag = "sessions", params(("id" = Uuid, Path)),
    responses((status = 200, body = SessionSnapshot)))]
pub async fn get(
    State(st): State<AppState>,
    caller: Caller,
    Path(id): Path<Uuid>,
) -> Result<Json<SessionSnapshot>, ApiError> {
    let mut conn = st.notes.acquire().await?;
    let session = owned(&mut conn, &caller, id).await?;
    let blocks = blocks::load_blocks(&mut conn, id, None).await?;
    let ink_pages = ink::load_pages(&mut conn, id).await?;
    let devices: Value = sqlx::query_scalar(
        "SELECT COALESCE(json_agg(json_build_object('deviceId', d.id, 'name', d.name, 'platform', d.platform, \
             'role', sd.role, 'isRecording', sd.is_recording, 'lastSeenAt', sd.last_seen_at) ORDER BY sd.joined_at), '[]') \
         FROM session_devices sd JOIN devices d ON d.id = sd.device_id WHERE sd.session_id = $1",
    )
    .bind(id)
    .fetch_one(&mut *conn)
    .await?;
    let revs: Value = sqlx::query_scalar(
        "SELECT COALESCE(json_object_agg(layer, rev), '{}') FROM session_layer_revs WHERE session_id = $1",
    )
    .bind(id)
    .fetch_one(&mut *conn)
    .await?;
    Ok(Json(SessionSnapshot {
        session,
        blocks,
        ink_pages,
        devices,
        revs,
    }))
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct UpdateSession {
    pub title: Option<String>,
    /// `null` clears the course.
    #[serde(default, deserialize_with = "double_option")]
    #[schema(value_type = Option<Uuid>)]
    pub course_id: Option<Option<Uuid>>,
    pub workspace_mode: Option<String>,
    #[schema(value_type = Option<Object>)]
    pub config: Option<Value>,
    #[serde(default, deserialize_with = "double_option")]
    #[schema(value_type = Option<String>)]
    pub deck_ref: Option<Option<String>>,
    #[schema(value_type = Option<Object>)]
    pub layout_prefs: Option<Value>,
}

/// Distinguishes "field absent" (None) from "field: null" (Some(None)).
fn double_option<'de, D, T>(d: D) -> Result<Option<Option<T>>, D::Error>
where
    D: serde::Deserializer<'de>,
    T: Deserialize<'de>,
{
    Option::<T>::deserialize(d).map(Some)
}

#[utoipa::path(patch, path = "/v1/sessions/{id}", tag = "sessions", params(("id" = Uuid, Path)),
    request_body = UpdateSession, responses((status = 200, body = Session)))]
pub async fn update(
    State(st): State<AppState>,
    caller: Caller,
    Path(id): Path<Uuid>,
    Json(req): Json<UpdateSession>,
) -> Result<Json<Session>, ApiError> {
    let mut tx = st.notes.begin().await?;
    let cur = owned(&mut tx, &caller, id).await?;
    let title = match &req.title {
        Some(t) => clean_title(Some(t))?,
        None => cur.title.clone(),
    };
    let mode = req
        .workspace_mode
        .clone()
        .unwrap_or(cur.workspace_mode.clone());
    if !WORKSPACE_MODES.contains(&mode.as_str()) {
        return Err(ApiError::bad_request(
            "workspaceMode must be typewriter, pencil or both",
        ));
    }
    let course_id = match req.course_id {
        Some(Some(c)) => {
            ensure_course(&mut tx, &caller, c).await?;
            Some(c)
        }
        Some(None) => None,
        None => cur.course_id,
    };
    let deck_ref = match req.deck_ref {
        Some(Some(r)) => {
            validate_deck_ref(&r)?;
            Some(r)
        }
        Some(None) => None,
        None => cur.deck_ref.clone(),
    };
    let config = merge_config(cur.config.clone(), req.config)?;
    let layout = match req.layout_prefs {
        Some(v) if v.is_object() => v,
        Some(_) => return Err(ApiError::bad_request("layoutPrefs must be an object")),
        None => cur.layout_prefs.clone(),
    };
    let session = sqlx::query_as::<_, Session>(&format!(
        "UPDATE sessions SET title = $2, workspace_mode = $3, course_id = $4, deck_ref = $5, config = $6, \
             layout_prefs = $7, revision = revision + 1 WHERE id = $1 RETURNING {SESSION_COLUMNS}"
    ))
    .bind(id)
    .bind(title)
    .bind(mode)
    .bind(course_id)
    .bind(deck_ref)
    .bind(config)
    .bind(layout)
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(Json(session))
}

#[utoipa::path(delete, path = "/v1/sessions/{id}", tag = "sessions", params(("id" = Uuid, Path)),
    responses((status = 204)))]
pub async fn delete(
    State(st): State<AppState>,
    caller: Caller,
    Path(id): Path<Uuid>,
) -> Result<StatusCode, ApiError> {
    let mut conn = st.notes.acquire().await?;
    access::session(&mut conn, &caller, id).await?;
    sqlx::query("UPDATE sessions SET deleted_at = now() WHERE id = $1")
        .bind(id)
        .execute(&mut *conn)
        .await?;
    Ok(StatusCode::NO_CONTENT)
}

/// Current revision of each layer, for the snapshot and catch-up.
pub async fn layer_rev(conn: &mut PgConnection, id: Uuid, layer: &str) -> Result<i64, ApiError> {
    Ok(revs::current(conn, id, layer).await?)
}

//! Magic Pencil (Panel 6): pages and vector strokes, synced like blocks.
//!
//! Stroke points use format v1, sent base64-encoded:
//! `[u8 version=1][u32 LE count][count × (f32 x, f32 y, f32 pressure) LE]`.
//! The server validates the framing and stores the bytes as-is — ink is never
//! rasterized or flattened.

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use base64::Engine;
use chrono::{DateTime, Utc};
use octo_common::ApiError;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sqlx::PgConnection;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::ctx::Caller;
use crate::realtime::Event;
use crate::routes::blocks::SinceRev;
use crate::{access, revs, AppState};

const TOOLS: &[&str] = &[
    "pen",
    "pencil",
    "highlighter",
    "rect",
    "circle",
    "line",
    "text",
];
const BACKGROUNDS: &[&str] = &["blank", "lined", "grid", "dotted"];
const MAX_POINTS: usize = 20_000;

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct InkPage {
    pub id: Uuid,
    pub session_id: Uuid,
    pub ordinal: i32,
    pub background: String,
    pub width: f32,
    pub height: f32,
    pub revision: i64,
    pub layer_rev: i64,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub deleted_at: Option<DateTime<Utc>>,
}

const PAGE_COLUMNS: &str = "id, session_id, ordinal, background, width, height, revision, layer_rev, created_at, updated_at, deleted_at";

#[derive(Debug, Clone, sqlx::FromRow)]
struct StrokeRow {
    id: Uuid,
    page_id: Uuid,
    tool: String,
    points: Vec<u8>,
    color: String,
    width: f32,
    text: Option<String>,
    audio_ts_ms: Option<i64>,
    device_id: Option<Uuid>,
    revision: i64,
    layer_rev: i64,
    created_at: DateTime<Utc>,
    deleted_at: Option<DateTime<Utc>>,
}

const STROKE_COLUMNS: &str = "id, page_id, tool, points, color, width, text, audio_ts_ms, device_id, revision, layer_rev, created_at, deleted_at";

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct Stroke {
    pub id: Uuid,
    pub page_id: Uuid,
    pub tool: String,
    /// Base64 of stroke format v1.
    pub points: String,
    pub color: String,
    pub width: f32,
    pub text: Option<String>,
    pub audio_ts_ms: Option<i64>,
    pub device_id: Option<Uuid>,
    pub revision: i64,
    pub layer_rev: i64,
    pub created_at: DateTime<Utc>,
    pub deleted_at: Option<DateTime<Utc>>,
}

impl From<StrokeRow> for Stroke {
    fn from(r: StrokeRow) -> Self {
        Stroke {
            id: r.id,
            page_id: r.page_id,
            tool: r.tool,
            points: base64::engine::general_purpose::STANDARD.encode(&r.points),
            color: r.color,
            width: r.width,
            text: r.text,
            audio_ts_ms: r.audio_ts_ms,
            device_id: r.device_id,
            revision: r.revision,
            layer_rev: r.layer_rev,
            created_at: r.created_at,
            deleted_at: r.deleted_at,
        }
    }
}

/// Decodes and checks stroke format v1; returns the raw bytes.
pub fn decode_points(b64: &str) -> Result<Vec<u8>, String> {
    let bytes = base64::engine::general_purpose::STANDARD
        .decode(b64)
        .map_err(|_| "points must be base64".to_string())?;
    if bytes.len() < 5 || bytes[0] != 1 {
        return Err("points must be stroke format v1".into());
    }
    let count = u32::from_le_bytes([bytes[1], bytes[2], bytes[3], bytes[4]]) as usize;
    if count == 0 || count > MAX_POINTS {
        return Err(format!("a stroke needs 1..{MAX_POINTS} points"));
    }
    if bytes.len() != 5 + count * 12 {
        return Err("points length does not match its count".into());
    }
    Ok(bytes)
}

/// Parsed points `(x, y, pressure)` — used when rendering ink for recognition.
pub fn parse_points(bytes: &[u8]) -> Vec<(f32, f32, f32)> {
    if bytes.len() < 5 {
        return Vec::new();
    }
    bytes[5..]
        .chunks_exact(12)
        .map(|c| {
            let f = |i: usize| f32::from_le_bytes([c[i], c[i + 1], c[i + 2], c[i + 3]]);
            (f(0), f(4), f(8))
        })
        .collect()
}

pub async fn load_pages(
    conn: &mut PgConnection,
    session_id: Uuid,
) -> Result<Vec<InkPage>, sqlx::Error> {
    sqlx::query_as::<_, InkPage>(&format!(
        "SELECT {PAGE_COLUMNS} FROM ink_pages WHERE session_id = $1 AND deleted_at IS NULL ORDER BY ordinal, created_at"
    ))
    .bind(session_id)
    .fetch_all(conn)
    .await
}

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct PagesResponse {
    pub rev: i64,
    pub pages: Vec<InkPage>,
}

#[utoipa::path(get, path = "/v1/sessions/{id}/ink/pages", tag = "ink", params(("id" = Uuid, Path)),
    responses((status = 200, body = PagesResponse)))]
pub async fn list_pages(
    State(st): State<AppState>,
    caller: Caller,
    Path(session_id): Path<Uuid>,
) -> Result<Json<PagesResponse>, ApiError> {
    let mut conn = st.notes.acquire().await?;
    access::session(&mut conn, &caller, session_id).await?;
    let rev = revs::current(&mut conn, session_id, revs::INK).await?;
    Ok(Json(PagesResponse {
        rev,
        pages: load_pages(&mut conn, session_id).await?,
    }))
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct PageInput {
    /// Client-generated; creating the same id twice returns the existing page.
    pub id: Option<Uuid>,
    pub ordinal: Option<i32>,
    pub background: Option<String>,
    pub width: Option<f32>,
    pub height: Option<f32>,
}

fn check_page(input: &PageInput) -> Result<(), ApiError> {
    if let Some(b) = &input.background {
        if !BACKGROUNDS.contains(&b.as_str()) {
            return Err(ApiError::bad_request(
                "background must be blank, lined, grid or dotted",
            ));
        }
    }
    for v in [input.width, input.height].into_iter().flatten() {
        if !(100.0..=20_000.0).contains(&v) {
            return Err(ApiError::bad_request("page size out of range"));
        }
    }
    Ok(())
}

#[utoipa::path(post, path = "/v1/sessions/{id}/ink/pages", tag = "ink", params(("id" = Uuid, Path)),
    request_body = PageInput, responses((status = 201, body = InkPage)))]
pub async fn create_page(
    State(st): State<AppState>,
    caller: Caller,
    Path(session_id): Path<Uuid>,
    Json(req): Json<PageInput>,
) -> Result<(StatusCode, Json<InkPage>), ApiError> {
    check_page(&req)?;
    let mut tx = st.notes.begin().await?;
    access::writable_session(&mut tx, &caller, session_id).await?;
    revs::lock(&mut tx, session_id, revs::INK).await?;
    let id = req.id.unwrap_or_else(Uuid::new_v4);
    if let Some(existing) = sqlx::query_as::<_, InkPage>(&format!(
        "SELECT {PAGE_COLUMNS} FROM ink_pages WHERE id = $1"
    ))
    .bind(id)
    .fetch_optional(&mut *tx)
    .await?
    {
        if existing.session_id != session_id {
            return Err(ApiError::bad_request("page id already in use"));
        }
        return Ok((StatusCode::OK, Json(existing)));
    }
    let ordinal = match req.ordinal {
        Some(o) => o,
        None => sqlx::query_scalar::<_, i32>("SELECT COALESCE(MAX(ordinal) + 1, 0) FROM ink_pages WHERE session_id = $1 AND deleted_at IS NULL")
            .bind(session_id)
            .fetch_one(&mut *tx)
            .await?,
    };
    let rev = revs::bump(&mut tx, session_id, revs::INK).await?;
    let page = sqlx::query_as::<_, InkPage>(&format!(
        "INSERT INTO ink_pages (id, session_id, user_id, ordinal, background, width, height, layer_rev) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING {PAGE_COLUMNS}"
    ))
    .bind(id)
    .bind(session_id)
    .bind(caller.user_id)
    .bind(ordinal)
    .bind(req.background.as_deref().unwrap_or("blank"))
    .bind(req.width.unwrap_or(1240.0))
    .bind(req.height.unwrap_or(1754.0))
    .bind(rev)
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;
    st.hub
        .session(
            session_id,
            Event::new("ink.changed", json!({ "pageIds": [id] }), Some(rev)),
        )
        .await;
    Ok((StatusCode::CREATED, Json(page)))
}

async fn owned_page(
    conn: &mut PgConnection,
    caller: &Caller,
    page_id: Uuid,
) -> Result<InkPage, ApiError> {
    let page = sqlx::query_as::<_, InkPage>(&format!(
        "SELECT {PAGE_COLUMNS} FROM ink_pages WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL"
    ))
    .bind(page_id)
    .bind(caller.user_id)
    .fetch_optional(&mut *conn)
    .await?
    .ok_or_else(|| ApiError::not_found("page not found"))?;
    access::writable_session(conn, caller, page.session_id).await?;
    Ok(page)
}

#[utoipa::path(patch, path = "/v1/ink/pages/{id}", tag = "ink", params(("id" = Uuid, Path)),
    request_body = PageInput, responses((status = 200, body = InkPage)))]
pub async fn update_page(
    State(st): State<AppState>,
    caller: Caller,
    Path(page_id): Path<Uuid>,
    Json(req): Json<PageInput>,
) -> Result<Json<InkPage>, ApiError> {
    check_page(&req)?;
    let mut tx = st.notes.begin().await?;
    let page = owned_page(&mut tx, &caller, page_id).await?;
    revs::lock(&mut tx, page.session_id, revs::INK).await?;
    let rev = revs::bump(&mut tx, page.session_id, revs::INK).await?;
    let page = sqlx::query_as::<_, InkPage>(&format!(
        "UPDATE ink_pages SET background = COALESCE($2, background), ordinal = COALESCE($3, ordinal), \
             width = COALESCE($4, width), height = COALESCE($5, height), revision = revision + 1, layer_rev = $6 \
         WHERE id = $1 RETURNING {PAGE_COLUMNS}"
    ))
    .bind(page_id)
    .bind(&req.background)
    .bind(req.ordinal)
    .bind(req.width)
    .bind(req.height)
    .bind(rev)
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;
    st.hub
        .session(
            page.session_id,
            Event::new("ink.changed", json!({ "pageIds": [page_id] }), Some(rev)),
        )
        .await;
    Ok(Json(page))
}

#[utoipa::path(delete, path = "/v1/ink/pages/{id}", tag = "ink", params(("id" = Uuid, Path)), responses((status = 204)))]
pub async fn delete_page(
    State(st): State<AppState>,
    caller: Caller,
    Path(page_id): Path<Uuid>,
) -> Result<StatusCode, ApiError> {
    let mut tx = st.notes.begin().await?;
    let page = owned_page(&mut tx, &caller, page_id).await?;
    revs::lock(&mut tx, page.session_id, revs::INK).await?;
    let rev = revs::bump(&mut tx, page.session_id, revs::INK).await?;
    sqlx::query("UPDATE ink_pages SET deleted_at = now(), revision = revision + 1, layer_rev = $2 WHERE id = $1")
        .bind(page_id)
        .bind(rev)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;
    st.hub
        .session(
            page.session_id,
            Event::new("ink.changed", json!({ "pageIds": [page_id] }), Some(rev)),
        )
        .await;
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct StrokesResponse {
    pub rev: i64,
    /// With `sinceRev`, erased strokes are included with `deletedAt` set.
    pub strokes: Vec<Stroke>,
}

#[utoipa::path(get, path = "/v1/ink/pages/{id}/strokes", tag = "ink", params(("id" = Uuid, Path), SinceRev),
    responses((status = 200, body = StrokesResponse)))]
pub async fn page_strokes(
    State(st): State<AppState>,
    caller: Caller,
    Path(page_id): Path<Uuid>,
    Query(q): Query<SinceRev>,
) -> Result<Json<StrokesResponse>, ApiError> {
    let mut conn = st.notes.acquire().await?;
    let session_id: Uuid =
        sqlx::query_scalar("SELECT session_id FROM ink_pages WHERE id = $1 AND user_id = $2")
            .bind(page_id)
            .bind(caller.user_id)
            .fetch_optional(&mut *conn)
            .await?
            .ok_or_else(|| ApiError::not_found("page not found"))?;
    access::session(&mut conn, &caller, session_id).await?;
    let rev = revs::current(&mut conn, session_id, revs::INK).await?;
    let rows = strokes_query(&mut conn, "page_id", page_id, q.since_rev).await?;
    Ok(Json(StrokesResponse {
        rev,
        strokes: rows.into_iter().map(Stroke::from).collect(),
    }))
}

#[utoipa::path(get, path = "/v1/sessions/{id}/ink/strokes", tag = "ink", params(("id" = Uuid, Path), SinceRev),
    responses((status = 200, body = StrokesResponse)))]
pub async fn session_strokes(
    State(st): State<AppState>,
    caller: Caller,
    Path(session_id): Path<Uuid>,
    Query(q): Query<SinceRev>,
) -> Result<Json<StrokesResponse>, ApiError> {
    let mut conn = st.notes.acquire().await?;
    access::session(&mut conn, &caller, session_id).await?;
    let rev = revs::current(&mut conn, session_id, revs::INK).await?;
    let rows = strokes_query(&mut conn, "session_id", session_id, q.since_rev).await?;
    Ok(Json(StrokesResponse {
        rev,
        strokes: rows.into_iter().map(Stroke::from).collect(),
    }))
}

async fn strokes_query(
    conn: &mut PgConnection,
    column: &str,
    id: Uuid,
    since: Option<i64>,
) -> Result<Vec<StrokeRow>, sqlx::Error> {
    match since {
        Some(since) => sqlx::query_as::<_, StrokeRow>(&format!(
            "SELECT {STROKE_COLUMNS} FROM ink_strokes WHERE {column} = $1 AND layer_rev > $2 ORDER BY layer_rev"
        ))
        .bind(id)
        .bind(since)
        .fetch_all(conn)
        .await,
        None => sqlx::query_as::<_, StrokeRow>(&format!(
            "SELECT {STROKE_COLUMNS} FROM ink_strokes WHERE {column} = $1 AND deleted_at IS NULL ORDER BY created_at, id"
        ))
        .bind(id)
        .fetch_all(conn)
        .await,
    }
}

/// Loads a page's live strokes as `(tool, color, width, points)` for rendering.
pub async fn strokes_for_render(
    conn: &mut PgConnection,
    page_id: Uuid,
    ids: &[Uuid],
) -> Result<Vec<(String, String, f32, Vec<(f32, f32, f32)>)>, sqlx::Error> {
    let rows: Vec<StrokeRow> = sqlx::query_as(&format!(
        "SELECT {STROKE_COLUMNS} FROM ink_strokes WHERE page_id = $1 AND id = ANY($2) AND deleted_at IS NULL"
    ))
    .bind(page_id)
    .bind(ids)
    .fetch_all(conn)
    .await?;
    Ok(rows
        .into_iter()
        .map(|r| (r.tool, r.color, r.width, parse_points(&r.points)))
        .collect())
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct StrokeInput {
    pub tool: Option<String>,
    pub points: Option<String>,
    pub color: Option<String>,
    pub width: Option<f32>,
    pub text: Option<String>,
    pub audio_ts_ms: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct StrokeOp {
    pub client_op_id: String,
    /// `add` | `update` (move / restyle) | `erase`
    pub op: String,
    pub stroke_id: Uuid,
    #[serde(default)]
    pub base_revision: i64,
    pub stroke: Option<StrokeInput>,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct StrokeOpsRequest {
    pub device_id: Option<Uuid>,
    pub ops: Vec<StrokeOp>,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct StrokeOpResult {
    pub client_op_id: String,
    pub status: String,
    pub stroke: Option<Stroke>,
    pub error: Option<String>,
}

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct StrokeOpsResponse {
    pub rev: i64,
    pub results: Vec<StrokeOpResult>,
}

fn check_color(c: &str) -> bool {
    let hex = c.strip_prefix('#').unwrap_or("");
    (hex.len() == 6 || hex.len() == 8) && hex.chars().all(|ch| ch.is_ascii_hexdigit())
}

#[utoipa::path(post, path = "/v1/ink/pages/{id}/ops", tag = "ink", params(("id" = Uuid, Path)),
    request_body = StrokeOpsRequest, responses((status = 200, body = StrokeOpsResponse)))]
pub async fn stroke_ops(
    State(st): State<AppState>,
    caller: Caller,
    Path(page_id): Path<Uuid>,
    Json(req): Json<StrokeOpsRequest>,
) -> Result<Json<StrokeOpsResponse>, ApiError> {
    if req.ops.len() > 500 {
        return Err(ApiError::bad_request("at most 500 ops per request"));
    }
    let mut tx = st.notes.begin().await?;
    let page = owned_page(&mut tx, &caller, page_id).await?;
    let session_id = page.session_id;
    revs::lock(&mut tx, session_id, revs::INK).await?;

    let mut results = Vec::with_capacity(req.ops.len());
    let mut changed = Vec::new();
    for op in &req.ops {
        let prev: Option<Value> = sqlx::query_scalar(
            "SELECT result FROM applied_ops WHERE session_id = $1 AND client_op_id = $2",
        )
        .bind(session_id)
        .bind(&op.client_op_id)
        .fetch_optional(&mut *tx)
        .await?;
        if let Some(prev) = prev.and_then(|v| serde_json::from_value::<StrokeOpResult>(v).ok()) {
            results.push(prev);
            continue;
        }
        let result = apply_stroke(&mut tx, &caller, session_id, page_id, req.device_id, op).await?;
        sqlx::query("INSERT INTO applied_ops (session_id, client_op_id, result) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING")
            .bind(session_id)
            .bind(&op.client_op_id)
            .bind(serde_json::to_value(&result).unwrap_or(Value::Null))
            .execute(&mut *tx)
            .await?;
        if result.status == "applied" {
            changed.push(op.stroke_id);
        }
        results.push(result);
    }
    let rev = revs::current(&mut tx, session_id, revs::INK).await?;
    tx.commit().await?;
    if !changed.is_empty() {
        st.hub
            .session(session_id, Event::new("ink.changed", json!({ "pageIds": [page_id], "strokeIds": changed, "deviceId": req.device_id }), Some(rev)))
            .await;
    }
    Ok(Json(StrokeOpsResponse { rev, results }))
}

fn stroke_result(
    op: &StrokeOp,
    status: &str,
    stroke: Option<Stroke>,
    error: Option<String>,
) -> StrokeOpResult {
    StrokeOpResult {
        client_op_id: op.client_op_id.clone(),
        status: status.into(),
        stroke,
        error,
    }
}

async fn apply_stroke(
    conn: &mut PgConnection,
    caller: &Caller,
    session_id: Uuid,
    page_id: Uuid,
    device_id: Option<Uuid>,
    op: &StrokeOp,
) -> Result<StrokeOpResult, ApiError> {
    if op.client_op_id.is_empty() || op.client_op_id.len() > 128 {
        return Ok(stroke_result(
            op,
            "rejected",
            None,
            Some("clientOpId must be 1..128 chars".into()),
        ));
    }
    let existing: Option<StrokeRow> = sqlx::query_as(&format!(
        "SELECT {STROKE_COLUMNS} FROM ink_strokes WHERE id = $1 FOR UPDATE"
    ))
    .bind(op.stroke_id)
    .fetch_optional(&mut *conn)
    .await?;
    if existing.as_ref().is_some_and(|s| s.page_id != page_id) {
        return Ok(stroke_result(
            op,
            "rejected",
            None,
            Some("stroke belongs to another page".into()),
        ));
    }
    let input = op.stroke.clone().unwrap_or(StrokeInput {
        tool: None,
        points: None,
        color: None,
        width: None,
        text: None,
        audio_ts_ms: None,
    });
    if let Some(t) = &input.tool {
        if !TOOLS.contains(&t.as_str()) {
            return Ok(stroke_result(
                op,
                "rejected",
                None,
                Some(format!("unknown tool '{t}'")),
            ));
        }
    }
    if input.color.as_deref().is_some_and(|c| !check_color(c)) {
        return Ok(stroke_result(
            op,
            "rejected",
            None,
            Some("color must be #RRGGBB or #AARRGGBB".into()),
        ));
    }
    if input.width.is_some_and(|w| !(0.1..=200.0).contains(&w)) {
        return Ok(stroke_result(
            op,
            "rejected",
            None,
            Some("width out of range".into()),
        ));
    }
    let points = match input.points.as_deref().map(decode_points).transpose() {
        Ok(p) => p,
        Err(e) => return Ok(stroke_result(op, "rejected", None, Some(e))),
    };

    let row: StrokeRow = match (op.op.as_str(), existing) {
        ("add", None) => {
            let (Some(tool), Some(points)) = (input.tool.clone(), points) else {
                return Ok(stroke_result(
                    op,
                    "rejected",
                    None,
                    Some("add needs tool and points".into()),
                ));
            };
            let rev = revs::bump(conn, session_id, revs::INK).await?;
            sqlx::query_as(&format!(
                "INSERT INTO ink_strokes (id, page_id, session_id, user_id, tool, points, color, width, text, audio_ts_ms, device_id, layer_rev) \
                 VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) RETURNING {STROKE_COLUMNS}"
            ))
            .bind(op.stroke_id)
            .bind(page_id)
            .bind(session_id)
            .bind(caller.user_id)
            .bind(tool)
            .bind(points)
            .bind(input.color.as_deref().unwrap_or("#FF000000"))
            .bind(input.width.unwrap_or(2.0))
            .bind(&input.text)
            .bind(input.audio_ts_ms)
            .bind(device_id)
            .bind(rev)
            .fetch_one(&mut *conn)
            .await?
        }
        // Re-sent add of a stroke we already have: same stroke, no change.
        ("add", Some(cur)) => return Ok(stroke_result(op, "applied", Some(cur.into()), None)),
        ("update", Some(cur)) => {
            if cur.deleted_at.is_some() || op.base_revision != cur.revision {
                return Ok(stroke_result(
                    op,
                    "conflict",
                    Some(cur.into()),
                    Some("stroke changed on the server".into()),
                ));
            }
            let rev = revs::bump(conn, session_id, revs::INK).await?;
            sqlx::query_as(&format!(
                "UPDATE ink_strokes SET tool = COALESCE($2, tool), points = COALESCE($3, points), color = COALESCE($4, color), \
                     width = COALESCE($5, width), text = COALESCE($6, text), revision = revision + 1, layer_rev = $7 \
                 WHERE id = $1 RETURNING {STROKE_COLUMNS}"
            ))
            .bind(cur.id)
            .bind(&input.tool)
            .bind(points)
            .bind(&input.color)
            .bind(input.width)
            .bind(&input.text)
            .bind(rev)
            .fetch_one(&mut *conn)
            .await?
        }
        ("erase", Some(cur)) => {
            if cur.deleted_at.is_some() {
                return Ok(stroke_result(op, "applied", Some(cur.into()), None));
            }
            let rev = revs::bump(conn, session_id, revs::INK).await?;
            sqlx::query_as(&format!(
                "UPDATE ink_strokes SET deleted_at = now(), revision = revision + 1, layer_rev = $2 WHERE id = $1 RETURNING {STROKE_COLUMNS}"
            ))
            .bind(cur.id)
            .bind(rev)
            .fetch_one(&mut *conn)
            .await?
        }
        ("update" | "erase", None) => {
            return Ok(stroke_result(
                op,
                "rejected",
                None,
                Some("unknown stroke".into()),
            ))
        }
        (other, _) => {
            return Ok(stroke_result(
                op,
                "rejected",
                None,
                Some(format!("unknown op '{other}'")),
            ))
        }
    };
    Ok(stroke_result(op, "applied", Some(row.into()), None))
}

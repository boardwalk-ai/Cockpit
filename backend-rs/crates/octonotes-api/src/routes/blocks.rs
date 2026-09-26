//! Typewriter blocks (Panel 5): block-level sync with per-block optimistic
//! concurrency, history and restore.
//!
//! Rules enforced here, whatever the client does:
//! - the client never creates or edits an `aiInsertedByStudent` block — only the
//!   AI apply endpoints do, so AI can't silently change student text;
//! - `origin` is fixed at creation;
//! - a stale `baseRevision` is a conflict, answered with the server copy (the
//!   client keeps both versions), never a silent overwrite;
//! - replaying an op (same `clientOpId`) changes nothing.

use axum::extract::{Path, Query, State};
use axum::Json;
use chrono::{DateTime, Utc};
use octo_common::ApiError;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sqlx::{PgConnection, Row};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::ctx::Caller;
use crate::realtime::Event;
use crate::{access, positions, revs, AppState};

pub const BLOCK_TYPES: &[&str] = &[
    "paragraph",
    "h1",
    "h2",
    "h3",
    "bulleted",
    "numbered",
    "checklist",
    "quote",
    "definition",
    "keyIdea",
    "formula",
    "example",
    "question",
    "examHint",
    "warning",
    "assignment",
    "summary",
    "table",
    "image",
    "diagram",
    "slideRef",
    "pdfExcerpt",
    "transcriptExcerpt",
    "audioTimestamp",
    "divider",
];
/// Origins a client may create directly. `aiInsertedByStudent` only comes from
/// the AI apply endpoints.
const CLIENT_ORIGINS: &[&str] = &["student", "fromInk", "fromTranscript", "fromSlide"];
const MAX_TEXT: usize = 100_000;
const MAX_OPS: usize = 500;

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct Block {
    pub id: Uuid,
    pub session_id: Uuid,
    pub section_id: Option<Uuid>,
    pub position: String,
    #[serde(rename = "type")]
    #[sqlx(rename = "type")]
    pub kind: String,
    pub text: String,
    pub checked: bool,
    pub indent: i32,
    pub origin: String,
    pub device_id: Option<Uuid>,
    pub audio_ts_ms: Option<i64>,
    #[schema(value_type = Option<Object>)]
    pub transcript_anchor: Option<Value>,
    #[schema(value_type = Option<Object>)]
    pub source_ref: Option<Value>,
    #[schema(value_type = Vec<Object>)]
    pub ai_sources: Value,
    pub topic_links: Vec<String>,
    pub assignment_links: Vec<String>,
    pub study_studio_selected: bool,
    pub revision: i64,
    pub layer_rev: i64,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub deleted_at: Option<DateTime<Utc>>,
}

pub const BLOCK_COLUMNS: &str = "id, session_id, section_id, position, type, text, checked, indent, origin, \
    device_id, audio_ts_ms, transcript_anchor, source_ref, ai_sources, topic_links, assignment_links, \
    study_studio_selected, revision, layer_rev, created_at, updated_at, deleted_at";

/// Fields a client sends for create/update. Missing fields keep their current
/// value on update.
#[derive(Debug, Clone, Default, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct BlockInput {
    #[serde(rename = "type")]
    pub kind: Option<String>,
    pub text: Option<String>,
    pub checked: Option<bool>,
    pub indent: Option<i32>,
    pub origin: Option<String>,
    pub section_id: Option<Uuid>,
    pub position: Option<String>,
    pub audio_ts_ms: Option<i64>,
    #[schema(value_type = Option<Object>)]
    pub transcript_anchor: Option<Value>,
    #[schema(value_type = Option<Object>)]
    pub source_ref: Option<Value>,
    pub topic_links: Option<Vec<String>>,
    pub assignment_links: Option<Vec<String>>,
    pub study_studio_selected: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct BlockOp {
    /// Unique per client op; replays are no-ops.
    pub client_op_id: String,
    /// `upsert` | `move` | `delete`
    pub op: String,
    pub block_id: Uuid,
    /// The block revision the client edited (0 = new block).
    #[serde(default)]
    pub base_revision: i64,
    pub block: Option<BlockInput>,
    /// New position for `move`.
    pub position: Option<String>,
    pub section_id: Option<Uuid>,
    pub indent: Option<i32>,
}

#[derive(Debug, Deserialize, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct OpsRequest {
    pub device_id: Option<Uuid>,
    pub ops: Vec<BlockOp>,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct OpResult {
    pub client_op_id: String,
    /// `applied` | `conflict` | `rejected`
    pub status: String,
    pub block: Option<Block>,
    pub error: Option<String>,
}

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct OpsResponse {
    pub rev: i64,
    pub results: Vec<OpResult>,
}

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct BlocksPage {
    /// Current blocks-layer revision; pass it back as `sinceRev`.
    pub rev: i64,
    /// Ordered by position. With `sinceRev`, only changed blocks (deleted ones
    /// included, with `deletedAt` set).
    pub blocks: Vec<Block>,
}

#[derive(Debug, Deserialize, utoipa::IntoParams)]
#[serde(rename_all = "camelCase")]
pub struct SinceRev {
    pub since_rev: Option<i64>,
}

#[utoipa::path(get, path = "/v1/sessions/{id}/blocks", tag = "blocks",
    params(("id" = Uuid, Path), SinceRev), responses((status = 200, body = BlocksPage)))]
pub async fn list(
    State(st): State<AppState>,
    caller: Caller,
    Path(session_id): Path<Uuid>,
    Query(q): Query<SinceRev>,
) -> Result<Json<BlocksPage>, ApiError> {
    let mut conn = st.notes.acquire().await?;
    access::session(&mut conn, &caller, session_id).await?;
    let rev = revs::current(&mut conn, session_id, revs::BLOCKS).await?;
    let blocks = load_blocks(&mut conn, session_id, q.since_rev).await?;
    Ok(Json(BlocksPage { rev, blocks }))
}

pub async fn load_blocks(
    conn: &mut PgConnection,
    session_id: Uuid,
    since_rev: Option<i64>,
) -> Result<Vec<Block>, sqlx::Error> {
    match since_rev {
        Some(since) => {
            sqlx::query_as::<_, Block>(&format!(
                "SELECT {BLOCK_COLUMNS} FROM blocks WHERE session_id = $1 AND layer_rev > $2 ORDER BY position, id"
            ))
            .bind(session_id)
            .bind(since)
            .fetch_all(conn)
            .await
        }
        None => {
            sqlx::query_as::<_, Block>(&format!(
                "SELECT {BLOCK_COLUMNS} FROM blocks WHERE session_id = $1 AND deleted_at IS NULL ORDER BY position, id"
            ))
            .bind(session_id)
            .fetch_all(conn)
            .await
        }
    }
}

#[utoipa::path(post, path = "/v1/sessions/{id}/blocks/ops", tag = "blocks",
    params(("id" = Uuid, Path)), request_body = OpsRequest, responses((status = 200, body = OpsResponse)))]
pub async fn ops(
    State(st): State<AppState>,
    caller: Caller,
    Path(session_id): Path<Uuid>,
    Json(req): Json<OpsRequest>,
) -> Result<Json<OpsResponse>, ApiError> {
    if req.ops.len() > MAX_OPS {
        return Err(ApiError::bad_request(format!(
            "at most {MAX_OPS} ops per request"
        )));
    }
    let mut tx = st.notes.begin().await?;
    access::writable_session(&mut tx, &caller, session_id).await?;
    revs::lock(&mut tx, session_id, revs::BLOCKS).await?;

    let mut results = Vec::with_capacity(req.ops.len());
    let mut changed = Vec::new();
    for op in &req.ops {
        if let Some(prev) = applied(&mut tx, session_id, &op.client_op_id).await? {
            results.push(prev);
            continue;
        }
        let result = apply(&mut tx, &caller, session_id, req.device_id, op).await?;
        record(&mut tx, session_id, &result).await?;
        if result.status == "applied" {
            changed.push(op.block_id);
        }
        results.push(result);
    }
    let rev = revs::current(&mut tx, session_id, revs::BLOCKS).await?;
    tx.commit().await?;

    if !changed.is_empty() {
        st.hub
            .session(
                session_id,
                Event::new(
                    "block.changed",
                    json!({ "blockIds": changed, "deviceId": req.device_id }),
                    Some(rev),
                ),
            )
            .await;
    }
    Ok(Json(OpsResponse { rev, results }))
}

async fn applied(
    conn: &mut PgConnection,
    session_id: Uuid,
    client_op_id: &str,
) -> Result<Option<OpResult>, ApiError> {
    let row: Option<Value> = sqlx::query_scalar(
        "SELECT result FROM applied_ops WHERE session_id = $1 AND client_op_id = $2",
    )
    .bind(session_id)
    .bind(client_op_id)
    .fetch_optional(conn)
    .await?;
    Ok(row.and_then(|v| serde_json::from_value(v).ok()))
}

async fn record(
    conn: &mut PgConnection,
    session_id: Uuid,
    result: &OpResult,
) -> Result<(), ApiError> {
    sqlx::query("INSERT INTO applied_ops (session_id, client_op_id, result) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING")
        .bind(session_id)
        .bind(&result.client_op_id)
        .bind(serde_json::to_value(result).unwrap_or(Value::Null))
        .execute(conn)
        .await?;
    Ok(())
}

fn rejected(op: &BlockOp, error: impl Into<String>) -> OpResult {
    OpResult {
        client_op_id: op.client_op_id.clone(),
        status: "rejected".into(),
        block: None,
        error: Some(error.into()),
    }
}

fn conflict(op: &BlockOp, server: Block) -> OpResult {
    OpResult {
        client_op_id: op.client_op_id.clone(),
        status: "conflict".into(),
        block: Some(server),
        error: Some(format!(
            "block changed on the server (revision {})",
            op.base_revision
        )),
    }
}

async fn fetch_for_update(
    conn: &mut PgConnection,
    block_id: Uuid,
) -> Result<Option<Block>, sqlx::Error> {
    sqlx::query_as::<_, Block>(&format!(
        "SELECT {BLOCK_COLUMNS} FROM blocks WHERE id = $1 FOR UPDATE"
    ))
    .bind(block_id)
    .fetch_optional(conn)
    .await
}

fn validate_input(input: &BlockInput) -> Result<(), String> {
    if let Some(k) = &input.kind {
        if !BLOCK_TYPES.contains(&k.as_str()) {
            return Err(format!("unknown block type '{k}'"));
        }
    }
    if let Some(p) = &input.position {
        if !positions::is_valid(p) {
            return Err("invalid position key".into());
        }
    }
    if input.text.as_ref().is_some_and(|t| t.len() > MAX_TEXT) {
        return Err("text too long".into());
    }
    if input.indent.is_some_and(|i| !(0..=8).contains(&i)) {
        return Err("indent must be 0..8".into());
    }
    Ok(())
}

async fn apply(
    conn: &mut PgConnection,
    caller: &Caller,
    session_id: Uuid,
    device_id: Option<Uuid>,
    op: &BlockOp,
) -> Result<OpResult, ApiError> {
    if op.client_op_id.is_empty() || op.client_op_id.len() > 128 {
        return Ok(rejected(op, "clientOpId must be 1..128 chars"));
    }
    let existing = fetch_for_update(conn, op.block_id).await?;
    if let Some(b) = &existing {
        if b.session_id != session_id {
            return Ok(rejected(op, "block belongs to another session"));
        }
        if b.origin == "aiInsertedByStudent" && op.op == "upsert" {
            // Text of an AI block stays as approved; only move/delete/restore.
            let changes_text = op
                .block
                .as_ref()
                .is_some_and(|i| i.text.is_some() || i.kind.is_some());
            if changes_text {
                return Ok(rejected(
                    op,
                    "AI-inserted blocks can be moved or deleted, not rewritten",
                ));
            }
        }
    }

    match (op.op.as_str(), existing) {
        ("upsert", None) => {
            if op.base_revision != 0 {
                return Ok(rejected(op, "unknown block"));
            }
            let input = op.block.clone().unwrap_or_default();
            if let Err(e) = validate_input(&input) {
                return Ok(rejected(op, e));
            }
            let origin = input.origin.clone().unwrap_or_else(|| "student".into());
            if !CLIENT_ORIGINS.contains(&origin.as_str()) {
                return Ok(rejected(
                    op,
                    format!("origin '{origin}' cannot be created by a client"),
                ));
            }
            let (Some(kind), Some(position)) = (input.kind.clone(), input.position.clone()) else {
                return Ok(rejected(op, "new blocks need type and position"));
            };
            let rev = revs::bump(conn, session_id, revs::BLOCKS).await?;
            let block = sqlx::query_as::<_, Block>(&format!(
                "INSERT INTO blocks (id, session_id, user_id, section_id, position, type, text, checked, indent, origin, \
                     device_id, audio_ts_ms, transcript_anchor, source_ref, topic_links, assignment_links, \
                     study_studio_selected, revision, layer_rev) \
                 VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,1,$18) RETURNING {BLOCK_COLUMNS}"
            ))
            .bind(op.block_id)
            .bind(session_id)
            .bind(caller.user_id)
            .bind(input.section_id)
            .bind(&position)
            .bind(&kind)
            .bind(input.text.clone().unwrap_or_default())
            .bind(input.checked.unwrap_or(false))
            .bind(input.indent.unwrap_or(0))
            .bind(&origin)
            .bind(device_id)
            .bind(input.audio_ts_ms)
            .bind(&input.transcript_anchor)
            .bind(&input.source_ref)
            .bind(input.topic_links.clone().unwrap_or_default())
            .bind(input.assignment_links.clone().unwrap_or_default())
            .bind(input.study_studio_selected.unwrap_or(false))
            .bind(rev)
            .fetch_one(&mut *conn)
            .await?;
            snapshot(conn, caller, &block, "create", device_id).await?;
            Ok(applied_result(op, block))
        }
        ("upsert", Some(cur)) => {
            if cur.deleted_at.is_some() || op.base_revision != cur.revision {
                return Ok(conflict(op, cur));
            }
            let input = op.block.clone().unwrap_or_default();
            if let Err(e) = validate_input(&input) {
                return Ok(rejected(op, e));
            }
            let rev = revs::bump(conn, session_id, revs::BLOCKS).await?;
            let block = sqlx::query_as::<_, Block>(&format!(
                "UPDATE blocks SET type = $2, text = $3, checked = $4, indent = $5, section_id = $6, position = $7, \
                     audio_ts_ms = $8, transcript_anchor = $9, source_ref = $10, topic_links = $11, \
                     assignment_links = $12, study_studio_selected = $13, device_id = $14, \
                     revision = revision + 1, layer_rev = $15 \
                 WHERE id = $1 RETURNING {BLOCK_COLUMNS}"
            ))
            .bind(cur.id)
            .bind(input.kind.unwrap_or(cur.kind))
            .bind(input.text.unwrap_or(cur.text))
            .bind(input.checked.unwrap_or(cur.checked))
            .bind(input.indent.unwrap_or(cur.indent))
            .bind(input.section_id.or(cur.section_id))
            .bind(input.position.unwrap_or(cur.position))
            .bind(input.audio_ts_ms.or(cur.audio_ts_ms))
            .bind(input.transcript_anchor.or(cur.transcript_anchor))
            .bind(input.source_ref.or(cur.source_ref))
            .bind(input.topic_links.unwrap_or(cur.topic_links))
            .bind(input.assignment_links.unwrap_or(cur.assignment_links))
            .bind(input.study_studio_selected.unwrap_or(cur.study_studio_selected))
            .bind(device_id.or(cur.device_id))
            .bind(rev)
            .fetch_one(&mut *conn)
            .await?;
            snapshot(conn, caller, &block, "update", device_id).await?;
            Ok(applied_result(op, block))
        }
        ("move", Some(cur)) => {
            if cur.deleted_at.is_some() || op.base_revision != cur.revision {
                return Ok(conflict(op, cur));
            }
            let Some(position) = op.position.clone().filter(|p| positions::is_valid(p)) else {
                return Ok(rejected(op, "move needs a valid position"));
            };
            if op.indent.is_some_and(|i| !(0..=8).contains(&i)) {
                return Ok(rejected(op, "indent must be 0..8"));
            }
            let rev = revs::bump(conn, session_id, revs::BLOCKS).await?;
            let block = sqlx::query_as::<_, Block>(&format!(
                "UPDATE blocks SET position = $2, section_id = COALESCE($3, section_id), indent = COALESCE($4, indent), \
                     revision = revision + 1, layer_rev = $5 WHERE id = $1 RETURNING {BLOCK_COLUMNS}"
            ))
            .bind(cur.id)
            .bind(position)
            .bind(op.section_id)
            .bind(op.indent)
            .bind(rev)
            .fetch_one(&mut *conn)
            .await?;
            snapshot(conn, caller, &block, "move", device_id).await?;
            Ok(applied_result(op, block))
        }
        ("delete", Some(cur)) => {
            if cur.deleted_at.is_some() {
                // Already gone — deleting twice is fine.
                return Ok(applied_result(op, cur));
            }
            if op.base_revision != cur.revision {
                return Ok(conflict(op, cur));
            }
            let rev = revs::bump(conn, session_id, revs::BLOCKS).await?;
            let block = sqlx::query_as::<_, Block>(&format!(
                "UPDATE blocks SET deleted_at = now(), revision = revision + 1, layer_rev = $2 WHERE id = $1 RETURNING {BLOCK_COLUMNS}"
            ))
            .bind(cur.id)
            .bind(rev)
            .fetch_one(&mut *conn)
            .await?;
            snapshot(conn, caller, &block, "delete", device_id).await?;
            Ok(applied_result(op, block))
        }
        ("move" | "delete", None) => Ok(rejected(op, "unknown block")),
        (other, _) => Ok(rejected(op, format!("unknown op '{other}'"))),
    }
}

fn applied_result(op: &BlockOp, block: Block) -> OpResult {
    OpResult {
        client_op_id: op.client_op_id.clone(),
        status: "applied".into(),
        block: Some(block),
        error: None,
    }
}

/// Stores the block as it now is in `block_revisions`.
pub async fn snapshot(
    conn: &mut PgConnection,
    caller: &Caller,
    block: &Block,
    op: &str,
    device_id: Option<Uuid>,
) -> Result<(), ApiError> {
    sqlx::query(
        "INSERT INTO block_revisions (block_id, session_id, user_id, revision, op, snapshot, device_id) \
         VALUES ($1,$2,$3,$4,$5,$6,$7)",
    )
    .bind(block.id)
    .bind(block.session_id)
    .bind(caller.user_id)
    .bind(block.revision)
    .bind(op)
    .bind(serde_json::to_value(block).unwrap_or(Value::Null))
    .bind(device_id)
    .execute(conn)
    .await?;
    Ok(())
}

/// Server-side block creation (AI apply, from-source): computes a position
/// right after `after` (or at the end), bumps the layer and snapshots.
pub async fn insert_server_block(
    conn: &mut PgConnection,
    caller: &Caller,
    b: NewServerBlock,
) -> Result<Block, ApiError> {
    revs::lock(conn, b.session_id, revs::BLOCKS).await?;
    let position = position_after(conn, b.session_id, b.after).await?;
    let rev = revs::bump(conn, b.session_id, revs::BLOCKS).await?;
    let block = sqlx::query_as::<_, Block>(&format!(
        "INSERT INTO blocks (id, session_id, user_id, position, type, text, origin, audio_ts_ms, transcript_anchor,              source_ref, ai_sources, indent, revision, layer_rev)          VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,1,$13) RETURNING {BLOCK_COLUMNS}"
    ))
    .bind(Uuid::new_v4())
    .bind(b.session_id)
    .bind(caller.user_id)
    .bind(position)
    .bind(b.kind)
    .bind(b.text)
    .bind(b.origin)
    .bind(b.audio_ts_ms)
    .bind(b.transcript_anchor)
    .bind(b.source_ref)
    .bind(b.ai_sources.unwrap_or_else(|| json!([])))
    .bind(b.indent.clamp(0, 8))
    .bind(rev)
    .fetch_one(&mut *conn)
    .await?;
    snapshot(conn, caller, &block, "create", None).await?;
    Ok(block)
}

/// A block the server creates on the student's behalf.
pub struct NewServerBlock {
    pub session_id: Uuid,
    /// Insert right after this block (end of the note when None).
    pub after: Option<Uuid>,
    pub kind: String,
    pub text: String,
    /// `aiInsertedByStudent`, `fromTranscript`, `fromSlide` or `fromInk`.
    pub origin: String,
    pub audio_ts_ms: Option<i64>,
    pub transcript_anchor: Option<Value>,
    pub source_ref: Option<Value>,
    pub ai_sources: Option<Value>,
    pub indent: i32,
}

async fn position_after(
    conn: &mut PgConnection,
    session_id: Uuid,
    after: Option<Uuid>,
) -> Result<String, ApiError> {
    let keys: Vec<String> = match after {
        Some(after) => {
            let anchor: Option<String> = sqlx::query_scalar(
                "SELECT position FROM blocks WHERE id = $1 AND session_id = $2 AND deleted_at IS NULL",
            )
            .bind(after)
            .bind(session_id)
            .fetch_optional(&mut *conn)
            .await?;
            let Some(anchor) = anchor else { return Err(ApiError::not_found("anchor block not found")) };
            let next: Option<String> = sqlx::query_scalar(
                "SELECT position FROM blocks WHERE session_id = $1 AND deleted_at IS NULL AND position > $2 \
                 ORDER BY position LIMIT 1",
            )
            .bind(session_id)
            .bind(&anchor)
            .fetch_optional(&mut *conn)
            .await?;
            return Ok(positions::between(Some(&anchor), next.as_deref()));
        }
        None => sqlx::query_scalar(
            "SELECT position FROM blocks WHERE session_id = $1 AND deleted_at IS NULL ORDER BY position DESC LIMIT 1",
        )
        .bind(session_id)
        .fetch_all(&mut *conn)
        .await?,
    };
    Ok(positions::between(keys.first().map(String::as_str), None))
}

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct BlockRevision {
    pub revision: i64,
    pub op: String,
    #[schema(value_type = Object)]
    pub snapshot: Value,
    pub device_id: Option<Uuid>,
    pub created_at: DateTime<Utc>,
}

#[utoipa::path(get, path = "/v1/blocks/{id}/history", tag = "blocks",
    params(("id" = Uuid, Path)), responses((status = 200, body = Vec<BlockRevision>)))]
pub async fn history(
    State(st): State<AppState>,
    caller: Caller,
    Path(block_id): Path<Uuid>,
) -> Result<Json<Vec<BlockRevision>>, ApiError> {
    let rows = sqlx::query(
        "SELECT r.revision, r.op, r.snapshot, r.device_id, r.created_at FROM block_revisions r \
         JOIN sessions s ON s.id = r.session_id \
         WHERE r.block_id = $1 AND s.user_id = $2 AND s.deleted_at IS NULL ORDER BY r.revision DESC LIMIT 200",
    )
    .bind(block_id)
    .bind(caller.user_id)
    .fetch_all(&st.notes)
    .await?;
    if rows.is_empty() {
        return Err(ApiError::not_found("block not found"));
    }
    Ok(Json(
        rows.into_iter()
            .map(|r| BlockRevision {
                revision: r.get("revision"),
                op: r.get("op"),
                snapshot: r.get("snapshot"),
                device_id: r.get("device_id"),
                created_at: r.get("created_at"),
            })
            .collect(),
    ))
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct RestoreRequest {
    pub revision: i64,
    pub device_id: Option<Uuid>,
}

#[utoipa::path(post, path = "/v1/blocks/{id}/restore", tag = "blocks",
    params(("id" = Uuid, Path)), request_body = RestoreRequest, responses((status = 200, body = Block)))]
pub async fn restore(
    State(st): State<AppState>,
    caller: Caller,
    Path(block_id): Path<Uuid>,
    Json(req): Json<RestoreRequest>,
) -> Result<Json<Block>, ApiError> {
    let mut tx = st.notes.begin().await?;
    let session_id: Option<Uuid> =
        sqlx::query_scalar("SELECT session_id FROM blocks WHERE id = $1")
            .bind(block_id)
            .fetch_optional(&mut *tx)
            .await?;
    let session_id = session_id.ok_or_else(|| ApiError::not_found("block not found"))?;
    access::writable_session(&mut tx, &caller, session_id).await?;
    revs::lock(&mut tx, session_id, revs::BLOCKS).await?;

    let snap: Option<Value> = sqlx::query_scalar(
        "SELECT snapshot FROM block_revisions WHERE block_id = $1 AND revision = $2",
    )
    .bind(block_id)
    .bind(req.revision)
    .fetch_optional(&mut *tx)
    .await?;
    let snap: Block = snap
        .and_then(|v| serde_json::from_value(v).ok())
        .ok_or_else(|| ApiError::not_found("revision not found"))?;

    let rev = revs::bump(&mut tx, session_id, revs::BLOCKS).await?;
    let block = sqlx::query_as::<_, Block>(&format!(
        "UPDATE blocks SET type = $2, text = $3, checked = $4, indent = $5, section_id = $6, position = $7, \
             audio_ts_ms = $8, transcript_anchor = $9, source_ref = $10, ai_sources = $11, topic_links = $12, \
             assignment_links = $13, study_studio_selected = $14, deleted_at = NULL, \
             revision = revision + 1, layer_rev = $15 WHERE id = $1 RETURNING {BLOCK_COLUMNS}"
    ))
    .bind(block_id)
    .bind(&snap.kind)
    .bind(&snap.text)
    .bind(snap.checked)
    .bind(snap.indent)
    .bind(snap.section_id)
    .bind(&snap.position)
    .bind(snap.audio_ts_ms)
    .bind(&snap.transcript_anchor)
    .bind(&snap.source_ref)
    .bind(&snap.ai_sources)
    .bind(&snap.topic_links)
    .bind(&snap.assignment_links)
    .bind(snap.study_studio_selected)
    .bind(rev)
    .fetch_one(&mut *tx)
    .await?;
    snapshot(&mut tx, &caller, &block, "restore", req.device_id).await?;
    tx.commit().await?;
    st.hub
        .session(
            session_id,
            Event::new(
                "block.changed",
                json!({ "blockIds": [block_id] }),
                Some(rev),
            ),
        )
        .await;
    Ok(Json(block))
}

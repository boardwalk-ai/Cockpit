//! Live Transcript (Panel 7). Three layers per segment: raw (ASR, never
//! overwritten) · faithful (post-class pass) · corrected (student). Every
//! student correction is kept in `transcript_revisions`.

use axum::extract::{Path, Query, State};
use axum::Json;
use chrono::{DateTime, Utc};
use octo_common::ApiError;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sqlx::{Postgres, QueryBuilder};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::ctx::Caller;
use crate::realtime::Event;
use crate::routes::blocks::{self, Block, NewServerBlock};
use crate::{access, revs, AppState};

const SPEAKERS: &[&str] = &["professor", "student", "speaker1", "unknown"];

#[derive(Debug, Clone, Serialize, sqlx::FromRow, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct Segment {
    pub id: Uuid,
    pub recording_id: Uuid,
    pub start_ms: i64,
    pub end_ms: i64,
    pub raw_text: String,
    pub faithful_text: Option<String>,
    pub corrected_text: Option<String>,
    /// corrected ?? faithful ?? raw
    pub display_text: String,
    pub speaker: String,
    pub speaker_original: String,
    pub speaker_conf: f32,
    pub asr_conf: f32,
    pub status: String,
    pub language: Option<String>,
    #[schema(value_type = Option<Object>)]
    pub slide_ref: Option<Value>,
    pub revision: i64,
    pub layer_rev: i64,
    pub updated_at: DateTime<Utc>,
    /// Marker types overlapping this segment.
    pub markers: Vec<String>,
    /// True when a note block links to it.
    pub linked: bool,
}

const SELECT: &str = "SELECT t.id, t.recording_id, t.start_ms, t.end_ms, t.raw_text, t.faithful_text, t.corrected_text, \
    COALESCE(t.corrected_text, t.faithful_text, t.raw_text) AS display_text, t.speaker, t.speaker_original, t.speaker_conf, \
    t.asr_conf, t.status, t.language, t.slide_ref, t.revision, t.layer_rev, t.updated_at, \
    COALESCE((SELECT array_agg(DISTINCT m.type) FROM markers m WHERE m.session_id = t.session_id \
              AND m.at_ms >= t.start_ms AND m.at_ms < t.end_ms), '{}') AS markers, \
    EXISTS (SELECT 1 FROM links l WHERE (l.to_kind = 'segment' AND l.to_id = t.id::text) \
            OR (l.from_kind = 'segment' AND l.from_id = t.id::text)) AS linked \
    FROM transcript_segments t";

#[derive(Debug, Deserialize, utoipa::IntoParams)]
#[serde(rename_all = "camelCase")]
pub struct TranscriptQuery {
    pub from_ms: Option<i64>,
    pub to_ms: Option<i64>,
    /// `professorOnly` | `questions` | `markers` | `corrections` | `linkedNotes` | `lowConfidence`
    pub filter: Option<String>,
    pub q: Option<String>,
    pub since_rev: Option<i64>,
    /// Start after this `startMs` (paging forward).
    pub after_ms: Option<i64>,
    pub limit: Option<i64>,
}

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct TranscriptPage {
    pub rev: i64,
    pub segments: Vec<Segment>,
    /// Pass as `afterMs` for the next page; null at the end.
    pub next_after_ms: Option<i64>,
}

#[utoipa::path(get, path = "/v1/sessions/{id}/transcript", tag = "transcript", params(("id" = Uuid, Path), TranscriptQuery),
    responses((status = 200, body = TranscriptPage)))]
pub async fn list(State(st): State<AppState>, caller: Caller, Path(session_id): Path<Uuid>, Query(q): Query<TranscriptQuery>) -> Result<Json<TranscriptPage>, ApiError> {
    let mut conn = st.notes.acquire().await?;
    access::session(&mut conn, &caller, session_id).await?;
    let rev = revs::current(&mut conn, session_id, revs::TRANSCRIPT).await?;
    let limit = q.limit.unwrap_or(200).clamp(1, 1000);
    let mut qb: QueryBuilder<Postgres> = QueryBuilder::new(SELECT);
    qb.push(" WHERE t.session_id = ").push_bind(session_id);
    if let Some(v) = q.from_ms {
        qb.push(" AND t.end_ms > ").push_bind(v);
    }
    if let Some(v) = q.to_ms {
        qb.push(" AND t.start_ms < ").push_bind(v);
    }
    if let Some(v) = q.after_ms {
        qb.push(" AND t.start_ms > ").push_bind(v);
    }
    if let Some(v) = q.since_rev {
        qb.push(" AND t.layer_rev > ").push_bind(v);
    }
    if let Some(text) = q.q.as_deref().map(str::trim).filter(|t| !t.is_empty()) {
        qb.push(" AND COALESCE(t.corrected_text, t.faithful_text, t.raw_text) ILIKE ").push_bind(format!("%{}%", text.replace('%', "\\%")));
    }
    match q.filter.as_deref() {
        None | Some("all") => {}
        Some("professorOnly") => {
            qb.push(" AND t.speaker = 'professor'");
        }
        Some("questions") => {
            qb.push(" AND (COALESCE(t.corrected_text, t.faithful_text, t.raw_text) LIKE '%?%' OR EXISTS (SELECT 1 FROM markers m WHERE m.session_id = t.session_id AND m.type = 'question' AND m.at_ms >= t.start_ms AND m.at_ms < t.end_ms))");
        }
        Some("markers") => {
            qb.push(" AND EXISTS (SELECT 1 FROM markers m WHERE m.session_id = t.session_id AND m.at_ms >= t.start_ms AND m.at_ms < t.end_ms)");
        }
        Some("corrections") => {
            qb.push(" AND (t.corrected_text IS NOT NULL OR t.speaker <> t.speaker_original)");
        }
        Some("linkedNotes") => {
            qb.push(" AND EXISTS (SELECT 1 FROM links l WHERE (l.to_kind = 'segment' AND l.to_id = t.id::text) OR (l.from_kind = 'segment' AND l.from_id = t.id::text))");
        }
        Some("lowConfidence") => {
            qb.push(" AND (t.asr_conf < 0.6 OR (t.speaker <> 'unknown' AND t.speaker_conf < 0.6))");
        }
        Some(other) => return Err(ApiError::bad_request(format!("unknown filter '{other}'"))),
    }
    qb.push(" ORDER BY t.start_ms, t.ordinal LIMIT ").push_bind(limit + 1);
    let mut segments: Vec<Segment> = qb.build_query_as().fetch_all(&mut *conn).await?;
    let next_after_ms = if segments.len() as i64 > limit {
        segments.truncate(limit as usize);
        segments.last().map(|s| s.start_ms)
    } else {
        None
    };
    Ok(Json(TranscriptPage { rev, segments, next_after_ms }))
}

async fn owned_segment(conn: &mut sqlx::PgConnection, caller: &Caller, id: Uuid) -> Result<(Uuid, Option<String>, String, String), ApiError> {
    let row: Option<(Uuid, Option<String>, String, String)> = sqlx::query_as(
        "SELECT t.session_id, t.corrected_text, t.speaker, t.speaker_original FROM transcript_segments t \
         JOIN sessions s ON s.id = t.session_id WHERE t.id = $1 AND s.user_id = $2 AND s.deleted_at IS NULL FOR UPDATE OF t",
    )
    .bind(id)
    .bind(caller.user_id)
    .fetch_optional(conn)
    .await?;
    row.ok_or_else(|| ApiError::not_found("segment not found"))
}

async fn one(conn: &mut sqlx::PgConnection, id: Uuid) -> Result<Segment, ApiError> {
    Ok(sqlx::query_as::<_, Segment>(&format!("{SELECT} WHERE t.id = $1")).bind(id).fetch_one(conn).await?)
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct Correction {
    pub corrected_text: Option<String>,
    pub speaker: Option<String>,
}

#[utoipa::path(patch, path = "/v1/transcript/segments/{id}", tag = "transcript", params(("id" = Uuid, Path)),
    request_body = Correction, responses((status = 200, body = Segment)))]
pub async fn correct(State(st): State<AppState>, caller: Caller, Path(id): Path<Uuid>, Json(req): Json<Correction>) -> Result<Json<Segment>, ApiError> {
    if let Some(s) = &req.speaker {
        if !SPEAKERS.contains(&s.as_str()) {
            return Err(ApiError::bad_request("speaker must be professor, student, speaker1 or unknown"));
        }
    }
    if req.corrected_text.as_ref().is_some_and(|t| t.trim().is_empty() || t.len() > 20_000) {
        return Err(ApiError::bad_request("correctedText must be 1..20000 chars"));
    }
    let mut tx = st.notes.begin().await?;
    let (session_id, old_text, old_speaker, _) = owned_segment(&mut tx, &caller, id).await?;
    revs::lock(&mut tx, session_id, revs::TRANSCRIPT).await?;
    let rev = revs::bump(&mut tx, session_id, revs::TRANSCRIPT).await?;
    if let Some(text) = &req.corrected_text {
        sqlx::query("INSERT INTO transcript_revisions (segment_id, field, old_value, new_value, corrected_by) VALUES ($1,'text',$2,$3,$4)")
            .bind(id)
            .bind(&old_text)
            .bind(text)
            .bind(caller.user_id)
            .execute(&mut *tx)
            .await?;
    }
    if let Some(sp) = &req.speaker {
        sqlx::query("INSERT INTO transcript_revisions (segment_id, field, old_value, new_value, corrected_by) VALUES ($1,'speaker',$2,$3,$4)")
            .bind(id)
            .bind(&old_speaker)
            .bind(sp)
            .bind(caller.user_id)
            .execute(&mut *tx)
            .await?;
    }
    sqlx::query(
        "UPDATE transcript_segments SET corrected_text = COALESCE($2, corrected_text), speaker = COALESCE($3, speaker), \
             speaker_conf = CASE WHEN $3::text IS NULL THEN speaker_conf ELSE 1 END, revision = revision + 1, layer_rev = $4 WHERE id = $1",
    )
    .bind(id)
    .bind(req.corrected_text.as_deref().map(str::trim))
    .bind(&req.speaker)
    .bind(rev)
    .execute(&mut *tx)
    .await?;
    let seg = one(&mut tx, id).await?;
    tx.commit().await?;
    st.hub.session(session_id, Event::new("transcript.corrected", json!({ "segmentIds": [id] }), Some(rev))).await;
    Ok(Json(seg))
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct RestoreSegment {
    /// `text` (drop the correction), `speaker` (back to the detected one), or both when omitted.
    pub field: Option<String>,
}

#[utoipa::path(post, path = "/v1/transcript/segments/{id}/restore", tag = "transcript", params(("id" = Uuid, Path)),
    request_body = RestoreSegment, responses((status = 200, body = Segment)))]
pub async fn restore(State(st): State<AppState>, caller: Caller, Path(id): Path<Uuid>, Json(req): Json<RestoreSegment>) -> Result<Json<Segment>, ApiError> {
    let field = req.field.unwrap_or_else(|| "both".into());
    if !["text", "speaker", "both"].contains(&field.as_str()) {
        return Err(ApiError::bad_request("field must be text or speaker"));
    }
    let mut tx = st.notes.begin().await?;
    let (session_id, old_text, old_speaker, original) = owned_segment(&mut tx, &caller, id).await?;
    revs::lock(&mut tx, session_id, revs::TRANSCRIPT).await?;
    let rev = revs::bump(&mut tx, session_id, revs::TRANSCRIPT).await?;
    if field != "speaker" && old_text.is_some() {
        sqlx::query("INSERT INTO transcript_revisions (segment_id, field, old_value, new_value, corrected_by) VALUES ($1,'text',$2,NULL,$3)")
            .bind(id)
            .bind(&old_text)
            .bind(caller.user_id)
            .execute(&mut *tx)
            .await?;
        sqlx::query("UPDATE transcript_segments SET corrected_text = NULL WHERE id = $1").bind(id).execute(&mut *tx).await?;
    }
    if field != "text" && old_speaker != original {
        sqlx::query("INSERT INTO transcript_revisions (segment_id, field, old_value, new_value, corrected_by) VALUES ($1,'speaker',$2,$3,$4)")
            .bind(id)
            .bind(&old_speaker)
            .bind(&original)
            .bind(caller.user_id)
            .execute(&mut *tx)
            .await?;
        sqlx::query("UPDATE transcript_segments SET speaker = speaker_original WHERE id = $1").bind(id).execute(&mut *tx).await?;
    }
    sqlx::query("UPDATE transcript_segments SET revision = revision + 1, layer_rev = $2 WHERE id = $1")
        .bind(id)
        .bind(rev)
        .execute(&mut *tx)
        .await?;
    let seg = one(&mut tx, id).await?;
    tx.commit().await?;
    st.hub.session(session_id, Event::new("transcript.corrected", json!({ "segmentIds": [id] }), Some(rev))).await;
    Ok(Json(seg))
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct TranscriptionToggle {
    pub on: bool,
}

#[utoipa::path(post, path = "/v1/sessions/{id}/transcription", tag = "transcript", params(("id" = Uuid, Path)),
    request_body = TranscriptionToggle, responses((status = 200)))]
pub async fn toggle(State(st): State<AppState>, caller: Caller, Path(session_id): Path<Uuid>, Json(req): Json<TranscriptionToggle>) -> Result<Json<Value>, ApiError> {
    let mut conn = st.notes.acquire().await?;
    access::writable_session(&mut conn, &caller, session_id).await?;
    sqlx::query("UPDATE sessions SET config = jsonb_set(config, '{liveTranscription}', to_jsonb($2::boolean)) WHERE id = $1")
        .bind(session_id)
        .bind(req.on)
        .execute(&mut *conn)
        .await?;
    st.hub.session(session_id, Event::new("transcription.state", json!({ "on": req.on }), None)).await;
    Ok(Json(json!({ "liveTranscription": req.on })))
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct FromSource {
    /// `transcript` | `slide` | `ink`
    pub kind: String,
    /// Segment id, `"{materialId}:{page}"` for slides, or ink recognition id.
    pub source_id: String,
    /// Insert right after this block (end of the note when omitted).
    pub after_block_id: Option<Uuid>,
}

#[utoipa::path(post, path = "/v1/sessions/{id}/blocks/from-source", tag = "blocks", params(("id" = Uuid, Path)),
    request_body = FromSource, responses((status = 201, body = Block)))]
pub async fn from_source(State(st): State<AppState>, caller: Caller, Path(session_id): Path<Uuid>, Json(req): Json<FromSource>) -> Result<(axum::http::StatusCode, Json<Block>), ApiError> {
    let mut tx = st.notes.begin().await?;
    access::writable_session(&mut tx, &caller, session_id).await?;
    let (block, link_kind, link_id) = match req.kind.as_str() {
        "transcript" => {
            let seg_id = Uuid::parse_str(&req.source_id).map_err(|_| ApiError::bad_request("sourceId must be a segment id"))?;
            let seg = one(&mut tx, seg_id).await.map_err(|_| ApiError::not_found("segment not found"))?;
            let session_of: Uuid = sqlx::query_scalar("SELECT session_id FROM transcript_segments WHERE id = $1").bind(seg_id).fetch_one(&mut *tx).await?;
            if session_of != session_id {
                return Err(ApiError::not_found("segment not found"));
            }
            let time = format_ms(seg.start_ms);
            let block = blocks::insert_server_block(&mut tx, &caller, NewServerBlock {
                session_id,
                after: req.after_block_id,
                kind: "transcriptExcerpt".into(),
                text: seg.display_text.clone(),
                origin: "fromTranscript".into(),
                audio_ts_ms: Some(seg.start_ms),
                transcript_anchor: Some(json!({ "segmentId": seg.id, "time": time, "speaker": seg.speaker, "excerpt": seg.display_text })),
                source_ref: Some(json!({ "material": "Transcript", "location": format!("{} · {time}", title_case(&seg.speaker)) })),
                ai_sources: None,
            })
            .await?;
            (block, "segment", seg_id.to_string())
        }
        // FROM-SOURCE-PHASE3
        other => return Err(ApiError::bad_request(format!("unknown source kind '{other}'"))),
    };
    sqlx::query("INSERT INTO links (session_id, user_id, from_kind, from_id, to_kind, to_id) VALUES ($1,$2,'block',$3,$4,$5) ON CONFLICT DO NOTHING")
        .bind(session_id)
        .bind(caller.user_id)
        .bind(block.id.to_string())
        .bind(link_kind)
        .bind(&link_id)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;
    st.hub
        .session(session_id, Event::new("block.changed", json!({ "blockIds": [block.id] }), Some(block.layer_rev)))
        .await;
    Ok((axum::http::StatusCode::CREATED, Json(block)))
}

pub fn format_ms(ms: i64) -> String {
    let s = ms / 1000;
    if s >= 3600 {
        format!("{}:{:02}:{:02}", s / 3600, (s / 60) % 60, s % 60)
    } else {
        format!("{}:{:02}", s / 60, s % 60)
    }
}

fn title_case(s: &str) -> String {
    let mut c = s.chars();
    c.next().map(|f| f.to_uppercase().collect::<String>() + c.as_str()).unwrap_or_default()
}

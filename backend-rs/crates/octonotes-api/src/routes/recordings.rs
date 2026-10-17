//! Recording (Panels 3–4): the phone records locally and uploads ~10 s chunks
//! that can resume after a drop; the server joins them into one compressed file
//! (kept until the user deletes it) and transcribes them.

use axum::body::Bytes;
use axum::extract::{Path, Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::Json;
use chrono::{DateTime, Utc};
use octo_common::ApiError;
use serde::{Deserialize, Serialize};
use serde_json::json;
use sha2::{Digest, Sha256};
use sqlx::PgConnection;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::ctx::Caller;
use crate::jobs::{self, Job, JobResult};
use crate::realtime::Event;
use crate::routes::devices;
use crate::{access, AppState};

const MAX_CHUNK_BYTES: usize = 5 * 1024 * 1024;
const MARKER_TYPES: &[&str] = &[
    "important",
    "question",
    "confusing",
    "examHint",
    "slideChange",
];

#[derive(Debug, Clone, Serialize, sqlx::FromRow, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct Recording {
    pub id: Uuid,
    pub session_id: Uuid,
    pub device_id: Option<Uuid>,
    pub codec: String,
    pub container: String,
    pub sample_rate: i32,
    pub chunk_ms: i32,
    pub state: String,
    pub started_at: DateTime<Utc>,
    pub stopped_at: Option<DateTime<Utc>>,
    pub duration_ms: i64,
    pub audio_bytes: Option<i64>,
}

const COLUMNS: &str = "id, session_id, device_id, codec, container, sample_rate, chunk_ms, state, started_at, stopped_at, duration_ms, audio_bytes";

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct StartRecording {
    /// Client-generated so a retried start doesn't create two recordings.
    pub id: Option<Uuid>,
    pub device_id: Uuid,
    /// `ogg` (Opus, default), `webm`, `mp4`, `wav`.
    pub container: Option<String>,
    pub sample_rate: Option<i32>,
    pub chunk_ms: Option<i32>,
}

#[utoipa::path(post, path = "/v1/sessions/{id}/recordings", tag = "recording", params(("id" = Uuid, Path)),
    request_body = StartRecording, responses((status = 201, body = Recording)))]
pub async fn start(
    State(st): State<AppState>,
    caller: Caller,
    Path(session_id): Path<Uuid>,
    Json(req): Json<StartRecording>,
) -> Result<(StatusCode, Json<Recording>), ApiError> {
    let container = req.container.unwrap_or_else(|| "ogg".into());
    if !["ogg", "webm", "mp4", "wav"].contains(&container.as_str()) {
        return Err(ApiError::bad_request(
            "container must be ogg, webm, mp4 or wav",
        ));
    }
    let chunk_ms = req.chunk_ms.unwrap_or(10_000);
    if !(1_000..=60_000).contains(&chunk_ms) {
        return Err(ApiError::bad_request("chunkMs must be 1000..60000"));
    }
    let mut tx = st.notes.begin().await?;
    access::writable_session(&mut tx, &caller, session_id).await?;
    devices::ensure_owned(&mut tx, &caller, req.device_id).await?;
    let id = req.id.unwrap_or_else(Uuid::new_v4);
    let rec = sqlx::query_as::<_, Recording>(&format!(
        "INSERT INTO recordings (id, session_id, user_id, device_id, container, sample_rate, chunk_ms) \
         VALUES ($1,$2,$3,$4,$5,$6,$7) ON CONFLICT (id) DO NOTHING RETURNING {COLUMNS}"
    ))
    .bind(id)
    .bind(session_id)
    .bind(caller.user_id)
    .bind(req.device_id)
    .bind(&container)
    .bind(req.sample_rate.unwrap_or(48_000))
    .bind(chunk_ms)
    .fetch_optional(&mut *tx)
    .await?;
    let (status, rec) = match rec {
        Some(r) => (StatusCode::CREATED, r),
        None => (StatusCode::OK, owned(&mut tx, &caller, id).await?),
    };
    join_device(
        &mut tx,
        &caller,
        session_id,
        req.device_id,
        "recorder",
        true,
    )
    .await?;
    sqlx::query("UPDATE sessions SET status = 'live', started_at = COALESCE(started_at, now()) WHERE id = $1 AND status IN ('draft', 'paused', 'ended', 'live')")
        .bind(session_id)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;
    publish_state(&st, &rec).await;
    Ok((status, Json(rec)))
}

/// Adds/refreshes a device in a session with a role.
pub async fn join_device(
    conn: &mut PgConnection,
    caller: &Caller,
    session_id: Uuid,
    device_id: Uuid,
    role: &str,
    recording: bool,
) -> Result<(), ApiError> {
    // A session has at most two devices: one records (a phone, unless it's
    // alone), the other works the session.
    // shortcut: a device counts while recording or seen in the last 10 min; a closed tab frees its seat after that.
    let others: Vec<bool> = sqlx::query_scalar(
        "SELECT sd.is_recording FROM session_devices sd \
         WHERE sd.session_id = $1 AND sd.device_id <> $2 \
           AND (sd.is_recording OR sd.last_seen_at > now() - interval '10 minutes')",
    )
    .bind(session_id)
    .bind(device_id)
    .fetch_all(&mut *conn)
    .await?;
    if others.len() >= 2 {
        return Err(ApiError::new(StatusCode::CONFLICT, "This session already has two devices.").with_code("session_full"));
    }
    if recording && others.iter().any(|rec| *rec) {
        return Err(ApiError::new(StatusCode::CONFLICT, "Another device is already recording this session.")
            .with_code("has_recorder"));
    }
    if role == "recorder" && !others.is_empty() {
        let platform: Option<String> = sqlx::query_scalar("SELECT platform FROM devices WHERE id = $1")
            .bind(device_id)
            .fetch_optional(&mut *conn)
            .await?;
        if !matches!(platform.as_deref(), Some("android" | "ios")) {
            return Err(ApiError::new(StatusCode::CONFLICT, "With two devices, the phone records.")
                .with_code("recorder_not_phone"));
        }
    }
    sqlx::query(
        "INSERT INTO session_devices (session_id, device_id, user_id, role, is_recording, last_seen_at) VALUES ($1,$2,$3,$4,$5,now()) \
         ON CONFLICT (session_id, device_id) DO UPDATE SET role = EXCLUDED.role, \
             is_recording = EXCLUDED.is_recording OR session_devices.is_recording, last_seen_at = now()",
    )
    .bind(session_id)
    .bind(device_id)
    .bind(caller.user_id)
    .bind(role)
    .bind(recording)
    .execute(conn)
    .await?;
    Ok(())
}

pub async fn owned(
    conn: &mut PgConnection,
    caller: &Caller,
    id: Uuid,
) -> Result<Recording, ApiError> {
    sqlx::query_as::<_, Recording>(&format!(
        "SELECT r.{} FROM recordings r JOIN sessions s ON s.id = r.session_id \
         WHERE r.id = $1 AND r.user_id = $2 AND s.deleted_at IS NULL",
        COLUMNS.replace(", ", ", r.")
    ))
    .bind(id)
    .bind(caller.user_id)
    .fetch_optional(conn)
    .await?
    .ok_or_else(|| ApiError::not_found("recording not found"))
}

async fn publish_state(st: &AppState, rec: &Recording) {
    st.hub
        .session(rec.session_id, Event::new("recording.state", json!({ "recordingId": rec.id, "deviceId": rec.device_id, "state": rec.state, "durationMs": rec.duration_ms }), None))
        .await;
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct UpdateRecording {
    /// `recording` (resume) | `paused` | `stopped`
    pub state: String,
    pub duration_ms: Option<i64>,
}

#[utoipa::path(patch, path = "/v1/recordings/{id}", tag = "recording", params(("id" = Uuid, Path)),
    request_body = UpdateRecording, responses((status = 200, body = Recording)))]
pub async fn update(
    State(st): State<AppState>,
    caller: Caller,
    Path(id): Path<Uuid>,
    Json(req): Json<UpdateRecording>,
) -> Result<Json<Recording>, ApiError> {
    if !["recording", "paused", "stopped"].contains(&req.state.as_str()) {
        return Err(ApiError::bad_request(
            "state must be recording, paused or stopped",
        ));
    }
    let mut tx = st.notes.begin().await?;
    let cur = owned(&mut tx, &caller, id).await?;
    if matches!(cur.state.as_str(), "stopped" | "uploaded" | "assembled") && req.state != "stopped"
    {
        return Err(
            ApiError::new(StatusCode::CONFLICT, "recording already stopped")
                .with_code("recording_stopped"),
        );
    }
    let rec = sqlx::query_as::<_, Recording>(&format!(
        "UPDATE recordings SET state = CASE WHEN state IN ('uploaded', 'assembled') THEN state ELSE $2 END, \
             duration_ms = GREATEST(duration_ms, COALESCE($3, duration_ms)), \
             stopped_at = CASE WHEN $2 = 'stopped' THEN COALESCE(stopped_at, now()) ELSE stopped_at END \
         WHERE id = $1 RETURNING {COLUMNS}"
    ))
    .bind(id)
    .bind(&req.state)
    .bind(req.duration_ms)
    .fetch_one(&mut *tx)
    .await?;
    if let Some(device) = rec.device_id {
        sqlx::query(
            "UPDATE session_devices SET is_recording = $3 WHERE session_id = $1 AND device_id = $2",
        )
        .bind(rec.session_id)
        .bind(device)
        .bind(req.state == "recording")
        .execute(&mut *tx)
        .await?;
    }
    let session_status = match req.state.as_str() {
        "recording" => Some("live"),
        "paused" => Some("paused"),
        _ => None,
    };
    if let Some(s) = session_status {
        sqlx::query(
            "UPDATE sessions SET status = $2 WHERE id = $1 AND status IN ('live', 'paused')",
        )
        .bind(rec.session_id)
        .bind(s)
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;
    publish_state(&st, &rec).await;
    Ok(Json(rec))
}

#[derive(Debug, Deserialize, utoipa::IntoParams)]
#[serde(rename_all = "camelCase")]
pub struct ChunkQuery {
    /// Chunk start on the recording timeline.
    pub start_ms: i64,
    pub duration_ms: i32,
}

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ChunkAck {
    pub seq: i32,
    pub bytes: i32,
    pub sha256: String,
    /// False when this exact chunk was already stored (a retry).
    pub stored: bool,
}

#[utoipa::path(put, path = "/v1/recordings/{id}/chunks/{seq}", tag = "recording",
    params(("id" = Uuid, Path), ("seq" = i32, Path), ChunkQuery), request_body(content = Vec<u8>, content_type = "audio/ogg"),
    responses((status = 200, body = ChunkAck)))]
pub async fn put_chunk(
    State(st): State<AppState>,
    caller: Caller,
    Path((id, seq)): Path<(Uuid, i32)>,
    Query(q): Query<ChunkQuery>,
    headers: HeaderMap,
    body: Bytes,
) -> Result<Json<ChunkAck>, ApiError> {
    if !(0..=100_000).contains(&seq) {
        return Err(ApiError::bad_request("seq out of range"));
    }
    if body.is_empty() || body.len() > MAX_CHUNK_BYTES {
        return Err(ApiError::bad_request(format!(
            "chunk must be 1..{MAX_CHUNK_BYTES} bytes"
        )));
    }
    if q.start_ms < 0 || !(1..=120_000).contains(&q.duration_ms) {
        return Err(ApiError::bad_request("startMs/durationMs out of range"));
    }
    st.upload_rate.check(caller.user_id, 120)?;
    let sha = hex::encode(Sha256::digest(&body));
    if let Some(claimed) = headers.get("x-chunk-sha256").and_then(|v| v.to_str().ok()) {
        if !claimed.eq_ignore_ascii_case(&sha) {
            return Err(
                ApiError::bad_request("chunk corrupted in transit (sha256 mismatch)")
                    .with_code("checksum_mismatch"),
            );
        }
    }
    // Checks first, then release the connection while the audio goes to
    // object storage (slow), then one connection for the bookkeeping. Never
    // hold a connection while asking the pool for another.
    let rec = {
        let mut conn = st.notes.acquire().await?;
        let rec = owned(&mut conn, &caller, id).await?;
        if rec.state == "assembled" {
            return Err(
                ApiError::new(StatusCode::CONFLICT, "recording already completed")
                    .with_code("recording_completed"),
            );
        }
        if let Some(prev) = sqlx::query_scalar::<_, String>(
            "SELECT sha256 FROM audio_chunks WHERE recording_id = $1 AND seq = $2",
        )
        .bind(id)
        .bind(seq)
        .fetch_optional(&mut *conn)
        .await?
        {
            if prev == sha {
                return Ok(Json(ChunkAck {
                    seq,
                    bytes: body.len() as i32,
                    sha256: sha,
                    stored: false,
                }));
            }
            return Err(ApiError::new(
                StatusCode::CONFLICT,
                "a different chunk already has this seq",
            )
            .with_code("chunk_conflict"));
        }
        rec
    };
    let key = format!(
        "{}/{}/audio/{}/{:06}.{}",
        caller.user_id, rec.session_id, id, seq, rec.container
    );
    st.storage
        .put(&key, &body, &format!("audio/{}", rec.container))
        .await
        .map_err(|e| ApiError::unavailable(format!("storage: {e}")))?;
    let mut tx = st.notes.begin().await?;
    let inserted = sqlx::query(
        "INSERT INTO audio_chunks (recording_id, seq, object_key, bytes, start_ms, duration_ms, sha256)          VALUES ($1,$2,$3,$4,$5,$6,$7) ON CONFLICT DO NOTHING",
    )
    .bind(id)
    .bind(seq)
    .bind(&key)
    .bind(body.len() as i32)
    .bind(q.start_ms)
    .bind(q.duration_ms)
    .bind(&sha)
    .execute(&mut *tx)
    .await?;
    if inserted.rows_affected() == 0 {
        // A concurrent retry of the same chunk won the race.
        return Ok(Json(ChunkAck {
            seq,
            bytes: body.len() as i32,
            sha256: sha,
            stored: false,
        }));
    }
    sqlx::query("UPDATE recordings SET duration_ms = GREATEST(duration_ms, $2) WHERE id = $1")
        .bind(id)
        .bind(q.start_ms + q.duration_ms as i64)
        .execute(&mut *tx)
        .await?;
    if st.config.server_asr {
        jobs::enqueue_tx(
            &mut tx,
            Some(caller.user_id),
            "asr.chunk",
            json!({ "recordingId": id, "seq": seq, "sessionId": rec.session_id }),
            Some(&format!("asr:{id}:{seq}")),
        )
        .await?;
    }
    tx.commit().await?;
    st.hub
        .session(
            rec.session_id,
            Event::new(
                "job.progress",
                json!({ "kind": "audio.uploaded", "recordingId": id, "seq": seq }),
                None,
            ),
        )
        .await;
    Ok(Json(ChunkAck {
        seq,
        bytes: body.len() as i32,
        sha256: sha,
        stored: true,
    }))
}

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct Manifest {
    pub recording_id: Uuid,
    pub state: String,
    /// Chunks the server has: `[seq, bytes, sha256]`.
    #[schema(value_type = Vec<Object>)]
    pub chunks: Vec<serde_json::Value>,
    /// Gaps below the highest received seq — upload these.
    pub missing: Vec<i32>,
    pub last_seq: Option<i32>,
}

#[utoipa::path(get, path = "/v1/recordings/{id}/manifest", tag = "recording", params(("id" = Uuid, Path)),
    responses((status = 200, body = Manifest)))]
pub async fn manifest(
    State(st): State<AppState>,
    caller: Caller,
    Path(id): Path<Uuid>,
) -> Result<Json<Manifest>, ApiError> {
    let mut conn = st.notes.acquire().await?;
    let rec = owned(&mut conn, &caller, id).await?;
    let rows: Vec<(i32, i32, String)> = sqlx::query_as(
        "SELECT seq, bytes, sha256 FROM audio_chunks WHERE recording_id = $1 ORDER BY seq",
    )
    .bind(id)
    .fetch_all(&mut *conn)
    .await?;
    Ok(Json(manifest_of(rec, &rows)))
}

fn manifest_of(rec: Recording, rows: &[(i32, i32, String)]) -> Manifest {
    let last = rows.last().map(|r| r.0);
    let have: std::collections::HashSet<i32> = rows.iter().map(|r| r.0).collect();
    let missing = (0..=last.unwrap_or(-1))
        .filter(|s| !have.contains(s))
        .collect();
    Manifest {
        recording_id: rec.id,
        state: rec.state,
        chunks: rows
            .iter()
            .map(|(s, b, h)| json!({ "seq": s, "bytes": b, "sha256": h }))
            .collect(),
        missing,
        last_seq: last,
    }
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct CompleteRecording {
    /// The last chunk seq the device recorded; the server refuses to complete
    /// while any chunk up to it is missing.
    pub last_seq: i32,
    pub duration_ms: Option<i64>,
}

#[utoipa::path(post, path = "/v1/recordings/{id}/complete", tag = "recording", params(("id" = Uuid, Path)),
    request_body = CompleteRecording, responses((status = 202, body = Recording), (status = 409, description = "chunks missing")))]
pub async fn complete(
    State(st): State<AppState>,
    caller: Caller,
    Path(id): Path<Uuid>,
    Json(req): Json<CompleteRecording>,
) -> Result<(StatusCode, Json<Recording>), ApiError> {
    let mut tx = st.notes.begin().await?;
    let rec = owned(&mut tx, &caller, id).await?;
    let have: Vec<i32> = sqlx::query_scalar(
        "SELECT seq FROM audio_chunks WHERE recording_id = $1 AND seq <= $2 ORDER BY seq",
    )
    .bind(id)
    .bind(req.last_seq)
    .fetch_all(&mut *tx)
    .await?;
    let missing: Vec<i32> = (0..=req.last_seq).filter(|s| !have.contains(s)).collect();
    if !missing.is_empty() {
        return Err(
            ApiError::new(StatusCode::CONFLICT, format!("chunks missing: {missing:?}"))
                .with_code("chunks_missing"),
        );
    }
    let rec = if rec.state == "assembled" {
        rec
    } else {
        sqlx::query_as::<_, Recording>(&format!(
            "UPDATE recordings SET state = 'uploaded', stopped_at = COALESCE(stopped_at, now()), \
                 duration_ms = GREATEST(duration_ms, COALESCE($2, duration_ms)) WHERE id = $1 RETURNING {COLUMNS}"
        ))
        .bind(id)
        .bind(req.duration_ms)
        .fetch_one(&mut *tx)
        .await?
    };
    if let Some(device) = rec.device_id {
        sqlx::query("UPDATE session_devices SET is_recording = false WHERE session_id = $1 AND device_id = $2")
            .bind(rec.session_id)
            .bind(device)
            .execute(&mut *tx)
            .await?;
    }
    jobs::enqueue_tx(
        &mut tx,
        Some(caller.user_id),
        "recording.assemble",
        json!({ "recordingId": id, "sessionId": rec.session_id }),
        Some(&format!("assemble:{id}")),
    )
    .await?;
    tx.commit().await?;
    publish_state(&st, &rec).await;
    Ok((StatusCode::ACCEPTED, Json(rec)))
}

/// Joins the chunks into one compressed file (Opus 24 kbps mono via ffmpeg
/// when available; otherwise the chunks are concatenated as-is), stores it,
/// then queues the faithful transcription pass.
pub async fn job_assemble(st: AppState, job: Job) -> JobResult {
    let id: Uuid =
        serde_json::from_value(job.payload["recordingId"].clone()).map_err(|e| e.to_string())?;
    let rec: Option<(Uuid, Uuid, String, Option<String>)> = sqlx::query_as(
        "SELECT session_id, user_id, container, audio_key FROM recordings WHERE id = $1",
    )
    .bind(id)
    .fetch_optional(&st.notes)
    .await
    .map_err(|e| e.to_string())?;
    let Some((session_id, user_id, container, existing)) = rec else {
        return Ok(());
    };
    if existing.is_some() {
        return Ok(());
    }
    let keys: Vec<String> = sqlx::query_scalar(
        "SELECT object_key FROM audio_chunks WHERE recording_id = $1 ORDER BY seq",
    )
    .bind(id)
    .fetch_all(&st.notes)
    .await
    .map_err(|e| e.to_string())?;
    let mut parts = Vec::with_capacity(keys.len());
    for k in &keys {
        parts.push(st.storage.get(k).await?);
    }
    let (bytes, ext) = match compress(&parts, &container).await {
        Some(ogg) => (ogg, "ogg".to_string()),
        None => (parts.concat(), container),
    };
    let key = format!("{user_id}/{session_id}/audio/{id}/recording.{ext}");
    st.storage
        .put(&key, &bytes, &format!("audio/{ext}"))
        .await?;
    sqlx::query(
        "UPDATE recordings SET audio_key = $2, audio_bytes = $3, state = 'assembled' WHERE id = $1",
    )
    .bind(id)
    .bind(&key)
    .bind(bytes.len() as i64)
    .execute(&st.notes)
    .await
    .map_err(|e| e.to_string())?;
    if st.config.server_asr {
        jobs::enqueue(
            &st.notes,
            Some(user_id),
            "transcript.faithful",
            json!({ "recordingId": id, "sessionId": session_id }),
            Some(&format!("faithful:{id}")),
        )
        .await
        .map_err(|e| e.to_string())?;
    }
    st.hub
        .session(
            session_id,
            Event::new(
                "recording.state",
                json!({ "recordingId": id, "state": "assembled" }),
                None,
            ),
        )
        .await;
    Ok(())
}

/// Re-encodes the chunks into one Opus/Ogg file at 24 kbps mono. `None` when
/// ffmpeg isn't installed or can't decode the input.
async fn compress(parts: &[Vec<u8>], container: &str) -> Option<Vec<u8>> {
    let dir = std::env::temp_dir().join(format!("octonotes-assemble-{}", Uuid::new_v4()));
    tokio::fs::create_dir_all(&dir).await.ok()?;
    let mut list = String::new();
    for (i, p) in parts.iter().enumerate() {
        let f = dir.join(format!("{i:06}.{container}"));
        tokio::fs::write(&f, p).await.ok()?;
        list.push_str(&format!(
            "file '{}'\n",
            f.to_string_lossy().replace('\\', "/")
        ));
    }
    let list_path = dir.join("list.txt");
    tokio::fs::write(&list_path, list).await.ok()?;
    let out = dir.join("out.ogg");
    let status = tokio::process::Command::new("ffmpeg")
        .args([
            "-y",
            "-loglevel",
            "error",
            "-f",
            "concat",
            "-safe",
            "0",
            "-i",
        ])
        .arg(&list_path)
        .args(["-ac", "1", "-c:a", "libopus", "-b:a", "24k"])
        .arg(&out)
        .status()
        .await
        .ok()?;
    let result = if status.success() {
        tokio::fs::read(&out).await.ok()
    } else {
        None
    };
    let _ = tokio::fs::remove_dir_all(&dir).await;
    result
}

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct AudioLink {
    pub url: String,
    pub expires_in: u32,
    pub bytes: Option<i64>,
}

#[utoipa::path(get, path = "/v1/recordings/{id}/audio", tag = "recording", params(("id" = Uuid, Path)),
    responses((status = 200, body = AudioLink), (status = 409, description = "not assembled yet")))]
pub async fn audio(
    State(st): State<AppState>,
    caller: Caller,
    Path(id): Path<Uuid>,
) -> Result<Json<AudioLink>, ApiError> {
    let mut conn = st.notes.acquire().await?;
    owned(&mut conn, &caller, id).await?;
    let key: Option<String> = sqlx::query_scalar("SELECT audio_key FROM recordings WHERE id = $1")
        .bind(id)
        .fetch_one(&mut *conn)
        .await?;
    let key = key.ok_or_else(|| {
        ApiError::new(StatusCode::CONFLICT, "audio is still being prepared")
            .with_code("audio_not_ready")
    })?;
    let bytes: Option<i64> = sqlx::query_scalar("SELECT audio_bytes FROM recordings WHERE id = $1")
        .bind(id)
        .fetch_one(&mut *conn)
        .await?;
    let url = st
        .storage
        .url(&key, 900)
        .await
        .map_err(ApiError::unavailable)?;
    Ok(Json(AudioLink {
        url,
        expires_in: 900,
        bytes,
    }))
}

#[utoipa::path(get, path = "/v1/sessions/{id}/recordings", tag = "recording", params(("id" = Uuid, Path)),
    responses((status = 200, body = Vec<Recording>)))]
pub async fn list(
    State(st): State<AppState>,
    caller: Caller,
    Path(session_id): Path<Uuid>,
) -> Result<Json<Vec<Recording>>, ApiError> {
    let mut conn = st.notes.acquire().await?;
    access::session(&mut conn, &caller, session_id).await?;
    let rows = sqlx::query_as::<_, Recording>(&format!(
        "SELECT {COLUMNS} FROM recordings WHERE session_id = $1 ORDER BY started_at"
    ))
    .bind(session_id)
    .fetch_all(&mut *conn)
    .await?;
    Ok(Json(rows))
}

#[derive(Debug, Serialize, Deserialize, sqlx::FromRow, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct Marker {
    pub id: Uuid,
    #[serde(rename = "type")]
    #[sqlx(rename = "type")]
    pub kind: String,
    pub at_ms: i64,
    pub device_id: Option<Uuid>,
    pub note: Option<String>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct NewMarker {
    pub id: Option<Uuid>,
    #[serde(rename = "type")]
    pub kind: String,
    pub at_ms: i64,
    pub device_id: Option<Uuid>,
    pub note: Option<String>,
}

#[utoipa::path(post, path = "/v1/sessions/{id}/markers", tag = "recording", params(("id" = Uuid, Path)),
    request_body = NewMarker, responses((status = 201, body = Marker)))]
pub async fn add_marker(
    State(st): State<AppState>,
    caller: Caller,
    Path(session_id): Path<Uuid>,
    Json(req): Json<NewMarker>,
) -> Result<(StatusCode, Json<Marker>), ApiError> {
    if !MARKER_TYPES.contains(&req.kind.as_str()) {
        return Err(ApiError::bad_request("unknown marker type"));
    }
    if req.at_ms < 0 || req.note.as_ref().is_some_and(|n| n.chars().count() > 500) {
        return Err(ApiError::bad_request(
            "atMs must be >= 0 and note <= 500 chars",
        ));
    }
    let mut conn = st.notes.acquire().await?;
    access::writable_session(&mut conn, &caller, session_id).await?;
    let id = req.id.unwrap_or_else(Uuid::new_v4);
    sqlx::query(
        "INSERT INTO markers (id, session_id, user_id, type, at_ms, device_id, note) VALUES ($1,$2,$3,$4,$5,$6,$7) ON CONFLICT (id) DO NOTHING",
    )
    .bind(id)
    .bind(session_id)
    .bind(caller.user_id)
    .bind(&req.kind)
    .bind(req.at_ms)
    .bind(req.device_id)
    .bind(&req.note)
    .execute(&mut *conn)
    .await?;
    let m = sqlx::query_as::<_, Marker>("SELECT id, type, at_ms, device_id, note, created_at FROM markers WHERE id = $1 AND session_id = $2")
        .bind(id)
        .bind(session_id)
        .fetch_optional(&mut *conn)
        .await?
        .ok_or_else(|| ApiError::bad_request("marker id already in use"))?;
    st.hub
        .session(
            session_id,
            Event::new(
                "marker.added",
                serde_json::to_value(&m).unwrap_or_default(),
                None,
            ),
        )
        .await;
    Ok((StatusCode::CREATED, Json(m)))
}

#[utoipa::path(get, path = "/v1/sessions/{id}/markers", tag = "recording", params(("id" = Uuid, Path)),
    responses((status = 200, body = Vec<Marker>)))]
pub async fn list_markers(
    State(st): State<AppState>,
    caller: Caller,
    Path(session_id): Path<Uuid>,
) -> Result<Json<Vec<Marker>>, ApiError> {
    let mut conn = st.notes.acquire().await?;
    access::session(&mut conn, &caller, session_id).await?;
    let rows = sqlx::query_as::<_, Marker>("SELECT id, type, at_ms, device_id, note, created_at FROM markers WHERE session_id = $1 ORDER BY at_ms")
        .bind(session_id)
        .fetch_all(&mut *conn)
        .await?;
    Ok(Json(rows))
}

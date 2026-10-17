//! Realtime + device lifecycle (Panels 3, 12).
//!
//! `WS /v1/sessions/{id}/live` carries every live event for one session. The
//! first frame authenticates (browsers can't set headers on a WebSocket):
//! `{"type":"auth","token":"<firebase id token>","deviceId":"…"}` (dev: `"userId"`).
//! Events are hints — the database is the truth, so a reconnecting client
//! catches up with `?sinceRev=` and misses nothing.

use std::time::Duration;

use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::response::Response;
use axum::Json;
use octo_common::ApiError;
use serde::Deserialize;
use serde_json::{json, Value};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::ctx::Caller;
use crate::realtime::Event;
use crate::routes::devices;
use crate::routes::recordings::join_device;
use crate::routes::sessions::{self, Session};
use crate::{access, revs, AppState};

pub async fn ws(
    State(st): State<AppState>,
    Path(session_id): Path<Uuid>,
    upgrade: WebSocketUpgrade,
) -> Response {
    upgrade.on_upgrade(move |socket| async move {
        if let Err(e) = run(st, session_id, socket).await {
            tracing::debug!(error = %e, "live socket closed");
        }
    })
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct AuthFrame {
    #[serde(rename = "type")]
    kind: String,
    token: Option<String>,
    user_id: Option<String>,
    device_id: Option<Uuid>,
}

async fn authenticate(st: &AppState, frame: &AuthFrame) -> Result<Caller, ApiError> {
    let mut headers = axum::http::HeaderMap::new();
    if let Some(t) = &frame.token {
        headers.insert(
            "authorization",
            format!("Bearer {t}")
                .parse()
                .map_err(|_| ApiError::unauthorized("bad token"))?,
        );
    }
    if let Some(u) = &frame.user_id {
        headers.insert(
            "x-user-id",
            u.parse().map_err(|_| ApiError::unauthorized("bad user"))?,
        );
    }
    let (mut parts, _) = axum::http::Request::builder()
        .body(())
        .expect("req")
        .into_parts();
    parts.headers = headers;
    <Caller as axum::extract::FromRequestParts<AppState>>::from_request_parts(&mut parts, st).await
}

/// A caption a phone sends: `{segId, text, final, startMs, endMs}`, checked
/// before it's relayed (short id, at most 1000 chars, sane times).
fn caption(d: &Value) -> Option<(String, String, bool, i64, i64)> {
    let seg = d["segId"].as_str().filter(|s| !s.is_empty() && s.len() <= 64)?;
    let text: String = d["text"].as_str()?.chars().take(1000).collect();
    let start = d["startMs"].as_i64().filter(|v| *v >= 0)?;
    let end = d["endMs"].as_i64().filter(|v| *v >= start)?;
    Some((seg.to_string(), text, d["final"].as_bool().unwrap_or(false), start, end))
}

/// A finished caption as a transcript segment of the device's recording,
/// announced like the server's own (`transcript.stable`).
async fn keep_caption(
    st: &AppState,
    session_id: Uuid,
    user_id: Uuid,
    device: Uuid,
    c: &(String, String, bool, i64, i64),
) -> Result<(), sqlx::Error> {
    let mut tx = st.notes.begin().await?;
    let Some(rid) = sqlx::query_scalar::<_, Uuid>(
        "SELECT id FROM recordings WHERE session_id = $1 AND device_id = $2 ORDER BY started_at DESC LIMIT 1",
    )
    .bind(session_id)
    .bind(device)
    .fetch_optional(&mut *tx)
    .await?
    else {
        return Ok(()); // not recording here
    };
    revs::lock(&mut tx, session_id, revs::TRANSCRIPT).await?;
    let rev = revs::bump(&mut tx, session_id, revs::TRANSCRIPT).await?;
    // Captions sit at chunk_seq -1, numbered in arrival order.
    let id: Uuid = sqlx::query_scalar(
        "INSERT INTO transcript_segments (session_id, recording_id, user_id, chunk_seq, ordinal, start_ms, end_ms, \
             raw_text, asr_conf, status, language, layer_rev) \
         VALUES ($1, $2, $3, -1, (SELECT COALESCE(max(ordinal) + 1, 0) FROM transcript_segments WHERE recording_id = $2 AND chunk_seq = -1), \
                 $4, $5, $6, 0.7, 'stable', 'en', $7) RETURNING id",
    )
    .bind(session_id)
    .bind(rid)
    .bind(user_id)
    .bind(c.3)
    .bind(c.4.max(c.3 + 1))
    .bind(c.1.trim())
    .bind(rev)
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;
    st.hub
        .session(
            session_id,
            Event::new("transcript.stable", json!({ "segmentIds": [id], "recordingId": rid, "chunkSeq": -1 }), Some(rev)),
        )
        .await;
    Ok(())
}

#[cfg(test)]
mod caption_tests {
    use super::caption;
    use serde_json::json;

    #[test]
    fn captions_are_checked() {
        let ok = caption(&json!({ "segId": "a1", "text": "hello", "final": true, "startMs": 10, "endMs": 900 })).unwrap();
        assert_eq!((ok.1.as_str(), ok.2), ("hello", true));
        assert!(caption(&json!({ "segId": "", "text": "x", "startMs": 0, "endMs": 1 })).is_none());
        assert!(caption(&json!({ "segId": "a", "text": "x", "startMs": 5, "endMs": 1 })).is_none());
        let long = caption(&json!({ "segId": "a", "text": "y".repeat(5000), "startMs": 0, "endMs": 0 })).unwrap();
        assert_eq!(long.1.len(), 1000);
    }
}

async fn send(socket: &mut WebSocket, v: Value) -> Result<(), axum::Error> {
    socket.send(Message::Text(v.to_string())).await
}

async fn run(st: AppState, session_id: Uuid, mut socket: WebSocket) -> Result<(), String> {
    // 1. Auth frame within 10 s.
    let first = tokio::time::timeout(Duration::from_secs(10), socket.recv())
        .await
        .map_err(|_| "auth timeout")?;
    let Some(Ok(Message::Text(text))) = first else {
        return Err("expected auth frame".into());
    };
    let frame: AuthFrame = serde_json::from_str(&text).map_err(|_| "bad auth frame")?;
    if frame.kind != "auth" {
        let _ = send(
            &mut socket,
            json!({ "type": "error", "data": { "code": "auth_required" } }),
        )
        .await;
        return Err("first frame must be auth".into());
    }
    let caller = match authenticate(&st, &frame).await {
        Ok(c) => c,
        Err(e) => {
            let _ = send(&mut socket, json!({ "type": "error", "data": { "code": e.code.unwrap_or("unauthorized"), "message": e.message } })).await;
            return Err("auth failed".into());
        }
    };
    let mut conn = st.notes.acquire().await.map_err(|e| e.to_string())?;
    if access::session(&mut conn, &caller, session_id)
        .await
        .is_err()
    {
        let _ = send(
            &mut socket,
            json!({ "type": "error", "data": { "code": "not_found" } }),
        )
        .await;
        return Err("session not found".into());
    }
    let device = match frame.device_id {
        Some(d) if devices::ensure_owned(&mut conn, &caller, d).await.is_ok() => {
            sqlx::query(
                "INSERT INTO session_devices (session_id, device_id, user_id, role, last_seen_at) VALUES ($1,$2,$3,'editor',now()) \
                 ON CONFLICT (session_id, device_id) DO UPDATE SET last_seen_at = now()",
            )
            .bind(session_id)
            .bind(d)
            .bind(caller.user_id)
            .execute(&mut *conn)
            .await
            .map_err(|e| e.to_string())?;
            Some(d)
        }
        _ => None,
    };
    let revs: Value = sqlx::query_scalar("SELECT COALESCE(json_object_agg(layer, rev), '{}') FROM session_layer_revs WHERE session_id = $1")
        .bind(session_id)
        .fetch_one(&mut *conn)
        .await
        .map_err(|e| e.to_string())?;
    drop(conn);

    let mut session_rx = st.hub.subscribe(&format!("session:{session_id}"));
    let mut user_rx = st.hub.subscribe(&format!("user:{}", caller.user_id));
    send(
        &mut socket,
        json!({ "type": "ready", "data": { "sessionId": session_id, "revs": revs } }),
    )
    .await
    .map_err(|e| e.to_string())?;
    if let Some(d) = device {
        st.hub
            .session(
                session_id,
                Event::new(
                    "device.presence",
                    json!({ "deviceId": d, "online": true }),
                    None,
                ),
            )
            .await;
    }

    st.metrics
        .websockets
        .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    let mut heartbeat = tokio::time::interval(Duration::from_secs(30));
    let result = loop {
        tokio::select! {
            ev = session_rx.recv() => match ev {
                Ok(ev) => if send(&mut socket, serde_json::to_value(&ev).unwrap_or_default()).await.is_err() { break Ok(()) },
                // Too slow: tell the client to catch up from the DB.
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => {
                    if send(&mut socket, json!({ "type": "resync" })).await.is_err() { break Ok(()) }
                }
                Err(_) => break Ok(()),
            },
            ev = user_rx.recv() => if let Ok(ev) = ev {
                if send(&mut socket, serde_json::to_value(&ev).unwrap_or_default()).await.is_err() { break Ok(()) }
            },
            msg = socket.recv() => match msg {
                Some(Ok(Message::Text(t))) => {
                    let v: Value = serde_json::from_str(&t).unwrap_or_default();
                    match v["type"].as_str() {
                        Some("ping") => { let _ = send(&mut socket, json!({ "type": "pong" })).await; }
                        Some("presence") => if let Some(d) = device {
                            let _ = sqlx::query("UPDATE session_devices SET last_seen_at = now() WHERE session_id = $1 AND device_id = $2")
                                .bind(session_id).bind(d).execute(&st.notes).await;
                        },
                        // On-device captions from the recording phone, relayed as
                        // they are heard; the server's own transcript stays the record.
                        Some("caption") => if let Some(d) = device {
                            if let Some(c) = caption(&v["data"]) {
                                st.hub.session(session_id, Event::new("transcript.live", json!({ "deviceId": d, "segId": c.0, "text": c.1, "final": c.2, "startMs": c.3, "endMs": c.4 }), None)).await;
                                if c.2 && !st.config.server_asr && !c.1.trim().is_empty() {
                                    if let Err(e) = keep_caption(&st, session_id, caller.user_id, d, &c).await {
                                        tracing::warn!(error = %e, "caption not kept");
                                    }
                                }
                            }
                        },
                        Some("follow") => {
                            st.hub.session(session_id, Event::new("slide.follow", json!({ "deviceId": device, "following": v["data"]["following"] }), None)).await;
                        }
                        _ => {}
                    }
                }
                Some(Ok(Message::Close(_))) | None => break Ok(()),
                Some(Err(e)) => break Err(e.to_string()),
                _ => {}
            },
            _ = heartbeat.tick() => {
                if socket.send(Message::Ping(Vec::new())).await.is_err() { break Ok(()) }
            }
        }
    };
    st.metrics
        .websockets
        .fetch_sub(1, std::sync::atomic::Ordering::Relaxed);
    if let Some(d) = device {
        st.hub
            .session(
                session_id,
                Event::new(
                    "device.presence",
                    json!({ "deviceId": d, "online": false }),
                    None,
                ),
            )
            .await;
    }
    result
}

#[utoipa::path(get, path = "/v1/sessions/{id}/devices", tag = "devices", params(("id" = Uuid, Path)),
    responses((status = 200, description = "Devices in the session with role, recording flag and last seen")))]
pub async fn session_devices(
    State(st): State<AppState>,
    caller: Caller,
    Path(session_id): Path<Uuid>,
) -> Result<Json<Value>, ApiError> {
    let mut conn = st.notes.acquire().await?;
    access::session(&mut conn, &caller, session_id).await?;
    Ok(Json(devices_json(&mut conn, session_id).await?))
}

async fn devices_json(conn: &mut sqlx::PgConnection, session_id: Uuid) -> Result<Value, ApiError> {
    Ok(sqlx::query_scalar(
        "SELECT COALESCE(json_agg(json_build_object('deviceId', d.id, 'name', d.name, 'platform', d.platform, 'role', sd.role, \
             'isRecording', sd.is_recording, 'lastSeenAt', sd.last_seen_at, \
             'online', sd.last_seen_at > now() - interval '60 seconds') ORDER BY sd.joined_at), '[]') \
         FROM session_devices sd JOIN devices d ON d.id = sd.device_id WHERE sd.session_id = $1",
    )
    .bind(session_id)
    .fetch_one(conn)
    .await?)
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct JoinSession {
    pub device_id: Uuid,
    /// `recorder` | `editor` (default) | `viewer`
    pub role: Option<String>,
}

#[utoipa::path(post, path = "/v1/sessions/{id}/join", tag = "devices", params(("id" = Uuid, Path)),
    request_body = JoinSession, responses((status = 200)))]
pub async fn join(
    State(st): State<AppState>,
    caller: Caller,
    Path(session_id): Path<Uuid>,
    Json(req): Json<JoinSession>,
) -> Result<Json<Value>, ApiError> {
    let role = req.role.unwrap_or_else(|| "editor".into());
    if !["recorder", "editor", "viewer"].contains(&role.as_str()) {
        return Err(ApiError::bad_request(
            "role must be recorder, editor or viewer",
        ));
    }
    let mut conn = st.notes.acquire().await?;
    access::session(&mut conn, &caller, session_id).await?;
    devices::ensure_owned(&mut conn, &caller, req.device_id).await?;
    join_device(&mut conn, &caller, session_id, req.device_id, &role, false).await?;
    st.hub
        .session(
            session_id,
            Event::new(
                "device.presence",
                json!({ "deviceId": req.device_id, "online": true, "role": role }),
                None,
            ),
        )
        .await;
    Ok(Json(devices_json(&mut conn, session_id).await?))
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct SetRole {
    pub role: String,
}

#[utoipa::path(patch, path = "/v1/sessions/{id}/devices/{deviceId}", tag = "devices",
    params(("id" = Uuid, Path), ("deviceId" = Uuid, Path)), request_body = SetRole, responses((status = 200)))]
pub async fn set_role(
    State(st): State<AppState>,
    caller: Caller,
    Path((session_id, device_id)): Path<(Uuid, Uuid)>,
    Json(req): Json<SetRole>,
) -> Result<Json<Value>, ApiError> {
    if !["recorder", "editor", "viewer"].contains(&req.role.as_str()) {
        return Err(ApiError::bad_request(
            "role must be recorder, editor or viewer",
        ));
    }
    let mut conn = st.notes.acquire().await?;
    access::session(&mut conn, &caller, session_id).await?;
    let res = sqlx::query(
        "UPDATE session_devices SET role = $3 WHERE session_id = $1 AND device_id = $2",
    )
    .bind(session_id)
    .bind(device_id)
    .bind(&req.role)
    .execute(&mut *conn)
    .await?;
    if res.rows_affected() == 0 {
        return Err(ApiError::not_found("device not in this session"));
    }
    st.hub
        .session(
            session_id,
            Event::new(
                "device.presence",
                json!({ "deviceId": device_id, "role": req.role }),
                None,
            ),
        )
        .await;
    Ok(Json(devices_json(&mut conn, session_id).await?))
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct Leave {
    pub device_id: Option<Uuid>,
}

/// Leaving never stops another device's recording (closing the laptop must
/// not stop the phone).
#[utoipa::path(post, path = "/v1/sessions/{id}/leave", tag = "devices", params(("id" = Uuid, Path)),
    request_body = Leave, responses((status = 200)))]
pub async fn leave(
    State(st): State<AppState>,
    caller: Caller,
    Path(session_id): Path<Uuid>,
    Json(req): Json<Leave>,
) -> Result<Json<Value>, ApiError> {
    let mut conn = st.notes.acquire().await?;
    access::session(&mut conn, &caller, session_id).await?;
    let recording: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM session_devices WHERE session_id = $1 AND is_recording",
    )
    .bind(session_id)
    .fetch_one(&mut *conn)
    .await?;
    if let Some(d) = req.device_id {
        st.hub
            .session(
                session_id,
                Event::new(
                    "device.presence",
                    json!({ "deviceId": d, "online": false }),
                    None,
                ),
            )
            .await;
    }
    Ok(Json(json!({ "keepsRecording": recording > 0 })))
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct Finish {
    pub device_id: Option<Uuid>,
    /// Omit first: 409 `other_device_recording` if another device records.
    /// Then `finishAndStop` (stop everything) or `leaveKeepRecording`.
    pub mode: Option<String>,
}

#[utoipa::path(post, path = "/v1/sessions/{id}/finish", tag = "sessions", params(("id" = Uuid, Path)),
    request_body = Finish, responses((status = 200, body = Session), (status = 409, description = "another device is recording")))]
pub async fn finish(
    State(st): State<AppState>,
    caller: Caller,
    Path(session_id): Path<Uuid>,
    Json(req): Json<Finish>,
) -> Result<Json<Value>, ApiError> {
    let mut tx = st.notes.begin().await?;
    access::writable_session(&mut tx, &caller, session_id).await?;
    let others: Value = sqlx::query_scalar(
        "SELECT COALESCE(json_agg(json_build_object('deviceId', d.id, 'name', d.name, 'platform', d.platform)), '[]') \
         FROM session_devices sd JOIN devices d ON d.id = sd.device_id \
         WHERE sd.session_id = $1 AND sd.is_recording AND ($2::uuid IS NULL OR sd.device_id <> $2)",
    )
    .bind(session_id)
    .bind(req.device_id)
    .fetch_one(&mut *tx)
    .await?;
    let someone_else_records = others.as_array().is_some_and(|a| !a.is_empty());
    match req.mode.as_deref() {
        None if someone_else_records => {
            return Err(
                ApiError::new(StatusCode::CONFLICT, "another device is still recording")
                    .with_code("other_device_recording")
                    .with_details(json!({ "devices": others })),
            );
        }
        Some("leaveKeepRecording") => {
            tx.commit().await?;
            return Ok(Json(
                json!({ "finished": false, "keepsRecording": someone_else_records }),
            ));
        }
        None | Some("finishAndStop") => {}
        Some(other) => return Err(ApiError::bad_request(format!("unknown mode '{other}'"))),
    }
    // Stop every recording; devices then upload what's left and call /complete.
    let open: Value = sqlx::query_scalar(
        "WITH stopped AS (UPDATE recordings SET state = 'stopped', stopped_at = COALESCE(stopped_at, now()) \
                          WHERE session_id = $1 AND state IN ('recording', 'paused') RETURNING id, device_id) \
         SELECT COALESCE(json_agg(json_build_object('recordingId', id, 'deviceId', device_id)), '[]') FROM stopped",
    )
    .bind(session_id)
    .fetch_one(&mut *tx)
    .await?;
    sqlx::query("UPDATE session_devices SET is_recording = false WHERE session_id = $1")
        .bind(session_id)
        .execute(&mut *tx)
        .await?;
    sqlx::query(
        "UPDATE sessions SET status = 'ended', ended_at = now(), \
             duration_ms = GREATEST(duration_ms, COALESCE((SELECT max(duration_ms) FROM recordings WHERE session_id = $1), 0)) \
         WHERE id = $1 AND status NOT IN ('finalized', 'archived')",
    )
    .bind(session_id)
    .execute(&mut *tx)
    .await?;
    crate::outbox::record(
        &mut tx,
        caller.user_id,
        "session.finished",
        Some(session_id),
        json!({}),
    )
    .await?;
    let session = sessions::owned(&mut tx, &caller, session_id).await?;
    tx.commit().await?;
    for r in open.as_array().into_iter().flatten() {
        st.hub
            .session(
                session_id,
                Event::new(
                    "recording.state",
                    json!({ "recordingId": r["recordingId"], "state": "stopped" }),
                    None,
                ),
            )
            .await;
    }
    st.hub
        .session(
            session_id,
            Event::new("session.finished", json!({ "sessionId": session_id }), None),
        )
        .await;
    Ok(Json(
        json!({ "finished": true, "session": session, "stoppedRecordings": open }),
    ))
}

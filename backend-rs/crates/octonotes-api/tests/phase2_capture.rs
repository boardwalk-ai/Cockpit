//! Phase 2 — live capture: recording, chunk upload, transcription (offline
//! engine), corrections, markers, finish, WebSocket + Redis fan-out.

mod common;

use std::time::Duration;

use axum::http::{Method, StatusCode};
use common::TestApp;
use futures::{SinkExt, StreamExt};
use octonotes_api::{app, AppState};
use serde_json::{json, Value};
use tokio_tungstenite::tungstenite::Message;
use uuid::Uuid;

fn fake_ogg(seq: i32) -> Vec<u8> {
    let mut b = b"OggS".to_vec();
    b.extend(std::iter::repeat_n(seq as u8, 2000));
    b
}

async fn device(t: &TestApp, user: &str, name: &str) -> String {
    let id = Uuid::new_v4();
    let (s, v) = t.post("/v1/devices", user, json!({ "id": id, "name": name, "platform": "android" })).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    id.to_string()
}

async fn chunk(t: &TestApp, rid: &str, seq: i32) -> (StatusCode, Value) {
    t.put_bytes(&format!("/v1/recordings/{rid}/chunks/{seq}?startMs={}&durationMs=10000", seq as i64 * 10_000), "alice", fake_ogg(seq), "audio/ogg").await
}

#[tokio::test]
async fn recording_survives_gaps_and_retries_then_transcribes() {
    let t = TestApp::new().await;
    let sid = t.session("alice").await;
    let phone = device(&t, "alice", "Alice's Pixel").await;
    let rid = Uuid::new_v4().to_string();
    let (s, rec) = t.post(&format!("/v1/sessions/{sid}/recordings"), "alice", json!({ "id": rid, "deviceId": phone })).await;
    assert_eq!(s, StatusCode::CREATED, "{rec}");
    let (_, snap) = t.get(&format!("/v1/sessions/{sid}"), "alice").await;
    assert_eq!(snap["session"]["status"], "live");

    // Wi-Fi drops during chunk 3: 0,1,2,4 arrive.
    for seq in [0, 1, 2, 4] {
        let (s, v) = chunk(&t, &rid, seq).await;
        assert_eq!(s, StatusCode::OK, "{v}");
    }
    let (_, m) = t.get(&format!("/v1/recordings/{rid}/manifest"), "alice").await;
    assert_eq!(m["missing"], json!([3]));
    assert_eq!(m["lastSeq"], 4);

    // Retry of chunk 1 is a no-op; a different chunk 1 is refused.
    let (s, v) = chunk(&t, &rid, 1).await;
    assert_eq!((s, v["stored"].as_bool()), (StatusCode::OK, Some(false)));
    let (s, v) = t.put_bytes(&format!("/v1/recordings/{rid}/chunks/1?startMs=10000&durationMs=10000"), "alice", b"OggSdifferent".to_vec(), "audio/ogg").await;
    assert_eq!((s, v["code"].as_str()), (StatusCode::CONFLICT, Some("chunk_conflict")));
    // Corruption in transit is caught.
    let (s, _) = t.call_with(Method::PUT, &format!("/v1/recordings/{rid}/chunks/5?startMs=50000&durationMs=10000"), "alice", None, &[("x-chunk-sha256", "00")]).await;
    assert_eq!(s, StatusCode::BAD_REQUEST);

    // Can't complete with a gap.
    let (s, v) = t.post(&format!("/v1/recordings/{rid}/complete"), "alice", json!({ "lastSeq": 4 })).await;
    assert_eq!((s, v["code"].as_str()), (StatusCode::CONFLICT, Some("chunks_missing")));
    // Wi-Fi back: the phone uploads the gap, then completes.
    chunk(&t, &rid, 3).await;
    let (s, v) = t.post(&format!("/v1/recordings/{rid}/complete"), "alice", json!({ "lastSeq": 4, "durationMs": 50000 })).await;
    assert_eq!(s, StatusCode::ACCEPTED, "{v}");

    t.drain_jobs().await;

    // Live pass: one stable segment per chunk, in order, raw text kept.
    let (_, tr) = t.get(&format!("/v1/sessions/{sid}/transcript"), "alice").await;
    let segs = tr["segments"].as_array().unwrap();
    assert_eq!(segs.len(), 5, "{tr}");
    let starts: Vec<i64> = segs.iter().map(|s| s["startMs"].as_i64().unwrap()).collect();
    assert_eq!(starts, vec![0, 10_000, 20_000, 30_000, 40_000]);
    assert!(segs.iter().all(|s| s["status"] == "stable"));
    // Faithful pass filled faithful text without touching raw text.
    assert!(segs.iter().all(|s| s["faithfulText"].is_string()), "{tr}");
    assert!(segs[0]["rawText"].as_str().unwrap().contains("chunk 0"));

    // The joined recording is stored and playable through a signed link.
    let (s, audio) = t.get(&format!("/v1/recordings/{rid}/audio"), "alice").await;
    assert_eq!(s, StatusCode::OK, "{audio}");
    let path = audio["url"].as_str().unwrap().trim_start_matches("http://test");
    let (s, _) = t.get(path, "alice").await;
    assert_eq!(s, StatusCode::OK);
    let (s, _) = t.get(&path.replace("sig=", "sig=0"), "alice").await;
    assert_eq!(s, StatusCode::FORBIDDEN);

    // Usage metered for billing (Phase 3 charges it).
    let secs: f64 = sqlx::query_scalar("SELECT COALESCE(sum(quantity), 0) FROM usage_meter WHERE kind = 'asr_seconds'")
        .fetch_one(&t.state.notes)
        .await
        .unwrap();
    assert_eq!(secs, 50.0);

    // Bob sees none of it.
    let (s, _) = t.get(&format!("/v1/recordings/{rid}/manifest"), "bob").await;
    assert_eq!(s, StatusCode::NOT_FOUND);
    t.cleanup().await;
}

#[tokio::test]
async fn corrections_keep_raw_text_and_link_to_notes() {
    let t = TestApp::new().await;
    let sid = t.session("alice").await;
    let phone = device(&t, "alice", "Phone").await;
    let rid = Uuid::new_v4().to_string();
    t.post(&format!("/v1/sessions/{sid}/recordings"), "alice", json!({ "id": rid, "deviceId": phone })).await;
    chunk(&t, &rid, 0).await;
    chunk(&t, &rid, 1).await;
    t.drain_jobs().await;
    let (_, tr) = t.get(&format!("/v1/sessions/{sid}/transcript"), "alice").await;
    let seg = tr["segments"][0]["id"].as_str().unwrap().to_string();
    let raw = tr["segments"][0]["rawText"].clone();

    let (s, v) = t.patch(&format!("/v1/transcript/segments/{seg}"), "alice", json!({ "correctedText": "Glycolysis produces two ATP.", "speaker": "professor" })).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert_eq!(v["displayText"], "Glycolysis produces two ATP.");
    assert_eq!(v["rawText"], raw, "raw text is never overwritten");
    let (_, only) = t.get(&format!("/v1/sessions/{sid}/transcript?filter=corrections"), "alice").await;
    assert_eq!(only["segments"].as_array().unwrap().len(), 1);

    // Quote into the notes: a source-linked block, then the linkedNotes filter finds it.
    let (s, block) = t.post(&format!("/v1/sessions/{sid}/blocks/from-source"), "alice", json!({ "kind": "transcript", "sourceId": seg })).await;
    assert_eq!(s, StatusCode::CREATED, "{block}");
    assert_eq!(block["origin"], "fromTranscript");
    assert_eq!(block["type"], "transcriptExcerpt");
    assert_eq!(block["text"], "Glycolysis produces two ATP.");
    let (_, linked) = t.get(&format!("/v1/sessions/{sid}/transcript?filter=linkedNotes"), "alice").await;
    assert_eq!(linked["segments"][0]["linked"], true);

    let (s, v) = t.post(&format!("/v1/transcript/segments/{seg}/restore"), "alice", json!({})).await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(v["displayText"], v["faithfulText"].as_str().map(Value::from).unwrap_or(raw.clone()));
    let revisions: i64 = sqlx::query_scalar("SELECT count(*) FROM transcript_revisions").fetch_one(&t.state.notes).await.unwrap();
    assert_eq!(revisions, 4, "every correction and restore is kept");

    // Markers + questions filter; transcription off skips new chunks.
    let (s, _) = t.post(&format!("/v1/sessions/{sid}/markers"), "alice", json!({ "type": "question", "atMs": 12000 })).await;
    assert_eq!(s, StatusCode::CREATED);
    let (_, q) = t.get(&format!("/v1/sessions/{sid}/transcript?filter=questions"), "alice").await;
    assert_eq!(q["segments"].as_array().unwrap().len(), 1);
    assert_eq!(q["segments"][0]["markers"], json!(["question"]));
    t.post(&format!("/v1/sessions/{sid}/transcription"), "alice", json!({ "on": false })).await;
    chunk(&t, &rid, 2).await;
    t.drain_jobs().await;
    let status: String = sqlx::query_scalar("SELECT asr_status FROM audio_chunks WHERE seq = 2").fetch_one(&t.state.notes).await.unwrap();
    assert_eq!(status, "skipped");
    t.cleanup().await;
}

#[tokio::test]
async fn finish_asks_before_stopping_another_devices_recording() {
    let t = TestApp::new().await;
    let sid = t.session("alice").await;
    let phone = device(&t, "alice", "Phone").await;
    let laptop = device(&t, "alice", "Laptop").await;
    t.post(&format!("/v1/sessions/{sid}/join"), "alice", json!({ "deviceId": laptop })).await;
    t.post(&format!("/v1/sessions/{sid}/recordings"), "alice", json!({ "deviceId": phone })).await;

    // Laptop leaves: the phone keeps recording.
    let (_, v) = t.post(&format!("/v1/sessions/{sid}/leave"), "alice", json!({ "deviceId": laptop })).await;
    assert_eq!(v["keepsRecording"], true);

    let (s, v) = t.post(&format!("/v1/sessions/{sid}/finish"), "alice", json!({ "deviceId": laptop })).await;
    assert_eq!((s, v["code"].as_str()), (StatusCode::CONFLICT, Some("other_device_recording")));
    assert_eq!(v["details"]["devices"][0]["name"], "Phone");

    let (s, v) = t.post(&format!("/v1/sessions/{sid}/finish"), "alice", json!({ "deviceId": laptop, "mode": "leaveKeepRecording" })).await;
    assert_eq!((s, v["finished"].as_bool()), (StatusCode::OK, Some(false)));

    let (s, v) = t.post(&format!("/v1/sessions/{sid}/finish"), "alice", json!({ "deviceId": laptop, "mode": "finishAndStop" })).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert_eq!(v["session"]["status"], "ended");
    assert_eq!(v["stoppedRecordings"].as_array().unwrap().len(), 1);
    let (_, devs) = t.get(&format!("/v1/sessions/{sid}/devices"), "alice").await;
    assert!(devs.as_array().unwrap().iter().all(|d| d["isRecording"] == false));
    let events: i64 = sqlx::query_scalar("SELECT count(*) FROM domain_events WHERE kind = 'session.finished'").fetch_one(&t.state.notes).await.unwrap();
    assert_eq!(events, 1, "The Deck gets a session.finished event");
    t.cleanup().await;
}

async fn serve(state: AppState) -> String {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move { axum::serve(listener, app(state)).await.unwrap() });
    format!("ws://{addr}")
}

async fn next_of_type(ws: &mut (impl StreamExt<Item = Result<Message, tokio_tungstenite::tungstenite::Error>> + Unpin), kind: &str) -> Value {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
    loop {
        let msg = tokio::time::timeout_at(deadline, ws.next()).await.expect("event in time").expect("open").expect("frame");
        if let Message::Text(t) = msg {
            let v: Value = serde_json::from_str(&t).unwrap();
            if v["type"] == kind {
                return v;
            }
        }
    }
}

#[tokio::test]
async fn websocket_delivers_events_and_rejects_strangers() {
    let t = TestApp::new().await;
    let sid = t.session("alice").await;
    let base = serve(t.state.clone()).await;

    let (mut ws, _) = tokio_tungstenite::connect_async(format!("{base}/v1/sessions/{sid}/live")).await.unwrap();
    ws.send(Message::Text(json!({ "type": "auth", "userId": "alice" }).to_string())).await.unwrap();
    let ready = next_of_type(&mut ws, "ready").await;
    assert_eq!(ready["data"]["sessionId"], sid);

    let block = Uuid::new_v4();
    t.post(&format!("/v1/sessions/{sid}/blocks/ops"), "alice", json!({ "ops": [{ "clientOpId": "w1", "op": "upsert", "blockId": block, "block": { "type": "paragraph", "text": "hi", "position": "a" } }] })).await;
    let ev = next_of_type(&mut ws, "block.changed").await;
    assert_eq!(ev["data"]["blockIds"][0], block.to_string());
    assert_eq!(ev["rev"], 1);

    // Bob can't subscribe to Alice's session.
    let (mut bob, _) = tokio_tungstenite::connect_async(format!("{base}/v1/sessions/{sid}/live")).await.unwrap();
    bob.send(Message::Text(json!({ "type": "auth", "userId": "bob" }).to_string())).await.unwrap();
    let err = next_of_type(&mut bob, "error").await;
    assert_eq!(err["data"]["code"], "not_found");
    t.cleanup().await;
}

#[tokio::test]
async fn two_instances_share_a_session_through_redis() {
    let redis = std::env::var("TEST_REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6380".into());
    let a = TestApp::with(|c| c.redis_url = Some(redis.clone())).await;
    // Instance B: same databases, its own process state, same Redis.
    let b_state = AppState::connect((*a.state.config).clone()).await.unwrap();
    let base_b = serve(b_state).await;
    let sid = a.session("alice").await;

    let (mut ws, _) = tokio_tungstenite::connect_async(format!("{base_b}/v1/sessions/{sid}/live")).await.unwrap();
    ws.send(Message::Text(json!({ "type": "auth", "userId": "alice" }).to_string())).await.unwrap();
    next_of_type(&mut ws, "ready").await;
    tokio::time::sleep(Duration::from_millis(300)).await; // relay subscribed

    // Write through instance A; the socket on instance B hears about it.
    let block = Uuid::new_v4();
    a.post(&format!("/v1/sessions/{sid}/blocks/ops"), "alice", json!({ "ops": [{ "clientOpId": "r1", "op": "upsert", "blockId": block, "block": { "type": "paragraph", "text": "via redis", "position": "a" } }] })).await;
    let ev = next_of_type(&mut ws, "block.changed").await;
    assert_eq!(ev["data"]["blockIds"][0], block.to_string());
    a.cleanup().await;
}

/// With ffmpeg installed, real Opus chunks are joined and re-encoded to one
/// 24 kbps mono file (skipped where ffmpeg is missing).
#[tokio::test]
async fn real_audio_is_joined_and_compressed() {
    let have_ffmpeg = std::process::Command::new("ffmpeg").arg("-version").output().is_ok();
    if !have_ffmpeg {
        eprintln!("ffmpeg not installed — skipping");
        return;
    }
    let t = TestApp::new().await;
    let sid = t.session("alice").await;
    let phone = device(&t, "alice", "Phone").await;
    let rid = Uuid::new_v4().to_string();
    t.post(&format!("/v1/sessions/{sid}/recordings"), "alice", json!({ "id": rid, "deviceId": phone })).await;
    let dir = std::env::temp_dir().join(format!("octonotes-audio-{rid}"));
    std::fs::create_dir_all(&dir).unwrap();
    let mut raw_total = 0;
    for seq in 0..3 {
        let f = dir.join(format!("{seq}.ogg"));
        let ok = std::process::Command::new("ffmpeg")
            .args(["-y", "-loglevel", "error", "-f", "lavfi", "-i", &format!("sine=frequency={}:duration=2", 300 + seq * 100), "-ac", "2", "-c:a", "libopus", "-b:a", "96k"])
            .arg(&f)
            .status()
            .unwrap()
            .success();
        assert!(ok);
        let bytes = std::fs::read(&f).unwrap();
        raw_total += bytes.len();
        let (s, v) = t.put_bytes(&format!("/v1/recordings/{rid}/chunks/{seq}?startMs={}&durationMs=2000", seq * 2000), "alice", bytes, "audio/ogg").await;
        assert_eq!(s, StatusCode::OK, "{v}");
    }
    t.post(&format!("/v1/recordings/{rid}/complete"), "alice", json!({ "lastSeq": 2 })).await;
    t.drain_jobs().await;
    let (key, bytes): (String, i64) = sqlx::query_as("SELECT audio_key, audio_bytes FROM recordings WHERE id = $1::uuid")
        .bind(&rid)
        .fetch_one(&t.state.notes)
        .await
        .unwrap();
    assert!(key.ends_with("recording.ogg"));
    assert!((bytes as usize) < raw_total, "compressed {bytes} < raw {raw_total}");
    let stored = t.state.storage.get(&key).await.unwrap();
    assert_eq!(&stored[..4], b"OggS");
    let _ = std::fs::remove_dir_all(dir);
    t.cleanup().await;
}

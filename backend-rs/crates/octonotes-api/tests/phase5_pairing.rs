//! Recording on another phone: pair with the 6-digit code or the QR, start
//! the session, and the paired phone records into it. Only phones record, one
//! per session.

mod common;

use axum::http::StatusCode;
use common::TestApp;
use serde_json::json;
use uuid::Uuid;

async fn device(t: &TestApp, user: &str, name: &str, platform: &str) -> String {
    let id = Uuid::new_v4();
    let (s, v) = t
        .post("/v1/devices", user, json!({ "id": id, "name": name, "platform": platform }))
        .await;
    assert_eq!(s, StatusCode::OK, "{v}");
    id.to_string()
}

#[tokio::test]
async fn pair_by_code_then_the_phone_records_into_the_session() {
    let t = TestApp::new().await;
    let receiver = device(&t, "alice", "Alice's PC", "windows").await;
    let phone = device(&t, "alice", "Alice's Pixel", "android").await;
    let laptop = device(&t, "alice", "Alice's laptop", "macos").await;

    let (s, p) = t.post("/v1/pairings", "alice", json!({ "receiverDeviceId": receiver })).await;
    assert_eq!(s, StatusCode::CREATED, "{p}");
    let (pid, code) = (p["id"].as_str().unwrap().to_string(), p["code"].as_str().unwrap().to_string());
    assert_eq!(code.len(), 6);
    assert!(p["secret"].as_str().is_some_and(|x| x.len() == 32), "{p}");
    assert_eq!(p["status"], "waiting");

    // Starting before a phone paired: refused.
    let sid = t.session("alice").await;
    let (s, _) = t.post(&format!("/v1/pairings/{pid}/start"), "alice", json!({ "sessionId": sid })).await;
    assert_eq!(s, StatusCode::CONFLICT);

    // The receiver itself can't be the recorder; a wrong code finds nothing.
    let (s, _) = t.post("/v1/pairings/claim", "alice", json!({ "code": code, "deviceId": receiver })).await;
    assert_eq!(s, StatusCode::BAD_REQUEST);
    // A PC never records: two PCs can't pair.
    let (s, e) = t.post("/v1/pairings/claim", "alice", json!({ "code": code, "deviceId": laptop })).await;
    assert_eq!(s, StatusCode::BAD_REQUEST, "{e}");
    assert_eq!(e["code"], "recorder_not_phone", "{e}");
    let wrong = if code == "000000" { "000001" } else { "000000" };
    let (s, _) = t.post("/v1/pairings/claim", "alice", json!({ "code": wrong, "deviceId": phone })).await;
    assert_eq!(s, StatusCode::NOT_FOUND);

    let (s, c) = t.post("/v1/pairings/claim", "alice", json!({ "code": code, "deviceId": phone })).await;
    assert_eq!(s, StatusCode::OK, "{c}");
    assert_eq!(c["status"], "paired");
    assert!(c.get("secret").is_none(), "the phone never sees the secret");

    // The receiver sees who paired.
    let (_, g) = t.get(&format!("/v1/pairings/{pid}"), "alice").await;
    assert_eq!(g["status"], "paired");
    assert_eq!(g["recorderDevice"]["name"], "Alice's Pixel");

    // Start: the phone learns the session and records into it.
    let (s, st) = t.post(&format!("/v1/pairings/{pid}/start"), "alice", json!({ "sessionId": sid })).await;
    assert_eq!(s, StatusCode::OK, "{st}");
    let (_, g) = t.get(&format!("/v1/pairings/{pid}"), "alice").await;
    assert_eq!(g["status"], "started");
    assert_eq!(g["sessionId"], sid.as_str());
    let (s, rec) = t
        .post(&format!("/v1/sessions/{sid}/recordings"), "alice", json!({ "id": Uuid::new_v4(), "deviceId": phone }))
        .await;
    assert_eq!(s, StatusCode::CREATED, "{rec}");
    let (_, devs) = t.get(&format!("/v1/sessions/{sid}/devices"), "alice").await;
    assert!(devs.to_string().contains("recorder"), "{devs}");

    // A retry of start is fine; a used code can't be claimed again.
    let (s, _) = t.post(&format!("/v1/pairings/{pid}/start"), "alice", json!({ "sessionId": sid })).await;
    assert_eq!(s, StatusCode::OK);
    let (s, _) = t.post("/v1/pairings/claim", "alice", json!({ "code": code, "deviceId": phone })).await;
    assert_eq!(s, StatusCode::NOT_FOUND);

    // One recorder per session: a second phone paired to the same session is refused.
    let other = device(&t, "alice", "Alice's old phone", "android").await;
    let (_, p2) = t.post("/v1/pairings", "alice", json!({ "receiverDeviceId": receiver })).await;
    let pid2 = p2["id"].as_str().unwrap().to_string();
    let (s, _) = t
        .post("/v1/pairings/claim", "alice", json!({ "code": p2["code"].as_str().unwrap(), "deviceId": other }))
        .await;
    assert_eq!(s, StatusCode::OK);
    let (s, e) = t.post(&format!("/v1/pairings/{pid2}/start"), "alice", json!({ "sessionId": sid })).await;
    assert_eq!(s, StatusCode::CONFLICT, "{e}");
    assert_eq!(e["code"], "has_recorder", "{e}");
    t.cleanup().await;
}

#[tokio::test]
async fn pair_by_qr_and_other_accounts_cannot() {
    let t = TestApp::new().await;
    let receiver = device(&t, "alice", "Alice's phone", "ios").await;
    let phone = device(&t, "alice", "Alice's Pixel", "android").await;
    let bobs = device(&t, "bob", "Bob's phone", "android").await;
    let (_, p) = t.post("/v1/pairings", "alice", json!({ "receiverDeviceId": receiver })).await;
    let (pid, secret) = (p["id"].as_str().unwrap().to_string(), p["secret"].as_str().unwrap().to_string());

    // Bob scans Alice's QR: told to use the same account.
    let (s, e) = t
        .post("/v1/pairings/claim", "bob", json!({ "secret": format!("octonotes-pair:{secret}"), "deviceId": bobs }))
        .await;
    assert_eq!(s, StatusCode::FORBIDDEN, "{e}");
    // Bob can't read it either.
    let (s, _) = t.get(&format!("/v1/pairings/{pid}"), "bob").await;
    assert_eq!(s, StatusCode::NOT_FOUND);

    let (s, c) = t
        .post("/v1/pairings/claim", "alice", json!({ "secret": format!("octonotes-pair:{secret}"), "deviceId": phone }))
        .await;
    assert_eq!(s, StatusCode::OK, "{c}");
    assert_eq!(c["status"], "paired");

    // Cancelled: no longer startable.
    let (s, _) = t.delete(&format!("/v1/pairings/{pid}"), "alice").await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    let sid = t.session("alice").await;
    let (s, _) = t.post(&format!("/v1/pairings/{pid}/start"), "alice", json!({ "sessionId": sid })).await;
    assert_eq!(s, StatusCode::CONFLICT);
    t.cleanup().await;
}

#[tokio::test]
async fn two_devices_at_most_and_the_phone_records() {
    let t = TestApp::new().await;
    let pc = device(&t, "alice", "Alice's PC", "windows").await;
    let phone = device(&t, "alice", "Alice's Pixel", "android").await;
    let tablet = device(&t, "alice", "Alice's tablet", "android").await;
    let rec = |d: &str| json!({ "id": Uuid::new_v4(), "deviceId": d });

    // Alone, a PC may record (its own mic).
    let solo = t.session("alice").await;
    let (s, v) = t.post(&format!("/v1/sessions/{solo}/recordings"), "alice", rec(&pc)).await;
    assert_eq!(s, StatusCode::CREATED, "{v}");

    // With the PC in the session, the phone records.
    let sid = t.session("alice").await;
    let (s, v) = t.post(&format!("/v1/sessions/{sid}/join"), "alice", json!({ "deviceId": pc })).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    let (s, v) = t.post(&format!("/v1/sessions/{sid}/recordings"), "alice", rec(&phone)).await;
    assert_eq!(s, StatusCode::CREATED, "{v}");

    // A second recorder, or a third device: refused.
    let (s, e) = t.post(&format!("/v1/sessions/{sid}/recordings"), "alice", rec(&tablet)).await;
    assert_eq!(s, StatusCode::CONFLICT, "{e}");
    let (s, e) = t.post(&format!("/v1/sessions/{sid}/join"), "alice", json!({ "deviceId": tablet })).await;
    assert_eq!(s, StatusCode::CONFLICT, "{e}");
    assert_eq!(e["code"], "session_full", "{e}");

    // Next to a phone, the PC can't be the recorder.
    let other = t.session("alice").await;
    let (s, v) = t.post(&format!("/v1/sessions/{other}/join"), "alice", json!({ "deviceId": phone })).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    let (s, e) = t.post(&format!("/v1/sessions/{other}/recordings"), "alice", rec(&pc)).await;
    assert_eq!(s, StatusCode::CONFLICT, "{e}");
    assert_eq!(e["code"], "recorder_not_phone", "{e}");
    t.cleanup().await;
}

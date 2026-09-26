//! Phase 1 — notes core: sessions, courses, devices, destinations, blocks, ink.

mod common;

use axum::http::{Method, StatusCode};
use common::{stroke_points, TestApp};
use serde_json::{json, Value};
use uuid::Uuid;

#[tokio::test]
async fn health_ready_me_and_openapi() {
    let t = TestApp::new().await;
    let (s, v) = t.get("/health", "alice").await;
    assert_eq!((s, v["status"].as_str()), (StatusCode::OK, Some("ok")));
    let (s, v) = t.get("/ready", "alice").await;
    assert_eq!(s, StatusCode::OK, "{v}");
    let (s, v) = t.get("/v1/me", "alice").await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(v["octoCredits"], 10000);
    assert_eq!(v["registered"], true);
    let (s, v) = t.get("/v1/openapi.json", "alice").await;
    assert_eq!(s, StatusCode::OK);
    assert!(v["paths"]["/v1/sessions/{id}/blocks/ops"].is_object(), "ops path in spec");
    t.cleanup().await;
}

#[tokio::test]
async fn unknown_account_is_403_account_required() {
    let t = TestApp::new().await;
    let (s, v) = t.get("/v1/sessions", "stranger").await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    assert_eq!(v["code"], "account_required");
    t.cleanup().await;
}

#[tokio::test]
async fn sessions_crud_search_and_isolation() {
    let t = TestApp::new().await;
    let (s, course) = t.post("/v1/courses", "alice", json!({ "name": "Biology 101", "color": "#E11D2E" })).await;
    assert_eq!(s, StatusCode::CREATED, "{course}");
    let (s, v) = t.post("/v1/courses", "alice", json!({ "name": "biology 101" })).await;
    assert_eq!((s, v["code"].as_str()), (StatusCode::CONFLICT, Some("course_exists")));

    let (s, sess) = t
        .post("/v1/sessions", "alice", json!({
            "title": "Glycolysis lecture", "courseId": course["id"], "workspaceMode": "both",
            "config": { "liveSuggestions": false }
        }))
        .await;
    assert_eq!(s, StatusCode::CREATED, "{sess}");
    assert_eq!(sess["config"]["liveSuggestions"], false);
    assert_eq!(sess["config"]["record"], true);
    let id = sess["id"].as_str().unwrap();
    t.session("alice").await;

    // Bad input is refused with a reason.
    let (s, _) = t.post("/v1/sessions", "alice", json!({ "workspaceMode": "canvas" })).await;
    assert_eq!(s, StatusCode::BAD_REQUEST);
    let (s, _) = t.post("/v1/sessions", "alice", json!({ "config": { "recrod": true } })).await;
    assert_eq!(s, StatusCode::BAD_REQUEST);

    // Search + filters + pagination.
    let (_, list) = t.get("/v1/sessions?q=glycolysis", "alice").await;
    assert_eq!(list["items"].as_array().unwrap().len(), 1);
    let (_, list) = t.get(&format!("/v1/sessions?courseId={}", course["id"].as_str().unwrap()), "alice").await;
    assert_eq!(list["items"].as_array().unwrap().len(), 1);
    let (_, page1) = t.get("/v1/sessions?limit=1", "alice").await;
    assert_eq!(page1["items"].as_array().unwrap().len(), 1);
    let cursor = page1["nextCursor"].as_str().expect("cursor");
    let (_, page2) = t.get(&format!("/v1/sessions?limit=1&cursor={cursor}"), "alice").await;
    assert_eq!(page2["items"].as_array().unwrap().len(), 1);
    assert_ne!(page1["items"][0]["id"], page2["items"][0]["id"]);
    assert!(page2["nextCursor"].is_null());

    // Bob can't see or touch Alice's session: 404, never 403.
    let (s, _) = t.get(&format!("/v1/sessions/{id}"), "bob").await;
    assert_eq!(s, StatusCode::NOT_FOUND);
    let (s, _) = t.patch(&format!("/v1/sessions/{id}"), "bob", json!({ "title": "x" })).await;
    assert_eq!(s, StatusCode::NOT_FOUND);
    let (_, bob_list) = t.get("/v1/sessions", "bob").await;
    assert_eq!(bob_list["items"].as_array().unwrap().len(), 0);

    // Patch, including clearing the course with null.
    let (s, v) = t.patch(&format!("/v1/sessions/{id}"), "alice", json!({ "title": "Glycolysis & ETC", "courseId": null })).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert_eq!(v["title"], "Glycolysis & ETC");
    assert!(v["courseId"].is_null());

    // Snapshot, then delete.
    let (s, snap) = t.get(&format!("/v1/sessions/{id}"), "alice").await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(snap["session"]["id"], id);
    assert!(snap["blocks"].as_array().unwrap().is_empty());
    let (s, _) = t.delete(&format!("/v1/sessions/{id}"), "alice").await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    let (s, _) = t.get(&format!("/v1/sessions/{id}"), "alice").await;
    assert_eq!(s, StatusCode::NOT_FOUND);
    t.cleanup().await;
}

#[tokio::test]
async fn create_session_is_idempotent() {
    let t = TestApp::new().await;
    let body = json!({ "title": "Retry me" });
    let h = [("idempotency-key", "k-123")];
    let (s1, a) = t.call_with(Method::POST, "/v1/sessions", "alice", Some(body.clone()), &h).await;
    let (s2, b) = t.call_with(Method::POST, "/v1/sessions", "alice", Some(body), &h).await;
    assert_eq!((s1, s2), (StatusCode::CREATED, StatusCode::CREATED));
    assert_eq!(a["id"], b["id"]);
    let (s3, v) = t.call_with(Method::POST, "/v1/sessions", "alice", Some(json!({ "title": "Other" })), &h).await;
    assert_eq!((s3, v["code"].as_str()), (StatusCode::UNPROCESSABLE_ENTITY, Some("idempotency_mismatch")));
    let (_, list) = t.get("/v1/sessions", "alice").await;
    assert_eq!(list["items"].as_array().unwrap().len(), 1);
    t.cleanup().await;
}

fn upsert(op_id: &str, block: Uuid, base: i64, body: Value) -> Value {
    json!({ "clientOpId": op_id, "op": "upsert", "blockId": block, "baseRevision": base, "block": body })
}

#[tokio::test]
async fn block_sync_conflicts_replay_history_restore() {
    let t = TestApp::new().await;
    let sid = t.session("alice").await;
    let ops = format!("/v1/sessions/{sid}/blocks/ops");
    let (a, b) = (Uuid::new_v4(), Uuid::new_v4());

    let (s, r) = t
        .post(&ops, "alice", json!({ "ops": [
            upsert("op1", a, 0, json!({ "type": "h1", "text": "Cellular Respiration", "position": "a" })),
            upsert("op2", b, 0, json!({ "type": "paragraph", "text": "Glycolysis happens in the cytoplasm", "position": "b" })),
        ]}))
        .await;
    assert_eq!(s, StatusCode::OK, "{r}");
    assert!(r["results"].as_array().unwrap().iter().all(|x| x["status"] == "applied"), "{r}");
    let rev_after_create = r["rev"].as_i64().unwrap();
    assert_eq!(rev_after_create, 2);

    // Device 1 edits b at revision 1 → applied (revision 2).
    let (_, r) = t.post(&ops, "alice", json!({ "ops": [upsert("op3", b, 1, json!({ "text": "Glycolysis: cytoplasm, 2 ATP" }))] })).await;
    assert_eq!(r["results"][0]["status"], "applied");
    assert_eq!(r["results"][0]["block"]["revision"], 2);

    // Device 2 still on revision 1 → conflict with the server copy (keep both).
    let (_, r) = t.post(&ops, "alice", json!({ "ops": [upsert("op4", b, 1, json!({ "text": "Glycolysis (from tablet)" }))] })).await;
    assert_eq!(r["results"][0]["status"], "conflict", "{r}");
    assert_eq!(r["results"][0]["block"]["text"], "Glycolysis: cytoplasm, 2 ATP");

    // Offline replay of op3 → identical result, nothing changes.
    let (_, r) = t.post(&ops, "alice", json!({ "ops": [upsert("op3", b, 1, json!({ "text": "Glycolysis: cytoplasm, 2 ATP" }))] })).await;
    assert_eq!(r["results"][0]["status"], "applied");
    assert_eq!(r["results"][0]["block"]["revision"], 2);

    // Clients can't forge AI blocks or bad types.
    let (_, r) = t.post(&ops, "alice", json!({ "ops": [
        upsert("op5", Uuid::new_v4(), 0, json!({ "type": "paragraph", "text": "x", "position": "c", "origin": "aiInsertedByStudent" })),
        upsert("op6", Uuid::new_v4(), 0, json!({ "type": "banner", "text": "x", "position": "c" })),
        upsert("op7", Uuid::new_v4(), 0, json!({ "type": "paragraph", "text": "x", "position": "c0" })),
    ]})).await;
    assert!(r["results"].as_array().unwrap().iter().all(|x| x["status"] == "rejected"), "{r}");

    // Move a before b's position, delete, history, restore.
    let (_, r) = t.post(&ops, "alice", json!({ "ops": [{ "clientOpId": "op8", "op": "move", "blockId": a, "baseRevision": 1, "position": "c" }] })).await;
    assert_eq!(r["results"][0]["status"], "applied");
    let (_, list) = t.get(&format!("/v1/sessions/{sid}/blocks"), "alice").await;
    let order: Vec<&str> = list["blocks"].as_array().unwrap().iter().map(|x| x["id"].as_str().unwrap()).collect();
    assert_eq!(order, vec![b.to_string(), a.to_string()]);

    let (_, r) = t.post(&ops, "alice", json!({ "ops": [{ "clientOpId": "op9", "op": "delete", "blockId": b, "baseRevision": 2 }] })).await;
    assert_eq!(r["results"][0]["status"], "applied");
    let rev_before = r["rev"].as_i64().unwrap();

    // Catch-up: only changes after a rev, deleted ones flagged.
    let (_, delta) = t.get(&format!("/v1/sessions/{sid}/blocks?sinceRev={}", rev_before - 1), "alice").await;
    assert_eq!(delta["blocks"].as_array().unwrap().len(), 1);
    assert!(delta["blocks"][0]["deletedAt"].is_string());

    let (s, hist) = t.get(&format!("/v1/blocks/{b}/history"), "alice").await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(hist.as_array().unwrap().len(), 3); // create, update, delete
    let (s, _) = t.get(&format!("/v1/blocks/{b}/history"), "bob").await;
    assert_eq!(s, StatusCode::NOT_FOUND);

    let (s, restored) = t.post(&format!("/v1/blocks/{b}/restore"), "alice", json!({ "revision": 2 })).await;
    assert_eq!(s, StatusCode::OK, "{restored}");
    assert!(restored["deletedAt"].is_null());
    assert_eq!(restored["text"], "Glycolysis: cytoplasm, 2 ATP");

    // Bob can't write into Alice's session.
    let (s, _) = t.post(&ops, "bob", json!({ "ops": [upsert("x", Uuid::new_v4(), 0, json!({ "type": "paragraph", "position": "d" }))] })).await;
    assert_eq!(s, StatusCode::NOT_FOUND);
    t.cleanup().await;
}

#[tokio::test]
async fn ink_pages_and_strokes() {
    let t = TestApp::new().await;
    let sid = t.session("alice").await;
    let page_id = Uuid::new_v4();
    let (s, page) = t.post(&format!("/v1/sessions/{sid}/ink/pages"), "alice", json!({ "id": page_id, "background": "grid" })).await;
    assert_eq!(s, StatusCode::CREATED, "{page}");
    // Same id again → same page (offline retry).
    let (s, _) = t.post(&format!("/v1/sessions/{sid}/ink/pages"), "alice", json!({ "id": page_id })).await;
    assert_eq!(s, StatusCode::OK);

    let stroke = Uuid::new_v4();
    let pts = stroke_points(&[(10.0, 10.0, 0.5), (20.0, 15.0, 0.6), (30.0, 22.0, 0.7)]);
    let ops = format!("/v1/ink/pages/{page_id}/ops");
    let (s, r) = t.post(&ops, "alice", json!({ "ops": [
        { "clientOpId": "s1", "op": "add", "strokeId": stroke, "stroke": { "tool": "pen", "points": pts, "color": "#FF1E88E5", "width": 3.0 } },
        { "clientOpId": "s2", "op": "add", "strokeId": Uuid::new_v4(), "stroke": { "tool": "pen", "points": "AQAAAAA=" } },
        { "clientOpId": "s3", "op": "add", "strokeId": Uuid::new_v4(), "stroke": { "tool": "laser", "points": pts } },
    ]})).await;
    assert_eq!(s, StatusCode::OK, "{r}");
    assert_eq!(r["results"][0]["status"], "applied");
    assert_eq!(r["results"][0]["stroke"]["points"], pts, "ink stored byte-for-byte");
    assert_eq!(r["results"][1]["status"], "rejected");
    assert_eq!(r["results"][2]["status"], "rejected");

    let (_, r) = t.post(&ops, "alice", json!({ "ops": [{ "clientOpId": "s4", "op": "erase", "strokeId": stroke }] })).await;
    assert_eq!(r["results"][0]["status"], "applied");
    let (_, live) = t.get(&format!("/v1/ink/pages/{page_id}/strokes"), "alice").await;
    assert!(live["strokes"].as_array().unwrap().is_empty());
    let (_, delta) = t.get(&format!("/v1/sessions/{sid}/ink/strokes?sinceRev=0"), "alice").await;
    assert_eq!(delta["strokes"].as_array().unwrap().len(), 1);
    assert!(delta["strokes"][0]["deletedAt"].is_string());

    let (s, page) = t.patch(&format!("/v1/ink/pages/{page_id}"), "alice", json!({ "background": "lined" })).await;
    assert_eq!((s, page["background"].as_str()), (StatusCode::OK, Some("lined")));
    let (s, _) = t.patch(&format!("/v1/ink/pages/{page_id}"), "bob", json!({ "background": "lined" })).await;
    assert_eq!(s, StatusCode::NOT_FOUND);
    t.cleanup().await;
}

#[tokio::test]
async fn devices_destinations_and_home() {
    let t = TestApp::new().await;
    let dev = Uuid::new_v4();
    let (s, d) = t.post("/v1/devices", "alice", json!({ "id": dev, "name": "Alice's iPhone", "platform": "ios" })).await;
    assert_eq!(s, StatusCode::OK, "{d}");
    // Bob can't take over Alice's device id.
    let (s, _) = t.post("/v1/devices", "bob", json!({ "id": dev, "name": "x", "platform": "web" })).await;
    assert_eq!(s, StatusCode::BAD_REQUEST);

    // Destinations come from Study Studio studios.
    let alice_id: String = sqlx::query_scalar("SELECT id::text FROM users WHERE firebase_uid = 'alice'")
        .fetch_one(t.state.octopilot.as_ref().unwrap())
        .await
        .unwrap();
    sqlx::query("INSERT INTO studios (user_id, title, subject) VALUES ($1::uuid, 'Biology Midterm', 'Biology')")
        .bind(&alice_id)
        .execute(t.state.studio.as_ref().unwrap())
        .await
        .unwrap();
    let (_, dest) = t.get("/v1/deck/destinations", "alice").await;
    assert_eq!(dest[0]["title"], "Biology Midterm");
    assert!(dest[0]["ref"].as_str().unwrap().starts_with("studio:"));
    let (_, dest_bob) = t.get("/v1/deck/destinations", "bob").await;
    assert!(dest_bob.as_array().unwrap().is_empty());

    t.session("alice").await;
    let (s, home) = t.get("/v1/home", "alice").await;
    assert_eq!(s, StatusCode::OK, "{home}");
    assert_eq!(home["continue"].as_array().unwrap().len(), 1);
    t.cleanup().await;
}

#[tokio::test]
async fn big_session_snapshot_is_fast() {
    let t = TestApp::new().await;
    let sid = t.session("alice").await;
    let mut key: Option<String> = None;
    let mut ops = Vec::new();
    for i in 0..500 {
        let k = octonotes_api::positions::between(key.as_deref(), None);
        ops.push(upsert(&format!("b{i}"), Uuid::new_v4(), 0, json!({ "type": "paragraph", "text": format!("Line {i} of the lecture notes"), "position": k })));
        key = Some(k);
    }
    let (s, _) = t.post(&format!("/v1/sessions/{sid}/blocks/ops"), "alice", json!({ "ops": ops })).await;
    assert_eq!(s, StatusCode::OK);
    // Warm once, then time.
    t.get(&format!("/v1/sessions/{sid}"), "alice").await;
    let start = std::time::Instant::now();
    let (_, snap) = t.get(&format!("/v1/sessions/{sid}"), "alice").await;
    let ms = start.elapsed().as_millis();
    assert_eq!(snap["blocks"].as_array().unwrap().len(), 500);
    eprintln!("500-block snapshot: {ms} ms");
    assert!(ms < 300, "snapshot took {ms} ms");
    t.cleanup().await;
}

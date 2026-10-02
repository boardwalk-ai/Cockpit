//! Phase 1d: the document from the editor's side — saving, the live text
//! stream, and versions with restore.

mod common;

use std::sync::Arc;

use axum::http::StatusCode;
use common::fakes::{ask, call, turn, FakeLlm, FakeScraper, ESSAY};
use common::{kinds, EventStream, TestApp};
use serde_json::{json, Value};
use tokio::sync::Notify;
use uuid::Uuid;

async fn new_project(t: &TestApp, user: &str) -> Uuid {
    let project = Uuid::new_v4();
    let (status, _) = t
        .put(&format!("/v1/projects/{project}"), user, json!({}))
        .await;
    assert_eq!(status, StatusCode::OK);
    project
}

async fn start_run(t: &TestApp, project: Uuid) -> Uuid {
    let run = Uuid::new_v4();
    let (status, body) = t
        .post(
            &format!("/v1/projects/{project}/runs"),
            "alice",
            json!({ "runId": run, "instruction": "An essay on rising tides" }),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    run
}

async fn answer(t: &TestApp, run: Uuid, field: &str, value: Value) {
    let (status, body) = t
        .post(
            &format!("/v1/runs/{run}/answer"),
            "alice",
            json!({ "field": field, "value": value }),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
}

/// A project whose scripted run has written an 800-word MLA essay.
async fn written_project(t: &TestApp) -> Uuid {
    let project = new_project(t, "alice").await;
    let run = start_run(t, project).await;
    let mut events = t
        .events(&format!("/v1/runs/{run}/events"), "alice", None)
        .await;
    events.until("question").await;
    answer(t, run, "essayFocus", json!(["Economic impact"])).await;
    events.until("question").await;
    answer(t, run, "sourceReviewChoice", json!("One Shot")).await;
    events.until("question").await;
    answer(t, run, "wordCount", json!(800)).await;
    events.until("question").await;
    answer(t, run, "citationStyle", json!("MLA")).await;
    assert_eq!(events.rest().await.last().unwrap()["type"], "done");
    project
}

async fn document(t: &TestApp, project: Uuid) -> Value {
    let (status, document) = t
        .get(&format!("/v1/projects/{project}/document"), "alice")
        .await;
    assert_eq!(status, StatusCode::OK);
    document
}

async fn save(t: &TestApp, project: Uuid, user: &str, body: Value) -> (StatusCode, Value) {
    t.put(&format!("/v1/projects/{project}/document"), user, body)
        .await
}

async fn versions(t: &TestApp, project: Uuid) -> Vec<Value> {
    let (status, body) = t
        .get(&format!("/v1/projects/{project}/versions"), "alice")
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    body["versions"].as_array().unwrap().clone()
}

fn reasons(versions: &[Value]) -> Vec<&str> {
    versions
        .iter()
        .map(|v| v["reason"].as_str().unwrap())
        .collect()
}

async fn lock(t: &TestApp, project: Uuid) {
    sqlx::query("UPDATE documents SET locked_by_run = $1 WHERE project_id = $2")
        .bind(Uuid::new_v4())
        .bind(project)
        .execute(&t.state.db)
        .await
        .unwrap();
}

#[tokio::test]
async fn the_scripted_run_writes_a_real_document() {
    let t = TestApp::new().await;
    let project = written_project(&t).await;

    let document = document(&t, project).await;
    assert_eq!(document["locked"], false);
    assert_eq!(document["style"], "mla");
    assert_eq!(document["title"], "An essay on rising tides");
    assert_eq!(document["wordCount"], 832);
    let body = document["body"].as_str().unwrap();
    assert_eq!(body.split_whitespace().count(), 832);
    assert!(body.contains("\n\n"), "paragraphs");
    assert!(!document["bibliography"].as_str().unwrap().is_empty());

    t.cleanup().await;
}

#[tokio::test]
async fn the_editor_saves_against_the_rev_it_loaded() {
    let t = TestApp::new().await;
    let project = written_project(&t).await;
    let loaded = document(&t, project).await;
    let rev = loaded["rev"].as_i64().unwrap();

    let edit = json!({
        "baseRev": rev,
        "title": "  Tides, revised  ",
        "body": "One short paragraph.\n\nAnd another.",
        "delta": { "ops": [{ "insert": "One short paragraph.\n\nAnd another.\n" }] },
        "fields": { "studentName": "Ada Lovelace" },
        "style": "apa",
    });
    let (status, saved) = save(&t, project, "alice", edit.clone()).await;
    assert_eq!(status, StatusCode::OK, "{saved}");
    assert_eq!(saved["rev"], rev + 1);
    assert_eq!(saved["wordCount"], 5);

    let now = document(&t, project).await;
    assert_eq!(now["rev"], rev + 1);
    assert_eq!(now["title"], "Tides, revised");
    assert_eq!(now["body"], "One short paragraph.\n\nAnd another.");
    assert_eq!(now["delta"], edit["delta"]);
    assert_eq!(now["style"], "apa");
    assert_eq!(now["fields"], json!({ "studentName": "Ada Lovelace" }));
    assert_eq!(now["wordCount"], 5);
    // Fields not sent are kept.
    assert_eq!(now["bibliography"], loaded["bibliography"]);

    // A retry of the same save (its reply was lost) succeeds without a change.
    let (status, again) = save(&t, project, "alice", edit).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(again["rev"], rev + 1);

    // A different save from the old copy loses, and says where things are.
    let (status, stale) = save(
        &t,
        project,
        "alice",
        json!({ "baseRev": rev, "body": "From a stale copy." }),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(stale["code"], "stale_rev");
    assert_eq!(stale["details"]["rev"], rev + 1);
    assert_eq!(
        document(&t, project).await["body"],
        "One short paragraph.\n\nAnd another."
    );

    // A new body without a delta drops the old delta: it no longer matches.
    let (status, _) = save(
        &t,
        project,
        "alice",
        json!({ "baseRev": rev + 1, "body": "Plain now." }),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let now = document(&t, project).await;
    assert_eq!(now["delta"], Value::Null);
    assert_eq!(now["title"], "Tides, revised");

    // The project list shows the new length.
    let (_, project_state) = t.get(&format!("/v1/projects/{project}"), "alice").await;
    assert_eq!(project_state["wordCount"], 2);
    assert_eq!(project_state["status"], "ready");

    t.cleanup().await;
}

#[tokio::test]
async fn saves_are_refused_while_the_agent_holds_the_lock() {
    let t = TestApp::new().await;
    let project = new_project(&t, "alice").await;
    lock(&t, project).await;

    let (status, body) = save(
        &t,
        project,
        "alice",
        json!({ "baseRev": 0, "body": "Typed during a write." }),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(body["code"], "document_locked");
    assert_eq!(document(&t, project).await["body"], "");

    t.cleanup().await;
}

#[tokio::test]
async fn bad_saves_are_rejected_and_other_peoples_documents_are_not_found() {
    let t = TestApp::new().await;
    let project = new_project(&t, "alice").await;

    for (body, why) in [
        (
            json!({ "baseRev": 0, "style": "vancouver" }),
            "unknown style",
        ),
        (
            json!({ "baseRev": 0, "fields": ["a"] }),
            "fields not an object",
        ),
        (
            json!({ "baseRev": 0, "delta": "text" }),
            "delta not a delta",
        ),
        (
            json!({ "baseRev": 0, "title": "x".repeat(301) }),
            "title too long",
        ),
    ] {
        let (status, _) = save(&t, project, "alice", body).await;
        assert_eq!(status, StatusCode::BAD_REQUEST, "{why}");
    }
    let (status, _) = save(&t, project, "alice", json!({ "body": "no baseRev" })).await;
    assert!(status.is_client_error());

    let (status, _) = save(
        &t,
        project,
        "bob",
        json!({ "baseRev": 0, "body": "Mine now." }),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = t
        .get(&format!("/v1/projects/{project}/versions"), "bob")
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = t
        .get(&format!("/v1/projects/{project}/document/stream"), "bob")
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    t.cleanup().await;
}

#[tokio::test]
async fn editor_saves_share_one_version_and_any_version_can_be_restored() {
    let t = TestApp::new().await;
    let project = written_project(&t).await;
    let written = document(&t, project).await;
    let rev = written["rev"].as_i64().unwrap();

    // The agent's write kept the empty document it replaced.
    let before = versions(&t, project).await;
    assert_eq!(reasons(&before), ["agent_write"]);
    assert_eq!(before[0]["wordCount"], 0);

    // Two quick saves: the agent's text is kept once, before the first.
    for (n, text) in ["First edit.", "Second edit."].iter().enumerate() {
        let (status, body) = save(
            &t,
            project,
            "alice",
            json!({ "baseRev": rev + n as i64, "body": text }),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "{body}");
    }
    let list = versions(&t, project).await;
    assert_eq!(reasons(&list), ["user_save", "agent_write"]);
    let agent_text = &list[0];
    assert_eq!(agent_text["rev"], rev);
    assert_eq!(agent_text["wordCount"], 832);
    assert_eq!(agent_text["title"], "An essay on rising tides");
    assert!(agent_text["preview"]
        .as_str()
        .unwrap()
        .starts_with("This draft was written"));

    // Undo the edits: the agent's essay is back, with its rich fields.
    let (status, restored) = t
        .post(
            &format!(
                "/v1/projects/{project}/versions/{}/restore",
                agent_text["id"].as_str().unwrap()
            ),
            "alice",
            json!({}),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{restored}");
    assert_eq!(restored["body"], written["body"]);
    assert_eq!(restored["bibliography"], written["bibliography"]);
    assert_eq!(restored["style"], "mla");
    assert_eq!(restored["wordCount"], 832);
    assert_eq!(restored["rev"], rev + 3);

    // What the restore replaced is a version too, so it can be undone.
    let list = versions(&t, project).await;
    assert_eq!(reasons(&list), ["restore", "user_save", "agent_write"]);
    assert_eq!(list[0]["preview"], "Second edit.");

    // Nothing to restore from: an unknown version, or a locked document.
    let (status, _) = t
        .post(
            &format!("/v1/projects/{project}/versions/{}/restore", Uuid::new_v4()),
            "alice",
            json!({}),
        )
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    lock(&t, project).await;
    let (status, body) = t
        .post(
            &format!(
                "/v1/projects/{project}/versions/{}/restore",
                list[0]["id"].as_str().unwrap()
            ),
            "alice",
            json!({}),
        )
        .await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(body["code"], "document_locked");

    t.cleanup().await;
}

/// Reads a document stream to its `unlocked` event and rebuilds the body the
/// way an editor would: replace on `snapshot`, append on `delta`.
async fn follow_to_unlocked(stream: &mut EventStream) -> (Vec<Value>, String) {
    let events = stream.until("unlocked").await;
    let mut text = String::new();
    for event in &events {
        match event["type"].as_str().unwrap() {
            "snapshot" => text = event["body"].as_str().unwrap().to_string(),
            "delta" => text.push_str(event["text"].as_str().unwrap()),
            _ => {}
        }
    }
    (events, text)
}

#[tokio::test]
async fn an_open_editor_sees_the_essay_as_it_is_written() {
    let t = TestApp::new().await;
    let project = new_project(&t, "alice").await;
    let mut editor = t
        .events(
            &format!("/v1/projects/{project}/document/stream"),
            "alice",
            None,
        )
        .await;
    let first = editor.next().await.unwrap();
    assert_eq!(first["type"], "snapshot");
    assert_eq!(first["locked"], false);
    assert_eq!(first["body"], "");

    let run = start_run(&t, project).await;
    let mut events = t
        .events(&format!("/v1/runs/{run}/events"), "alice", None)
        .await;
    events.until("question").await;
    answer(&t, run, "essayFocus", json!(["Economic impact"])).await;
    events.until("question").await;
    answer(&t, run, "sourceReviewChoice", json!("One Shot")).await;
    events.until("question").await;
    answer(&t, run, "wordCount", json!(500)).await;
    events.until("question").await;
    answer(&t, run, "citationStyle", json!("APA")).await;

    let (seen, text) = follow_to_unlocked(&mut editor).await;
    let seen_kinds = kinds(&seen);
    // The write starts from a locked, empty snapshot; text arrives in pieces,
    // each saved piece is acknowledged, and the final document comes whole.
    assert_eq!(seen[0]["type"], "snapshot");
    assert_eq!(seen[0]["locked"], true);
    assert_eq!(seen[0]["body"], "");
    assert_eq!(seen_kinds.iter().filter(|k| **k == "delta").count(), 5);
    assert_eq!(seen_kinds.iter().filter(|k| **k == "committed").count(), 5);
    let last_snapshot = &seen[seen.len() - 2];
    assert_eq!(last_snapshot["type"], "snapshot");
    assert_eq!(last_snapshot["locked"], false);
    assert_eq!(seen.last().unwrap()["rev"], last_snapshot["rev"]);

    let document = document(&t, project).await;
    assert_eq!(text, document["body"].as_str().unwrap());
    assert_eq!(document["wordCount"], 520);

    // An editor save reaches every open editor as a fresh snapshot.
    let (status, _) = save(
        &t,
        project,
        "alice",
        json!({ "baseRev": document["rev"], "body": "Edited elsewhere." }),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let update = editor.next().await.unwrap();
    assert_eq!(update["type"], "snapshot");
    assert_eq!(update["body"], "Edited elsewhere.");

    // Deleting the project ends the stream.
    t.delete(&format!("/v1/projects/{project}"), "alice").await;
    assert!(editor.next().await.is_none());

    t.cleanup().await;
}

/// An agent run held mid-write: the writer has sent its first chunk and waits
/// on the returned gate.
async fn held_write(release: bool) -> (TestApp, Uuid, Uuid, Arc<Notify>) {
    let gate = Arc::new(Notify::new());
    let mut turns = vec![
        call("plan_essay", json!({})),
        call("generate_outlines", json!({ "count": 5 })),
        call("search_sources", json!({ "count": 5 })),
        call("scrape_sources", json!({})),
        call("compact_sources", json!({})),
        ask("wordCount", json!({ "inputType": "number" })),
        ask("citationStyle", json!({ "inputType": "select" })),
        call("write_essay", json!({})),
    ];
    if release {
        turns.push(call("finalize_document", json!({})));
        turns.push(turn("Ready.", &[]));
    }
    let mut llm = FakeLlm::new(turns);
    llm.hold_writer = Some(gate.clone());
    let t = TestApp::agent(Arc::new(llm), Arc::new(FakeScraper)).await;
    let project = new_project(&t, "alice").await;
    let run = start_run(&t, project).await;

    let mut events = t
        .events(&format!("/v1/runs/{run}/events"), "alice", None)
        .await;
    events.until("question").await;
    answer(&t, run, "wordCount", json!(500)).await;
    events.until("question").await;
    answer(&t, run, "citationStyle", json!("APA")).await;
    events.until("writing_started").await;
    (t, project, run, gate)
}

#[tokio::test]
async fn an_editor_opened_mid_write_catches_up_and_misses_nothing() {
    let (t, project, _run, gate) = held_write(true).await;

    let mut editor = t
        .events(
            &format!("/v1/projects/{project}/document/stream"),
            "alice",
            None,
        )
        .await;
    let first = editor.next().await.unwrap();
    assert_eq!(first["type"], "snapshot");
    assert_eq!(first["locked"], true);
    // Whatever was streamed before the editor opened is in the snapshot.
    assert!(ESSAY.starts_with(first["body"].as_str().unwrap()));

    // The rest of the essay arrives; the editor ends up with what was saved.
    let mut text = first["body"].as_str().unwrap().to_string();
    gate.notify_one();
    let (seen, rebuilt) = follow_to_unlocked(&mut editor).await;
    for event in &seen {
        if event["type"] == "delta" {
            text.push_str(event["text"].as_str().unwrap());
        }
    }
    assert!(!text.contains("BIBLIOGRAPHY"), "the stream is prose only");
    assert_eq!(text.trim_end(), ESSAY);
    assert_eq!(rebuilt, ESSAY);
    assert_eq!(document(&t, project).await["body"], ESSAY);

    t.cleanup().await;
}

#[tokio::test]
async fn cancelling_mid_write_unlocks_an_open_editor() {
    let (t, project, run, _gate) = held_write(false).await;
    let mut editor = t
        .events(
            &format!("/v1/projects/{project}/document/stream"),
            "alice",
            None,
        )
        .await;
    assert_eq!(editor.next().await.unwrap()["locked"], true);

    let (status, _) = t
        .post(&format!("/v1/runs/{run}/cancel"), "alice", json!({}))
        .await;
    assert_eq!(status, StatusCode::OK);

    let (seen, _) = follow_to_unlocked(&mut editor).await;
    assert_eq!(kinds(&seen[seen.len() - 2..]), ["snapshot", "unlocked"]);
    assert_eq!(seen[seen.len() - 2]["locked"], false);

    t.cleanup().await;
}

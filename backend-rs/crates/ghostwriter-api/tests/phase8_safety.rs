//! Phase 8: content checks. A refused task ends the run with a short reply,
//! before anything is spent (the brief), before anything is written (the
//! outline), or before the text is kept (the essay), and is logged.

mod common;

use std::sync::Arc;

use axum::http::StatusCode;
use common::fakes::{self, FakeLlm, FakeScraper, FakeScreen};
use common::{EventStream, TestApp};
use ghostwriter_api::safety::Stage;
use serde_json::{json, Value};
use uuid::Uuid;

async fn app_refusing(stage: Stage, llm: Arc<FakeLlm>) -> TestApp {
    let mut t = TestApp::agent(llm, Arc::new(FakeScraper)).await;
    t.state.screen = Arc::new(FakeScreen(stage));
    t.rebuilt()
}

async fn start(t: &TestApp) -> (Uuid, Uuid, EventStream) {
    let project = Uuid::new_v4();
    let run = Uuid::new_v4();
    t.put(&format!("/v1/projects/{project}"), "alice", json!({}))
        .await;
    let (status, body) = t
        .post(
            &format!("/v1/projects/{project}/runs"),
            "alice",
            json!({ "runId": run, "instruction": "An essay on rising tides" }),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    let events = t
        .events(&format!("/v1/runs/{run}/events"), "alice", None)
        .await;
    (project, run, events)
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

/// The refusal said, then the run done (an answer, not an error).
fn ends_refused(events: &[Value]) {
    let said: Vec<&str> = events
        .iter()
        .filter(|e| e["type"] == "assistant_message")
        .filter_map(|e| e["text"].as_str())
        .collect();
    assert!(
        said.iter().any(|s| s.starts_with("I can't write that one")),
        "{said:?}"
    );
    assert_eq!(events.last().unwrap()["type"], "done");
}

async fn logged(t: &TestApp, run: Uuid) -> Vec<(String, String)> {
    sqlx::query_as("SELECT stage, category FROM safety_events WHERE run_id = $1")
        .bind(run)
        .fetch_all(&t.state.db)
        .await
        .unwrap()
}

/// Whether the run charged for the essay itself.
fn spent(events: &[Value]) -> bool {
    events
        .iter()
        .any(|e| e["type"] == "credits" && e["reason"] == "Essay generation")
}

#[tokio::test]
async fn a_refused_brief_spends_nothing() {
    let llm = Arc::new(FakeLlm::new(fakes::full_script()));
    let t = app_refusing(Stage::Task, llm.clone()).await;
    let (project, run, mut events) = start(&t).await;
    let events = events.rest().await;

    ends_refused(&events);
    assert!(llm.orchestrator_requests.lock().unwrap().is_empty());
    assert!(!spent(&events));
    assert_eq!(logged(&t, run).await, [("task".into(), "illicit".into())]);
    // Nothing was written, so the project is not shown as a ready essay.
    let (_, body) = t.get(&format!("/v1/projects/{project}"), "alice").await;
    assert_eq!(body["status"], "idle", "{body}");
}

#[tokio::test]
async fn a_refused_outline_stops_before_writing() {
    let llm = Arc::new(FakeLlm::new(fakes::full_script()));
    let t = app_refusing(Stage::Outline, llm.clone()).await;
    let (_, run, mut stream) = start(&t).await;
    let mut events = stream.until("question").await;
    answer(&t, run, "essayFocus", json!(["Economic impact"])).await;
    events.extend(stream.rest().await);

    ends_refused(&events);
    assert!(!events
        .iter()
        .any(|e| e["type"] == "step_start" && e["tool"] == "write_essay"));
    assert!(llm.stream_requests.lock().unwrap().is_empty());
    assert_eq!(
        logged(&t, run).await,
        [("outline".into(), "illicit".into())]
    );
}

#[tokio::test]
async fn a_refused_essay_is_not_kept_or_charged() {
    let llm = Arc::new(FakeLlm::new(fakes::full_script()));
    let t = app_refusing(Stage::Output, llm.clone()).await;
    let (project, run, mut stream) = start(&t).await;
    let mut events = stream.until("question").await;
    answer(&t, run, "essayFocus", json!(["Economic impact"])).await;
    events.extend(stream.until("question").await);
    answer(&t, run, "wordCount", json!(800)).await;
    events.extend(stream.until("question").await);
    answer(&t, run, "citationStyle", json!("MLA")).await;
    events.extend(stream.rest().await);

    ends_refused(&events);
    assert!(!spent(&events), "the write is not charged");
    let (_, doc) = t
        .get(&format!("/v1/projects/{project}/document"), "alice")
        .await;
    assert_eq!(doc["body"], "", "{doc}");
    assert_eq!(logged(&t, run).await, [("output".into(), "illicit".into())]);
}

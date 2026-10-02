//! Phase 4: revisions. A run on a project whose essay is written revises the
//! document as it stands, instead of starting a new essay.

mod common;

use std::sync::Arc;

use axum::http::StatusCode;
use common::fakes::{self, call, turn, FakeLlm, FakeScraper, BIBLIOGRAPHY, ESSAY};
use common::{kinds, TestApp};
use serde_json::{json, Value};
use uuid::Uuid;

const REVISED: &str = "Coastal cities live by the tide (Sweet, 2022).\n\n\
    Rising seas raise every high tide.\n\n\
    The cities that cope will plan for the tide to come.";

async fn start(t: &TestApp, project: Uuid, instruction: &str) -> Uuid {
    let run = Uuid::new_v4();
    let (status, body) = t
        .post(
            &format!("/v1/projects/{project}/runs"),
            "alice",
            json!({ "runId": run, "instruction": instruction }),
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

/// Writes the full scripted agent essay into a new project.
async fn written_by_agent(t: &TestApp) -> Uuid {
    let project = Uuid::new_v4();
    t.put(&format!("/v1/projects/{project}"), "alice", json!({}))
        .await;
    let run = start(t, project, "An essay on rising tides").await;
    let mut events = t
        .events(&format!("/v1/runs/{run}/events"), "alice", None)
        .await;
    events.until("question").await;
    answer(t, run, "essayFocus", json!(["Economic impact"])).await;
    events.until("question").await;
    answer(t, run, "wordCount", json!(800)).await;
    events.until("question").await;
    answer(t, run, "citationStyle", json!("MLA")).await;
    events.until("question").await;
    answer(t, run, "studentName", json!("Ada Lovelace")).await;
    assert_eq!(events.rest().await.last().unwrap()["type"], "done");
    project
}

async fn run_to_end(t: &TestApp, run: Uuid) -> Vec<Value> {
    t.events(&format!("/v1/runs/{run}/events"), "alice", None)
        .await
        .rest()
        .await
}

fn of_kind<'a>(events: &'a [Value], kind: &str) -> Vec<&'a Value> {
    events.iter().filter(|e| e["type"] == kind).collect()
}

#[tokio::test]
async fn a_change_request_revises_the_essay_in_place() {
    let mut turns = fakes::full_script();
    turns.push(call(
        "revise_essay",
        json!({ "instructions": "Shorten paragraph 2." }),
    ));
    turns.push(turn("Paragraph 2 is shorter now.", &[]));
    let llm = Arc::new(FakeLlm::new(turns));
    let t = TestApp::agent(llm.clone(), Arc::new(FakeScraper)).await;
    let project = written_by_agent(&t).await;

    *llm.essay_output.lock().unwrap() = format!("{REVISED}\n===BIBLIOGRAPHY===\n{BIBLIOGRAPHY}");
    let run = start(&t, project, "Shorten paragraph 2").await;
    let events = run_to_end(&t, run).await;

    let steps: Vec<&str> = of_kind(&events, "step_start")
        .iter()
        .map(|e| e["tool"].as_str().unwrap())
        .collect();
    assert_eq!(steps, ["revise_essay"], "{:#?}", kinds(&events));
    assert_eq!(
        of_kind(&events, "step_done")[0]["summary"],
        "Revised · 25 words."
    );
    // The progress bar measures against the essay as it was.
    assert_eq!(of_kind(&events, "writing_started")[0]["targetWords"], 28);
    assert_eq!(of_kind(&events, "credits")[0]["reason"], "Essay revision");
    assert_eq!(events.last().unwrap()["type"], "done");

    // The model saw the revision prompt, its two tools, and the numbered essay.
    let request = llm
        .orchestrator_requests
        .lock()
        .unwrap()
        .last()
        .unwrap()
        .clone();
    let tools: Vec<&str> = request
        .tools
        .iter()
        .map(|t| t["function"]["name"].as_str().unwrap())
        .collect();
    assert_eq!(tools, ["revise_essay", "ask_user"]);
    let brief = request.messages[1]["content"].as_str().unwrap();
    assert!(brief.starts_with("USER REQUEST\nShorten paragraph 2"));
    assert!(brief.contains("[2] Rising seas raise every ordinary high tide"));

    // The document has the revision; title, style and fields are untouched.
    let (_, document) = t
        .get(&format!("/v1/projects/{project}/document"), "alice")
        .await;
    assert_eq!(document["body"], REVISED);
    assert_eq!(document["bibliography"], BIBLIOGRAPHY);
    assert_eq!(document["style"], "mla");
    assert_eq!(document["fields"]["studentName"], "Ada Lovelace");
    assert_eq!(document["locked"], false);

    // What it replaced is kept, so the revision can be undone.
    let (_, list) = t
        .get(&format!("/v1/projects/{project}/versions"), "alice")
        .await;
    let latest = &list["versions"][0];
    assert_eq!(latest["reason"], "agent_revise");
    assert_eq!(latest["wordCount"], 28);
    assert!(latest["preview"]
        .as_str()
        .unwrap()
        .starts_with(&ESSAY[..20]));

    // Both runs are there to replay.
    let (_, state) = t.get(&format!("/v1/projects/{project}"), "alice").await;
    assert_eq!(state["runIds"].as_array().unwrap().len(), 2);
    assert_eq!(state["lastRunId"], run.to_string());

    t.cleanup().await;
}

#[tokio::test]
async fn a_question_about_the_essay_is_answered_without_touching_it() {
    let mut turns = fakes::full_script();
    turns.push(turn("Paragraph 2 explains why every high tide rises.", &[]));
    let llm = Arc::new(FakeLlm::new(turns));
    let t = TestApp::agent(llm, Arc::new(FakeScraper)).await;
    let project = written_by_agent(&t).await;
    let (_, before) = t
        .get(&format!("/v1/projects/{project}/document"), "alice")
        .await;

    let run = start(&t, project, "What is paragraph 2 about?").await;
    let events = run_to_end(&t, run).await;

    assert_eq!(
        kinds(&events)
            .into_iter()
            .filter(|k| *k != "assistant_delta")
            .collect::<Vec<_>>(),
        ["user_message", "assistant_message", "done"]
    );
    let (_, after) = t
        .get(&format!("/v1/projects/{project}/document"), "alice")
        .await;
    assert_eq!(after["rev"], before["rev"]);

    t.cleanup().await;
}

#[tokio::test]
async fn the_scripted_driver_revises_too() {
    let t = TestApp::new().await;
    let project = Uuid::new_v4();
    t.put(&format!("/v1/projects/{project}"), "alice", json!({}))
        .await;
    let first = start(&t, project, "An essay on tides").await;
    let mut events = t
        .events(&format!("/v1/runs/{first}/events"), "alice", None)
        .await;
    events.until("question").await;
    answer(&t, first, "essayFocus", json!(["Economic impact"])).await;
    events.until("question").await;
    answer(&t, first, "sourceReviewChoice", json!("One Shot")).await;
    events.until("question").await;
    answer(&t, first, "wordCount", json!(500)).await;
    events.until("question").await;
    answer(&t, first, "citationStyle", json!("APA")).await;
    events.rest().await;

    let run = start(&t, project, "Make the ending stronger").await;
    let events = run_to_end(&t, run).await;
    assert_eq!(of_kind(&events, "step_start")[0]["tool"], "revise_essay");
    assert_eq!(events.last().unwrap()["type"], "done");

    let (_, document) = t
        .get(&format!("/v1/projects/{project}/document"), "alice")
        .await;
    assert!(document["body"]
        .as_str()
        .unwrap()
        .ends_with("Revision note: Make the ending stronger"));
    let (_, list) = t
        .get(&format!("/v1/projects/{project}/versions"), "alice")
        .await;
    assert_eq!(list["versions"][0]["reason"], "agent_revise");

    t.cleanup().await;
}

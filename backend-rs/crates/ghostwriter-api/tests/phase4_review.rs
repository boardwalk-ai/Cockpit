//! Phase 4: judging the sources before writing, reviewing the written essay,
//! and Ask Octo.

mod common;

use std::sync::Arc;

use axum::http::StatusCode;
use common::fakes::{self, call, turn, FakeLlm, FakeScraper};
use common::{kinds, TestApp};
use ghostwriter_api::llm::ChatReply;
use serde_json::{json, Value};
use uuid::Uuid;

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

/// Runs the first essay to its end and returns the project and its events.
async fn write(t: &TestApp) -> (Uuid, Vec<Value>) {
    let project = Uuid::new_v4();
    t.put(&format!("/v1/projects/{project}"), "alice", json!({}))
        .await;
    let run = start(t, project, "An essay on rising tides").await;
    let mut events = t
        .events(&format!("/v1/runs/{run}/events"), "alice", None)
        .await;
    let mut seen = events.until("question").await;
    answer(t, run, "essayFocus", json!(["Economic impact"])).await;
    seen.extend(events.until("question").await);
    answer(t, run, "wordCount", json!(800)).await;
    seen.extend(events.until("question").await);
    answer(t, run, "citationStyle", json!("MLA")).await;
    seen.extend(events.until("question").await);
    answer(t, run, "studentName", json!("Ada Lovelace")).await;
    seen.extend(events.rest().await);
    assert_eq!(seen.last().unwrap()["type"], "done", "{:#?}", kinds(&seen));
    (project, seen)
}

/// The full script with `extra` turns right after `compact_sources`.
fn with_evaluation(extra: Vec<ChatReply>) -> Vec<ChatReply> {
    let mut turns = fakes::full_script();
    let at = 6; // after compact_sources
    for (offset, reply) in extra.into_iter().enumerate() {
        turns.insert(at + offset, reply);
    }
    turns
}

/// The `step_done` summaries of `tool`, in order.
fn summaries(events: &[Value], tool: &str) -> Vec<String> {
    let steps: Vec<&Value> = events
        .iter()
        .filter(|e| e["type"] == "step_start" && e["tool"] == tool)
        .collect();
    steps
        .iter()
        .map(|step| {
            events
                .iter()
                .find(|e| e["type"] == "step_done" && e["stepId"] == step["stepId"])
                .unwrap_or_else(|| panic!("{tool} did not finish"))["summary"]
                .as_str()
                .unwrap()
                .to_string()
        })
        .collect()
}

#[tokio::test]
async fn sources_that_cover_the_essay_go_straight_to_writing() {
    let llm = Arc::new(FakeLlm::new(with_evaluation(vec![call(
        "evaluate_sources",
        json!({}),
    )])));
    let t = TestApp::agent(llm.clone(), Arc::new(FakeScraper)).await;
    let (_, events) = write(&t).await;

    let done = summaries(&events, "evaluate_sources");
    assert_eq!(done.len(), 1);
    assert!(done[0].ends_with("sources cover the essay."), "{done:?}");

    // The evaluator was shown the topic, the outline and the summaries.
    let asked = llm
        .sub_requests
        .lock()
        .unwrap()
        .iter()
        .find(|r| {
            r.messages[0]["content"]
                .as_str()
                .unwrap()
                .contains("research quality evaluator")
        })
        .unwrap()
        .messages[1]["content"]
        .as_str()
        .unwrap()
        .to_string();
    assert!(asked.starts_with("Essay topic: Rising Tides and Coastal Cities"));
    assert!(asked.contains("- Introduction: The tide line moves"));
    assert!(asked.contains("Source 1: "));
    assert!(llm.last_transcript().contains(r#"\"searchAgain\":false"#));

    t.cleanup().await;
}

#[tokio::test]
async fn thin_sources_ask_for_one_more_search_and_only_one() {
    let llm = Arc::new(FakeLlm::new(with_evaluation(vec![
        call("evaluate_sources", json!({})),
        call("evaluate_sources", json!({ "notes": "second look" })),
    ])));
    *llm.evaluation.lock().unwrap() = Some(
        json!({
            "sufficient": false,
            "quality": "terrible",
            "gaps": ["What flooding costs"],
            "recommendation": "flood insurance claims data",
        })
        .to_string(),
    );
    let t = TestApp::agent(llm.clone(), Arc::new(FakeScraper)).await;
    let (_, events) = write(&t).await;

    assert_eq!(
        summaries(&events, "evaluate_sources"),
        [
            "The sources leave gaps. Looking for more.",
            "The sources leave some gaps. Writing with what we have.",
        ]
    );
    let transcript = llm.last_transcript();
    assert!(transcript.contains(r#"\"searchAgain\":true"#));
    assert!(transcript.contains("flood insurance claims data"));
    // A quality the evaluator made up is not passed on.
    assert!(transcript.contains(r#"\"quality\":\"fair\""#));

    t.cleanup().await;
}

#[tokio::test]
async fn an_evaluator_that_fails_does_not_stop_the_essay() {
    let llm = Arc::new(FakeLlm::new(with_evaluation(vec![call(
        "evaluate_sources",
        json!({}),
    )])));
    *llm.evaluation.lock().unwrap() = Some("I cannot answer in JSON today.".to_string());
    let t = TestApp::agent(llm, Arc::new(FakeScraper)).await;
    let (_, events) = write(&t).await;

    assert_eq!(summaries(&events, "evaluate_sources").len(), 1);
    assert!(!kinds(&events).contains(&"step_error"));

    t.cleanup().await;
}

#[tokio::test]
async fn a_review_lists_the_issues_and_leaves_the_essay_alone() {
    let mut turns = fakes::full_script();
    turns.push(call("critique_essay", json!({})));
    turns.push(turn("Paragraph 2 leans on one source.", &[]));
    let llm = Arc::new(FakeLlm::new(turns));
    let t = TestApp::agent(llm.clone(), Arc::new(FakeScraper)).await;
    let (project, _) = write(&t).await;
    let (_, before) = t
        .get(&format!("/v1/projects/{project}/document"), "alice")
        .await;

    let run = start(&t, project, "Review my essay").await;
    let events = t
        .events(&format!("/v1/runs/{run}/events"), "alice", None)
        .await
        .rest()
        .await;

    assert_eq!(
        summaries(&events, "critique_essay"),
        ["2 things to fix, 1 important."]
    );
    // Issues with no such paragraph, or nothing to say, are dropped; an
    // unknown type becomes "clarity".
    let update = events
        .iter()
        .find(|e| e["type"] == "context_update")
        .unwrap();
    assert_eq!(
        update["critiqueIssues"],
        json!([
            { "paragraph": 2, "type": "evidence", "description": "The claim has one source.", "major": true },
            { "paragraph": 3, "type": "clarity", "description": "The ending is abrupt.", "major": false },
        ])
    );
    // The model gets the issues back to talk about.
    assert!(llm.last_transcript().contains("The ending is abrupt."));

    // A review is free and changes nothing.
    assert!(!kinds(&events).contains(&"credits"));
    assert!(!kinds(&events).contains(&"document_updated"));
    let (_, after) = t
        .get(&format!("/v1/projects/{project}/document"), "alice")
        .await;
    assert_eq!(after["rev"], before["rev"]);
    assert_eq!(after["locked"], false);
    let (_, list) = t
        .get(&format!("/v1/projects/{project}/versions"), "alice")
        .await;
    assert!(list["versions"]
        .as_array()
        .unwrap()
        .iter()
        .all(|v| v["reason"] != "agent_revise"));

    t.cleanup().await;
}

#[tokio::test]
async fn octo_answers_a_question_about_the_app() {
    let llm = Arc::new(FakeLlm::new(Vec::new()));
    let t = TestApp::agent(llm.clone(), Arc::new(FakeScraper)).await;

    let (status, body) = t
        .post(
            "/v1/octo/ask",
            "alice",
            json!({ "question": "  Where is my essay?  " }),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["answer"], "Tap the Open Editor pill at the top right.");
    {
        let requests = llm.sub_requests.lock().unwrap();
        assert_eq!(requests.len(), 1);
        assert_eq!(requests[0].messages[1]["content"], "Where is my essay?");
    }

    let (status, _) = t
        .post("/v1/octo/ask", "alice", json!({ "question": "   " }))
        .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    let (status, _) = t
        .post(
            "/v1/octo/ask",
            "alice",
            json!({ "question": "a".repeat(501) }),
        )
        .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(llm.sub_requests.lock().unwrap().len(), 1);

    t.cleanup().await;
}

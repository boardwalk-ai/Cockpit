//! Phase 4: humanizing the written essay, and restoring its paragraphs.

mod common;

use std::sync::Arc;

use axum::http::StatusCode;
use common::fakes::{self, ask, call, turn, FakeHumanizer, FakeLlm, BIBLIOGRAPHY, ESSAY};
use common::{kinds, EventStream, TestApp};
use ghostwriter_api::humanize::{HttpHumanizer, Provider};
use ghostwriter_api::llm::ChatReply;
use serde_json::{json, Value};
use uuid::Uuid;

/// The essay after the fake humanizer: one phrase reworded.
fn humanized() -> String {
    ESSAY.replace("Coastal cities", "Seaside towns")
}

/// The same, as StealthGPT returns it: one block of text.
fn merged() -> String {
    humanized().replace("\n\n", " ")
}

fn humanizer_question() -> ChatReply {
    ask(
        "humanizerChoice",
        json!({ "inputType": "select", "options": [
            { "label": "StealthGPT", "value": "StealthGPT" },
            { "label": "UndetectableAI", "value": "UndetectableAI" },
            { "label": "Skip", "value": "Skip" },
        ]}),
    )
}

/// The whole first run up to the delivered essay, then `after`.
fn script(after: Vec<ChatReply>) -> Vec<ChatReply> {
    let mut turns = fakes::full_script();
    turns.pop(); // the closing sentence; the humanizer step comes first
    turns.extend(after);
    turns
}

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

/// Starts a first run and answers up to the title page; the next question is
/// the humanizer's.
async fn to_the_humanizer_question(t: &TestApp) -> (Uuid, Uuid, EventStream, Vec<Value>) {
    let project = Uuid::new_v4();
    t.put(&format!("/v1/projects/{project}"), "alice", json!({}))
        .await;
    let run = start(t, project, "An essay on rising tides").await;
    let mut events = t
        .events(&format!("/v1/runs/{run}/events"), "alice", None)
        .await;
    let mut seen = events.until("question").await;
    for (field, value) in [
        ("essayFocus", json!(["Economic impact"])),
        ("wordCount", json!(800)),
        ("citationStyle", json!("APA")),
        ("studentName", json!("Ada Lovelace")),
    ] {
        answer(t, run, field, value).await;
        seen.extend(events.until("question").await);
    }
    assert_eq!(seen.last().unwrap()["field"], "humanizerChoice");
    (project, run, events, seen)
}

async fn document(t: &TestApp, project: Uuid) -> Value {
    let (status, body) = t
        .get(&format!("/v1/projects/{project}/document"), "alice")
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    body
}

async fn version_reasons(t: &TestApp, project: Uuid) -> Vec<String> {
    sqlx::query_scalar(
        "SELECT reason FROM document_versions WHERE project_id = $1 ORDER BY created_at, rev",
    )
    .bind(project)
    .fetch_all(&t.state.db)
    .await
    .unwrap()
}

async fn balance(t: &TestApp) -> Value {
    t.get("/v1/me", "alice").await.1["octoCredits"].clone()
}

fn of_kind<'a>(events: &'a [Value], kind: &str) -> Vec<&'a Value> {
    events.iter().filter(|e| e["type"] == kind).collect()
}

#[tokio::test]
async fn the_essay_is_humanized_in_place_and_can_be_undone() {
    let llm = Arc::new(FakeLlm::new(script(vec![
        humanizer_question(),
        call("humanize_essay", json!({ "provider": "UndetectableAI" })),
        turn("Humanized and ready in the editor.", &[]),
    ])));
    let humanizer = Arc::new(FakeHumanizer::default());
    let t = TestApp::agent_with_humanizer(llm.clone(), humanizer.clone()).await;
    let (project, run, mut events, _) = to_the_humanizer_question(&t).await;

    // The essay is delivered before the humanizer is offered.
    let before = document(&t, project).await;
    assert_eq!(before["body"], ESSAY);

    answer(&t, run, "humanizerChoice", json!("UndetectableAI")).await;
    let ending = events.rest().await;

    let step = of_kind(&ending, "step_start")[0];
    assert_eq!(step["tool"], "humanize_essay");
    assert_eq!(step["title"], "Humanizing with UndetectableAI");
    assert_eq!(
        of_kind(&ending, "step_done")[0]["summary"],
        "Humanized with UndetectableAI · 28 words."
    );
    assert!(of_kind(&ending, "step_error").is_empty());
    assert_eq!(ending.last().unwrap()["type"], "done");

    // The humanizer was given the essay, not the bibliography.
    assert_eq!(
        *humanizer.calls.lock().unwrap(),
        [(Provider::Undetectable, ESSAY.to_string())]
    );

    // The document holds the humanized essay; the rest is as it was.
    let after = document(&t, project).await;
    assert_eq!(after["body"], humanized());
    assert_eq!(after["bibliography"], BIBLIOGRAPHY);
    assert_eq!(after["fields"], before["fields"]);
    assert_eq!(after["locked"], false);
    assert_eq!(
        of_kind(&ending, "document_updated").last().unwrap()["rev"],
        after["rev"]
    );

    // The essay as it was is kept as a version.
    assert_eq!(
        version_reasons(&t, project).await,
        ["agent_write", "agent_write", "humanize"]
    );
    let kept: String = sqlx::query_scalar(
        "SELECT snapshot->>'body' FROM document_versions \
         WHERE project_id = $1 AND reason = 'humanize'",
    )
    .bind(project)
    .fetch_one(&t.state.db)
    .await
    .unwrap();
    assert_eq!(kept, ESSAY);

    // Charged once, at the humanizing rate: 100 OC on top of research and writing.
    let charge = of_kind(&ending, "credits")[0];
    assert_eq!(charge["reason"], "Humanizing");
    assert_eq!(charge["charged"], 100);
    assert_eq!(balance(&t).await, 9_700);

    // The model was told the paragraphs survived, so it did not offer a split.
    assert!(llm
        .last_transcript()
        .contains("\\\"paragraphsMerged\\\":false"));

    t.cleanup().await;
}

#[tokio::test]
async fn skipping_the_humanizer_leaves_the_essay_alone() {
    let llm = Arc::new(FakeLlm::new(script(vec![
        humanizer_question(),
        turn("Your essay is ready in the editor.", &[]),
    ])));
    let humanizer = Arc::new(FakeHumanizer::default());
    let t = TestApp::agent_with_humanizer(llm, humanizer.clone()).await;
    let (project, run, mut events, _) = to_the_humanizer_question(&t).await;

    answer(&t, run, "humanizerChoice", json!("Skip")).await;
    let ending = events.rest().await;

    assert!(of_kind(&ending, "step_start").is_empty());
    assert_eq!(ending.last().unwrap()["type"], "done");
    assert!(humanizer.calls.lock().unwrap().is_empty());
    assert_eq!(document(&t, project).await["body"], ESSAY);
    assert_eq!(balance(&t).await, 9_800);

    t.cleanup().await;
}

#[tokio::test]
async fn merged_paragraphs_are_restored_without_changing_a_word() {
    let llm = Arc::new(FakeLlm::new(script(vec![
        humanizer_question(),
        call("humanize_essay", json!({ "provider": "StealthGPT" })),
        ask(
            "paragraphSplitChoice",
            json!({ "inputType": "select", "options": [
                { "label": "Restore paragraphs", "value": "AI split" },
                { "label": "Leave as is", "value": "Skip split" },
            ]}),
        ),
        call("split_paragraphs", json!({})),
        turn("Humanized, with its paragraphs back.", &[]),
    ])));
    let t = TestApp::agent_with_humanizer(llm.clone(), Arc::new(FakeHumanizer::default())).await;
    let (project, run, mut events, _) = to_the_humanizer_question(&t).await;

    answer(&t, run, "humanizerChoice", json!("StealthGPT")).await;
    let humanizing = events.until("question").await;
    assert_eq!(humanizing.last().unwrap()["field"], "paragraphSplitChoice");
    assert_eq!(
        of_kind(&humanizing, "step_start")[0]["title"],
        "Humanizing with StealthGPT"
    );

    // StealthGPT returned one block, and the model was told so.
    assert_eq!(document(&t, project).await["body"], merged());
    assert!(llm
        .last_transcript()
        .contains("\\\"paragraphsMerged\\\":true"));

    answer(&t, run, "paragraphSplitChoice", json!("AI split")).await;
    let ending = events.rest().await;
    assert_eq!(
        of_kind(&ending, "step_done")[0]["summary"],
        "3 paragraphs restored."
    );

    // Three paragraphs again, with the humanizer's wording untouched.
    let after = document(&t, project).await;
    assert_eq!(after["body"], humanized());
    assert_eq!(after["locked"], false);

    // Each rewrite kept a version; the split is not charged.
    assert_eq!(
        version_reasons(&t, project).await,
        ["agent_write", "agent_write", "humanize", "humanize"]
    );
    assert_eq!(balance(&t).await, 9_700);

    t.cleanup().await;
}

#[tokio::test]
async fn a_split_that_changes_the_wording_is_thrown_away() {
    let llm = FakeLlm::new(script(vec![
        humanizer_question(),
        call("humanize_essay", json!({ "provider": "StealthGPT" })),
        call("split_paragraphs", json!({})),
        turn("I could not restore the paragraphs.", &[]),
    ]));
    *llm.careless_splitter.lock().unwrap() = true;
    let t = TestApp::agent_with_humanizer(Arc::new(llm), Arc::new(FakeHumanizer::default())).await;
    let (project, run, mut events, _) = to_the_humanizer_question(&t).await;

    answer(&t, run, "humanizerChoice", json!("StealthGPT")).await;
    let ending = events.rest().await;

    let errors = of_kind(&ending, "step_error");
    assert_eq!(errors.len(), 1, "{:#?}", kinds(&ending));
    assert_eq!(
        errors[0]["error"],
        "the split changed the wording, so the essay was left as it was"
    );

    // The humanized block is still there, word for word, and not locked.
    let after = document(&t, project).await;
    assert_eq!(after["body"], merged());
    assert_eq!(after["locked"], false);

    t.cleanup().await;
}

#[tokio::test]
async fn a_humanizer_that_fails_leaves_the_essay_and_the_balance_alone() {
    let llm = Arc::new(FakeLlm::new(script(vec![
        humanizer_question(),
        call("humanize_essay", json!({ "provider": "StealthGPT" })),
        turn("The humanizer is not working right now.", &[]),
    ])));
    let humanizer = Arc::new(FakeHumanizer::default());
    *humanizer.fail.lock().unwrap() = Some("StealthGPT refused the request (402).".into());
    let t = TestApp::agent_with_humanizer(llm.clone(), humanizer).await;
    let (project, run, mut events, _) = to_the_humanizer_question(&t).await;

    answer(&t, run, "humanizerChoice", json!("StealthGPT")).await;
    let ending = events.rest().await;

    assert_eq!(
        of_kind(&ending, "step_error")[0]["error"],
        "StealthGPT refused the request (402)."
    );
    assert!(llm.last_transcript().contains("refused the request"));
    assert!(of_kind(&ending, "credits").is_empty());

    let after = document(&t, project).await;
    assert_eq!(after["body"], ESSAY);
    assert_eq!(after["locked"], false);
    assert_eq!(balance(&t).await, 9_800);
    // The run still ends properly: the essay was delivered before this.
    assert_eq!(ending.last().unwrap()["type"], "done");

    t.cleanup().await;
}

#[tokio::test]
async fn a_humanizer_with_no_key_says_so_plainly() {
    let llm = Arc::new(FakeLlm::new(script(vec![
        humanizer_question(),
        call("humanize_essay", json!({ "provider": "UndetectableAI" })),
        call("humanize_essay", json!({ "provider": "Grammarly" })),
        turn("Humanizing is not available right now.", &[]),
    ])));
    let mut t = TestApp::agent_with_humanizer(llm, Arc::new(FakeHumanizer::default())).await;
    // The real client, against a settings table that holds no keys.
    t.state.humanizer = Arc::new(HttpHumanizer::new(
        t.state.http.clone(),
        t.state.octopilot.clone(),
    ));
    t.app = ghostwriter_api::app(t.state.clone());
    let (project, run, mut events, _) = to_the_humanizer_question(&t).await;

    answer(&t, run, "humanizerChoice", json!("UndetectableAI")).await;
    let ending = events.rest().await;

    let errors: Vec<&str> = of_kind(&ending, "step_error")
        .iter()
        .map(|e| e["error"].as_str().unwrap())
        .collect();
    assert_eq!(
        errors,
        [
            "UndetectableAI is not available right now.",
            "unknown humanizer \"Grammarly\"; use StealthGPT or UndetectableAI",
        ]
    );
    assert_eq!(document(&t, project).await["locked"], false);

    t.cleanup().await;
}

#[tokio::test]
async fn a_later_request_humanizes_the_essay_as_the_user_left_it() {
    let mut turns = fakes::full_script();
    turns.extend([
        call("humanize_essay", json!({ "provider": "UndetectableAI" })),
        turn("Humanized.", &[]),
    ]);
    let humanizer = Arc::new(FakeHumanizer::default());
    let t = TestApp::agent_with_humanizer(Arc::new(FakeLlm::new(turns)), humanizer.clone()).await;

    // A first run that delivers the essay with no humanizer step.
    let project = Uuid::new_v4();
    t.put(&format!("/v1/projects/{project}"), "alice", json!({}))
        .await;
    let first = start(&t, project, "An essay on rising tides").await;
    let mut events = t
        .events(&format!("/v1/runs/{first}/events"), "alice", None)
        .await;
    events.until("question").await;
    for (field, value) in [
        ("essayFocus", json!(["Economic impact"])),
        ("wordCount", json!(800)),
        ("citationStyle", json!("APA")),
        ("studentName", json!("Ada Lovelace")),
    ] {
        answer(&t, first, field, value).await;
        if field != "studentName" {
            events.until("question").await;
        }
    }
    assert_eq!(events.rest().await.last().unwrap()["type"], "done");

    // The user edits the essay in the editor.
    let rev = document(&t, project).await["rev"].clone();
    let edited = "Coastal cities, edited by me.\n\nA second paragraph of my own.";
    let (status, body) = t
        .put(
            &format!("/v1/projects/{project}/document"),
            "alice",
            json!({ "baseRev": rev, "body": edited }),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");

    // Then asks for it to be humanized.
    let second = start(&t, project, "Humanize it with UndetectableAI").await;
    let ending = t
        .events(&format!("/v1/runs/{second}/events"), "alice", None)
        .await
        .rest()
        .await;

    let steps: Vec<&str> = of_kind(&ending, "step_start")
        .iter()
        .map(|e| e["tool"].as_str().unwrap())
        .collect();
    assert_eq!(steps, ["humanize_essay"], "{:#?}", kinds(&ending));
    // Not a rewrite by the writer: no progress bar.
    assert!(of_kind(&ending, "writing_started").is_empty());

    // The humanizer got the user's version, and the document has its result.
    assert_eq!(humanizer.calls.lock().unwrap().last().unwrap().1, edited);
    assert_eq!(
        document(&t, project).await["body"],
        "Seaside towns, edited by me.\n\nA second paragraph of my own."
    );

    t.cleanup().await;
}

#[tokio::test]
async fn the_scripted_driver_walks_the_humanizer_step_too() {
    let t = TestApp::with(|config| config.scripted_humanizer = true).await;
    let project = Uuid::new_v4();
    t.put(&format!("/v1/projects/{project}"), "alice", json!({}))
        .await;
    let run = start(&t, project, "An essay on rising tides").await;
    let mut events = t
        .events(&format!("/v1/runs/{run}/events"), "alice", None)
        .await;
    events.until("question").await;
    for (field, value) in [
        ("essayFocus", json!(["Economic impact"])),
        ("sourceReviewChoice", json!("One Shot")),
        ("wordCount", json!(500)),
        ("citationStyle", json!("APA")),
    ] {
        answer(&t, run, field, value).await;
        events.until("question").await;
    }
    let written = document(&t, project).await["body"]
        .as_str()
        .unwrap()
        .to_string();
    assert!(written.contains("\n\n"));

    // StealthGPT merges the paragraphs, so the run asks about restoring them.
    answer(&t, run, "humanizerChoice", json!("StealthGPT")).await;
    let humanizing = events.until("question").await;
    assert_eq!(humanizing.last().unwrap()["field"], "paragraphSplitChoice");
    let step = of_kind(&humanizing, "step_start")[0];
    assert_eq!(step["title"], "Humanizing with StealthGPT");
    assert_eq!(
        step["stepId"],
        of_kind(&humanizing, "step_done")[0]["stepId"]
    );
    assert!(!document(&t, project).await["body"]
        .as_str()
        .unwrap()
        .contains("\n\n"));

    answer(&t, run, "paragraphSplitChoice", json!("AI split")).await;
    let ending = events.rest().await;
    assert_eq!(ending.last().unwrap()["type"], "done");
    let after = document(&t, project).await;
    assert_eq!(after["body"], written);
    assert_eq!(after["locked"], false);

    t.cleanup().await;
}

//! Phase 1c: the agent loop and its tools, with the model and the scraper
//! replaced by test doubles.

mod common;

use std::sync::Arc;

use axum::http::StatusCode;
use common::fakes::{self, ask, call, turn, FakeLlm, FakeScraper, BIBLIOGRAPHY, ESSAY};
use common::{kinds, EventStream, TestApp};
use ghostwriter_api::llm::{ChatReply, ToolCall};
use serde_json::{json, Value};
use tokio::sync::Notify;
use uuid::Uuid;

async fn app_with(llm: Arc<FakeLlm>) -> TestApp {
    TestApp::agent(llm, Arc::new(FakeScraper)).await
}

async fn start_run(t: &TestApp, user: &str) -> (Uuid, Uuid) {
    let project = Uuid::new_v4();
    let run = Uuid::new_v4();
    t.put(&format!("/v1/projects/{project}"), user, json!({}))
        .await;
    let (status, body) = t
        .post(
            &format!("/v1/projects/{project}/runs"),
            user,
            json!({ "runId": run, "instruction": "An essay on rising tides" }),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    (project, run)
}

async fn answer(t: &TestApp, user: &str, run: Uuid, field: &str, value: Value) {
    let (status, body) = t
        .post(
            &format!("/v1/runs/{run}/answer"),
            user,
            json!({ "field": field, "value": value }),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
}

async fn stream(t: &TestApp, user: &str, run: Uuid) -> EventStream {
    t.events(&format!("/v1/runs/{run}/events"), user, None)
        .await
}

fn of_kind<'a>(events: &'a [Value], kind: &str) -> Vec<&'a Value> {
    events.iter().filter(|e| e["type"] == kind).collect()
}

/// Walks the full script, answering each question, and returns every event.
async fn run_to_the_end(t: &TestApp, run: Uuid) -> Vec<Value> {
    let mut events = stream(t, "alice", run).await;
    let mut seen = events.until("question").await;
    answer(
        t,
        "alice",
        run,
        "essayFocus",
        json!(["Economic impact", "Policy responses"]),
    )
    .await;
    seen.extend(events.until("question").await);
    answer(t, "alice", run, "wordCount", json!(800)).await;
    seen.extend(events.until("question").await);
    answer(t, "alice", run, "citationStyle", json!("MLA")).await;
    seen.extend(events.until("question").await);
    answer(t, "alice", run, "studentName", json!("Ada Lovelace")).await;
    seen.extend(events.rest().await);
    seen
}

#[tokio::test]
async fn the_agent_takes_a_brief_to_a_delivered_essay() {
    let llm = Arc::new(FakeLlm::new(fakes::full_script()));
    let t = app_with(llm.clone()).await;
    let (project, run) = start_run(&t, "alice").await;
    let events = run_to_the_end(&t, run).await;

    // The timeline: every tool is a step that starts and finishes.
    let steps: Vec<&str> = of_kind(&events, "step_start")
        .iter()
        .map(|e| e["tool"].as_str().unwrap())
        .collect();
    assert_eq!(
        steps,
        [
            "plan_essay",
            "generate_outlines",
            "search_sources",
            "scrape_sources",
            "compact_sources",
            "write_essay",
            "finalize_document",
        ]
    );
    let summaries: Vec<&str> = of_kind(&events, "step_done")
        .iter()
        .map(|e| e["summary"].as_str().unwrap())
        .collect();
    assert_eq!(
        summaries,
        [
            "Rising Tides and Coastal Cities",
            "5 paragraphs outlined.",
            "4 sources found.", // the PDF, the duplicate and the ftp link were dropped
            "3 sources read.",  // one link was dead
            "3 sources ready to cite.",
            "28 words written.",
            "Your essay is ready.",
        ]
    );
    assert!(of_kind(&events, "step_error").is_empty());
    assert_eq!(events.last().unwrap()["type"], "done");

    // Questions: the loop fixes the focus question's type and drops bad options.
    let questions = of_kind(&events, "question");
    assert_eq!(questions[0]["field"], "essayFocus");
    assert_eq!(questions[0]["inputType"], "multiselect");
    assert_eq!(questions[0]["options"].as_array().unwrap().len(), 2);
    assert_eq!(questions[1]["field"], "wordCount");
    assert_eq!(questions[1]["inputType"], "number");
    assert_eq!(questions[1]["suggestions"], json!(["500", "800", "1200"]));
    assert_eq!(questions[1]["allowCustom"], true);
    assert_eq!(questions[2]["inputType"], "select");
    assert_eq!(questions[2]["allowCustom"], false);
    assert_eq!(questions[3]["field"], "studentName");
    assert_eq!(questions[3]["inputType"], "text");

    // What the model said out loud.
    let said: Vec<&str> = of_kind(&events, "assistant_message")
        .iter()
        .map(|e| e["text"].as_str().unwrap())
        .collect();
    assert_eq!(
        said,
        ["Sources are in.", "Your essay is ready in the editor."]
    );

    // Sources pill: the three sources the essay cites, with their details.
    let sources = of_kind(&events, "sources_ready")[0];
    assert_eq!(sources["count"], 3);
    assert_eq!(
        sources["sources"][0],
        json!({
            "url": "https://noaa.example/slr",
            "title": "Global and Regional Sea Level Rise Scenarios",
            "author": "Sweet, W.",
            "publishedYear": "2022",
            "publisher": "NOAA",
        })
    );
    assert_eq!(sources["sources"][2]["publisher"], "City Hall");

    // Open Editor pill and the progress bar.
    assert_eq!(of_kind(&events, "writing_started")[0]["targetWords"], 800);
    let progress = of_kind(&events, "write_progress");
    assert_eq!(progress.last().unwrap()["words"], 28);
    assert_eq!(progress.last().unwrap()["targetWords"], 800);

    // The document holds what the agent wrote.
    let (status, document) = t
        .get(&format!("/v1/projects/{project}/document"), "alice")
        .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(document["body"], ESSAY);
    assert_eq!(document["bibliography"], BIBLIOGRAPHY);
    assert_eq!(document["title"], "Rising Tides and Coastal Cities");
    assert_eq!(document["style"], "mla");
    assert_eq!(document["fields"], json!({ "studentName": "Ada Lovelace" }));
    assert_eq!(document["sources"].as_array().unwrap().len(), 3);
    assert_eq!(document["wordCount"], 28);
    assert_eq!(document["locked"], false);
    let last_update = of_kind(&events, "document_updated");
    assert_eq!(last_update.last().unwrap()["rev"], document["rev"]);

    // A snapshot was taken before each agent edit; the first is the blank page.
    let versions: Vec<(i64, String, String)> = sqlx::query_as(
        "SELECT rev, reason, snapshot->>'body' FROM document_versions \
         WHERE project_id = $1 ORDER BY created_at, rev",
    )
    .bind(project)
    .fetch_all(&t.state.db)
    .await
    .unwrap();
    assert_eq!(versions.len(), 2);
    assert_eq!(versions[0], (0, "agent_write".into(), String::new()));
    assert_eq!(versions[1].2, ESSAY);

    // The project reflects the finished essay.
    let (_, project_state) = t.get(&format!("/v1/projects/{project}"), "alice").await;
    assert_eq!(project_state["status"], "ready");
    assert_eq!(project_state["title"], "Rising Tides and Coastal Cities");
    assert_eq!(project_state["targetWords"], 800);
    assert_eq!(project_state["wordCount"], 28);
    assert_eq!(project_state["activeRunId"], Value::Null);

    // The run's context and conversation were saved.
    let (context, messages): (Value, Value) =
        sqlx::query_as("SELECT context, messages FROM runs WHERE id = $1")
            .bind(run)
            .fetch_one(&t.state.db)
            .await
            .unwrap();
    assert_eq!(context["exportReady"], true);
    assert_eq!(context["wordCount"], 800);
    assert_eq!(
        context["focus"],
        json!(["Economic impact", "Policy responses"])
    );
    assert_eq!(context["outlines"][1]["type"], "Body Paragraph");
    assert_eq!(context["outlines"][4]["type"], "Conclusion");
    assert!(messages.as_array().unwrap().len() > 20);

    // The model was shown each tool's result and each answer.
    let transcript = llm.last_transcript();
    assert!(transcript.contains("delivered"));
    assert!(transcript.contains("Ada Lovelace"));
    assert!(transcript.contains("essayFocusOptions"));

    t.cleanup().await;
}

#[tokio::test]
async fn paid_steps_charge_octocredits_once_each() {
    let t = app_with(Arc::new(FakeLlm::new(fakes::full_script()))).await;
    let (_, run) = start_run(&t, "alice").await;
    let events = run_to_the_end(&t, run).await;

    // Source research and essay generation: 100 OC each, at the minimum.
    let credits = of_kind(&events, "credits");
    assert_eq!(credits.len(), 2);
    assert_eq!(credits[0]["reason"], "Source research");
    assert_eq!(credits[0]["charged"], 100);
    assert_eq!(credits[0]["balance"], 9_900);
    assert_eq!(credits[1]["reason"], "Essay generation");
    assert_eq!(credits[1]["balance"], 9_800);

    let (_, me) = t.get("/v1/me", "alice").await;
    assert_eq!(me["octoCredits"], 9_800);

    let refs: Vec<String> =
        sqlx::query_scalar("SELECT source_ref FROM credit_ledger ORDER BY created_at, source_ref")
            .fetch_all(t.state.octopilot.as_ref().unwrap())
            .await
            .unwrap();
    assert_eq!(
        refs,
        [
            format!("ghostwriter:sources:3:{run}"),
            format!("ghostwriter:write:{run}"),
        ]
    );

    t.cleanup().await;
}

#[tokio::test]
async fn a_user_who_cannot_afford_a_step_is_told_and_not_charged() {
    // Bob has 50 OC; reading sources costs 100.
    let llm = Arc::new(FakeLlm::new(vec![
        call("plan_essay", json!({})),
        call("generate_outlines", json!({ "count": 5 })),
        call("search_sources", json!({ "count": 5 })),
        call("scrape_sources", json!({})),
        turn("You do not have enough OctoCredits to continue.", &[]),
    ]));
    let t = app_with(llm.clone()).await;
    let (_, run) = start_run(&t, "bob").await;

    let mut events = stream(&t, "bob", run).await;
    let seen = events.until("assistant_message").await;
    let error = of_kind(&seen, "step_error")[0];
    assert!(error["error"]
        .as_str()
        .unwrap()
        .starts_with("Not enough OctoCredits"));
    assert!(of_kind(&seen, "credits").is_empty());

    // The model was told why, so it could tell the user.
    assert!(llm.last_transcript().contains("Not enough OctoCredits"));

    let (_, me) = t.get("/v1/me", "bob").await;
    assert_eq!(me["octoCredits"], 50);

    // The run waits for the user rather than dying.
    events.until("awaiting_reply").await;
    let (_, state) = t.get(&format!("/v1/runs/{run}"), "bob").await;
    assert_eq!(state["status"], "waiting_for_user");
    assert_eq!(state["pendingQuestion"], Value::Null);

    t.cleanup().await;
}

#[tokio::test]
async fn a_tool_error_goes_back_to_the_model_and_the_run_carries_on() {
    let llm = Arc::new(FakeLlm::new(vec![
        // Out of order: nothing to write yet.
        call("write_essay", json!({})),
        // Not a tool, and arguments that are not JSON.
        call("launch_rocket", json!({})),
        ChatReply {
            content: String::new(),
            tool_calls: vec![ToolCall {
                id: "call_bad".into(),
                name: "plan_essay".into(),
                arguments: "{not json".into(),
            }],
        },
        call("plan_essay", json!({})),
        turn("Planned.", &[]),
    ]));
    let t = app_with(llm.clone()).await;
    let (project, run) = start_run(&t, "alice").await;

    let mut events = stream(&t, "alice", run).await;
    let seen = events.until("assistant_message").await;

    // The failed tool shows as a failed step, then the run recovered.
    let errors = of_kind(&seen, "step_error");
    assert_eq!(errors.len(), 1);
    assert_eq!(
        errors[0]["error"],
        "call plan_essay first (the essay topic is missing)"
    );
    let transcript = llm.last_transcript();
    assert!(transcript.contains("call plan_essay first"));
    assert!(transcript.contains("unknown tool: launch_rocket"));
    assert!(transcript.contains("invalid JSON arguments"));
    assert!(kinds(&seen).contains(&"step_done"));

    // A failed write left no lock behind.
    let (_, document) = t
        .get(&format!("/v1/projects/{project}/document"), "alice")
        .await;
    assert_eq!(document["locked"], false);
    assert_eq!(document["body"], "");

    t.cleanup().await;
}

#[tokio::test]
async fn the_same_call_twice_in_a_row_is_blocked() {
    let llm = Arc::new(FakeLlm::new(vec![
        turn("", &[("plan_essay", json!({})), ("plan_essay", json!({}))]),
        turn("Done planning.", &[]),
    ]));
    let t = app_with(llm.clone()).await;
    let (_, run) = start_run(&t, "alice").await;

    let seen = stream(&t, "alice", run)
        .await
        .until("assistant_message")
        .await;
    assert_eq!(of_kind(&seen, "step_start").len(), 1);
    assert!(llm
        .last_transcript()
        .contains("duplicate call to plan_essay"));

    t.cleanup().await;
}

#[tokio::test]
async fn a_plain_text_question_waits_for_a_chat_reply() {
    let llm = Arc::new(FakeLlm::new(vec![
        turn("Which course is this for?", &[]),
        call("plan_essay", json!({})),
        turn("Thanks, planned.", &[]),
    ]));
    let t = app_with(llm.clone()).await;
    let (_, run) = start_run(&t, "alice").await;

    let mut events = stream(&t, "alice", run).await;
    let asked = events.until("assistant_message").await;
    assert_eq!(asked.last().unwrap()["text"], "Which course is this for?");

    // The run says it is waiting on the chat box.
    events.until("awaiting_reply").await;
    let (_, state) = t.get(&format!("/v1/runs/{run}"), "alice").await;
    assert_eq!(state["status"], "waiting_for_user");
    assert_eq!(state["pendingQuestion"], Value::Null);

    let (status, _) = t
        .post(
            &format!("/v1/runs/{run}/message"),
            "alice",
            json!({ "text": "HIST 101" }),
        )
        .await;
    assert_eq!(status, StatusCode::OK);

    let next = events.until("assistant_message").await;
    assert!(kinds(&next).contains(&"step_done"));
    assert!(llm.last_transcript().contains("HIST 101"));

    t.cleanup().await;
}

#[tokio::test]
async fn a_message_sent_during_a_question_reaches_the_model() {
    let llm = Arc::new(FakeLlm::new(vec![
        ask("essayFocus", json!({})),
        turn("Noted, I will keep it formal.", &[]),
    ]));
    let t = app_with(llm.clone()).await;
    let (_, run) = start_run(&t, "alice").await;

    let mut events = stream(&t, "alice", run).await;
    events.until("question").await;
    t.post(
        &format!("/v1/runs/{run}/message"),
        "alice",
        json!({ "text": "Keep it formal" }),
    )
    .await;
    answer(&t, "alice", run, "essayFocus", json!("__suggest_more__")).await;
    events.until("assistant_message").await;

    let transcript = llm.last_transcript();
    assert!(transcript.contains("Keep it formal"));
    assert!(transcript.contains("__suggest_more__"));

    t.cleanup().await;
}

#[tokio::test]
async fn the_document_is_locked_while_the_agent_writes() {
    let gate = Arc::new(Notify::new());
    let mut llm = FakeLlm::new(vec![
        call("plan_essay", json!({})),
        call("generate_outlines", json!({ "count": 5 })),
        call("search_sources", json!({ "count": 5 })),
        call("scrape_sources", json!({})),
        call("compact_sources", json!({})),
        ask("wordCount", json!({ "inputType": "number" })),
        ask("citationStyle", json!({ "inputType": "select" })),
        call("write_essay", json!({})),
        call("finalize_document", json!({})),
        turn("Ready.", &[]),
    ]);
    llm.hold_writer = Some(gate.clone());
    let t = app_with(Arc::new(llm)).await;
    let (project, run) = start_run(&t, "alice").await;

    let mut events = stream(&t, "alice", run).await;
    events.until("question").await;
    answer(&t, "alice", run, "wordCount", json!(500)).await;
    events.until("question").await;
    answer(&t, "alice", run, "citationStyle", json!("None")).await;
    events.until("writing_started").await;

    // Mid-write: locked.
    let document_path = format!("/v1/projects/{project}/document");
    let (_, document) = t.get(&document_path, "alice").await;
    assert_eq!(document["locked"], true);

    // The writer finishes: unlocked, and delivered.
    gate.notify_one();
    let ending = events.rest().await;
    assert_eq!(ending.last().unwrap()["type"], "done");
    let (_, document) = t.get(&document_path, "alice").await;
    assert_eq!(document["locked"], false);
    assert_eq!(document["style"], "none");
    assert_eq!(document["body"], ESSAY);

    t.cleanup().await;
}

#[tokio::test]
async fn cancelling_mid_write_unlocks_the_document() {
    let gate = Arc::new(Notify::new());
    let mut llm = FakeLlm::new(vec![
        call("plan_essay", json!({})),
        call("generate_outlines", json!({ "count": 5 })),
        call("search_sources", json!({ "count": 5 })),
        call("scrape_sources", json!({})),
        call("compact_sources", json!({})),
        ask("wordCount", json!({})),
        ask("citationStyle", json!({})),
        call("write_essay", json!({})),
    ]);
    llm.hold_writer = Some(gate); // never released: the writer hangs
    let t = app_with(Arc::new(llm)).await;
    let (project, run) = start_run(&t, "alice").await;

    let mut events = stream(&t, "alice", run).await;
    events.until("question").await;
    answer(&t, "alice", run, "wordCount", json!(500)).await;
    events.until("question").await;
    answer(&t, "alice", run, "citationStyle", json!("APA")).await;
    events.until("writing_started").await;

    let (status, body) = t
        .post(&format!("/v1/runs/{run}/cancel"), "alice", json!({}))
        .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["status"], "cancelled");
    assert_eq!(events.rest().await.last().unwrap()["type"], "cancelled");

    let (_, document) = t
        .get(&format!("/v1/projects/{project}/document"), "alice")
        .await;
    assert_eq!(document["locked"], false);

    t.cleanup().await;
}

#[tokio::test]
async fn a_writer_that_returns_nothing_is_a_failed_step_not_an_empty_essay() {
    let llm = FakeLlm::new(vec![
        call("plan_essay", json!({})),
        call("generate_outlines", json!({ "count": 5 })),
        call("search_sources", json!({ "count": 5 })),
        call("scrape_sources", json!({})),
        call("compact_sources", json!({})),
        ask("wordCount", json!({})),
        ask("citationStyle", json!({})),
        call("write_essay", json!({})),
        // The model tries to deliver anyway; that is refused too.
        call("finalize_document", json!({})),
        turn("I could not write the essay.", &[]),
    ]);
    *llm.essay_output.lock().unwrap() = "   ".to_string();
    let llm = Arc::new(llm);
    let t = app_with(llm.clone()).await;
    let (project, run) = start_run(&t, "alice").await;

    let mut events = stream(&t, "alice", run).await;
    events.until("question").await;
    answer(&t, "alice", run, "wordCount", json!(500)).await;
    events.until("question").await;
    answer(&t, "alice", run, "citationStyle", json!("APA")).await;
    let seen = events.until("assistant_message").await;

    let errors: Vec<&str> = of_kind(&seen, "step_error")
        .iter()
        .map(|e| e["error"].as_str().unwrap())
        .collect();
    assert_eq!(
        errors,
        [
            "the writer returned no essay",
            "write_essay has not succeeded yet"
        ]
    );

    // Nothing was written, nothing is locked, and only research was charged.
    let (_, document) = t
        .get(&format!("/v1/projects/{project}/document"), "alice")
        .await;
    assert_eq!(document["body"], "");
    assert_eq!(document["locked"], false);
    let (_, me) = t.get("/v1/me", "alice").await;
    assert_eq!(me["octoCredits"], 9_900);

    t.cleanup().await;
}

#[tokio::test]
async fn a_run_with_no_model_configured_fails_with_a_plain_reason() {
    // The agent driver, but no injected model and no key in api_keys.
    let t = TestApp::with(|config| config.driver = "agent".into()).await;
    let (_, run) = start_run(&t, "alice").await;

    let events = stream(&t, "alice", run).await.rest().await;
    let last = events.last().unwrap();
    assert_eq!(last["type"], "fatal");
    assert_eq!(
        last["error"],
        "GhostWriter is not set up to write right now."
    );

    t.cleanup().await;
}

#[tokio::test]
async fn a_model_that_keeps_failing_ends_the_run() {
    // No scripted turns: every orchestrator call errors.
    let t = app_with(Arc::new(FakeLlm::new(Vec::new()))).await;
    let (project, run) = start_run(&t, "alice").await;

    let events = stream(&t, "alice", run).await.rest().await;
    assert_eq!(kinds(&events), ["user_message", "fatal"]);
    assert_eq!(
        events[1]["error"],
        "The model is not responding. Please try again."
    );
    let (_, project_state) = t.get(&format!("/v1/projects/{project}"), "alice").await;
    assert_eq!(project_state["status"], "idle");

    t.cleanup().await;
}

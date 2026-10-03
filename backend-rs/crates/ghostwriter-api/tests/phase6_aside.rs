//! Messages the user sends while a run is going: answered at once, kept as
//! instructions, and acted on without the user pressing anything.

mod common;

use std::sync::Arc;
use std::time::Duration;

use axum::http::StatusCode;
use common::fakes::{self, ask, call, FakeLlm, FakeScraper, ESSAY};
use common::{kinds, TestApp};
use ghostwriter_api::llm::ChatReply;
use serde_json::{json, Value};
use tokio::sync::Notify;
use uuid::Uuid;

async fn start(t: &TestApp) -> (Uuid, Uuid) {
    let (project, run) = (Uuid::new_v4(), Uuid::new_v4());
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
    (project, run)
}

async fn run_when(t: &TestApp, run: Uuid, ready: impl Fn(&Value) -> bool) -> Value {
    for _ in 0..2000 {
        let (_, state) = t.get(&format!("/v1/runs/{run}"), "alice").await;
        if ready(&state) {
            return state;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    let (_, state) = t.get(&format!("/v1/runs/{run}"), "alice").await;
    panic!("the run never got there: {state}");
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

async fn say(t: &TestApp, run: Uuid, text: &str) {
    let (status, body) = t
        .post(
            &format!("/v1/runs/{run}/message"),
            "alice",
            json!({ "text": text }),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
}

/// Answers whatever the run asks until it ends; returns how it ended.
async fn answer_all(t: &TestApp, run: Uuid) -> String {
    let answers = [
        ("essayFocus", json!(["Economic impact"])),
        ("wordCount", json!(800)),
        ("citationStyle", json!("MLA")),
        ("studentName", json!("Ada Lovelace")),
    ];
    for _ in 0..4000 {
        let (_, state) = t.get(&format!("/v1/runs/{run}"), "alice").await;
        let status = state["status"].as_str().unwrap().to_string();
        if matches!(status.as_str(), "finished" | "error" | "cancelled") {
            return status;
        }
        if let Some(field) = state["pendingQuestion"]["field"].as_str() {
            let value = answers.iter().find(|(f, _)| *f == field).unwrap().1.clone();
            answer(t, run, field, value).await;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    panic!("the run never ended");
}

async fn events_of(t: &TestApp, run: Uuid) -> Vec<Value> {
    t.events(&format!("/v1/runs/{run}/events"), "alice", None)
        .await
        .rest()
        .await
}

/// Waits until the run's log has an event of `kind` that `matches`.
async fn logged(t: &TestApp, run: Uuid, kind: &str, matches: impl Fn(&Value) -> bool) -> Value {
    for _ in 0..2000 {
        let found: Vec<Value> = sqlx::query_scalar(
            "SELECT payload FROM run_events WHERE run_id = $1 AND type = $2 ORDER BY seq",
        )
        .bind(run)
        .bind(kind)
        .fetch_all(&t.state.db)
        .await
        .unwrap();
        if let Some(event) = found.into_iter().find(|e| matches(e)) {
            return event;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    panic!("no {kind} event as expected");
}

/// A run held mid-write: the writer stops after its first chunk until `hold`
/// is notified.
async fn writing(turns: Vec<ChatReply>) -> (TestApp, Arc<FakeLlm>, Arc<Notify>, Uuid, Uuid) {
    let hold = Arc::new(Notify::new());
    let mut llm = FakeLlm::new(turns);
    llm.hold_writer = Some(hold.clone());
    let llm = Arc::new(llm);
    let t = TestApp::agent(llm.clone(), Arc::new(FakeScraper)).await;
    let (project, run) = start(&t).await;
    for field in ["essayFocus", "wordCount", "citationStyle"] {
        run_when(&t, run, |r| r["pendingQuestion"]["field"] == field).await;
        let value = match field {
            "essayFocus" => json!(["Economic impact"]),
            "wordCount" => json!(800),
            _ => json!("MLA"),
        };
        answer(&t, run, field, value).await;
    }
    logged(&t, run, "writing_started", |_| true).await;
    // Let the writer reach its first chunk and wait there.
    tokio::time::sleep(Duration::from_millis(100)).await;
    (t, llm, hold, project, run)
}

#[tokio::test]
async fn a_question_mid_write_is_answered_at_once_and_the_agent_hears_it() {
    let (t, llm, hold, _, run) = writing(fakes::full_script()).await;
    *llm.aside.lock().unwrap() =
        Some(json!({ "reply": "About a minute more.", "kind": "question" }).to_string());

    say(&t, run, "How long will it take?").await;
    // Answered while the writer is still held.
    let reply = logged(&t, run, "assistant_message", |e| e["aside"] == true).await;
    assert_eq!(reply["text"], "About a minute more.");

    hold.notify_one();
    assert_eq!(answer_all(&t, run).await, "finished");

    // The agent got it, marked as answered, and the essay was not touched.
    assert!(llm
        .last_transcript()
        .contains("[Mid-run message, already answered] The user said: How long will it take?"));
    assert_eq!(llm.stream_requests.lock().unwrap().len(), 1);
    let directives: Value = sqlx::query_scalar("SELECT directives FROM runs WHERE id = $1")
        .bind(run)
        .fetch_one(&t.state.db)
        .await
        .unwrap();
    assert_eq!(directives, json!([]));

    t.cleanup().await;
}

#[tokio::test]
async fn an_instruction_mid_write_starts_the_writing_again_with_it() {
    let mut turns = fakes::full_script();
    let write_at = turns
        .iter()
        .position(|t| {
            t.tool_calls
                .first()
                .is_some_and(|c| c.name == "write_essay")
        })
        .unwrap();
    // After the interruption the model writes again, as the result tells it to.
    turns.insert(
        write_at + 1,
        call("write_essay", json!({ "notes": "again" })),
    );
    let (t, llm, hold, project, run) = writing(turns).await;
    *llm.aside.lock().unwrap() =
        Some(json!({ "reply": "Starting again with that.", "kind": "instruction" }).to_string());

    say(&t, run, "Keep it formal").await;
    logged(&t, run, "step_done", |e| {
        e["summary"] == "Starting again with your note."
    })
    .await;
    // The second write streams through.
    hold.notify_one();
    assert_eq!(answer_all(&t, run).await, "finished");

    // The second writer brief carries the instruction.
    let writes = llm.stream_requests.lock().unwrap().clone();
    assert_eq!(writes.len(), 2);
    let brief = writes[1].messages[1]["content"].as_str().unwrap();
    assert!(brief.contains("THE USER'S INSTRUCTIONS (follow them):\n- Keep it formal"));
    assert!(!writes[0].messages[1]["content"]
        .as_str()
        .unwrap()
        .contains("Keep it formal"));
    assert!(llm.last_transcript().contains(r#"\"interrupted\":true"#));

    // Charged once, for the write that finished; the essay is the second one.
    let events = events_of(&t, run).await;
    let writing_charges = events
        .iter()
        .filter(|e| e["type"] == "credits" && e["reason"] == "Essay generation")
        .count();
    assert_eq!(writing_charges, 1);
    let (_, document) = t
        .get(&format!("/v1/projects/{project}/document"), "alice")
        .await;
    assert_eq!(document["body"], ESSAY);
    assert_eq!(document["locked"], false);

    t.cleanup().await;
}

#[tokio::test]
async fn a_message_instead_of_an_answer_is_heard_and_the_question_asked_again() {
    let mut turns = fakes::full_script();
    // The model asks the focus question a second time, after the message.
    let first_ask = turns
        .iter()
        .position(|t| t.tool_calls.first().is_some_and(|c| c.name == "ask_user"))
        .unwrap();
    turns.insert(
        first_ask + 1,
        ask("essayFocus", json!({ "inputType": "multiselect" })),
    );
    let llm = Arc::new(FakeLlm::new(turns));
    *llm.aside.lock().unwrap() = Some(
        json!({ "reply": "Noted, I will lean on recent data.", "kind": "instruction" }).to_string(),
    );
    let t = TestApp::agent(llm.clone(), Arc::new(FakeScraper)).await;
    let (_, run) = start(&t).await;
    run_when(&t, run, |r| r["pendingQuestion"]["field"] == "essayFocus").await;

    say(&t, run, "Use the newest data you can find").await;
    // The question is set aside, the agent hears the message and asks again.
    let skipped = logged(&t, run, "question_answered", |e| e["skipped"] == true).await;
    assert_eq!(skipped["field"], "essayFocus");
    run_when(&t, run, |r| r["pendingQuestion"]["field"] == "essayFocus").await;
    assert!(llm.last_transcript().contains("userMessage"));
    assert!(llm
        .last_transcript()
        .contains("Use the newest data you can find"));

    assert_eq!(answer_all(&t, run).await, "finished");
    let directives: Value = sqlx::query_scalar("SELECT directives FROM runs WHERE id = $1")
        .bind(run)
        .fetch_one(&t.state.db)
        .await
        .unwrap();
    assert_eq!(directives, json!(["Use the newest data you can find"]));

    t.cleanup().await;
}

#[tokio::test]
async fn asking_to_stop_stops_the_run() {
    let (t, llm, _hold, _, run) = writing(fakes::full_script()).await;
    *llm.aside.lock().unwrap() =
        Some(json!({ "reply": "Stopping now.", "kind": "stop" }).to_string());

    say(&t, run, "stop, I changed my mind").await;
    run_when(&t, run, |r| r["status"] == "cancelled").await;
    let events = events_of(&t, run).await;
    assert_eq!(events.last().unwrap()["type"], "cancelled");
    assert!(kinds(&events).contains(&"assistant_message"));

    t.cleanup().await;
}

#[tokio::test]
async fn the_scripted_driver_asks_again_after_a_message_instead_of_an_answer() {
    // No model here: the message goes to the run as it is.
    let t = TestApp::new().await;
    let (_, run) = start(&t).await;
    run_when(&t, run, |r| r["pendingQuestion"]["field"] == "essayFocus").await;

    say(&t, run, "Make it about Venice").await;
    logged(&t, run, "question_answered", |e| e["skipped"] == true).await;
    // Asked again, and answering it moves on.
    let questions = || async {
        sqlx::query_scalar::<_, i64>(
            "SELECT count(*) FROM run_events WHERE run_id = $1 AND type = 'question' \
             AND payload->>'field' = 'essayFocus'",
        )
        .bind(run)
        .fetch_one(&t.state.db)
        .await
        .unwrap()
    };
    for _ in 0..500 {
        if questions().await == 2 {
            break;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    assert_eq!(questions().await, 2);
    run_when(&t, run, |r| r["pendingQuestion"]["field"] == "essayFocus").await;
    answer(&t, run, "essayFocus", json!(["Economic impact"])).await;
    run_when(&t, run, |r| {
        r["pendingQuestion"]["field"] == "sourceReviewChoice"
    })
    .await;

    t.cleanup().await;
}

#[tokio::test]
async fn a_question_asked_while_a_card_waits_leaves_the_card_alone() {
    let llm = Arc::new(FakeLlm::new(fakes::full_script()));
    *llm.aside.lock().unwrap() =
        Some(json!({ "reply": "A few minutes.", "kind": "question" }).to_string());
    let t = TestApp::agent(llm.clone(), Arc::new(FakeScraper)).await;
    let (_, run) = start(&t).await;
    run_when(&t, run, |r| r["pendingQuestion"]["field"] == "essayFocus").await;

    say(&t, run, "How long does this take?").await;
    logged(&t, run, "assistant_message", |e| e["aside"] == true).await;
    tokio::time::sleep(Duration::from_millis(200)).await;
    // Still the same question, not set aside.
    let state = run_when(&t, run, |r| r["status"] == "waiting_for_user").await;
    assert_eq!(state["pendingQuestion"]["field"], "essayFocus");
    let set_aside: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM run_events WHERE run_id = $1 AND type = 'question_answered'",
    )
    .bind(run)
    .fetch_one(&t.state.db)
    .await
    .unwrap();
    assert_eq!(set_aside, 0);

    // Once answered, the agent hears it too, marked as already answered.
    assert_eq!(answer_all(&t, run).await, "finished");
    assert!(llm
        .last_transcript()
        .contains("[Mid-run message, already answered] The user said: How long does this take?"));

    t.cleanup().await;
}

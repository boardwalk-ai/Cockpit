//! Runs as jobs: a run nobody answers is parked instead of failed and picks
//! up where it stopped when the answer comes; a run whose worker died is
//! taken back and resumed.

mod common;

use std::sync::Arc;
use std::time::Duration;

use axum::http::StatusCode;
use common::fakes::{self, call, turn, FakeLlm, FakeScraper, ESSAY};
use common::{kinds, TestApp};
use serde_json::{json, Value};
use tokio::sync::Notify;
use uuid::Uuid;

/// Waits on a question this long before letting the run go.
const PARK_AFTER: Duration = Duration::from_millis(60);

async fn start(t: &TestApp, instruction: &str) -> (Uuid, Uuid) {
    let (project, run) = (Uuid::new_v4(), Uuid::new_v4());
    t.put(&format!("/v1/projects/{project}"), "alice", json!({}))
        .await;
    let (status, body) = t
        .post(
            &format!("/v1/projects/{project}/runs"),
            "alice",
            json!({ "runId": run, "instruction": instruction }),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    (project, run)
}

/// Polls the run until `ready` says so.
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

/// True once no worker holds the run.
async fn parked(t: &TestApp, run: Uuid) -> bool {
    let (status, lease): (String, Option<chrono::DateTime<chrono::Utc>>) =
        sqlx::query_as("SELECT status, lease_until FROM runs WHERE id = $1")
            .bind(run)
            .fetch_one(&t.state.db)
            .await
            .unwrap();
    status == "waiting_for_user" && lease.is_none() && !t.state.hub.is_live(run)
}

async fn until_parked(t: &TestApp, run: Uuid) {
    for _ in 0..2000 {
        if parked(t, run).await {
            return;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    panic!("the run was never parked");
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

/// Answers whatever the run asks, from `answers`, until it ends. Returns how
/// it ended.
async fn answer_all(t: &TestApp, run: Uuid, answers: &[(&str, Value)]) -> String {
    for _ in 0..4000 {
        let (_, state) = t.get(&format!("/v1/runs/{run}"), "alice").await;
        let status = state["status"].as_str().unwrap().to_string();
        if matches!(status.as_str(), "finished" | "error" | "cancelled") {
            return status;
        }
        if let Some(field) = state["pendingQuestion"]["field"].as_str() {
            let value = answers
                .iter()
                .find(|(f, _)| *f == field)
                .unwrap_or_else(|| panic!("no answer for {field}"))
                .1
                .clone();
            answer(t, run, field, value).await;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    let (_, state) = t.get(&format!("/v1/runs/{run}"), "alice").await;
    let row: (String, Option<String>, Option<String>, String) = sqlx::query_as(
        "SELECT status, worker, lease_until::text, now()::text FROM runs WHERE id = $1",
    )
    .bind(run)
    .fetch_one(&t.state.db)
    .await
    .unwrap();
    let waits: Vec<(Option<String>, Option<String>, Option<String>)> = sqlx::query_as(
        "SELECT state, wait_event_type, left(query, 120) FROM pg_stat_activity          WHERE datname = current_database() AND pid <> pg_backend_pid()",
    )
    .fetch_all(&t.state.db)
    .await
    .unwrap();
    panic!("the run never ended: {state} {row:?} {waits:#?}");
}

async fn all_events(t: &TestApp, run: Uuid) -> Vec<Value> {
    t.events(&format!("/v1/runs/{run}/events"), "alice", None)
        .await
        .rest()
        .await
}

fn steps<'a>(events: &'a [Value], tool: &str) -> Vec<&'a Value> {
    events
        .iter()
        .filter(|e| e["type"] == "step_start" && e["tool"] == tool)
        .collect()
}

const AGENT_ANSWERS: [(&str, &str); 4] = [
    ("essayFocus", r#"["Economic impact"]"#),
    ("wordCount", "800"),
    ("citationStyle", r#""MLA""#),
    ("studentName", r#""Ada Lovelace""#),
];

fn agent_answers() -> Vec<(&'static str, Value)> {
    AGENT_ANSWERS
        .iter()
        .map(|(field, value)| (*field, serde_json::from_str(value).unwrap()))
        .collect()
}

#[tokio::test]
async fn a_run_nobody_answers_is_parked_and_the_answer_picks_it_up() {
    let t = TestApp::with(|config| config.park_after = PARK_AFTER).await;
    let (project, run) = start(&t, "An essay on tides").await;

    // The app is following; the run asks, waits, and is let go.
    let mut events = t
        .events(&format!("/v1/runs/{run}/events"), "alice", None)
        .await;
    events.until("question").await;
    until_parked(&t, run).await;
    let (_, state) = t.get(&format!("/v1/runs/{run}"), "alice").await;
    assert_eq!(state["status"], "waiting_for_user");
    assert_eq!(state["pendingQuestion"]["field"], "essayFocus");
    let (_, project_state) = t.get(&format!("/v1/projects/{project}"), "alice").await;
    assert_eq!(project_state["activeRunId"], run.to_string());

    // Answering wakes it; the same stream carries on.
    answer(&t, run, "essayFocus", json!(["Economic impact"])).await;
    let next = events.until("question").await;
    assert_eq!(next.last().unwrap()["field"], "sourceReviewChoice");
    drop(events);

    let ended = answer_all(
        &t,
        run,
        &[
            ("sourceReviewChoice", json!("One Shot")),
            ("wordCount", json!(500)),
            ("citationStyle", json!("APA")),
        ],
    )
    .await;
    assert_eq!(ended, "finished");

    // Nothing was done twice, and nothing failed.
    let events = all_events(&t, run).await;
    assert_eq!(steps(&events, "plan_essay").len(), 1);
    assert_eq!(
        kinds(&events)
            .iter()
            .filter(|k| **k == "user_message")
            .count(),
        1
    );
    assert!(!kinds(&events).contains(&"fatal"));
    assert!(!kinds(&events).contains(&"step_error"));
    assert_eq!(
        kinds(&events)
            .iter()
            .filter(|k| **k == "writing_started")
            .count(),
        1
    );
    let (_, document) = t
        .get(&format!("/v1/projects/{project}/document"), "alice")
        .await;
    assert!(document["wordCount"].as_i64().unwrap() > 400);

    t.cleanup().await;
}

#[tokio::test]
async fn the_agent_resumes_from_its_saved_conversation() {
    let llm = Arc::new(FakeLlm::new(fakes::full_script()));
    let mut t = TestApp::agent(llm.clone(), Arc::new(FakeScraper)).await;
    let mut config = (*t.state.config).clone();
    config.park_after = PARK_AFTER;
    t.state.config = Arc::new(config);
    let t = t.rebuilt();

    let (_, run) = start(&t, "An essay on rising tides").await;
    run_when(&t, run, |r| r["pendingQuestion"]["field"] == "essayFocus").await;
    until_parked(&t, run).await;

    assert_eq!(answer_all(&t, run, &agent_answers()).await, "finished");

    // The plan was made once: the resumed run did not start over.
    let planned = llm
        .sub_requests
        .lock()
        .unwrap()
        .iter()
        .filter(|r| {
            r.messages[0]["content"]
                .as_str()
                .unwrap()
                .contains("planning sub-agent")
        })
        .count();
    assert_eq!(planned, 1);

    // The model got the answer as the result of the question it had asked.
    let transcript = llm.last_transcript();
    assert!(
        transcript.contains(r#""tool_call_id":"call_ask_user_0","role":"tool""#)
            || transcript.contains(r#""role":"tool","tool_call_id":"call_ask_user_0""#)
    );
    assert!(
        transcript.contains(r#"{\"answer\":[\"Economic impact\"]}"#),
        "{transcript}"
    );

    let events = all_events(&t, run).await;
    assert_eq!(
        kinds(&events)
            .iter()
            .filter(|k| **k == "user_message")
            .count(),
        1
    );
    assert_eq!(steps(&events, "plan_essay").len(), 1);

    t.cleanup().await;
}

#[tokio::test]
async fn a_chat_reply_wakes_a_run_parked_on_a_plain_question() {
    let mut turns = vec![turn("Which angle matters most to you?", &[])];
    turns.extend(fakes::full_script());
    let llm = Arc::new(FakeLlm::new(turns));
    let mut t = TestApp::agent(llm.clone(), Arc::new(FakeScraper)).await;
    let mut config = (*t.state.config).clone();
    config.park_after = PARK_AFTER;
    t.state.config = Arc::new(config);
    let t = t.rebuilt();

    let (_, run) = start(&t, "An essay on rising tides").await;
    until_parked(&t, run).await;
    let (status, _) = t
        .post(
            &format!("/v1/runs/{run}/message"),
            "alice",
            json!({ "text": "The money side of it" }),
        )
        .await;
    assert_eq!(status, StatusCode::OK);

    assert_eq!(answer_all(&t, run, &agent_answers()).await, "finished");
    let first_after = llm.orchestrator_requests.lock().unwrap()[1].clone();
    assert_eq!(
        first_after.messages.last().unwrap()["content"],
        "The money side of it"
    );

    t.cleanup().await;
}

#[tokio::test]
async fn a_run_whose_worker_died_is_taken_back_and_resumed() {
    let mut turns = fakes::full_script();
    // After the restart the model writes again (the first write was cut off).
    let write_at = turns
        .iter()
        .position(|t| {
            t.tool_calls
                .first()
                .is_some_and(|c| c.name == "write_essay")
        })
        .unwrap();
    turns.insert(
        write_at + 1,
        call("write_essay", json!({ "notes": "again" })),
    );
    let hold = Arc::new(Notify::new());
    let mut llm = FakeLlm::new(turns);
    llm.hold_writer = Some(hold.clone());
    let llm = Arc::new(llm);
    let t = TestApp::agent(llm.clone(), Arc::new(FakeScraper)).await;

    let (project, run) = start(&t, "An essay on rising tides").await;
    for (field, value) in agent_answers().into_iter().take(3) {
        run_when(&t, run, |r| r["pendingQuestion"]["field"] == field).await;
        answer(&t, run, field, value).await;
    }
    // The writer is mid-stream, holding the document: it has said so, and
    // waits on the model between chunks (no database work in flight).
    for _ in 0..2000 {
        let started: bool = sqlx::query_scalar(
            "SELECT EXISTS (SELECT 1 FROM run_events WHERE run_id = $1 AND type = 'writing_started')",
        )
        .bind(run)
        .fetch_one(&t.state.db)
        .await
        .unwrap();
        if started {
            break;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    tokio::time::sleep(Duration::from_millis(100)).await;
    let locked: Option<Uuid> =
        sqlx::query_scalar("SELECT locked_by_run FROM documents WHERE project_id = $1")
            .bind(project)
            .fetch_one(&t.state.db)
            .await
            .unwrap();
    assert_eq!(locked, Some(run));

    // The process driving it dies: its task stops and its lease runs out.
    t.state.hub.abort(run);
    sqlx::query(
        "UPDATE runs SET worker = 'a-dead-process', lease_until = now() - interval '1 second' \
         WHERE id = $1",
    )
    .bind(run)
    .execute(&t.state.db)
    .await
    .unwrap();
    // The second write streams through.
    hold.notify_one();

    assert_eq!(answer_all(&t, run, &agent_answers()).await, "finished");

    let events = all_events(&t, run).await;
    let writes = steps(&events, "write_essay");
    assert_eq!(writes.len(), 2);
    // The cut-off step was closed, so the app does not spin forever.
    let closed = events
        .iter()
        .find(|e| e["type"] == "step_error" && e["stepId"] == writes[0]["stepId"])
        .expect("the interrupted step is closed");
    assert_eq!(closed["error"], "Interrupted. Picking up from here.");
    assert!(llm
        .last_transcript()
        .contains("This call was interrupted before it finished."));

    let (_, document) = t
        .get(&format!("/v1/projects/{project}/document"), "alice")
        .await;
    assert_eq!(document["body"], ESSAY);
    assert_eq!(document["locked"], false);

    t.cleanup().await;
}

#[tokio::test]
async fn a_parked_run_can_be_cancelled_and_a_new_one_started() {
    let t = TestApp::with(|config| config.park_after = PARK_AFTER).await;
    let (project, run) = start(&t, "An essay on tides").await;
    run_when(&t, run, |r| r["status"] == "waiting_for_user").await;
    until_parked(&t, run).await;

    let (_, body) = t
        .post(&format!("/v1/runs/{run}/cancel"), "alice", json!({}))
        .await;
    assert_eq!(body["status"], "cancelled");
    let events = all_events(&t, run).await;
    assert_eq!(events.last().unwrap()["type"], "cancelled");

    let (status, _) = t
        .post(
            &format!("/v1/projects/{project}/runs"),
            "alice",
            json!({ "runId": Uuid::new_v4(), "instruction": "Again" }),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED);

    t.cleanup().await;
}

#[tokio::test]
async fn a_message_to_a_run_parked_on_a_question_waits_for_its_answer() {
    let t = TestApp::with(|config| config.park_after = PARK_AFTER).await;
    let (_, run) = start(&t, "An essay on tides").await;
    run_when(&t, run, |r| r["status"] == "waiting_for_user").await;
    until_parked(&t, run).await;

    t.post(
        &format!("/v1/runs/{run}/message"),
        "alice",
        json!({ "text": "Keep it short" }),
    )
    .await;
    // Still parked on its question: a chat message is not the answer.
    tokio::time::sleep(Duration::from_millis(100)).await;
    assert!(parked(&t, run).await);
    let inbox: Value = sqlx::query_scalar("SELECT inbox FROM runs WHERE id = $1")
        .bind(run)
        .fetch_one(&t.state.db)
        .await
        .unwrap();
    assert_eq!(inbox, json!(["Keep it short"]));

    t.cleanup().await;
}

#[tokio::test]
async fn a_scripted_run_cut_off_mid_write_finishes_its_essay() {
    // Slow enough that the write can be cut off part-way.
    let t = TestApp::with(|config| config.scripted_step = Duration::from_millis(150)).await;
    let (project, run) = start(&t, "An essay on tides").await;
    for (field, value) in [
        ("essayFocus", json!(["Economic impact"])),
        ("sourceReviewChoice", json!("One Shot")),
        ("wordCount", json!(500)),
        ("citationStyle", json!("APA")),
    ] {
        run_when(&t, run, |r| r["pendingQuestion"]["field"] == field).await;
        answer(&t, run, field, value).await;
    }
    for _ in 0..2000 {
        let words: i32 = sqlx::query_scalar("SELECT word_count FROM projects WHERE id = $1")
            .bind(project)
            .fetch_one(&t.state.db)
            .await
            .unwrap();
        if words > 0 {
            break;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }

    // Part of the essay is in the document when the process dies.
    t.state.hub.abort(run);
    sqlx::query(
        "UPDATE runs SET worker = 'a-dead-process', lease_until = now() - interval '1 second' \
         WHERE id = $1",
    )
    .bind(run)
    .execute(&t.state.db)
    .await
    .unwrap();

    run_when(&t, run, |r| r["status"] == "finished").await;
    let events = all_events(&t, run).await;
    // Still the first run, not taken for a revision of the half-written essay.
    assert!(steps(&events, "revise_essay").is_empty());
    assert_eq!(steps(&events, "write_essay").len(), 2);
    let (_, document) = t
        .get(&format!("/v1/projects/{project}/document"), "alice")
        .await;
    assert!(document["wordCount"].as_i64().unwrap() >= 500, "{document}");
    assert_eq!(document["locked"], false);

    t.cleanup().await;
}

#[tokio::test]
async fn a_run_waiting_on_its_user_does_not_hold_up_anyone_else() {
    // One worker place: a waiting run must not keep it.
    let t = TestApp::with(|config| config.worker_slots = 1).await;
    let (first_project, first) = start(&t, "An essay on tides").await;
    run_when(&t, first, |r| r["status"] == "waiting_for_user").await;

    let (_, second) = start(&t, "An essay on rivers").await;
    run_when(&t, second, |r| r["status"] == "waiting_for_user").await;

    // Both go on when answered.
    answer(&t, first, "essayFocus", json!(["Economic impact"])).await;
    answer(&t, second, "essayFocus", json!(["Social impact"])).await;
    run_when(&t, first, |r| {
        r["pendingQuestion"]["field"] == "sourceReviewChoice"
    })
    .await;
    run_when(&t, second, |r| {
        r["pendingQuestion"]["field"] == "sourceReviewChoice"
    })
    .await;

    // The list says which essays wait on the user.
    let (_, list) = t.get("/v1/projects", "alice").await;
    let waiting: Vec<bool> = list["projects"]
        .as_array()
        .unwrap()
        .iter()
        .map(|p| p["needsAnswer"].as_bool().unwrap())
        .collect();
    assert_eq!(waiting, [true, true]);
    t.post(&format!("/v1/runs/{first}/cancel"), "alice", json!({}))
        .await;
    let (_, project) = t
        .get(&format!("/v1/projects/{first_project}"), "alice")
        .await;
    assert_eq!(project["needsAnswer"], false);

    t.cleanup().await;
}

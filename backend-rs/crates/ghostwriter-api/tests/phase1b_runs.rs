//! Phase 1b: runs — start, the durable event stream, answers, messages, cancel.
//! Driven by the scripted driver, so no model is involved.

mod common;

use axum::http::StatusCode;
use common::{kinds, EventStream, TestApp};
use serde_json::{json, Value};
use uuid::Uuid;

/// Creates a project for `user` and starts a run on it.
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
    assert_eq!(body["runId"], run.to_string());
    (project, run)
}

async fn answer(t: &TestApp, run: Uuid, field: &str, value: Value) -> (StatusCode, Value) {
    t.post(
        &format!("/v1/runs/{run}/answer"),
        "alice",
        json!({ "field": field, "value": value }),
    )
    .await
}

async fn stream(t: &TestApp, run: Uuid, since: i64) -> EventStream {
    t.events(
        &format!("/v1/runs/{run}/events?sinceSeq={since}"),
        "alice",
        None,
    )
    .await
}

/// Answers the three scripted questions, reading the stream between them.
async fn answer_all(t: &TestApp, run: Uuid, events: &mut EventStream) -> Vec<Value> {
    let mut seen = events.until("question").await;
    answer(
        t,
        run,
        "essayFocus",
        json!(["Economic impact", "Policy responses"]),
    )
    .await;
    seen.extend(events.until("question").await);
    answer(t, run, "sourceReviewChoice", json!("One Shot")).await;
    seen.extend(events.until("question").await);
    answer(t, run, "wordCount", json!(800)).await;
    seen.extend(events.until("question").await);
    answer(t, run, "citationStyle", json!("APA")).await;
    seen.extend(events.rest().await);
    seen
}

#[tokio::test]
async fn a_run_goes_from_brief_to_done() {
    let t = TestApp::new().await;
    let (project, run) = start_run(&t, "alice").await;
    let mut events = stream(&t, run, 0).await;

    // Up to the first question.
    let opening = events.until("question").await;
    assert_eq!(
        kinds(&opening),
        ["user_message", "step_start", "step_done", "question"]
    );
    assert_eq!(opening[0]["text"], "An essay on rising tides");
    assert_eq!(opening[1]["tool"], "plan_essay");
    assert_eq!(opening[1]["stepId"], opening[2]["stepId"]);
    let question = &opening[3];
    assert_eq!(question["field"], "essayFocus");
    assert_eq!(question["inputType"], "multiselect");
    assert_eq!(question["options"].as_array().unwrap().len(), 5);

    // The run is parked on that question.
    let (_, state) = t.get(&format!("/v1/runs/{run}"), "alice").await;
    assert_eq!(state["status"], "waiting_for_user");
    assert_eq!(state["pendingQuestion"]["field"], "essayFocus");
    assert_eq!(state["lastSeq"], 4);
    let (_, project_state) = t.get(&format!("/v1/projects/{project}"), "alice").await;
    assert_eq!(project_state["status"], "writing");
    assert_eq!(project_state["activeRunId"], run.to_string());

    let (status, _) = answer(
        &t,
        run,
        "essayFocus",
        json!(["Economic impact", "Policy responses"]),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    // Through the research steps to the source review question.
    let middle = events.until("question").await;
    assert_eq!(middle[0]["type"], "question_answered");
    assert_eq!(middle[0]["field"], "essayFocus");
    assert_eq!(middle.last().unwrap()["field"], "sourceReviewChoice");
    answer(&t, run, "sourceReviewChoice", json!("One Shot")).await;

    // Summaries, then the word-count question.
    let summaries = events.until("question").await;
    let ready = summaries
        .iter()
        .find(|e| e["type"] == "sources_ready")
        .unwrap();
    assert_eq!(ready["count"], 5);
    assert_eq!(ready["sources"].as_array().unwrap().len(), 5);
    assert_eq!(summaries.last().unwrap()["field"], "wordCount");
    answer(&t, run, "wordCount", json!(800)).await;

    let style = events.until("question").await;
    assert_eq!(style.last().unwrap()["field"], "citationStyle");
    answer(&t, run, "citationStyle", json!("APA")).await;

    // Writing, with live text deltas ahead of the stored message.
    let ending = events.rest().await;
    let ending_kinds = kinds(&ending);
    assert!(ending_kinds.contains(&"assistant_delta"));
    let message = ending
        .iter()
        .find(|e| e["type"] == "assistant_message")
        .unwrap();
    assert_eq!(message["text"], "Thanks. Writing your essay now.");
    let started = ending
        .iter()
        .find(|e| e["type"] == "writing_started")
        .unwrap();
    assert_eq!(started["targetWords"], 800);
    let progress: Vec<i64> = ending
        .iter()
        .filter(|e| e["type"] == "write_progress")
        .map(|e| e["words"].as_i64().unwrap())
        .collect();
    assert_eq!(progress, [160, 360, 560, 760, 832]); // the last one overshoots
    assert_eq!(*ending_kinds.last().unwrap(), "done");

    // Closed: finished, project ready, nothing active.
    let (_, state) = t.get(&format!("/v1/runs/{run}"), "alice").await;
    assert_eq!(state["status"], "finished");
    assert_eq!(state["pendingQuestion"], Value::Null);
    let (_, project_state) = t.get(&format!("/v1/projects/{project}"), "alice").await;
    assert_eq!(project_state["status"], "ready");
    assert_eq!(project_state["activeRunId"], Value::Null);
    assert_eq!(project_state["title"], "An essay on rising tides");

    t.cleanup().await;
}

#[tokio::test]
async fn stored_events_are_numbered_without_gaps_and_replay_exactly() {
    let t = TestApp::new().await;
    let (_, run) = start_run(&t, "alice").await;
    let mut live = stream(&t, run, 0).await;
    let seen = answer_all(&t, run, &mut live).await;

    let stored: Vec<&Value> = seen.iter().filter(|e| e.get("seq").is_some()).collect();
    let seqs: Vec<i64> = stored.iter().map(|e| e["seq"].as_i64().unwrap()).collect();
    assert_eq!(seqs, (1..=seqs.len() as i64).collect::<Vec<_>>());

    // A replay after the run ended is the stored events and nothing else.
    let replay = stream(&t, run, 0).await.rest().await;
    assert!(!kinds(&replay).contains(&"assistant_delta"));
    assert_eq!(replay.len(), stored.len());
    for (replayed, original) in replay.iter().zip(&stored) {
        assert_eq!(&replayed, original);
    }

    // From a cursor, only what came after it.
    let tail = stream(&t, run, 10).await.rest().await;
    assert_eq!(tail.first().unwrap()["seq"], 11);
    assert_eq!(tail.len(), stored.len() - 10);

    // Last-Event-ID is the same cursor.
    let by_header = t
        .events(&format!("/v1/runs/{run}/events"), "alice", Some(10))
        .await
        .rest()
        .await;
    assert_eq!(by_header, tail);

    // Past the end: an empty stream that closes.
    let nothing = stream(&t, run, 9_999).await.rest().await;
    assert!(nothing.is_empty());

    t.cleanup().await;
}

#[tokio::test]
async fn a_client_that_reconnects_misses_nothing() {
    let t = TestApp::new().await;
    let (_, run) = start_run(&t, "alice").await;

    // First connection drops at the first question.
    let mut first = stream(&t, run, 0).await;
    let before = first.until("question").await;
    let cursor = before.last().unwrap()["seq"].as_i64().unwrap();
    drop(first);

    // Things happen while nobody is connected.
    answer(&t, run, "essayFocus", json!(["Social impact"])).await;

    // The second connection picks up exactly after the cursor.
    let mut second = stream(&t, run, cursor).await;
    let after = second.until("question").await;
    assert_eq!(after[0]["seq"], cursor + 1);
    assert_eq!(after[0]["type"], "question_answered");
    assert_eq!(after.last().unwrap()["field"], "sourceReviewChoice");

    let seqs: Vec<i64> = after.iter().map(|e| e["seq"].as_i64().unwrap()).collect();
    let expected: Vec<i64> = (cursor + 1..=cursor + seqs.len() as i64).collect();
    assert_eq!(seqs, expected);

    t.cleanup().await;
}

#[tokio::test]
async fn only_the_pending_question_can_be_answered_and_only_once() {
    let t = TestApp::new().await;
    let (_, run) = start_run(&t, "alice").await;
    stream(&t, run, 0).await.until("question").await;

    // Not the question that is waiting.
    let (status, body) = answer(&t, run, "wordCount", json!(800)).await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(body["code"], "no_pending_question");

    // No value.
    let (status, _) = answer(&t, run, "essayFocus", Value::Null).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);

    // Someone else's run reads as not found.
    let (status, _) = t
        .post(
            &format!("/v1/runs/{run}/answer"),
            "bob",
            json!({ "field": "essayFocus", "value": ["x"] }),
        )
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    // The real answer works once.
    let (status, _) = answer(&t, run, "essayFocus", json!(["Social impact"])).await;
    assert_eq!(status, StatusCode::OK);
    let (status, body) = answer(&t, run, "essayFocus", json!(["Again"])).await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(body["code"], "no_pending_question");

    let answered: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM run_events WHERE run_id = $1 AND type = 'question_answered'",
    )
    .bind(run)
    .fetch_one(&t.state.db)
    .await
    .unwrap();
    assert_eq!(answered, 1);

    t.cleanup().await;
}

#[tokio::test]
async fn starting_is_idempotent_and_one_run_at_a_time() {
    let t = TestApp::new().await;
    let (project, run) = start_run(&t, "alice").await;
    let runs_path = format!("/v1/projects/{project}/runs");

    // The same start again is a no-op.
    let (status, body) = t
        .post(
            &runs_path,
            "alice",
            json!({ "runId": run, "instruction": "Different" }),
        )
        .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["runId"], run.to_string());

    // A second run on the same project has to wait.
    let (status, body) = t
        .post(
            &runs_path,
            "alice",
            json!({ "runId": Uuid::new_v4(), "instruction": "Another" }),
        )
        .await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(body["code"], "run_active");

    let count: i64 = sqlx::query_scalar("SELECT count(*) FROM runs WHERE project_id = $1")
        .bind(project)
        .fetch_one(&t.state.db)
        .await
        .unwrap();
    assert_eq!(count, 1);

    // A run id cannot be reused on another project.
    let other = Uuid::new_v4();
    t.put(&format!("/v1/projects/{other}"), "alice", json!({}))
        .await;
    let (status, body) = t
        .post(
            &format!("/v1/projects/{other}/runs"),
            "alice",
            json!({ "runId": run, "instruction": "x" }),
        )
        .await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(body["code"], "run_id_taken");

    t.cleanup().await;
}

#[tokio::test]
async fn starting_needs_a_brief_and_an_owned_project() {
    let t = TestApp::new().await;
    let project = Uuid::new_v4();
    t.put(&format!("/v1/projects/{project}"), "alice", json!({}))
        .await;
    let runs_path = format!("/v1/projects/{project}/runs");

    // No brief anywhere.
    let (status, _) = t
        .post(&runs_path, "alice", json!({ "runId": Uuid::new_v4() }))
        .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);

    // Not Bob's project.
    let (status, _) = t
        .post(
            &runs_path,
            "bob",
            json!({ "runId": Uuid::new_v4(), "instruction": "x" }),
        )
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    // The brief saved on the project is enough.
    t.put(
        &format!("/v1/projects/{project}"),
        "alice",
        json!({ "instruction": "Saved brief" }),
    )
    .await;
    let run = Uuid::new_v4();
    let (status, _) = t.post(&runs_path, "alice", json!({ "runId": run })).await;
    assert_eq!(status, StatusCode::CREATED);
    let opening = stream(&t, run, 0).await.until("question").await;
    assert_eq!(opening[0]["text"], "Saved brief");

    t.cleanup().await;
}

#[tokio::test]
async fn chat_messages_reach_the_run() {
    let t = TestApp::new().await;
    let (_, run) = start_run(&t, "alice").await;
    let mut events = stream(&t, run, 0).await;
    events.until("question").await;

    let (status, _) = t
        .post(
            &format!("/v1/runs/{run}/message"),
            "alice",
            json!({ "text": "  Keep it formal  " }),
        )
        .await;
    assert_eq!(status, StatusCode::OK);
    let echoed = events.until("user_message").await;
    assert_eq!(echoed.last().unwrap()["text"], "Keep it formal");

    // Written instead of an answer: the run hears it and asks again, and the
    // answer then moves it on.
    let again = events.until("question").await;
    assert!(again
        .iter()
        .any(|e| e["type"] == "question_answered" && e["skipped"] == true));
    assert_eq!(again.last().unwrap()["field"], "essayFocus");
    answer(&t, run, "essayFocus", json!(["Social impact"])).await;
    let next = events.until("question").await;
    assert_eq!(next.last().unwrap()["field"], "sourceReviewChoice");

    // Blank text is refused.
    let (status, _) = t
        .post(
            &format!("/v1/runs/{run}/message"),
            "alice",
            json!({ "text": "   " }),
        )
        .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);

    t.cleanup().await;
}

#[tokio::test]
async fn cancelling_stops_the_run_and_frees_the_project() {
    let t = TestApp::new().await;
    let (project, run) = start_run(&t, "alice").await;
    let mut events = stream(&t, run, 0).await;
    events.until("question").await;

    let (status, body) = t
        .post(&format!("/v1/runs/{run}/cancel"), "alice", json!({}))
        .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["status"], "cancelled");

    // The connected client is told, and the stream ends.
    let ending = events.rest().await;
    assert_eq!(kinds(&ending), ["cancelled"]);

    let (_, state) = t.get(&format!("/v1/runs/{run}"), "alice").await;
    assert_eq!(state["status"], "cancelled");
    assert_eq!(state["pendingQuestion"], Value::Null);
    let (_, project_state) = t.get(&format!("/v1/projects/{project}"), "alice").await;
    assert_eq!(project_state["status"], "idle");
    assert_eq!(project_state["activeRunId"], Value::Null);

    // Cancelling again is harmless; answering or messaging is refused.
    let (status, body) = t
        .post(&format!("/v1/runs/{run}/cancel"), "alice", json!({}))
        .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["status"], "cancelled");
    let (status, _) = answer(&t, run, "essayFocus", json!(["x"])).await;
    assert_eq!(status, StatusCode::CONFLICT);
    let (status, body) = t
        .post(
            &format!("/v1/runs/{run}/message"),
            "alice",
            json!({ "text": "hello" }),
        )
        .await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(body["code"], "run_ended");

    // Exactly one terminal event was stored.
    let terminal: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM run_events WHERE run_id = $1 AND type IN ('done', 'fatal', 'cancelled')",
    )
    .bind(run)
    .fetch_one(&t.state.db)
    .await
    .unwrap();
    assert_eq!(terminal, 1);

    // The project can start a new run now.
    let (status, _) = t
        .post(
            &format!("/v1/projects/{project}/runs"),
            "alice",
            json!({ "runId": Uuid::new_v4(), "instruction": "Try again" }),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED);

    t.cleanup().await;
}

#[tokio::test]
async fn an_unusable_answer_fails_the_run_with_a_reason() {
    let t = TestApp::new().await;
    let (_, run) = start_run(&t, "alice").await;
    let mut events = stream(&t, run, 0).await;
    events.until("question").await;
    answer(&t, run, "essayFocus", json!(["Social impact"])).await;
    events.until("question").await;
    answer(&t, run, "sourceReviewChoice", json!("One Shot")).await;
    events.until("question").await;

    answer(&t, run, "wordCount", json!("banana")).await;
    let ending = events.rest().await;
    let last = ending.last().unwrap();
    assert_eq!(last["type"], "fatal");
    assert_eq!(last["error"], "That word count is not usable.");

    t.cleanup().await;
}

#[tokio::test]
async fn runs_are_private_to_their_owner() {
    let t = TestApp::new().await;
    let (_, run) = start_run(&t, "alice").await;

    let (status, _) = t.get(&format!("/v1/runs/{run}"), "bob").await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = t.get(&format!("/v1/runs/{run}/events"), "bob").await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = t
        .post(&format!("/v1/runs/{run}/cancel"), "bob", json!({}))
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = t
        .post(
            &format!("/v1/runs/{run}/message"),
            "bob",
            json!({ "text": "hi" }),
        )
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    // Alice's run is untouched: it goes on to its first question.
    stream(&t, run, 0).await.until("question").await;
    let (_, state) = t.get(&format!("/v1/runs/{run}"), "alice").await;
    assert_eq!(state["status"], "waiting_for_user");

    t.cleanup().await;
}

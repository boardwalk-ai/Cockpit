//! Phase 5: push notifications. A run tells the user's phones when it needs
//! them or has ended, but only when nobody is following it.

mod common;

use std::sync::Arc;
use std::time::Duration;

use axum::http::StatusCode;
use common::fakes::{FakeLlm, FakePusher, FakeScraper};
use common::TestApp;
use serde_json::{json, Value};
use uuid::Uuid;

async fn register(t: &TestApp, user: &str, token: &str) -> Uuid {
    let device = Uuid::new_v4();
    let (status, body) = t
        .put(
            &format!("/v1/devices/{device}"),
            user,
            json!({ "token": token, "platform": "android" }),
        )
        .await;
    assert_eq!(status, StatusCode::NO_CONTENT, "{body}");
    device
}

async fn start(t: &TestApp, user: &str) -> (Uuid, Uuid) {
    let (project, run) = (Uuid::new_v4(), Uuid::new_v4());
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

/// Polls the run until `ready` says so.
async fn run_when(t: &TestApp, run: Uuid, ready: impl Fn(&Value) -> bool) -> Value {
    for _ in 0..400 {
        let (_, state) = t.get(&format!("/v1/runs/{run}"), "alice").await;
        if ready(&state) {
            return state;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    panic!("the run never got there");
}

/// Waits until `count` notifications have been sent, then a little longer to
/// catch any that should not have been.
async fn sent(pusher: &FakePusher, count: usize) -> Vec<(String, String, String)> {
    for _ in 0..400 {
        if pusher.sent.lock().unwrap().len() >= count {
            break;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    tokio::time::sleep(Duration::from_millis(60)).await;
    pusher
        .sent
        .lock()
        .unwrap()
        .iter()
        .map(|(token, notice)| {
            (
                token.clone(),
                notice.data["type"].clone(),
                notice.body.clone(),
            )
        })
        .collect()
}

async fn device_tokens(t: &TestApp) -> Vec<String> {
    sqlx::query_scalar("SELECT token FROM devices ORDER BY token")
        .fetch_all(&t.state.db)
        .await
        .unwrap()
}

#[tokio::test]
async fn a_device_is_registered_refreshed_moved_and_removed() {
    let t = TestApp::new().await;
    let device = register(&t, "alice", "token-1").await;
    assert_eq!(device_tokens(&t).await, ["token-1"]);

    // The same install with a new token: still one row.
    let (status, _) = t
        .put(
            &format!("/v1/devices/{device}"),
            "alice",
            json!({ "token": "token-2", "platform": "ios" }),
        )
        .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    assert_eq!(device_tokens(&t).await, ["token-2"]);

    // A reinstall: new id, same token. The old row goes.
    let reinstalled = register(&t, "alice", "token-2").await;
    assert_eq!(device_tokens(&t).await, ["token-2"]);

    // Bob signs in on the same phone: the device is his now.
    let (status, _) = t
        .put(
            &format!("/v1/devices/{reinstalled}"),
            "bob",
            json!({ "token": "token-2", "platform": "android" }),
        )
        .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    // Alice cannot remove it; Bob can.
    t.delete(&format!("/v1/devices/{reinstalled}"), "alice")
        .await;
    assert_eq!(device_tokens(&t).await, ["token-2"]);
    let (status, _) = t.delete(&format!("/v1/devices/{reinstalled}"), "bob").await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    assert!(device_tokens(&t).await.is_empty());

    for body in [
        json!({ "platform": "android" }),
        json!({ "token": "  ", "platform": "android" }),
        json!({ "token": "t", "platform": "windows" }),
        json!({ "token": "t" }),
    ] {
        let (status, _) = t
            .put(&format!("/v1/devices/{}", Uuid::new_v4()), "alice", body)
            .await;
        assert_eq!(status, StatusCode::BAD_REQUEST);
    }

    t.cleanup().await;
}

#[tokio::test]
async fn a_question_nobody_is_watching_is_pushed_to_the_owners_phones() {
    let pusher = Arc::new(FakePusher::default());
    let t = TestApp::with_pusher(|_| {}, pusher.clone()).await;
    register(&t, "alice", "alice-phone").await;
    register(&t, "alice", "alice-tablet").await;
    register(&t, "bob", "bob-phone").await;

    let (project, run) = start(&t, "alice").await;
    run_when(&t, run, |r| r["status"] == "waiting_for_user").await;

    let notices = sent(&pusher, 2).await;
    assert_eq!(
        notices
            .iter()
            .map(|(token, kind, _)| (token.as_str(), kind.as_str()))
            .collect::<Vec<_>>(),
        [("alice-phone", "question"), ("alice-tablet", "question")]
    );
    assert!(notices[0].2.starts_with("What should this essay focus on?"));

    let title: String = sqlx::query_scalar("SELECT title FROM projects WHERE id = $1")
        .bind(project)
        .fetch_one(&t.state.db)
        .await
        .unwrap();
    let first = pusher.sent.lock().unwrap()[0].1.clone();
    assert_eq!(first.title, title);
    assert_eq!(first.data["projectId"], project.to_string());
    assert_eq!(first.data["runId"], run.to_string());

    t.cleanup().await;
}

#[tokio::test]
async fn nothing_is_pushed_while_the_app_is_following_the_run() {
    let pusher = Arc::new(FakePusher::default());
    let t = TestApp::with_pusher(|_| {}, pusher.clone()).await;
    register(&t, "alice", "alice-phone").await;

    let (_, run) = start(&t, "alice").await;
    let mut events = t
        .events(&format!("/v1/runs/{run}/events"), "alice", None)
        .await;
    events.until("question").await;

    assert!(sent(&pusher, 1).await.is_empty());
    drop(events);

    t.cleanup().await;
}

#[tokio::test]
async fn an_unwatched_run_pushes_every_question_and_its_ending() {
    let pusher = Arc::new(FakePusher::default());
    let t = TestApp::with_pusher(|_| {}, pusher.clone()).await;
    register(&t, "alice", "alice-phone").await;
    let (_, run) = start(&t, "alice").await;

    for (field, value) in [
        ("essayFocus", json!(["Economic impact"])),
        ("sourceReviewChoice", json!("One Shot")),
        ("wordCount", json!(500)),
        ("citationStyle", json!("APA")),
    ] {
        run_when(&t, run, |r| r["pendingQuestion"]["field"] == field).await;
        let (status, body) = t
            .post(
                &format!("/v1/runs/{run}/answer"),
                "alice",
                json!({ "field": field, "value": value }),
            )
            .await;
        assert_eq!(status, StatusCode::OK, "{body}");
    }
    run_when(&t, run, |r| r["status"] == "finished").await;

    let notices = sent(&pusher, 5).await;
    let kinds: Vec<&str> = notices.iter().map(|(_, kind, _)| kind.as_str()).collect();
    assert_eq!(
        kinds,
        ["question", "question", "question", "question", "done"]
    );
    assert_eq!(notices[4].2, "GhostWriter has finished. Tap to open.");

    t.cleanup().await;
}

#[tokio::test]
async fn a_run_that_fails_unwatched_says_why() {
    let pusher = Arc::new(FakePusher::default());
    // A model that never answers.
    let llm = Arc::new(FakeLlm::new(Vec::new()));
    let mut t = TestApp::agent(llm, Arc::new(FakeScraper)).await;
    t.state.pusher = pusher.clone();
    let t = t.rebuilt();
    register(&t, "alice", "alice-phone").await;
    let (_, run) = start(&t, "alice").await;
    run_when(&t, run, |r| r["status"] == "error").await;

    let notices = sent(&pusher, 1).await;
    assert_eq!(notices.len(), 1);
    assert_eq!(notices[0].1, "fatal");
    assert_eq!(
        notices[0].2,
        "GhostWriter stopped. The model is not responding. Please try again."
    );

    t.cleanup().await;
}

#[tokio::test]
async fn a_dead_token_is_forgotten() {
    let pusher = Arc::new(FakePusher::default());
    pusher.dead.lock().unwrap().push("old-phone".to_string());
    let t = TestApp::with_pusher(|_| {}, pusher.clone()).await;
    register(&t, "alice", "old-phone").await;
    register(&t, "alice", "new-phone").await;

    let (_, run) = start(&t, "alice").await;
    run_when(&t, run, |r| r["status"] == "waiting_for_user").await;
    sent(&pusher, 2).await;

    assert_eq!(device_tokens(&t).await, ["new-phone"]);

    t.cleanup().await;
}

//! Deleted accounts lose their GhostWriter data, and the app's update and
//! maintenance check.

mod common;

use std::time::Duration;

use axum::http::StatusCode;
use common::TestApp;
use ghostwriter_api::sweeper;
use serde_json::{json, Value};
use uuid::Uuid;

async fn count(t: &TestApp, table: &str, user: &str) -> i64 {
    sqlx::query_scalar(&format!(
        "SELECT count(*) FROM {table} WHERE user_id = \
         (SELECT id FROM users WHERE firebase_uid = $1)"
    ))
    .bind(user)
    .fetch_one(&t.state.db)
    .await
    .unwrap()
}

/// A project with a run waiting on a question, a folder and a device.
async fn fill(t: &TestApp, user: &str) -> (Uuid, Uuid) {
    let (project, run, folder) = (Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4());
    t.put(
        &format!("/v1/folders/{folder}"),
        user,
        json!({ "name": "Essays" }),
    )
    .await;
    t.put(&format!("/v1/projects/{project}"), user, json!({}))
        .await;
    let (status, body) = t
        .post(
            &format!("/v1/projects/{project}/runs"),
            user,
            json!({ "runId": run, "instruction": "An essay on tides" }),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    t.put(
        &format!("/v1/devices/{}", Uuid::new_v4()),
        user,
        json!({ "token": format!("token-{user}"), "platform": "android" }),
    )
    .await;
    for _ in 0..500 {
        let (_, state) = t.get(&format!("/v1/runs/{run}"), user).await;
        if state["status"] == "waiting_for_user" {
            return (project, run);
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    panic!("the run never asked");
}

async fn delete_account(t: &TestApp, user: &str) -> Uuid {
    sqlx::query_scalar("DELETE FROM users WHERE firebase_uid = $1 RETURNING id")
        .bind(user)
        .fetch_one(t.state.octopilot.as_ref().unwrap())
        .await
        .unwrap()
}

#[tokio::test]
async fn a_deleted_account_loses_its_data_and_no_one_else_does() {
    let t = TestApp::new().await;
    let (project, _) = fill(&t, "alice").await;
    let (bob_project, _) = fill(&t, "bob").await;
    // Alice's sign-in is cached now.
    assert_eq!(t.get("/v1/projects", "alice").await.0, StatusCode::OK);

    let alice = delete_account(&t, "alice").await;
    let (tombstone,): (Option<String>,) =
        sqlx::query_as("SELECT firebase_uid FROM deleted_users WHERE user_id = $1")
            .bind(alice)
            .fetch_one(&t.state.db)
            .await
            .unwrap();
    assert_eq!(
        tombstone.as_deref(),
        Some("alice"),
        "the database keeps the tombstone"
    );

    assert_eq!(sweeper::sweep(&t.state).await.unwrap(), 1);
    for table in ["projects", "runs", "folders", "devices"] {
        let left: i64 =
            sqlx::query_scalar(&format!("SELECT count(*) FROM {table} WHERE user_id = $1"))
                .bind(alice)
                .fetch_one(&t.state.db)
                .await
                .unwrap();
        assert_eq!(left, 0, "{table}");
    }
    let events: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM run_events e WHERE NOT EXISTS \
         (SELECT 1 FROM runs r WHERE r.id = e.run_id)",
    )
    .fetch_one(&t.state.db)
    .await
    .unwrap();
    assert_eq!(events, 0);
    let docs: i64 = sqlx::query_scalar("SELECT count(*) FROM documents WHERE project_id = $1")
        .bind(project)
        .fetch_one(&t.state.db)
        .await
        .unwrap();
    assert_eq!(docs, 0);

    // Bob keeps everything.
    for table in ["projects", "runs", "folders", "devices"] {
        assert_eq!(count(&t, table, "bob").await, 1, "{table}");
    }
    let (status, _) = t.get(&format!("/v1/projects/{bob_project}"), "bob").await;
    assert_eq!(status, StatusCode::OK);

    // The cached sign-in is gone with the account.
    let (status, body) = t.get("/v1/projects", "alice").await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    assert_eq!(body["code"], "account_required");

    // Swept once.
    assert_eq!(sweeper::sweep(&t.state).await.unwrap(), 0);

    t.cleanup().await;
}

#[tokio::test]
async fn a_sweep_gets_through_a_long_list() {
    let t = TestApp::new().await;
    let shared = t.state.octopilot.as_ref().unwrap();
    // Accounts deleted before GhostWriter had anything of theirs.
    sqlx::query(
        "INSERT INTO deleted_users (user_id, deleted_at) \
         SELECT gen_random_uuid(), now() - make_interval(secs => g) \
         FROM generate_series(1, 1200) g",
    )
    .execute(shared)
    .await
    .unwrap();
    fill(&t, "alice").await;
    delete_account(&t, "alice").await;

    assert_eq!(sweeper::sweep(&t.state).await.unwrap(), 1201);
    assert_eq!(count(&t, "projects", "alice").await, 0);
    assert_eq!(sweeper::sweep(&t.state).await.unwrap(), 0);

    // One deleted later is picked up by the next pass.
    delete_account(&t, "bob").await;
    assert_eq!(sweeper::sweep(&t.state).await.unwrap(), 1);

    t.cleanup().await;
}

async fn status(t: &TestApp, query: &str) -> Value {
    let (code, body) = t.get(&format!("/v1/app/status?{query}"), "nobody").await;
    assert_eq!(code, StatusCode::OK, "{body}");
    body
}

#[tokio::test]
async fn the_app_learns_when_to_update() {
    let t = TestApp::new().await;
    let body = status(&t, "platform=android&version=1.0.0").await;
    assert_eq!(body["update"], "none", "nothing set: all clear");
    assert_eq!(body["maintenance"], false);

    sqlx::query(
        "INSERT INTO app_status (app, platform, min_version, latest_version, store_url) VALUES \
         ('ghostwriter', '*', '1.0.0', '1.1.0', NULL), \
         ('ghostwriter', 'android', '1.2.0', '1.3.0', 'https://play.example/gw')",
    )
    .execute(t.state.octopilot.as_ref().unwrap())
    .await
    .unwrap();
    t.state.app_status.refresh();

    let android = status(&t, "app=ghostwriter&platform=android&version=1.1.5").await;
    assert_eq!(android["update"], "required");
    assert_eq!(android["latestVersion"], "1.3.0");
    assert_eq!(android["storeUrl"], "https://play.example/gw");
    assert_eq!(
        status(&t, "platform=android&version=1.2.0+7").await["update"],
        "available"
    );
    assert_eq!(
        status(&t, "platform=android&version=1.3.0").await["update"],
        "none"
    );
    // iOS has no row of its own and follows `*`.
    assert_eq!(
        status(&t, "platform=ios&version=1.0.5").await["update"],
        "available"
    );
    assert_eq!(
        status(&t, "platform=ios&version=0.9.0").await["update"],
        "required"
    );
    // Another app's settings are its own.
    assert_eq!(
        status(&t, "app=study_studio&platform=android&version=0.1.0").await["update"],
        "none"
    );

    t.cleanup().await;
}

#[tokio::test]
async fn maintenance_closes_the_api_but_not_the_status_check() {
    let t = TestApp::new().await;
    sqlx::query(
        "INSERT INTO app_status (app, platform, maintenance, maintenance_message) \
         VALUES ('ghostwriter', '*', true, 'Upgrading. Back at 10:00.')",
    )
    .execute(t.state.octopilot.as_ref().unwrap())
    .await
    .unwrap();
    t.state.app_status.refresh();

    let (code, body) = t.get("/v1/projects", "alice").await;
    assert_eq!(code, StatusCode::SERVICE_UNAVAILABLE);
    assert_eq!(body["code"], "maintenance");
    assert_eq!(body["error"], "Upgrading. Back at 10:00.");

    let body = status(&t, "platform=android&version=1.0.0").await;
    assert_eq!(body["maintenance"], true);
    assert_eq!(body["message"], "Upgrading. Back at 10:00.");
    assert_eq!(t.get("/health", "alice").await.0, StatusCode::OK);

    sqlx::query("UPDATE app_status SET maintenance = false")
        .execute(t.state.octopilot.as_ref().unwrap())
        .await
        .unwrap();
    t.state.app_status.refresh();
    assert_eq!(t.get("/v1/projects", "alice").await.0, StatusCode::OK);
    assert_eq!(
        status(&t, "platform=android&version=1.0.0").await["message"],
        Value::Null
    );

    t.cleanup().await;
}

#[tokio::test]
async fn an_allowed_tester_gets_an_account_on_first_sign_in() {
    let t = TestApp::with(|config| {
        config.account_allowlist = vec!["pm@example.com".into()];
        config.starting_credits = 9999;
    })
    .await;
    let pool = t.state.octopilot.clone().unwrap();
    let user = |uid: &str, email: &str, verified: bool| octo_common::auth::AuthedUser {
        uid: uid.into(),
        email: Some(email.into()),
        email_verified: verified,
        name: Some("Pat Manager".into()),
    };
    let provision = |u| {
        let st = t.state.clone();
        let pool = pool.clone();
        async move {
            ghostwriter_api::ctx::provision(&st, &pool, &u)
                .await
                .unwrap()
        }
    };

    // Not on the list, or not verified: no account.
    assert!(!provision(user("stranger", "x@example.com", true)).await);
    assert!(!provision(user("faker", "pm@example.com", false)).await);
    // On the list (any case): an account with the starting credits, once.
    assert!(provision(user("pm-uid", "PM@Example.com", true)).await);
    assert!(!provision(user("pm-uid", "pm@example.com", true)).await);
    let (credits, plan): (i32, String) =
        sqlx::query_as("SELECT octo_credits, plan FROM users WHERE firebase_uid = 'pm-uid'")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!((credits, plan.as_str()), (9999, "Staging Tester"));
}

//! Phase 1a: identity, projects and folders.

mod common;

use axum::http::StatusCode;
use common::TestApp;
use serde_json::{json, Value};
use uuid::Uuid;

fn titles(list: &Value) -> Vec<&str> {
    list["projects"]
        .as_array()
        .unwrap()
        .iter()
        .map(|p| p["title"].as_str().unwrap())
        .collect()
}

#[tokio::test]
async fn health_and_ready() {
    let t = TestApp::new().await;

    let (status, body) = t.get("/health", "alice").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["status"], "ok");

    let (status, body) = t.get("/ready", "alice").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["ghostwriterDb"], true);
    assert_eq!(body["octopilotDb"], true);

    t.cleanup().await;
}

#[tokio::test]
async fn me_returns_the_account_and_its_balance() {
    let t = TestApp::new().await;

    let (status, body) = t.get("/v1/me", "alice").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["name"], "Alice");
    assert_eq!(body["email"], "alice@test");
    assert_eq!(body["octoCredits"], 10000);
    assert!(Uuid::parse_str(body["id"].as_str().unwrap()).is_ok());

    t.cleanup().await;
}

#[tokio::test]
async fn sign_in_without_an_account_is_refused() {
    let t = TestApp::new().await;

    for path in ["/v1/me", "/v1/projects"] {
        let (status, body) = t.get(path, "stranger").await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{path}");
        assert_eq!(body["code"], "account_required", "{path}");
    }

    t.cleanup().await;
}

#[tokio::test]
async fn saving_a_project_is_an_idempotent_upsert() {
    let t = TestApp::new().await;
    let id = Uuid::new_v4();
    let path = format!("/v1/projects/{id}");

    let body = json!({ "title": "  Tides  ", "instruction": "An essay on tides" });
    let (status, created) = t.put(&path, "alice", body.clone()).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(created["id"], id.to_string());
    assert_eq!(created["title"], "Tides");
    assert_eq!(created["instruction"], "An essay on tides");
    assert_eq!(created["status"], "idle");
    assert_eq!(created["wordCount"], 0);
    assert_eq!(created["folderId"], Value::Null);

    // The same save again changes nothing and makes no second copy.
    let (status, again) = t.put(&path, "alice", body).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(again["createdAt"], created["createdAt"]);

    let (_, list) = t.get("/v1/projects", "alice").await;
    assert_eq!(titles(&list), ["Tides"]);

    // Every project has its one document from the start.
    let documents: i64 = sqlx::query_scalar("SELECT count(*) FROM documents WHERE project_id = $1")
        .bind(id)
        .fetch_one(&t.state.db)
        .await
        .unwrap();
    assert_eq!(documents, 1);

    t.cleanup().await;
}

#[tokio::test]
async fn updating_changes_only_the_fields_sent() {
    let t = TestApp::new().await;
    let path = format!("/v1/projects/{}", Uuid::new_v4());

    t.put(
        &path,
        "alice",
        json!({ "title": "Tides", "instruction": "Brief" }),
    )
    .await;

    let (_, renamed) = t
        .put(&path, "alice", json!({ "title": "Coastal tides" }))
        .await;
    assert_eq!(renamed["title"], "Coastal tides");
    assert_eq!(renamed["instruction"], "Brief");

    // A blank title means "not sent", not "erase".
    let (_, blank) = t.put(&path, "alice", json!({ "title": "   " })).await;
    assert_eq!(blank["title"], "Coastal tides");

    t.cleanup().await;
}

#[tokio::test]
async fn a_new_project_with_no_title_gets_a_default() {
    let t = TestApp::new().await;
    let path = format!("/v1/projects/{}", Uuid::new_v4());

    let (status, created) = t.put(&path, "alice", json!({})).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(created["title"], "Untitled essay");
    assert_eq!(created["instruction"], "");

    t.cleanup().await;
}

#[tokio::test]
async fn projects_are_private_to_their_owner() {
    let t = TestApp::new().await;
    let id = Uuid::new_v4();
    let path = format!("/v1/projects/{id}");
    t.put(&path, "alice", json!({ "title": "Alice's essay" }))
        .await;

    // Bob cannot see it, read it, overwrite it or delete it.
    let (_, list) = t.get("/v1/projects", "bob").await;
    assert!(titles(&list).is_empty());

    let (status, _) = t.get(&path, "bob").await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    let (status, _) = t.put(&path, "bob", json!({ "title": "Mine now" })).await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    let (status, _) = t.delete(&path, "bob").await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    let (_, still) = t.get(&path, "alice").await;
    assert_eq!(still["title"], "Alice's essay");

    t.cleanup().await;
}

#[tokio::test]
async fn get_one_reports_the_active_run() {
    let t = TestApp::new().await;
    let id = Uuid::new_v4();
    let path = format!("/v1/projects/{id}");
    t.put(&path, "alice", json!({ "title": "Tides" })).await;

    let (status, project) = t.get(&path, "alice").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(project["activeRunId"], Value::Null);

    let run = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO runs (id, project_id, user_id, status) \
         SELECT $1, id, user_id, 'waiting_for_user' FROM projects WHERE id = $2",
    )
    .bind(run)
    .bind(id)
    .execute(&t.state.db)
    .await
    .unwrap();

    let (_, project) = t.get(&path, "alice").await;
    assert_eq!(project["activeRunId"], run.to_string());

    // A finished run is not active.
    sqlx::query("UPDATE runs SET status = 'finished' WHERE id = $1")
        .bind(run)
        .execute(&t.state.db)
        .await
        .unwrap();
    let (_, project) = t.get(&path, "alice").await;
    assert_eq!(project["activeRunId"], Value::Null);

    t.cleanup().await;
}

#[tokio::test]
async fn deleting_a_project_removes_everything_under_it() {
    let t = TestApp::new().await;
    let id = Uuid::new_v4();
    let path = format!("/v1/projects/{id}");
    t.put(&path, "alice", json!({ "title": "Tides" })).await;

    let (status, _) = t.delete(&path, "alice").await;
    assert_eq!(status, StatusCode::NO_CONTENT);

    let (status, _) = t.get(&path, "alice").await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = t.delete(&path, "alice").await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    let documents: i64 = sqlx::query_scalar("SELECT count(*) FROM documents")
        .fetch_one(&t.state.db)
        .await
        .unwrap();
    assert_eq!(documents, 0);

    t.cleanup().await;
}

#[tokio::test]
async fn folders_file_and_unfile_projects() {
    let t = TestApp::new().await;
    let folder = Uuid::new_v4();
    let folder_path = format!("/v1/folders/{folder}");
    let project_path = format!("/v1/projects/{}", Uuid::new_v4());

    let (status, created) = t
        .put(&folder_path, "alice", json!({ "name": " Geography " }))
        .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(created["name"], "Geography");

    let (_, renamed) = t
        .put(&folder_path, "alice", json!({ "name": "Earth science" }))
        .await;
    assert_eq!(renamed["name"], "Earth science");
    assert_eq!(renamed["createdAt"], created["createdAt"]);

    // File a project in it.
    let (status, filed) = t
        .put(
            &project_path,
            "alice",
            json!({ "title": "Tides", "folderId": folder }),
        )
        .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(filed["folderId"], folder.to_string());

    // Leaving folderId out keeps the folder.
    let (_, kept) = t
        .put(&project_path, "alice", json!({ "title": "Tides 2" }))
        .await;
    assert_eq!(kept["folderId"], folder.to_string());

    // An explicit null unfiles it.
    let (_, unfiled) = t
        .put(&project_path, "alice", json!({ "folderId": null }))
        .await;
    assert_eq!(unfiled["folderId"], Value::Null);

    let (_, list) = t.get("/v1/projects", "alice").await;
    assert_eq!(list["folders"].as_array().unwrap().len(), 1);
    assert_eq!(list["folders"][0]["name"], "Earth science");

    t.cleanup().await;
}

#[tokio::test]
async fn deleting_a_folder_keeps_its_projects() {
    let t = TestApp::new().await;
    let folder = Uuid::new_v4();
    let folder_path = format!("/v1/folders/{folder}");
    let project_path = format!("/v1/projects/{}", Uuid::new_v4());
    t.put(&folder_path, "alice", json!({ "name": "Geography" }))
        .await;
    t.put(
        &project_path,
        "alice",
        json!({ "title": "Tides", "folderId": folder }),
    )
    .await;

    let (status, _) = t.delete(&folder_path, "alice").await;
    assert_eq!(status, StatusCode::NO_CONTENT);

    let (status, project) = t.get(&project_path, "alice").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(project["folderId"], Value::Null);

    t.cleanup().await;
}

#[tokio::test]
async fn folders_are_private_to_their_owner() {
    let t = TestApp::new().await;
    let folder = Uuid::new_v4();
    let folder_path = format!("/v1/folders/{folder}");
    t.put(&folder_path, "alice", json!({ "name": "Geography" }))
        .await;

    // Bob cannot rename it, delete it, or file his project in it.
    let (status, _) = t.put(&folder_path, "bob", json!({ "name": "Mine" })).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = t.delete(&folder_path, "bob").await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    let project_path = format!("/v1/projects/{}", Uuid::new_v4());
    let (status, _) = t
        .put(
            &project_path,
            "bob",
            json!({ "title": "Bob's", "folderId": folder }),
        )
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (_, list) = t.get("/v1/projects", "bob").await;
    assert!(titles(&list).is_empty());
    assert!(list["folders"].as_array().unwrap().is_empty());

    t.cleanup().await;
}

#[tokio::test]
async fn bad_input_is_rejected() {
    let t = TestApp::new().await;
    let project_path = format!("/v1/projects/{}", Uuid::new_v4());

    let (status, _) = t
        .put(&project_path, "alice", json!({ "title": "x".repeat(201) }))
        .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);

    let (status, _) = t
        .put(
            &format!("/v1/folders/{}", Uuid::new_v4()),
            "alice",
            json!({ "name": "  " }),
        )
        .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);

    let (status, _) = t.get("/v1/projects/not-a-uuid", "alice").await;
    assert_eq!(status, StatusCode::BAD_REQUEST);

    // Nothing was created along the way.
    let (_, list) = t.get("/v1/projects", "alice").await;
    assert!(titles(&list).is_empty());

    t.cleanup().await;
}

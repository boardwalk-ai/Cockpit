//! AI settings: the models and personalities users choose from (from the
//! shared DB), what a run uses, masking the real model, and prices from the
//! shared table.

mod common;

use std::sync::Arc;
use std::time::Duration;

use axum::http::StatusCode;
use common::fakes::{self, turn, FakeLlm, FakeScraper};
use common::TestApp;
use serde_json::{json, Value};
use uuid::Uuid;

/// A catalog: a free default and a Pro model at twice the price, and two voices.
async fn seed(t: &TestApp) {
    let pool = t.state.octopilot.as_ref().unwrap();
    sqlx::query(
        "INSERT INTO ai_models (id, display_name, tagline, orchestrator_model, writer_model, \
             fast_model, min_plan, credit_multiplier, is_default, sort) VALUES \
         ('octo-v1', 'Octo v1', 'Everyday', 'fake/orch-1', 'fake/writer-1', 'fake/fast-1', 'free', 1, true, 1), \
         ('octo-v2-pro', 'Octo v2 Pro', 'Best', 'fake/orch-pro', 'fake/writer-pro', 'fake/fast-pro', 'pro', 2, false, 2), \
         ('octo-off', 'Octo Off', '', 'x', 'x', 'x', 'free', 1, false, 3)",
    )
    .execute(pool)
    .await
    .unwrap();
    sqlx::query("UPDATE ai_models SET enabled = false WHERE id = 'octo-off'")
        .execute(pool)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO ai_personalities (id, display_name, description, prompt, is_default, sort) VALUES \
         ('cool', 'Cool', 'Relaxed', 'Talk in a relaxed, friendly way.', true, 1), \
         ('professor', 'Professor', 'Precise', 'Talk like a kind university professor.', false, 2)",
    )
    .execute(pool)
    .await
    .unwrap();
    // A user on the free plan.
    sqlx::query(
        "INSERT INTO users (firebase_uid, email, name, plan, octo_credits) \
         VALUES ('carol', 'carol@test', 'Carol', 'Guest Plan', 1000)",
    )
    .execute(pool)
    .await
    .unwrap();
    t.state.ai.refresh();
}

async fn put_pref(t: &TestApp, user: &str, scope: &str, body: Value) -> (StatusCode, Value) {
    t.put(&format!("/v1/ai/preferences/{scope}"), user, body)
        .await
}

async fn start(t: &TestApp) -> Uuid {
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
    run
}

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
            t.post(
                &format!("/v1/runs/{run}/answer"),
                "alice",
                json!({ "field": field, "value": value }),
            )
            .await;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    panic!("the run never ended");
}

#[tokio::test]
async fn the_catalog_shows_names_not_models_and_locks_pro_for_free_users() {
    let t = TestApp::new().await;
    seed(&t).await;

    let (status, free) = t.get("/v1/ai/catalog", "carol").await;
    assert_eq!(status, StatusCode::OK, "{free}");
    assert_eq!(free["pro"], false);
    let models = free["models"].as_array().unwrap();
    assert_eq!(models.len(), 2, "a turned-off model is not listed");
    assert_eq!(models[0]["name"], "Octo v1");
    assert_eq!(models[0]["default"], true);
    assert_eq!(models[1]["locked"], true);
    assert_eq!(free["personalities"][1]["name"], "Professor");
    // The real models never leave the server.
    assert!(!free.to_string().contains("fake/"));

    let (_, pro) = t.get("/v1/ai/catalog", "alice").await;
    assert_eq!(pro["pro"], true);
    assert_eq!(pro["models"][1]["locked"], false);

    t.cleanup().await;
}

#[tokio::test]
async fn choices_are_saved_per_scope_and_pro_models_need_pro() {
    let t = TestApp::new().await;
    seed(&t).await;

    let (status, body) = put_pref(&t, "carol", "global", json!({ "model": "octo-v2-pro" })).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    assert_eq!(body["code"], "pro_required");
    for (scope, body) in [
        ("everywhere", json!({ "model": "octo-v1" })),
        ("global", json!({ "model": "octo-v9" })),
        ("global", json!({ "model": "octo-off" })),
        ("global", json!({ "personality": "pirate" })),
    ] {
        let (status, _) = put_pref(&t, "alice", scope, body).await;
        assert_eq!(status, StatusCode::BAD_REQUEST, "{scope}");
    }

    // Every app: Pro model, cool voice. GhostWriter only: the professor.
    put_pref(&t, "alice", "global", json!({ "model": "octo-v2-pro" })).await;
    let (status, prefs) = put_pref(
        &t,
        "alice",
        "ghostwriter",
        json!({ "personality": "professor" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{prefs}");
    assert_eq!(
        prefs["scopes"]["global"],
        json!({ "model": "octo-v2-pro", "personality": null })
    );
    assert_eq!(
        prefs["effective"]["ghostwriter"],
        json!({ "model": "octo-v2-pro", "personality": "professor" })
    );
    assert_eq!(
        prefs["effective"]["study_studio"],
        json!({ "model": "octo-v2-pro", "personality": "cool" })
    );

    // `null` follows the wider scope again; an absent field is left alone.
    put_pref(&t, "alice", "ghostwriter", json!({ "model": "octo-v1" })).await;
    let (_, prefs) = put_pref(&t, "alice", "ghostwriter", json!({ "model": null })).await;
    assert_eq!(
        prefs["scopes"]["ghostwriter"],
        json!({ "model": null, "personality": "professor" })
    );
    assert_eq!(prefs["effective"]["ghostwriter"]["model"], "octo-v2-pro");

    // A user who leaves Pro falls back to the default model.
    sqlx::query("UPDATE users SET plan = 'Guest Plan' WHERE firebase_uid = 'alice'")
        .execute(t.state.octopilot.as_ref().unwrap())
        .await
        .unwrap();
    let (_, prefs) = t.get("/v1/ai/preferences", "alice").await;
    assert_eq!(prefs["effective"]["ghostwriter"]["model"], "octo-v1");

    t.cleanup().await;
}

#[tokio::test]
async fn a_run_uses_the_chosen_models_voice_and_prices() {
    let mut turns = fakes::full_script();
    // The model gives itself away; the user never sees it.
    let last = turns.len() - 1;
    turns[last] = turn("Done! I am Claude, made by Anthropic.", &[]);
    let llm = Arc::new(FakeLlm::new(turns));
    let t = TestApp::agent(llm.clone(), Arc::new(FakeScraper)).await;
    seed(&t).await;
    put_pref(
        &t,
        "alice",
        "ghostwriter",
        json!({ "model": "octo-v2-pro", "personality": "professor" }),
    )
    .await;
    // Admin raises the minimum charge.
    sqlx::query("UPDATE pricing_config SET min_charge = 300")
        .execute(t.state.octopilot.as_ref().unwrap())
        .await
        .unwrap();
    t.state.ai.refresh();

    let run = start(&t).await;
    assert_eq!(answer_all(&t, run).await, "finished");

    // The bundle behind "Octo v2 Pro".
    let first = llm.orchestrator_requests.lock().unwrap()[0].clone();
    assert_eq!(first.model, "fake/orch-pro");
    let system = first.messages[0]["content"].as_str().unwrap();
    assert!(system.contains("You are Octo v2 Pro, made by Octopilot."));
    assert!(system.contains("Talk like a kind university professor."));
    assert_eq!(
        llm.stream_requests.lock().unwrap()[0].model,
        "fake/writer-pro"
    );
    // The writer gets no voice: the essay stays academic.
    let writer = llm.stream_requests.lock().unwrap()[0].clone();
    assert!(!json!(writer.messages).to_string().contains("professor"));
    let compactor = llm
        .sub_requests
        .lock()
        .unwrap()
        .iter()
        .find(|r| {
            r.messages[0]["content"]
                .as_str()
                .unwrap()
                .contains("SOURCE_COMPACTION")
        })
        .unwrap()
        .model
        .clone();
    assert_eq!(compactor, "fake/fast-pro");

    let events = t
        .events(&format!("/v1/runs/{run}/events"), "alice", None)
        .await
        .rest()
        .await;
    let said: Vec<&str> = events
        .iter()
        .filter(|e| e["type"] == "assistant_message")
        .map(|e| e["text"].as_str().unwrap())
        .collect();
    assert_eq!(
        said.last().unwrap(),
        &"Done! I am Octo v2 Pro, made by Octo v2 Pro."
    );
    // Every charge follows the shared table.
    let charges: Vec<i64> = events
        .iter()
        .filter(|e| e["type"] == "credits")
        .map(|e| e["charged"].as_i64().unwrap())
        .collect();
    assert!(!charges.is_empty());
    assert!(charges.iter().all(|c| *c == 300), "{charges:?}");

    t.cleanup().await;
}

#[tokio::test]
async fn a_run_keeps_its_model_when_the_choice_changes_midway() {
    let llm = Arc::new(FakeLlm::new(fakes::full_script()));
    let t = TestApp::agent(llm.clone(), Arc::new(FakeScraper)).await;
    seed(&t).await;
    put_pref(&t, "alice", "global", json!({ "model": "octo-v2-pro" })).await;

    let run = start(&t).await;
    for _ in 0..2000 {
        let (_, state) = t.get(&format!("/v1/runs/{run}"), "alice").await;
        if state["pendingQuestion"]["field"] == "essayFocus" {
            break;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    // Parked on the question, the user switches model; this run is not moved.
    put_pref(&t, "alice", "global", json!({ "model": "octo-v1" })).await;
    assert_eq!(answer_all(&t, run).await, "finished");
    let models: Vec<String> = llm
        .orchestrator_requests
        .lock()
        .unwrap()
        .iter()
        .map(|r| r.model.clone())
        .collect();
    assert!(models.iter().all(|m| m == "fake/orch-pro"), "{models:?}");

    t.cleanup().await;
}

#[tokio::test]
async fn without_a_catalog_runs_use_the_old_settings() {
    let llm = Arc::new(FakeLlm::new(fakes::full_script()));
    let t = TestApp::agent(llm.clone(), Arc::new(FakeScraper)).await;

    let run = start(&t).await;
    assert_eq!(answer_all(&t, run).await, "finished");
    let first = llm.orchestrator_requests.lock().unwrap()[0].clone();
    assert!(!first.model.starts_with("fake/"));
    assert!(first.messages[0]["content"]
        .as_str()
        .unwrap()
        .contains("You are GhostWriter, made by Octopilot."));

    let (_, catalog) = t.get("/v1/ai/catalog", "alice").await;
    assert_eq!(catalog["models"], json!([]));

    t.cleanup().await;
}

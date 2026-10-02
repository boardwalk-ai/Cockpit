//! Phase 4: the user's review of the sources steers their summaries.

mod common;

use std::sync::Arc;

use axum::http::StatusCode;
use common::fakes::{ask, call, FakeLlm, FakeScraper};
use common::TestApp;
use serde_json::json;
use uuid::Uuid;

#[tokio::test]
async fn reviewed_sources_are_left_out_or_steered_by_their_notes() {
    let llm = Arc::new(FakeLlm::new(vec![
        call("plan_essay", json!({})),
        call("generate_outlines", json!({ "count": 5 })),
        call("search_sources", json!({ "count": 5 })),
        call("scrape_sources", json!({})),
        ask(
            "sourceReviewChoice",
            json!({ "inputType": "select", "options": [
                { "label": "One Shot", "value": "One Shot" },
                { "label": "Review Sources", "value": "Review Sources" },
            ]}),
        ),
        // The model asks for a plain question; the loop makes it the review.
        ask("sourceReview", json!({ "inputType": "text" })),
        call("compact_sources", json!({})),
    ]));
    let t = TestApp::agent(llm.clone(), Arc::new(FakeScraper)).await;
    let project = Uuid::new_v4();
    t.put(&format!("/v1/projects/{project}"), "alice", json!({}))
        .await;
    let run = Uuid::new_v4();
    t.post(
        &format!("/v1/projects/{project}/runs"),
        "alice",
        json!({ "runId": run, "instruction": "An essay on rising tides" }),
    )
    .await;

    let mut events = t
        .events(&format!("/v1/runs/{run}/events"), "alice", None)
        .await;
    let choice = events.until("question").await;
    assert_eq!(choice.last().unwrap()["field"], "sourceReviewChoice");
    let post = |field: &'static str, value: serde_json::Value| {
        let t = &t;
        async move {
            let (status, body) = t
                .post(
                    &format!("/v1/runs/{run}/answer"),
                    "alice",
                    json!({ "field": field, "value": value }),
                )
                .await;
            assert_eq!(status, StatusCode::OK, "{body}");
        }
    };
    post("sourceReviewChoice", json!("Review Sources")).await;

    let review = events.until("question").await;
    let question = review.last().unwrap();
    assert_eq!(question["field"], "sourceReview");
    assert_eq!(question["inputType"], "sourceReview");
    // The three sources that were read come with the question.
    let urls: Vec<&str> = question["sources"]
        .as_array()
        .unwrap()
        .iter()
        .map(|s| s["url"].as_str().unwrap())
        .collect();
    assert_eq!(
        urls,
        [
            "https://noaa.example/slr",
            "https://nature.example/retreat",
            "https://city.example/plan"
        ]
    );

    post(
        "sourceReview",
        json!([
            { "url": "https://noaa.example/slr", "focusNote": "Only the 2050 projections" },
            { "url": "https://city.example/plan", "rejected": true },
        ]),
    )
    .await;
    let ready = events.until("sources_ready").await;
    let ready = ready.last().unwrap();
    let kept: Vec<&str> = ready["sources"]
        .as_array()
        .unwrap()
        .iter()
        .map(|s| s["url"].as_str().unwrap())
        .collect();
    assert_eq!(
        kept,
        ["https://noaa.example/slr", "https://nature.example/retreat"]
    );

    // The note reached the summary of its source, and only that one.
    let compactions: Vec<String> = llm
        .sub_requests
        .lock()
        .unwrap()
        .iter()
        .filter_map(|r| r.messages[1]["content"].as_str().map(str::to_string))
        .filter(|m| m.contains("SOURCE_COMPACTION"))
        .collect();
    assert_eq!(compactions.len(), 2);
    assert!(compactions[0].ends_with("focus on: Only the 2050 projections"));
    assert!(!compactions[1].contains("focus on"));

    t.cleanup().await;
}

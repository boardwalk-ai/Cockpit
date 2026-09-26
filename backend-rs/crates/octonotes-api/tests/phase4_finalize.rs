//! Phase 4 — review, finalize, exports, recommendations, Study Studio
//! conversion (against a fake Study Studio API), reverse links, Deck search.

mod common;

use std::sync::{Arc, Mutex, OnceLock};

use axum::body::Bytes;
use axum::extract::{Path, State};
use axum::http::{HeaderMap, Method, StatusCode};
use axum::routing::post;
use axum::Router;
use common::TestApp;
use serde_json::{json, Value};
use sqlx::PgPool;
use uuid::Uuid;

/// A stand-in for Study Studio's FastAPI: same paths and response shapes,
/// writing into the stand-in studio tables of the test database.
#[derive(Clone, Default)]
struct FakeStudio {
    pool: Arc<OnceLock<PgPool>>,
    uploads: Arc<Mutex<Vec<String>>>,
}

fn user_of(h: &HeaderMap) -> Uuid {
    h.get("x-user-id")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| Uuid::parse_str(s).ok())
        .expect("on-behalf user id")
}

async fn fake_create(State(f): State<FakeStudio>, h: HeaderMap, body: axum::Json<Value>) -> String {
    let id: Uuid =
        sqlx::query_scalar("INSERT INTO studios (user_id, title) VALUES ($1, $2) RETURNING id")
            .bind(user_of(&h))
            .bind(body["title"].as_str().unwrap_or("x"))
            .fetch_one(f.pool.get().unwrap())
            .await
            .unwrap();
    format!(
        "event: data\r\ndata: {}\r\n\r\nevent: done\r\ndata: {{}}\r\n\r\n",
        json!({ "id": id, "title": body["title"] })
    )
}

async fn fake_upload(
    State(f): State<FakeStudio>,
    Path(studio): Path<Uuid>,
    h: HeaderMap,
    body: Bytes,
) -> (StatusCode, axum::Json<Value>) {
    f.uploads
        .lock()
        .unwrap()
        .push(String::from_utf8_lossy(&body).to_string());
    let doc: Uuid = sqlx::query_scalar("INSERT INTO documents (studio_id, user_id, filename, mime, object_key) VALUES ($1,$2,'n.md','text/markdown','k') RETURNING id")
        .bind(studio).bind(user_of(&h)).fetch_one(f.pool.get().unwrap()).await.unwrap();
    (
        StatusCode::ACCEPTED,
        axum::Json(json!({ "id": Uuid::new_v4(), "documentId": doc, "status": "queued" })),
    )
}

async fn fake_build(State(f): State<FakeStudio>, Path(studio): Path<Uuid>, h: HeaderMap) -> String {
    let id: Uuid = sqlx::query_scalar("INSERT INTO studio_builds (studio_id, user_id, status, stage, lessons_total) VALUES ($1,$2,'generating','Writing lessons',3) RETURNING id")
        .bind(studio).bind(user_of(&h)).fetch_one(f.pool.get().unwrap()).await.unwrap();
    format!(
        "event: data\r\ndata: {}\r\n\r\n",
        json!({ "buildId": id, "studioId": studio })
    )
}

async fn start_fake() -> (FakeStudio, String) {
    let fake = FakeStudio::default();
    let app = Router::new()
        .route("/studios", post(fake_create))
        .route("/studios/:id/documents", post(fake_upload))
        .route("/studios/:id/build", post(fake_build))
        .with_state(fake.clone());
    let l = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}", l.local_addr().unwrap());
    tokio::spawn(async move { axum::serve(l, app).await.unwrap() });
    (fake, url)
}

async fn seed_notes(t: &TestApp, sid: &str) -> Vec<String> {
    let items = [
        ("h1", "Glycolysis"),
        ("paragraph", "Glucose is split into two pyruvate molecules"),
        (
            "definition",
            "Glycolysis — the first stage of cellular respiration",
        ),
        ("paragraph", "Net yield is 2 ATP and 2 NADH"),
        ("paragraph", "DRAFT idea to drop"),
        ("h1", "Open questions"),
        ("question", "Why is it anaerobic?"),
    ];
    let mut key: Option<String> = None;
    let mut ops = Vec::new();
    let mut ids = Vec::new();
    for (i, (kind, text)) in items.iter().enumerate() {
        let k = octonotes_api::positions::between(key.as_deref(), None);
        let id = Uuid::new_v4();
        ids.push(id.to_string());
        ops.push(json!({ "clientOpId": format!("n{i}"), "op": "upsert", "blockId": id, "block": { "type": kind, "text": text, "position": k,
            "sourceRef": if i == 1 { json!({ "material": "Transcript", "location": "Professor · 3:05" }) } else { Value::Null } } }));
        key = Some(k);
    }
    t.post(
        &format!("/v1/sessions/{sid}/blocks/ops"),
        "alice",
        json!({ "ops": ops }),
    )
    .await;
    ids
}

async fn credits(t: &TestApp) -> i64 {
    t.get("/v1/me", "alice").await.1["octoCredits"]
        .as_i64()
        .unwrap()
}

#[tokio::test]
async fn review_finalize_export_convert_and_link_back() {
    let (fake, url) = start_fake().await;
    let t = TestApp::with(|c| {
        c.study_studio_api_url = Some(url.clone());
        c.service_keys = vec!["deck-secret".into()];
    })
    .await;
    fake.pool.set(t.state.studio.clone().unwrap()).unwrap();
    let sid = t.session("alice").await;
    let ids = seed_notes(&t, &sid).await;

    // Review: prepare → Smart Notes + checklist.
    let (s, r) = t
        .post(
            &format!("/v1/sessions/{sid}/review/prepare"),
            "alice",
            json!({}),
        )
        .await;
    assert_eq!(s, StatusCode::ACCEPTED, "{r}");
    t.drain_jobs().await;
    let rid = r["id"].as_str().unwrap();
    let (_, review) = t.get(&format!("/v1/reviews/{rid}"), "alice").await;
    assert_eq!(review["review"]["status"], "ready", "{review}");
    let sections = review["layers"]["smartNotes"]["sections"]
        .as_array()
        .unwrap();
    assert_eq!(
        sections
            .iter()
            .map(|s| s["blockIds"].as_array().unwrap().len())
            .sum::<usize>(),
        ids.len(),
        "every block placed once"
    );
    assert!(review["review"]["checklist"]
        .as_array()
        .unwrap()
        .iter()
        .any(|c| c["key"] == "devicesSynced" && c["state"] == "done"));

    // Decisions: drop one block, edit another. Originals stay untouched.
    let (s, _) = t.post(&format!("/v1/reviews/{rid}/decisions"), "alice", json!([
        { "blockKey": ids[4], "decision": "excluded" },
        { "blockKey": ids[3], "decision": "edited", "editedText": "Net yield: 2 ATP + 2 NADH per glucose" },
    ])).await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    let (s, _) = t
        .call(
            Method::PUT,
            &format!("/v1/reviews/{rid}/draft"),
            "alice",
            Some(json!({ "leftLayer": "studentNotes", "rightLayer": "smartNotes" })),
        )
        .await;
    assert_eq!(s, StatusCode::NO_CONTENT);

    // Finalize screen data, then Finalize (idempotent) with one topic only.
    let (_, summary) = t
        .get(&format!("/v1/sessions/{sid}/finalize/summary"), "alice")
        .await;
    assert_eq!(summary["stale"], true);
    assert_eq!(summary["outline"].as_array().unwrap().len(), 2);
    let body = json!({ "includedTopics": ["Glycolysis"], "title": "Glycolysis — Week 4" });
    let h = [("idempotency-key", "fin-1")];
    let (s1, fin) = t
        .call_with(
            Method::POST,
            &format!("/v1/sessions/{sid}/finalize"),
            "alice",
            Some(body.clone()),
            &h,
        )
        .await;
    let (s2, again) = t
        .call_with(
            Method::POST,
            &format!("/v1/sessions/{sid}/finalize"),
            "alice",
            Some(body),
            &h,
        )
        .await;
    assert_eq!(
        (s1, s2),
        (StatusCode::CREATED, StatusCode::CREATED),
        "{fin}"
    );
    assert_eq!(fin["id"], again["id"], "finalize happens once");
    let texts: Vec<&str> = fin["content"]["blocks"]
        .as_array()
        .unwrap()
        .iter()
        .map(|b| b["text"].as_str().unwrap())
        .collect();
    assert!(texts.contains(&"Net yield: 2 ATP + 2 NADH per glucose"));
    assert!(!texts.contains(&"DRAFT idea to drop"));
    assert!(
        !texts.contains(&"Why is it anaerobic?"),
        "excluded topic left out"
    );
    let (_, blocks) = t.get(&format!("/v1/sessions/{sid}/blocks"), "alice").await;
    assert_eq!(
        blocks["blocks"].as_array().unwrap().len(),
        ids.len(),
        "original notes unchanged"
    );
    let fid = fin["id"].as_str().unwrap().to_string();

    // Exports.
    for fmt in ["pdf", "md", "docx"] {
        let (s, e) = t
            .post(
                &format!("/v1/final-notes/{fid}/export"),
                "alice",
                json!({ "format": fmt }),
            )
            .await;
        assert_eq!(s, StatusCode::ACCEPTED);
        t.drain_jobs().await;
        let (_, st) = t
            .get(
                &format!("/v1/exports/{}", e["exportId"].as_str().unwrap()),
                "alice",
            )
            .await;
        assert_eq!(st["status"], "done", "{st}");
        let path = st["url"]
            .as_str()
            .unwrap()
            .trim_start_matches("http://test")
            .to_string();
        let res = tower::ServiceExt::oneshot(
            t.app.clone(),
            axum::http::Request::get(&path)
                .body(axum::body::Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
        let bytes = http_body_util::BodyExt::collect(res.into_body())
            .await
            .unwrap()
            .to_bytes();
        match fmt {
            "pdf" => assert_eq!(&bytes[..5], b"%PDF-"),
            "docx" => assert_eq!(&bytes[..2], b"PK"),
            _ => assert!(String::from_utf8_lossy(&bytes).starts_with("# Glycolysis — Week 4")),
        }
    }

    // Recommendations (built at finalize) + Home.
    let (_, reco) = t
        .get(&format!("/v1/final-notes/{fid}/recommendations"), "alice")
        .await;
    assert_eq!(reco["status"], "ready", "{reco}");
    assert_eq!(reco["topics"][0]["readiness"], "ready");
    assert!(reco["topics"][0]["activities"]
        .as_array()
        .unwrap()
        .contains(&json!("quizMe")));
    let (_, home) = t.get("/v1/home", "alice").await;
    assert_eq!(home["recommended"][0]["finalNotesId"], fid);

    // Conversion draft → options → generate.
    let (s, conv) = t
        .post("/v1/conversions", "alice", json!({ "finalNotesId": fid }))
        .await;
    assert_eq!(s, StatusCode::CREATED, "{conv}");
    let cid = conv["id"].as_str().unwrap().to_string();
    assert_eq!(conv["destination"], "createNew");
    assert_eq!(
        conv["creditEstimate"],
        100 + 2 * conv["summary"]["learningItems"].as_i64().unwrap()
    );
    let (s, v) = t
        .patch(
            &format!("/v1/conversions/{cid}"),
            "alice",
            json!({ "activities": [{ "type": "mockExam", "enabled": true }] }),
        )
        .await;
    assert_eq!(
        (s, v["code"].as_str()),
        (StatusCode::BAD_REQUEST, Some("activity_unavailable"))
    );
    let (s, conv) = t
        .patch(
            &format!("/v1/conversions/{cid}"),
            "alice",
            json!({ "level": "challenging", "activities": [{ "type": "quizMe", "count": 5 }] }),
        )
        .await;
    assert_eq!(s, StatusCode::OK, "{conv}");
    let estimate = conv["creditEstimate"].as_i64().unwrap();
    let before = credits(&t).await;
    let (s, g) = t
        .post(
            &format!("/v1/conversions/{cid}/generate"),
            "alice",
            json!({}),
        )
        .await;
    assert_eq!(s, StatusCode::ACCEPTED, "{g}");
    assert_eq!(
        before - credits(&t).await,
        estimate,
        "charged exactly the estimate"
    );
    let (s, again) = t
        .post(
            &format!("/v1/conversions/{cid}/generate"),
            "alice",
            json!({}),
        )
        .await;
    assert_eq!(
        (s, again["status"].as_str()),
        (StatusCode::ACCEPTED, Some("building")),
        "second click starts nothing"
    );
    assert_eq!(before - credits(&t).await, estimate);
    let uploaded = fake.uploads.lock().unwrap().join("");
    assert!(
        uploaded.contains("[Professor · 3:05]"),
        "source markers travel with the notes"
    );
    assert!(!uploaded.contains("DRAFT idea to drop"));

    // The build finishes in Study Studio → the follow job closes the conversion.
    let studio = g["studioId"].as_str().unwrap().to_string();
    sqlx::query("UPDATE studio_builds SET status = 'done', lessons_done = 3")
        .execute(t.state.studio.as_ref().unwrap())
        .await
        .unwrap();
    sqlx::query("UPDATE jobs SET run_after = now() WHERE kind = 'conversion.follow'")
        .execute(&t.state.notes)
        .await
        .unwrap();
    t.drain_jobs().await;
    let (_, done) = t.get(&format!("/v1/conversions/{cid}"), "alice").await;
    assert_eq!(done["status"], "done", "{done}");
    let (_, home) = t.get("/v1/home", "alice").await;
    assert!(home["recommended"].as_array().unwrap().is_empty());

    // Study Studio "View in Notes".
    let (_, links) = t
        .get(
            &format!("/v1/links?studioId={studio}&topicTitle=Glycolysis"),
            "alice",
        )
        .await;
    assert_eq!(links[0]["finalNotesId"], fid, "{links}");
    let (_, none) = t.get(&format!("/v1/links?studioId={studio}"), "bob").await;
    assert!(none.as_array().unwrap().is_empty());

    // The Deck's chat: service key on behalf of the user.
    t.drain_jobs().await;
    octonotes_api::jobs::enqueue(
        &t.state.notes,
        None,
        "embed.session",
        json!({ "sessionId": sid }),
        None,
    )
    .await
    .unwrap();
    t.drain_jobs().await;
    let alice: Uuid = sqlx::query_scalar("SELECT id FROM users WHERE firebase_uid = 'alice'")
        .fetch_one(t.state.octopilot.as_ref().unwrap())
        .await
        .unwrap();
    let (s, found) = t
        .call_with(
            Method::POST,
            "/v1/deck/search",
            "nobody",
            Some(json!({ "query": "pyruvate glucose" })),
            &[
                ("x-service-key", "deck-secret"),
                ("x-on-behalf-of", &alice.to_string()),
            ],
        )
        .await;
    assert_eq!(s, StatusCode::OK, "{found}");
    assert_eq!(found["items"][0]["sessionId"], sid);
    let (s, _) = t
        .call_with(
            Method::POST,
            "/v1/deck/search",
            "nobody",
            Some(json!({ "query": "x" })),
            &[
                ("x-service-key", "wrong"),
                ("x-on-behalf-of", &alice.to_string()),
            ],
        )
        .await;
    assert_eq!(s, StatusCode::UNAUTHORIZED);
    let events: Vec<String> = sqlx::query_scalar("SELECT kind FROM domain_events ORDER BY id")
        .fetch_all(&t.state.notes)
        .await
        .unwrap();
    assert!(
        events.contains(&"finalNotes.ready".to_string())
            && events.contains(&"conversion.done".to_string()),
        "{events:?}"
    );
    t.cleanup().await;
}

#[tokio::test]
async fn failed_conversion_is_refunded() {
    // Study Studio unreachable.
    let t = TestApp::with(|c| c.study_studio_api_url = Some("http://127.0.0.1:9".into())).await;
    let sid = t.session("alice").await;
    seed_notes(&t, &sid).await;
    let (_, fin) = t
        .post(&format!("/v1/sessions/{sid}/finalize"), "alice", json!({}))
        .await;
    t.drain_jobs().await;
    let (_, conv) = t
        .post(
            "/v1/conversions",
            "alice",
            json!({ "finalNotesId": fin["id"] }),
        )
        .await;
    let before = credits(&t).await;
    let (s, v) = t
        .post(
            &format!("/v1/conversions/{}/generate", conv["id"].as_str().unwrap()),
            "alice",
            json!({}),
        )
        .await;
    assert_eq!(
        (s, v["code"].as_str()),
        (StatusCode::BAD_GATEWAY, Some("studio_failed"))
    );
    assert_eq!(credits(&t).await, before, "refunded");
    let (_, c) = t
        .get(
            &format!("/v1/conversions/{}", conv["id"].as_str().unwrap()),
            "alice",
        )
        .await;
    assert_eq!(c["status"], "failed");
    t.cleanup().await;
}

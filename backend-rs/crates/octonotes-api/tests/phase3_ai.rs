//! Phase 3 — AI layer + OctoCredits (offline model engine; real charging on
//! the stand-in octopilot tables).

mod common;

use std::io::Write;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use common::{stroke_points, TestApp};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use tower::ServiceExt;
use uuid::Uuid;

/// POSTs and parses an SSE response into (event, data) pairs.
async fn sse(
    t: &TestApp,
    path: &str,
    user: &str,
    body: Value,
) -> (StatusCode, Vec<(String, Value)>) {
    let req = Request::builder()
        .method("POST")
        .uri(path)
        .header("x-user-id", user)
        .header("content-type", "application/json")
        .body(Body::from(body.to_string()))
        .unwrap();
    let res = t.app.clone().oneshot(req).await.unwrap();
    let status = res.status();
    let text =
        String::from_utf8(res.into_body().collect().await.unwrap().to_bytes().to_vec()).unwrap();
    if status != StatusCode::OK {
        return (
            status,
            vec![(
                "http".into(),
                serde_json::from_str(&text).unwrap_or(Value::Null),
            )],
        );
    }
    let mut events = Vec::new();
    for frame in text.split("\n\n") {
        let (mut ev, mut data) = (String::new(), String::new());
        for line in frame.lines() {
            if let Some(v) = line.strip_prefix("event:") {
                ev = v.trim().to_string();
            }
            if let Some(v) = line.strip_prefix("data:") {
                data.push_str(v.trim_start());
            }
        }
        if !ev.is_empty() {
            events.push((ev, serde_json::from_str(&data).unwrap_or(Value::Null)));
        }
    }
    (status, events)
}

fn find<'a>(events: &'a [(String, Value)], name: &str) -> &'a Value {
    &events
        .iter()
        .find(|(e, _)| e == name)
        .unwrap_or_else(|| panic!("no {name} event in {events:?}"))
        .1
}

async fn credits(t: &TestApp, user: &str) -> i64 {
    t.get("/v1/me", user).await.1["octoCredits"]
        .as_i64()
        .unwrap()
}

async fn blocks(t: &TestApp, sid: &str, items: &[(&str, &str)]) -> Vec<String> {
    let mut key: Option<String> = None;
    let mut ops = Vec::new();
    let mut ids = Vec::new();
    for (i, (kind, text)) in items.iter().enumerate() {
        let k = octonotes_api::positions::between(key.as_deref(), None);
        let id = Uuid::new_v4();
        ids.push(id.to_string());
        ops.push(json!({ "clientOpId": format!("seed{i}"), "op": "upsert", "blockId": id, "block": { "type": kind, "text": text, "position": k } }));
        key = Some(k);
    }
    let (s, _) = t
        .post(
            &format!("/v1/sessions/{sid}/blocks/ops"),
            "alice",
            json!({ "ops": ops }),
        )
        .await;
    assert_eq!(s, StatusCode::OK);
    ids
}

#[tokio::test]
async fn charging_is_atomic_idempotent_and_refundable() {
    let t = TestApp::new().await;
    let bob: Uuid = sqlx::query_scalar("SELECT id FROM users WHERE firebase_uid = 'bob'")
        .fetch_one(t.state.octopilot.as_ref().unwrap())
        .await
        .unwrap();
    // 20 parallel charges of 5 against a balance of 50: exactly 10 succeed.
    let mut handles = Vec::new();
    for i in 0..20 {
        let c = t.state.credits.clone();
        handles.push(tokio::spawn(async move {
            c.charge(bob, 5, &format!("test:par:{i}"), "parallel", json!({}))
                .await
        }));
    }
    let mut ok = 0;
    for h in handles {
        match h.await.unwrap() {
            Ok(o) if o.charged => ok += 1,
            Ok(_) => {}
            Err(e) => assert_eq!(e.code, Some("insufficient_credits")),
        }
    }
    assert_eq!(ok, 10);
    assert_eq!(credits(&t, "bob").await, 0, "never overspent");

    let alice: Uuid = sqlx::query_scalar("SELECT id FROM users WHERE firebase_uid = 'alice'")
        .fetch_one(t.state.octopilot.as_ref().unwrap())
        .await
        .unwrap();
    let a = t
        .state
        .credits
        .charge(alice, 100, "test:once", "x", json!({}))
        .await
        .unwrap();
    let b = t
        .state
        .credits
        .charge(alice, 100, "test:once", "x", json!({}))
        .await
        .unwrap();
    assert!(a.charged && !b.charged, "same source_ref charges once");
    assert_eq!(credits(&t, "alice").await, 9900);
    let r1 = t
        .state
        .credits
        .refund(alice, "test:once", "failed build")
        .await
        .unwrap();
    let r2 = t
        .state
        .credits
        .refund(alice, "test:once", "failed build")
        .await
        .unwrap();
    assert!(r1.charged && !r2.charged);
    assert_eq!(credits(&t, "alice").await, 10000);

    let (s, prices) = t.get("/v1/me/pricing", "alice").await;
    assert_eq!(s, StatusCode::OK);
    assert!(prices
        .as_array()
        .unwrap()
        .iter()
        .any(|p| p["action"] == "suggest" && p["credits"] == 2));
    t.cleanup().await;
}

#[tokio::test]
async fn suggestions_never_touch_student_text_until_applied() {
    let t = TestApp::new().await;
    let sid = t.session("alice").await;
    let ids = blocks(
        &t,
        &sid,
        &[
            ("h1", "Cellular Respiration"),
            (
                "paragraph",
                "Glycolysis splits glucose into two pyruvate molecules in the cytoplasm",
            ),
        ],
    )
    .await;
    let before = t
        .get(&format!("/v1/sessions/{sid}/blocks"), "alice")
        .await
        .1;

    let (s, events) = sse(
        &t,
        &format!("/v1/sessions/{sid}/ai/suggest"),
        "alice",
        json!({ "blockId": ids[1], "action": "explain" }),
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    assert!(events.iter().any(|(e, _)| e == "delta"));
    let suggestion = find(&events, "result")["suggestion"].clone();
    assert_eq!(find(&events, "done")["creditsCharged"], 2);
    assert_eq!(credits(&t, "alice").await, 9998);
    // Rule: the AI call itself changed no block.
    assert_eq!(
        t.get(&format!("/v1/sessions/{sid}/blocks"), "alice")
            .await
            .1,
        before
    );

    let sug_id = suggestion["id"].as_str().unwrap();
    let (s, block) = t
        .post(
            &format!("/v1/ai/suggestions/{sug_id}/apply"),
            "alice",
            json!({ "mode": "asExplanation" }),
        )
        .await;
    assert_eq!(s, StatusCode::OK, "{block}");
    assert_eq!(block["origin"], "aiInsertedByStudent");
    assert_eq!(block["indent"], 1);
    let (s, _) = t
        .post(
            &format!("/v1/ai/suggestions/{sug_id}/apply"),
            "alice",
            json!({ "mode": "insertBelow" }),
        )
        .await;
    assert_eq!(s, StatusCode::CONFLICT, "applied once only");
    // Clients still can't rewrite the AI block's text.
    let (_, r) = t.post(&format!("/v1/sessions/{sid}/blocks/ops"), "alice", json!({ "ops": [{ "clientOpId": "x", "op": "upsert", "blockId": block["id"], "baseRevision": 1, "block": { "text": "forged" } }] })).await;
    assert_eq!(r["results"][0]["status"], "rejected");

    // Replace Selection needs the revision the student saw.
    let (_, ev2) = sse(
        &t,
        &format!("/v1/sessions/{sid}/ai/suggest"),
        "alice",
        json!({ "blockId": ids[1], "action": "simplify" }),
    )
    .await;
    let sug2 = find(&ev2, "result")["suggestion"]["id"]
        .as_str()
        .unwrap()
        .to_string();
    let body2 = find(&ev2, "result")["suggestion"]["body"]
        .as_str()
        .unwrap()
        .to_string();
    let (s, _) = t.post(&format!("/v1/ai/suggestions/{sug2}/apply"), "alice", json!({ "mode": "replaceSelection", "selection": "two pyruvate molecules", "baseRevision": 9 })).await;
    assert_eq!(s, StatusCode::CONFLICT);
    let (s, replaced) = t.post(&format!("/v1/ai/suggestions/{sug2}/apply"), "alice", json!({ "mode": "replaceSelection", "selection": "two pyruvate molecules", "baseRevision": 1 })).await;
    assert_eq!(s, StatusCode::OK, "{replaced}");
    assert!(
        replaced["text"].as_str().unwrap().contains(&body2),
        "{replaced}"
    );
    assert!(replaced["text"]
        .as_str()
        .unwrap()
        .starts_with("Glycolysis splits glucose into "));
    assert_eq!(replaced["revision"], 2);
    let (_, hist) = t
        .get(&format!("/v1/blocks/{}/history", ids[1]), "alice")
        .await;
    assert_eq!(
        hist.as_array().unwrap().len(),
        2,
        "the student's original is kept"
    );
    t.cleanup().await;
}

#[tokio::test]
async fn what_did_i_miss_insert_and_limits() {
    let t = TestApp::new().await;
    let sid = t.session("alice").await;
    blocks(
        &t,
        &sid,
        &[
            (
                "paragraph",
                "ATP synthase makes ATP from the proton gradient",
            ),
            ("question", "Why does the chain need oxygen?"),
        ],
    )
    .await;
    let (_, events) = sse(
        &t,
        &format!("/v1/sessions/{sid}/ai/command"),
        "alice",
        json!({ "command": "What did I miss?", "contexts": [{ "type": "session" }] }),
    )
    .await;
    let result = find(&events, "result");
    assert!(result["points"].as_array().is_some());
    let run = find(&events, "done")["runId"].as_str().unwrap().to_string();
    let (s, ins) = t
        .post(
            &format!("/v1/ai/runs/{run}/insert"),
            "alice",
            json!({ "mode": "insertBelow" }),
        )
        .await;
    assert_eq!(s, StatusCode::OK, "{ins}");
    assert!(ins["blocks"]
        .as_array()
        .unwrap()
        .iter()
        .all(|b| b["origin"] == "aiInsertedByStudent" && b["type"] == "bulleted"));

    let (_, ev) = sse(
        &t,
        &format!("/v1/sessions/{sid}/ai/command"),
        "alice",
        json!({ "command": "explain oxidative phosphorylation" }),
    )
    .await;
    let r = find(&ev, "result");
    assert_eq!(r["sourcesAgree"], true);
    assert!(
        !r["body"].as_str().unwrap().contains("SOURCES:"),
        "marker line stripped"
    );
    let (_, hist) = t
        .get(&format!("/v1/sessions/{sid}/ai/history"), "alice")
        .await;
    assert_eq!(hist.as_array().unwrap().len(), 2);

    // Not enough credits → 402 before anything runs.
    let bob_sid = t.session("bob").await;
    sqlx::query(
        "INSERT INTO system_settings (key, value) VALUES ('octonotes_price_summarize', '500')",
    )
    .execute(t.state.octopilot.as_ref().unwrap())
    .await
    .unwrap();
    t.state.prices.invalidate();
    let (s, err) = sse(
        &t,
        &format!("/v1/sessions/{bob_sid}/summarize"),
        "bob",
        json!({}),
    )
    .await;
    assert_eq!(s, StatusCode::PAYMENT_REQUIRED);
    assert_eq!(err[0].1["code"], "insufficient_credits");
    assert_eq!(err[0].1["details"]["needed"], 500);
    let runs: i64 = sqlx::query_scalar("SELECT count(*) FROM ai_runs WHERE kind = 'summarize'")
        .fetch_one(&t.state.notes)
        .await
        .unwrap();
    assert_eq!(runs, 0);

    // 30 AI calls a minute per user, then 429.
    let mut last = StatusCode::OK;
    for _ in 0..31 {
        last = sse(
            &t,
            &format!("/v1/sessions/{sid}/ai/command"),
            "alice",
            json!({ "command": "summarize" }),
        )
        .await
        .0;
    }
    assert_eq!(last, StatusCode::TOO_MANY_REQUESTS);
    t.cleanup().await;
}

/// A minimal valid PDF with one line of Helvetica text per page.
fn pdf(pages: &[&str]) -> Vec<u8> {
    let mut objs: Vec<String> = vec![
        "<< /Type /Catalog /Pages 2 0 R >>".into(),
        String::new(),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>".into(),
    ];
    let mut kids = Vec::new();
    for text in pages {
        let stream = format!("BT /F1 24 Tf 72 700 Td ({text}) Tj ET");
        let content_id = objs.len() + 2;
        objs.push(format!("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R >> >> /Contents {content_id} 0 R >>"));
        kids.push(format!("{} 0 R", objs.len()));
        objs.push(format!(
            "<< /Length {} >>\nstream\n{stream}\nendstream",
            stream.len()
        ));
    }
    objs[1] = format!(
        "<< /Type /Pages /Kids [{}] /Count {} >>",
        kids.join(" "),
        pages.len()
    );
    let mut out = b"%PDF-1.4\n".to_vec();
    let mut offsets = Vec::new();
    for (i, o) in objs.iter().enumerate() {
        offsets.push(out.len());
        out.extend_from_slice(format!("{} 0 obj\n{o}\nendobj\n", i + 1).as_bytes());
    }
    let xref = out.len();
    out.extend_from_slice(format!("xref\n0 {}\n0000000000 65535 f \n", objs.len() + 1).as_bytes());
    for off in offsets {
        out.extend_from_slice(format!("{off:010} 00000 n \n").as_bytes());
    }
    out.extend_from_slice(
        format!(
            "trailer\n<< /Size {} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n",
            objs.len() + 1
        )
        .as_bytes(),
    );
    out
}

fn pptx(slides: &[&str]) -> Vec<u8> {
    let mut buf = std::io::Cursor::new(Vec::new());
    {
        let mut z = zip::ZipWriter::new(&mut buf);
        let opt = zip::write::SimpleFileOptions::default();
        for (i, s) in slides.iter().enumerate() {
            z.start_file(format!("ppt/slides/slide{}.xml", i + 1), opt)
                .unwrap();
            write!(z, "<p:sld><a:p><a:r><a:t>{s}</a:t></a:r></a:p></p:sld>").unwrap();
        }
        z.finish().unwrap();
    }
    buf.into_inner()
}

async fn upload(t: &TestApp, sid: &str, name: &str, bytes: Vec<u8>) -> (StatusCode, Value) {
    let boundary = "----octonotesboundary";
    let mut body = format!("--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{name}\"\r\nContent-Type: application/octet-stream\r\n\r\n").into_bytes();
    body.extend(bytes);
    body.extend(format!("\r\n--{boundary}--\r\n").into_bytes());
    let req = Request::builder()
        .method("POST")
        .uri(format!("/v1/sessions/{sid}/materials"))
        .header("x-user-id", "alice")
        .header(
            "content-type",
            format!("multipart/form-data; boundary={boundary}"),
        )
        .body(Body::from(body))
        .unwrap();
    let res = t.app.clone().oneshot(req).await.unwrap();
    let s = res.status();
    (
        s,
        serde_json::from_slice(&res.into_body().collect().await.unwrap().to_bytes())
            .unwrap_or(Value::Null),
    )
}

#[tokio::test]
async fn materials_research_and_relevant_data() {
    let t = TestApp::new().await;
    let sid = t.session("alice").await;
    let (s, m) = upload(
        &t,
        &sid,
        "week4.pdf",
        pdf(&[
            "Glycolysis in the cytoplasm",
            "Electron transport chain needs oxygen",
        ]),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{m}");
    let (s, deck) = upload(
        &t,
        &sid,
        "lecture.pptx",
        pptx(&["ATP synthase", "Chemiosmosis and the proton gradient"]),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{deck}");
    let (s, v) = upload(&t, &sid, "evil.pdf", b"MZ\x90\x00not a pdf".to_vec()).await;
    assert_eq!(
        (s, v["code"].as_str()),
        (StatusCode::BAD_REQUEST, Some("unsupported_type"))
    );
    t.drain_jobs().await;

    let mid = m["id"].as_str().unwrap();
    let (_, pages) = t.get(&format!("/v1/materials/{mid}/pages"), "alice").await;
    assert_eq!(pages.as_array().unwrap().len(), 2, "{pages}");
    assert!(pages[1]["ocrText"]
        .as_str()
        .unwrap()
        .contains("Electron transport chain"));
    assert_eq!(pages[1]["ocrConfidence"], "high");
    let (_, slides) = t
        .get(
            &format!("/v1/materials/{}/pages", deck["id"].as_str().unwrap()),
            "alice",
        )
        .await;
    assert_eq!(slides[1]["title"], "Chemiosmosis and the proton gradient");

    // Indexed for retrieval; Relevant Data finds the right page.
    let (_, rel) = t
        .get(
            &format!("/v1/sessions/{sid}/relevant?q=oxygen%20electron%20transport"),
            "alice",
        )
        .await;
    assert_eq!(rel["items"][0]["kind"], "slide", "{rel}");
    assert!(rel["items"][0]["label"]
        .as_str()
        .unwrap()
        .contains("Slide 2"));

    // Link to note + quote a slide into the notes.
    let (s, block) = t
        .post(
            &format!("/v1/sessions/{sid}/blocks/from-source"),
            "alice",
            json!({ "kind": "slide", "sourceId": format!("{mid}:2") }),
        )
        .await;
    assert_eq!(s, StatusCode::CREATED, "{block}");
    assert_eq!(
        (block["origin"].as_str(), block["type"].as_str()),
        (Some("fromSlide"), Some("slideRef"))
    );
    let (_, pages) = t.get(&format!("/v1/materials/{mid}/pages"), "alice").await;
    assert_eq!(pages[1]["noteBlockLinks"], 1);

    // Research: course evidence first, applied into the notes, saved.
    let (s, events) = sse(&t, &format!("/v1/sessions/{sid}/research"), "alice", json!({ "question": "Why does the electron transport chain need oxygen?", "depth": "quick" })).await;
    assert_eq!(s, StatusCode::OK);
    let result = find(&events, "result");
    assert!(
        result["evidence"]
            .as_array()
            .unwrap()
            .iter()
            .any(|e| e["kind"] == "courseSlide"),
        "{result}"
    );
    assert_eq!(result["courseSearchedFirst"], true);
    assert_eq!(find(&events, "done")["creditsCharged"], 10);
    let rid = result["researchId"].as_str().unwrap();
    let (s, b) = t
        .post(
            &format!("/v1/research/{rid}/apply"),
            "alice",
            json!({ "mode": "insertBelow" }),
        )
        .await;
    assert_eq!(s, StatusCode::CREATED);
    assert!(!b["aiSources"].as_array().unwrap().is_empty());
    let (s, _) = t
        .post(&format!("/v1/research/{rid}/save"), "alice", json!({}))
        .await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    let (_, list) = t
        .get(&format!("/v1/sessions/{sid}/research"), "alice")
        .await;
    assert_eq!(list[0]["saved"], true);

    // Summarize → topics from the headings.
    blocks(
        &t,
        &sid,
        &[
            ("h1", "Glycolysis"),
            ("paragraph", "Glucose to pyruvate"),
            ("h2", "Electron transport chain"),
            ("paragraph", "Oxygen is the final electron acceptor"),
        ],
    )
    .await;
    let (_, ev) = sse(
        &t,
        &format!("/v1/sessions/{sid}/summarize"),
        "alice",
        json!({}),
    )
    .await;
    let topics = find(&ev, "result")["topics"].as_array().unwrap().clone();
    assert!(
        topics
            .iter()
            .any(|x| x["title"] == "Electron transport chain"),
        "{topics:?}"
    );
    t.cleanup().await;
}

#[tokio::test]
async fn organize_apply_and_undo_are_one_reversible_pass() {
    let t = TestApp::new().await;
    let sid = t.session("alice").await;
    let ids = blocks(
        &t,
        &sid,
        &[
            ("h1", "Respiration"),
            ("question", "Is glycolysis aerobic?"),
            ("paragraph", "Glycolysis makes 2 ATP"),
            ("paragraph", "The ETC makes most ATP"),
        ],
    )
    .await;
    let order = |v: &Value| {
        v["blocks"]
            .as_array()
            .unwrap()
            .iter()
            .map(|b| b["id"].as_str().unwrap().to_string())
            .collect::<Vec<_>>()
    };
    let before = order(
        &t.get(&format!("/v1/sessions/{sid}/blocks"), "alice")
            .await
            .1,
    );

    let (s, p) = t
        .post(
            &format!("/v1/sessions/{sid}/organize/preview"),
            "alice",
            json!({}),
        )
        .await;
    assert_eq!(s, StatusCode::OK, "{p}");
    let preview = &p["preview"];
    assert_eq!(preview["suggestions"][0]["confidence"], "high");
    assert_eq!(
        order(
            &t.get(&format!("/v1/sessions/{sid}/blocks"), "alice")
                .await
                .1
        ),
        before,
        "preview moves nothing"
    );

    let pass = preview["passId"].as_str().unwrap();
    let (s, r) = t
        .post(
            &format!("/v1/organize/{pass}/apply"),
            "alice",
            json!({ "all": true }),
        )
        .await;
    assert_eq!(s, StatusCode::OK, "{r}");
    let after = order(
        &t.get(&format!("/v1/sessions/{sid}/blocks"), "alice")
            .await
            .1,
    );
    assert_eq!(after.last().unwrap(), &ids[1], "question moved to the end");

    let (s, u) = t
        .post(&format!("/v1/organize/{pass}/undo"), "alice", json!({}))
        .await;
    assert_eq!(s, StatusCode::OK, "{u}");
    assert_eq!(
        order(
            &t.get(&format!("/v1/sessions/{sid}/blocks"), "alice")
                .await
                .1
        ),
        before,
        "undo restores the order"
    );
    let (s, _) = t
        .post(&format!("/v1/organize/{pass}/undo"), "alice", json!({}))
        .await;
    assert_eq!(s, StatusCode::CONFLICT);
    t.cleanup().await;
}

#[tokio::test]
async fn handwriting_and_metered_transcription() {
    let t = TestApp::new().await;
    let sid = t.session("alice").await;
    let page = Uuid::new_v4();
    t.post(
        &format!("/v1/sessions/{sid}/ink/pages"),
        "alice",
        json!({ "id": page }),
    )
    .await;
    let stroke = Uuid::new_v4();
    t.post(&format!("/v1/ink/pages/{page}/ops"), "alice", json!({ "ops": [{ "clientOpId": "s1", "op": "add", "strokeId": stroke,
        "stroke": { "tool": "pen", "points": stroke_points(&[(0.0, 0.0, 0.5), (40.0, 30.0, 0.5), (80.0, 5.0, 0.5)]) } }] })).await;
    let (s, r) = t
        .post(
            &format!("/v1/ink/pages/{page}/recognize"),
            "alice",
            json!({ "strokeIds": [stroke] }),
        )
        .await;
    assert_eq!(s, StatusCode::CREATED, "{r}");
    assert_eq!(r["recognition"]["status"], "proposed");
    let rec = r["recognition"]["id"].as_str().unwrap();
    let (s, v) = t
        .patch(
            &format!("/v1/ink/recognitions/{rec}"),
            "alice",
            json!({ "status": "corrected", "text": "ATP = energy currency" }),
        )
        .await;
    assert_eq!(
        (s, v["text"].as_str()),
        (StatusCode::OK, Some("ATP = energy currency"))
    );
    let (s, block) = t
        .post(
            &format!("/v1/sessions/{sid}/blocks/from-source"),
            "alice",
            json!({ "kind": "ink", "sourceId": rec }),
        )
        .await;
    assert_eq!(s, StatusCode::CREATED, "{block}");
    assert_eq!(
        (block["origin"].as_str(), block["text"].as_str()),
        (Some("fromInk"), Some("ATP = energy currency"))
    );
    let strokes = t
        .get(&format!("/v1/ink/pages/{page}/strokes"), "alice")
        .await
        .1;
    assert_eq!(
        strokes["strokes"].as_array().unwrap().len(),
        1,
        "ink untouched"
    );

    // 1 h 1 min of live transcription → 30 OC now, 60 s carried over.
    let alice: Uuid = sqlx::query_scalar("SELECT id FROM users WHERE firebase_uid = 'alice'")
        .fetch_one(t.state.octopilot.as_ref().unwrap())
        .await
        .unwrap();
    let before = credits(&t, "alice").await;
    sqlx::query("INSERT INTO usage_meter (user_id, kind, quantity, ref) VALUES ($1,'asr_seconds',1800,'a'), ($1,'asr_seconds',1860,'b')")
        .bind(alice).execute(&t.state.notes).await.unwrap();
    octonotes_api::jobs::enqueue(&t.state.notes, None, "system.meter", json!({}), None)
        .await
        .unwrap();
    t.drain_jobs().await;
    assert_eq!(before - credits(&t, "alice").await, 30);
    let carry: f64 =
        sqlx::query_scalar("SELECT sum(quantity) FROM usage_meter WHERE charged_at IS NULL")
            .fetch_one(&t.state.notes)
            .await
            .unwrap();
    assert!((carry - 60.0).abs() < 0.01);
    t.cleanup().await;
}

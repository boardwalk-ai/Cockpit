//! Integration-test harness: a fresh Postgres database per test, holding
//! notes_db (migrated) plus the dev stand-ins for the shared `users` and Study
//! Studio tables, and the app served in-process (no network).
//!
//! `TEST_PG_URL` (default: the dev compose Postgres, `postgres://octonotes:octonotes@127.0.0.1:5435`) must
//! be a server where the user can CREATE DATABASE. Phase 3+ tests need the
//! pgvector extension available there (the dev compose image has it).
#![allow(dead_code)]

use axum::body::Body;
use axum::http::{Method, Request, StatusCode};
use axum::Router;
use http_body_util::BodyExt;
use octonotes_api::config::Config;
use octonotes_api::{app, AppState};
use serde_json::Value;
use sqlx::{Connection, Executor, PgConnection};
use tower::ServiceExt;
use uuid::Uuid;

pub struct TestApp {
    pub app: Router,
    pub state: AppState,
    pub db: String,
    admin: String,
    pub storage_dir: std::path::PathBuf,
}

pub fn admin_url() -> String {
    std::env::var("TEST_PG_URL").unwrap_or_else(|_| "postgres://octonotes:octonotes@127.0.0.1:5435".into())
}

impl TestApp {
    pub async fn new() -> Self {
        Self::with(|_| {}).await
    }

    /// A fresh app; `tweak` adjusts the config before it starts.
    pub async fn with(tweak: impl FnOnce(&mut Config)) -> Self {
        let admin = admin_url();
        let db = format!("octonotes_test_{}", Uuid::new_v4().simple());
        let mut conn = PgConnection::connect(&format!("{admin}/postgres")).await.expect("connect admin db");
        conn.execute(format!("CREATE DATABASE {db}").as_str()).await.expect("create test db");
        conn.close().await.ok();

        let url = format!("{admin}/{db}");
        let mut c = PgConnection::connect(&url).await.expect("connect test db");
        c.execute(include_str!("../../dev/octopilot_dev.sql")).await.expect("users stand-in");
        c.execute(include_str!("../../dev/studio_dev.sql")).await.expect("studio stand-in");
        c.execute(
            "INSERT INTO users (firebase_uid, email, name, plan, octo_credits) VALUES \
             ('alice', 'alice@test', 'Alice', 'Pro Monthly', 10000), \
             ('bob', 'bob@test', 'Bob', 'Pro Monthly', 50)",
        )
        .await
        .expect("seed users");
        c.close().await.ok();

        let storage_dir = std::env::temp_dir().join(&db);
        let mut config = Config::from_env();
        config.notes_database_url = url.clone();
        config.octopilot_database_url = Some(url.clone());
        config.studio_database_url = Some(url.clone());
        config.studio_vector_database_url = None;
        config.firebase_project_id = String::new();
        config.storage_dir = storage_dir.to_string_lossy().to_string();
        config.redis_url = None;
        config.s3_endpoint = None;
        config.embed_url = None;
        config.study_studio_api_url = None;
        config.public_base_url = "http://test".into();
        tweak(&mut config);
        let state = AppState::connect(config).await.expect("app state");
        TestApp { app: app(state.clone()), state, db, admin, storage_dir }
    }

    pub async fn call(&self, method: Method, path: &str, user: &str, body: Option<Value>) -> (StatusCode, Value) {
        self.call_with(method, path, user, body, &[]).await
    }

    pub async fn call_with(&self, method: Method, path: &str, user: &str, body: Option<Value>, headers: &[(&str, &str)]) -> (StatusCode, Value) {
        let mut req = Request::builder().method(method).uri(path).header("x-user-id", user);
        for (k, v) in headers {
            req = req.header(*k, *v);
        }
        let req = match body {
            Some(b) => req.header("content-type", "application/json").body(Body::from(b.to_string())),
            None => req.body(Body::empty()),
        }
        .expect("request");
        let res = self.app.clone().oneshot(req).await.expect("response");
        let status = res.status();
        let bytes = res.into_body().collect().await.expect("body").to_bytes();
        let value = if bytes.is_empty() { Value::Null } else { serde_json::from_slice(&bytes).unwrap_or(Value::String(String::from_utf8_lossy(&bytes).into())) };
        (status, value)
    }

    /// Sends raw bytes (audio chunk uploads).
    pub async fn put_bytes(&self, path: &str, user: &str, bytes: Vec<u8>, content_type: &str) -> (StatusCode, Value) {
        let req = Request::builder()
            .method(Method::PUT)
            .uri(path)
            .header("x-user-id", user)
            .header("content-type", content_type)
            .body(Body::from(bytes))
            .expect("request");
        let res = self.app.clone().oneshot(req).await.expect("response");
        let status = res.status();
        let bytes = res.into_body().collect().await.expect("body").to_bytes();
        (status, serde_json::from_slice(&bytes).unwrap_or(Value::Null))
    }

    pub async fn get(&self, path: &str, user: &str) -> (StatusCode, Value) {
        self.call(Method::GET, path, user, None).await
    }
    pub async fn post(&self, path: &str, user: &str, body: Value) -> (StatusCode, Value) {
        self.call(Method::POST, path, user, Some(body)).await
    }
    pub async fn patch(&self, path: &str, user: &str, body: Value) -> (StatusCode, Value) {
        self.call(Method::PATCH, path, user, Some(body)).await
    }
    pub async fn delete(&self, path: &str, user: &str) -> (StatusCode, Value) {
        self.call(Method::DELETE, path, user, None).await
    }

    /// Creates a session for `user` and returns its id.
    pub async fn session(&self, user: &str) -> String {
        let (s, v) = self.post("/v1/sessions", user, serde_json::json!({ "title": "Cellular Respiration" })).await;
        assert_eq!(s, StatusCode::CREATED, "{v}");
        v["id"].as_str().expect("id").to_string()
    }

    /// Runs queued background jobs to completion.
    pub async fn drain_jobs(&self) {
        octonotes_api::jobs::drain(&self.state).await;
    }

    pub async fn cleanup(self) {
        self.state.notes.close().await;
        if let Some(p) = &self.state.octopilot {
            p.close().await;
        }
        if let Some(p) = &self.state.studio {
            p.close().await;
        }
        drop(self.app);
        drop(self.state);
        if let Ok(mut conn) = PgConnection::connect(&format!("{}/postgres", self.admin)).await {
            let _ = conn.execute(format!("DROP DATABASE IF EXISTS {} WITH (FORCE)", self.db).as_str()).await;
        }
        let _ = std::fs::remove_dir_all(&self.storage_dir);
    }
}

/// Packs points into stroke format v1, base64.
pub fn stroke_points(points: &[(f32, f32, f32)]) -> String {
    use base64::Engine;
    let mut b = vec![1u8];
    b.extend_from_slice(&(points.len() as u32).to_le_bytes());
    for (x, y, p) in points {
        b.extend_from_slice(&x.to_le_bytes());
        b.extend_from_slice(&y.to_le_bytes());
        b.extend_from_slice(&p.to_le_bytes());
    }
    base64::engine::general_purpose::STANDARD.encode(b)
}

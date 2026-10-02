//! Integration-test harness: a fresh Postgres database per test, holding the
//! migrated ghostwriter schema plus the dev stand-in for the shared `users`
//! table, and the app served in-process (no network).
//!
//! `TEST_PG_URL` (default `postgres://postgres:postgres@127.0.0.1:5432`) must
//! be a server where the user can CREATE DATABASE.
#![allow(dead_code)]

use axum::body::Body;
use axum::http::{Method, Request, StatusCode};
use axum::Router;
use ghostwriter_api::config::Config;
use ghostwriter_api::{app, AppState};
use http_body_util::BodyExt;
use serde_json::Value;
use sqlx::{Connection, Executor, PgConnection};
use tower::ServiceExt;
use uuid::Uuid;

pub struct TestApp {
    pub app: Router,
    pub state: AppState,
    pub db: String,
    admin: String,
}

pub fn admin_url() -> String {
    std::env::var("TEST_PG_URL")
        .unwrap_or_else(|_| "postgres://postgres:postgres@127.0.0.1:5432".into())
}

impl TestApp {
    /// A fresh app with two accounts: `alice` (10,000 OC) and `bob` (50 OC).
    pub async fn new() -> Self {
        let admin = admin_url();
        let db = format!("ghostwriter_test_{}", Uuid::new_v4().simple());
        let mut conn = PgConnection::connect(&format!("{admin}/postgres"))
            .await
            .expect("connect admin db");
        conn.execute(format!("CREATE DATABASE {db}").as_str())
            .await
            .expect("create test db");
        conn.close().await.ok();

        let url = format!("{admin}/{db}");
        let mut c = PgConnection::connect(&url).await.expect("connect test db");
        // One stand-in for the shared octopilot tables, kept with octonotes-api.
        c.execute(include_str!("../../../octonotes-api/dev/octopilot_dev.sql"))
            .await
            .expect("users stand-in");
        c.execute(
            "INSERT INTO users (firebase_uid, email, name, plan, octo_credits) VALUES \
             ('alice', 'alice@test', 'Alice', 'Pro Monthly', 10000), \
             ('bob', 'bob@test', 'Bob', 'Pro Monthly', 50)",
        )
        .await
        .expect("seed users");
        c.close().await.ok();

        let mut config = Config::from_env();
        config.ghostwriter_database_url = url.clone();
        config.octopilot_database_url = Some(url);
        config.firebase_project_id = String::new();
        let state = AppState::connect(config).await.expect("app state");
        TestApp {
            app: app(state.clone()),
            state,
            db,
            admin,
        }
    }

    /// Sends a request as `user` (the dev `X-User-Id` identity).
    pub async fn call(
        &self,
        method: Method,
        path: &str,
        user: &str,
        body: Option<Value>,
    ) -> (StatusCode, Value) {
        let req = Request::builder()
            .method(method)
            .uri(path)
            .header("x-user-id", user);
        let req = match body {
            Some(b) => req
                .header("content-type", "application/json")
                .body(Body::from(b.to_string())),
            None => req.body(Body::empty()),
        }
        .expect("request");
        let res = self.app.clone().oneshot(req).await.expect("response");
        let status = res.status();
        let bytes = res.into_body().collect().await.expect("body").to_bytes();
        let value = if bytes.is_empty() {
            Value::Null
        } else {
            serde_json::from_slice(&bytes)
                .unwrap_or_else(|_| Value::String(String::from_utf8_lossy(&bytes).into_owned()))
        };
        (status, value)
    }

    pub async fn get(&self, path: &str, user: &str) -> (StatusCode, Value) {
        self.call(Method::GET, path, user, None).await
    }

    pub async fn put(&self, path: &str, user: &str, body: Value) -> (StatusCode, Value) {
        self.call(Method::PUT, path, user, Some(body)).await
    }

    pub async fn delete(&self, path: &str, user: &str) -> (StatusCode, Value) {
        self.call(Method::DELETE, path, user, None).await
    }

    /// Drops the test database. Call at the end of every test.
    pub async fn cleanup(self) {
        self.state.db.close().await;
        if let Some(p) = &self.state.octopilot {
            p.close().await;
        }
        drop(self.app);
        drop(self.state);
        if let Ok(mut conn) = PgConnection::connect(&format!("{}/postgres", self.admin)).await {
            let _ = conn
                .execute(format!("DROP DATABASE IF EXISTS {} WITH (FORCE)", self.db).as_str())
                .await;
        }
    }
}

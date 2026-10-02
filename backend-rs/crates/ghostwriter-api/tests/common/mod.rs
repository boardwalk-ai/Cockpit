//! Integration-test harness: a fresh Postgres database per test, holding the
//! migrated ghostwriter schema plus the dev stand-in for the shared `users`
//! table, and the app served in-process (no network).
//!
//! `TEST_PG_URL` (default `postgres://postgres:postgres@127.0.0.1:5432`) must
//! be a server where the user can CREATE DATABASE.
#![allow(dead_code)]

pub mod fakes;

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
        Self::with(|_| {}).await
    }

    /// A fresh app; `tweak` adjusts the config before it starts.
    pub async fn with(tweak: impl FnOnce(&mut Config)) -> Self {
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
        config.scripted_step = std::time::Duration::ZERO;
        // Most scripted tests end at the essay; the humanizer tests turn this on.
        config.scripted_humanizer = false;
        config.driver = "scripted".into();
        tweak(&mut config);
        let state = AppState::connect(config).await.expect("app state");
        TestApp {
            app: app(state.clone()),
            state,
            db,
            admin,
        }
    }

    /// A fresh scripted app that pushes through `pusher`.
    pub async fn with_pusher(
        tweak: impl FnOnce(&mut Config),
        pusher: std::sync::Arc<fakes::FakePusher>,
    ) -> Self {
        let mut t = Self::with(tweak).await;
        t.state.pusher = pusher;
        t.app = app(t.state.clone());
        t
    }

    /// A fresh app whose runs are driven by the agent loop, with the model and
    /// the scraper replaced by test doubles.
    pub async fn agent(
        llm: std::sync::Arc<dyn ghostwriter_api::llm::Llm>,
        scraper: std::sync::Arc<dyn ghostwriter_api::scrape::Scraper>,
    ) -> Self {
        let mut t = Self::with(|config| config.driver = "agent".into()).await;
        t.state.llm = Some(llm);
        t.state.scraper = scraper;
        t.state.humanizer = std::sync::Arc::new(fakes::FakeHumanizer::default());
        t.app = app(t.state.clone());
        t
    }

    /// [`TestApp::agent`] with a humanizer the test holds on to.
    pub async fn agent_with_humanizer(
        llm: std::sync::Arc<dyn ghostwriter_api::llm::Llm>,
        humanizer: std::sync::Arc<fakes::FakeHumanizer>,
    ) -> Self {
        let mut t = Self::agent(llm, std::sync::Arc::new(fakes::FakeScraper)).await;
        t.state.humanizer = humanizer;
        t.app = app(t.state.clone());
        t
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

    pub async fn post(&self, path: &str, user: &str, body: Value) -> (StatusCode, Value) {
        self.call(Method::POST, path, user, Some(body)).await
    }

    /// Opens a Server-Sent Events stream. `last_event_id` sets that header.
    pub async fn events(&self, path: &str, user: &str, last_event_id: Option<i64>) -> EventStream {
        let mut req = Request::builder()
            .method(Method::GET)
            .uri(path)
            .header("x-user-id", user);
        if let Some(id) = last_event_id {
            req = req.header("last-event-id", id.to_string());
        }
        let res = self
            .app
            .clone()
            .oneshot(req.body(Body::empty()).expect("request"))
            .await
            .expect("response");
        assert_eq!(res.status(), StatusCode::OK, "events stream for {path}");
        EventStream {
            body: res.into_body().into_data_stream(),
            buffer: String::new(),
        }
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

/// A Server-Sent Events response, read one event at a time.
pub struct EventStream {
    body: axum::body::BodyDataStream,
    buffer: String,
}

impl EventStream {
    /// The next event's JSON, or `None` when the stream has ended. Panics if
    /// nothing arrives for five seconds, so a stuck run fails the test.
    pub async fn next(&mut self) -> Option<Value> {
        use futures::StreamExt;
        loop {
            if let Some(end) = self.buffer.find(
                "

",
            ) {
                let frame: String = self.buffer.drain(..end + 2).collect();
                let data: String = frame
                    .lines()
                    .filter_map(|line| line.strip_prefix("data:"))
                    .map(str::trim_start)
                    .collect();
                if data.is_empty() {
                    continue; // a keep-alive comment
                }
                return Some(serde_json::from_str(&data).expect("event json"));
            }
            let chunk = tokio::time::timeout(std::time::Duration::from_secs(5), self.body.next())
                .await
                .expect("an event within five seconds");
            match chunk {
                Some(bytes) => self
                    .buffer
                    .push_str(&String::from_utf8_lossy(&bytes.expect("stream chunk"))),
                None => return None,
            }
        }
    }

    /// Events up to and including the first of type `kind`.
    pub async fn until(&mut self, kind: &str) -> Vec<Value> {
        let mut events = Vec::new();
        loop {
            let event = self
                .next()
                .await
                .unwrap_or_else(|| panic!("stream ended before a `{kind}` event: {events:#?}"));
            let found = event["type"] == kind;
            events.push(event);
            if found {
                return events;
            }
        }
    }

    /// Everything left until the stream ends.
    pub async fn rest(&mut self) -> Vec<Value> {
        let mut events = Vec::new();
        while let Some(event) = self.next().await {
            events.push(event);
        }
        events
    }
}

/// The `type` of each event, in order.
pub fn kinds(events: &[Value]) -> Vec<&str> {
    events
        .iter()
        .map(|e| e["type"].as_str().unwrap_or("?"))
        .collect()
}

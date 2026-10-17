//! Prometheus metrics (`GET /metrics`, from the server itself only: the
//! service listens on loopback and nginx adds `X-Forwarded-For` to anything
//! from outside). Request counts and latency by route template, plus gauges
//! read at scrape time: ingest/build queues, passages, AI spend, credits.

use std::collections::HashMap;
use std::fmt::Write as _;
use std::sync::{Arc, Mutex};
use std::time::Instant;

use axum::extract::{MatchedPath, Request, State};
use axum::http::{HeaderMap, StatusCode};
use axum::middleware::Next;
use axum::response::{IntoResponse, Response};
use sqlx::Row;

use crate::AppState;

const BUCKETS: [f64; 10] = [0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 10.0, 60.0];

#[derive(Default)]
struct Histogram {
    counts: [u64; BUCKETS.len()],
    sum: f64,
    total: u64,
}

#[derive(Clone, Default)]
pub struct Metrics {
    /// (method, route template, status) → count.
    requests: Arc<Mutex<HashMap<(String, String, u16), u64>>>,
    latency: Arc<Mutex<HashMap<String, Histogram>>>,
}

impl Metrics {
    fn observe(&self, method: &str, route: &str, status: u16, secs: f64) {
        *self.requests.lock().unwrap().entry((method.into(), route.into(), status)).or_default() += 1;
        let mut lat = self.latency.lock().unwrap();
        let h = lat.entry(route.to_string()).or_default();
        for (i, b) in BUCKETS.iter().enumerate() {
            if secs <= *b {
                h.counts[i] += 1;
            }
        }
        h.sum += secs;
        h.total += 1;
    }
}

/// Records every request by route template (never the raw path with ids).
/// SSE streams count until their headers go out, not their whole length.
pub async fn track(State(st): State<AppState>, req: Request, next: Next) -> Response {
    let route = req.extensions().get::<MatchedPath>().map(|p| p.as_str().to_string()).unwrap_or_else(|| "unmatched".into());
    let method = req.method().to_string();
    let start = Instant::now();
    let res = next.run(req).await;
    st.metrics.observe(&method, &route, res.status().as_u16(), start.elapsed().as_secs_f64());
    res
}

async fn rows(pool: &sqlx::PgPool, sql: &str) -> Vec<(String, f64)> {
    match sqlx::query(sql).fetch_all(pool).await {
        Ok(r) => r.iter().map(|r| (r.get::<String, _>(0), r.get::<f64, _>(1))).collect(),
        Err(e) => {
            tracing::warn!("metrics: {e}");
            vec![]
        }
    }
}

pub async fn render(State(st): State<AppState>, headers: HeaderMap) -> Response {
    if headers.contains_key("x-forwarded-for") {
        return StatusCode::FORBIDDEN.into_response();
    }
    let mut out = String::new();
    let _ = writeln!(out, "# TYPE study_http_requests_total counter");
    for ((m, r, s), n) in st.metrics.requests.lock().unwrap().iter() {
        let _ = writeln!(out, "study_http_requests_total{{method=\"{m}\",route=\"{r}\",status=\"{s}\"}} {n}");
    }
    let _ = writeln!(out, "# TYPE study_http_request_duration_seconds histogram");
    for (r, h) in st.metrics.latency.lock().unwrap().iter() {
        for (i, b) in BUCKETS.iter().enumerate() {
            let _ = writeln!(out, "study_http_request_duration_seconds_bucket{{route=\"{r}\",le=\"{b}\"}} {}", h.counts[i]);
        }
        let _ = writeln!(out, "study_http_request_duration_seconds_bucket{{route=\"{r}\",le=\"+Inf\"}} {}", h.total);
        let _ = writeln!(out, "study_http_request_duration_seconds_sum{{route=\"{r}\"}} {}", h.sum);
        let _ = writeln!(out, "study_http_request_duration_seconds_count{{route=\"{r}\"}} {}", h.total);
    }

    let gauges: [(&str, &str, &sqlx::PgPool, &str); 6] = [
        ("study_ingest_jobs", "status", &st.cockpit, "SELECT status, count(*)::float8 FROM ingest_jobs GROUP BY 1"),
        ("study_builds", "status", &st.cockpit, "SELECT status, count(*)::float8 FROM studio_builds GROUP BY 1"),
        (
            "study_oldest_queued_seconds",
            "queue",
            &st.cockpit,
            "SELECT 'ingest', COALESCE(EXTRACT(EPOCH FROM now() - min(created_at)), 0)::float8 FROM ingest_jobs WHERE status = 'queued' \
             UNION ALL SELECT 'build', COALESCE(EXTRACT(EPOCH FROM now() - min(created_at)), 0)::float8 FROM studio_builds WHERE status = 'queued'",
        ),
        ("study_passages", "kind", &st.vector, "SELECT 'all', count(*)::float8 FROM chunks"),
        (
            "study_ai_cost_usd_today",
            "feature",
            &st.cockpit,
            "SELECT feature, COALESCE(sum(cost_usd), 0)::float8 FROM llm_usage WHERE created_at >= date_trunc('day', now()) GROUP BY 1",
        ),
        (
            "study_notifications_unsent",
            "kind",
            &st.cockpit,
            "SELECT kind, count(*)::float8 FROM study_notifications WHERE sent_at IS NULL GROUP BY 1",
        ),
    ];
    for (name, label, pool, sql) in gauges {
        let _ = writeln!(out, "# TYPE {name} gauge");
        for (k, v) in rows(pool, sql).await {
            let _ = writeln!(out, "{name}{{{label}=\"{k}\"}} {v}");
        }
    }
    if let Some(shared) = &st.shared {
        let _ = writeln!(out, "# TYPE study_credits_charged_today gauge");
        for (k, v) in rows(
            shared,
            "SELECT split_part(source_ref, ':', 2), COALESCE(sum(amount), 0)::float8 FROM credit_ledger \
             WHERE source_ref LIKE 'study:%' AND entry_type = 'usage_deduction' AND created_at >= date_trunc('day', now()) GROUP BY 1",
        )
        .await
        {
            let _ = writeln!(out, "study_credits_charged_today{{feature=\"{k}\"}} {v}");
        }
    }
    ([("content-type", "text/plain; version=0.0.4")], out).into_response()
}

//! Prometheus metrics (`GET /metrics`, loopback or `METRICS_TOKEN` only).
//!
//! In-process counters (requests, latency, 402s, WebSockets) plus gauges read
//! from the database at scrape time (job queue, ASR lag, AI spend).

use std::collections::HashMap;
use std::fmt::Write as _;
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Instant;

use axum::extract::{ConnectInfo, MatchedPath, Request, State};
use axum::http::{HeaderMap, StatusCode};
use axum::middleware::Next;
use axum::response::{IntoResponse, Response};

use crate::AppState;

const BUCKETS: [f64; 10] = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 10.0];

#[derive(Default)]
struct Histogram {
    counts: [u64; BUCKETS.len()],
    sum: f64,
    total: u64,
}

/// (method, route template, status) → count.
type RequestCounts = HashMap<(String, String, u16), u64>;

#[derive(Clone, Default)]
pub struct Metrics {
    requests: Arc<Mutex<RequestCounts>>,
    latency: Arc<Mutex<HashMap<String, Histogram>>>,
    pub websockets: Arc<AtomicI64>,
}

impl Metrics {
    fn observe(&self, method: &str, route: &str, status: u16, secs: f64) {
        *self
            .requests
            .lock()
            .expect("metrics")
            .entry((method.to_string(), route.to_string(), status))
            .or_default() += 1;
        let mut lat = self.latency.lock().expect("metrics");
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
pub async fn track(State(st): State<AppState>, req: Request, next: Next) -> Response {
    let route = req
        .extensions()
        .get::<MatchedPath>()
        .map(|p| p.as_str().to_string())
        .unwrap_or_else(|| "unmatched".into());
    let method = req.method().to_string();
    let start = Instant::now();
    let res = next.run(req).await;
    st.metrics.observe(
        &method,
        &route,
        res.status().as_u16(),
        start.elapsed().as_secs_f64(),
    );
    res
}

pub async fn render(
    State(st): State<AppState>,
    headers: HeaderMap,
    conn: Option<ConnectInfo<std::net::SocketAddr>>,
) -> Response {
    let loopback = conn.map(|c| c.0.ip().is_loopback()).unwrap_or(false);
    let token_ok = match &st.config.metrics_token {
        Some(t) => {
            headers.get("authorization").and_then(|v| v.to_str().ok())
                == Some(&format!("Bearer {t}"))
        }
        None => false,
    };
    // Behind nginx every request looks local, so a forwarded request needs the token.
    if !(token_ok || (loopback && !headers.contains_key("x-forwarded-for"))) {
        return StatusCode::FORBIDDEN.into_response();
    }
    let mut out = String::new();
    let _ = writeln!(out, "# TYPE octonotes_http_requests_total counter");
    for ((m, r, s), n) in st.metrics.requests.lock().expect("metrics").iter() {
        let _ = writeln!(
            out,
            "octonotes_http_requests_total{{method=\"{m}\",route=\"{r}\",status=\"{s}\"}} {n}"
        );
    }
    let _ = writeln!(
        out,
        "# TYPE octonotes_http_request_duration_seconds histogram"
    );
    for (r, h) in st.metrics.latency.lock().expect("metrics").iter() {
        for (i, b) in BUCKETS.iter().enumerate() {
            let _ = writeln!(
                out,
                "octonotes_http_request_duration_seconds_bucket{{route=\"{r}\",le=\"{b}\"}} {}",
                h.counts[i]
            );
        }
        let _ = writeln!(
            out,
            "octonotes_http_request_duration_seconds_bucket{{route=\"{r}\",le=\"+Inf\"}} {}",
            h.total
        );
        let _ = writeln!(
            out,
            "octonotes_http_request_duration_seconds_sum{{route=\"{r}\"}} {}",
            h.sum
        );
        let _ = writeln!(
            out,
            "octonotes_http_request_duration_seconds_count{{route=\"{r}\"}} {}",
            h.total
        );
    }
    let _ = writeln!(
        out,
        "# TYPE octonotes_websockets gauge\noctonotes_websockets {}",
        st.metrics.websockets.load(Ordering::Relaxed)
    );

    // Database-derived gauges.
    let q = sqlx::query_as::<_, (i64, i64, i64, f64, i64, i64, i64)>(
        "SELECT \
           (SELECT count(*) FROM jobs WHERE status = 'queued' AND run_after <= now()), \
           (SELECT count(*) FROM jobs WHERE status = 'running'), \
           (SELECT count(*) FROM jobs WHERE status = 'failed' AND updated_at > now() - interval '10 minutes'), \
           COALESCE((SELECT EXTRACT(EPOCH FROM now() - min(received_at))::float8 FROM audio_chunks WHERE asr_status = 'pending'), 0), \
           (SELECT COALESCE(sum(tokens_in + tokens_out), 0)::bigint FROM ai_runs WHERE created_at > now() - interval '1 hour'), \
           (SELECT COALESCE(sum(credits_charged), 0)::bigint FROM ai_runs WHERE created_at > now() - interval '1 hour'), \
           (SELECT count(*) FROM pg_stat_activity WHERE datname = current_database())",
    )
    .fetch_one(&st.notes)
    .await;
    if let Ok((queued, running, failed, asr_lag, tokens, credits, conns)) = q {
        let _ = writeln!(
            out,
            "# TYPE octonotes_jobs_queued gauge\noctonotes_jobs_queued {queued}"
        );
        let _ = writeln!(
            out,
            "# TYPE octonotes_jobs_running gauge\noctonotes_jobs_running {running}"
        );
        let _ = writeln!(
            out,
            "# TYPE octonotes_jobs_failed_10m gauge\noctonotes_jobs_failed_10m {failed}"
        );
        let _ = writeln!(
            out,
            "# TYPE octonotes_asr_lag_seconds gauge\noctonotes_asr_lag_seconds {asr_lag}"
        );
        let _ = writeln!(
            out,
            "# TYPE octonotes_ai_tokens_1h gauge\noctonotes_ai_tokens_1h {tokens}"
        );
        let _ = writeln!(
            out,
            "# TYPE octonotes_ai_credits_1h gauge\noctonotes_ai_credits_1h {credits}"
        );
        let _ = writeln!(
            out,
            "# TYPE octonotes_db_connections gauge\noctonotes_db_connections {conns}"
        );
    }
    let _ = writeln!(
        out,
        "# TYPE octonotes_db_pool_size gauge\noctonotes_db_pool_size {}",
        st.notes.size()
    );
    ([("content-type", "text/plain; version=0.0.4")], out).into_response()
}

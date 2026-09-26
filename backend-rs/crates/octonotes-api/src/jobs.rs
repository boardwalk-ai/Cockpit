//! Durable background jobs on Postgres (`jobs` table).
//!
//! Workers claim with `FOR UPDATE SKIP LOCKED`, so several workers (threads or
//! instances) never take the same job. Failures retry with exponential backoff
//! up to `max_attempts`; a job stuck `running` for 15 minutes (crashed worker)
//! is requeued. Handlers must be idempotent — a job can run more than once.

use std::future::Future;
use std::pin::Pin;
use std::time::Duration;

use serde_json::{json, Value};
use sqlx::PgPool;
use uuid::Uuid;

use crate::AppState;

pub type JobResult = Result<(), String>;
type Handler = fn(AppState, Job) -> Pin<Box<dyn Future<Output = JobResult> + Send>>;

#[derive(Debug, Clone, sqlx::FromRow)]
pub struct Job {
    pub id: Uuid,
    pub user_id: Option<Uuid>,
    pub kind: String,
    pub payload: Value,
    pub attempts: i32,
    pub max_attempts: i32,
}

/// Queue a job. `dedupe_key` makes it at-most-once per key (scheduled jobs).
pub async fn enqueue(pool: &PgPool, user_id: Option<Uuid>, kind: &str, payload: Value, dedupe_key: Option<&str>) -> Result<Option<Uuid>, sqlx::Error> {
    sqlx::query_scalar(
        "INSERT INTO jobs (user_id, kind, payload, dedupe_key) VALUES ($1, $2, $3, $4) \
         ON CONFLICT (dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING RETURNING id",
    )
    .bind(user_id)
    .bind(kind)
    .bind(payload)
    .bind(dedupe_key)
    .fetch_optional(pool)
    .await
}

/// A job that runs `delay_secs` from now (polling follow-ups).
pub async fn enqueue_at(pool: &PgPool, user_id: Option<Uuid>, kind: &str, payload: Value, delay_secs: i64) -> Result<Uuid, sqlx::Error> {
    sqlx::query_scalar("INSERT INTO jobs (user_id, kind, payload, run_after) VALUES ($1, $2, $3, now() + make_interval(secs => $4)) RETURNING id")
        .bind(user_id)
        .bind(kind)
        .bind(payload)
        .bind(delay_secs as f64)
        .fetch_one(pool)
        .await
}

/// Same, inside an open transaction (job appears only if the tx commits).
pub async fn enqueue_tx(conn: &mut sqlx::PgConnection, user_id: Option<Uuid>, kind: &str, payload: Value, dedupe_key: Option<&str>) -> Result<Option<Uuid>, sqlx::Error> {
    sqlx::query_scalar(
        "INSERT INTO jobs (user_id, kind, payload, dedupe_key) VALUES ($1, $2, $3, $4) \
         ON CONFLICT (dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING RETURNING id",
    )
    .bind(user_id)
    .bind(kind)
    .bind(payload)
    .bind(dedupe_key)
    .fetch_optional(conn)
    .await
}

fn handler(kind: &str) -> Option<Handler> {
    Some(match kind {
        "system.purge" => |st, job| Box::pin(purge(st, job)),
        "asr.chunk" => |st, job| Box::pin(crate::asr::job_chunk(st, job)),
        "transcript.faithful" => |st, job| Box::pin(crate::asr::job_faithful(st, job)),
        "recording.assemble" => |st, job| Box::pin(crate::routes::recordings::job_assemble(st, job)),
        "system.outbox" => |st, job| Box::pin(crate::outbox::job_publish(st, job)),
        "material.process" => |st, job| Box::pin(crate::routes::materials::job_process(st, job)),
        "embed.session" => |st, job| Box::pin(crate::retrieval::job_embed_session(st, job)),
        "system.meter" => |st, job| Box::pin(crate::pricing::job_meter(st, job)),
        "review.prepare" => |st, job| Box::pin(crate::routes::review::job_prepare(st, job)),
        "recommendations.build" => |st, job| Box::pin(crate::routes::recommendations::job_build(st, job)),
        "conversion.follow" => |st, job| Box::pin(crate::routes::conversions::job_follow(st, job)),
        "export.render" => |st, job| Box::pin(crate::routes::final_notes::job_export(st, job)),
        // PHASE-HANDLERS
        _ => return None,
    })
}

async fn claim(pool: &PgPool, worker: &str) -> Result<Option<Job>, sqlx::Error> {
    sqlx::query_as::<_, Job>(
        "UPDATE jobs SET status = 'running', locked_by = $1, locked_at = now(), attempts = attempts + 1 \
         WHERE id = (SELECT id FROM jobs WHERE status = 'queued' AND run_after <= now() \
                     ORDER BY run_after FOR UPDATE SKIP LOCKED LIMIT 1) \
         RETURNING id, user_id, kind, payload, attempts, max_attempts",
    )
    .bind(worker)
    .fetch_optional(pool)
    .await
}

async fn finish(pool: &PgPool, job: &Job, result: JobResult) {
    let res = match result {
        Ok(()) => sqlx::query("UPDATE jobs SET status = 'done', error = NULL WHERE id = $1").bind(job.id).execute(pool).await,
        Err(e) if job.attempts < job.max_attempts => {
            let backoff = 5i64 * 2i64.pow(job.attempts.clamp(0, 10) as u32);
            tracing::warn!(job = %job.id, kind = %job.kind, attempt = job.attempts, error = %e, "job failed; retrying");
            sqlx::query("UPDATE jobs SET status = 'queued', error = $2, run_after = now() + make_interval(secs => $3) WHERE id = $1")
                .bind(job.id)
                .bind(&e)
                .bind(backoff as f64)
                .execute(pool)
                .await
        }
        Err(e) => {
            tracing::error!(job = %job.id, kind = %job.kind, error = %e, "job failed permanently");
            sqlx::query("UPDATE jobs SET status = 'failed', error = $2 WHERE id = $1").bind(job.id).bind(&e).execute(pool).await
        }
    };
    if let Err(e) = res {
        tracing::error!(error = %e, "could not record job result");
    }
}

/// Starts `n` worker loops plus the scheduler.
pub fn spawn(st: AppState, n: usize) {
    for i in 0..n {
        let st = st.clone();
        let name = format!("{}-{i}", std::process::id());
        tokio::spawn(async move {
            loop {
                match claim(&st.notes, &name).await {
                    Ok(Some(job)) => {
                        let result = match handler(&job.kind) {
                            Some(h) => {
                                // A panicking handler fails the job instead of killing the worker.
                                match tokio::spawn(h(st.clone(), job.clone())).await {
                                    Ok(r) => r,
                                    Err(e) => Err(format!("handler panicked: {e}")),
                                }
                            }
                            None => Err(format!("no handler for job kind '{}'", job.kind)),
                        };
                        finish(&st.notes, &job, result).await;
                    }
                    Ok(None) => tokio::time::sleep(Duration::from_millis(500)).await,
                    Err(e) => {
                        tracing::warn!(error = %e, "job claim failed");
                        tokio::time::sleep(Duration::from_secs(2)).await;
                    }
                }
            }
        });
    }
    tokio::spawn(scheduler(st));
}

/// Periodic work: requeue stuck jobs, daily purge, outbox publishing.
async fn scheduler(st: AppState) {
    let mut tick = tokio::time::interval(Duration::from_secs(30));
    loop {
        tick.tick().await;
        let _ = sqlx::query(
            "UPDATE jobs SET status = 'queued', locked_by = NULL WHERE status = 'running' AND locked_at < now() - interval '15 minutes'",
        )
        .execute(&st.notes)
        .await;
        let day = chrono::Utc::now().format("%Y-%m-%d").to_string();
        let _ = enqueue(&st.notes, None, "system.purge", json!({}), Some(&format!("purge:{day}"))).await;
        let minute = chrono::Utc::now().format("%Y-%m-%dT%H:%M").to_string();
        let _ = enqueue(&st.notes, None, "system.outbox", json!({}), Some(&format!("outbox:{minute}"))).await;
        let _ = enqueue(&st.notes, None, "system.meter", json!({}), Some(&format!("meter:{minute}"))).await;
    }
}

/// Hard-deletes sessions 30 days after soft delete (rows cascade) and their
/// stored files; old applied-op / idempotency records.
async fn purge(st: AppState, _job: Job) -> JobResult {
    let doomed: Vec<(Uuid, Uuid)> = sqlx::query_as(
        "SELECT id, user_id FROM sessions WHERE deleted_at < now() - interval '30 days' LIMIT 500",
    )
    .fetch_all(&st.notes)
    .await
    .map_err(|e| e.to_string())?;
    for (id, user_id) in doomed {
        st.storage
            .delete_prefix(&format!("{user_id}/{id}/"))
            .await
            .map_err(|e| format!("storage purge failed: {e}"))?;
        sqlx::query("DELETE FROM sessions WHERE id = $1").bind(id).execute(&st.notes).await.map_err(|e| e.to_string())?;
    }
    sqlx::query("DELETE FROM applied_ops WHERE created_at < now() - interval '90 days'")
        .execute(&st.notes)
        .await
        .map_err(|e| e.to_string())?;
    sqlx::query("DELETE FROM idempotency_keys WHERE created_at < now() - interval '30 days'")
        .execute(&st.notes)
        .await
        .map_err(|e| e.to_string())?;
    sqlx::query("DELETE FROM jobs WHERE status IN ('done', 'cancelled') AND updated_at < now() - interval '14 days'")
        .execute(&st.notes)
        .await
        .map_err(|e| e.to_string())?;
    Ok(())
}

/// Runs all due jobs synchronously (tests).
pub async fn drain(st: &AppState) {
    for _ in 0..500 {
        let Ok(Some(job)) = claim(&st.notes, "test").await else { return };
        let result = match handler(&job.kind) {
            Some(h) => h(st.clone(), job.clone()).await,
            None => Err(format!("no handler for '{}'", job.kind)),
        };
        finish(&st.notes, &job, result).await;
    }
}

//! The run queue. A started run is `queued`; a worker claims it, drives it,
//! and holds a lease on it while it does. A worker that dies stops renewing
//! its leases, and the runs it held are claimed again and resumed from what
//! was saved. A run that waits too long on the user is parked: no worker
//! holds it until the answer comes, which queues it again.
//!
//! The worker runs inside the API process. Its claims go through the
//! database (`FOR UPDATE SKIP LOCKED`), so more than one can share a queue.

use std::sync::Arc;
use std::time::Instant;

use serde_json::Value;
use tokio::sync::{Notify, Semaphore};
use tokio::task::JoinHandle;
use uuid::Uuid;

use super::driver;
use crate::AppState;

/// What a worker needs to drive a claimed run.
pub struct Job {
    pub run_id: Uuid,
    pub project_id: Uuid,
    pub user_id: Uuid,
    pub instruction: String,
    /// The answer that woke a parked run, `{ field, value }`.
    pub resume: Option<Value>,
    /// The run has been driven before: pick it up, do not start it over.
    pub resuming: bool,
}

/// This process's identity in the queue, and the bell that wakes its worker.
#[derive(Clone)]
pub struct WorkerHandle {
    pub id: Arc<str>,
    wake: Arc<Notify>,
}

impl Default for WorkerHandle {
    fn default() -> Self {
        Self {
            id: Uuid::new_v4().to_string().into(),
            wake: Arc::new(Notify::new()),
        }
    }
}

impl WorkerHandle {
    /// Something was queued: look now rather than at the next poll.
    pub fn wake(&self) {
        self.wake.notify_one();
    }
}

/// The running worker. Dropping it stops it (runs it is driving go on).
pub struct Worker(JoinHandle<()>);

impl Drop for Worker {
    fn drop(&mut self) {
        self.0.abort();
    }
}

/// Starts this process's worker.
pub fn start(st: AppState) -> Worker {
    let slots = Arc::new(Semaphore::new(st.config.worker_slots.max(1)));
    Worker(tokio::spawn(async move {
        let heartbeat = st.config.run_lease / 3;
        let mut last_beat: Option<Instant> = None;
        loop {
            if last_beat.is_none_or(|at| at.elapsed() >= heartbeat) {
                last_beat = Some(Instant::now());
                if let Err(error) = renew(&st).await {
                    tracing::warn!(%error, "worker: could not renew leases");
                }
            }
            if let Err(error) = reclaim(&st).await {
                tracing::warn!(%error, "worker: could not reclaim runs");
            }
            while let Ok(permit) = slots.clone().try_acquire_owned() {
                match claim(&st).await {
                    Ok(Some(job)) => driver::spawn(st.clone(), job, permit),
                    Ok(None) => break,
                    Err(error) => {
                        tracing::warn!(%error, "worker: could not claim a run");
                        break;
                    }
                }
            }
            tokio::select! {
                _ = st.worker.wake.notified() => {}
                _ = tokio::time::sleep(st.config.worker_poll) => {}
            }
        }
    }))
}

fn lease_secs(st: &AppState) -> f64 {
    st.config.run_lease.as_secs_f64()
}

#[derive(sqlx::FromRow)]
struct Claimed {
    id: Uuid,
    project_id: Uuid,
    user_id: Uuid,
    instruction: Option<String>,
    resume: Option<Value>,
    last_seq: i64,
}

/// Takes the oldest queued run, if there is one.
async fn claim(st: &AppState) -> Result<Option<Job>, sqlx::Error> {
    let row: Option<Claimed> = sqlx::query_as(
        "UPDATE runs r SET status = 'running', worker = $1, \
             lease_until = now() + make_interval(secs => $2), resume = NULL, updated_at = now() \
         FROM (SELECT id, resume FROM runs WHERE status = 'queued' \
               ORDER BY updated_at FOR UPDATE SKIP LOCKED LIMIT 1) next \
         WHERE r.id = next.id \
         RETURNING r.id, r.project_id, r.user_id, r.context->>'instruction' AS instruction, \n                   next.resume, r.last_seq",
    )
    .bind(st.worker.id.as_ref())
    .bind(lease_secs(st))
    .fetch_optional(&st.db)
    .await?;
    Ok(row.map(|row| Job {
        run_id: row.id,
        project_id: row.project_id,
        user_id: row.user_id,
        instruction: row.instruction.unwrap_or_default(),
        resume: row.resume,
        resuming: row.last_seq > 0,
    }))
}

/// Keeps the leases of the runs this process is driving.
async fn renew(st: &AppState) -> Result<(), sqlx::Error> {
    let live = st.hub.live_ids();
    if live.is_empty() {
        return Ok(());
    }
    sqlx::query(
        "UPDATE runs SET lease_until = now() + make_interval(secs => $3) \
         WHERE id = ANY($1) AND worker = $2 AND lease_until IS NOT NULL",
    )
    .bind(&live)
    .bind(st.worker.id.as_ref())
    .bind(lease_secs(st))
    .execute(&st.db)
    .await?;
    Ok(())
}

/// Runs whose worker stopped renewing: a working one goes back in the queue,
/// a waiting one is parked until it is answered.
async fn reclaim(st: &AppState) -> Result<(), sqlx::Error> {
    let reclaimed: Vec<(Uuid, String)> = sqlx::query_as(
        "UPDATE runs SET worker = NULL, lease_until = NULL, updated_at = now(), \
             status = CASE WHEN status = 'running' THEN 'queued' ELSE status END \
         WHERE lease_until < now() AND status IN ('running', 'waiting_for_user') \
         RETURNING id, status",
    )
    .fetch_all(&st.db)
    .await?;
    for (run_id, status) in reclaimed {
        tracing::warn!(%run_id, %status, "worker: took back a run whose worker stopped");
    }
    Ok(())
}

/// Lets go of a run that is waiting on the user. False if it is not waiting
/// any more (the answer came just now).
pub(crate) async fn park(st: &AppState, run_id: Uuid) -> Result<bool, sqlx::Error> {
    Ok(sqlx::query(
        "UPDATE runs SET worker = NULL, lease_until = NULL, updated_at = now() \
         WHERE id = $1 AND status = 'waiting_for_user' AND worker = $2",
    )
    .bind(run_id)
    .bind(st.worker.id.as_ref())
    .execute(&st.db)
    .await?
    .rows_affected()
        > 0)
}

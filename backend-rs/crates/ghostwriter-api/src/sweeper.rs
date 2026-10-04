//! Deleted accounts. When a `users` row is deleted, the shared database
//! records it in `deleted_users`; GhostWriter's data lives in its own
//! database, out of reach of a cascade, so this sweeps it: every project
//! (document, versions, runs, events), folder and device of that user.
//!
//! Every process sweeps; the deletes are idempotent, so two sweeping the
//! same account at once is harmless.

use std::time::Duration;

use chrono::{DateTime, Utc};
use tokio::task::JoinHandle;
use uuid::Uuid;

use crate::runs::ACTIVE;
use crate::AppState;

/// Tombstones read per pass.
const BATCH: i64 = 500;

/// How far back each pass looks again, for tombstones committed late.
const OVERLAP: Duration = Duration::from_secs(3600);

/// The running sweeper. Dropping it stops it.
pub struct Sweeper(JoinHandle<()>);

impl Drop for Sweeper {
    fn drop(&mut self) {
        self.0.abort();
    }
}

/// Sweeps now and then every `config.sweep_every`. Without the shared
/// database there is nothing to read, and it does nothing.
pub fn start(st: AppState) -> Sweeper {
    Sweeper(tokio::spawn(async move {
        if st.octopilot.is_none() {
            return;
        }
        loop {
            match sweep(&st).await {
                Ok(0) => {}
                Ok(swept) => tracing::info!(swept, "sweeper: removed deleted accounts' data"),
                Err(error) => tracing::warn!(%error, "sweeper: could not sweep"),
            }
            tokio::time::sleep(st.config.sweep_every).await;
        }
    }))
}

#[derive(sqlx::FromRow)]
struct Tombstone {
    user_id: Uuid,
    firebase_uid: Option<String>,
    deleted_at: DateTime<Utc>,
}

/// One pass: removes the data of deleted accounts not swept yet. Returns
/// how many accounts it swept.
pub async fn sweep(st: &AppState) -> Result<usize, sqlx::Error> {
    let Some(shared) = &st.octopilot else {
        return Ok(0);
    };
    let since: Option<DateTime<Utc>> =
        sqlx::query_scalar("SELECT max(deleted_at) FROM swept_users")
            .fetch_one(&st.db)
            .await?;
    // Where the pass has got to: (deleted_at, user_id), in that order.
    let mut after = (
        since.map_or(DateTime::UNIX_EPOCH, |at| at - OVERLAP),
        Uuid::nil(),
    );
    let mut swept = 0;
    loop {
        let tombstones: Vec<Tombstone> = sqlx::query_as(
            "SELECT user_id, firebase_uid, deleted_at FROM deleted_users \
             WHERE (deleted_at, user_id) > ($1, $2) \
             ORDER BY deleted_at, user_id LIMIT $3",
        )
        .bind(after.0)
        .bind(after.1)
        .bind(BATCH)
        .fetch_all(shared)
        .await?;
        let Some(last) = tombstones.last() else {
            return Ok(swept);
        };
        after = (last.deleted_at, last.user_id);

        let ids: Vec<Uuid> = tombstones.iter().map(|t| t.user_id).collect();
        let done: Vec<Uuid> =
            sqlx::query_scalar("SELECT user_id FROM swept_users WHERE user_id = ANY($1)")
                .bind(&ids)
                .fetch_all(&st.db)
                .await?;
        for tombstone in &tombstones {
            // A sign-in cached before the account went must not reach it now.
            if let Some(uid) = &tombstone.firebase_uid {
                st.user_ids.forget(uid).await;
            }
            if done.contains(&tombstone.user_id) {
                continue;
            }
            sweep_user(st, tombstone.user_id, tombstone.deleted_at).await?;
            swept += 1;
        }
        if tombstones.len() < BATCH as usize {
            return Ok(swept);
        }
    }
}

/// Removes everything GhostWriter holds for `user_id`.
async fn sweep_user(
    st: &AppState,
    user_id: Uuid,
    deleted_at: DateTime<Utc>,
) -> Result<(), sqlx::Error> {
    // Stop the runs this process drives; one on another worker stops when
    // its run row disappears under it.
    let live: Vec<Uuid> = sqlx::query_scalar(&format!(
        "SELECT id FROM runs WHERE user_id = $1 AND status IN {ACTIVE}"
    ))
    .bind(user_id)
    .fetch_all(&st.db)
    .await?;
    for run_id in live {
        st.hub.abort(run_id);
    }

    let mut tx = st.db.begin().await?;
    // Documents, versions, runs and their events go with the project.
    let projects: Vec<Uuid> =
        sqlx::query_scalar("DELETE FROM projects WHERE user_id = $1 RETURNING id")
            .bind(user_id)
            .fetch_all(&mut *tx)
            .await?;
    sqlx::query("DELETE FROM runs WHERE user_id = $1")
        .bind(user_id)
        .execute(&mut *tx)
        .await?;
    sqlx::query("DELETE FROM safety_events WHERE user_id = $1")
        .bind(user_id)
        .execute(&mut *tx)
        .await?;
    sqlx::query("DELETE FROM folders WHERE user_id = $1")
        .bind(user_id)
        .execute(&mut *tx)
        .await?;
    sqlx::query("DELETE FROM devices WHERE user_id = $1")
        .bind(user_id)
        .execute(&mut *tx)
        .await?;
    sqlx::query(
        "INSERT INTO swept_users (user_id, deleted_at) VALUES ($1, $2) \
         ON CONFLICT (user_id) DO NOTHING",
    )
    .bind(user_id)
    .bind(deleted_at)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;

    // Ends any open document stream on them.
    for project_id in projects {
        st.docs.changed(project_id);
    }
    tracing::info!(%user_id, "sweeper: deleted account's data removed");
    Ok(())
}

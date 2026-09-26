//! Domain-event outbox for The Deck (calendar, notifications): events are
//! written in the same transaction as the change (`record`), then published to
//! Redis channel `deck:events` by a job, so an event is never lost and never
//! announces a change that rolled back.

use serde_json::{json, Value};
use sqlx::PgConnection;
use uuid::Uuid;

use crate::jobs::{Job, JobResult};
use crate::realtime::Event;
use crate::AppState;

pub async fn record(
    conn: &mut PgConnection,
    user_id: Uuid,
    kind: &str,
    subject_id: Option<Uuid>,
    payload: Value,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO domain_events (user_id, kind, subject_id, payload) VALUES ($1, $2, $3, $4)",
    )
    .bind(user_id)
    .bind(kind)
    .bind(subject_id)
    .bind(payload)
    .execute(conn)
    .await?;
    Ok(())
}

type EventRow = (
    i64,
    Uuid,
    String,
    Option<Uuid>,
    Value,
    chrono::DateTime<chrono::Utc>,
);

/// Publishes unpublished events in order.
pub async fn job_publish(st: AppState, _job: Job) -> JobResult {
    let mut tx = st.notes.begin().await.map_err(|e| e.to_string())?;
    let rows: Vec<EventRow> = sqlx::query_as(
        "SELECT id, user_id, kind, subject_id, payload, occurred_at FROM domain_events \
         WHERE published_at IS NULL ORDER BY id LIMIT 500 FOR UPDATE SKIP LOCKED",
    )
    .fetch_all(&mut *tx)
    .await
    .map_err(|e| e.to_string())?;
    for (id, user_id, kind, subject, payload, at) in &rows {
        let data = json!({ "id": id, "app": "octonotes", "userId": user_id, "kind": kind, "subjectId": subject, "payload": payload, "occurredAt": at });
        st.hub
            .publish("deck:events", Event::new("domain.event", data, None))
            .await;
    }
    if let Some(last) = rows.last() {
        sqlx::query("UPDATE domain_events SET published_at = now() WHERE published_at IS NULL AND id <= $1 AND id = ANY($2)")
            .bind(last.0)
            .bind(rows.iter().map(|r| r.0).collect::<Vec<_>>())
            .execute(&mut *tx)
            .await
            .map_err(|e| e.to_string())?;
    }
    tx.commit().await.map_err(|e| e.to_string())
}

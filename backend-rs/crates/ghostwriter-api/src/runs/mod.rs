//! Agent runs: the durable event log and the live fan-out on top of it.
//!
//! Every event a client must not miss is appended to `run_events` with the
//! next `seq` for its run, then broadcast to whoever is connected. A client
//! that reconnects asks for everything after the last `seq` it saw, so a
//! dropped connection loses nothing. Text deltas are broadcast only: on
//! replay the finished message stands in for them.
//!
//! A worker ([`worker`]) claims a run from the queue and drives it. A run cut
//! off by a restart is claimed again once its lease runs out, and resumed.

pub mod driver;
pub mod worker;

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use serde_json::{json, Map, Value};
use sqlx::PgPool;
use tokio::sync::{broadcast, mpsc, OwnedMutexGuard};
use tokio::task::AbortHandle;
use uuid::Uuid;

use crate::push::{notify_run, RunNews};
use crate::AppState;

/// Run states in which a driver is (or should be) working.
pub const ACTIVE: &str = "('queued', 'running', 'waiting_for_user')";

/// Event types after which a run emits nothing more.
pub fn is_terminal(kind: &str) -> bool {
    matches!(kind, "done" | "fatal" | "cancelled")
}

/// One event as sent to clients. `seq` is `None` for a live-only event.
#[derive(Clone, Debug)]
pub struct LiveEvent {
    pub seq: Option<i64>,
    pub kind: String,
    pub payload: Value,
}

impl LiveEvent {
    /// The JSON a client receives: the payload's fields plus `type` and `seq`.
    pub fn to_json(&self) -> Value {
        let mut object = match &self.payload {
            Value::Object(map) => map.clone(),
            Value::Null => Map::new(),
            other => Map::from_iter([("value".to_string(), other.clone())]),
        };
        object.insert("type".into(), json!(self.kind));
        if let Some(seq) = self.seq {
            object.insert("seq".into(), json!(seq));
        }
        Value::Object(object)
    }
}

/// What the HTTP handlers hold for a run whose driver is in this process.
struct Live {
    events: broadcast::Sender<LiveEvent>,
    answers: mpsc::UnboundedSender<(String, Value)>,
    messages: mpsc::UnboundedSender<String>,
    abort: Option<AbortHandle>,
}

/// The driver's ends of a run's channels.
pub struct Inbox {
    pub answers: mpsc::UnboundedReceiver<(String, Value)>,
    pub messages: mpsc::UnboundedReceiver<String>,
}

/// In-memory side of the runs this process is driving.
#[derive(Clone, Default)]
pub struct Hub {
    live: Arc<Mutex<HashMap<Uuid, Live>>>,
    /// Serializes "append event + broadcast" per run, so broadcasts leave in
    /// `seq` order and a subscriber can drop anything at or below its cursor.
    locks: Arc<Mutex<HashMap<Uuid, Arc<tokio::sync::Mutex<()>>>>>,
    /// Rung whenever a run goes live here, so streams following a run no
    /// worker held pick it up at once.
    opened: Arc<tokio::sync::Notify>,
    /// Clients following each run's events, whether or not it is live here.
    followers: Arc<Mutex<HashMap<Uuid, usize>>>,
}

/// A client following a run; counted until dropped.
pub struct Following {
    followers: Arc<Mutex<HashMap<Uuid, usize>>>,
    run_id: Uuid,
}

impl Drop for Following {
    fn drop(&mut self) {
        let mut followers = self.followers.lock().unwrap();
        if let Some(count) = followers.get_mut(&self.run_id) {
            *count -= 1;
            if *count == 0 {
                followers.remove(&self.run_id);
            }
        }
    }
}

impl Hub {
    /// Registers a run that is about to start and returns its inbox.
    /// Waits until some run goes live here.
    pub fn opened(&self) -> tokio::sync::futures::Notified<'_> {
        self.opened.notified()
    }

    pub fn open(&self, run_id: Uuid) -> Inbox {
        let (events, _) = broadcast::channel(256);
        let (answers, answers_rx) = mpsc::unbounded_channel();
        let (messages, messages_rx) = mpsc::unbounded_channel();
        self.live.lock().unwrap().insert(
            run_id,
            Live {
                events,
                answers,
                messages,
                abort: None,
            },
        );
        self.opened.notify_waiters();
        Inbox {
            answers: answers_rx,
            messages: messages_rx,
        }
    }

    pub fn set_abort(&self, run_id: Uuid, abort: AbortHandle) {
        if let Some(live) = self.live.lock().unwrap().get_mut(&run_id) {
            live.abort = Some(abort);
        }
    }

    /// Stops the run's driver task, if it is in this process.
    pub fn abort(&self, run_id: Uuid) {
        if let Some(abort) = self
            .live
            .lock()
            .unwrap()
            .get(&run_id)
            .and_then(|live| live.abort.clone())
        {
            abort.abort();
        }
    }

    /// The runs this process is driving.
    pub fn live_ids(&self) -> Vec<Uuid> {
        self.live.lock().unwrap().keys().copied().collect()
    }

    pub fn is_live(&self, run_id: Uuid) -> bool {
        self.live.lock().unwrap().contains_key(&run_id)
    }

    /// A receiver for the run's events from now on; `None` if it is not live.
    pub fn subscribe(&self, run_id: Uuid) -> Option<broadcast::Receiver<LiveEvent>> {
        self.live
            .lock()
            .unwrap()
            .get(&run_id)
            .map(|live| live.events.subscribe())
    }

    /// Counts a client following the run until the guard is dropped.
    pub fn follow(&self, run_id: Uuid) -> Following {
        *self.followers.lock().unwrap().entry(run_id).or_default() += 1;
        Following {
            followers: self.followers.clone(),
            run_id,
        }
    }

    /// How many clients are following the run's events right now.
    pub fn watchers(&self, run_id: Uuid) -> usize {
        self.followers
            .lock()
            .unwrap()
            .get(&run_id)
            .copied()
            .unwrap_or(0)
    }

    fn broadcast(&self, run_id: Uuid, event: LiveEvent) {
        if let Some(live) = self.live.lock().unwrap().get(&run_id) {
            // No subscribers is fine: the event is in the log.
            let _ = live.events.send(event);
        }
    }

    /// Hands an answer to the driver. False if the run is not live.
    pub fn deliver_answer(&self, run_id: Uuid, field: String, value: Value) -> bool {
        self.live
            .lock()
            .unwrap()
            .get(&run_id)
            .is_some_and(|live| live.answers.send((field, value)).is_ok())
    }

    /// Hands a chat message to the driver. False if the run is not live.
    pub fn deliver_message(&self, run_id: Uuid, text: String) -> bool {
        self.live
            .lock()
            .unwrap()
            .get(&run_id)
            .is_some_and(|live| live.messages.send(text).is_ok())
    }

    /// Takes the run's event lock. Hold it across a state change and the
    /// event that announces it.
    pub async fn lock(&self, run_id: Uuid) -> OwnedMutexGuard<()> {
        let mutex = self
            .locks
            .lock()
            .unwrap()
            .entry(run_id)
            .or_default()
            .clone();
        mutex.lock_owned().await
    }

    pub(crate) fn close(&self, run_id: Uuid) {
        // Dropping the sender ends every subscriber's stream.
        self.live.lock().unwrap().remove(&run_id);
        self.locks.lock().unwrap().remove(&run_id);
    }
}

/// Appends an event to the run's log and broadcasts it. Returns its `seq`.
pub async fn emit(
    st: &AppState,
    run_id: Uuid,
    kind: &str,
    payload: Value,
) -> Result<i64, sqlx::Error> {
    let _guard = st.hub.lock(run_id).await;
    append(st, run_id, kind, payload).await
}

/// [`emit`] for a caller that already holds the run's event lock.
pub async fn append(
    st: &AppState,
    run_id: Uuid,
    kind: &str,
    payload: Value,
) -> Result<i64, sqlx::Error> {
    let seq = append_to_log(&st.db, run_id, kind, &payload).await?;
    st.hub.broadcast(
        run_id,
        LiveEvent {
            seq: Some(seq),
            kind: kind.to_string(),
            payload,
        },
    );
    Ok(seq)
}

async fn append_to_log(
    db: &PgPool,
    run_id: Uuid,
    kind: &str,
    payload: &Value,
) -> Result<i64, sqlx::Error> {
    let mut tx = db.begin().await?;
    // The row lock on `runs` hands out `seq` values one at a time.
    // Nothing is added after a run has ended, but the event that ends it;
    // `RowNotFound` tells a driver that is still going that it was stopped.
    let seq: i64 = sqlx::query_scalar(&format!(
        "UPDATE runs SET last_seq = last_seq + 1, updated_at = now() \
         WHERE id = $1 AND (status IN {ACTIVE} OR $2) RETURNING last_seq"
    ))
    .bind(run_id)
    .bind(is_terminal(kind))
    .fetch_one(&mut *tx)
    .await?;
    sqlx::query("INSERT INTO run_events (run_id, seq, type, payload) VALUES ($1, $2, $3, $4)")
        .bind(run_id)
        .bind(seq)
        .bind(kind)
        .bind(payload)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;
    Ok(seq)
}

/// Broadcasts an event without storing it (text deltas).
pub fn emit_live(st: &AppState, run_id: Uuid, kind: &str, payload: Value) {
    st.hub.broadcast(
        run_id,
        LiveEvent {
            seq: None,
            kind: kind.to_string(),
            payload,
        },
    );
}

/// Stored events with `seq` greater than `after`, oldest first.
pub async fn events_after(
    db: &PgPool,
    run_id: Uuid,
    after: i64,
) -> Result<Vec<LiveEvent>, sqlx::Error> {
    let rows: Vec<(i64, String, Value)> = sqlx::query_as(
        "SELECT seq, type, payload FROM run_events \
         WHERE run_id = $1 AND seq > $2 ORDER BY seq",
    )
    .bind(run_id)
    .bind(after)
    .fetch_all(db)
    .await?;
    Ok(rows
        .into_iter()
        .map(|(seq, kind, payload)| LiveEvent {
            seq: Some(seq),
            kind,
            payload,
        })
        .collect())
}

/// How a run ended.
pub enum Outcome {
    Finished,
    Failed(String),
    Cancelled,
}

/// Closes a run: final status, document unlocked, terminal event, channels
/// dropped. Does nothing if the run is already closed, so the driver ending
/// and a cancel arriving at the same moment cannot both close it.
pub async fn finish(st: &AppState, run_id: Uuid, outcome: Outcome) -> Result<(), sqlx::Error> {
    let (status, kind, error) = match &outcome {
        Outcome::Finished => ("finished", "done", None),
        Outcome::Failed(message) => ("error", "fatal", Some(message.as_str())),
        Outcome::Cancelled => ("cancelled", "cancelled", None),
    };

    let guard = st.hub.lock(run_id).await;
    let closed = close_in_db(&st.db, run_id, status, error).await?;
    if let Some((project_id, unlocked)) = closed {
        if unlocked {
            st.docs.changed(project_id);
        }
        let payload = match error {
            Some(message) => json!({ "error": message }),
            None => json!({}),
        };
        append(st, run_id, kind, payload).await?;

        // Nobody was following: tell the user's phones how it ended.
        if st.hub.watchers(run_id) == 0 {
            match &outcome {
                Outcome::Finished => notify_run(st, project_id, run_id, RunNews::Finished),
                Outcome::Failed(message) => {
                    notify_run(st, project_id, run_id, RunNews::Failed(message))
                }
                Outcome::Cancelled => {}
            }
        }
    }
    drop(guard);
    st.hub.close(run_id);
    Ok(())
}

/// Marks the run closed and releases what it held. Returns the run's project
/// and whether its document was locked, or `None` if the run was not active.
async fn close_in_db(
    db: &PgPool,
    run_id: Uuid,
    status: &str,
    error: Option<&str>,
) -> Result<Option<(Uuid, bool)>, sqlx::Error> {
    let mut tx = db.begin().await?;
    let project_id: Option<Uuid> = sqlx::query_scalar(&format!(
        "UPDATE runs SET status = $2, error = $3, pending_question = NULL, updated_at = now() \
         WHERE id = $1 AND status IN {ACTIVE} RETURNING project_id"
    ))
    .bind(run_id)
    .bind(status)
    .bind(error)
    .fetch_optional(&mut *tx)
    .await?;
    let Some(project_id) = project_id else {
        return Ok(None);
    };

    let unlocked =
        sqlx::query("UPDATE documents SET locked_by_run = NULL WHERE locked_by_run = $1")
            .bind(run_id)
            .execute(&mut *tx)
            .await?
            .rows_affected()
            > 0;
    // A project with words in it is worth opening even if the run failed.
    sqlx::query(
        "UPDATE projects SET updated_at = now(), status = \
             CASE WHEN $2 OR word_count > 0 THEN 'ready' ELSE 'idle' END \
         WHERE id = $1",
    )
    .bind(project_id)
    .bind(status == "finished")
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(Some((project_id, unlocked)))
}

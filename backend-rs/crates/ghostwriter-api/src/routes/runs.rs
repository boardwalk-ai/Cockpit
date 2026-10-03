//! Runs over HTTP: start one, follow its events, answer it, talk to it, stop it.

use std::convert::Infallible;
use std::time::Duration;

use axum::extract::{Path, Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::sse::{Event, KeepAlive, Sse};
use axum::Json;
use futures::Stream;
use octo_common::ApiError;
use serde::Deserialize;
use serde_json::{json, Value};
use tokio::sync::broadcast::error::RecvError;
use uuid::Uuid;

use super::clean_text;
use crate::ctx::Caller;
use crate::runs::{self, is_terminal, LiveEvent, Outcome, ACTIVE};
use crate::AppState;

fn conflict(message: &str, code: &'static str) -> ApiError {
    ApiError::new(StatusCode::CONFLICT, message).with_code(code)
}

#[derive(sqlx::FromRow)]
struct Run {
    project_id: Uuid,
    status: String,
    pending_question: Option<Value>,
    last_seq: i64,
    error: Option<String>,
}

/// The run, if it exists and belongs to the caller.
async fn owned_run(st: &AppState, caller: &Caller, run_id: Uuid) -> Result<Run, ApiError> {
    let run: Option<Run> = sqlx::query_as(
        "SELECT project_id, status, pending_question, last_seq, error          FROM runs WHERE id = $1 AND user_id = $2",
    )
    .bind(run_id)
    .bind(caller.user_id)
    .fetch_optional(&st.db)
    .await?;
    run.ok_or_else(|| ApiError::not_found("run not found"))
}

fn is_active(status: &str) -> bool {
    matches!(status, "queued" | "running" | "waiting_for_user")
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StartRun {
    /// Chosen by the client, so a retried start cannot begin a second run.
    pub run_id: Uuid,
    /// The brief. Falls back to the one saved on the project.
    pub instruction: Option<String>,
}

/// `POST /v1/projects/:id/runs` — start a run on the project.
pub async fn start(
    State(st): State<AppState>,
    caller: Caller,
    Path(project_id): Path<Uuid>,
    Json(body): Json<StartRun>,
) -> Result<(StatusCode, Json<Value>), ApiError> {
    let saved: Option<String> =
        sqlx::query_scalar("SELECT instruction FROM projects WHERE id = $1 AND user_id = $2")
            .bind(project_id)
            .bind(caller.user_id)
            .fetch_optional(&st.db)
            .await?;
    let saved = saved.ok_or_else(|| ApiError::not_found("project not found"))?;

    // A retry of a start that already went through.
    let existing: Option<(Uuid, Uuid)> =
        sqlx::query_as("SELECT project_id, user_id FROM runs WHERE id = $1")
            .bind(body.run_id)
            .fetch_optional(&st.db)
            .await?;
    if let Some((run_project, run_user)) = existing {
        if run_project == project_id && run_user == caller.user_id {
            return Ok((StatusCode::OK, Json(json!({ "runId": body.run_id }))));
        }
        return Err(conflict("that run id is already in use", "run_id_taken"));
    }

    let instruction = clean_text(body.instruction, 20_000, "instruction")?
        .or_else(|| Some(saved).filter(|s| !s.is_empty()))
        .ok_or_else(|| ApiError::bad_request("instruction is required"))?;

    let mut tx = st.db.begin().await?;
    let inserted = sqlx::query(
        "INSERT INTO runs (id, project_id, user_id, status, context) \
         VALUES ($1, $2, $3, 'queued', $4)",
    )
    .bind(body.run_id)
    .bind(project_id)
    .bind(caller.user_id)
    .bind(json!({ "instruction": instruction }))
    .execute(&mut *tx)
    .await;
    match inserted {
        Ok(_) => {}
        // The partial unique index: one active run per project.
        Err(sqlx::Error::Database(e)) if e.is_unique_violation() => {
            return Err(conflict(
                "this project already has a run in progress",
                "run_active",
            ));
        }
        Err(e) => return Err(e.into()),
    }
    // An untitled project takes its name from the brief.
    sqlx::query(
        "UPDATE projects SET instruction = $2, status = 'writing', updated_at = now(), \
             title = CASE WHEN title = 'Untitled essay' THEN left($2, 80) ELSE title END \
         WHERE id = $1",
    )
    .bind(project_id)
    .bind(&instruction)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;

    st.worker.wake();
    Ok((StatusCode::CREATED, Json(json!({ "runId": body.run_id }))))
}

/// `GET /v1/runs/:runId` — where the run stands, for an app coming back to it.
pub async fn get_one(
    State(st): State<AppState>,
    caller: Caller,
    Path(run_id): Path<Uuid>,
) -> Result<Json<Value>, ApiError> {
    let run = owned_run(&st, &caller, run_id).await?;
    Ok(Json(json!({
        "id": run_id,
        "projectId": run.project_id,
        "status": run.status,
        "pendingQuestion": run.pending_question,
        "lastSeq": run.last_seq,
        "error": run.error,
    })))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EventsQuery {
    pub since_seq: Option<i64>,
}

fn frame(event: &LiveEvent) -> Event {
    let data = event.to_json().to_string();
    match event.seq {
        Some(seq) => Event::default().id(seq.to_string()).data(data),
        None => Event::default().data(data),
    }
}

/// `GET /v1/runs/:runId/events?sinceSeq=N` — the run's events as Server-Sent
/// Events: everything stored after `N`, then live until the run ends.
/// `Last-Event-ID` works in place of `sinceSeq`.
pub async fn events(
    State(st): State<AppState>,
    caller: Caller,
    Path(run_id): Path<Uuid>,
    Query(query): Query<EventsQuery>,
    headers: HeaderMap,
) -> Result<Sse<impl Stream<Item = Result<Event, Infallible>>>, ApiError> {
    owned_run(&st, &caller, run_id).await?;

    let since = query
        .since_seq
        .or_else(|| {
            headers
                .get("last-event-id")
                .and_then(|v| v.to_str().ok())
                .and_then(|s| s.trim().parse().ok())
        })
        .unwrap_or(0)
        .max(0);

    // Subscribe before reading the log, so nothing falls between the two.
    // Anything that arrives on both is dropped by the `seq` cursor.
    let mut live = st.hub.subscribe(run_id);
    // Counted as watching for as long as the stream is open, so the run does
    // not push to a phone that is looking at it.
    let following = st.hub.follow(run_id);

    let stream = async_stream::stream! {
        let _following = following;
        let mut cursor = since;
        let mut read_to_end = false;

        'outer: loop {
            // Catch up from the log.
            let Ok(stored) = runs::events_after(&st.db, run_id, cursor).await else {
                break;
            };
            for event in stored {
                cursor = event.seq.unwrap_or(cursor);
                let terminal = is_terminal(&event.kind);
                yield Ok(frame(&event));
                if terminal {
                    break 'outer;
                }
            }

            // Then follow it live. A run no worker in this process holds
            // (queued, parked, or driven elsewhere) is followed by reading
            // the log until a worker here picks it up.
            let Some(receiver) = live.as_mut() else {
                // Listen before looking, so a run going live in between is
                // not missed.
                let opened = st.hub.opened();
                tokio::pin!(opened);
                opened.as_mut().enable();
                live = st.hub.subscribe(run_id);
                if live.is_some() {
                    continue 'outer;
                }
                // An ended run has nothing more once its log has been read to
                // the end. Checked under the run's lock: a run is closed and
                // its terminal event logged under it, so the event is either
                // not due yet or already there to read.
                let active: Option<String> = {
                    let _guard = st.hub.lock(run_id).await;
                    sqlx::query_scalar(&format!(
                        "SELECT status FROM runs WHERE id = $1 AND status IN {ACTIVE}"
                    ))
                    .bind(run_id)
                    .fetch_optional(&st.db)
                    .await
                    .unwrap_or(None)
                };
                if active.is_none() {
                    if read_to_end {
                        break;
                    }
                    read_to_end = true;
                    continue 'outer;
                }
                tokio::select! {
                    _ = opened => {}
                    _ = tokio::time::sleep(st.config.worker_poll.min(Duration::from_secs(1))) => {}
                }
                live = st.hub.subscribe(run_id);
                continue 'outer;
            };
            loop {
                match receiver.recv().await {
                    Ok(event) => {
                        if let Some(seq) = event.seq {
                            if seq <= cursor {
                                continue;
                            }
                            cursor = seq;
                        }
                        let terminal = is_terminal(&event.kind);
                        yield Ok(frame(&event));
                        if terminal {
                            break 'outer;
                        }
                    }
                    // Fell behind the broadcast buffer: re-read the log.
                    Err(RecvError::Lagged(_)) => continue 'outer,
                    // The run closed: one last read of the log, then stop.
                    Err(RecvError::Closed) => {
                        live = None;
                        continue 'outer;
                    }
                }
            }
        }
    };

    Ok(Sse::new(stream).keep_alive(KeepAlive::new().interval(Duration::from_secs(15))))
}

#[derive(Deserialize)]
pub struct Answer {
    pub field: String,
    #[serde(default)]
    pub value: Value,
}

/// `POST /v1/runs/:runId/answer` — answer the question the run is waiting on.
pub async fn answer(
    State(st): State<AppState>,
    caller: Caller,
    Path(run_id): Path<Uuid>,
    Json(body): Json<Answer>,
) -> Result<Json<Value>, ApiError> {
    owned_run(&st, &caller, run_id).await?;
    if body.value.is_null() {
        return Err(ApiError::bad_request("value is required"));
    }

    let _guard = st.hub.lock(run_id).await;
    // Only the question that is pending right now can be answered, and only
    // once: this update is what a second or stale answer loses to.
    // A run no worker holds (parked) is queued with the answer, to be
    // picked up from where it stopped.
    let live = st.hub.is_live(run_id);
    let answered = sqlx::query(
        "UPDATE runs SET pending_question = NULL, updated_at = now(), \
             status = CASE WHEN $3 THEN 'running' ELSE 'queued' END, \
             resume = CASE WHEN $3 THEN NULL ELSE jsonb_build_object('field', $2::text, 'value', $4::jsonb) END \
         WHERE id = $1 AND status = 'waiting_for_user' \
           AND pending_question->>'field' = $2",
    )
    .bind(run_id)
    .bind(&body.field)
    .bind(live)
    .bind(&body.value)
    .execute(&st.db)
    .await?
    .rows_affected();
    if answered == 0 {
        return Err(conflict(
            &format!("no question is waiting for \"{}\"", body.field),
            "no_pending_question",
        ));
    }

    runs::append(
        &st,
        run_id,
        "question_answered",
        json!({ "field": body.field, "value": body.value }),
    )
    .await?;
    if live {
        st.hub.deliver_answer(run_id, body.field, body.value);
    } else {
        st.worker.wake();
    }
    Ok(Json(json!({ "ok": true })))
}

#[derive(Deserialize)]
pub struct Message {
    pub text: Option<String>,
}

/// `POST /v1/runs/:runId/message` — a free chat message to the run.
pub async fn message(
    State(st): State<AppState>,
    caller: Caller,
    Path(run_id): Path<Uuid>,
    Json(body): Json<Message>,
) -> Result<Json<Value>, ApiError> {
    let run = owned_run(&st, &caller, run_id).await?;
    let text = clean_text(body.text, 4_000, "text")?
        .ok_or_else(|| ApiError::bad_request("text is required"))?;
    if !is_active(&run.status) {
        return Err(conflict("this run has ended", "run_ended"));
    }

    let _guard = st.hub.lock(run_id).await;
    runs::append(&st, run_id, "user_message", json!({ "text": text })).await?;
    if st.hub.deliver_message(run_id, text.clone()) {
        return Ok(Json(json!({ "ok": true })));
    }
    // No worker holds the run: keep the message for whoever picks it up, and
    // wake a run that is parked waiting for exactly this.
    let woken: Option<String> = sqlx::query_scalar(
        "UPDATE runs SET inbox = inbox || jsonb_build_array($2::text), updated_at = now(), \
             status = CASE WHEN status = 'waiting_for_user' AND pending_question IS NULL \
                 THEN 'queued' ELSE status END \
         WHERE id = $1 RETURNING status",
    )
    .bind(run_id)
    .bind(&text)
    .fetch_optional(&st.db)
    .await?;
    if woken.as_deref() == Some("queued") {
        st.worker.wake();
    }
    Ok(Json(json!({ "ok": true })))
}

/// `POST /v1/runs/:runId/cancel` — stop the run. Cancelling a run that has
/// already ended is not an error.
pub async fn cancel(
    State(st): State<AppState>,
    caller: Caller,
    Path(run_id): Path<Uuid>,
) -> Result<Json<Value>, ApiError> {
    owned_run(&st, &caller, run_id).await?;

    st.hub.abort(run_id);
    runs::finish(&st, run_id, Outcome::Cancelled).await?;

    let status: String = sqlx::query_scalar("SELECT status FROM runs WHERE id = $1")
        .bind(run_id)
        .fetch_one(&st.db)
        .await?;
    Ok(Json(json!({ "status": status })))
}

/// For `GET /v1/projects/:id`: the project's active run, if any.
pub async fn active_run_id(st: &AppState, project_id: Uuid) -> Result<Option<Uuid>, ApiError> {
    Ok(sqlx::query_scalar(&format!(
        "SELECT id FROM runs WHERE project_id = $1 AND status IN {ACTIVE}"
    ))
    .bind(project_id)
    .fetch_optional(&st.db)
    .await?)
}

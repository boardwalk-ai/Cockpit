//! Studio builds (R5): one generation pass over all of a studio's material —
//! an outline, one lesson per outline entry (8 at a time, each grounded in
//! the passages retrieved for it), then application scenarios. Lessons are
//! written as they land, so the app fills in live. A port of
//! `rag.run_studio_build` + `routers/stream.py`, plus:
//!
//! * **One build per studio** (tasklist A1): starting a build while one is
//!   running returns the running one's id.
//! * **Builds are jobs in `studio_builds`**, claimed with `SKIP LOCKED`, so a
//!   restart resumes them instead of losing them mid-way.
//! * **A failed rebuild leaves the studio as it was**: the outline is made
//!   before anything is cleared, the old topics are kept on the build row
//!   (`previous`) and put back if no lesson could be written.
//! * **Ids carry over**: the outline is shown the old titles, then lessons
//!   and cards are matched to the old ones by similarity (they keep their old ids, so
//!   mastery and card schedules stay) — also across a resume.
//! * **Metered**: every call is in `llm_usage` with this build's id, so a
//!   build's exact cost is one query.

use std::collections::HashMap;
use std::convert::Infallible;
use std::sync::Arc;
use std::time::Duration;

use axum::extract::{Path, Query, State};
use axum::response::sse::{Event, KeepAlive, Sse};
use futures::{Stream, StreamExt};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use crate::gen::{self, Lesson};
use crate::identity::UserId;
use crate::llm::{self, Call, Meter};
use crate::notify;
use crate::progress::owned_studio;
use crate::search;
use crate::sse::{self, SseStream};
use crate::AppState;

const PRIMARY_FALLBACK: &str = "anthropic/claude-sonnet-4-6";
/// A build that hasn't moved for this long is treated as dead.
const STALE: &str = "20 minutes";
const DOCS_TIMEOUT: Duration = Duration::from_secs(600);
const EMBED_TIMEOUT: Duration = Duration::from_secs(30);

/// `studio_builds.previous`: the topics before a rebuild (nullable).
pub async fn ensure_schema(state: &AppState) -> sqlx::Result<()> {
    sqlx::query("ALTER TABLE studio_builds ADD COLUMN IF NOT EXISTS previous jsonb")
        .execute(&state.cockpit)
        .await?;
    Ok(())
}

/// The progress bar's position, as Python weighs it.
pub fn progress_pct(status: &str, done: i32, total: i32) -> f64 {
    let frac = |d: i32, t: i32| (d as f64 / t as f64).clamp(0.0, 1.0);
    let round4 = |x: f64| (x * 10_000.0).round() / 10_000.0;
    match status {
        "done" => 1.0,
        "failed" => 0.0,
        "queued" => 0.02,
        "extracting" if total > 0 => round4(0.02 + 0.18 * frac(done, total)),
        "extracting" => 0.08,
        "generating" if total <= 0 => 0.25,
        "generating" => round4(0.25 + 0.60 * frac(done, total)),
        "scenarios" => 0.92,
        _ => 0.05,
    }
}

fn cut(s: &str, n: usize) -> String {
    if s.chars().count() <= n {
        return s.to_string();
    }
    // Python: `s[:n-3] + "…"`
    let mut t: String = s.chars().take(n - 3).collect();
    t.push('…');
    t
}

fn first(s: &str, n: usize) -> String {
    s.chars().take(n).collect()
}

// --- Endpoints ------------------------------------------------------------------

/// `POST /studios/{id}/build` — `data {buildId, studioId}`. If a build of
/// this studio is already running, that one's id (no second build).
pub async fn start(State(state): State<AppState>, UserId(user): UserId, Path(id): Path<String>) -> SseStream {
    let Some(sid) = owned_studio(&state.cockpit, &id, user).await else {
        return sse::events(vec![sse::error(format!("Studio {id} not found"))]);
    };
    match start_or_join(&state, sid, user).await {
        Ok((build, joined)) => {
            if !joined {
                state.builds.notify_one();
            }
            sse::one(&json!({ "buildId": build.to_string(), "studioId": id }))
        }
        Err(e) => sse::events(vec![sse::error(format!("Could not start build: {e}"))]),
    }
}

/// The running build of the studio, or a new queued one. True if joined.
pub async fn start_or_join(state: &AppState, studio: Uuid, user: Uuid) -> sqlx::Result<(Uuid, bool)> {
    let mut tx = state.cockpit.begin().await?;
    sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended('studio-build:' || $1::text, 0))")
        .bind(studio)
        .execute(&mut *tx)
        .await?;
    // Builds that stopped moving long ago are dead (a crash): close them.
    sqlx::query(&format!(
        "UPDATE studio_builds SET status = 'failed', error = 'The build stopped. Start it again.', updated_at = now() \
         WHERE studio_id = $1 AND status NOT IN ('done', 'failed') AND updated_at < now() - interval '{STALE}'"
    ))
    .bind(studio)
    .execute(&mut *tx)
    .await?;
    let running: Option<Uuid> = sqlx::query_scalar(
        "SELECT id FROM studio_builds WHERE studio_id = $1 AND status NOT IN ('done', 'failed') \
         ORDER BY created_at DESC LIMIT 1",
    )
    .bind(studio)
    .fetch_optional(&mut *tx)
    .await?;
    if let Some(b) = running {
        tx.commit().await?;
        return Ok((b, true));
    }
    let id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO studio_builds (id, studio_id, user_id, status, stage, lessons_total, lessons_done) \
         VALUES ($1, $2, $3, 'queued', 'Starting…', 0, 0)",
    )
    .bind(id)
    .bind(studio)
    .bind(user)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok((id, false))
}

#[derive(Deserialize)]
pub struct StatusQ {
    #[serde(default)]
    snapshot: bool,
}

fn progress_event(r: &sqlx::postgres::PgRow) -> Event {
    let (status, done, total): (String, i32, i32) = (r.get("status"), r.get("lessons_done"), r.get("lessons_total"));
    sse::event(
        "progress",
        &json!({
            "status": status,
            "stage": r.get::<String, _>("stage"),
            "lessonsDone": done,
            "lessonsTotal": total,
            "progressPct": progress_pct(&status, done, total),
        }),
    )
}

/// `GET /studios/{id}/build-status/{build}` — `progress` on each change
/// until done / failed (~10 min), or once with `snapshot=true`.
pub async fn status(
    State(state): State<AppState>,
    UserId(user): UserId,
    Path((_studio, build)): Path<(String, String)>,
    Query(q): Query<StatusQ>,
) -> Sse<impl Stream<Item = Result<Event, Infallible>>> {
    let build = Uuid::parse_str(&build).ok();
    let stream = async_stream::stream! {
        let mut last: Option<(String, String, i32, i32)> = None;
        for _ in 0..1200 {
            let row = match build {
                Some(b) => sqlx::query(
                    "SELECT user_id, status, stage, lessons_done, lessons_total, error FROM studio_builds WHERE id = $1",
                )
                .bind(b)
                .fetch_optional(&state.cockpit)
                .await
                .ok()
                .flatten(),
                None => None,
            };
            let Some(r) = row.filter(|r| r.get::<Uuid, _>("user_id") == user) else {
                yield Ok(sse::error("Build not found"));
                return;
            };
            if q.snapshot {
                yield Ok(progress_event(&r));
                yield Ok(sse::done());
                return;
            }
            let key = (r.get::<String, _>("status"), r.get::<String, _>("stage"), r.get::<i32, _>("lessons_done"), r.get::<i32, _>("lessons_total"));
            if last.as_ref() != Some(&key) {
                yield Ok(progress_event(&r));
                last = Some(key.clone());
            }
            match key.0.as_str() {
                "done" => { yield Ok(sse::done()); return; }
                "failed" => {
                    let e: Option<String> = r.get("error");
                    yield Ok(sse::error(e.unwrap_or_else(|| "Build failed".into())));
                    return;
                }
                _ => tokio::time::sleep(Duration::from_millis(500)).await,
            }
        }
        yield Ok(sse::error("Build timed out"));
    };
    Sse::new(stream).keep_alive(KeepAlive::default())
}

// --- The worker ------------------------------------------------------------------

async fn set(state: &AppState, build: Uuid, status: &str, stage: &str, done: i32, total: i32) {
    let _ = sqlx::query(
        "UPDATE studio_builds SET status = $2, stage = $3, lessons_done = $4, lessons_total = $5, updated_at = now() WHERE id = $1",
    )
    .bind(build)
    .bind(status)
    .bind(first(stage, 160))
    .bind(done)
    .bind(total)
    .execute(&state.cockpit)
    .await;
}

async fn set_stage(state: &AppState, build: Uuid, status: &str, stage: &str) {
    let _ = sqlx::query("UPDATE studio_builds SET status = $2, stage = $3, updated_at = now() WHERE id = $1")
        .bind(build)
        .bind(status)
        .bind(first(stage, 160))
        .execute(&state.cockpit)
        .await;
}

async fn fail(state: &AppState, build: Uuid, error: &str) {
    let _ = sqlx::query("UPDATE studio_builds SET status = 'failed', error = $2, updated_at = now() WHERE id = $1")
        .bind(build)
        .bind(first(error, 500))
        .execute(&state.cockpit)
        .await;
}

/// Claims the oldest queued build.
async fn claim(state: &AppState) -> sqlx::Result<Option<Uuid>> {
    let mut tx = state.cockpit.begin().await?;
    let id: Option<Uuid> = sqlx::query_scalar(
        "SELECT id FROM studio_builds WHERE status = 'queued' ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED",
    )
    .fetch_optional(&mut *tx)
    .await?;
    if let Some(b) = id {
        sqlx::query("UPDATE studio_builds SET status = 'extracting', stage = 'Starting…', updated_at = now() WHERE id = $1")
            .bind(b)
            .execute(&mut *tx)
            .await?;
    }
    tx.commit().await?;
    Ok(id)
}

pub async fn worker(state: AppState, n: usize) {
    loop {
        match claim(&state).await {
            Ok(Some(build)) => {
                let t = std::time::Instant::now();
                match run(&state, build).await {
                    Ok(()) => notify::build_finished(&state, build, None).await,
                    Err(e) => {
                        tracing::warn!(worker = n, %build, "build failed: {e}");
                        fail(&state, build, &e).await;
                        notify::build_finished(&state, build, Some(&e)).await;
                    }
                }
                let cost = sqlx::query(
                    "SELECT count(*)::int8 AS calls, coalesce(sum(prompt_tokens), 0)::int8 AS p, \
                     coalesce(sum(completion_tokens), 0)::int8 AS c, coalesce(sum(cost_usd), 0)::float8 AS usd \
                     FROM llm_usage WHERE build_id = $1",
                )
                .bind(build)
                .fetch_one(&state.cockpit)
                .await;
                if let Ok(r) = cost {
                    tracing::info!(
                        worker = n, %build, secs = t.elapsed().as_secs_f32(),
                        calls = r.get::<i64, _>("calls"), prompt = r.get::<i64, _>("p"),
                        completion = r.get::<i64, _>("c"), usd = r.get::<f64, _>("usd"),
                        "build finished"
                    );
                }
            }
            Ok(None) => {
                let _ = tokio::time::timeout(Duration::from_secs(5), state.builds.notified()).await;
            }
            Err(e) => {
                tracing::warn!("claim build: {e}");
                tokio::time::sleep(Duration::from_secs(5)).await;
            }
        }
    }
}

pub fn spawn(state: &AppState) {
    let s = state.clone();
    let n = state.config.build_workers.max(1);
    tokio::spawn(async move {
        // Builds a stopped process was running: recent ones resume (they
        // kept their `previous`), old ones are closed.
        let _ = sqlx::query(&format!(
            "UPDATE studio_builds SET status = 'failed', error = 'The build stopped. Start it again.', updated_at = now() \
             WHERE status NOT IN ('queued', 'done', 'failed') AND updated_at < now() - interval '{STALE}'"
        ))
        .execute(&s.cockpit)
        .await;
        let _ = sqlx::query(
            "UPDATE studio_builds SET status = 'queued', stage = 'Starting…', updated_at = now() \
             WHERE status NOT IN ('queued', 'done', 'failed')",
        )
        .execute(&s.cockpit)
        .await;
        for i in 0..n {
            tokio::spawn(worker(s.clone(), i));
        }
    });
}

/// Waits until every document of the studio is ready or failed, showing
/// "Ingesting document… 1 of 3: name". False (and the build failed) if
/// none made it or it took over 10 minutes.
async fn wait_for_documents(state: &AppState, build: Uuid, studio: Uuid) -> Result<(), String> {
    let deadline = tokio::time::Instant::now() + DOCS_TIMEOUT;
    loop {
        let rows = sqlx::query("SELECT filename, status FROM documents WHERE studio_id = $1 ORDER BY created_at")
            .bind(studio)
            .fetch_all(&state.cockpit)
            .await
            .map_err(|e| e.to_string())?;
        if rows.is_empty() {
            return Err("No documents uploaded.".into());
        }
        let st = |r: &sqlx::postgres::PgRow| r.get::<String, _>("status");
        let name = |r: &sqlx::postgres::PgRow| r.get::<String, _>("filename");
        let ready: Vec<_> = rows.iter().filter(|r| st(r) == "ready").collect();
        let failed: Vec<_> = rows.iter().filter(|r| st(r) == "failed").collect();
        let pending: Vec<_> = rows.iter().filter(|r| st(r) != "ready" && st(r) != "failed").collect();
        let current = match (pending.first(), ready.last()) {
            (Some(p), _) => name(p),
            (None, Some(r)) => name(r),
            _ => String::new(),
        };
        let current = cut(&current, 64);
        let mut stage = format!("Ingesting document… {} of {}", ready.len(), rows.len());
        if !pending.is_empty() && !current.is_empty() {
            stage.push_str(&format!(": {current}"));
        }
        set(state, build, "extracting", &stage, ready.len() as i32, rows.len() as i32).await;
        if pending.is_empty() {
            if ready.is_empty() {
                let which = failed.first().map(|r| name(r)).unwrap_or_else(|| "ingest".into());
                return Err(format!("Documents failed to ingest ({which})."));
            }
            return Ok(());
        }
        if tokio::time::Instant::now() >= deadline {
            return Err("Timed out ingesting documents.".into());
        }
        tokio::time::sleep(Duration::from_secs(1)).await;
    }
}

struct Ctx {
    state: AppState,
    build: Uuid,
    studio: Uuid,
    user: Uuid,
    key: String,
    model: String,
}

impl Ctx {
    fn meter<'a>(&self, feature: &'a str) -> Meter<'a> {
        Meter { user: self.user, studio: Some(self.studio), build: Some(self.build), feature }
    }

    async fn ask(&self, feature: &str, system: &str, question: &str, context: &str, max_tokens: u32) -> Result<String, String> {
        let call = Call {
            http: &self.state.http,
            key: &self.key,
            model: &self.model,
            messages: llm::context_messages(system, question, context),
            max_tokens,
            temperature: 0.2,
            user: self.user,
        };
        llm::complete(call, &self.state.cockpit, self.meter(feature)).await
    }
}

/// One build, start to finish. Err = the build failed with that message.
pub async fn run(state: &AppState, build: Uuid) -> Result<(), String> {
    let row = sqlx::query("SELECT studio_id, user_id, previous FROM studio_builds WHERE id = $1")
        .bind(build)
        .fetch_one(&state.cockpit)
        .await
        .map_err(|e| e.to_string())?;
    let (studio, user): (Uuid, Uuid) = (row.get("studio_id"), row.get("user_id"));
    let stored_previous: Option<Value> = row.get("previous");

    wait_for_documents(state, build, studio).await?;
    set(state, build, "extracting", "Reading your materials…", 0, 0).await;
    let chunks: Vec<String> =
        sqlx::query_scalar("SELECT content FROM chunks WHERE studio_id = $1 AND user_id = $2 ORDER BY document_id, ordinal")
            .bind(studio)
            .bind(user)
            .fetch_all(&state.vector)
            .await
            .map_err(|e| e.to_string())?;
    if chunks.is_empty() {
        return Err("No material was ingested.".into());
    }

    let (key, model) = match &state.shared {
        Some(pool) => {
            let key = octo_common::llm::openrouter_key(pool).await;
            let primary = octo_common::llm::model(pool, "primary_model", PRIMARY_FALLBACK).await;
            (key, octo_common::llm::model(pool, "secondary_model", &primary).await)
        }
        None => (None, PRIMARY_FALLBACK.to_string()),
    };
    let Some(key) = key else { return Err("The builder isn't connected right now.".into()) };
    let ctx = Arc::new(Ctx { state: state.clone(), build, studio, user, key, model });

    let names: HashMap<Uuid, String> = sqlx::query("SELECT id, filename FROM documents WHERE studio_id = $1")
        .bind(studio)
        .fetch_all(&state.cockpit)
        .await
        .map(|rows| rows.iter().map(|r| (r.get("id"), r.get("filename"))).collect())
        .unwrap_or_default();

    // The topics before this build (a resumed build kept them on its row).
    let previous: Vec<Value> = match stored_previous {
        Some(Value::Array(a)) => a,
        _ => sqlx::query_scalar("SELECT payload FROM generated_topics WHERE studio_id = $1 ORDER BY ordinal")
            .bind(studio)
            .fetch_all(&state.cockpit)
            .await
            .map_err(|e| e.to_string())?,
    };
    let old_titles: Vec<String> = previous.iter().map(|p| gen::text(p.get("title"))).collect();

    // Outline first: if it fails the studio is untouched. It sees the old
    // titles, so lessons that still fit keep their names (and progress).
    set(state, build, "generating", "Building studio…", 0, 0).await;
    let material = gen::material(&chunks, gen::CONTEXT_CHAR_BUDGET);
    let reply = ctx
        .ask("build_outline", gen::OUTLINE_SYSTEM, &gen::outline_hint(&old_titles), &material, gen::OUTLINE_MAX_TOKENS)
        .await
        .map_err(|e| {
            tracing::warn!(%build, "outline: {e}");
            "Couldn't plan the lessons. Try again.".to_string()
        })?;
    let outline = gen::outline(&reply);
    if outline.is_empty() {
        return Err("Couldn't plan the lessons. Try again.".into());
    }
    let total = outline.len() as i32;
    // Which old topic each new lesson takes over (its id, so its mastery and
    // card schedules stay).
    let new_titles: Vec<String> = outline.iter().map(|l| l.title.clone()).collect();
    let takes_over = Arc::new(gen::assign(&new_titles, &old_titles, true));

    // Keep the old topics on the build, then clear the studio for the live
    // fill — in one transaction.
    {
        let mut tx = state.cockpit.begin().await.map_err(|e| e.to_string())?;
        sqlx::query(
            "UPDATE studio_builds SET previous = $2, lessons_total = $3, lessons_done = 0, stage = $4, updated_at = now() WHERE id = $1",
        )
        .bind(build)
        .bind(Value::Array(previous.clone()))
        .bind(total)
        .bind(format!("Getting lessons… 0 of {total}"))
        .execute(&mut *tx)
        .await
        .map_err(|e| e.to_string())?;
        sqlx::query("DELETE FROM generated_topics WHERE studio_id = $1")
            .bind(studio)
            .execute(&mut *tx)
            .await
            .map_err(|e| e.to_string())?;
        tx.commit().await.map_err(|e| e.to_string())?;
    }

    let previous = Arc::new(previous);
    let outline = Arc::new(outline);
    let names = Arc::new(names);
    let material_fallback: Arc<String> = Arc::new(gen::material(&chunks, gen::LESSON_FALLBACK_CHARS));
    let studio_str = studio.to_string();

    let written = futures::stream::iter(0..outline.len())
        .map(|i| {
            let (ctx, outline, names, previous, takes_over, fallback, studio_str) = (
                ctx.clone(),
                outline.clone(),
                names.clone(),
                previous.clone(),
                takes_over.clone(),
                material_fallback.clone(),
                studio_str.clone(),
            );
            async move {
                let lesson = &outline[i];
                let others: Vec<String> =
                    outline.iter().filter(|o| o.title != lesson.title).map(|o| o.title.clone()).collect();
                let old = takes_over[i].map(|j| &previous[j]);
                let old_fronts: Vec<String> = old
                    .and_then(|o| o.get("flashcards"))
                    .and_then(Value::as_array)
                    .map(|cards| cards.iter().map(|c| gen::text(c.get("front"))).collect())
                    .unwrap_or_default();
                let topic = lesson_topic(&ctx, lesson, &others, &old_fronts, &names, &fallback, &studio_str).await?;
                let topic = match old {
                    Some(o) => gen::carry_from(topic, o),
                    None => topic,
                };
                save_lesson(&ctx, i as i32, &topic, total).await.ok()
            }
        })
        .buffer_unordered(gen::DETAIL_CONCURRENCY)
        .filter_map(|x| async move { x })
        .count()
        .await;

    if written == 0 {
        restore(state, studio, user, previous.as_slice()).await;
        return Err("Couldn't write the lessons — your studio wasn't changed. Try again.".into());
    }

    // Scenarios: best effort, never fails the build.
    set_stage(state, build, "scenarios", "Building scenarios…").await;
    match ctx.ask("build_scenarios", gen::SCENARIO_SYSTEM, gen::SCENARIO_HINT, &material, gen::SCENARIO_MAX_TOKENS).await {
        Ok(reply) => {
            let list = gen::scenarios(&reply, &studio_str);
            if let Err(e) = save_scenarios(state, studio, user, &list).await {
                tracing::warn!(%build, "scenarios: {e}");
            }
        }
        Err(e) => tracing::warn!(%build, "scenarios: {e}"),
    }

    let _ = sqlx::query(
        "UPDATE studio_builds SET status = 'done', stage = 'Studio ready', previous = NULL, updated_at = now() WHERE id = $1",
    )
    .bind(build)
    .execute(&state.cockpit)
    .await;
    Ok(())
}

/// The material for one lesson: the passages retrieved for its title and
/// scope (all of them as citations), else the first 24k characters. On a
/// rebuild the lesson's old card fronts go along, to be kept.
async fn lesson_topic(
    ctx: &Ctx,
    lesson: &Lesson,
    others: &[String],
    old_fronts: &[String],
    names: &HashMap<Uuid, String>,
    fallback: &str,
    studio_str: &str,
) -> Option<Value> {
    let q = format!("{}. {}", lesson.title, lesson.scope).trim().to_string();
    let qvec = search::embed_query_within(&ctx.state, &q, EMBED_TIMEOUT).await;
    let hits = search::hybrid(&ctx.state.vector, ctx.user, ctx.studio, &q, qvec, gen::DETAIL_TOP_K)
        .await
        .unwrap_or_default();
    let joined = hits.iter().map(|h| h.content.as_str()).collect::<Vec<_>>().join("\n\n");
    let context = if joined.is_empty() { fallback } else { joined.as_str() };
    let reply = ctx
        .ask(
            "build_lesson",
            gen::DETAIL_SYSTEM,
            &gen::detail_hint_rebuild(&lesson.title, &lesson.scope, others, old_fronts),
            context,
            gen::DETAIL_MAX_TOKENS,
        )
        .await
        .map_err(|e| tracing::warn!(build = %ctx.build, lesson = %lesson.title, "lesson: {e}"))
        .ok()?;
    let Some(Value::Object(obj)) = gen::parse_json(&reply) else {
        tracing::warn!(build = %ctx.build, lesson = %lesson.title, "lesson reply wasn't a JSON object");
        return None;
    };
    let raw = gen::lesson_raw(obj, lesson, others);
    Some(gen::shape_topic(&raw, studio_str, gen::hits_to_sources(&hits, names)))
}

/// Writes one finished lesson and moves the counter.
async fn save_lesson(ctx: &Ctx, ordinal: i32, topic: &Value, total: i32) -> sqlx::Result<()> {
    let mut tx = ctx.state.cockpit.begin().await?;
    sqlx::query("INSERT INTO generated_topics (id, studio_id, user_id, ordinal, payload) VALUES ($1, $2, $3, $4, $5)")
        .bind(Uuid::new_v4())
        .bind(ctx.studio)
        .bind(ctx.user)
        .bind(ordinal)
        .bind(topic)
        .execute(&mut *tx)
        .await?;
    let done: i32 = sqlx::query_scalar(
        "UPDATE studio_builds SET lessons_done = lessons_done + 1, updated_at = now() WHERE id = $1 RETURNING lessons_done",
    )
    .bind(ctx.build)
    .fetch_one(&mut *tx)
    .await?;
    let title = topic.get("title").and_then(Value::as_str).map(str::trim).filter(|t| !t.is_empty()).unwrap_or("lesson");
    let stage = if total > 0 {
        format!("Getting lessons… {done} of {total}: {}", cut(title, 72))
    } else {
        format!("Getting lessons… {}", cut(title, 72))
    };
    sqlx::query("UPDATE studio_builds SET stage = $2 WHERE id = $1")
        .bind(ctx.build)
        .bind(first(&stage, 160))
        .execute(&mut *tx)
        .await?;
    tx.commit().await
}

/// Puts the topics from before the rebuild back.
async fn restore(state: &AppState, studio: Uuid, user: Uuid, previous: &[Value]) {
    let r: sqlx::Result<()> = async {
        let mut tx = state.cockpit.begin().await?;
        sqlx::query("DELETE FROM generated_topics WHERE studio_id = $1").bind(studio).execute(&mut *tx).await?;
        for (i, p) in previous.iter().enumerate() {
            sqlx::query("INSERT INTO generated_topics (id, studio_id, user_id, ordinal, payload) VALUES ($1, $2, $3, $4, $5)")
                .bind(Uuid::new_v4())
                .bind(studio)
                .bind(user)
                .bind(i as i32)
                .bind(p)
                .execute(&mut *tx)
                .await?;
        }
        tx.commit().await
    }
    .await;
    if let Err(e) = r {
        tracing::warn!(%studio, "restore topics: {e}");
    }
}

async fn save_scenarios(state: &AppState, studio: Uuid, user: Uuid, list: &[Value]) -> sqlx::Result<()> {
    let mut tx = state.cockpit.begin().await?;
    sqlx::query("DELETE FROM generated_scenarios WHERE studio_id = $1").bind(studio).execute(&mut *tx).await?;
    for (i, p) in list.iter().enumerate() {
        sqlx::query("INSERT INTO generated_scenarios (id, studio_id, user_id, ordinal, payload) VALUES ($1, $2, $3, $4, $5)")
            .bind(Uuid::new_v4())
            .bind(studio)
            .bind(user)
            .bind(i as i32)
            .bind(p)
            .execute(&mut *tx)
            .await?;
    }
    tx.commit().await
}

// --- Filling in what older studios lack ---------------------------------------------

async fn primary(state: &AppState) -> (Option<String>, String) {
    llm::credentials(state.shared.as_ref(), "primary_model", PRIMARY_FALLBACK).await
}

/// `POST /studios/{id}/connections` — how the topics connect, made once
/// (one small call) for studios built before the outline recorded it. The
/// rows stay locked during the call, so a second tap waits and then finds
/// them done instead of paying again.
pub async fn connections(State(state): State<AppState>, UserId(user): UserId, Path(id): Path<String>) -> SseStream {
    let Some(sid) = owned_studio(&state.cockpit, &id, user).await else {
        return sse::events(vec![sse::error("Studio not found")]);
    };
    let r: Result<(i32, bool), String> = async {
        let mut tx = state.cockpit.begin().await.map_err(|e| e.to_string())?;
        let rows = sqlx::query("SELECT id, payload FROM generated_topics WHERE studio_id = $1 ORDER BY ordinal FOR UPDATE")
            .bind(sid)
            .fetch_all(&mut *tx)
            .await
            .map_err(|e| e.to_string())?;
        let payloads: Vec<(Uuid, Value)> = rows.iter().map(|r| (r.get("id"), r.get("payload"))).collect();
        let has = |p: &Value, k: &str| p.get(k).and_then(Value::as_array).is_some_and(|a| !a.is_empty());
        let known = payloads.iter().any(|(_, p)| has(p, "prerequisites") || has(p, "relatesTo"));
        let mut added = 0;
        if !payloads.is_empty() && !known {
            let titles: Vec<String> = payloads.iter().map(|(_, p)| gen::text(p.get("title"))).collect();
            let links = if titles.len() < 2 {
                HashMap::new()
            } else {
                let (key, model) = primary(&state).await;
                match key {
                    None => HashMap::new(),
                    Some(key) => {
                        let call = Call {
                            http: &state.http,
                            key: &key,
                            model: &model,
                            messages: llm::context_messages(gen::CONNECT_SYSTEM, &gen::connect_hint(&titles), ""),
                            max_tokens: gen::CONNECT_MAX_TOKENS,
                            temperature: 0.2,
                            user,
                        };
                        let meter = Meter { user, studio: Some(sid), build: None, feature: "connections" };
                        match llm::complete(call, &state.cockpit, meter).await {
                            Ok(reply) => gen::clean_connections(gen::parse_json(&reply), &titles),
                            Err(e) => {
                                tracing::warn!(studio = %sid, "connections: {e}");
                                HashMap::new()
                            }
                        }
                    }
                }
            };
            for (row, p) in &payloads {
                let Some((builds_on, relates)) = links.get(&gen::text(p.get("title"))) else { continue };
                let mut p = p.clone();
                p["prerequisites"] = json!(builds_on);
                p["relatesTo"] = json!(relates);
                sqlx::query("UPDATE generated_topics SET payload = $2 WHERE id = $1")
                    .bind(row)
                    .bind(&p)
                    .execute(&mut *tx)
                    .await
                    .map_err(|e| e.to_string())?;
                added += 1;
            }
        }
        tx.commit().await.map_err(|e| e.to_string())?;
        Ok((added, known))
    }
    .await;
    match r {
        Ok((added, known)) => sse::one(&json!({ "updated": added, "alreadyKnown": known })),
        Err(e) => sse::events(vec![sse::error(e)]),
    }
}

/// `POST /studios/{id}/topics/{topic}/concepts` — a lesson's concept map,
/// made once (one call) for lessons built before maps existed; then kept.
pub async fn concepts(
    State(state): State<AppState>,
    UserId(user): UserId,
    Path((id, topic)): Path<(String, String)>,
) -> SseStream {
    let Some(sid) = owned_studio(&state.cockpit, &id, user).await else {
        return sse::events(vec![sse::error("Studio not found")]);
    };
    let r: Result<Option<bool>, String> = async {
        let mut tx = state.cockpit.begin().await.map_err(|e| e.to_string())?;
        let rows = sqlx::query("SELECT id, payload FROM generated_topics WHERE studio_id = $1 ORDER BY ordinal FOR UPDATE")
            .bind(sid)
            .fetch_all(&mut *tx)
            .await
            .map_err(|e| e.to_string())?;
        let payloads: Vec<(Uuid, Value)> = rows.iter().map(|r| (r.get("id"), r.get("payload"))).collect();
        let Some(at) = payloads.iter().position(|(_, p)| p.get("id").and_then(Value::as_str) == Some(topic.as_str())) else {
            return Ok(None);
        };
        let (row, payload) = &payloads[at];
        let has = payload.get("concepts").and_then(Value::as_array).is_some_and(|a| !a.is_empty());
        if has {
            return Ok(Some(false));
        }
        let others: Vec<String> =
            payloads.iter().enumerate().filter(|(i, _)| *i != at).map(|(_, (_, p))| gen::text(p.get("title"))).collect();
        let (key, model) = primary(&state).await;
        let Some(key) = key else { return Ok(Some(false)) };
        let call = Call {
            http: &state.http,
            key: &key,
            model: &model,
            messages: llm::context_messages(
                gen::CONCEPT_SYSTEM,
                &gen::concept_question(&gen::text(payload.get("title")), &others),
                &gen::concept_context(payload),
            ),
            max_tokens: gen::CONCEPT_MAX_TOKENS,
            temperature: 0.2,
            user,
        };
        let meter = Meter { user, studio: Some(sid), build: None, feature: "concepts" };
        let reply = match llm::complete(call, &state.cockpit, meter).await {
            Ok(r) => r,
            Err(e) => {
                tracing::warn!(studio = %sid, %topic, "concepts: {e}");
                return Ok(Some(false));
            }
        };
        let Some(Value::Object(mut obj)) = gen::parse_json(&reply) else { return Ok(Some(false)) };
        obj.insert("_otherTitles".into(), json!(others));
        let tid = gen::text(payload.get("id"));
        let (c, l) = gen::shape_concepts(&Value::Object(obj), if tid.is_empty() { "t" } else { &tid });
        if c.is_empty() {
            return Ok(Some(false));
        }
        let mut p = payload.clone();
        p["concepts"] = json!(c);
        p["conceptLinks"] = json!(l);
        sqlx::query("UPDATE generated_topics SET payload = $2 WHERE id = $1")
            .bind(row)
            .bind(&p)
            .execute(&mut *tx)
            .await
            .map_err(|e| e.to_string())?;
        tx.commit().await.map_err(|e| e.to_string())?;
        Ok(Some(true))
    }
    .await;
    match r {
        Ok(Some(made)) => sse::one(&json!({ "made": made })),
        Ok(None) => sse::events(vec![sse::error("Topic not found")]),
        Err(e) => sse::events(vec![sse::error(e)]),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn progress_like_python() {
        assert_eq!(progress_pct("queued", 0, 0), 0.02);
        assert_eq!(progress_pct("extracting", 1, 4), 0.065);
        assert_eq!(progress_pct("extracting", 0, 0), 0.08);
        assert_eq!(progress_pct("generating", 0, 0), 0.25);
        assert_eq!(progress_pct("generating", 3, 12), 0.4);
        assert_eq!(progress_pct("generating", 20, 12), 0.85);
        assert_eq!(progress_pct("scenarios", 12, 12), 0.92);
        assert_eq!(progress_pct("done", 0, 0), 1.0);
        assert_eq!(progress_pct("failed", 3, 4), 0.0);
        assert_eq!(progress_pct("weird", 0, 0), 0.05);
    }

    #[test]
    fn stage_names_are_cut() {
        assert_eq!(cut("abc", 64), "abc");
        let long = "x".repeat(80);
        assert_eq!(cut(&long, 72).chars().count(), 70);
        assert!(cut(&long, 72).ends_with('…'));
    }
}

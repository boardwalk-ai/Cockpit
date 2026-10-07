//! Progress writes (R2): quiz answers, card reviews, "Got it" on a lesson,
//! rename, and the activity read-back. Same effects as `routers/stream.py`
//! + `services/progress.py` / `schedule.py` / `activity.py`, plus:
//!
//! * **Idempotent** — the app may send `event_id` (a uuid per answer). It
//!   becomes the `study_events` row id, so a retried request inserts nothing
//!   and changes nothing else (tasklist A2).
//! * **"Got it" counts once a day per lesson** (A3).
//!
//! Like the Python service, writes never fail the client's ack.

use std::collections::BTreeMap;

use axum::extract::{Path, Query, State};
use chrono::{DateTime, Duration, NaiveDate, Utc};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::{PgPool, Postgres, Row, Transaction};
use uuid::Uuid;

use crate::identity::UserId;
use crate::schedule::{next_state, status, CardState};
use crate::sse::{self, SseStream};
use crate::AppState;

pub const MAX_DAYS: i64 = 62;

/// The studio's uuid if `user` owns it.
pub async fn owned_studio(db: &PgPool, studio: &str, user: Uuid) -> Option<Uuid> {
    let id = Uuid::parse_str(studio).ok()?;
    sqlx::query_scalar::<_, Uuid>("SELECT id FROM studios WHERE id = $1 AND user_id = $2")
        .bind(id)
        .bind(user)
        .fetch_optional(db)
        .await
        .ok()
        .flatten()
}

/// Logs one event. False when that event id was already logged (a retry).
async fn log_event(
    tx: &mut Transaction<'_, Postgres>,
    event_id: Option<Uuid>,
    user: Uuid,
    studio: Uuid,
    topic: &str,
    kind: &str,
    correct: bool,
) -> sqlx::Result<bool> {
    let done = sqlx::query(
        "INSERT INTO study_events (id, user_id, studio_id, topic_id, kind, correct) \
         VALUES ($1, $2, $3, $4, $5, $6) ON CONFLICT (id) DO NOTHING",
    )
    .bind(event_id.unwrap_or_else(Uuid::new_v4))
    .bind(user)
    .bind(studio)
    .bind(truncate(topic, 64))
    .bind(kind)
    .bind(correct)
    .execute(&mut **tx)
    .await?;
    Ok(done.rows_affected() == 1)
}

fn truncate(s: &str, n: usize) -> &str {
    match s.char_indices().nth(n) {
        Some((i, _)) => &s[..i],
        None => s,
    }
}

/// Moves a topic's mastery by `delta` (clamped to 0..1) and bumps one
/// counter column. Creates the row on first use, as Python's `_get_or_create`.
async fn bump(
    tx: &mut Transaction<'_, Postgres>,
    user: Uuid,
    studio: Uuid,
    topic: &str,
    delta: f64,
    counter: &str,
    correct: bool,
) -> sqlx::Result<f64> {
    let (qa, qc, fr, rv) = match counter {
        "quiz" => (1, i32::from(correct), 0, 0),
        "card" => (0, 0, 1, 0),
        _ => (0, 0, 0, 1),
    };
    sqlx::query_scalar(
        "INSERT INTO topic_progress \
           (id, user_id, studio_id, topic_id, mastery, quiz_attempts, quiz_correct, flashcard_reviews, reviews) \
         VALUES ($1, $2, $3, $4, LEAST(1, GREATEST(0, $5)), $6, $7, $8, $9) \
         ON CONFLICT (user_id, topic_id) DO UPDATE SET \
           mastery = LEAST(1, GREATEST(0, topic_progress.mastery + $5)), \
           quiz_attempts = topic_progress.quiz_attempts + $6, \
           quiz_correct = topic_progress.quiz_correct + $7, \
           flashcard_reviews = topic_progress.flashcard_reviews + $8, \
           reviews = topic_progress.reviews + $9, \
           updated_at = now() \
         RETURNING mastery",
    )
    .bind(Uuid::new_v4())
    .bind(user)
    .bind(studio)
    .bind(truncate(topic, 64))
    .bind(delta)
    .bind(qa)
    .bind(qc)
    .bind(fr)
    .bind(rv)
    .fetch_one(&mut **tx)
    .await
}

#[derive(Deserialize)]
pub struct QuizQ {
    correct: bool,
    event_id: Option<Uuid>,
}

/// `POST /studios/{id}/topics/{tid}/quiz-result?correct=&event_id=`
pub async fn quiz_result(
    State(state): State<AppState>,
    UserId(user): UserId,
    Path((studio, topic)): Path<(String, String)>,
    Query(q): Query<QuizQ>,
) -> SseStream {
    if let Some(sid) = owned_studio(&state.cockpit, &studio, user).await {
        let r: sqlx::Result<()> = async {
            let mut tx = state.cockpit.begin().await?;
            if log_event(&mut tx, q.event_id, user, sid, &topic, "quiz", q.correct).await? {
                bump(&mut tx, user, sid, &topic, if q.correct { 0.08 } else { -0.05 }, "quiz", q.correct)
                    .await?;
            }
            tx.commit().await
        }
        .await;
        if let Err(e) = r {
            tracing::warn!("quiz-result: {e}");
        }
    }
    sse::ack()
}

#[derive(Deserialize)]
pub struct QualityQ {
    quality: f64,
    event_id: Option<Uuid>,
}

/// `POST /studios/{id}/topics/{tid}/flashcard-review?quality=` (0..1, legacy)
pub async fn flashcard_review(
    State(state): State<AppState>,
    UserId(user): UserId,
    Path((studio, topic)): Path<(String, String)>,
    Query(q): Query<QualityQ>,
) -> SseStream {
    let quality = q.quality.clamp(0.0, 1.0);
    if let Some(sid) = owned_studio(&state.cockpit, &studio, user).await {
        let r: sqlx::Result<()> = async {
            let mut tx = state.cockpit.begin().await?;
            if log_event(&mut tx, q.event_id, user, sid, &topic, "card", quality >= 0.5).await? {
                bump(&mut tx, user, sid, &topic, quality * 0.10 - 0.04, "card", false).await?;
            }
            tx.commit().await
        }
        .await;
        if let Err(e) = r {
            tracing::warn!("flashcard-review: {e}");
        }
    }
    sse::ack()
}

/// A card's schedule as the app reads it.
fn fields(s: &CardState, due: Option<DateTime<Utc>>) -> Value {
    json!({
        "reps": s.reps,
        "intervalDays": s.interval_days,
        "ease": s.ease,
        "lapses": s.lapses,
        "dueDate": due,
        "status": status(s),
    })
}

#[derive(Deserialize)]
pub struct GradeQ {
    topic_id: String,
    grade: i32,
    event_id: Option<Uuid>,
}

/// `POST /studios/{id}/flashcards/{card}/review?topic_id=&grade=0..3&event_id=`
/// Returns the card's new schedule (`data`), or `{}` when nothing was done.
pub async fn card_review(
    State(state): State<AppState>,
    UserId(user): UserId,
    Path((studio, card)): Path<(String, String)>,
    Query(q): Query<GradeQ>,
) -> SseStream {
    let grade = q.grade.clamp(0, 3);
    if card.chars().count() > 64 || q.topic_id.chars().count() > 64 {
        return sse::one(&json!({}));
    }
    let Some(sid) = owned_studio(&state.cockpit, &studio, user).await else {
        return sse::one(&json!({}));
    };
    let r: sqlx::Result<Value> = async {
        let mut tx = state.cockpit.begin().await?;
        let row = sqlx::query(
            "SELECT reps, interval_days, ease, lapses, due_at FROM flashcard_schedule \
             WHERE user_id = $1 AND card_id = $2 FOR UPDATE",
        )
        .bind(user)
        .bind(&card)
        .fetch_optional(&mut *tx)
        .await?;
        let before = row.as_ref().map(|r| CardState {
            reps: r.get("reps"),
            interval_days: r.get("interval_days"),
            ease: r.get("ease"),
            lapses: r.get("lapses"),
        });
        if !log_event(&mut tx, q.event_id, user, sid, &q.topic_id, "card", grade >= 2).await? {
            // A retry: report the schedule as it stands.
            tx.rollback().await?;
            return Ok(match (before, row) {
                (Some(s), Some(r)) => fields(&s, r.get("due_at")),
                _ => json!({}),
            });
        }
        let (after, wait) = next_state(before.unwrap_or_default(), grade);
        let due = Utc::now() + wait;
        sqlx::query(
            "INSERT INTO flashcard_schedule \
               (id, user_id, studio_id, topic_id, card_id, reps, interval_days, ease, lapses, due_at) \
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) \
             ON CONFLICT (user_id, card_id) DO UPDATE SET \
               reps = $6, interval_days = $7, ease = $8, lapses = $9, due_at = $10, updated_at = now()",
        )
        .bind(Uuid::new_v4())
        .bind(user)
        .bind(sid)
        .bind(&q.topic_id)
        .bind(&card)
        .bind(after.reps)
        .bind(after.interval_days)
        .bind(after.ease)
        .bind(after.lapses)
        .bind(due)
        .execute(&mut *tx)
        .await?;
        bump(&mut tx, user, sid, &q.topic_id, f64::from(grade) / 3.0 * 0.10 - 0.04, "card", false)
            .await?;
        tx.commit().await?;
        Ok(fields(&after, Some(due)))
    }
    .await;
    match r {
        Ok(v) => sse::one(&v),
        Err(e) => {
            tracing::warn!("card review: {e}");
            sse::one(&json!({}))
        }
    }
}

/// `POST /studios/{id}/topics/{tid}/mark-reviewed` — once a day per lesson.
pub async fn mark_reviewed(
    State(state): State<AppState>,
    UserId(user): UserId,
    Path((studio, topic)): Path<(String, String)>,
) -> SseStream {
    if let Some(sid) = owned_studio(&state.cockpit, &studio, user).await {
        let r: sqlx::Result<()> = async {
            let mut tx = state.cockpit.begin().await?;
            // One lock per user+lesson so two quick taps can't both count.
            sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))")
                .bind(format!("reviewed:{user}:{topic}"))
                .execute(&mut *tx)
                .await?;
            let recent: bool = sqlx::query_scalar(
                "SELECT EXISTS (SELECT 1 FROM study_events WHERE user_id = $1 AND studio_id = $2 \
                 AND topic_id = $3 AND kind = 'lesson' AND at > now() - interval '20 hours')",
            )
            .bind(user)
            .bind(sid)
            .bind(truncate(&topic, 64))
            .fetch_one(&mut *tx)
            .await?;
            if !recent {
                log_event(&mut tx, None, user, sid, &topic, "lesson", true).await?;
                bump(&mut tx, user, sid, &topic, 0.03, "lesson", false).await?;
            }
            tx.commit().await
        }
        .await;
        if let Err(e) = r {
            tracing::warn!("mark-reviewed: {e}");
        }
    }
    sse::ack()
}

#[derive(Deserialize)]
pub struct RenameQ {
    title: String,
}

/// `POST /studios/{id}/rename?title=`
pub async fn rename(
    State(state): State<AppState>,
    UserId(user): UserId,
    Path(studio): Path<String>,
    Query(q): Query<RenameQ>,
) -> SseStream {
    let name: String = q.title.split_whitespace().collect::<Vec<_>>().join(" ");
    let name = truncate(&name, 200).to_string();
    let mut renamed = false;
    if !name.is_empty() {
        if let Some(sid) = owned_studio(&state.cockpit, &studio, user).await {
            renamed = sqlx::query("UPDATE studios SET title = $1 WHERE id = $2")
                .bind(&name)
                .bind(sid)
                .execute(&state.cockpit)
                .await
                .map(|r| r.rows_affected() == 1)
                .unwrap_or(false);
        }
    }
    sse::one(&json!({ "renamed": renamed, "title": name }))
}

/// Events grouped by the user's local day: the last `days` days, oldest
/// first (a port of `services/activity.bucket`).
pub fn bucket(
    events: &[(DateTime<Utc>, String, bool)],
    days: i64,
    tz_minutes: i64,
    now: DateTime<Utc>,
) -> Vec<Value> {
    let shift = Duration::minutes(tz_minutes);
    let today: NaiveDate = (now + shift).date_naive();
    let first = today - Duration::days(days - 1);
    let mut out: BTreeMap<NaiveDate, (i64, i64, i64)> =
        (0..days).map(|i| (first + Duration::days(i), (0, 0, 0))).collect();
    for (at, kind, correct) in events {
        if let Some(row) = out.get_mut(&(*at + shift).date_naive()) {
            match kind.as_str() {
                "card" => row.0 += 1,
                "quiz" => {
                    row.1 += 1;
                    if *correct {
                        row.2 += 1;
                    }
                }
                _ => {}
            }
        }
    }
    out.into_iter()
        .map(|(d, (cards, quiz, right))| {
            json!({ "date": d.to_string(), "cards": cards, "quiz": quiz, "quizRight": right })
        })
        .collect()
}

#[derive(Deserialize)]
pub struct ActivityQ {
    days: Option<i64>,
    tz: Option<i64>,
}

/// `GET /studios/{id}/activity?days=14&tz=<minutes east of UTC>`
pub async fn activity(
    State(state): State<AppState>,
    UserId(user): UserId,
    Path(studio): Path<String>,
    Query(q): Query<ActivityQ>,
) -> SseStream {
    let days = q.days.unwrap_or(14).clamp(1, MAX_DAYS);
    let tz = q.tz.unwrap_or(0).clamp(-14 * 60, 14 * 60);
    let mut rows = Vec::new();
    if let Some(sid) = owned_studio(&state.cockpit, &studio, user).await {
        let now = Utc::now();
        let events: Vec<(DateTime<Utc>, String, bool)> = sqlx::query_as(
            "SELECT at, kind, correct FROM study_events \
             WHERE user_id = $1 AND studio_id = $2 AND at >= $3",
        )
        .bind(user)
        .bind(sid)
        .bind(now - Duration::days(days + 1))
        .fetch_all(&state.cockpit)
        .await
        .unwrap_or_default();
        rows = bucket(&events, days, tz, now);
    }
    sse::one(&rows)
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    #[test]
    fn buckets_by_local_day_like_python() {
        // Same case as Backend/tests/test_units.py::test_activity_buckets_by_local_day.
        let now = Utc.with_ymd_and_hms(2026, 10, 7, 20, 0, 0).unwrap();
        let ev = |h: u32, d: u32, m: u32, kind: &str, ok: bool| {
            (Utc.with_ymd_and_hms(2026, m, d, h, 0, 0).unwrap(), kind.to_string(), ok)
        };
        let events = vec![
            ev(19, 7, 10, "card", true),
            ev(10, 7, 10, "quiz", true),
            ev(11, 7, 10, "quiz", false),
            ev(11, 1, 9, "card", true),
        ];
        let rows = bucket(&events, 3, 390, now);
        let dates: Vec<_> = rows.iter().map(|r| r["date"].as_str().unwrap().to_string()).collect();
        assert_eq!(dates, ["2026-10-06", "2026-10-07", "2026-10-08"]);
        assert_eq!(rows[1], json!({"date": "2026-10-07", "cards": 0, "quiz": 2, "quizRight": 1}));
        assert_eq!(rows[2]["cards"], 1);
        assert_eq!(rows[0], json!({"date": "2026-10-06", "cards": 0, "quiz": 0, "quizRight": 0}));
    }

    #[test]
    fn truncates_on_char_boundaries() {
        assert_eq!(truncate("abc", 2), "ab");
        assert_eq!(truncate("ကကက", 2), "ကက");
        assert_eq!(truncate("ab", 5), "ab");
    }
}

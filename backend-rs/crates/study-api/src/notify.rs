//! Notifications (R6): the phone hears when a studio is ready (or failed),
//! when it is time for today's planned session, and when cards are piling
//! up. Sent with Firebase Cloud Messaging (`octo_common::push`).
//!
//! Everything goes through an outbox, `study_notifications`, keyed by a
//! dedupe key (`build:<id>`, `plan:<user>:<day>`, `due:<user>:<day>`), so a
//! retry or a second worker can never send one twice. A sender leases due
//! rows, sends them to every phone of the user and marks them sent; a
//! failed send is tried again later (at most 5 times), a reminder older than
//! six hours is dropped rather than sent late.
//!
//! Reminders are polite: at most one plan reminder and one cards reminder a
//! day per person, none on a day they already studied, none for people who
//! haven't studied in two weeks, and only in a three-hour window after the
//! time they chose (so a worker that was down doesn't wake anyone at night).

use std::collections::BTreeMap;
use std::time::Duration;

use axum::extract::{Path, State};
use axum::Json;
use chrono::{DateTime, Datelike, Duration as Span, NaiveDate, NaiveDateTime, Timelike, Utc};
use octo_common::push::{Notice, PushError};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::{PgPool, Row};
use uuid::Uuid;

use crate::identity::UserId;
use crate::progress::owned_studio;
use crate::sse::{self, SseStream};
use crate::AppState;

/// The Android notification channel the app makes for Study Studio.
pub const CHANNEL: &str = "study";
/// Hours after the chosen time a reminder may still go out.
const WINDOW_MIN: i32 = 180;
/// The evening reminder for due cards (local time, minutes).
const DUE_AT: i32 = 19 * 60;
/// Fewer due cards than this isn't worth a notification.
const DUE_MIN: i64 = 5;
const MAX_ATTEMPTS: i32 = 5;
const BODY_LIMIT: usize = 180;

pub async fn ensure_schema(db: &PgPool) -> sqlx::Result<()> {
    for sql in [
        "CREATE TABLE IF NOT EXISTS study_devices (\
           id uuid PRIMARY KEY, user_id uuid NOT NULL, token text NOT NULL UNIQUE, \
           platform varchar(16) NOT NULL, tz_minutes integer NOT NULL DEFAULT 0, \
           created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now())",
        "CREATE INDEX IF NOT EXISTS ix_study_devices_user ON study_devices (user_id)",
        "CREATE TABLE IF NOT EXISTS study_plans (\
           studio_id uuid PRIMARY KEY REFERENCES studios(id) ON DELETE CASCADE, user_id uuid NOT NULL, \
           mode varchar(8) NOT NULL, exam date, minutes integer NOT NULL, days smallint[] NOT NULL, \
           remind_minute integer, tz_minutes integer NOT NULL DEFAULT 0, \
           updated_at timestamptz NOT NULL DEFAULT now())",
        "CREATE INDEX IF NOT EXISTS ix_study_plans_remind ON study_plans (user_id) WHERE remind_minute IS NOT NULL",
        "CREATE TABLE IF NOT EXISTS study_notifications (\
           id uuid PRIMARY KEY, user_id uuid NOT NULL, kind varchar(24) NOT NULL, \
           dedupe_key varchar(200) NOT NULL UNIQUE, title text NOT NULL, body text NOT NULL, \
           data jsonb NOT NULL DEFAULT '{}', due_at timestamptz NOT NULL DEFAULT now(), \
           sent_at timestamptz, attempts integer NOT NULL DEFAULT 0, error text, \
           created_at timestamptz NOT NULL DEFAULT now())",
        "CREATE INDEX IF NOT EXISTS ix_study_notifications_due ON study_notifications (due_at) WHERE sent_at IS NULL",
    ] {
        sqlx::query(sql).execute(db).await?;
    }
    Ok(())
}

fn shorten(text: &str, n: usize) -> String {
    let text = text.trim();
    if text.chars().count() <= n {
        return text.to_string();
    }
    let cut: String = text.chars().take(n - 1).collect();
    format!("{}…", cut.trim_end())
}

fn plural(n: i64, one: &str, many: &str) -> String {
    format!("{n} {}", if n == 1 { one } else { many })
}

/// Queues a notification; nothing happens if its key was queued before.
/// True if it was new.
#[allow(clippy::too_many_arguments)]
pub async fn enqueue(
    db: &PgPool,
    user: Uuid,
    kind: &str,
    key: &str,
    title: &str,
    body: &str,
    link: &str,
    studio: Option<Uuid>,
) -> sqlx::Result<bool> {
    let mut data = json!({ "type": kind, "link": link });
    if let Some(s) = studio {
        data["studioId"] = json!(s.to_string());
    }
    let r = sqlx::query(
        "INSERT INTO study_notifications (id, user_id, kind, dedupe_key, title, body, data) \
         VALUES ($1, $2, $3, $4, $5, $6, $7) ON CONFLICT (dedupe_key) DO NOTHING",
    )
    .bind(Uuid::new_v4())
    .bind(user)
    .bind(kind)
    .bind(key)
    .bind(shorten(title, 80))
    .bind(shorten(body, BODY_LIMIT))
    .bind(data)
    .execute(db)
    .await?;
    Ok(r.rows_affected() == 1)
}

/// A finished (or failed) build, for its owner's phones.
pub async fn build_finished(state: &AppState, build: Uuid, error: Option<&str>) {
    let row = sqlx::query(
        "SELECT b.user_id, b.studio_id, s.title, \
           (SELECT count(*) FROM generated_topics t WHERE t.studio_id = b.studio_id) AS lessons \
         FROM studio_builds b JOIN studios s ON s.id = b.studio_id WHERE b.id = $1",
    )
    .bind(build)
    .fetch_optional(&state.cockpit)
    .await;
    let Ok(Some(r)) = row else { return };
    let (user, studio, title): (Uuid, Uuid, String) = (r.get("user_id"), r.get("studio_id"), r.get("title"));
    let lessons: i64 = r.get("lessons");
    let (kind, body) = match error {
        None => ("studio_ready", format!("Your studio is ready — {}. Tap to start.", plural(lessons, "lesson", "lessons"))),
        Some(e) => ("studio_failed", format!("The build didn't finish. {e}")),
    };
    let r = enqueue(&state.cockpit, user, kind, &format!("build:{build}"), &title, &body, &format!("/study/{studio}"), Some(studio)).await;
    match r {
        Ok(true) => state.notices.notify_one(),
        Ok(false) => {}
        Err(e) => tracing::warn!(%build, "notify: {e}"),
    }
}

// --- What the app tells us --------------------------------------------------------

fn ack_or(r: Result<(), String>) -> SseStream {
    match r {
        Ok(()) => sse::ack(),
        Err(e) => sse::events(vec![sse::error(e)]),
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DeviceIn {
    id: Uuid,
    token: String,
    platform: String,
    #[serde(default)]
    tz_minutes: i32,
}

/// `POST /devices` `{id, token, platform, tzMinutes}` — this install gets
/// Study Studio notifications. Whoever is signed in owns it; a token moves
/// with a reinstall (one install per token).
pub async fn put_device(State(state): State<AppState>, UserId(user): UserId, Json(d): Json<DeviceIn>) -> SseStream {
    let token = d.token.trim().to_string();
    if token.is_empty() || token.len() > 4096 {
        return ack_or(Err("token is required".into()));
    }
    if !matches!(d.platform.as_str(), "android" | "ios" | "web") {
        return ack_or(Err("platform must be android, ios or web".into()));
    }
    let tz = d.tz_minutes.clamp(-720, 840);
    let r: sqlx::Result<()> = async {
        let mut tx = state.cockpit.begin().await?;
        sqlx::query("DELETE FROM study_devices WHERE token = $1 AND id <> $2")
            .bind(&token)
            .bind(d.id)
            .execute(&mut *tx)
            .await?;
        sqlx::query(
            "INSERT INTO study_devices (id, user_id, token, platform, tz_minutes) VALUES ($1, $2, $3, $4, $5) \
             ON CONFLICT (id) DO UPDATE SET user_id = EXCLUDED.user_id, token = EXCLUDED.token, \
               platform = EXCLUDED.platform, tz_minutes = EXCLUDED.tz_minutes, updated_at = now()",
        )
        .bind(d.id)
        .bind(user)
        .bind(&token)
        .bind(&d.platform)
        .bind(tz)
        .execute(&mut *tx)
        .await?;
        tx.commit().await
    }
    .await;
    ack_or(r.map_err(|e| e.to_string()))
}

/// `DELETE /devices/{id}` — no more notifications on this install (sign-out).
pub async fn remove_device(State(state): State<AppState>, UserId(user): UserId, Path(id): Path<String>) -> SseStream {
    let Ok(id) = Uuid::parse_str(&id) else { return sse::ack() };
    let r = sqlx::query("DELETE FROM study_devices WHERE id = $1 AND user_id = $2")
        .bind(id)
        .bind(user)
        .execute(&state.cockpit)
        .await;
    ack_or(r.map(|_| ()).map_err(|e| e.to_string()))
}

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct PlanIn {
    mode: String,
    #[serde(default)]
    exam: Option<String>,
    minutes: i32,
    days: Vec<i16>,
    /// Minute of the day for the reminder; none = no reminder.
    #[serde(default)]
    remind: Option<i32>,
    #[serde(default)]
    tz_minutes: i32,
}

/// The plan's settings, checked. Err = what's wrong.
pub fn check_plan(p: &PlanIn) -> Result<(Option<NaiveDate>, Vec<i16>), String> {
    if !matches!(p.mode.as_str(), "exam" | "pace") {
        return Err("mode must be exam or pace".into());
    }
    if !(5..=240).contains(&p.minutes) {
        return Err("minutes must be 5 to 240".into());
    }
    let mut days: Vec<i16> = p.days.iter().copied().filter(|d| (1..=7).contains(d)).collect();
    days.sort_unstable();
    days.dedup();
    if days.is_empty() {
        return Err("pick at least one day".into());
    }
    if p.remind.is_some_and(|m| !(0..1440).contains(&m)) {
        return Err("remind must be a minute of the day".into());
    }
    let exam = match p.exam.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
        Some(s) => Some(NaiveDate::parse_from_str(s.get(..10).unwrap_or(s), "%Y-%m-%d").map_err(|_| "exam must be YYYY-MM-DD")?),
        None => None,
    };
    if p.mode == "exam" && exam.is_none() {
        return Err("an exam plan needs its date".into());
    }
    Ok((exam, days))
}

/// `POST /studios/{id}/plan` — the studio's study plan as the phone keeps
/// it, so reminders come on its days at its time.
pub async fn put_plan(
    State(state): State<AppState>,
    UserId(user): UserId,
    Path(id): Path<String>,
    Json(p): Json<PlanIn>,
) -> SseStream {
    let Some(studio) = owned_studio(&state.cockpit, &id, user).await else {
        return ack_or(Err(format!("Studio {id} not found")));
    };
    let (exam, days) = match check_plan(&p) {
        Ok(x) => x,
        Err(e) => return ack_or(Err(e)),
    };
    let r = sqlx::query(
        "INSERT INTO study_plans (studio_id, user_id, mode, exam, minutes, days, remind_minute, tz_minutes) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8) \
         ON CONFLICT (studio_id) DO UPDATE SET mode = EXCLUDED.mode, exam = EXCLUDED.exam, minutes = EXCLUDED.minutes, \
           days = EXCLUDED.days, remind_minute = EXCLUDED.remind_minute, tz_minutes = EXCLUDED.tz_minutes, updated_at = now()",
    )
    .bind(studio)
    .bind(user)
    .bind(&p.mode)
    .bind(exam)
    .bind(p.minutes)
    .bind(&days)
    .bind(p.remind)
    .bind(p.tz_minutes.clamp(-720, 840))
    .execute(&state.cockpit)
    .await;
    ack_or(r.map(|_| ()).map_err(|e| e.to_string()))
}

// --- When to remind (pure) ------------------------------------------------------------

/// Local wall-clock time for a UTC offset in minutes.
pub fn local(now: DateTime<Utc>, tz: i32) -> NaiveDateTime {
    now.naive_utc() + Span::minutes(tz as i64)
}

/// The UTC instant of local midnight starting `day`.
pub fn day_start_utc(day: NaiveDate, tz: i32) -> DateTime<Utc> {
    (day.and_hms_opt(0, 0, 0).unwrap() - Span::minutes(tz as i64)).and_utc()
}

/// True within the window after `at` (minutes of the local day).
pub fn in_window(local: NaiveDateTime, at: i32) -> bool {
    let m = (local.hour() * 60 + local.minute()) as i32;
    m >= at && m < at + WINDOW_MIN
}

#[derive(Debug, Clone)]
pub struct Plan {
    pub studio: Uuid,
    pub user: Uuid,
    pub title: String,
    pub mode: String,
    pub exam: Option<NaiveDate>,
    pub minutes: i32,
    pub days: Vec<i16>,
    pub remind: i32,
    pub tz: i32,
}

/// The local day a plan reminder is owed for now, if one is: a study day,
/// within the window after its time, and (for an exam plan) the exam not
/// passed.
pub fn plan_due(p: &Plan, now: DateTime<Utc>) -> Option<NaiveDate> {
    let l = local(now, p.tz);
    let day = l.date();
    let weekday = day.weekday().number_from_monday() as i16;
    if !p.days.contains(&weekday) || !in_window(l, p.remind) {
        return None;
    }
    if p.mode == "exam" && p.exam.is_some_and(|e| e < day) {
        return None;
    }
    Some(day)
}

/// The plan reminder's text: (title, body).
pub fn plan_text(p: &Plan, day: NaiveDate, due_cards: i64) -> (String, String) {
    let cards = if due_cards > 0 { format!(" {} due.", plural(due_cards, "card", "cards")) } else { String::new() };
    let body = match (p.mode.as_str(), p.exam) {
        ("exam", Some(exam)) => {
            let left = (exam - day).num_days();
            if left == 0 {
                format!("Exam day — good luck! A short look over your cards helps.{cards}")
            } else {
                format!("{} to your exam. Today's {} minutes are ready.{cards}", plural(left, "day", "days"), p.minutes)
            }
        }
        _ => format!("Your {}-minute session is ready.{cards}", p.minutes),
    };
    (p.title.clone(), body)
}

// --- The worker -----------------------------------------------------------------------

/// Plan reminders owed now: one a day per person (the studio whose exam is
/// nearest first), not for a studio they've already studied today.
async fn schedule_plans(state: &AppState, now: DateTime<Utc>) -> sqlx::Result<usize> {
    let rows = sqlx::query(
        "SELECT p.studio_id, p.user_id, s.title, p.mode, p.exam, p.minutes, p.days, p.remind_minute, p.tz_minutes \
         FROM study_plans p JOIN studios s ON s.id = p.studio_id \
         WHERE p.remind_minute IS NOT NULL AND EXISTS (SELECT 1 FROM study_devices d WHERE d.user_id = p.user_id) \
         ORDER BY p.user_id, p.exam NULLS LAST, p.updated_at",
    )
    .fetch_all(&state.cockpit)
    .await?;
    let mut queued = 0;
    for r in rows {
        let plan = Plan {
            studio: r.get("studio_id"),
            user: r.get("user_id"),
            title: r.get("title"),
            mode: r.get("mode"),
            exam: r.get("exam"),
            minutes: r.get("minutes"),
            days: r.get("days"),
            remind: r.get("remind_minute"),
            tz: r.get("tz_minutes"),
        };
        let Some(day) = plan_due(&plan, now) else { continue };
        let since = day_start_utc(day, plan.tz);
        let studied: bool = sqlx::query_scalar(
            "SELECT EXISTS (SELECT 1 FROM study_events WHERE user_id = $1 AND studio_id = $2 AND at >= $3)",
        )
        .bind(plan.user)
        .bind(plan.studio)
        .bind(since)
        .fetch_one(&state.cockpit)
        .await?;
        if studied {
            continue;
        }
        let due: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM flashcard_schedule WHERE user_id = $1 AND studio_id = $2 AND due_at <= $3",
        )
        .bind(plan.user)
        .bind(plan.studio)
        .bind(now)
        .fetch_one(&state.cockpit)
        .await?;
        let (title, body) = plan_text(&plan, day, due);
        let key = format!("plan:{}:{day}", plan.user);
        let link = format!("/study/{}/study-plan", plan.studio);
        if enqueue(&state.cockpit, plan.user, "plan", &key, &title, &body, &link, Some(plan.studio)).await? {
            queued += 1;
        }
    }
    Ok(queued)
}

/// The evening cards reminder: for people who studied in the last two
/// weeks but not today, with at least 5 cards due and no plan reminder
/// today. Uses the timezone of their most recently seen phone.
async fn schedule_due(state: &AppState, now: DateTime<Utc>) -> sqlx::Result<usize> {
    let rows = sqlx::query(
        "SELECT DISTINCT ON (user_id) user_id, tz_minutes FROM study_devices ORDER BY user_id, updated_at DESC",
    )
    .fetch_all(&state.cockpit)
    .await?;
    let mut queued = 0;
    for r in rows {
        let (user, tz): (Uuid, i32) = (r.get("user_id"), r.get("tz_minutes"));
        let l = local(now, tz);
        if !in_window(l, DUE_AT) {
            continue;
        }
        let day = l.date();
        let since = day_start_utc(day, tz);
        let skip: bool = sqlx::query_scalar(
            "SELECT EXISTS (SELECT 1 FROM study_notifications WHERE dedupe_key = $2) \
                 OR EXISTS (SELECT 1 FROM study_events WHERE user_id = $1 AND at >= $3) \
                 OR NOT EXISTS (SELECT 1 FROM study_events WHERE user_id = $1 AND at >= $3 - interval '14 days')",
        )
        .bind(user)
        .bind(format!("plan:{user}:{day}"))
        .bind(since)
        .fetch_one(&state.cockpit)
        .await?;
        if skip {
            continue;
        }
        let per_studio = sqlx::query(
            "SELECT f.studio_id, s.title, count(*) AS n FROM flashcard_schedule f JOIN studios s ON s.id = f.studio_id \
             WHERE f.user_id = $1 AND f.due_at <= $2 GROUP BY 1, 2 ORDER BY 3 DESC",
        )
        .bind(user)
        .bind(now)
        .fetch_all(&state.cockpit)
        .await?;
        let total: i64 = per_studio.iter().map(|r| r.get::<i64, _>("n")).sum();
        let Some(top) = per_studio.first().filter(|_| total >= DUE_MIN) else { continue };
        let (studio, name): (Uuid, String) = (top.get("studio_id"), top.get("title"));
        let more = per_studio.len() - 1;
        let body = if more == 0 {
            format!("{} due in {name}. Five minutes keeps them fresh.", plural(total, "card is", "cards are"))
        } else {
            format!("{} due in {name} and {}. Five minutes keeps them fresh.", plural(total, "card is", "cards are"), plural(more as i64, "more studio", "more studios"))
        };
        let key = format!("due:{user}:{day}");
        let link = format!("/study/{studio}/flashcards");
        if enqueue(&state.cockpit, user, "due", &key, "Cards to review", &body, &link, Some(studio)).await? {
            queued += 1;
        }
    }
    Ok(queued)
}

/// Sends what is due. Each row is leased first (attempts + 1, next try
/// pushed back), so two workers never send the same one.
async fn send_pending(state: &AppState) -> sqlx::Result<usize> {
    let rows = sqlx::query(
        "UPDATE study_notifications SET attempts = attempts + 1, \
           due_at = now() + make_interval(mins => 2 * (attempts + 1) * (attempts + 1)) \
         WHERE id IN (SELECT id FROM study_notifications WHERE sent_at IS NULL AND due_at <= now() \
                      AND attempts < $1 ORDER BY due_at LIMIT 20 FOR UPDATE SKIP LOCKED) \
         RETURNING id, user_id, kind, title, body, data, created_at",
    )
    .bind(MAX_ATTEMPTS)
    .fetch_all(&state.cockpit)
    .await?;
    let mut sent = 0;
    for r in rows {
        let id: Uuid = r.get("id");
        let user: Uuid = r.get("user_id");
        let created: DateTime<Utc> = r.get("created_at");
        let finish = |error: Option<String>| {
            sqlx::query("UPDATE study_notifications SET sent_at = now(), error = $2 WHERE id = $1")
                .bind(id)
                .bind(error)
                .execute(&state.cockpit)
        };
        if Utc::now() - created > Span::hours(6) {
            finish(Some("expired".into())).await?;
            continue;
        }
        let devices: Vec<(Uuid, String)> = sqlx::query_as("SELECT id, token FROM study_devices WHERE user_id = $1")
            .bind(user)
            .fetch_all(&state.cockpit)
            .await?;
        if devices.is_empty() {
            finish(Some("no device".into())).await?;
            continue;
        }
        let data: BTreeMap<String, String> = r
            .get::<Value, _>("data")
            .as_object()
            .map(|m| m.iter().map(|(k, v)| (k.clone(), v.as_str().map(str::to_string).unwrap_or_else(|| v.to_string()))).collect())
            .unwrap_or_default();
        let notice = Notice { title: r.get("title"), body: r.get("body"), data, ..Default::default() };
        let mut delivered = 0;
        let mut last_error = None;
        for (device, token) in devices {
            match state.pusher.send(&token, &notice).await {
                Ok(()) => delivered += 1,
                Err(PushError::Unregistered) => {
                    sqlx::query("DELETE FROM study_devices WHERE id = $1 AND token = $2")
                        .bind(device)
                        .bind(&token)
                        .execute(&state.cockpit)
                        .await?;
                    last_error = Some("unregistered".to_string());
                }
                Err(PushError::Other(e)) => {
                    tracing::warn!(notification = %id, %device, "push: {e}");
                    last_error = Some(shorten(&e, 300));
                }
            }
        }
        if delivered > 0 {
            finish(None).await?;
            sent += 1;
        } else if last_error.as_deref() == Some("unregistered") {
            finish(last_error).await?;
        } else {
            // Left for another try (already pushed back by the lease).
            sqlx::query("UPDATE study_notifications SET error = $2 WHERE id = $1")
                .bind(id)
                .bind(last_error)
                .execute(&state.cockpit)
                .await?;
        }
    }
    Ok(sent)
}

/// Schedules reminders every minute and sends what is due (or at once when
/// a build queues one).
pub fn spawn(state: &AppState) {
    if !state.pusher.enabled() {
        tracing::warn!("NOTIFY_WORKER on but FCM_SERVICE_ACCOUNT_FILE not set — no notifications");
        return;
    }
    let s = state.clone();
    tokio::spawn(async move {
        let mut last_schedule = None::<i64>;
        loop {
            let now = Utc::now();
            let minute = now.timestamp() / 60;
            if last_schedule != Some(minute) {
                last_schedule = Some(minute);
                match schedule_plans(&s, now).await {
                    Ok(n) if n > 0 => tracing::info!(queued = n, "plan reminders"),
                    Ok(_) => {}
                    Err(e) => tracing::warn!("plan reminders: {e}"),
                }
                match schedule_due(&s, now).await {
                    Ok(n) if n > 0 => tracing::info!(queued = n, "cards reminders"),
                    Ok(_) => {}
                    Err(e) => tracing::warn!("cards reminders: {e}"),
                }
            }
            match send_pending(&s).await {
                Ok(n) if n > 0 => tracing::info!(sent = n, "notifications"),
                Ok(_) => {}
                Err(e) => tracing::warn!("notifications: {e}"),
            }
            let _ = tokio::time::timeout(Duration::from_secs(20), s.notices.notified()).await;
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(s: &str) -> DateTime<Utc> {
        DateTime::parse_from_rfc3339(s).unwrap().with_timezone(&Utc)
    }

    fn plan(mode: &str, exam: Option<&str>) -> Plan {
        Plan {
            studio: Uuid::nil(),
            user: Uuid::nil(),
            title: "Networks".into(),
            mode: mode.into(),
            exam: exam.map(|e| NaiveDate::parse_from_str(e, "%Y-%m-%d").unwrap()),
            minutes: 30,
            days: vec![1, 3, 5],
            remind: 19 * 60,
            tz: 390, // Yangon, UTC+6:30
        }
    }

    #[test]
    fn reminds_on_plan_days_in_the_window_local_time() {
        let p = plan("pace", None);
        // Wed 2026-10-07 19:10 in Yangon = 12:40 UTC
        assert_eq!(plan_due(&p, at("2026-10-07T12:40:00Z")), NaiveDate::from_ymd_opt(2026, 10, 7));
        // 18:50 local: too early
        assert_eq!(plan_due(&p, at("2026-10-07T12:20:00Z")), None);
        // 22:10 local: past the window
        assert_eq!(plan_due(&p, at("2026-10-07T15:40:00Z")), None);
        // Thursday is not a study day
        assert_eq!(plan_due(&p, at("2026-10-08T12:40:00Z")), None);
        // Late evening UTC is already the next local day
        let mut early = plan("pace", None);
        early.remind = 7 * 60;
        early.days = vec![4];
        assert_eq!(plan_due(&early, at("2026-10-08T00:40:00Z")), NaiveDate::from_ymd_opt(2026, 10, 8));
    }

    #[test]
    fn no_reminders_after_the_exam() {
        let p = plan("exam", Some("2026-10-06"));
        assert_eq!(plan_due(&p, at("2026-10-07T12:40:00Z")), None);
        let p = plan("exam", Some("2026-10-07"));
        assert!(plan_due(&p, at("2026-10-07T12:40:00Z")).is_some());
    }

    #[test]
    fn texts() {
        let d = NaiveDate::from_ymd_opt(2026, 10, 7).unwrap();
        assert_eq!(plan_text(&plan("pace", None), d, 0).1, "Your 30-minute session is ready.");
        assert_eq!(
            plan_text(&plan("exam", Some("2026-10-12")), d, 1).1,
            "5 days to your exam. Today's 30 minutes are ready. 1 card due."
        );
        assert_eq!(plan_text(&plan("exam", Some("2026-10-08")), d, 12).1, "1 day to your exam. Today's 30 minutes are ready. 12 cards due.");
        assert!(plan_text(&plan("exam", Some("2026-10-07")), d, 0).1.starts_with("Exam day"));
    }

    #[test]
    fn local_midnight_in_utc() {
        let d = NaiveDate::from_ymd_opt(2026, 10, 7).unwrap();
        assert_eq!(day_start_utc(d, 390), at("2026-10-06T17:30:00Z"));
        assert_eq!(day_start_utc(d, -300), at("2026-10-07T05:00:00Z"));
    }

    #[test]
    fn plan_settings_are_checked() {
        let ok = |j: Value| check_plan(&serde_json::from_value::<PlanIn>(j).unwrap());
        let (exam, days) = ok(json!({"mode":"exam","exam":"2026-11-01","minutes":30,"days":[5,1,1,9],"remind":1140,"tzMinutes":390})).unwrap();
        assert_eq!(exam, NaiveDate::from_ymd_opt(2026, 11, 1));
        assert_eq!(days, vec![1, 5]);
        assert!(ok(json!({"mode":"exam","minutes":30,"days":[1]})).is_err());
        assert!(ok(json!({"mode":"pace","minutes":30,"days":[]})).is_err());
        assert!(ok(json!({"mode":"pace","minutes":30,"days":[2],"remind":1440})).is_err());
        assert!(ok(json!({"mode":"pace","minutes":1,"days":[2]})).is_err());
        assert!(ok(json!({"mode":"pace","minutes":30,"days":[2],"remind":null})).is_ok());
        assert!(ok(json!({"mode":"exam","exam":"2026-11-01T00:00:00.000","minutes":30,"days":[2]})).is_ok());
    }

    #[test]
    fn long_text_is_cut() {
        assert_eq!(shorten(" hi ", 10), "hi");
        assert_eq!(shorten(&"x".repeat(50), 10).chars().count(), 10);
    }
}

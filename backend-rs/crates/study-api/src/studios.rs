//! Reading studios: the user's own, with their topics (mastery and card
//! schedules overlaid per user, related topics linked both ways), scenarios
//! and source files. A port of the read side of `routers/stream.py`.

use std::collections::HashMap;

use axum::extract::{Path, State};
use axum::Json;
use chrono::{DateTime, Utc};
use octo_common::error::ApiError;
use serde_json::Value;
use sqlx::{PgPool, Row};
use uuid::Uuid;

use crate::dto::{self, Me, Scenario, SourceFile, Studio, Topic};
use crate::identity::UserId;
use crate::schedule::{status, CardState};
use crate::sse::{self, SseStream};
use crate::AppState;

/// topic id → the ids of topics it relates to, both ways, from the titles
/// each payload names in `relatesTo`.
pub fn related_ids(payloads: &[Value]) -> HashMap<String, Vec<String>> {
    let id = |p: &Value| p.get("id").and_then(Value::as_str).map(str::to_string);
    let by_title: HashMap<String, String> = payloads
        .iter()
        .filter_map(|p| {
            let t = p.get("title")?.as_str()?.trim().to_lowercase();
            Some((t, id(p)?))
        })
        .collect();
    let mut out: HashMap<String, Vec<String>> = HashMap::new();
    let mut link = |a: &str, b: &str| {
        if a.is_empty() || b.is_empty() || a == b {
            return;
        }
        let list = out.entry(a.to_string()).or_default();
        if !list.iter().any(|x| x == b) {
            list.push(b.to_string());
        }
    };
    for p in payloads {
        let Some(me) = id(p) else { continue };
        for title in p.get("relatesTo").and_then(Value::as_array).into_iter().flatten() {
            let Some(t) = title.as_str() else { continue };
            if let Some(other) = by_title.get(&t.trim().to_lowercase()) {
                link(&me, other);
                link(other, &me);
            }
        }
    }
    out
}

/// The studio's topics in order, with this user's mastery, card schedules
/// and related topics.
pub async fn load_topics(db: &PgPool, studio: Uuid, user: Uuid) -> Result<Vec<Topic>, ApiError> {
    let payloads: Vec<Value> = sqlx::query_scalar(
        "SELECT payload FROM generated_topics WHERE studio_id = $1 ORDER BY ordinal",
    )
    .bind(studio)
    .fetch_all(db)
    .await?;

    let mastery: HashMap<String, f64> = sqlx::query(
        "SELECT topic_id, mastery FROM topic_progress WHERE user_id = $1 AND studio_id = $2",
    )
    .bind(user)
    .bind(studio)
    .fetch_all(db)
    .await
    .map(|rows| rows.iter().map(|r| (r.get::<String, _>(0), r.get::<f64, _>(1))).collect())
    .unwrap_or_default();

    let cards: HashMap<String, (CardState, Option<DateTime<Utc>>)> = sqlx::query(
        "SELECT card_id, reps, interval_days, ease, lapses, due_at FROM flashcard_schedule \
         WHERE user_id = $1 AND studio_id = $2",
    )
    .bind(user)
    .bind(studio)
    .fetch_all(db)
    .await
    .map(|rows| {
        rows.iter()
            .map(|r| {
                let s = CardState {
                    reps: r.get("reps"),
                    interval_days: r.get("interval_days"),
                    ease: r.get("ease"),
                    lapses: r.get("lapses"),
                };
                (r.get::<String, _>("card_id"), (s, r.get("due_at")))
            })
            .collect()
    })
    .unwrap_or_default();

    let related = related_ids(&payloads);
    let mut out = Vec::with_capacity(payloads.len());
    for payload in payloads {
        // A payload that doesn't read is skipped, not fatal for the studio.
        let Ok(mut t) = serde_json::from_value::<Topic>(payload) else { continue };
        if let Some(r) = related.get(&t.id) {
            t.related_topic_ids = r.clone();
        }
        if let Some(m) = mastery.get(&t.id) {
            t.mastery = *m;
        }
        for c in &mut t.flashcards {
            if let Some((s, due)) = cards.get(&c.id) {
                c.reps = s.reps;
                c.interval_days = s.interval_days;
                c.ease = s.ease;
                c.lapses = s.lapses;
                c.due_date = *due;
                c.status = status(s).to_string();
            }
        }
        out.push(t);
    }
    Ok(out)
}

pub async fn load_scenarios(db: &PgPool, studio: Uuid) -> Vec<Scenario> {
    let payloads: Vec<Value> = sqlx::query_scalar(
        "SELECT payload FROM generated_scenarios WHERE studio_id = $1 ORDER BY ordinal",
    )
    .bind(studio)
    .fetch_all(db)
    .await
    .unwrap_or_default();
    payloads.into_iter().filter_map(|p| serde_json::from_value(p).ok()).collect()
}

pub async fn load_files(db: &PgPool, studio: Uuid, user: Uuid) -> Vec<SourceFile> {
    sqlx::query(
        "SELECT id, filename, mime, status FROM documents \
         WHERE studio_id = $1 AND user_id = $2 ORDER BY created_at",
    )
    .bind(studio)
    .bind(user)
    .fetch_all(db)
    .await
    .map(|rows| {
        rows.iter()
            .map(|r| {
                let name: String = r.get("filename");
                let mime: String = r.get("mime");
                SourceFile {
                    id: r.get::<Uuid, _>("id").to_string(),
                    kind: dto::file_type(&name, &mime).to_string(),
                    processed: r.get::<String, _>("status") == "ready",
                    name,
                }
            })
            .collect()
    })
    .unwrap_or_default()
}

/// A studio the user owns, in full; None if it isn't theirs.
pub async fn load_studio(db: &PgPool, studio: Uuid, user: Uuid) -> Result<Option<Studio>, ApiError> {
    let row = sqlx::query(
        "SELECT id, title, subject, created_at, updated_at FROM studios \
         WHERE id = $1 AND user_id = $2",
    )
    .bind(studio)
    .bind(user)
    .fetch_optional(db)
    .await?;
    let Some(r) = row else { return Ok(None) };
    Ok(Some(Studio {
        id: r.get::<Uuid, _>("id").to_string(),
        title: r.get("title"),
        subject: r.get::<Option<String>, _>("subject").unwrap_or_default(),
        created_at: r.get("created_at"),
        updated_at: r.get("updated_at"),
        last_studied: None,
        source_files: load_files(db, studio, user).await,
        topics: load_topics(db, studio, user).await?,
        scenarios: load_scenarios(db, studio).await,
    }))
}

/// `GET /studios` — the user's studios, newest first, one `item` each.
pub async fn list(State(state): State<AppState>, UserId(user): UserId) -> Result<SseStream, ApiError> {
    let ids: Vec<Uuid> = sqlx::query_scalar(
        "SELECT id FROM studios WHERE user_id = $1 ORDER BY created_at DESC",
    )
    .bind(user)
    .fetch_all(&state.cockpit)
    .await?;
    let mut events = Vec::with_capacity(ids.len() + 1);
    for id in ids {
        if let Some(s) = load_studio(&state.cockpit, id, user).await? {
            events.push(sse::event("item", &s));
        }
    }
    events.push(sse::done());
    Ok(sse::events(events))
}

/// `GET /studios/{id}` — one owned studio.
pub async fn get(
    State(state): State<AppState>,
    UserId(user): UserId,
    Path(id): Path<String>,
) -> SseStream {
    let Ok(sid) = Uuid::parse_str(&id) else {
        return sse::events(vec![sse::error(format!("Studio {id} not found"))]);
    };
    match load_studio(&state.cockpit, sid, user).await {
        Ok(Some(s)) => sse::one(&s),
        Ok(None) => sse::events(vec![sse::error(format!("Studio {id} not found"))]),
        Err(e) => sse::events(vec![sse::error(e.message)]),
    }
}

fn clip(s: &str, n: usize) -> String {
    s.chars().take(n).collect()
}

/// `POST /studios` `{title, subject}` — a new empty studio (`data`).
pub async fn create(State(state): State<AppState>, UserId(user): UserId, Json(body): Json<Value>) -> SseStream {
    let field = |k: &str| body.get(k).and_then(Value::as_str).map(str::trim).filter(|s| !s.is_empty());
    let title = clip(field("title").unwrap_or("Untitled Studio"), 200);
    let subject = field("subject").map(|s| clip(s, 120));
    let id = Uuid::new_v4();
    let r = sqlx::query("INSERT INTO studios (id, user_id, title, subject) VALUES ($1, $2, $3, $4)")
        .bind(id)
        .bind(user)
        .bind(&title)
        .bind(&subject)
        .execute(&state.cockpit)
        .await;
    if let Err(e) = r {
        return sse::events(vec![sse::error(format!("Could not create studio: {e}"))]);
    }
    match load_studio(&state.cockpit, id, user).await {
        Ok(Some(s)) => sse::one(&s),
        Ok(None) => sse::events(vec![sse::error("Could not create studio")]),
        Err(e) => sse::events(vec![sse::error(format!("Could not create studio: {}", e.message))]),
    }
}

/// `DELETE /studios/{id}` — the studio and everything in it: its rows
/// (cascade), its passages (vector DB, no cross-database key) and its files.
pub async fn delete(State(state): State<AppState>, UserId(user): UserId, Path(id): Path<String>) -> SseStream {
    let not_found = || sse::events(vec![sse::error(format!("Studio {id} not found"))]);
    let Ok(sid) = Uuid::parse_str(&id) else { return not_found() };
    let keys: Vec<String> = match sqlx::query_scalar(
        "SELECT d.object_key FROM documents d JOIN studios s ON s.id = d.studio_id WHERE s.id = $1 AND s.user_id = $2",
    )
    .bind(sid)
    .bind(user)
    .fetch_all(&state.cockpit)
    .await
    {
        Ok(k) => k,
        Err(e) => return sse::events(vec![sse::error(format!("Could not delete studio: {e}"))]),
    };
    let gone = sqlx::query("DELETE FROM studios WHERE id = $1 AND user_id = $2")
        .bind(sid)
        .bind(user)
        .execute(&state.cockpit)
        .await;
    match gone {
        Ok(r) if r.rows_affected() == 0 => return not_found(),
        Err(e) => return sse::events(vec![sse::error(format!("Could not delete studio: {e}"))]),
        Ok(_) => {}
    }
    // Clean-up is best effort; the studio is already gone for the user.
    if let Err(e) = sqlx::query("DELETE FROM chunks WHERE studio_id = $1 AND user_id = $2")
        .bind(sid)
        .bind(user)
        .execute(&state.vector)
        .await
    {
        tracing::warn!(studio = %sid, "delete chunks: {e}");
    }
    if let Some(store) = &state.store {
        for k in keys {
            if let Err(e) = store.delete(&k).await {
                tracing::warn!(studio = %sid, "delete object: {e}");
            }
        }
    }
    sse::one(&serde_json::json!({ "id": id, "deleted": true }))
}

/// `GET /me` — id, email and OctoCredits balance.
pub async fn me(State(state): State<AppState>, UserId(user): UserId) -> SseStream {
    let mut me = Me { id: user.to_string(), email: None, credits: None };
    if let Some(shared) = &state.shared {
        if let Ok(Some(r)) = sqlx::query("SELECT email, octo_credits FROM users WHERE id = $1")
            .bind(user)
            .fetch_optional(shared)
            .await
        {
            me.email = r.try_get("email").ok();
            me.credits = r.try_get("octo_credits").ok();
        }
    }
    sse::one(&me)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn related_both_ways_by_title() {
        let p = vec![
            json!({"id": "a", "title": "TCP", "relatesTo": ["udp", "missing", "TCP"]}),
            json!({"id": "b", "title": "UDP"}),
            json!({"id": "c", "title": "DNS", "relatesTo": ["UDP"]}),
        ];
        let r = related_ids(&p);
        assert_eq!(r["a"], vec!["b"]);
        assert_eq!(r["b"], vec!["a", "c"]);
        assert_eq!(r["c"], vec!["b"]);
    }
}

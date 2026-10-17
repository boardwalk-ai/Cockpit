//! Share links: an owner turns on a link for a studio; anyone signed in who
//! opens it can add their own copy. A copy is a new studio of theirs — the
//! lessons, cards, quizzes, scenarios, concept maps and the passages Ask AI
//! searches (vectors copied, no AI call) — with fresh progress. The uploaded
//! files are not copied (their names stay as sources). Turning the link off
//! stops new copies; copies already made stay with their owners.
//!
//! - `GET    /studios/{id}/share`      the link (or `code: null`)
//! - `POST   /studios/{id}/share`      turn it on (same link if it is on)
//! - `DELETE /studios/{id}/share`      turn it off
//! - `GET    /shares/{code}`           what the link holds (title, counts, who)
//! - `POST   /shares/{code}/copy`      add a copy (`Idempotency-Key`)

use std::collections::HashMap;

use axum::extract::{Path, State};
use axum::http::HeaderMap;
use serde_json::{json, Value};
use sqlx::{PgPool, Row};
use uuid::Uuid;

use crate::identity::UserId;
use crate::progress::owned_studio;
use crate::sse::{self, SseStream};
use crate::studios::{idempotency_key, load_studio};
use crate::AppState;

/// `studio_shares`, plus where a copy came from on `studios`.
pub async fn ensure_schema(cockpit: &PgPool) -> sqlx::Result<()> {
    for q in [
        "CREATE TABLE IF NOT EXISTS studio_shares (code text PRIMARY KEY, \
         studio_id uuid NOT NULL REFERENCES studios(id) ON DELETE CASCADE, owner_id uuid NOT NULL, \
         created_at timestamptz NOT NULL DEFAULT now(), revoked_at timestamptz, copies integer NOT NULL DEFAULT 0)",
        "CREATE UNIQUE INDEX IF NOT EXISTS ux_studio_shares_live ON studio_shares (studio_id) WHERE revoked_at IS NULL",
        "ALTER TABLE studios ADD COLUMN IF NOT EXISTS copied_from uuid, ADD COLUMN IF NOT EXISTS shared_by text",
    ] {
        sqlx::query(q).execute(cockpit).await?;
    }
    Ok(())
}

/// 10 letters/digits: 62^10 ≈ 8×10^17, not guessable.
fn new_code() -> String {
    const ABC: &[u8] = b"abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    let b = *Uuid::new_v4().as_bytes();
    let mut n = u128::from_be_bytes(b);
    (0..10)
        .map(|_| {
            let c = ABC[(n % ABC.len() as u128) as usize] as char;
            n /= ABC.len() as u128;
            c
        })
        .collect()
}

fn short_hex(n: usize) -> String {
    Uuid::new_v4().simple().to_string()[..n].to_string()
}

/// Lessons with every id made new, so the copy's progress (keyed by user +
/// topic / card id) never touches the original's. Concept ids carry their
/// lesson's id as a prefix; links between lessons go by title and stay.
pub fn remap_topics(payloads: &[Value], studio: &str) -> Vec<Value> {
    let ids: HashMap<String, String> = payloads
        .iter()
        .filter_map(|p| p.get("id").and_then(Value::as_str))
        .map(|old| (old.to_string(), format!("gen_{}", short_hex(10))))
        .collect();
    fn walk(v: &mut Value, ids: &HashMap<String, String>) {
        match v {
            Value::String(s) => {
                if let Some(n) = ids.get(s.as_str()) {
                    *s = n.clone();
                } else if let Some((old, new)) = ids.iter().find(|(o, _)| s.starts_with(&format!("{o}_"))) {
                    *s = format!("{new}{}", &s[old.len()..]);
                }
            }
            Value::Array(a) => a.iter_mut().for_each(|x| walk(x, ids)),
            Value::Object(m) => m.values_mut().for_each(|x| walk(x, ids)),
            _ => {}
        }
    }
    payloads
        .iter()
        .map(|p| {
            let mut p = p.clone();
            for (key, prefix) in [("flashcards", "fc"), ("quizQuestions", "q")] {
                for item in p.get_mut(key).and_then(Value::as_array_mut).into_iter().flatten() {
                    item["id"] = json!(format!("{prefix}_{}", short_hex(8)));
                }
            }
            walk(&mut p, &ids);
            p["studioId"] = json!(studio);
            p["mastery"] = json!(0.0);
            p
        })
        .collect()
}

fn link(state: &AppState, code: &str) -> String {
    format!("{}{code}", state.config.share_base_url)
}

async fn live_share(db: &PgPool, studio: Uuid) -> sqlx::Result<Option<(String, i32)>> {
    Ok(sqlx::query("SELECT code, copies FROM studio_shares WHERE studio_id = $1 AND revoked_at IS NULL")
        .bind(studio)
        .fetch_optional(db)
        .await?
        .map(|r| (r.get("code"), r.get("copies"))))
}

fn share_data(state: &AppState, s: Option<(String, i32)>) -> Value {
    match s {
        Some((code, copies)) => json!({ "code": code, "url": link(state, &code), "copies": copies }),
        None => json!({ "code": null, "url": null, "copies": 0 }),
    }
}

pub async fn get_share(State(state): State<AppState>, UserId(user): UserId, Path(id): Path<String>) -> SseStream {
    let Some(sid) = owned_studio(&state.cockpit, &id, user).await else {
        return sse::events(vec![sse::error("Studio not found")]);
    };
    match live_share(&state.cockpit, sid).await {
        Ok(s) => sse::one(&share_data(&state, s)),
        Err(e) => sse::events(vec![sse::error(e.to_string())]),
    }
}

pub async fn start(
    State(state): State<AppState>,
    UserId(user): UserId,
    who: octo_common::AuthedUser,
    Path(id): Path<String>,
) -> SseStream {
    if let Some(access) = &state.access {
        if !access.flag(&who, "study_share").await {
            return sse::events(vec![sse::error_data(&json!({
                "message": "Sharing is switched off for now.", "code": "feature_off", "feature": "study_share"
            }))]);
        }
    }
    let Some(sid) = owned_studio(&state.cockpit, &id, user).await else {
        return sse::events(vec![sse::error("Studio not found")]);
    };
    // The unique index on live links makes a double tap end on one link.
    let _ = sqlx::query(
        "INSERT INTO studio_shares (code, studio_id, owner_id) VALUES ($1, $2, $3) \
         ON CONFLICT (studio_id) WHERE revoked_at IS NULL DO NOTHING",
    )
    .bind(new_code())
    .bind(sid)
    .bind(user)
    .execute(&state.cockpit)
    .await;
    match live_share(&state.cockpit, sid).await {
        Ok(s @ Some(_)) => sse::one(&share_data(&state, s)),
        Ok(None) => sse::events(vec![sse::error("Couldn't make the link. Try again.")]),
        Err(e) => sse::events(vec![sse::error(e.to_string())]),
    }
}

pub async fn stop(State(state): State<AppState>, UserId(user): UserId, Path(id): Path<String>) -> SseStream {
    let Some(sid) = owned_studio(&state.cockpit, &id, user).await else {
        return sse::events(vec![sse::error("Studio not found")]);
    };
    match sqlx::query("UPDATE studio_shares SET revoked_at = now() WHERE studio_id = $1 AND revoked_at IS NULL")
        .bind(sid)
        .execute(&state.cockpit)
        .await
    {
        Ok(_) => sse::ack(),
        Err(e) => sse::events(vec![sse::error(e.to_string())]),
    }
}

/// The live share behind a code: (studio, owner).
async fn resolve(db: &PgPool, code: &str) -> Result<(Uuid, Uuid), &'static str> {
    let r = sqlx::query("SELECT studio_id, owner_id, revoked_at IS NOT NULL AS off FROM studio_shares WHERE code = $1")
        .bind(code)
        .fetch_optional(db)
        .await
        .map_err(|_| "Couldn't open the link. Try again.")?
        .ok_or("This link doesn't exist.")?;
    if r.get::<bool, _>("off") {
        return Err("This link was turned off by its owner.");
    }
    Ok((r.get("studio_id"), r.get("owner_id")))
}

/// The sharer's name and photo, for "Shared by …".
async fn sharer(state: &AppState, owner: Uuid) -> (Option<String>, Option<String>) {
    let Some(pool) = &state.shared else { return (None, None) };
    let Ok(Some(r)) = sqlx::query("SELECT name, email, photo_url FROM users WHERE id = $1").bind(owner).fetch_optional(pool).await
    else {
        return (None, None);
    };
    let some = |s: Option<String>| s.map(|s| s.trim().to_string()).filter(|s| !s.is_empty());
    let name = some(r.try_get("name").ok().flatten())
        .or_else(|| some(r.try_get("email").ok().flatten()).map(|e| e.split('@').next().unwrap_or("").to_string()));
    let photo = some(r.try_get("photo_url").ok().flatten()).filter(|u| u.starts_with("https://"));
    (name, photo)
}

pub async fn preview(State(state): State<AppState>, UserId(_user): UserId, Path(code): Path<String>) -> SseStream {
    let (sid, owner) = match resolve(&state.cockpit, &code).await {
        Ok(x) => x,
        Err(m) => return sse::events(vec![sse::error(m)]),
    };
    let r = sqlx::query(
        "SELECT s.title, s.subject, \
           (SELECT count(*) FROM generated_topics t WHERE t.studio_id = s.id)::int AS lessons, \
           (SELECT coalesce(sum(jsonb_array_length(coalesce(t.payload->'flashcards', '[]'))), 0) FROM generated_topics t WHERE t.studio_id = s.id)::int AS cards, \
           (SELECT count(*) FROM generated_scenarios c WHERE c.studio_id = s.id)::int AS scenarios \
         FROM studios s WHERE s.id = $1",
    )
    .bind(sid)
    .fetch_optional(&state.cockpit)
    .await;
    let Ok(Some(r)) = r else { return sse::events(vec![sse::error("This link doesn't exist.")]) };
    let (name, photo) = sharer(&state, owner).await;
    sse::one(&json!({
        "code": code,
        "title": r.get::<String, _>("title"),
        "subject": r.get::<Option<String>, _>("subject").unwrap_or_default(),
        "lessons": r.get::<i32, _>("lessons"),
        "cards": r.get::<i32, _>("cards"),
        "scenarios": r.get::<i32, _>("scenarios"),
        "sharedBy": name,
        "sharedByPhoto": photo,
    }))
}

pub async fn copy(
    State(state): State<AppState>,
    UserId(user): UserId,
    Path(code): Path<String>,
    headers: HeaderMap,
) -> SseStream {
    let (src, owner) = match resolve(&state.cockpit, &code).await {
        Ok(x) => x,
        Err(m) => return sse::events(vec![sse::error(m)]),
    };
    let key = idempotency_key(&headers).map(|k| format!("share:{code}:{k}"));
    match copy_studio(&state, src, owner, user, key.as_deref(), &code).await {
        Ok(new) => match load_studio(&state.cockpit, new, user).await {
            Ok(Some(s)) => sse::one(&s),
            _ => sse::events(vec![sse::error("Couldn't add the studio. Try again.")]),
        },
        Err(e) => {
            tracing::warn!(%src, %user, "share copy: {e}");
            sse::events(vec![sse::error("Couldn't add the studio. Try again.")])
        }
    }
}

/// The copy itself. Studio rows in one transaction, then the passages (the
/// vector DB is another database); if those fail the new studio is removed.
/// A retry with the same key returns the first copy, finishing its passages
/// if they never landed.
async fn copy_studio(state: &AppState, src: Uuid, owner: Uuid, user: Uuid, key: Option<&str>, code: &str) -> Result<Uuid, String> {
    let e = |e: sqlx::Error| e.to_string();
    if let Some(k) = key {
        let done: Option<Uuid> = sqlx::query_scalar("SELECT id FROM studios WHERE user_id = $1 AND idempotency_key = $2")
            .bind(user)
            .bind(k)
            .fetch_optional(&state.cockpit)
            .await
            .map_err(e)?;
        if let Some(id) = done {
            copy_passages(state, src, id, user).await?;
            return Ok(id);
        }
    }
    let (shared_by, _) = sharer(state, owner).await;
    let new = Uuid::new_v4();
    let mut tx = state.cockpit.begin().await.map_err(e)?;
    let inserted = sqlx::query(
        "INSERT INTO studios (id, user_id, title, subject, idempotency_key, copied_from, shared_by) \
         SELECT $1, $2, title, subject, $3, id, $4 FROM studios WHERE id = $5 \
         ON CONFLICT (user_id, idempotency_key) WHERE idempotency_key IS NOT NULL DO NOTHING",
    )
    .bind(new)
    .bind(user)
    .bind(key)
    .bind(&shared_by)
    .bind(src)
    .execute(&mut *tx)
    .await
    .map_err(e)?;
    if inserted.rows_affected() == 0 {
        // The same key raced in: the other request owns the copy.
        drop(tx);
        let id: Uuid = sqlx::query_scalar("SELECT id FROM studios WHERE user_id = $1 AND idempotency_key = $2")
            .bind(user)
            .bind(key)
            .fetch_one(&state.cockpit)
            .await
            .map_err(e)?;
        return Ok(id);
    }
    // Files' names (as sources), not the files: no object key.
    sqlx::query(
        "INSERT INTO documents (id, studio_id, user_id, filename, mime, bytes, object_key, status) \
         SELECT nid, $1, $2, filename, mime, bytes, '', 'ready' FROM ( \
           SELECT md5($1::text || id::text)::uuid AS nid, filename, mime, bytes FROM documents \
           WHERE studio_id = $3 AND status = 'ready') d",
    )
    .bind(new)
    .bind(user)
    .bind(src)
    .execute(&mut *tx)
    .await
    .map_err(e)?;
    let rows = sqlx::query("SELECT ordinal, payload FROM generated_topics WHERE studio_id = $1 ORDER BY ordinal")
        .bind(src)
        .fetch_all(&mut *tx)
        .await
        .map_err(e)?;
    let payloads: Vec<Value> = rows.iter().map(|r| r.get("payload")).collect();
    for (r, p) in rows.iter().zip(remap_topics(&payloads, &new.to_string())) {
        sqlx::query("INSERT INTO generated_topics (id, studio_id, user_id, ordinal, payload) VALUES ($1, $2, $3, $4, $5)")
            .bind(Uuid::new_v4())
            .bind(new)
            .bind(user)
            .bind(r.get::<i32, _>("ordinal"))
            .bind(&p)
            .execute(&mut *tx)
            .await
            .map_err(e)?;
    }
    let scenarios = sqlx::query("SELECT ordinal, payload FROM generated_scenarios WHERE studio_id = $1 ORDER BY ordinal")
        .bind(src)
        .fetch_all(&mut *tx)
        .await
        .map_err(e)?;
    for r in scenarios {
        let mut p: Value = r.get("payload");
        p["id"] = json!(format!("scn_{}", short_hex(10)));
        p["studioId"] = json!(new.to_string());
        sqlx::query("INSERT INTO generated_scenarios (id, studio_id, user_id, ordinal, payload) VALUES ($1, $2, $3, $4, $5)")
            .bind(Uuid::new_v4())
            .bind(new)
            .bind(user)
            .bind(r.get::<i32, _>("ordinal"))
            .bind(&p)
            .execute(&mut *tx)
            .await
            .map_err(e)?;
    }
    sqlx::query("UPDATE studio_shares SET copies = copies + 1 WHERE code = $1")
        .bind(code)
        .execute(&mut *tx)
        .await
        .map_err(e)?;
    tx.commit().await.map_err(e)?;

    if let Err(err) = copy_passages(state, src, new, user).await {
        let _ = sqlx::query("DELETE FROM studios WHERE id = $1").bind(new).execute(&state.cockpit).await;
        return Err(err);
    }
    Ok(new)
}

/// The source's passages under the copy (same vectors, new ids), once: the
/// copy's documents are `md5(copy || source doc)`, so the mapping is known
/// again on a retry.
async fn copy_passages(state: &AppState, src: Uuid, new: Uuid, user: Uuid) -> Result<(), String> {
    let have: i64 = sqlx::query_scalar("SELECT count(*) FROM chunks WHERE studio_id = $1")
        .bind(new)
        .fetch_one(&state.vector)
        .await
        .map_err(|e| e.to_string())?;
    if have > 0 {
        return Ok(());
    }
    sqlx::query(
        "INSERT INTO chunks (id, document_id, studio_id, user_id, ordinal, content, embedding, tsv, page, heading) \
         SELECT gen_random_uuid(), md5($2::text || document_id::text)::uuid, $2, $3, ordinal, content, embedding, tsv, page, heading \
         FROM chunks WHERE studio_id = $1",
    )
    .bind(src)
    .bind(new)
    .bind(user)
    .execute(&state.vector)
    .await
    .map_err(|e| e.to_string())?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn codes_are_ten_unambiguous_characters() {
        let a = new_code();
        assert_eq!(a.len(), 10);
        assert!(!a.contains(['0', 'O', 'l', '1', 'I']));
        assert_ne!(a, new_code());
    }

    #[test]
    fn copies_get_new_ids_everywhere() {
        let p = vec![
            json!({"id": "gen_a", "studioId": "old", "mastery": 0.8,
                "flashcards": [{"id": "fc_1", "topicId": "gen_a"}],
                "quizQuestions": [{"id": "q_1", "topicId": "gen_a"}],
                "concepts": [{"id": "gen_a_c0", "name": "X"}],
                "conceptLinks": [{"from": "gen_a_c0", "to": "gen_a_c1", "label": "is"}],
                "relatedTopicIds": ["gen_b"], "relatesTo": ["B title"]}),
            json!({"id": "gen_b", "studioId": "old", "relatedTopicIds": ["gen_a"]}),
        ];
        let out = remap_topics(&p, "new");
        let (a, b) = (&out[0], &out[1]);
        let ta = a["id"].as_str().unwrap();
        let tb = b["id"].as_str().unwrap();
        assert!(ta.starts_with("gen_") && ta != "gen_a" && tb != "gen_b");
        assert_eq!(a["studioId"], "new");
        assert_eq!(a["mastery"], 0.0);
        assert_eq!(a["flashcards"][0]["topicId"], ta);
        assert_ne!(a["flashcards"][0]["id"], "fc_1");
        assert_ne!(a["quizQuestions"][0]["id"], "q_1");
        assert_eq!(a["concepts"][0]["id"], format!("{ta}_c0"));
        assert_eq!(a["conceptLinks"][0]["to"], format!("{ta}_c1"));
        assert_eq!(a["relatedTopicIds"][0], tb);
        assert_eq!(b["relatedTopicIds"][0], ta);
        assert_eq!(a["relatesTo"][0], "B title");
    }
}

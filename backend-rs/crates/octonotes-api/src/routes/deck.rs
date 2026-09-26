//! Save destinations ("Save in The Deck"). The Deck isn't built yet, so the
//! destinations are the user's Study Studio studios (`studio:<uuid>`); when the
//! Deck exists this returns its folders (`deck:<uuid>`) — same shape.

use axum::extract::State;
use axum::Json;
use chrono::{DateTime, Utc};
use octo_common::ApiError;
use serde::Serialize;
use sqlx::Row;
use utoipa::ToSchema;

use crate::ctx::Caller;
use crate::AppState;

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct Destination {
    /// Stored on the session as `deckRef`.
    #[serde(rename = "ref")]
    pub reference: String,
    /// `studyStudio` today, `deckFolder` later.
    pub kind: String,
    pub title: String,
    pub subtitle: Option<String>,
    pub updated_at: Option<DateTime<Utc>>,
}

#[utoipa::path(get, path = "/v1/deck/destinations", tag = "deck", responses((status = 200, body = Vec<Destination>)))]
pub async fn destinations(
    State(st): State<AppState>,
    caller: Caller,
) -> Result<Json<Vec<Destination>>, ApiError> {
    let Some(studio) = &st.studio else {
        return Ok(Json(Vec::new()));
    };
    let rows = sqlx::query(
        "SELECT id::text AS id, title, subject, updated_at FROM studios WHERE user_id = $1 ORDER BY updated_at DESC LIMIT 200",
    )
    .bind(caller.user_id)
    .fetch_all(studio)
    .await?;
    Ok(Json(
        rows.into_iter()
            .map(|r| Destination {
                reference: format!("studio:{}", r.get::<String, _>("id")),
                kind: "studyStudio".into(),
                title: r.get("title"),
                subtitle: r.get("subject"),
                updated_at: r.get("updated_at"),
            })
            .collect(),
    ))
}

/// Who a Deck call is for: a signed-in user, or The Deck's backend calling
/// with a service key on behalf of a user (`X-Service-Key` + `X-On-Behalf-Of:
/// <users.id>`).
pub struct DeckCaller(pub uuid::Uuid);

#[axum::async_trait]
impl axum::extract::FromRequestParts<AppState> for DeckCaller {
    type Rejection = ApiError;

    async fn from_request_parts(
        parts: &mut axum::http::request::Parts,
        st: &AppState,
    ) -> Result<Self, Self::Rejection> {
        if let Some(key) = parts
            .headers
            .get("x-service-key")
            .and_then(|v| v.to_str().ok())
        {
            if st.config.service_keys.is_empty()
                || !st
                    .config
                    .service_keys
                    .iter()
                    .any(|k| ct_eq(k.as_bytes(), key.as_bytes()))
            {
                return Err(ApiError::unauthorized("invalid service key"));
            }
            let user = parts
                .headers
                .get("x-on-behalf-of")
                .and_then(|v| v.to_str().ok())
                .and_then(|s| uuid::Uuid::parse_str(s).ok())
                .ok_or_else(|| ApiError::bad_request("X-On-Behalf-Of must be a users.id"))?;
            return Ok(DeckCaller(user));
        }
        let c =
            <Caller as axum::extract::FromRequestParts<AppState>>::from_request_parts(parts, st)
                .await?;
        Ok(DeckCaller(c.user_id))
    }
}

#[derive(Debug, serde::Deserialize, ToSchema)]
pub struct DeckSearch {
    pub query: String,
    pub limit: Option<usize>,
}

/// Retrieval across ALL the user's OctoNotes sessions, for The Deck's chat.
/// Returns passages with where they came from, never whole notes.
#[utoipa::path(post, path = "/v1/deck/search", tag = "deck", request_body = DeckSearch,
    responses((status = 200, description = "{items: [{sessionId, sessionTitle, kind, label, excerpt, locator, openPath, score}]}")))]
pub async fn search(
    State(st): State<AppState>,
    who: DeckCaller,
    axum::Json(req): axum::Json<DeckSearch>,
) -> Result<Json<serde_json::Value>, ApiError> {
    use crate::retrieval::{self, Embedder, Passage};
    let q = req.query.trim();
    if q.is_empty() || q.chars().count() > 1000 {
        return Err(ApiError::bad_request("query must be 1..1000 chars"));
    }
    let k = req.limit.unwrap_or(10).clamp(1, 30);
    let qv = Embedder::from_state(&st)
        .embed(&[q.to_string()])
        .await
        .map_err(ApiError::internal)?
        .pop()
        .unwrap_or_default();
    let base = "SELECT c.session_id, s.title AS session_title, c.source_kind, c.source_id, c.content, c.locator FROM note_chunks c \
                JOIN sessions s ON s.id = c.session_id WHERE c.user_id = $1 AND s.deleted_at IS NULL";
    let dense = sqlx::query(&format!("{base} ORDER BY c.embedding <=> $2 LIMIT 30"))
        .bind(who.0)
        .bind(pgvector::Vector::from(qv))
        .fetch_all(&st.notes)
        .await?;
    let lexical = sqlx::query(&format!("{base} AND c.tsv @@ plainto_tsquery('simple', $2) ORDER BY ts_rank(c.tsv, plainto_tsquery('simple', $2)) DESC LIMIT 30"))
        .bind(who.0).bind(q).fetch_all(&st.notes).await?;
    let mut sessions = std::collections::HashMap::new();
    let to_p =
        |r: &sqlx::postgres::PgRow,
         sessions: &mut std::collections::HashMap<String, (uuid::Uuid, String)>| {
            let sid: uuid::Uuid = r.get("session_id");
            let kind: String = r.get("source_kind");
            let source: String = r.get("source_id");
            sessions.insert(
                format!("{kind}|{sid}|{source}"),
                (sid, r.get("session_title")),
            );
            Passage {
                kind,
                source_id: format!("{sid}|{source}"),
                content: r.get("content"),
                locator: r.get("locator"),
                score: 0.0,
            }
        };
    let d: Vec<Passage> = dense.iter().map(|r| to_p(r, &mut sessions)).collect();
    let l: Vec<Passage> = lexical.iter().map(|r| to_p(r, &mut sessions)).collect();
    let items: Vec<serde_json::Value> = retrieval::rrf(vec![d, l], k).into_iter().map(|p| {
        let (sid, _) = p.source_id.split_once('|').unwrap_or(("", ""));
        let title = sessions.values().find(|(s, _)| s.to_string() == sid).map(|x| x.1.clone()).unwrap_or_default();
        serde_json::json!({ "sessionId": sid, "sessionTitle": title, "kind": p.kind, "label": retrieval::label(&p),
                            "excerpt": crate::ai::clip(&p.content, 400), "locator": p.locator, "openPath": format!("/notes/session?id={sid}"), "score": p.score })
    }).collect();
    Ok(Json(serde_json::json!({ "items": items })))
}

/// Constant-time comparison (service keys).
fn ct_eq(a: &[u8], b: &[u8]) -> bool {
    a.len() == b.len() && a.iter().zip(b).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
}

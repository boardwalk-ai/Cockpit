//! Hybrid retrieval in-process (replaces the Go `/search`): dense (bge-m3
//! cosine over the HNSW index) + lexical (`english` and language-neutral
//! `simple` text search, so Burmese matches too), fused with reciprocal rank.
//! Every query is filtered by user and studio inside the SQL.

use std::time::Duration;

use pgvector::Vector;
use sqlx::{PgPool, Row};
use uuid::Uuid;

use crate::AppState;

#[derive(Debug, Clone)]
pub struct Hit {
    pub chunk_id: Uuid,
    pub document_id: Uuid,
    pub ordinal: i32,
    pub content: String,
    pub score: f64,
    pub page: Option<i32>,
}

/// The query's vector, or None if the embedder doesn't answer in 3 s.
pub async fn embed_query(state: &AppState, q: &str) -> Option<Vec<f32>> {
    embed_query_within(state, q, Duration::from_secs(3)).await
}

/// The same with a longer wait (a build can afford one; a question can't).
pub async fn embed_query_within(state: &AppState, q: &str, wait: Duration) -> Option<Vec<f32>> {
    crate::embedder::embed_once(state, &[q.to_string()], wait).await.ok()?.into_iter().next()
}

/// Top `k` passages. With no vector (embedder down) it is lexical only.
pub async fn hybrid(
    vector: &PgPool,
    user: Uuid,
    studio: Uuid,
    query: &str,
    qvec: Option<Vec<f32>>,
    k: i64,
) -> sqlx::Result<Vec<Hit>> {
    let cand = (k * 4).max(20);
    let rows = sqlx::query(
        "WITH q AS (SELECT plainto_tsquery('english', $4) || plainto_tsquery('simple', $4) AS ts), \
         dense AS ( \
           SELECT id, ROW_NUMBER() OVER (ORDER BY embedding <=> $1) AS rnk FROM chunks \
           WHERE $1::vector IS NOT NULL AND user_id = $2 AND studio_id = $3 \
           ORDER BY embedding <=> $1 LIMIT $5), \
         lexical AS ( \
           SELECT c.id, ROW_NUMBER() OVER (ORDER BY ts_rank(c.tsv, q.ts) DESC) AS rnk FROM chunks c, q \
           WHERE c.user_id = $2 AND c.studio_id = $3 AND c.tsv @@ q.ts LIMIT $5), \
         fused AS ( \
           SELECT id, SUM(1.0 / (60 + rnk)) AS score FROM (SELECT * FROM dense UNION ALL SELECT * FROM lexical) u \
           GROUP BY id) \
         SELECT c.id, c.document_id, c.ordinal, c.content, f.score::float8 AS score, c.page \
         FROM fused f JOIN chunks c ON c.id = f.id ORDER BY f.score DESC LIMIT $6",
    )
    .bind(qvec.map(Vector::from))
    .bind(user)
    .bind(studio)
    .bind(query)
    .bind(cand)
    .bind(k)
    .fetch_all(vector)
    .await?;
    Ok(rows
        .iter()
        .map(|r| Hit {
            chunk_id: r.get("id"),
            document_id: r.get("document_id"),
            ordinal: r.get("ordinal"),
            content: r.get("content"),
            score: r.get("score"),
            page: r.try_get("page").ok().flatten(),
        })
        .collect())
}

#[derive(serde::Deserialize)]
pub struct SearchQ {
    user_id: Uuid,
    studio_id: Uuid,
    q: String,
    k: Option<i64>,
}

/// `GET /search?user_id&studio_id&q&k` — the passages Ask AI would get, for
/// measuring retrieval (F9). From the server itself only, like `/metrics`.
pub async fn debug(
    axum::extract::State(state): axum::extract::State<AppState>,
    headers: axum::http::HeaderMap,
    axum::extract::Query(p): axum::extract::Query<SearchQ>,
) -> Result<axum::Json<serde_json::Value>, axum::http::StatusCode> {
    if headers.contains_key("x-forwarded-for") {
        return Err(axum::http::StatusCode::FORBIDDEN);
    }
    let qvec = embed_query(&state, &p.q).await;
    let degraded = qvec.is_none();
    let hits = hybrid(&state.vector, p.user_id, p.studio_id, &p.q, qvec, p.k.unwrap_or(5).clamp(1, 50))
        .await
        .map_err(|_| axum::http::StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(axum::Json(serde_json::json!({
        "degraded": degraded,
        "hits": hits.iter().map(|h| serde_json::json!({ "id": h.chunk_id, "page": h.page, "score": h.score })).collect::<Vec<_>>(),
    })))
}

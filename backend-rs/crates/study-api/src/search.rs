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
    let url = format!("{}/embed", state.config.embed_service_url.trim_end_matches('/'));
    let r = state
        .http
        .post(url)
        .timeout(wait)
        .json(&serde_json::json!({ "texts": [q] }))
        .send()
        .await
        .ok()?;
    if !r.status().is_success() {
        return None;
    }
    let v: serde_json::Value = r.json().await.ok()?;
    serde_json::from_value::<Vec<Vec<f32>>>(v["vectors"].clone()).ok()?.into_iter().next()
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

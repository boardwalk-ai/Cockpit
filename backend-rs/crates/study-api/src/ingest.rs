//! The ingest worker (replaces the Go worker and the Redis list): jobs live
//! in `ingest_jobs`; a worker claims one with `FOR UPDATE SKIP LOCKED`,
//! extracts the file page by page, chunks it, embeds every passage with the
//! real model and only then marks the document `ready`. A file is never
//! "ready" on placeholder vectors (tasklist F3): if embedding keeps failing
//! the job fails with a reason the app can show.

use std::time::Duration;

use pgvector::Vector;
use sqlx::Row;
use uuid::Uuid;

use crate::chunk::{chunk_pages, Chunk, OVERLAP, TARGET};
use crate::extract::{extract, Hirara};
use crate::AppState;

const EMBED_BATCH: usize = 16;
const EMBED_TRIES: u32 = 3;

/// Adds the page / heading columns to `chunks` (nullable; the Python and Go
/// services ignore them).
pub async fn ensure_schema(state: &AppState) -> sqlx::Result<()> {
    sqlx::query("ALTER TABLE chunks ADD COLUMN IF NOT EXISTS page integer, ADD COLUMN IF NOT EXISTS heading text")
        .execute(&state.vector)
        .await?;
    Ok(())
}

/// Embeds `texts` with the embed service, retrying with backoff.
pub async fn embed(state: &AppState, texts: &[String]) -> Result<Vec<Vec<f32>>, String> {
    let mut last = String::new();
    for attempt in 0..EMBED_TRIES {
        if attempt > 0 {
            tokio::time::sleep(Duration::from_secs(2u64.pow(attempt))).await;
        }
        match crate::embedder::embed_once(state, texts, Duration::from_secs(180)).await {
            Ok(vecs) => return Ok(vecs),
            Err(e) => last = e,
        }
    }
    Err(last)
}

/// What goes to the embedder: the passage under its heading, for context.
fn embed_text(c: &Chunk) -> String {
    match &c.heading {
        Some(h) => format!("{h}\n{}", c.text),
        None => c.text.clone(),
    }
}

async fn set_job(state: &AppState, job: Uuid, status: &str, chunks: i32, error: Option<&str>) {
    let _ = sqlx::query(
        "UPDATE ingest_jobs SET status = $2, chunks_written = $3, error = $4, updated_at = now() WHERE id = $1",
    )
    .bind(job)
    .bind(status)
    .bind(chunks)
    .bind(error)
    .execute(&state.cockpit)
    .await;
}

/// Claims the oldest queued job, if any.
async fn claim(state: &AppState) -> sqlx::Result<Option<(Uuid, Uuid)>> {
    let mut tx = state.cockpit.begin().await?;
    let row = sqlx::query(
        "SELECT id, document_id FROM ingest_jobs WHERE status = 'queued' \
         ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED",
    )
    .fetch_optional(&mut *tx)
    .await?;
    let Some(r) = row else { return Ok(None) };
    let (job, doc): (Uuid, Uuid) = (r.get("id"), r.get("document_id"));
    sqlx::query("UPDATE ingest_jobs SET status = 'running', updated_at = now() WHERE id = $1")
        .bind(job)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;
    Ok(Some((job, doc)))
}

/// One job, start to finish. Returns the passages written.
pub async fn run(state: &AppState, job: Uuid, doc: Uuid) -> Result<i32, String> {
    let d = sqlx::query("SELECT object_key, filename, mime, studio_id, user_id FROM documents WHERE id = $1")
        .bind(doc)
        .fetch_one(&state.cockpit)
        .await
        .map_err(|e| e.to_string())?;
    let (key, filename, mime): (String, String, String) = (d.get("object_key"), d.get("filename"), d.get("mime"));
    let (studio, user): (Uuid, Uuid) = (d.get("studio_id"), d.get("user_id"));

    let store = state.store.as_ref().ok_or("no object store configured")?;
    let data = store.get(&key).await?;
    let hirara = Hirara {
        http: &state.http,
        url: &state.config.hirara_hub_url,
        token: &state.config.hirara_hub_token,
    };
    let pages = extract(&hirara, &filename, &mime, &data).await?;
    let chunks = chunk_pages(&pages, TARGET, OVERLAP);
    if chunks.is_empty() {
        return Err("No readable text in this file.".into());
    }

    let mut vectors: Vec<Vec<f32>> = Vec::with_capacity(chunks.len());
    for batch in chunks.chunks(EMBED_BATCH) {
        let texts: Vec<String> = batch.iter().map(embed_text).collect();
        vectors.extend(embed(state, &texts).await.map_err(|e| format!("Couldn't index the file: {e}"))?);
    }

    // All passages in one transaction: a document is either fully indexed or not.
    let mut tx = state.vector.begin().await.map_err(|e| e.to_string())?;
    sqlx::query("DELETE FROM chunks WHERE document_id = $1 AND user_id = $2")
        .bind(doc)
        .bind(user)
        .execute(&mut *tx)
        .await
        .map_err(|e| e.to_string())?;
    for (i, (c, v)) in chunks.iter().zip(vectors).enumerate() {
        sqlx::query(
            "INSERT INTO chunks (id, document_id, studio_id, user_id, ordinal, content, embedding, tsv, page, heading) \
             VALUES ($1, $2, $3, $4, $5, $6, $7, to_tsvector('english', $6) || to_tsvector('simple', $6), $8, $9)",
        )
        .bind(Uuid::new_v4())
        .bind(doc)
        .bind(studio)
        .bind(user)
        .bind(i as i32)
        .bind(&c.text)
        .bind(Vector::from(v))
        .bind(c.page)
        .bind(&c.heading)
        .execute(&mut *tx)
        .await
        .map_err(|e| e.to_string())?;
    }
    tx.commit().await.map_err(|e| e.to_string())?;
    let n = chunks.len() as i32;
    set_job(state, job, "done", n, None).await;
    let _ = sqlx::query("UPDATE documents SET status = 'ready' WHERE id = $1")
        .bind(doc)
        .execute(&state.cockpit)
        .await;
    Ok(n)
}

/// A worker: claims and runs jobs; sleeps until woken (an upload) or 5 s.
pub async fn worker(state: AppState, n: usize) {
    loop {
        match claim(&state).await {
            Ok(Some((job, doc))) => {
                let t = std::time::Instant::now();
                match run(&state, job, doc).await {
                    Ok(chunks) => tracing::info!(worker = n, %job, chunks, secs = t.elapsed().as_secs_f32(), "ingested"),
                    Err(e) => {
                        tracing::warn!(worker = n, %job, "ingest failed: {e}");
                        let msg: String = e.chars().take(500).collect();
                        set_job(&state, job, "failed", 0, Some(&msg)).await;
                        let _ = sqlx::query("UPDATE documents SET status = 'failed' WHERE id = $1")
                            .bind(doc)
                            .execute(&state.cockpit)
                            .await;
                    }
                }
            }
            Ok(None) => {
                let _ = tokio::time::timeout(Duration::from_secs(5), state.jobs.notified()).await;
            }
            Err(e) => {
                tracing::warn!("claim: {e}");
                tokio::time::sleep(Duration::from_secs(5)).await;
            }
        }
    }
}

pub fn spawn(state: &AppState) {
    // Jobs left "running" by a process that stopped go back in the queue.
    let s = state.clone();
    tokio::spawn(async move {
        let _ = sqlx::query(
            "UPDATE ingest_jobs SET status = 'queued', updated_at = now()              WHERE status = 'running' AND updated_at < now() - interval '10 minutes'",
        )
        .execute(&s.cockpit)
        .await;
    });
    for n in 0..state.config.ingest_workers.max(1) {
        tokio::spawn(worker(state.clone(), n));
    }
}

//! Retrieval over a session's own content (transcript windows, blocks, slide
//! pages, saved research) plus — when the session is saved to a Study Studio
//! studio — that studio's RAG chunks. Hybrid: dense cosine + lexical, fused
//! with reciprocal-rank fusion (the same approach as Study Studio's `rag.py`).
//!
//! Embeddings come from the shared BGE-m3 service (`EMBED_URL`, 1024-dim), the
//! same model as Study Studio, so scores are comparable. Without it (dev/tests)
//! a deterministic hashing embedder keeps everything working, and Study Studio
//! chunks are then matched lexically only (different vector space).

use std::collections::HashMap;

use pgvector::Vector;
use serde::Serialize;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use sqlx::Row;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::jobs::{Job, JobResult};
use crate::AppState;

pub const DIM: usize = 1024;
const WINDOW_MS: i64 = 60_000;

pub enum Embedder {
    Remote { http: reqwest::Client, url: String },
    Hashing,
}

impl Embedder {
    pub fn from_state(st: &AppState) -> Self {
        match &st.config.embed_url {
            Some(url) => Embedder::Remote {
                http: st.http.clone(),
                url: url.trim_end_matches('/').to_string(),
            },
            None => Embedder::Hashing,
        }
    }

    pub fn name(&self) -> &'static str {
        match self {
            Embedder::Remote { .. } => "bge-m3",
            Embedder::Hashing => "hashing-v1",
        }
    }

    pub async fn embed(&self, texts: &[String]) -> Result<Vec<Vec<f32>>, String> {
        match self {
            Embedder::Remote { http, url } => {
                let mut out = Vec::with_capacity(texts.len());
                for batch in texts.chunks(32) {
                    let v: Value = http
                        .post(format!("{url}/embed"))
                        .json(&json!({ "texts": batch }))
                        .send()
                        .await
                        .map_err(|e| format!("embed: {e}"))?
                        .json()
                        .await
                        .map_err(|e| format!("embed body: {e}"))?;
                    let vectors: Vec<Vec<f32>> = serde_json::from_value(v["vectors"].clone())
                        .map_err(|e| format!("embed shape: {e}"))?;
                    if vectors.iter().any(|x| x.len() != DIM) {
                        return Err(format!("embed service returned non-{DIM}-dim vectors"));
                    }
                    out.extend(vectors);
                }
                Ok(out)
            }
            Embedder::Hashing => Ok(texts.iter().map(|t| hashing(t)).collect()),
        }
    }
}

/// Feature hashing of lowercase word unigrams + bigrams, L2-normalized.
pub fn hashing(text: &str) -> Vec<f32> {
    let mut v = vec![0f32; DIM];
    let words: Vec<String> = text
        .split(|c: char| !c.is_alphanumeric())
        .filter(|w| !w.is_empty())
        .map(|w| w.to_lowercase())
        .collect();
    let mut add = |token: &str| {
        let h = Sha256::digest(token.as_bytes());
        let idx = (u32::from_le_bytes([h[0], h[1], h[2], h[3]]) as usize) % DIM;
        let sign = if h[4] & 1 == 0 { 1.0 } else { -1.0 };
        v[idx] += sign;
    };
    for w in &words {
        add(w);
    }
    for pair in words.windows(2) {
        add(&format!("{} {}", pair[0], pair[1]));
    }
    let norm = v.iter().map(|x| x * x).sum::<f32>().sqrt();
    if norm > 0.0 {
        v.iter_mut().for_each(|x| *x /= norm);
    }
    v
}

fn hash(text: &str) -> String {
    hex::encode(&Sha256::digest(text.as_bytes())[..12])
}

struct Doc {
    kind: &'static str,
    id: String,
    content: String,
    locator: Value,
}

/// Rebuilds a session's index incrementally: unchanged sources keep their
/// vectors, changed ones are re-embedded, removed ones are dropped.
pub async fn job_embed_session(st: AppState, job: Job) -> JobResult {
    let sid: Uuid =
        serde_json::from_value(job.payload["sessionId"].clone()).map_err(|e| e.to_string())?;
    let user: Option<Uuid> =
        sqlx::query_scalar("SELECT user_id FROM sessions WHERE id = $1 AND deleted_at IS NULL")
            .bind(sid)
            .fetch_optional(&st.notes)
            .await
            .map_err(|e| e.to_string())?;
    let Some(user) = user else { return Ok(()) };
    let docs = collect(&st, sid).await.map_err(|e| e.to_string())?;

    // Keyed by source; value = (content hash, embedder). A source is
    // re-embedded when its text changed OR it was embedded by another model
    // (e.g. the offline embedder before the BGE-m3 service came back).
    let existing: HashMap<(String, String), (String, String)> = sqlx::query(
        "SELECT source_kind, source_id, content_hash, embedder FROM note_chunks WHERE session_id = $1",
    )
    .bind(sid)
    .fetch_all(&st.notes)
    .await
    .map_err(|e| e.to_string())?
    .into_iter()
    .map(|r| {
        (
            (r.get::<String, _>("source_kind"), r.get::<String, _>("source_id")),
            (r.get::<String, _>("content_hash"), r.get::<String, _>("embedder")),
        )
    })
    .collect();
    let embedder = Embedder::from_state(&st);
    let changed: Vec<&Doc> = docs
        .iter()
        .filter(|d| {
            existing.get(&(d.kind.to_string(), d.id.clone()))
                != Some(&(hash(&d.content), embedder.name().to_string()))
        })
        .collect();
    let vectors = embedder
        .embed(
            &changed
                .iter()
                .map(|d| d.content.clone())
                .collect::<Vec<_>>(),
        )
        .await?;

    let mut tx = st.notes.begin().await.map_err(|e| e.to_string())?;
    let keep: Vec<String> = docs
        .iter()
        .map(|d| format!("{}|{}", d.kind, d.id))
        .collect();
    sqlx::query("DELETE FROM note_chunks WHERE session_id = $1 AND NOT (source_kind || '|' || source_id = ANY($2))")
        .bind(sid)
        .bind(&keep)
        .execute(&mut *tx)
        .await
        .map_err(|e| e.to_string())?;
    for (d, v) in changed.iter().zip(vectors) {
        sqlx::query(
            "INSERT INTO note_chunks (session_id, user_id, source_kind, source_id, content, content_hash, locator, embedding, embedder) \
             VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) \
             ON CONFLICT (session_id, source_kind, source_id) DO UPDATE SET content = EXCLUDED.content, \
                 content_hash = EXCLUDED.content_hash, locator = EXCLUDED.locator, embedding = EXCLUDED.embedding, embedder = EXCLUDED.embedder",
        )
        .bind(sid)
        .bind(user)
        .bind(d.kind)
        .bind(&d.id)
        .bind(&d.content)
        .bind(hash(&d.content))
        .bind(&d.locator)
        .bind(Vector::from(v))
        .bind(embedder.name())
        .execute(&mut *tx)
        .await
        .map_err(|e| e.to_string())?;
    }
    tx.commit().await.map_err(|e| e.to_string())
}

async fn collect(st: &AppState, sid: Uuid) -> Result<Vec<Doc>, sqlx::Error> {
    let mut docs = Vec::new();
    // Transcript: 60-second windows of display text.
    let segs = sqlx::query(
        "SELECT start_ms, COALESCE(corrected_text, faithful_text, raw_text) AS text, speaker FROM transcript_segments \
         WHERE session_id = $1 AND status = 'stable' ORDER BY start_ms",
    )
    .bind(sid)
    .fetch_all(&st.notes)
    .await?;
    let mut windows: Vec<(i64, String)> = Vec::new();
    for r in segs {
        let start: i64 = r.get("start_ms");
        let text: String = r.get("text");
        let w = start / WINDOW_MS;
        match windows.last_mut() {
            Some((ws, t)) if *ws == w => {
                t.push(' ');
                t.push_str(&text);
            }
            _ => windows.push((w, text)),
        }
    }
    for (w, text) in windows {
        docs.push(Doc {
            kind: "transcript",
            id: format!("w{w}"),
            content: text,
            locator: json!({ "fromMs": w * WINDOW_MS, "toMs": (w + 1) * WINDOW_MS }),
        });
    }
    // Blocks with real text.
    for r in sqlx::query("SELECT id, type, text FROM blocks WHERE session_id = $1 AND deleted_at IS NULL AND length(text) >= 12")
        .bind(sid)
        .fetch_all(&st.notes)
        .await?
    {
        let id: Uuid = r.get("id");
        docs.push(Doc { kind: "block", id: id.to_string(), content: r.get("text"), locator: json!({ "blockId": id, "type": r.get::<String, _>("type") }) });
    }
    // Slide/material pages.
    for r in sqlx::query(
        "SELECT p.material_id, p.number, p.title, p.ocr_text, m.filename FROM material_pages p JOIN materials m ON m.id = p.material_id \
         WHERE m.session_id = $1 AND m.deleted_at IS NULL AND length(p.ocr_text) > 0",
    )
    .bind(sid)
    .fetch_all(&st.notes)
    .await?
    {
        let mid: Uuid = r.get("material_id");
        let n: i32 = r.get("number");
        docs.push(Doc {
            kind: "slide",
            id: format!("{mid}:{n}"),
            content: format!("{}\n{}", r.get::<String, _>("title"), r.get::<String, _>("ocr_text")),
            locator: json!({ "materialId": mid, "page": n, "filename": r.get::<String, _>("filename") }),
        });
    }
    // Saved research explanations.
    for r in sqlx::query("SELECT id, question, explanation FROM research_runs WHERE session_id = $1 AND saved AND explanation IS NOT NULL")
        .bind(sid)
        .fetch_all(&st.notes)
        .await?
    {
        let id: Uuid = r.get("id");
        docs.push(Doc {
            kind: "research",
            id: id.to_string(),
            content: format!("{}\n{}", r.get::<String, _>("question"), r.get::<String, _>("explanation")),
            locator: json!({ "researchId": id }),
        });
    }
    Ok(docs)
}

#[derive(Debug, Clone, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct Passage {
    /// `transcript` | `slide` | `block` | `research` | `studyStudio`
    pub kind: String,
    pub source_id: String,
    pub content: String,
    #[schema(value_type = Object)]
    pub locator: Value,
    pub score: f64,
}

/// Top-k passages for `query` in the session, plus its linked studio.
pub async fn search(
    st: &AppState,
    user_id: Uuid,
    session_id: Uuid,
    query: &str,
    k: usize,
) -> Result<Vec<Passage>, String> {
    let embedder = Embedder::from_state(st);
    let qv = embedder
        .embed(&[query.to_string()])
        .await?
        .pop()
        .unwrap_or_default();
    let dense = sqlx::query(
        "SELECT source_kind, source_id, content, locator FROM note_chunks WHERE session_id = $1 AND user_id = $2 \
         ORDER BY embedding <=> $3 LIMIT 20",
    )
    .bind(session_id)
    .bind(user_id)
    .bind(Vector::from(qv.clone()))
    .fetch_all(&st.notes)
    .await
    .map_err(|e| e.to_string())?;
    let lexical = sqlx::query(
        "SELECT source_kind, source_id, content, locator FROM note_chunks WHERE session_id = $1 AND user_id = $2 \
         AND tsv @@ plainto_tsquery('simple', $3) ORDER BY ts_rank(tsv, plainto_tsquery('simple', $3)) DESC LIMIT 20",
    )
    .bind(session_id)
    .bind(user_id)
    .bind(query)
    .fetch_all(&st.notes)
    .await
    .map_err(|e| e.to_string())?;

    let to_passage = |r: &sqlx::postgres::PgRow| Passage {
        kind: r.get("source_kind"),
        source_id: r.get("source_id"),
        content: r.get("content"),
        locator: r.get("locator"),
        score: 0.0,
    };
    let mut lists: Vec<Vec<Passage>> = vec![
        dense.iter().map(to_passage).collect(),
        lexical.iter().map(to_passage).collect(),
    ];

    // The linked Study Studio (course sources first).
    if let (Some(vec_pool), Some(studio_id)) =
        (&st.studio_vector, linked_studio(st, session_id).await)
    {
        let remote = matches!(embedder, Embedder::Remote { .. });
        let studio_rows = if remote {
            sqlx::query(
                "SELECT id::text AS id, content, ordinal FROM chunks WHERE user_id = $1 AND studio_id = $2 \
                 ORDER BY embedding <=> $3 LIMIT 20",
            )
            .bind(user_id)
            .bind(studio_id)
            .bind(Vector::from(qv))
            .fetch_all(vec_pool)
            .await
            .map_err(|e| e.to_string())?
        } else {
            Vec::new()
        };
        let studio_lex = sqlx::query(
            "SELECT id::text AS id, content, ordinal FROM chunks WHERE user_id = $1 AND studio_id = $2 \
             AND tsv @@ plainto_tsquery('simple', $3) ORDER BY ts_rank(tsv, plainto_tsquery('simple', $3)) DESC LIMIT 20",
        )
        .bind(user_id)
        .bind(studio_id)
        .bind(query)
        .fetch_all(vec_pool)
        .await
        .unwrap_or_default();
        let to_studio = |r: &sqlx::postgres::PgRow| Passage {
            kind: "studyStudio".into(),
            source_id: r.get("id"),
            content: r.get("content"),
            locator: json!({ "studioId": studio_id, "ordinal": r.get::<i32, _>("ordinal") }),
            score: 0.0,
        };
        lists.push(studio_rows.iter().map(to_studio).collect());
        lists.push(studio_lex.iter().map(to_studio).collect());
    }
    Ok(rrf(lists, k))
}

/// The Study Studio studio a session is saved to (`deck_ref = studio:<uuid>`).
pub async fn linked_studio(st: &AppState, session_id: Uuid) -> Option<Uuid> {
    let r: Option<String> = sqlx::query_scalar("SELECT deck_ref FROM sessions WHERE id = $1")
        .bind(session_id)
        .fetch_optional(&st.notes)
        .await
        .ok()
        .flatten()
        .flatten();
    r.and_then(|r| {
        r.strip_prefix("studio:")
            .and_then(|id| Uuid::parse_str(id).ok())
    })
}

/// Reciprocal-rank fusion (k = 60) across ranked lists, de-duplicated.
pub fn rrf(lists: Vec<Vec<Passage>>, k: usize) -> Vec<Passage> {
    let mut scores: HashMap<(String, String), (f64, Passage)> = HashMap::new();
    for list in lists {
        for (rank, p) in list.into_iter().enumerate() {
            let key = (p.kind.clone(), p.source_id.clone());
            let e = scores.entry(key).or_insert((0.0, p));
            e.0 += 1.0 / (60.0 + rank as f64 + 1.0);
        }
    }
    let mut out: Vec<Passage> = scores
        .into_values()
        .map(|(s, mut p)| {
            p.score = s;
            p
        })
        .collect();
    out.sort_by(|a, b| {
        b.score
            .partial_cmp(&a.score)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    out.truncate(k);
    out
}

/// A human label for a passage ("Transcript · 18:20–19:20", "Slide 7").
pub fn label(p: &Passage) -> String {
    match p.kind.as_str() {
        "transcript" => {
            let from = p.locator["fromMs"].as_i64().unwrap_or(0);
            let to = p.locator["toMs"].as_i64().unwrap_or(0);
            format!(
                "Transcript · {}–{}",
                crate::routes::transcript::format_ms(from),
                crate::routes::transcript::format_ms(to)
            )
        }
        "slide" => format!(
            "{} · Slide {}",
            p.locator["filename"].as_str().unwrap_or("Slides"),
            p.locator["page"]
        ),
        "block" => "Your notes".into(),
        "research" => "Saved research".into(),
        "studyStudio" => "Study Studio".into(),
        other => other.into(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hashing_embedder_is_normalized_and_lexical() {
        let a = hashing("the electron transport chain uses oxygen");
        let b = hashing("oxygen is used by the electron transport chain");
        let c = hashing("photosynthesis in chloroplasts");
        let dot = |x: &[f32], y: &[f32]| x.iter().zip(y).map(|(p, q)| p * q).sum::<f32>();
        assert!((dot(&a, &a) - 1.0).abs() < 1e-4);
        assert!(dot(&a, &b) > dot(&a, &c));
    }

    #[test]
    fn rrf_prefers_items_in_both_lists() {
        let p = |id: &str| Passage {
            kind: "block".into(),
            source_id: id.into(),
            content: String::new(),
            locator: json!({}),
            score: 0.0,
        };
        let fused = rrf(vec![vec![p("a"), p("b")], vec![p("b"), p("c")]], 3);
        assert_eq!(fused[0].source_id, "b");
    }
}

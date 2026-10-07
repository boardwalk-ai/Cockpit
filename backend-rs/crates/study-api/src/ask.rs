//! `GET /ask?studio_id&q&history&topic` — Ask AI as SSE: `citations`
//! (with file names and pages) first, then `delta`s, then `meta`, `done`.
//! A port of the Python route, plus the A5 guards: the studio must be the
//! caller's, `q` is capped at 2,000 characters, and each user gets at most
//! 30 questions per 10 minutes. If the embedder is down the search falls
//! back to keywords and `meta.retrieval` says `"degraded"` instead of the
//! failure being swallowed (F4). Every answer's cost goes to `llm_usage`.

use std::collections::{HashMap, VecDeque};
use std::convert::Infallible;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use axum::extract::{Query, State};
use axum::response::sse::{Event, KeepAlive, Sse};
use futures::{Stream, StreamExt};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use crate::identity::UserId;
use crate::llm::{self, Call, Piece};
use crate::progress::owned_studio;
use crate::search;
use crate::sse;
use crate::AppState;

pub const SYSTEM_PROMPT: &str = "You are the Study Studio tutor. Answer ONLY from the provided context. \
Cite the sources you use with bracketed numbers like [1], [2] that match \
the context blocks. If the context does not contain the answer, say you \
don't have enough material on that topic yet — do not invent facts.";
pub const ASK_STYLE: &str = " You are talking to a student on a phone: answer in short plain \
paragraphs (about 150 words unless they ask for more), no headings or \
tables, and mark the one or two key terms with **double asterisks**.";

const MAX_Q: usize = 2000;
const HISTORY_TURNS: usize = 3;
const HISTORY_CHARS: usize = 1200;
const TOP_K: i64 = 8;
const CONTEXT_K: usize = 5;
const MAX_TOKENS: u32 = 1200;
pub const RATE_LIMIT: usize = 30;
pub const RATE_WINDOW: Duration = Duration::from_secs(600);

/// Questions asked per user in the last window (one process, in memory).
#[derive(Default)]
pub struct RateLimit(Mutex<HashMap<Uuid, VecDeque<Instant>>>);

impl RateLimit {
    pub fn allow(&self, user: Uuid, now: Instant) -> bool {
        let mut m = self.0.lock().unwrap();
        let q = m.entry(user).or_default();
        while q.front().is_some_and(|t| now.duration_since(*t) > RATE_WINDOW) {
            q.pop_front();
        }
        if q.len() >= RATE_LIMIT {
            return false;
        }
        q.push_back(now);
        true
    }
}

fn cut(s: &str, n: usize) -> String {
    s.trim().chars().take(n).collect()
}

/// Earlier turns from the client: a JSON list of {q, a}, the last few kept,
/// each side trimmed. Anything malformed is ignored.
pub fn parse_history(raw: Option<&str>) -> Vec<(String, String)> {
    let Some(v) = raw.and_then(|r| serde_json::from_str::<Value>(r).ok()) else { return vec![] };
    let Some(items) = v.as_array() else { return vec![] };
    let turns: Vec<(String, String)> = items
        .iter()
        .filter_map(|it| {
            let q = cut(it.get("q")?.as_str()?, HISTORY_CHARS);
            let a = cut(it.get("a")?.as_str()?, HISTORY_CHARS);
            (!q.is_empty() && !a.is_empty()).then_some((q, a))
        })
        .collect();
    turns[turns.len().saturating_sub(HISTORY_TURNS)..].to_vec()
}

/// What to search with: a short follow-up borrows the last question; a
/// chosen topic leads.
pub fn search_text(q: &str, history: &[(String, String)], topic: Option<&str>) -> String {
    let mut parts = Vec::new();
    if let Some(t) = topic.map(str::trim).filter(|t| !t.is_empty()) {
        parts.push(t.to_string());
    }
    if let Some((last, _)) = history.last() {
        if q.split_whitespace().count() < 8 {
            parts.push(last.clone());
        }
    }
    parts.push(q.to_string());
    parts.join(" ")
}

pub fn messages(q: &str, context: &str, history: &[(String, String)], focus: Option<&str>) -> Vec<Value> {
    let mut system = format!("{SYSTEM_PROMPT}{ASK_STYLE}");
    if let Some(f) = focus {
        system.push_str(&format!(" The student is asking about the topic \"{f}\"."));
    }
    let mut out = vec![json!({ "role": "system", "content": system })];
    for (q, a) in history {
        out.push(json!({ "role": "user", "content": q }));
        out.push(json!({ "role": "assistant", "content": a }));
    }
    out.push(json!({ "role": "user", "content": format!("Context:\n{context}\n\nQuestion: {q}") }));
    out
}

#[derive(Deserialize)]
pub struct AskQ {
    studio_id: String,
    q: String,
    history: Option<String>,
    topic: Option<String>,
}

pub async fn ask(
    State(state): State<AppState>,
    UserId(user): UserId,
    Query(p): Query<AskQ>,
) -> Sse<impl Stream<Item = Result<Event, Infallible>>> {
    let stream = async_stream::stream! {
        let q = p.q.trim().to_string();
        if q.is_empty() || q.chars().count() > MAX_Q {
            yield Ok(sse::error(format!("Ask in up to {MAX_Q} characters.")));
            return;
        }
        let Some(studio) = owned_studio(&state.cockpit, &p.studio_id, user).await else {
            yield Ok(sse::error("Studio not found"));
            return;
        };
        if !state.ask_limit.allow(user, Instant::now()) {
            yield Ok(sse::error("That's a lot of questions at once — try again in a few minutes."));
            return;
        }
        let turns = parse_history(p.history.as_deref());
        let topic = p.topic.as_deref().map(str::trim).filter(|t| !t.is_empty()).map(|t| cut(t, 300));

        let query = search_text(&q, &turns, topic.as_deref());
        let qvec = search::embed_query(&state, &query).await;
        let degraded = qvec.is_none();
        let hits = search::hybrid(&state.vector, user, studio, &query, qvec, TOP_K).await.unwrap_or_default();

        if !hits.is_empty() {
            let ids: Vec<Uuid> = hits.iter().map(|h| h.document_id).collect();
            let names: HashMap<Uuid, String> = sqlx::query("SELECT id, filename FROM documents WHERE user_id = $1 AND id = ANY($2)")
                .bind(user).bind(&ids).fetch_all(&state.cockpit).await
                .map(|rows| rows.iter().map(|r| (r.get("id"), r.get("filename"))).collect())
                .unwrap_or_default();
            let cites: Vec<Value> = hits.iter().take(CONTEXT_K).map(|h| json!({
                "chunkId": h.chunk_id.to_string(),
                "documentId": h.document_id.to_string(),
                "ordinal": h.ordinal,
                "score": (h.score * 10_000.0).round() / 10_000.0,
                "snippet": h.content.chars().take(280).collect::<String>(),
                "fileName": names.get(&h.document_id),
                "page": h.page,
            })).collect();
            yield Ok(sse::event("citations", &cites));
        }
        let context = hits.iter().enumerate().map(|(i, h)| format!("[{}] {}", i + 1, h.content)).collect::<Vec<_>>().join("\n\n");

        let (key, model) = llm::credentials(state.shared.as_ref(), "primary_model", "anthropic/claude-sonnet-4-6").await;
        let Some(key) = key else {
            yield Ok(sse::error("The tutor isn't connected right now."));
            return;
        };
        let call = Call {
            http: &state.http,
            key: &key,
            model: &model,
            messages: messages(&q, &context, &turns, topic.as_deref()),
            max_tokens: MAX_TOKENS,
            temperature: 0.2,
            user,
        };
        match llm::stream(call).await {
            Err(e) => {
                tracing::warn!("ask: {e}");
                yield Ok(sse::error("Couldn't get an answer just now."));
                return;
            }
            Ok(s) => {
                futures::pin_mut!(s);
                while let Some(piece) = s.next().await {
                    match piece {
                        Ok(Piece::Text(t)) => yield Ok(sse::event("delta", &json!({ "text": t }))),
                        Ok(Piece::Usage(u)) => {
                            let meter = llm::Meter { user, studio: Some(studio), build: None, feature: "ask" };
                            llm::record(&state.cockpit, meter, &model, &u).await
                        }
                        Err(e) => {
                            tracing::warn!("ask stream: {e}");
                            yield Ok(sse::error("The answer was cut off."));
                            return;
                        }
                    }
                }
            }
        }
        let mut meta = json!({ "model": model });
        if degraded {
            meta["retrieval"] = json!("degraded");
        }
        yield Ok(sse::event("meta", &meta));
        yield Ok(sse::done());
    };
    Sse::new(stream).keep_alive(KeepAlive::default())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn history_like_python() {
        let raw = serde_json::to_string(&json!([
            {"q":"q0","a":"a0"},{"q":"q1","a":"a1"},{"q":"q2","a":"a2"},{"q":"q3","a":"a3"},{"q":"q4","a":"a4"},
            {"q":"no answer"}, "junk", {"q": "x".repeat(5000), "a": "y"}
        ]))
        .unwrap();
        let t = parse_history(Some(&raw));
        assert_eq!(t.iter().map(|x| x.0.chars().count()).collect::<Vec<_>>(), vec![2, 2, 1200]);
        assert_eq!(t[0].0, "q3");
        assert!(parse_history(Some("not json")).is_empty());
        assert!(parse_history(None).is_empty());
    }

    #[test]
    fn search_text_like_python() {
        let h = vec![("What is NAT?".to_string(), "…".to_string())];
        assert_eq!(search_text("why?", &h, Some("NAT")), "NAT What is NAT? why?");
        let long = "how does a router choose the next hop for a packet today";
        assert_eq!(search_text(long, &h, None), long);
    }

    #[test]
    fn messages_carry_history_and_topic() {
        let m = messages("why?", "[1] x", &[("What is NAT?".into(), "It maps.".into())], Some("NAT"));
        let roles: Vec<_> = m.iter().map(|x| x["role"].as_str().unwrap()).collect();
        assert_eq!(roles, ["system", "user", "assistant", "user"]);
        assert!(m[0]["content"].as_str().unwrap().contains("\"NAT\""));
        assert!(m[3]["content"].as_str().unwrap().ends_with("Question: why?"));
    }

    #[test]
    fn thirty_questions_per_ten_minutes() {
        let rl = RateLimit::default();
        let u = Uuid::new_v4();
        let t0 = Instant::now();
        for _ in 0..RATE_LIMIT {
            assert!(rl.allow(u, t0));
        }
        assert!(!rl.allow(u, t0));
        assert!(rl.allow(Uuid::new_v4(), t0));
        assert!(rl.allow(u, t0 + RATE_WINDOW + Duration::from_secs(1)));
    }
}

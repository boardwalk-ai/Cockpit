//! `POST /studios/{id}/grade` — is a spoken (or typed) Lightning recall
//! answer right? The app checks words itself first and asks here only when
//! they don't match, so a different wording or a synonym can still count. One small call on the cheap build model; paid in credits
//! like every AI call (feature `grade`).
//!
//! Body `{question, answer, said}` → `data {correct, feedback}`.

use axum::extract::{Path, State};
use axum::Json;
use serde::Deserialize;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::credits;
use crate::gen;
use crate::identity::UserId;
use crate::llm::{self, Call, Meter};
use crate::progress::owned_studio;
use crate::sse::{self, SseStream};
use crate::AppState;

const SYSTEM: &str = "You mark a student's quick spoken answer to a flashcard question. \
The answer may be transcribed speech: ignore spelling, filler words and word order. \
Count it correct if it means the same as the expected answer, \
even if shorter, as long as the key idea is there. Count it wrong if it is a different idea, \
too vague, or misses the key term. Output JSON only: {\"correct\": true|false, \"feedback\": \"one short sentence\"}.";

#[derive(Deserialize)]
pub struct GradeIn {
    question: String,
    answer: String,
    said: String,
}

fn cut(s: &str, n: usize) -> String {
    s.trim().chars().take(n).collect()
}

pub fn prompt(q: &GradeIn) -> String {
    format!(
        "Question: {}\nExpected answer: {}\nStudent said: {}",
        cut(&q.question, 600),
        cut(&q.answer, 600),
        cut(&q.said, 400)
    )
}

/// The verdict from a reply; None if it isn't one.
pub fn verdict(reply: &str) -> Option<(bool, String)> {
    let v = gen::parse_json(reply)?;
    let correct = v.get("correct").and_then(Value::as_bool)?;
    let feedback = v.get("feedback").and_then(Value::as_str).unwrap_or("").trim().chars().take(200).collect();
    Some((correct, feedback))
}

pub async fn grade(
    State(state): State<AppState>,
    UserId(user): UserId,
    Path(id): Path<String>,
    Json(body): Json<GradeIn>,
) -> SseStream {
    let Some(sid) = owned_studio(&state.cockpit, &id, user).await else {
        return sse::events(vec![sse::error("Studio not found")]);
    };
    if body.said.trim().is_empty() || body.answer.trim().is_empty() {
        return sse::one(&json!({ "correct": false, "feedback": "" }));
    }
    let hold = match credits::reserve(&state, user, "grade", format!("study:grade:{sid}:{}", Uuid::new_v4()), json!({ "studio": sid })).await {
        Ok(h) => h,
        Err(short) => return sse::events(vec![sse::error_data(&short.data())]),
    };
    let (key, model) = match &state.shared {
        Some(pool) => {
            let key = octo_common::llm::openrouter_key(pool).await;
            let primary = octo_common::llm::model(pool, "primary_model", "anthropic/claude-sonnet-4-6").await;
            let model = match &state.config.build_model {
                Some(m) => m.clone(),
                None => octo_common::llm::model(pool, "secondary_model", &primary).await,
            };
            (key, model)
        }
        None => (None, String::new()),
    };
    let Some(key) = key else {
        hold.release(&state).await;
        return sse::events(vec![sse::error("Grading isn't available right now.")]);
    };
    let call = Call {
        http: &state.http,
        key: &key,
        model: &model,
        messages: vec![json!({ "role": "system", "content": SYSTEM }), json!({ "role": "user", "content": prompt(&body) })],
        max_tokens: 120,
        temperature: 0.0,
        user,
    };
    let meter = Meter { user, studio: Some(sid), build: None, feature: "grade" };
    match llm::complete_costed(call, &state.cockpit, meter).await {
        Ok((reply, u)) => match verdict(&reply) {
            Some((correct, feedback)) => {
                hold.settle(&state, u.cost, json!({ "studio": sid })).await;
                sse::one(&json!({ "correct": correct, "feedback": feedback, "usage": u.json(&model) }))
            }
            None => {
                hold.release(&state).await;
                sse::events(vec![sse::error("Couldn't mark that one.")])
            }
        },
        Err(e) => {
            hold.release(&state).await;
            tracing::warn!(studio = %sid, "grade: {e}");
            sse::events(vec![sse::error("Couldn't mark that one.")])
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_verdict() {
        assert_eq!(verdict(r#"{"correct": true, "feedback": "Same idea."}"#), Some((true, "Same idea.".into())));
        assert_eq!(verdict("```json\n{\"correct\": false}\n```"), Some((false, String::new())));
        assert_eq!(verdict("maybe"), None);
    }

    #[test]
    fn prompt_is_capped() {
        let q = GradeIn { question: "q".repeat(5000), answer: "a".into(), said: "s".repeat(5000) };
        assert!(prompt(&q).chars().count() < 1100);
    }
}

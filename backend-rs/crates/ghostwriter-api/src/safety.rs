//! Content checks (docs/ghostwriter/PLAN-content-policy.md), by OpenAI's
//! moderation endpoint: free, with fixed categories.
//!
//! Topics are not blocked, tasks are: students write about hard subjects,
//! so only the categories that mean "help someone do it" stop a run. The
//! check runs on the user's request, the outline and the finished text.
//! A stopped task gets a short reply and is logged (who, where, which
//! category, never the text).
//!
//! It fails open: with no key, or when the endpoint cannot be reached, the
//! run goes on and a warning is logged, so an outage does not stop every
//! essay.

use axum::async_trait;
use serde_json::{json, Value};
use sqlx::PgPool;
use uuid::Uuid;

const MODERATION_URL: &str = "https://api.openai.com/v1/moderations";
const MODERATION_MODEL: &str = "omni-moderation-latest";

/// The longest text sent at once; the start of a long essay shows what it is.
const MAX_CHARS: usize = 24_000;

/// Where in a run the check happens.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Stage {
    /// What the user asked for (a brief, a revision, a chat message).
    Task,
    /// The planned essay: topic, thesis and outline.
    Outline,
    /// The text about to be saved.
    Output,
}

impl Stage {
    pub fn as_str(self) -> &'static str {
        match self {
            Stage::Task => "task",
            Stage::Outline => "outline",
            Stage::Output => "output",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Verdict {
    Allow,
    /// Not written. `category` is the endpoint's; `reply` is what the user
    /// is told.
    Refuse {
        category: String,
        reply: String,
    },
}

#[async_trait]
pub trait Screen: Send + Sync {
    async fn check(&self, stage: Stage, text: &str) -> Verdict;
}

/// Lets everything through (tests, and builds without the shared DB).
pub struct AllowAll;

#[async_trait]
impl Screen for AllowAll {
    async fn check(&self, _: Stage, _: &str) -> Verdict {
        Verdict::Allow
    }
}

/// OpenAI's moderation endpoint, with an `openai` key from the shared pool.
pub struct Moderation {
    http: reqwest::Client,
    octopilot: Option<PgPool>,
}

impl Moderation {
    pub fn new(http: reqwest::Client, octopilot: Option<PgPool>) -> Self {
        Self { http, octopilot }
    }

    async fn key(&self) -> Option<String> {
        let pool = self.octopilot.as_ref()?;
        sqlx::query_scalar(
            "SELECT key FROM api_keys WHERE provider ILIKE 'openai' AND is_active = true \
             ORDER BY usage_count ASC NULLS FIRST LIMIT 1",
        )
        .fetch_optional(pool)
        .await
        .ok()
        .flatten()
    }
}

#[async_trait]
impl Screen for Moderation {
    async fn check(&self, stage: Stage, text: &str) -> Verdict {
        let Some(key) = self.key().await else {
            tracing::warn!(
                stage = stage.as_str(),
                "content check skipped: no openai key"
            );
            return Verdict::Allow;
        };
        let input: String = text.chars().take(MAX_CHARS).collect();
        let response = self
            .http
            .post(MODERATION_URL)
            .bearer_auth(key)
            .json(&json!({ "model": MODERATION_MODEL, "input": input }))
            .send()
            .await;
        let body: Value = match response {
            Ok(r) if r.status().is_success() => r.json().await.unwrap_or_default(),
            Ok(r) => {
                tracing::warn!(status = %r.status(), "content check refused; allowing");
                return Verdict::Allow;
            }
            Err(error) => {
                tracing::warn!(%error, "content check failed; allowing");
                return Verdict::Allow;
            }
        };
        verdict(&body)
    }
}

/// The categories that stop a run: the ones about helping someone do harm,
/// not the ones about a subject. A flagged topic-level category alone
/// (violence, hate, harassment, sexual, self-harm as a subject) passes.
const STOPPING: [&str; 6] = [
    "illicit",
    "illicit/violent",
    "self-harm/instructions",
    "self-harm/intent",
    "sexual/minors",
    "harassment/threatening",
];

/// The endpoint's answer as a verdict.
pub fn verdict(body: &Value) -> Verdict {
    let result = &body["results"][0];
    if result["flagged"].as_bool() != Some(true) {
        return Verdict::Allow;
    }
    let hit = STOPPING
        .iter()
        .find(|c| result["categories"][**c].as_bool() == Some(true));
    match hit {
        Some(category) => Verdict::Refuse {
            category: category.to_string(),
            reply: reply_for(category),
        },
        None => Verdict::Allow,
    }
}

/// What the user is told: one line declining, and what is still on offer.
pub fn reply_for(category: &str) -> String {
    if category.starts_with("self-harm") {
        return "I can't help with that. If you're going through a hard time, you \
                don't have to face it alone: you can find someone to talk to, free \
                and confidential, at findahelpline.com. If this is for a class, I'm \
                glad to help with an essay on support, prevention or awareness."
            .to_string();
    }
    "I can't write that one. I'm glad to help with an essay that analyses or \
     explains the topic, or how to prevent the harm, instead."
        .to_string()
}

/// Records a refusal: who, where, which category. Not the text itself.
pub async fn log(db: &PgPool, user_id: Uuid, run_id: Option<Uuid>, stage: Stage, category: &str) {
    let saved = sqlx::query(
        "INSERT INTO safety_events (user_id, run_id, stage, category) VALUES ($1, $2, $3, $4)",
    )
    .bind(user_id)
    .bind(run_id)
    .bind(stage.as_str())
    .bind(category)
    .execute(db)
    .await;
    if let Err(error) = saved {
        tracing::error!(%error, "could not log a content refusal");
    }
    tracing::info!(%user_id, ?run_id, stage = stage.as_str(), category, "content refused");
}

#[cfg(test)]
mod tests {
    use super::*;

    fn answer(flagged: bool, categories: Value) -> Value {
        json!({ "results": [{ "flagged": flagged, "categories": categories }] })
    }

    #[test]
    fn a_subject_alone_passes() {
        let body = answer(true, json!({ "violence": true, "illicit": false }));
        assert_eq!(verdict(&body), Verdict::Allow);
        assert_eq!(verdict(&answer(false, json!({}))), Verdict::Allow);
        assert_eq!(verdict(&json!({})), Verdict::Allow, "unreadable: fail open");
    }

    #[test]
    fn helping_someone_do_it_stops() {
        let body = answer(true, json!({ "violence": true, "illicit": true }));
        let Verdict::Refuse { category, reply } = verdict(&body) else {
            panic!("should refuse");
        };
        assert_eq!(category, "illicit");
        assert!(reply.contains("instead"));
    }

    #[test]
    fn self_harm_gets_support() {
        let body = answer(true, json!({ "self-harm/intent": true }));
        let Verdict::Refuse { reply, .. } = verdict(&body) else {
            panic!("should refuse");
        };
        assert!(reply.contains("findahelpline.com"));
    }
}

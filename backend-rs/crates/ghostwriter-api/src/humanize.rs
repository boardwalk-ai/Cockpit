//! The humanizer services, behind a trait so tests need no network.
//!
//! A port of OctopilotWeb's `tools/humanize.ts`: StealthGPT answers in one
//! call; UndetectableAI takes the text and is polled for the result. Their
//! keys live in the shared DB's `system_settings`, as on the web.

use std::time::Duration;

use axum::async_trait;
use serde_json::{json, Value};
use sqlx::PgPool;

const STEALTHGPT_URL: &str = "https://www.stealthgpt.ai/api/stealthify";
const UNDETECTABLE_SUBMIT_URL: &str = "https://humanize.undetectable.ai/submit";
const UNDETECTABLE_DOCUMENT_URL: &str = "https://humanize.undetectable.ai/document";

/// How often, and how many times, UndetectableAI is asked for the result.
const POLL_EVERY: Duration = Duration::from_secs(2);
const POLL_ATTEMPTS: usize = 12;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Provider {
    StealthGpt,
    Undetectable,
}

impl Provider {
    /// Reads the provider from what the model or the user said.
    pub fn parse(text: &str) -> Option<Self> {
        match text
            .trim()
            .to_lowercase()
            .replace([' ', '-', '_'], "")
            .as_str()
        {
            "stealthgpt" | "stealth" => Some(Self::StealthGpt),
            "undetectableai" | "undetectable" => Some(Self::Undetectable),
            _ => None,
        }
    }

    /// The name users see.
    pub fn label(self) -> &'static str {
        match self {
            Self::StealthGpt => "StealthGPT",
            Self::Undetectable => "UndetectableAI",
        }
    }

    fn key_setting(self) -> &'static str {
        match self {
            Self::StealthGpt => "stealthgpt_api_key",
            Self::Undetectable => "undetectable_api_key",
        }
    }
}

#[async_trait]
pub trait Humanizer: Send + Sync {
    /// The text, rewritten by the provider. Errors are safe to show the user.
    async fn humanize(&self, provider: Provider, text: &str) -> Result<String, String>;
}

pub struct HttpHumanizer {
    http: reqwest::Client,
    /// The shared DB, where the providers' keys are kept.
    settings: Option<PgPool>,
}

impl HttpHumanizer {
    pub fn new(http: reqwest::Client, settings: Option<PgPool>) -> Self {
        Self { http, settings }
    }

    async fn key(&self, provider: Provider) -> Result<String, String> {
        let unavailable = || format!("{} is not available right now.", provider.label());
        let pool = self.settings.as_ref().ok_or_else(unavailable)?;
        octo_common::llm::setting(pool, provider.key_setting())
            .await
            .ok_or_else(unavailable)
    }

    async fn stealth_gpt(&self, key: &str, text: &str) -> Result<String, String> {
        let response = self
            .http
            .post(STEALTHGPT_URL)
            .header("api-token", key)
            .timeout(Duration::from_secs(150))
            .json(&json!({
                "prompt": text,
                "rephrase": false,
                "tone": "Standard",
                "mode": "Medium",
                "detector": "GPTZero",
            }))
            .send()
            .await
            .map_err(|e| format!("StealthGPT did not answer: {e}"))?;
        let status = response.status();
        if !status.is_success() {
            return Err(format!("StealthGPT refused the request ({status})."));
        }
        let body: Value = response
            .json()
            .await
            .map_err(|_| "StealthGPT sent an unreadable reply.".to_string())?;
        result_text(&body["result"]).ok_or_else(|| "StealthGPT returned nothing.".to_string())
    }

    async fn undetectable(&self, key: &str, text: &str) -> Result<String, String> {
        let response = self
            .http
            .post(UNDETECTABLE_SUBMIT_URL)
            .header("apikey", key)
            .timeout(Duration::from_secs(60))
            .json(&json!({
                "content": text,
                "readability": "University",
                "purpose": "Essay",
                "strength": "More Human",
                "model": "v11",
            }))
            .send()
            .await
            .map_err(|e| format!("UndetectableAI did not answer: {e}"))?;
        let status = response.status();
        if !status.is_success() {
            return Err(format!("UndetectableAI refused the request ({status})."));
        }
        let submitted: Value = response
            .json()
            .await
            .map_err(|_| "UndetectableAI sent an unreadable reply.".to_string())?;
        if let Some(output) = result_text(&submitted["output"]) {
            return Ok(output);
        }

        // The id may come back as a string or a number.
        let id = [&submitted["id"], &submitted["documentId"]]
            .into_iter()
            .find_map(|v| match v {
                Value::String(s) if !s.is_empty() => Some(s.clone()),
                Value::Number(n) => Some(n.to_string()),
                _ => None,
            })
            .ok_or("UndetectableAI did not accept the essay.")?;

        for attempt in 0..POLL_ATTEMPTS {
            if attempt > 0 {
                tokio::time::sleep(POLL_EVERY).await;
            }
            let Ok(response) = self
                .http
                .post(UNDETECTABLE_DOCUMENT_URL)
                .header("apikey", key)
                .timeout(Duration::from_secs(30))
                .json(&json!({ "id": id }))
                .send()
                .await
            else {
                continue;
            };
            if !response.status().is_success() {
                continue;
            }
            if let Ok(document) = response.json::<Value>().await {
                if let Some(output) = result_text(&document["output"]) {
                    return Ok(output);
                }
            }
        }
        Err("UndetectableAI is still working on it. Please try again in a moment.".to_string())
    }
}

fn result_text(value: &Value) -> Option<String> {
    value
        .as_str()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
}

#[async_trait]
impl Humanizer for HttpHumanizer {
    async fn humanize(&self, provider: Provider, text: &str) -> Result<String, String> {
        let key = self.key(provider).await?;
        match provider {
            Provider::StealthGpt => self.stealth_gpt(&key, text).await,
            Provider::Undetectable => self.undetectable(&key, text).await,
        }
    }
}

/// The paragraphs of an essay body: blocks separated by a blank line.
pub fn paragraphs(body: &str) -> Vec<&str> {
    body.split("\n\n")
        .map(str::trim)
        .filter(|p| !p.is_empty())
        .collect()
}

/// True when `a` and `b` are the same words in the same order, whatever the
/// spacing and line breaks.
pub fn same_wording(a: &str, b: &str) -> bool {
    a.split_whitespace().eq(b.split_whitespace())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_provider_however_it_is_written() {
        assert_eq!(Provider::parse("StealthGPT"), Some(Provider::StealthGpt));
        assert_eq!(Provider::parse(" stealth gpt "), Some(Provider::StealthGpt));
        assert_eq!(
            Provider::parse("UndetectableAI"),
            Some(Provider::Undetectable)
        );
        assert_eq!(
            Provider::parse("undetectable-ai"),
            Some(Provider::Undetectable)
        );
        assert_eq!(Provider::parse("Skip"), None);
        assert_eq!(Provider::parse(""), None);
    }

    #[test]
    fn counts_paragraphs_by_blank_lines() {
        assert_eq!(
            paragraphs("One.\n\nTwo.\n\n\n\nThree.\n"),
            ["One.", "Two.", "Three."]
        );
        assert_eq!(
            paragraphs("One line.\nStill one."),
            ["One line.\nStill one."]
        );
        assert!(paragraphs("  \n\n ").is_empty());
    }

    #[test]
    fn same_wording_ignores_only_spacing() {
        assert!(same_wording("One two.\n\nThree.", "One  two. Three."));
        assert!(!same_wording("One two three.", "One two, three."));
        assert!(!same_wording("One two.", "One two. Three."));
    }
}

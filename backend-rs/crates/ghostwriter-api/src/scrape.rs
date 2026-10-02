//! Fetching a source's text, behind a trait so tests need no network.

use std::time::Duration;

use axum::async_trait;
use serde_json::Value;

#[derive(Clone, Debug, Default)]
pub struct Scraped {
    pub title: Option<String>,
    pub publisher: Option<String>,
    pub content: String,
}

#[async_trait]
pub trait Scraper: Send + Sync {
    async fn fetch(&self, url: &str) -> Result<Scraped, String>;
}

/// The Octopilot scraper service (`GET <base>?url=…`).
pub struct HttpScraper {
    http: reqwest::Client,
    base: String,
}

impl HttpScraper {
    pub fn new(http: reqwest::Client, base: impl Into<String>) -> Self {
        Self {
            http,
            base: base.into(),
        }
    }
}

fn text(value: &Value) -> Option<String> {
    value
        .as_str()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
}

#[async_trait]
impl Scraper for HttpScraper {
    async fn fetch(&self, url: &str) -> Result<Scraped, String> {
        let response = self
            .http
            .get(&self.base)
            .query(&[("url", url)])
            .header("Accept", "application/json")
            .timeout(Duration::from_secs(15))
            .send()
            .await
            .map_err(|e| format!("scrape failed: {e}"))?;
        if !response.status().is_success() {
            return Err(format!("scrape failed: {}", response.status()));
        }
        let body: Value = response
            .json()
            .await
            .map_err(|e| format!("scrape reply unreadable: {e}"))?;

        // v2 wraps the page in `references[0]`; v1 put the fields at the top.
        let page = body["references"].get(0).unwrap_or(&body);
        let content = text(&page["rawContent"])
            .or_else(|| text(&page["fullContent"]))
            .ok_or("scrape returned no text")?;
        Ok(Scraped {
            title: text(&page["title"]),
            publisher: text(&page["publisher"]).or_else(|| text(&page["source"])),
            content,
        })
    }
}

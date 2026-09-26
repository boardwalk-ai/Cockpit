//! Source search + scrape — a port of the web `searchAndScrape`. OpenRouter
//! (the Alvin prompt) proposes candidate URLs; each is scraped through the
//! upstream scraper and kept only if it yields real content. Non-streaming: the
//! full list is returned (matches the Flutter `ToolsService.searchSources`).

use std::collections::HashSet;

use axum::extract::{Query, State};
use axum::Json;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::db;
use crate::error::ApiError;
use crate::openrouter::{call_json, parse_json_loose, ChatMessage};
use crate::AppState;

const ALVIN_PROMPT: &str = include_str!("../prompts/alvin.md");
const MAX_ROUNDS: usize = 5;

// ── DTOs (camelCase → Flutter `Source`) ──────────────────────────────────────
#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct GoodSource {
    pub url: String,
    pub title: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub author: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub published_year: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub publisher: Option<String>,
    pub full_content: String,
}

#[derive(Deserialize)]
pub struct OutlineInput {
    #[serde(rename = "type")]
    pub kind: Option<String>,
    pub title: String,
    pub description: Option<String>,
}

#[derive(Deserialize)]
pub struct SearchBody {
    pub topic: String,
    #[serde(default)]
    pub outlines: Vec<OutlineInput>,
    pub target_count: Option<usize>,
    /// Keyword mode override — appended as the topic when provided.
    pub keyword: Option<String>,
}

// ── GET /v1/scrape?url= ──────────────────────────────────────────────────────
#[derive(Deserialize)]
pub struct ScrapeQuery {
    pub url: String,
}

pub async fn scrape(
    State(st): State<AppState>,
    Query(q): Query<ScrapeQuery>,
) -> Result<Json<GoodSource>, ApiError> {
    let scraped = scrape_url(&st, &q.url).await?;
    if scraped.full_content.trim().is_empty() {
        return Err(ApiError::not_found("page had no scrapable content"));
    }
    Ok(Json(GoodSource {
        url: q.url,
        title: scraped.title.unwrap_or_default(),
        author: None,
        published_year: None,
        publisher: scraped.publisher,
        full_content: scraped.full_content,
    }))
}

// ── POST /v1/sources/search ──────────────────────────────────────────────────
pub async fn search(
    State(st): State<AppState>,
    Json(body): Json<SearchBody>,
) -> Result<Json<Vec<GoodSource>>, ApiError> {
    let api_key = db::openrouter_key(&st.db).await?;
    let model = db::model(&st.db, "primary_model", &st.config.openrouter_model).await;
    let topic = match &body.keyword {
        Some(k) if !k.trim().is_empty() => k.trim().to_string(),
        _ => body.topic.trim().to_string(),
    };
    if topic.is_empty() {
        return Err(ApiError::bad_request("missing topic/keyword"));
    }
    let target = body.target_count.unwrap_or(12).clamp(1, 30);

    let mut found: Vec<GoodSource> = Vec::new();
    let mut used: HashSet<String> = HashSet::new();

    for round in 0..MAX_ROUNDS {
        if found.len() >= target {
            break;
        }
        let needed = target - found.len();
        let request_count = (needed * 2).clamp(10, 30);
        let refinement = (round > 0).then(|| {
            format!(
                "Previous rounds found {} good sources. Find {needed} more from \
                 DIFFERENT publishers, domains, and authors than before.",
                found.len()
            )
        });

        let candidates = match fetch_candidates(
            &st,
            &api_key,
            &model,
            &topic,
            &body.outlines,
            request_count,
            refinement,
        )
        .await
        {
            Ok(c) => c,
            Err(e) if round == 0 => return Err(e), // first round failure is fatal
            Err(_) => break,
        };

        let fresh: Vec<Value> = candidates
            .into_iter()
            .filter(|row| match normalise_url(row) {
                Some(u) => used.insert(u),
                None => false,
            })
            .collect();
        if fresh.is_empty() {
            break;
        }

        for row in fresh {
            if found.len() >= target {
                break;
            }
            let url = normalise_url(&row).unwrap();
            if let Ok(scraped) = scrape_url(&st, &url).await {
                if scraped.full_content.trim().is_empty() {
                    continue;
                }
                found.push(GoodSource {
                    title: scraped
                        .title
                        .clone()
                        .filter(|t| !t.trim().is_empty())
                        .or_else(|| get_str(&row, &["Title", "title"]))
                        .unwrap_or_default(),
                    author: get_str(&row, &["Author", "author"]),
                    published_year: get_str(&row, &["Published Year", "publishedYear", "year"]),
                    publisher: scraped
                        .publisher
                        .or_else(|| get_str(&row, &["Publisher", "publisher", "source"])),
                    full_content: scraped.full_content,
                    url,
                });
            }
        }
    }

    Ok(Json(found))
}

async fn fetch_candidates(
    st: &AppState,
    api_key: &str,
    model: &str,
    topic: &str,
    outlines: &[OutlineInput],
    count: usize,
    refinement: Option<String>,
) -> Result<Vec<Value>, ApiError> {
    let outlines_json: Vec<Value> = outlines
        .iter()
        .map(|o| {
            serde_json::json!({
                "type": o.kind,
                "title": o.title,
                "description": o.description,
            })
        })
        .collect();

    let mut user = format!("Number of links needed: {count}\nEssay Topic: {topic}\n");
    if let Some(r) = refinement {
        user.push_str(&format!("Refinement: {r}\n"));
    }
    user.push_str("\nSupporting Outlines:\n");
    user.push_str(&serde_json::to_string_pretty(&outlines_json).unwrap_or_default());

    let raw = call_json(
        &st.http,
        api_key,
        model,
        vec![
            ChatMessage {
                role: "system",
                content: ALVIN_PROMPT.to_string(),
            },
            ChatMessage {
                role: "user",
                content: user,
            },
        ],
        0.25,
    )
    .await?;

    let parsed = parse_json_loose(&raw).unwrap_or(Value::Null);
    let rows = match parsed {
        Value::Array(a) => a,
        Value::Object(ref o) => o
            .get("results")
            .and_then(|v| v.as_array())
            .cloned()
            .or_else(|| o.values().find_map(|v| v.as_array().cloned()))
            .unwrap_or_default(),
        _ => Vec::new(),
    };
    Ok(rows)
}

// ── upstream scraper ─────────────────────────────────────────────────────────
struct Scraped {
    title: Option<String>,
    publisher: Option<String>,
    full_content: String,
}

#[derive(Deserialize)]
struct UpstreamRef {
    title: Option<String>,
    source: Option<String>,
    publisher: Option<String>,
    #[serde(rename = "rawContent")]
    raw_content: Option<String>,
    #[serde(rename = "fullContent")]
    full_content: Option<String>,
}
#[derive(Deserialize)]
struct UpstreamResponse {
    #[serde(default)]
    references: Vec<UpstreamRef>,
    title: Option<String>,
    publisher: Option<String>,
    #[serde(rename = "fullContent")]
    full_content: Option<String>,
}

async fn scrape_url(st: &AppState, url: &str) -> Result<Scraped, ApiError> {
    let endpoint = format!(
        "{}?url={}",
        st.config.upstream_scraper,
        urlencoding::encode(url)
    );
    let resp = st
        .http
        .get(endpoint)
        .header("Accept", "application/json")
        .send()
        .await?
        .error_for_status()?;
    let data: UpstreamResponse = resp.json().await?;

    if let Some(r) = data.references.into_iter().next() {
        return Ok(Scraped {
            title: r.title,
            publisher: r.publisher.or(r.source),
            full_content: r.raw_content.or(r.full_content).unwrap_or_default(),
        });
    }
    Ok(Scraped {
        title: data.title,
        publisher: data.publisher,
        full_content: data.full_content.unwrap_or_default(),
    })
}

// ── helpers ──────────────────────────────────────────────────────────────────
fn get_str(v: &Value, keys: &[&str]) -> Option<String> {
    for k in keys {
        if let Some(s) = v.get(*k).and_then(|x| x.as_str()) {
            let t = s.trim();
            if !t.is_empty() {
                return Some(t.to_string());
            }
        }
    }
    None
}

fn normalise_url(row: &Value) -> Option<String> {
    let raw = get_str(row, &["website_URL", "url", "link"])?;
    let lower = raw.to_lowercase();
    if !(lower.starts_with("http://") || lower.starts_with("https://")) {
        return None;
    }
    if lower.contains(".pdf") {
        return None;
    }
    Some(lower)
}

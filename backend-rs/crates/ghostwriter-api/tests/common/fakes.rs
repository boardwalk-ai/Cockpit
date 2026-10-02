//! Test doubles for the model and the scraper, so the agent loop runs with no
//! network and the same result every time.

use std::collections::VecDeque;
use std::sync::{Arc, Mutex};

use axum::async_trait;
use futures::StreamExt;
use ghostwriter_api::llm::{ChatReply, ChatRequest, Llm, TextStream, ToolCall};
use ghostwriter_api::scrape::{Scraped, Scraper};
use serde_json::{json, Value};
use tokio::sync::Notify;

pub const ESSAY: &str = "Coastal cities live by the tide (Sweet, 2022).\n\n\
    Rising seas raise every ordinary high tide (Hino, 2017).\n\n\
    The cities that cope will plan for the tide to come.";
pub const BIBLIOGRAPHY: &str = "Sweet, W. (2022). Sea level rise scenarios. NOAA.\n\
    Hino, M. (2017). Managed retreat. Nature Climate Change.";

/// One orchestrator turn: what the model says and which tools it calls.
pub fn turn(content: &str, calls: &[(&str, Value)]) -> ChatReply {
    ChatReply {
        content: content.to_string(),
        tool_calls: calls
            .iter()
            .enumerate()
            .map(|(index, (name, args))| ToolCall {
                id: format!("call_{name}_{index}"),
                name: name.to_string(),
                arguments: args.to_string(),
            })
            .collect(),
    }
}

/// A turn that calls one tool and says nothing.
pub fn call(name: &str, args: Value) -> ChatReply {
    turn("", &[(name, args)])
}

/// A turn that asks the user through `ask_user`.
pub fn ask(field: &str, args: Value) -> ChatReply {
    let mut args = args;
    args["field"] = json!(field);
    if args.get("question").is_none() {
        args["question"] = json!(format!("{field}?"));
    }
    call("ask_user", args)
}

/// The turns of a whole essay, start to finish.
pub fn full_script() -> Vec<ChatReply> {
    vec![
        call("plan_essay", json!({})),
        ask(
            "essayFocus",
            json!({
                "question": "What should this essay focus on?",
                "inputType": "select", // the loop corrects this to multiselect
                "options": [
                    { "label": "Economic impact", "value": "Economic impact" },
                    { "label": "Policy responses", "value": "Policy responses" },
                    { "label": "", "value": "dropped: no label" },
                ],
            }),
        ),
        call(
            "generate_outlines",
            json!({ "count": 5, "selectedFocusAreas": ["Economic impact", "Policy responses"] }),
        ),
        call("search_sources", json!({ "count": 5 })),
        call("scrape_sources", json!({ "limit": 5 })),
        turn("Sources are in.", &[("compact_sources", json!({}))]),
        ask(
            "wordCount",
            json!({ "inputType": "number", "suggestions": ["500", "800", 1200] }),
        ),
        ask(
            "citationStyle",
            json!({ "inputType": "select", "suggestions": ["APA", "MLA"] }),
        ),
        call("write_essay", json!({})),
        ask("studentName", json!({ "inputType": "text" })),
        call("finalize_document", json!({})),
        turn("Your essay is ready in the editor.", &[]),
    ]
}

#[derive(Default)]
pub struct FakeLlm {
    /// The orchestrator's turns, in order.
    turns: Mutex<VecDeque<ChatReply>>,
    /// Every orchestrator request, for checking what the model was shown.
    pub orchestrator_requests: Mutex<Vec<ChatRequest>>,
    /// What the writer streams. Empty string = the writer returns nothing.
    pub essay_output: Mutex<String>,
    /// If set, the writer stream waits here after its first chunk.
    pub hold_writer: Option<Arc<Notify>>,
}

impl FakeLlm {
    pub fn new(turns: Vec<ChatReply>) -> Self {
        Self {
            turns: Mutex::new(turns.into()),
            essay_output: Mutex::new(format!("{ESSAY}\n===BIBLIOGRAPHY===\n{BIBLIOGRAPHY}")),
            ..Self::default()
        }
    }

    /// The text of every message the orchestrator was last shown.
    pub fn last_transcript(&self) -> String {
        self.orchestrator_requests
            .lock()
            .unwrap()
            .last()
            .map(|request| json!(request.messages).to_string())
            .unwrap_or_default()
    }

    fn sub_agent(system: &str) -> Value {
        if system.contains("planning sub-agent") {
            json!({
                "essayTopic": "Rising Tides and Coastal Cities",
                "essayType": "Analytical",
                "thesis": "Coastal cities must plan for higher tides.",
                "paragraphCount": 5,
                "searchQueries": ["sea level rise cities", "managed retreat"],
                "notes": "Keep it concrete.",
                "essayFocusOptions": ["Economic impact", "Policy responses", "History"],
            })
        } else if system.contains("Lily") {
            json!({ "outlines": [
                { "type": "Introduction", "title": "The tide line moves", "description": "Set the scene." },
                { "type": "body paragraph", "title": "Why seas rise", "description": "Causes." },
                { "type": "Body Paragraph", "title": "What it costs", "description": "Economics." },
                { "type": "Something else", "title": "What cities do", "description": "Policy." },
                { "type": "CONCLUSION", "title": "Plan ahead", "description": "Wrap up." },
            ]})
        } else if system.contains("Alvin") {
            json!([
                { "website_URL": "https://noaa.example/slr", "Title": "Sea level rise", "Author": "Sweet, W.", "Published Year": "2022", "Publisher": "NOAA" },
                { "url": "https://nature.example/retreat", "title": "Managed retreat", "author": "Hino, M.", "year": "2017", "source": "Nature" },
                { "website_URL": "https://dead.example/gone", "Title": "A dead link" },
                { "website_URL": "https://city.example/plan", "Title": "A city plan" },
                { "website_URL": "https://noaa.example/report.pdf", "Title": "A PDF, skipped" },
                { "website_URL": "HTTPS://NOAA.example/slr", "Title": "A duplicate, skipped" },
                { "website_URL": "ftp://files.example/x", "Title": "Not a web page, skipped" },
            ])
        } else if system.contains("SOURCE_COMPACTION") {
            json!({
                "compacted_content": "Seas are rising.",
                "key_points": ["Faster since 1993"],
                "relevant_quotes": ["\"Flooding is routine.\""],
            })
        } else {
            json!({ "error": "FakeLlm does not know this sub-agent" })
        }
    }
}

#[async_trait]
impl Llm for FakeLlm {
    async fn chat(&self, request: ChatRequest) -> Result<ChatReply, String> {
        if request.tools.is_empty() {
            let system = request.messages[0]["content"].as_str().unwrap_or_default();
            return Ok(ChatReply {
                content: Self::sub_agent(system).to_string(),
                tool_calls: Vec::new(),
            });
        }
        self.orchestrator_requests.lock().unwrap().push(request);
        self.turns
            .lock()
            .unwrap()
            .pop_front()
            .ok_or_else(|| "FakeLlm ran out of scripted turns".to_string())
    }

    async fn stream(&self, _request: ChatRequest) -> Result<TextStream, String> {
        let output = self.essay_output.lock().unwrap().clone();
        let hold = self.hold_writer.clone();
        // Small chunks that split words and the marker, like a real stream.
        let chunks: Vec<String> = output
            .chars()
            .collect::<Vec<_>>()
            .chunks(7)
            .map(|c| c.iter().collect())
            .collect();
        Ok(async_stream::stream! {
            for (index, chunk) in chunks.into_iter().enumerate() {
                yield Ok(chunk);
                if index == 0 {
                    if let Some(hold) = &hold {
                        hold.notified().await;
                    }
                }
            }
        }
        .boxed())
    }
}

/// Serves two pages and fails everything else.
pub struct FakeScraper;

#[async_trait]
impl Scraper for FakeScraper {
    async fn fetch(&self, url: &str) -> Result<Scraped, String> {
        match url {
            "https://noaa.example/slr" => Ok(Scraped {
                title: Some("Global and Regional Sea Level Rise Scenarios".into()),
                publisher: Some("ignored: the search result already had one".into()),
                content: "Sea level along the coast is rising.".into(),
            }),
            "https://nature.example/retreat" => Ok(Scraped {
                title: None,
                publisher: None,
                content: "Managed retreat moves people away from risk.".into(),
            }),
            "https://city.example/plan" => Ok(Scraped {
                title: None,
                publisher: Some("City Hall".into()),
                content: "The city will raise its sea wall.".into(),
            }),
            _ => Err("scrape failed: 404".into()),
        }
    }
}

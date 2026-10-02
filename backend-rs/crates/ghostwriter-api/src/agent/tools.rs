//! The tools the orchestrator can call. Each reads and writes the run's
//! [`Context`](super::context::Context) and returns a short result for the
//! model plus a one-line summary for the user's timeline.
//!
//! `ask_user` is not here: the loop handles it, because it waits on the user
//! instead of doing work.

use std::time::{Duration, Instant};

use futures::StreamExt;
use octo_common::llm::parse_json_loose;
use serde_json::{json, Value};
use uuid::Uuid;

use super::context::{CompactedSource, Outline, ScrapedSource, Source};
use super::{prompt, Agent};
use crate::documents::{self, AgentSave, DocError};
use crate::llm::{system, user, ChatRequest};
use crate::pricing;
use crate::runs::driver::RunError;

/// A tool's reply to the model and its summary for the timeline.
type Done = (Value, String);

/// A tool failure. `Tool` goes back to the model, which may retry or tell the
/// user; `Run` ends the run.
pub enum Failure {
    Tool(String),
    Run(RunError),
}

impl From<String> for Failure {
    fn from(message: String) -> Self {
        Failure::Tool(message)
    }
}

impl From<&str> for Failure {
    fn from(message: &str) -> Self {
        Failure::Tool(message.to_string())
    }
}

impl From<RunError> for Failure {
    fn from(error: RunError) -> Self {
        Failure::Run(error)
    }
}

impl From<sqlx::Error> for Failure {
    fn from(error: sqlx::Error) -> Self {
        Failure::Run(RunError::Db(error))
    }
}

impl From<DocError> for Failure {
    fn from(error: DocError) -> Self {
        match error {
            DocError::Locked => Failure::Tool("the document is locked by another run".into()),
            DocError::Db(e) => Failure::Run(RunError::Db(e)),
        }
    }
}

fn function(name: &str, description: &str, parameters: Value) -> Value {
    json!({
        "type": "function",
        "function": { "name": name, "description": description, "parameters": parameters },
    })
}

/// The tool specs sent to the model.
pub fn specs() -> Vec<Value> {
    let none = json!({ "type": "object", "additionalProperties": false, "properties": {} });
    vec![
        function(
            "plan_essay",
            "Produce the essay plan (topic, type, thesis, search queries, focus options). Call this FIRST.",
            json!({
                "type": "object", "additionalProperties": false,
                "properties": { "notes": { "type": "string", "description": "Optional extra guidance for the planner." } },
            }),
        ),
        function(
            "ask_user",
            "Ask the user a question and wait for the answer. Use for word count, citation style, essay focus and title-page details. Keep the question short. Prefer `options` for choices.",
            json!({
                "type": "object", "additionalProperties": false, "required": ["field", "question"],
                "properties": {
                    "field": { "type": "string", "description": "Stable identifier, e.g. \"wordCount\", \"citationStyle\", \"essayFocus\", \"studentName\"." },
                    "question": { "type": "string" },
                    "options": {
                        "type": "array",
                        "items": {
                            "type": "object", "additionalProperties": false, "required": ["label", "value"],
                            "properties": { "label": { "type": "string" }, "value": { "type": "string" } },
                        },
                    },
                    "suggestions": { "type": "array", "items": { "type": "string" }, "description": "Quick-reply chips; the user may also type their own." },
                    "inputType": { "type": "string", "enum": ["text", "number", "select", "multiselect"] },
                    "allowCustom": { "type": "boolean" },
                },
            }),
        ),
        function(
            "generate_outlines",
            "Generate the paragraph outline: 1 Introduction + (count-2) Body Paragraphs + 1 Conclusion. Requires plan_essay first. Decide the count from the user's focus selection; never ask the user.",
            json!({
                "type": "object", "additionalProperties": false, "required": ["count"],
                "properties": {
                    "count": { "type": "integer", "minimum": 3, "maximum": 20 },
                    "selectedFocusAreas": { "type": "array", "items": { "type": "string" } },
                },
            }),
        ),
        function(
            "search_sources",
            "Propose citable sources for the essay from its topic and outlines. Call after generate_outlines. Call again with a `refinement` if the first batch is too narrow.",
            json!({
                "type": "object", "additionalProperties": false, "required": ["count"],
                "properties": {
                    "count": { "type": "integer", "minimum": 3, "maximum": 20 },
                    "refinement": { "type": "string" },
                },
            }),
        ),
        function(
            "scrape_sources",
            "Fetch the full text of the search results not yet fetched. Dead or paywalled URLs are dropped. Call after search_sources.",
            json!({
                "type": "object", "additionalProperties": false,
                "properties": {
                    "urls": { "type": "array", "items": { "type": "string" } },
                    "limit": { "type": "integer", "minimum": 1, "maximum": 30, "description": "Default 5." },
                },
            }),
        ),
        function(
            "compact_sources",
            "Summarise each fetched source into a short, quote-preserving brief the writer can cite. Call after scrape_sources and before write_essay.",
            json!({
                "type": "object", "additionalProperties": false,
                "properties": { "urls": { "type": "array", "items": { "type": "string" } } },
            }),
        ),
        function(
            "write_essay",
            "Draft the full essay and bibliography into the user's document. Needs outlines, compacted sources, wordCount and citationStyle.",
            json!({
                "type": "object", "additionalProperties": false,
                "properties": { "notes": { "type": "string", "description": "Optional writer guidance (tone, angle)." } },
            }),
        ),
        function(
            "finalize_document",
            "Put the collected title-page details on the document and deliver it. Call after write_essay and after the title-page questions.",
            none,
        ),
    ]
}

/// The line the user sees while the tool runs.
pub fn title(name: &str, args: &Value) -> String {
    match name {
        "plan_essay" => "Planning the essay".into(),
        "generate_outlines" => "Building the outline".into(),
        "search_sources" => "Searching for sources".into(),
        "scrape_sources" => "Reading the sources".into(),
        "compact_sources" => "Summarising the sources".into(),
        "write_essay" => "Writing the essay".into(),
        "finalize_document" => "Finishing the document".into(),
        other => {
            let _ = args;
            format!("Running {other}")
        }
    }
}

/// How long the tool may take.
pub fn time_limit(name: &str) -> Duration {
    Duration::from_secs(match name {
        "scrape_sources" => 180,
        "compact_sources" => 240,
        "write_essay" => 300,
        _ => 90,
    })
}

pub fn exists(name: &str) -> bool {
    matches!(
        name,
        "plan_essay"
            | "generate_outlines"
            | "search_sources"
            | "scrape_sources"
            | "compact_sources"
            | "write_essay"
            | "finalize_document"
    )
}

pub async fn execute(
    agent: &mut Agent<'_>,
    step_id: Uuid,
    name: &str,
    args: &Value,
) -> Result<Done, Failure> {
    match name {
        "plan_essay" => plan_essay(agent, args).await,
        "generate_outlines" => generate_outlines(agent, args).await,
        "search_sources" => search_sources(agent, args).await,
        "scrape_sources" => scrape_sources(agent, step_id, args).await,
        "compact_sources" => compact_sources(agent, step_id, args).await,
        "write_essay" => write_essay(agent, args).await,
        "finalize_document" => finalize_document(agent).await,
        other => Err(format!("unknown tool: {other}").into()),
    }
}

fn text_of(value: &Value) -> String {
    value.as_str().unwrap_or_default().trim().to_string()
}

fn optional(value: &Value) -> Option<String> {
    Some(text_of(value)).filter(|s| !s.is_empty())
}

fn strings(value: &Value, max: usize) -> Vec<String> {
    value
        .as_array()
        .map(|items| {
            items
                .iter()
                .map(text_of)
                .filter(|s| !s.is_empty())
                .take(max)
                .collect()
        })
        .unwrap_or_default()
}

/// One JSON-returning sub-agent call.
async fn ask_json(
    agent: &Agent<'_>,
    model: &str,
    system_prompt: &str,
    user_message: String,
    temperature: f32,
    json_mode: bool,
) -> Result<Value, Failure> {
    let reply = agent
        .llm
        .chat(ChatRequest {
            model: model.to_string(),
            messages: vec![system(system_prompt), user(user_message)],
            temperature: Some(temperature),
            json: json_mode,
            tools: Vec::new(),
        })
        .await?;
    parse_json_loose(&reply.content).ok_or_else(|| "the model did not return JSON".into())
}

async fn plan_essay(agent: &mut Agent<'_>, args: &Value) -> Result<Done, Failure> {
    let instruction = agent.ctx.instruction.trim().to_string();
    if instruction.is_empty() {
        return Err("no instruction was provided".into());
    }
    let mut message = format!("User instruction:\n{instruction}");
    if let Some(notes) = optional(&args["notes"]) {
        message.push_str(&format!("\n\nOrchestrator notes:\n{notes}"));
    }

    let plan = ask_json(
        agent,
        &agent.models.orchestrator,
        prompt::PLANNER,
        message,
        0.3,
        true,
    )
    .await?;

    let topic = optional(&plan["essayTopic"]).unwrap_or_else(|| "Untitled topic".into());
    let essay_type = optional(&plan["essayType"]).unwrap_or_else(|| "Essay".into());
    let thesis = text_of(&plan["thesis"]);
    let paragraph_count = plan["paragraphCount"].as_i64().unwrap_or(5).clamp(3, 12);
    let search_queries = strings(&plan["searchQueries"], 6);
    let focus_options = strings(&plan["essayFocusOptions"], 8);

    agent.ctx.essay_topic = Some(topic.clone());
    agent.ctx.essay_type = Some(essay_type.clone());
    agent.ctx.thesis = Some(thesis.clone());
    agent.ctx.plan_notes = optional(&plan["notes"]);
    agent.ctx.search_queries = search_queries.clone();
    agent.ctx.focus_options = focus_options.clone();

    // The project takes the topic as its name.
    sqlx::query("UPDATE projects SET title = left($2, 200), updated_at = now() WHERE id = $1")
        .bind(agent.run.project_id)
        .bind(&topic)
        .execute(&agent.run.st.db)
        .await?;
    agent
        .run
        .emit(
            "context_update",
            json!({ "essayTopic": topic, "essayType": essay_type, "thesis": thesis }),
        )
        .await?;

    Ok((
        json!({
            "essayTopic": topic,
            "essayType": essay_type,
            "plan": {
                "thesis": thesis,
                "paragraphCount": paragraph_count,
                "searchQueries": search_queries,
                "notes": agent.ctx.plan_notes,
                "essayFocusOptions": focus_options,
            },
        }),
        topic,
    ))
}

async fn generate_outlines(agent: &mut Agent<'_>, args: &Value) -> Result<Done, Failure> {
    let Some(topic) = agent.ctx.essay_topic.clone() else {
        return Err("call plan_essay first (the essay topic is missing)".into());
    };
    let total = args["count"].as_i64().unwrap_or(5).clamp(3, 20) as usize;
    let focus = strings(&args["selectedFocusAreas"], 12);
    if agent.ctx.focus.is_empty() {
        agent.ctx.focus = focus.clone();
    }

    let mut message = format!(
        "Essay Topic: {topic}\nEssay Type: {}\n\nPlan:\nThesis: {}\nParagraph count: {total}",
        agent.ctx.essay_type.as_deref().unwrap_or("Essay"),
        agent.ctx.thesis.as_deref().unwrap_or(""),
    );
    if let Some(notes) = &agent.ctx.plan_notes {
        message.push_str(&format!("\nPlanner notes: {notes}"));
    }
    if !focus.is_empty() {
        message.push_str("\n\nUser's selected focus areas (ensure the outline covers these):");
        for area in &focus {
            message.push_str(&format!("\n- {area}"));
        }
    }
    message.push_str(&format!("\n\nUser Instruction:\n{}", agent.ctx.instruction));

    let reply = ask_json(
        agent,
        &agent.models.orchestrator,
        &prompt::outliner(total),
        message,
        0.5,
        true,
    )
    .await?;

    let outlines: Vec<Outline> = reply["outlines"]
        .as_array()
        .map(|items| {
            items
                .iter()
                .map(|item| Outline {
                    kind: match text_of(&item["type"]).to_lowercase().as_str() {
                        "introduction" => "Introduction",
                        "conclusion" => "Conclusion",
                        _ => "Body Paragraph",
                    }
                    .to_string(),
                    title: text_of(&item["title"]),
                    description: text_of(&item["description"]),
                })
                .collect()
        })
        .unwrap_or_default();
    if outlines.is_empty() {
        return Err("the model returned no outlines".into());
    }

    agent.ctx.outlines = outlines.clone();
    agent
        .run
        .emit("context_update", json!({ "outlines": outlines }))
        .await?;

    let summary = format!("{} paragraphs outlined.", outlines.len());
    let brief: Vec<Value> = outlines
        .iter()
        .map(|o| json!({ "type": o.kind, "title": o.title }))
        .collect();
    Ok((json!({ "outlines": brief }), summary))
}

async fn search_sources(agent: &mut Agent<'_>, args: &Value) -> Result<Done, Failure> {
    let Some(topic) = agent.ctx.essay_topic.clone() else {
        return Err("call plan_essay and generate_outlines first".into());
    };
    if agent.ctx.outlines.is_empty() {
        return Err("call generate_outlines first".into());
    }
    let target = args["count"].as_i64().unwrap_or(8).clamp(3, 20) as usize;

    let mut message = format!("Number of links needed: {target}\nEssay Topic: {topic}");
    if let Some(refinement) = optional(&args["refinement"]) {
        message.push_str(&format!("\nRefinement: {refinement}"));
    }
    message.push_str("\n\nSupporting Outlines:\n");
    message.push_str(&serde_json::to_string_pretty(&agent.ctx.outlines).unwrap_or_default());

    let reply = ask_json(
        agent,
        &agent.models.search,
        prompt::SEARCHER,
        message,
        0.2,
        false,
    )
    .await?;

    // An array, or an object holding one.
    let rows: Vec<Value> = match &reply {
        Value::Array(rows) => rows.clone(),
        Value::Object(map) => map
            .values()
            .find_map(|v| v.as_array().cloned())
            .unwrap_or_default(),
        _ => Vec::new(),
    };

    let known = |agent: &Agent<'_>, url: &str| {
        agent
            .ctx
            .search_results
            .iter()
            .any(|s| s.url.eq_ignore_ascii_case(url))
    };
    let first = |row: &Value, keys: &[&str]| keys.iter().find_map(|k| optional(&row[*k]));

    let mut added: Vec<Source> = Vec::new();
    for row in &rows {
        let Some(url) = first(row, &["website_URL", "url", "link"]) else {
            continue;
        };
        let lower = url.to_lowercase();
        let is_web_page = lower.starts_with("http://") || lower.starts_with("https://");
        let is_pdf = lower
            .split('?')
            .next()
            .is_some_and(|path| path.ends_with(".pdf"));
        if !is_web_page || is_pdf || known(agent, &url) {
            continue;
        }
        if added.iter().any(|s| s.url.eq_ignore_ascii_case(&url)) {
            continue;
        }
        added.push(Source {
            url,
            title: first(row, &["Title", "title"]).unwrap_or_default(),
            author: first(row, &["Author", "author"]),
            published_year: first(row, &["Published Year", "publishedYear", "year"]),
            publisher: first(row, &["Publisher", "publisher", "source"]),
        });
        if added.len() >= target {
            break;
        }
    }
    if added.is_empty() {
        return Err("no new sources were found; try a different refinement".into());
    }

    agent.ctx.search_results.extend(added.clone());
    let summary = format!("{} sources found.", added.len());
    let brief: Vec<Value> = added
        .iter()
        .map(|s| json!({ "url": s.url, "title": s.title }))
        .collect();
    Ok((
        json!({ "added": brief, "totalInContext": agent.ctx.search_results.len() }),
        summary,
    ))
}

/// Checks the user can afford `amount`. Skipped when charging is off.
async fn precheck(agent: &Agent<'_>, amount: i32) -> Result<(), Failure> {
    let credits = &agent.run.st.credits;
    if !credits.active() {
        return Ok(());
    }
    credits
        .precheck(agent.run.user_id, amount)
        .await
        .map_err(|e| Failure::Tool(format!("Not enough OctoCredits: {}", e.message)))
}

/// Charges OctoCredits and tells the client the new balance. A charge that
/// fails after the work is done is logged, not surfaced: the user has the work.
async fn charge(agent: &Agent<'_>, amount: i32, action: &str, reason: &str) -> Result<(), Failure> {
    let credits = &agent.run.st.credits;
    if !credits.active() {
        return Ok(());
    }
    let source_ref = format!("ghostwriter:{action}:{}", agent.run.run_id);
    match credits
        .charge(
            agent.run.user_id,
            amount,
            &source_ref,
            reason,
            json!({ "runId": agent.run.run_id, "projectId": agent.run.project_id }),
        )
        .await
    {
        Ok(outcome) if outcome.charged => {
            agent
                .run
                .emit(
                    "credits",
                    json!({ "charged": outcome.amount, "balance": outcome.balance, "reason": reason }),
                )
                .await?;
        }
        Ok(_) => {}
        Err(error) => {
            tracing::error!(run_id = %agent.run.run_id, error = %error.message, "charge failed")
        }
    }
    Ok(())
}

/// Characters of a source kept for the compactor.
const SOURCE_TEXT_LIMIT: usize = 30_000;

async fn scrape_sources(
    agent: &mut Agent<'_>,
    step_id: Uuid,
    args: &Value,
) -> Result<Done, Failure> {
    let limit = args["limit"].as_i64().unwrap_or(5).clamp(1, 30) as usize;
    let scraped = |agent: &Agent<'_>, url: &str| {
        agent
            .ctx
            .scraped
            .iter()
            .any(|s| s.source.url.eq_ignore_ascii_case(url))
    };

    let explicit = strings(&args["urls"], 30);
    let candidates: Vec<Source> = if explicit.is_empty() {
        agent.ctx.search_results.clone()
    } else {
        explicit
            .into_iter()
            .map(|url| {
                agent
                    .ctx
                    .search_results
                    .iter()
                    .find(|s| s.url.eq_ignore_ascii_case(&url))
                    .cloned()
                    .unwrap_or(Source {
                        url,
                        ..Source::default()
                    })
            })
            .collect()
    };
    let targets: Vec<Source> = candidates
        .into_iter()
        .filter(|s| !scraped(agent, &s.url))
        .take(limit)
        .collect();
    if targets.is_empty() {
        return Ok((
            json!({ "scraped": 0, "failed": 0, "totalInContext": agent.ctx.scraped.len() }),
            "Nothing new to read.".into(),
        ));
    }

    precheck(agent, pricing::charge(0, 0, targets.len() as i64)).await?;

    let (mut read, mut failed) = (0, 0);
    for (index, target) in targets.iter().enumerate() {
        agent
            .run
            .emit(
                "step_progress",
                json!({ "stepId": step_id, "detail": format!("Reading {} of {}", index + 1, targets.len()) }),
            )
            .await?;
        match agent.scraper.fetch(&target.url).await {
            Ok(page) if !page.content.trim().is_empty() => {
                let mut source = target.clone();
                if let Some(title) = page.title {
                    source.title = title;
                }
                if source.publisher.is_none() {
                    source.publisher = page.publisher;
                }
                agent.ctx.scraped.push(ScrapedSource {
                    source,
                    full_content: page.content.chars().take(SOURCE_TEXT_LIMIT).collect(),
                });
                read += 1;
            }
            _ => failed += 1,
        }
    }

    if read > 0 {
        let total = agent.ctx.scraped.len();
        charge(
            agent,
            pricing::charge(0, 0, read),
            &format!("sources:{total}"),
            "Source research",
        )
        .await?;
    }

    Ok((
        json!({ "scraped": read, "failed": failed, "totalInContext": agent.ctx.scraped.len() }),
        format!("{read} sources read."),
    ))
}

async fn compact_sources(
    agent: &mut Agent<'_>,
    step_id: Uuid,
    args: &Value,
) -> Result<Done, Failure> {
    let selected = strings(&args["urls"], 30);
    let targets: Vec<ScrapedSource> = agent
        .ctx
        .scraped
        .iter()
        .filter(|s| {
            let url = &s.source.url;
            let done = agent
                .ctx
                .compacted
                .iter()
                .any(|c| c.source.url.eq_ignore_ascii_case(url));
            let wanted =
                selected.is_empty() || selected.iter().any(|u| u.eq_ignore_ascii_case(url));
            !done && wanted
        })
        .cloned()
        .collect();

    let (mut compacted, mut failed) = (0, 0);
    for (index, target) in targets.iter().enumerate() {
        agent
            .run
            .emit(
                "step_progress",
                json!({ "stepId": step_id, "detail": format!("Summarising {} of {}", index + 1, targets.len()) }),
            )
            .await?;
        let message = format!(
            "Task: SOURCE_COMPACTION\nSource Type: web\nSource Title: {}\n\nFull Content:\n{}",
            if target.source.title.is_empty() {
                "Untitled"
            } else {
                &target.source.title
            },
            target.full_content,
        );
        let reply = ask_json(
            agent,
            &agent.models.secondary,
            prompt::COMPACTOR,
            message,
            0.2,
            true,
        )
        .await;
        let summary = match reply {
            Ok(reply) => compaction_summary(&reply),
            Err(Failure::Run(error)) => return Err(Failure::Run(error)),
            Err(Failure::Tool(_)) => String::new(),
        };
        if summary.is_empty() {
            failed += 1;
            continue;
        }
        agent.ctx.compacted.push(CompactedSource {
            source: target.source.clone(),
            summary,
        });
        compacted += 1;
    }

    if agent.ctx.compacted.is_empty() {
        return Err("no source could be summarised; search and scrape again".into());
    }

    // The sources the essay will cite are settled: show them.
    let sources: Vec<&Source> = agent.ctx.compacted.iter().map(|c| &c.source).collect();
    agent
        .run
        .emit(
            "sources_ready",
            json!({ "count": sources.len(), "sources": sources }),
        )
        .await?;

    Ok((
        json!({ "compacted": compacted, "failed": failed, "totalInContext": agent.ctx.compacted.len() }),
        format!("{} sources ready to cite.", agent.ctx.compacted.len()),
    ))
}

/// The compactor's three parts as one brief.
fn compaction_summary(reply: &Value) -> String {
    let list = |value: &Value| -> Vec<String> {
        match value {
            Value::Array(_) => strings(value, 40),
            Value::String(s) => s
                .lines()
                .map(str::trim)
                .filter(|l| !l.is_empty())
                .map(str::to_string)
                .collect(),
            _ => Vec::new(),
        }
    };
    let mut sections = Vec::new();
    let main = text_of(&reply["compacted_content"]);
    if !main.is_empty() {
        sections.push(main);
    }
    let points = list(&reply["key_points"]);
    if !points.is_empty() {
        sections.push(format!("Key points:\n- {}", points.join("\n- ")));
    }
    let quotes = list(&reply["relevant_quotes"]);
    if !quotes.is_empty() {
        sections.push(format!("Relevant quotes:\n- {}", quotes.join("\n- ")));
    }
    sections.join("\n\n")
}

/// How often the writer's new text goes to open editors.
const LIVE_BATCH: Duration = Duration::from_millis(50);

/// Sends the part of `body` past `streamed` (a byte offset) to open editors
/// and returns the new offset. `body` only ever grows, so it is a clean cut.
fn stream_live(agent: &Agent<'_>, body: &str, streamed: usize) -> usize {
    agent
        .run
        .st
        .docs
        .append(agent.run.project_id, &body[streamed..]);
    body.len()
}

/// The essay part of the writer's output so far, and the bibliography once
/// the marker has arrived.
fn split_output(output: &str) -> (&str, Option<&str>) {
    match output.split_once(prompt::BIBLIOGRAPHY_MARKER) {
        Some((body, bibliography)) => (body, Some(bibliography)),
        // The marker may be half-streamed: hold back a possible partial one.
        None => {
            let partial = (1..prompt::BIBLIOGRAPHY_MARKER.len())
                .rev()
                .find(|n| output.ends_with(&prompt::BIBLIOGRAPHY_MARKER[..*n]))
                .unwrap_or(0);
            (&output[..output.len() - partial], None)
        }
    }
}

async fn write_essay(agent: &mut Agent<'_>, args: &Value) -> Result<Done, Failure> {
    let Some(topic) = agent.ctx.essay_topic.clone() else {
        return Err("call plan_essay first (the essay topic is missing)".into());
    };
    if agent.ctx.outlines.len() < 3 {
        return Err("need at least 3 outlines; call generate_outlines first".into());
    }
    if agent.ctx.compacted.is_empty() {
        return Err("no compacted sources; run compact_sources first".into());
    }
    let Some(target) = agent.ctx.word_count else {
        return Err("wordCount is missing; ask_user(field=\"wordCount\") first".into());
    };
    let Some(citation_style) = agent.ctx.citation_style.clone() else {
        return Err("citationStyle is missing; ask_user(field=\"citationStyle\") first".into());
    };

    precheck(agent, pricing::charge(target, 0, 0)).await?;

    let outlines: Vec<String> = agent
        .ctx
        .outlines
        .iter()
        .enumerate()
        .map(|(i, o)| {
            format!(
                "Outline {} ({}): {} - {}",
                i + 1,
                o.kind,
                o.title,
                o.description
            )
        })
        .collect();
    let sources: Vec<String> = agent
        .ctx
        .compacted
        .iter()
        .enumerate()
        .map(|(i, c)| {
            format!(
                "source {}:\ntitle: {}\nPublisher: {}\nAuthor: {}\nYear: {}\nContent(compacted): {}",
                i + 1,
                c.source.title,
                c.source.publisher.as_deref().unwrap_or(""),
                c.source.author.as_deref().unwrap_or(""),
                c.source.published_year.as_deref().unwrap_or(""),
                c.summary,
            )
        })
        .collect();
    let mut message = format!(
        "Word Count: {target}\nEssay Topic: {topic}\nEssay Type: {}\nWriting Tone: academic\n\
         Citation Format: {citation_style}\n\nOutlines ({} paragraphs):\n{}\n\nSources:\n{}",
        agent.ctx.essay_type.as_deref().unwrap_or("Essay"),
        outlines.len(),
        outlines.join("\n"),
        sources.join("\n\n"),
    );
    if let Some(notes) = optional(&args["notes"]) {
        message.push_str(&format!("\n\nOrchestrator notes:\n{notes}"));
    }

    let db = agent.run.st.db.clone();
    let docs = agent.run.st.docs.clone();
    let (project_id, run_id) = (agent.run.project_id, agent.run.run_id);

    documents::begin_agent_write(&db, project_id, run_id, "agent_write").await?;
    docs.begin(project_id);
    sqlx::query("UPDATE projects SET target_words = $2, updated_at = now() WHERE id = $1")
        .bind(project_id)
        .bind(target as i32)
        .execute(&db)
        .await?;
    agent
        .run
        .emit("writing_started", json!({ "targetWords": target }))
        .await?;

    let mut stream = agent
        .llm
        .stream(ChatRequest {
            model: agent.models.writer.clone(),
            messages: vec![system(prompt::writer()), user(message)],
            temperature: Some(0.4),
            json: false,
            tools: Vec::new(),
        })
        .await?;

    let mut output = String::new();
    let mut last_progress = Instant::now();
    let mut last_save = Instant::now();
    let mut last_live: Option<Instant> = None;
    let mut reported = -1;
    let mut streamed = 0;
    while let Some(chunk) = stream.next().await {
        output.push_str(&chunk?);
        let (body, _) = split_output(&output);

        if last_live.is_none_or(|at| at.elapsed() >= LIVE_BATCH) {
            last_live = Some(Instant::now());
            streamed = stream_live(agent, body.trim_start(), streamed);
        }

        if last_progress.elapsed() >= Duration::from_secs(1) {
            last_progress = Instant::now();
            let words = pricing::count_words(body);
            if words != reported {
                reported = words;
                agent
                    .run
                    .emit(
                        "write_progress",
                        json!({ "words": words, "targetWords": target }),
                    )
                    .await?;
            }
        }
        if last_save.elapsed() >= Duration::from_secs(2) {
            last_save = Instant::now();
            let save = AgentSave {
                body: Some(body.trim()),
                ..AgentSave::default()
            };
            let (rev, words) = documents::save_agent(&db, project_id, run_id, save).await?;
            docs.committed(project_id, rev);
            agent
                .run
                .emit(
                    "document_updated",
                    json!({ "rev": rev, "wordCount": words }),
                )
                .await?;
        }
    }

    let (body, bibliography) = split_output(&output);
    stream_live(agent, body.trim_start(), streamed);
    let body = body.trim();
    if body.is_empty() {
        return Err("the writer returned no essay".into());
    }
    let bibliography = bibliography.unwrap_or("").trim();
    let cited: Vec<&Source> = agent.ctx.compacted.iter().map(|c| &c.source).collect();
    let cited = json!(cited);

    let save = AgentSave {
        body: Some(body),
        bibliography: Some(bibliography),
        title: Some(&topic),
        style: Some(documents::style_key(&citation_style)),
        sources: Some(&cited),
        fields: None,
    };
    let (rev, words) = documents::save_agent(&db, project_id, run_id, save).await?;
    documents::unlock(&db, &docs, project_id, run_id).await?;

    agent
        .run
        .emit(
            "write_progress",
            json!({ "words": words, "targetWords": target }),
        )
        .await?;
    agent
        .run
        .emit(
            "document_updated",
            json!({ "rev": rev, "wordCount": words }),
        )
        .await?;
    agent.ctx.words_written = words;

    charge(
        agent,
        pricing::charge(words, 0, 0),
        "write",
        "Essay generation",
    )
    .await?;

    Ok((
        json!({ "wordCount": words, "hasBibliography": !bibliography.is_empty() }),
        format!("{words} words written."),
    ))
}

async fn finalize_document(agent: &mut Agent<'_>) -> Result<Done, Failure> {
    if agent.ctx.words_written == 0 {
        return Err("write_essay has not succeeded yet".into());
    }
    let db = agent.run.st.db.clone();
    let (project_id, run_id) = (agent.run.project_id, agent.run.run_id);
    let fields = agent.ctx.document_fields();

    documents::begin_agent_write(&db, project_id, run_id, "agent_write").await?;
    let save = AgentSave {
        fields: Some(&fields),
        ..AgentSave::default()
    };
    let (rev, words) = documents::save_agent(&db, project_id, run_id, save).await?;
    documents::unlock(&db, &agent.run.st.docs, project_id, run_id).await?;

    agent
        .run
        .emit(
            "document_updated",
            json!({ "rev": rev, "wordCount": words }),
        )
        .await?;
    agent.ctx.export_ready = true;

    Ok((json!({ "delivered": true }), "Your essay is ready.".into()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn splits_the_writer_output_at_the_marker() {
        let done = "Para one.\n\nPara two.\n===BIBLIOGRAPHY===\nSweet, W. (2022).";
        assert_eq!(
            split_output(done),
            ("Para one.\n\nPara two.\n", Some("\nSweet, W. (2022)."))
        );

        // No marker yet: everything is essay.
        assert_eq!(split_output("Para one."), ("Para one.", None));

        // A marker that is only half here is held back, not counted as essay.
        assert_eq!(split_output("Para one.\n===BIBLIO"), ("Para one.\n", None));
        assert_eq!(split_output("Para one.\n="), ("Para one.\n", None));
    }

    #[test]
    fn joins_the_compactor_reply_into_one_brief() {
        let reply = json!({
            "compacted_content": "Seas are rising.",
            "key_points": ["Faster since 1993", "Uneven by region"],
            "relevant_quotes": "\"High-tide flooding is now routine.\"",
        });
        assert_eq!(
            compaction_summary(&reply),
            "Seas are rising.\n\nKey points:\n- Faster since 1993\n- Uneven by region\n\n\
             Relevant quotes:\n- \"High-tide flooding is now routine.\""
        );
        assert_eq!(compaction_summary(&json!({})), "");
    }
}

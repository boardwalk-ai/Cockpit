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

use super::context::{CompactedSource, CritiqueIssue, Outline, ScrapedSource, Source};
use super::{prompt, Agent};
use crate::documents::{self, AgentSave, DocError};
use crate::humanize::{self, Provider};
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
    /// The user asked for the write to start again with this instruction.
    Interrupted(String),
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
            "evaluate_sources",
            "Judge whether the summarised sources are enough for a well-cited essay. Call once after compact_sources. If the result has searchAgain = true, search again with its recommendation as the refinement, then scrape and compact, and move on.",
            json!({
                "type": "object", "additionalProperties": false,
                "properties": { "notes": { "type": "string", "description": "Optional: what kinds of sources the essay needs." } },
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
        function(
            "humanize_essay",
            "Send the essay in the user's document through a humanizer (StealthGPT or UndetectableAI) and put the result back in the document. Ask the user which one with field=\"humanizerChoice\" first, unless they already named it.",
            json!({
                "type": "object", "additionalProperties": false,
                "properties": { "provider": { "type": "string", "enum": ["StealthGPT", "UndetectableAI"] } },
            }),
        ),
        function(
            "split_paragraphs",
            "Restore the paragraph breaks after a humanizer merged the essay into one block, without changing any wording. Call only when humanize_essay reported paragraphsMerged.",
            json!({ "type": "object", "additionalProperties": false, "properties": {} }),
        ),
    ]
}

/// The tools of a revision run: the essay is written, the user wants changes.
pub fn revision_specs() -> Vec<Value> {
    let shared = |name: &str| {
        specs()
            .into_iter()
            .find(|spec| spec["function"]["name"] == name)
            .expect("a tool of the first run")
    };
    let ask = shared("ask_user");
    vec![
        function(
            "revise_essay",
            "Rewrite the essay in the user's document to make the requested changes. Everything not mentioned stays as it is.",
            json!({
                "type": "object", "additionalProperties": false, "required": ["instructions"],
                "properties": { "instructions": { "type": "string", "description": "Precisely what to change: which paragraphs (numbered from 1) and how." } },
            }),
        ),
        function(
            "critique_essay",
            "Review the essay in the user's document for thesis, evidence, clarity, citations, length and structure. Returns the issues by paragraph number. Changes nothing.",
            json!({
                "type": "object", "additionalProperties": false,
                "properties": { "notes": { "type": "string", "description": "Optional: what to look at, e.g. 'evidence in the body paragraphs'." } },
            }),
        ),
        ask,
        shared("humanize_essay"),
        shared("split_paragraphs"),
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
        "evaluate_sources" => "Checking the sources".into(),
        "critique_essay" => "Reviewing the essay".into(),
        "write_essay" => "Writing the essay".into(),
        "revise_essay" => "Revising the essay".into(),
        "finalize_document" => "Finishing the document".into(),
        "humanize_essay" => format!(
            "Humanizing with {}",
            args["provider"]
                .as_str()
                .and_then(Provider::parse)
                .unwrap_or(Provider::StealthGpt)
                .label()
        ),
        "split_paragraphs" => "Restoring the paragraphs".into(),
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
        "write_essay" | "revise_essay" => 300,
        "humanize_essay" => 200,
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
            | "evaluate_sources"
            | "critique_essay"
            | "write_essay"
            | "revise_essay"
            | "finalize_document"
            | "humanize_essay"
            | "split_paragraphs"
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
        "evaluate_sources" => evaluate_sources(agent, args).await,
        "critique_essay" => critique_essay(agent, args).await,
        "write_essay" => write_essay(agent, args).await,
        "revise_essay" => revise_essay(agent, args).await,
        "finalize_document" => finalize_document(agent).await,
        "humanize_essay" => humanize_essay(agent, args).await,
        "split_paragraphs" => split_paragraphs(agent).await,
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

/// The user's instructions on this project ("keep it formal"), for a brief.
async fn user_instructions(agent: &Agent<'_>) -> Result<String, Failure> {
    let all = crate::runs::aside::directives(&agent.run.st, agent.run.project_id).await?;
    if all.is_empty() {
        return Ok(String::new());
    }
    Ok(format!(
        "\n\nTHE USER'S INSTRUCTIONS (follow them):\n- {}",
        all.join("\n- ")
    ))
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
            reasoning: None,
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
    message.push_str(&user_instructions(agent).await?);

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

    precheck(agent, agent.price(0, 0, targets.len() as i64).await).await?;

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
            agent.price(0, 0, read).await,
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
            // Left out by the user in their source review.
            let rejected = agent.ctx.review_of(url).is_some_and(|note| note.rejected);
            !done && wanted && !rejected
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
        let mut message = format!(
            "Task: SOURCE_COMPACTION\nSource Type: web\nSource Title: {}\n\nFull Content:\n{}",
            if target.source.title.is_empty() {
                "Untitled"
            } else {
                &target.source.title
            },
            target.full_content,
        );
        let note = agent
            .ctx
            .review_of(&target.source.url)
            .and_then(|note| note.focus_note.as_deref())
            .map(str::trim)
            .filter(|note| !note.is_empty());
        if let Some(note) = note {
            message.push_str(&format!(
                "\n\nThe user wants this summary to focus on: {note}"
            ));
        }
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
            Err(failure @ (Failure::Run(_) | Failure::Interrupted(_))) => return Err(failure),
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

    precheck(agent, agent.price(target, 0, 0).await).await?;

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
    message.push_str(&user_instructions(agent).await?);

    let db = agent.run.st.db.clone();
    let project_id = agent.run.project_id;
    sqlx::query("UPDATE projects SET target_words = $2, updated_at = now() WHERE id = $1")
        .bind(project_id)
        .bind(target as i32)
        .execute(&db)
        .await?;

    let request = ChatRequest {
        model: agent.models.writer.clone(),
        messages: vec![system(prompt::writer()), user(message)],
        temperature: Some(0.4),
        json: false,
        tools: Vec::new(),
        reasoning: None,
    };
    let (body, bibliography) = stream_into_document(agent, request, target, "agent_write").await?;
    let cited: Vec<&Source> = agent.ctx.compacted.iter().map(|c| &c.source).collect();
    let cited = json!(cited);

    let save = AgentSave {
        body: Some(&body),
        bibliography: Some(&bibliography),
        title: Some(&topic),
        style: Some(documents::style_key(&citation_style)),
        sources: Some(&cited),
        fields: None,
    };
    let words = finish_document_write(agent, save, target).await?;
    agent.ctx.words_written = words;

    charge(
        agent,
        agent.price(words, 0, 0).await,
        "write",
        "Essay generation",
    )
    .await?;

    Ok((
        json!({ "wordCount": words, "hasBibliography": !bibliography.is_empty() }),
        format!("{words} words written."),
    ))
}

/// Locks the document, streams the writer's output into it (live to open
/// editors, saved every 2 seconds, progress once a second) and returns the
/// finished body and bibliography. The document stays locked: the caller
/// saves the final text with [finish_document_write].
async fn stream_into_document(
    agent: &mut Agent<'_>,
    request: ChatRequest,
    target: i64,
    reason: &str,
) -> Result<(String, String), Failure> {
    let db = agent.run.st.db.clone();
    let docs = agent.run.st.docs.clone();
    let (project_id, run_id) = (agent.run.project_id, agent.run.run_id);

    // What the document held, to put back if the user asks for a rewrite.
    let (before_body, before_bibliography): (String, String) =
        sqlx::query_as("SELECT body, bibliography FROM documents WHERE project_id = $1")
            .bind(project_id)
            .fetch_one(&db)
            .await?;
    documents::begin_agent_write(&db, project_id, run_id, reason).await?;
    docs.begin(project_id);
    let writing = agent.run.st.hub.begin_write(run_id);
    agent
        .run
        .emit("writing_started", json!({ "targetWords": target }))
        .await?;

    let mut stream = agent.llm.stream(request).await?;
    let mut output = String::new();
    let mut last_progress = Instant::now();
    let mut last_save = Instant::now();
    let mut last_live: Option<Instant> = None;
    let mut reported = -1;
    let mut streamed = 0;
    loop {
        let chunk = tokio::select! {
            chunk = stream.next() => chunk,
            instruction = writing.signal.requested() => {
                // Put the document back as it was, unlocked; nothing is charged.
                let save = AgentSave {
                    body: Some(&before_body),
                    bibliography: Some(&before_bibliography),
                    ..AgentSave::default()
                };
                let (rev, words) = documents::save_agent(&db, project_id, run_id, save).await?;
                documents::unlock(&db, &docs, project_id, run_id).await?;
                agent
                    .run
                    .emit("document_updated", json!({ "rev": rev, "wordCount": words }))
                    .await?;
                return Err(Failure::Interrupted(instruction));
            }
        };
        let Some(chunk) = chunk else { break };
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
    Ok((
        body.to_string(),
        bibliography.unwrap_or("").trim().to_string(),
    ))
}

/// Saves a write's final text, unlocks the document and reports it. Returns
/// the body's word count.
async fn finish_document_write(
    agent: &mut Agent<'_>,
    save: AgentSave<'_>,
    target: i64,
) -> Result<i64, Failure> {
    let db = agent.run.st.db.clone();
    let docs = agent.run.st.docs.clone();
    let (project_id, run_id) = (agent.run.project_id, agent.run.run_id);
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
    Ok(words)
}

/// `revise_essay`: rewrites the essay as it stands in the document (with the
/// user's own edits) to do what the user asked. A version is kept first, so
/// the revision can be undone from History.
async fn revise_essay(agent: &mut Agent<'_>, args: &Value) -> Result<Done, Failure> {
    let Some(instructions) = optional(&args["instructions"]) else {
        return Err("revise_essay needs `instructions`: what to change".into());
    };
    let (title, style, body, bibliography): (String, String, String, String) = sqlx::query_as(
        "SELECT title, style, body, bibliography FROM documents WHERE project_id = $1",
    )
    .bind(agent.run.project_id)
    .fetch_one(&agent.run.st.db)
    .await?;
    if body.trim().is_empty() {
        return Err("the document has no essay to revise".into());
    }
    let current = pricing::count_words(&body);
    precheck(agent, agent.price(current, 0, 0).await).await?;

    let sources: Vec<String> = agent
        .ctx
        .compacted
        .iter()
        .enumerate()
        .map(|(i, c)| {
            format!(
                "source {}: {} ({}, {})\n{}",
                i + 1,
                c.source.title,
                c.source.author.as_deref().unwrap_or("unknown author"),
                c.source.published_year.as_deref().unwrap_or("n.d."),
                c.summary,
            )
        })
        .collect();
    let mut message = format!(
        "Title: {title}\nCitation Format: {}\n\nWHAT TO CHANGE\n{instructions}\n\n\
         CURRENT ESSAY\n{body}\n\nCURRENT BIBLIOGRAPHY\n{bibliography}",
        style.to_uppercase(),
    );
    if !sources.is_empty() {
        message.push_str(&format!("\n\nSOURCES\n{}", sources.join("\n\n")));
    }
    message.push_str(&user_instructions(agent).await?);

    let request = ChatRequest {
        model: agent.models.writer.clone(),
        messages: vec![system(prompt::reviser()), user(message)],
        temperature: Some(0.3),
        json: false,
        tools: Vec::new(),
        reasoning: None,
    };
    let (revised, new_bibliography) =
        stream_into_document(agent, request, current, "agent_revise").await?;
    // A reviser that drops the bibliography keeps the old one.
    let new_bibliography = if new_bibliography.is_empty() {
        bibliography.trim().to_string()
    } else {
        new_bibliography
    };
    let save = AgentSave {
        body: Some(&revised),
        bibliography: Some(&new_bibliography),
        ..AgentSave::default()
    };
    let words = finish_document_write(agent, save, current).await?;
    agent.ctx.revisions += 1;
    agent.ctx.words_written = words;

    charge(
        agent,
        agent.price(words, 0, 0).await,
        &format!("revise:{}", agent.ctx.revisions),
        "Essay revision",
    )
    .await?;

    Ok((
        json!({ "wordCount": words, "before": current }),
        format!("Revised · {words} words."),
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

/// The essay as it stands in the document (with the user's own edits).
async fn current_body(agent: &Agent<'_>) -> Result<String, Failure> {
    let body: String = sqlx::query_scalar("SELECT body FROM documents WHERE project_id = $1")
        .bind(agent.run.project_id)
        .fetch_one(&agent.run.st.db)
        .await?;
    if body.trim().is_empty() {
        return Err("the document has no essay yet".into());
    }
    Ok(body)
}

/// Locks the document for a change that is not streamed (the humanizer, the
/// paragraph split) and keeps a version of it first. Open editors are told, so
/// they go read-only while it happens.
async fn lock_for_rewrite(agent: &Agent<'_>) -> Result<(), Failure> {
    let st = &agent.run.st;
    documents::begin_agent_write(&st.db, agent.run.project_id, agent.run.run_id, "humanize")
        .await?;
    st.docs.changed(agent.run.project_id);
    Ok(())
}

/// Saves the rewritten body, unlocks, and announces the new revision.
async fn save_rewrite(agent: &mut Agent<'_>, body: &str) -> Result<i64, Failure> {
    let db = agent.run.st.db.clone();
    let docs = agent.run.st.docs.clone();
    let (project_id, run_id) = (agent.run.project_id, agent.run.run_id);
    let save = AgentSave {
        body: Some(body),
        ..AgentSave::default()
    };
    let (rev, words) = documents::save_agent(&db, project_id, run_id, save).await?;
    documents::unlock(&db, &docs, project_id, run_id).await?;
    agent
        .run
        .emit(
            "document_updated",
            json!({ "rev": rev, "wordCount": words }),
        )
        .await?;
    agent.ctx.words_written = words;
    Ok(words)
}

/// `humanize_essay`: sends the essay as it stands through StealthGPT or
/// UndetectableAI and puts the result in the document. The bibliography is
/// left alone. A version is kept first, so it can be undone from History.
async fn humanize_essay(agent: &mut Agent<'_>, args: &Value) -> Result<Done, Failure> {
    let provider = match optional(&args["provider"]) {
        Some(name) => Provider::parse(&name).ok_or_else(|| {
            Failure::Tool(format!(
                "unknown humanizer \"{name}\"; use StealthGPT or UndetectableAI"
            ))
        })?,
        None => Provider::StealthGpt,
    };
    let body = current_body(agent).await?;
    let words = pricing::count_words(&body);
    let price = agent.price(0, words, 0).await;
    precheck(agent, price).await?;

    lock_for_rewrite(agent).await?;
    let humanizer = agent.run.st.humanizer.clone();
    // The loop unlocks the document if this fails.
    let humanized = humanizer.humanize(provider, body.trim()).await?;
    let humanized = humanized.trim();
    if humanized.is_empty() {
        return Err(format!("{} returned nothing", provider.label()).into());
    }

    let before = humanize::paragraphs(&body).len();
    let after = humanize::paragraphs(humanized).len();
    let new_words = save_rewrite(agent, humanized).await?;

    agent.ctx.humanizations += 1;
    agent.ctx.humanized_by = Some(provider.label().to_string());
    agent.ctx.paragraphs_before_humanize = before;
    charge(
        agent,
        price,
        &format!("humanize:{}", agent.ctx.humanizations),
        "Humanizing",
    )
    .await?;

    Ok((
        json!({
            "provider": provider.label(),
            "wordCount": new_words,
            "paragraphsBefore": before,
            "paragraphs": after,
            // Some humanizers return one block of text.
            "paragraphsMerged": after < before,
        }),
        format!("Humanized with {} · {new_words} words.", provider.label()),
    ))
}

/// `split_paragraphs`: puts the paragraph breaks back after a humanizer merged
/// them. The model only chooses where the breaks go: a split that changes a
/// single word is thrown away.
async fn split_paragraphs(agent: &mut Agent<'_>) -> Result<Done, Failure> {
    let body = current_body(agent).await?;
    let target = match agent.ctx.paragraphs_before_humanize {
        0 => agent.ctx.outlines.len(),
        before => before,
    };
    if target < 2 {
        return Err("there is no paragraph structure to restore".into());
    }
    if humanize::paragraphs(&body).len() >= target {
        return Err("the essay already has its paragraphs".into());
    }

    // The outline names each paragraph's job, when it still matches.
    let structure = if agent.ctx.outlines.len() == target {
        agent
            .ctx
            .outlines
            .iter()
            .enumerate()
            .map(|(i, o)| format!("{}. {} — {}", i + 1, o.kind, o.title))
            .collect::<Vec<_>>()
            .join("\n")
    } else {
        format!("{target} paragraphs: an introduction, the body paragraphs, a conclusion")
    };
    let message = format!(
        "Target paragraph structure (in order):\n{structure}\n\n\
         Essay text (merged into one block by the humanizer):\n{}\n\n\
         Split the text into exactly {target} paragraphs matching the structure above. \
         Preserve all wording verbatim.",
        body.trim(),
    );

    lock_for_rewrite(agent).await?;
    let reply = ask_json(
        agent,
        &agent.models.secondary,
        &prompt::splitter(target),
        message,
        0.2,
        true,
    )
    .await?;
    let pieces: Vec<String> = reply["paragraphs"]
        .as_array()
        .map(|items| {
            items
                .iter()
                .map(|item| match item {
                    Value::String(text) => text.trim().to_string(),
                    other => text_of(&other["text"]),
                })
                .filter(|text| !text.is_empty())
                .collect()
        })
        .unwrap_or_default();
    if pieces.len() < 2 {
        return Err("the model returned no paragraphs".into());
    }
    let split = pieces.join("\n\n");
    if !humanize::same_wording(&split, &body) {
        return Err("the split changed the wording, so the essay was left as it was".into());
    }

    save_rewrite(agent, &split).await?;
    Ok((
        json!({ "paragraphs": pieces.len() }),
        format!("{} paragraphs restored.", pieces.len()),
    ))
}

/// `evaluate_sources`: asks whether the summarised sources can carry the
/// essay. The run may look for more once; after that it writes with what it has.
async fn evaluate_sources(agent: &mut Agent<'_>, args: &Value) -> Result<Done, Failure> {
    let total = agent.ctx.compacted.len();
    if total == 0 {
        return Err("no summarised sources yet; call compact_sources first".into());
    }
    let sources: Vec<String> = agent
        .ctx
        .compacted
        .iter()
        .enumerate()
        .map(|(i, c)| {
            let title = if c.source.title.is_empty() {
                "(no title)"
            } else {
                &c.source.title
            };
            format!("Source {}: {title}\n{}", i + 1, c.summary)
        })
        .collect();
    let outlines: Vec<String> = agent
        .ctx
        .outlines
        .iter()
        .map(|o| format!("- {}: {}", o.kind, o.title))
        .collect();
    let mut message = format!(
        "Essay topic: {}\nEssay type: {}\nRequired paragraphs:\n{}",
        agent.ctx.essay_topic.as_deref().unwrap_or("unknown"),
        agent.ctx.essay_type.as_deref().unwrap_or("Essay"),
        outlines.join("\n"),
    );
    if let Some(notes) = optional(&args["notes"]) {
        message.push_str(&format!("\nNotes: {notes}"));
    }
    message.push_str(&format!(
        "\n\nCompacted sources ({total} total):\n{}",
        sources.join("\n\n")
    ));

    // An evaluator that fails must not stop the essay: fall back to a count.
    let verdict = match ask_json(
        agent,
        &agent.models.secondary,
        prompt::EVALUATOR,
        message,
        0.2,
        true,
    )
    .await
    {
        Ok(verdict) => verdict,
        Err(failure @ (Failure::Run(_) | Failure::Interrupted(_))) => return Err(failure),
        Err(Failure::Tool(_)) => Value::Null,
    };
    let sufficient = verdict["sufficient"].as_bool().unwrap_or(total >= 3);
    let quality = verdict["quality"]
        .as_str()
        .filter(|quality| matches!(*quality, "good" | "fair" | "poor"))
        .unwrap_or("fair");
    let gaps = strings(&verdict["gaps"], 6);
    let recommendation = text_of(&verdict["recommendation"]);

    agent.ctx.source_evaluations += 1;
    let search_again = !sufficient && agent.ctx.source_evaluations == 1;
    let summary = if sufficient {
        format!("{total} sources cover the essay.")
    } else if search_again {
        "The sources leave gaps. Looking for more.".to_string()
    } else {
        "The sources leave some gaps. Writing with what we have.".to_string()
    };

    Ok((
        json!({
            "sufficient": sufficient,
            "quality": quality,
            "gaps": gaps,
            "recommendation": recommendation,
            "searchAgain": search_again,
        }),
        summary,
    ))
}

const ISSUE_KINDS: [&str; 6] = [
    "thesis",
    "evidence",
    "clarity",
    "citations",
    "length",
    "structure",
];

/// `critique_essay`: reviews the essay as it stands in the document and lists
/// what is weak. It changes nothing and costs nothing; `revise_essay` acts on it.
async fn critique_essay(agent: &mut Agent<'_>, args: &Value) -> Result<Done, Failure> {
    let (style, body): (String, String) =
        sqlx::query_as("SELECT style, body FROM documents WHERE project_id = $1")
            .bind(agent.run.project_id)
            .fetch_one(&agent.run.st.db)
            .await?;
    let paragraphs = humanize::paragraphs(&body);
    if paragraphs.is_empty() {
        return Err("the document has no essay to review".into());
    }
    let numbered: Vec<String> = paragraphs
        .iter()
        .enumerate()
        .map(|(i, p)| format!("[{}] {p}", i + 1))
        .collect();
    let outlines: Vec<String> = agent
        .ctx
        .outlines
        .iter()
        .enumerate()
        .map(|(i, o)| format!("[{}] {} — {}: {}", i + 1, o.kind, o.title, o.description))
        .collect();
    let mut message = format!(
        "Topic: {}\nCitation style: {}",
        agent.ctx.essay_topic.as_deref().unwrap_or("unknown"),
        style.to_uppercase(),
    );
    if let Some(notes) = optional(&args["notes"]) {
        message.push_str(&format!("\nFocus: {notes}"));
    }
    if !outlines.is_empty() {
        message.push_str(&format!("\n\nOutline structure:\n{}", outlines.join("\n")));
    }
    message.push_str(&format!(
        "\n\nEssay (paragraphs numbered from 1):\n{}",
        numbered.join("\n\n")
    ));

    let review = ask_json(
        agent,
        &agent.models.orchestrator,
        prompt::CRITIC,
        message,
        0.3,
        true,
    )
    .await?;

    let issues: Vec<CritiqueIssue> = review["issues"]
        .as_array()
        .map(|items| {
            items
                .iter()
                .filter_map(|item| {
                    let paragraph = item["paragraph"].as_u64()? as usize;
                    let description = text_of(&item["description"]);
                    if !(1..=paragraphs.len()).contains(&paragraph) || description.is_empty() {
                        return None;
                    }
                    let kind = item["type"]
                        .as_str()
                        .filter(|kind| ISSUE_KINDS.contains(kind))
                        .unwrap_or("clarity");
                    Some(CritiqueIssue {
                        paragraph,
                        kind: kind.to_string(),
                        description,
                        major: item["severity"] == "major",
                    })
                })
                .take(12)
                .collect()
        })
        .unwrap_or_default();
    let major = issues.iter().filter(|issue| issue.major).count();
    let score = review["overallScore"].as_i64().unwrap_or(7).clamp(1, 10);
    let ready = review["ready"].as_bool().unwrap_or(major == 0);

    agent
        .run
        .emit("context_update", json!({ "critiqueIssues": issues }))
        .await?;
    let summary = match (issues.len(), major) {
        (0, _) => "No issues found.".to_string(),
        (1, 0) => "1 thing could be better.".to_string(),
        (count, 0) => format!("{count} things could be better."),
        (count, major) => format!("{count} things to fix, {major} important."),
    };
    let result = json!({
        "overallScore": score,
        "ready": ready,
        "majorIssues": major,
        "issues": issues,
    });
    agent.ctx.critique_issues = issues;

    Ok((result, summary))
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

//! The agent loop: the model picks a tool, the tool runs, the result goes back,
//! until the essay is delivered.
//!
//! A port of OctopilotWeb's `agent/loop.ts`. Every transition is an event on
//! the run, so the app's timeline is this loop, seen from outside.
//!
//! A run on a project whose essay is already written is a *revision*: the user
//! asks for changes (or asks about the essay) and the agent revises the
//! document as it stands, with a smaller set of tools. The run ends when the
//! agent has answered; the next request is a new run.

pub mod context;
pub mod prompt;
pub mod tools;

use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};

use serde_json::{json, Value};
use uuid::Uuid;

use self::context::{AiSnapshot, Context};
use self::tools::Failure;
use crate::documents;
use crate::llm::{self, ChatRequest, Llm, OpenRouter, ToolCall};
use crate::runs::driver::{RunCtx, RunError};
use crate::scrape::Scraper;
use crate::AppState;

/// Model round-trips a run may take before it is stopped.
const MAX_STEPS: usize = 40;
/// An identical tool call inside this window is the model looping.
const DEDUP_WINDOW: Duration = Duration::from_secs(5);

/// Which model does what. Read from `system_settings`, like the web app.
#[derive(Clone, Debug)]
pub struct Models {
    pub orchestrator: String,
    pub writer: String,
    pub secondary: String,
    pub search: String,
}

impl Models {
    async fn load(st: &AppState) -> Self {
        const PRIMARY: &str = "anthropic/claude-sonnet-4-6";
        let Some(pool) = &st.octopilot else {
            return Self {
                orchestrator: PRIMARY.into(),
                writer: PRIMARY.into(),
                secondary: "google/gemini-3.1-flash-lite-preview".into(),
                search: "perplexity/sonar-pro-search".into(),
            };
        };
        let setting = |key: &'static str, default: String| async move {
            octo_common::llm::model(pool, key, &default).await
        };
        let primary = setting("primary_model", PRIMARY.into()).await;
        Self {
            orchestrator: setting("ghostwriter_orchestrator_model", primary.clone()).await,
            writer: setting("ghostwriter_write_model", primary.clone()).await,
            secondary: setting("secondary_model", primary.clone()).await,
            search: setting("source_search_model", primary).await,
        }
    }
}

impl Models {
    /// The run's chosen models in place of the defaults.
    pub fn apply(&mut self, ai: Option<&AiSnapshot>) {
        let Some(ai) = ai else { return };
        if let Some(model) = &ai.orchestrator {
            self.orchestrator = model.clone();
        }
        if let Some(model) = &ai.writer {
            self.writer = model.clone();
        }
        if let Some(model) = &ai.fast {
            self.secondary = model.clone();
        }
    }
}

/// The user's AI choice for GhostWriter, as a run will use it.
pub(crate) async fn snapshot_for(st: &AppState, user_id: Uuid) -> AiSnapshot {
    match &st.octopilot {
        Some(pool) => AiSnapshot::from_choice(&st.ai.choice(pool, user_id, "ghostwriter").await),
        None => AiSnapshot::default(),
    }
}

/// What a tool works with.
pub struct Agent<'a> {
    pub run: &'a mut RunCtx,
    pub ctx: Context,
    pub llm: Arc<dyn Llm>,
    pub scraper: Arc<dyn Scraper>,
    pub models: Models,
}

impl Agent<'_> {
    /// What an operation costs: the shared price table, times the run's model
    /// multiplier.
    pub async fn price(&self, words_generated: i64, words_humanized: i64, sources: i64) -> i32 {
        let st = &self.run.st;
        let pricing = match &st.octopilot {
            Some(pool) => st.ai.pricing(pool).await,
            None => octo_common::ai::Pricing::default(),
        };
        let multiplier = self.ctx.ai.as_ref().map_or(1.0, |ai| ai.credit_multiplier);
        pricing.charge(words_generated, words_humanized, sources, multiplier)
    }
}

/// The model for this run: the injected one (tests), or OpenRouter with a key
/// from the shared pool.
async fn model_client(st: &AppState) -> Result<Arc<dyn Llm>, RunError> {
    if let Some(llm) = &st.llm {
        return Ok(llm.clone());
    }
    let key = match &st.octopilot {
        Some(pool) => octo_common::llm::openrouter_key(pool).await,
        None => None,
    };
    let key = key.ok_or_else(|| {
        tracing::error!("no active OpenRouter key in api_keys");
        RunError::Failed("GhostWriter is not set up to write right now.".to_string())
    })?;
    Ok(Arc::new(OpenRouter::new(st.http.clone(), key)))
}

/// A model client and the models to use, outside a run (the quick reply).
/// `None` when no model is available.
pub(crate) async fn client(st: &AppState) -> Option<(Arc<dyn Llm>, Models)> {
    let llm = model_client(st).await.ok()?;
    Some((llm, Models::load(st).await))
}

/// Drives one run to the delivered essay.
pub async fn run(run: &mut RunCtx) -> Result<(), RunError> {
    let llm = model_client(&run.st).await?;
    let models = Models::load(&run.st).await;
    let scraper = run.st.scraper.clone();
    let instruction = run.instruction.clone();

    if run.resuming {
        let (messages, context, pending_call): (Value, Value, Option<String>) =
            sqlx::query_as("SELECT messages, context, pending_call FROM runs WHERE id = $1")
                .bind(run.run_id)
                .fetch_one(&run.st.db)
                .await?;
        let messages = messages.as_array().cloned().unwrap_or_default();
        if !messages.is_empty() {
            let ctx: Context = serde_json::from_value(context).unwrap_or_default();
            let mut agent = Agent {
                run,
                ctx,
                llm,
                scraper,
                models,
            };
            agent.models.apply(agent.ctx.ai.as_ref());
            agent.run.voice_name = agent.ctx.ai.as_ref().map(|ai| ai.name.clone());
            return resume(agent, messages, pending_call).await;
        }
        // Stopped before anything was saved: start over, without repeating
        // the user's message.
    } else {
        run.emit("user_message", json!({ "text": instruction }))
            .await?;
    }

    // The model and voice the user chose, fixed for this run.
    let ai = snapshot_for(&run.st, run.user_id).await;
    let persona = prompt::persona(&ai.name, ai.voice.as_deref());

    let today = chrono::Utc::now().format("%B %-d, %Y").to_string();
    let written: Option<(String, String, String)> = sqlx::query_as(
        "SELECT title, style, body FROM documents \
         WHERE project_id = $1 AND btrim(body) <> ''",
    )
    .bind(run.project_id)
    .fetch_optional(&run.st.db)
    .await?;
    let revision = written.is_some();

    let (messages, ctx, specs) = match written {
        None => (
            vec![
                llm::system(format!("{}{persona}", prompt::orchestrator())),
                llm::user(prompt::user_brief(&instruction, &today)),
            ],
            Context {
                instruction,
                ..Context::default()
            },
            tools::specs(),
        ),
        Some((title, style, body)) => {
            // What the earlier run worked out (topic, outline, sources) helps
            // the reviser cite properly.
            let previous: Option<Value> = sqlx::query_scalar(
                "SELECT context FROM runs WHERE project_id = $1 AND id <> $2 \
                 ORDER BY created_at DESC LIMIT 1",
            )
            .bind(run.project_id)
            .bind(run.run_id)
            .fetch_optional(&run.st.db)
            .await?;
            let mut ctx: Context = previous
                .and_then(|value| serde_json::from_value(value).ok())
                .unwrap_or_default();
            ctx.instruction = instruction.clone();
            ctx.export_ready = false;
            ctx.revisions = 0;
            (
                vec![
                    llm::system(format!("{}{persona}", prompt::revision_orchestrator())),
                    llm::user(prompt::revision_brief(
                        &instruction,
                        &title,
                        &style.to_uppercase(),
                        &body,
                        &today,
                    )),
                ],
                ctx,
                tools::revision_specs(),
            )
        }
    };
    let mut agent = Agent {
        run,
        ctx,
        llm,
        scraper,
        models,
    };
    agent.run.voice_name = Some(ai.name.clone());
    agent.ctx.ai = Some(ai);
    agent.models.apply(agent.ctx.ai.as_ref());
    drive(agent, messages, specs, revision, false).await
}

/// Picks a run up from its saved conversation: the turn it stopped in is
/// completed (the user's answer, or "interrupted" for a tool that did not
/// finish), then the loop goes on.
async fn resume(
    mut agent: Agent<'_>,
    mut messages: Vec<Value>,
    pending_call: Option<String>,
) -> Result<(), RunError> {
    let revision = messages
        .first()
        .and_then(|m| m["content"].as_str())
        .is_some_and(prompt::is_revision);
    let specs = if revision {
        tools::revision_specs()
    } else {
        tools::specs()
    };

    let last_turn = messages.iter().rposition(|m| m["role"] == "assistant");
    let mut waiting_for_reply = false;
    if let Some(index) = last_turn {
        let turn = messages[index].clone();
        let answered: Vec<String> = messages[index + 1..]
            .iter()
            .filter_map(|m| m["tool_call_id"].as_str().map(str::to_string))
            .collect();
        let calls = turn["tool_calls"].as_array().cloned().unwrap_or_default();
        waiting_for_reply = calls.is_empty() && index + 1 == messages.len();
        for call in calls {
            let Some(id) = call["id"].as_str() else {
                continue;
            };
            if answered.iter().any(|a| a == id) {
                continue;
            }
            let resumed = agent
                .run
                .resume
                .clone()
                .filter(|_| pending_call.as_deref() == Some(id));
            let result = match resumed {
                Some(resume) => {
                    let field = resume["field"].as_str().unwrap_or_default().to_string();
                    answer_result(&mut agent.ctx, &field, resume["value"].clone())
                }
                None => json!({
                    "error": "This call was interrupted before it finished. Call it again if it is still needed.",
                }),
            };
            messages
                .push(json!({ "role": "tool", "tool_call_id": id, "content": result.to_string() }));
        }
    }

    // What the user said while no worker held the run.
    let stored = agent.run.take_stored_messages().await?;
    if !stored.is_empty() {
        waiting_for_reply = false;
    }
    for text in stored {
        messages.push(llm::user(text));
    }
    save(&agent, &messages).await?;
    drive(agent, messages, specs, revision, waiting_for_reply).await
}

/// The loop: the model answers, its tools run, until the essay is delivered.
async fn drive(
    mut agent: Agent<'_>,
    mut messages: Vec<Value>,
    specs: Vec<Value>,
    revision: bool,
    mut waiting_for_reply: bool,
) -> Result<(), RunError> {
    let mut recent: HashMap<String, Instant> = HashMap::new();

    for _ in 0..MAX_STEPS {
        if waiting_for_reply {
            waiting_for_reply = false;
            let text = agent.run.wait_message().await?;
            messages.push(llm::user(text));
        }
        // What the user said while tools were running.
        for text in agent.run.take_messages() {
            messages.push(llm::user(text));
        }

        let reply = think(&agent, &messages, &specs).await?;
        let said = reply.content.trim();
        if !said.is_empty() {
            agent.run.say(said).await?;
        }

        if reply.tool_calls.is_empty() {
            messages.push(json!({ "role": "assistant", "content": reply.content }));
            save(&agent, &messages).await?;
            // A revision ends once the agent has answered; the next request
            // is a new run.
            if agent.ctx.export_ready || revision {
                return Ok(());
            }
            // The model asked something in plain text: wait for the reply.
            waiting_for_reply = true;
            continue;
        }

        messages.push(json!({
            "role": "assistant",
            "content": if reply.content.is_empty() { Value::Null } else { json!(reply.content) },
            "tool_calls": reply.tool_calls.iter().map(|call| json!({
                "id": call.id,
                "type": "function",
                "function": { "name": call.name, "arguments": call.arguments },
            })).collect::<Vec<_>>(),
        }));
        // Saved after every call, so a run cut off mid-turn resumes there.
        save(&agent, &messages).await?;
        for call in &reply.tool_calls {
            let result = dispatch(&mut agent, call, &mut recent).await?;
            messages.push(json!({
                "role": "tool",
                "tool_call_id": call.id,
                "content": result.to_string(),
            }));
            save(&agent, &messages).await?;
        }
    }

    Err(RunError::Failed(
        "This run took too many steps and was stopped.".to_string(),
    ))
}

/// One orchestrator round-trip, retried once.
async fn think(
    agent: &Agent<'_>,
    messages: &[Value],
    specs: &[Value],
) -> Result<llm::ChatReply, RunError> {
    let request = ChatRequest {
        model: agent.models.orchestrator.clone(),
        messages: messages.to_vec(),
        temperature: Some(0.3),
        json: false,
        tools: specs.to_vec(),
    };
    match agent.llm.chat(request.clone()).await {
        Ok(reply) => Ok(reply),
        Err(first) => {
            tracing::warn!(run_id = %agent.run.run_id, error = %first, "orchestrator call failed; retrying");
            agent.llm.chat(request).await.map_err(|error| {
                tracing::error!(run_id = %agent.run.run_id, %error, "orchestrator call failed twice");
                RunError::Failed("The model is not responding. Please try again.".to_string())
            })
        }
    }
}

/// Saves the run's context and conversation, for inspection and for resuming.
async fn save(agent: &Agent<'_>, messages: &[Value]) -> Result<(), RunError> {
    sqlx::query("UPDATE runs SET context = $2, messages = $3, updated_at = now() WHERE id = $1")
        .bind(agent.run.run_id)
        .bind(serde_json::to_value(&agent.ctx).unwrap_or_default())
        .bind(json!(messages))
        .execute(&agent.run.st.db)
        .await?;
    Ok(())
}

/// Runs one tool call and returns what goes back to the model.
async fn dispatch(
    agent: &mut Agent<'_>,
    call: &ToolCall,
    recent: &mut HashMap<String, Instant>,
) -> Result<Value, RunError> {
    let args: Value = if call.arguments.trim().is_empty() {
        json!({})
    } else {
        match serde_json::from_str(&call.arguments) {
            Ok(args) => args,
            Err(e) => return Ok(json!({ "error": format!("invalid JSON arguments: {e}") })),
        }
    };

    if call.name == "ask_user" {
        agent.run.call_id = Some(call.id.clone());
        return ask_user(agent, &args).await;
    }
    if !tools::exists(&call.name) {
        return Ok(json!({ "error": format!("unknown tool: {}", call.name) }));
    }

    let fingerprint = format!("{}:{args}", call.name);
    if recent
        .get(&fingerprint)
        .is_some_and(|at| at.elapsed() < DEDUP_WINDOW)
    {
        return Ok(json!({
            "error": format!("duplicate call to {} with identical arguments; try a different approach", call.name),
        }));
    }
    recent.insert(fingerprint, Instant::now());

    let step_id = Uuid::new_v4();
    agent
        .run
        .emit(
            "step_start",
            json!({ "stepId": step_id, "tool": call.name, "title": tools::title(&call.name, &args) }),
        )
        .await?;

    let outcome = tokio::time::timeout(
        tools::time_limit(&call.name),
        tools::execute(agent, step_id, &call.name, &args),
    )
    .await;
    // Whatever happened, a tool must not leave the document locked.
    let st = &agent.run.st;
    documents::unlock(&st.db, &st.docs, agent.run.project_id, agent.run.run_id).await?;

    let error = match outcome {
        Ok(Ok((result, summary))) => {
            agent
                .run
                .emit(
                    "step_done",
                    json!({ "stepId": step_id, "summary": summary }),
                )
                .await?;
            return Ok(result);
        }
        Ok(Err(Failure::Run(error))) => return Err(error),
        // The user asked for a rewrite while it wrote: nothing was kept or
        // charged, and the model starts it again.
        Ok(Err(Failure::Interrupted(instruction))) => {
            agent
                .run
                .emit(
                    "step_done",
                    json!({ "stepId": step_id, "summary": "Starting again with your note." }),
                )
                .await?;
            return Ok(json!({
                "interrupted": true,
                "instruction": instruction,
                "next": format!("Call {} again now; the instruction is already in the brief.", call.name),
            }));
        }
        Ok(Err(Failure::Tool(message))) => message,
        Err(_) => format!("{} took too long", call.name),
    };
    let error = agent.run.masked(&error).await;
    agent
        .run
        .emit(
            "step_error",
            json!({ "stepId": step_id, "error": error, "retryable": true }),
        )
        .await?;
    Ok(json!({ "error": error }))
}

/// `ask_user`: put the question to the user and wait.
async fn ask_user(agent: &mut Agent<'_>, args: &Value) -> Result<Value, RunError> {
    let field = args["field"]
        .as_str()
        .unwrap_or_default()
        .trim()
        .to_string();
    let question = args["question"]
        .as_str()
        .unwrap_or_default()
        .trim()
        .to_string();
    if field.is_empty() || question.is_empty() {
        return Ok(json!({ "error": "ask_user requires `field` and `question`" }));
    }

    let options: Vec<Value> = args["options"]
        .as_array()
        .map(|options| {
            options
                .iter()
                .filter_map(|option| {
                    let label = option["label"].as_str()?.trim();
                    let value = option["value"].as_str()?.trim();
                    (!label.is_empty() && !value.is_empty())
                        .then(|| json!({ "label": label, "value": value }))
                })
                .collect()
        })
        .unwrap_or_default();
    let suggestions: Vec<String> = args["suggestions"]
        .as_array()
        .map(|items| {
            items
                .iter()
                .map(|item| match item {
                    Value::String(s) => s.trim().to_string(),
                    other => other.to_string(),
                })
                .filter(|s| !s.is_empty())
                .collect()
        })
        .unwrap_or_default();

    // The essay-focus question is always a multi-select, and the source
    // review its own sheet, whatever the model said.
    let input_type = if field == "essayFocus" {
        "multiselect"
    } else if field == "sourceReview" {
        "sourceReview"
    } else {
        args["inputType"]
            .as_str()
            .filter(|kind| matches!(*kind, "number" | "select" | "multiselect"))
            .unwrap_or("text")
    };
    let allow_custom = args["allowCustom"]
        .as_bool()
        .unwrap_or(input_type != "select");

    let mut payload = json!({
        "question": question,
        "inputType": input_type,
        "allowCustom": allow_custom,
    });
    if !options.is_empty() {
        payload["options"] = json!(options);
    }
    if !suggestions.is_empty() {
        payload["suggestions"] = json!(suggestions);
    }
    if input_type == "sourceReview" {
        // The sources the user reviews: the ones that were read.
        let sources: Vec<&context::Source> = agent.ctx.scraped.iter().map(|s| &s.source).collect();
        if sources.is_empty() {
            return Ok(json!({ "error": "no sources to review yet; run scrape_sources first" }));
        }
        payload["sources"] = json!(sources);
        payload["allowCustom"] = json!(false);
    }

    let answer = agent.run.ask(&field, payload).await?;
    Ok(answer_result(&mut agent.ctx, &field, answer))
}

/// What the model is told about the user's reply to a question: their
/// answer, or a message they wrote instead (already answered), after which
/// it asks again.
fn answer_result(ctx: &mut Context, field: &str, answer: Value) -> Value {
    if let Some(message) = answer.get("userMessage") {
        return json!({
            "userMessage": message,
            "note": "The user wrote this instead of answering. Take it into account, then ask the same question again with ask_user.",
        });
    }
    ctx.apply_answer(field, &answer);
    json!({ "answer": answer })
}

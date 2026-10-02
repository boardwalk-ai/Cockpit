//! The agent loop: the model picks a tool, the tool runs, the result goes back,
//! until the essay is delivered.
//!
//! A port of OctopilotWeb's `agent/loop.ts`. Every transition is an event on
//! the run, so the app's timeline is this loop, seen from outside.

pub mod context;
pub mod prompt;
pub mod tools;

use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};

use serde_json::{json, Value};
use uuid::Uuid;

use self::context::Context;
use self::tools::Failure;
use crate::documents;
use crate::llm::{self, ChatRequest, Llm, OpenRouter, ToolCall};
use crate::runs::driver::{RunCtx, RunError};
use crate::scrape::Scraper;

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
    async fn load(run: &RunCtx) -> Self {
        const PRIMARY: &str = "anthropic/claude-sonnet-4-6";
        let Some(pool) = &run.st.octopilot else {
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

/// What a tool works with.
pub struct Agent<'a> {
    pub run: &'a mut RunCtx,
    pub ctx: Context,
    pub llm: Arc<dyn Llm>,
    pub scraper: Arc<dyn Scraper>,
    pub models: Models,
}

/// The model for this run: the injected one (tests), or OpenRouter with a key
/// from the shared pool.
async fn model_client(run: &RunCtx) -> Result<Arc<dyn Llm>, RunError> {
    if let Some(llm) = &run.st.llm {
        return Ok(llm.clone());
    }
    let key = match &run.st.octopilot {
        Some(pool) => octo_common::llm::openrouter_key(pool).await,
        None => None,
    };
    let key = key.ok_or_else(|| {
        tracing::error!("no active OpenRouter key in api_keys");
        RunError::Failed("GhostWriter is not set up to write right now.".to_string())
    })?;
    Ok(Arc::new(OpenRouter::new(run.st.http.clone(), key)))
}

/// Drives one run to the delivered essay.
pub async fn run(run: &mut RunCtx) -> Result<(), RunError> {
    let llm = model_client(run).await?;
    let models = Models::load(run).await;
    let scraper = run.st.scraper.clone();
    let instruction = run.instruction.clone();

    run.emit("user_message", json!({ "text": instruction }))
        .await?;

    let today = chrono::Utc::now().format("%B %-d, %Y").to_string();
    let mut messages = vec![
        llm::system(prompt::orchestrator()),
        llm::user(prompt::user_brief(&instruction, &today)),
    ];
    let mut agent = Agent {
        run,
        ctx: Context {
            instruction,
            ..Context::default()
        },
        llm,
        scraper,
        models,
    };
    let specs = tools::specs();
    let mut recent: HashMap<String, Instant> = HashMap::new();

    for _ in 0..MAX_STEPS {
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
            if agent.ctx.export_ready {
                return Ok(());
            }
            // The model asked something in plain text: wait for the reply.
            let text = agent.run.wait_message().await?;
            messages.push(llm::user(text));
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
        for call in &reply.tool_calls {
            let result = dispatch(&mut agent, call, &mut recent).await?;
            messages.push(json!({
                "role": "tool",
                "tool_call_id": call.id,
                "content": result.to_string(),
            }));
        }
        save(&agent, &messages).await?;
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
        Ok(Err(Failure::Tool(message))) => message,
        Err(_) => format!("{} took too long", call.name),
    };
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

    // The essay-focus question is always a multi-select, whatever the model said.
    let input_type = if field == "essayFocus" {
        "multiselect"
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

    let answer = agent.run.ask(&field, payload).await?;
    agent.ctx.apply_answer(&field, &answer);
    Ok(json!({ "answer": answer }))
}

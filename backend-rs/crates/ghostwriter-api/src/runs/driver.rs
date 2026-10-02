//! What drives a run. A driver gets a [`RunCtx`] and talks to the user only
//! through it: emit events, ask questions, read chat messages.
//!
//! The scripted driver walks the same steps the real agent will, with canned
//! content and no model calls. It exercises the whole event protocol and lets
//! the app be built and demoed without spending credits.

use std::time::Duration;

use serde_json::{json, Value};
use uuid::Uuid;

use super::{append, emit, emit_live, finish, Inbox, Outcome};
use crate::AppState;

/// Why a driver stopped early.
#[derive(Debug)]
pub enum RunError {
    /// The run was closed under the driver (cancelled, or closed elsewhere).
    Stopped,
    /// The run cannot continue; the message is shown to the user.
    Failed(String),
    Db(sqlx::Error),
}

impl From<sqlx::Error> for RunError {
    fn from(e: sqlx::Error) -> Self {
        RunError::Db(e)
    }
}

/// A driver's handle on its run.
pub struct RunCtx {
    pub st: AppState,
    pub run_id: Uuid,
    pub project_id: Uuid,
    pub user_id: Uuid,
    pub instruction: String,
    inbox: Inbox,
}

impl RunCtx {
    /// Emits a stored event.
    pub async fn emit(&self, kind: &str, payload: Value) -> Result<(), RunError> {
        emit(&self.st, self.run_id, kind, payload).await?;
        Ok(())
    }

    /// Emits a live-only event (a text delta).
    pub fn emit_live(&self, kind: &str, payload: Value) {
        emit_live(&self.st, self.run_id, kind, payload);
    }

    /// Asks the user a question and waits for the answer to `field`.
    pub async fn ask(&mut self, field: &str, mut question: Value) -> Result<Value, RunError> {
        question["field"] = json!(field);

        {
            let _guard = self.st.hub.lock(self.run_id).await;
            let waiting = sqlx::query(
                "UPDATE runs SET status = 'waiting_for_user', pending_question = $2, \
                     updated_at = now() \
                 WHERE id = $1 AND status = 'running'",
            )
            .bind(self.run_id)
            .bind(&question)
            .execute(&self.st.db)
            .await?
            .rows_affected();
            if waiting == 0 {
                return Err(RunError::Stopped);
            }
            append(&self.st, self.run_id, "question", question).await?;
        }

        let limit = self.st.config.ask_timeout;
        loop {
            match tokio::time::timeout(limit, self.inbox.answers.recv()).await {
                Ok(Some((answered, value))) if answered == field => return Ok(value),
                Ok(Some(_)) => continue,
                Ok(None) => return Err(RunError::Stopped),
                Err(_) => {
                    return Err(RunError::Failed(
                        "Timed out waiting for your answer.".to_string(),
                    ))
                }
            }
        }
    }

    /// Waits for the user's next chat message: the model asked something in
    /// plain text rather than through `ask`.
    pub async fn wait_message(&mut self) -> Result<String, RunError> {
        {
            let _guard = self.st.hub.lock(self.run_id).await;
            let waiting = sqlx::query(
                "UPDATE runs SET status = 'waiting_for_user', updated_at = now()                  WHERE id = $1 AND status = 'running'",
            )
            .bind(self.run_id)
            .execute(&self.st.db)
            .await?
            .rows_affected();
            if waiting == 0 {
                return Err(RunError::Stopped);
            }
            // Tells the app the run is now waiting on the chat box.
            append(&self.st, self.run_id, "awaiting_reply", json!({})).await?;
        }

        let text = match tokio::time::timeout(
            self.st.config.ask_timeout,
            self.inbox.messages.recv(),
        )
        .await
        {
            Ok(Some(text)) => text,
            Ok(None) => return Err(RunError::Stopped),
            Err(_) => {
                return Err(RunError::Failed(
                    "Timed out waiting for your reply.".to_string(),
                ))
            }
        };
        sqlx::query(
            "UPDATE runs SET status = 'running', updated_at = now()              WHERE id = $1 AND status = 'waiting_for_user'",
        )
        .bind(self.run_id)
        .execute(&self.st.db)
        .await?;
        Ok(text)
    }

    /// Chat messages the user sent since the last call.
    pub fn take_messages(&mut self) -> Vec<String> {
        let mut messages = Vec::new();
        while let Ok(text) = self.inbox.messages.try_recv() {
            messages.push(text);
        }
        messages
    }

    /// One running step: `step_start`, the work, then `step_done`.
    async fn step(&self, tool: &str, title: &str, summary: &str) -> Result<(), RunError> {
        let step_id = Uuid::new_v4();
        self.emit(
            "step_start",
            json!({ "stepId": step_id, "tool": tool, "title": title }),
        )
        .await?;
        self.pause().await;
        self.emit(
            "step_done",
            json!({ "stepId": step_id, "summary": summary }),
        )
        .await
    }

    async fn pause(&self) {
        let pause = self.st.config.scripted_step;
        if !pause.is_zero() {
            tokio::time::sleep(pause).await;
        }
    }

    /// Says something as GhostWriter: deltas for a live client, then the
    /// stored message.
    pub(crate) async fn say(&self, text: &str) -> Result<(), RunError> {
        for word in text.split_inclusive(' ') {
            self.emit_live("assistant_delta", json!({ "chunk": word }));
        }
        self.emit("assistant_message", json!({ "text": text }))
            .await
    }
}

/// Starts the run's driver in the background.
pub fn spawn(st: AppState, run_id: Uuid, project_id: Uuid, user_id: Uuid, instruction: String) {
    let inbox = st.hub.open(run_id);
    let mut ctx = RunCtx {
        st: st.clone(),
        run_id,
        project_id,
        user_id,
        instruction,
        inbox,
    };

    let task = tokio::spawn(async move {
        let result = if ctx.st.config.driver == "scripted" {
            scripted(&mut ctx).await
        } else {
            crate::agent::run(&mut ctx).await
        };
        let outcome = match result {
            Ok(()) => Outcome::Finished,
            // Whoever stopped the run has closed it already.
            Err(RunError::Stopped) => return,
            Err(RunError::Failed(message)) => Outcome::Failed(message),
            Err(RunError::Db(error)) => {
                tracing::error!(%run_id, %error, "run failed on a database error");
                Outcome::Failed("Something went wrong on our side.".to_string())
            }
        };
        if let Err(error) = finish(&ctx.st, run_id, outcome).await {
            tracing::error!(%run_id, %error, "could not close run");
        }
    });
    st.hub.set_abort(run_id, task.abort_handle());
}

fn option(label: &str) -> Value {
    json!({ "label": label, "value": label })
}

/// The scripted run: the real workflow's steps and questions, canned content.
async fn scripted(ctx: &mut RunCtx) -> Result<(), RunError> {
    ctx.emit("user_message", json!({ "text": ctx.instruction }))
        .await?;

    ctx.step(
        "plan_essay",
        "Planning the essay",
        "Thesis and angles drafted.",
    )
    .await?;

    let focus = ctx
        .ask(
            "essayFocus",
            json!({
                "question": "What should this essay focus on? Pick the angles that matter most.",
                "inputType": "multiselect",
                "allowCustom": true,
                "options": [
                    option("Causes and background"),
                    option("Economic impact"),
                    option("Social impact"),
                    option("Policy responses"),
                    option("Future outlook"),
                ],
            }),
        )
        .await?;
    let angles = focus.as_array().map_or(1, Vec::len).max(1);

    for message in ctx.take_messages() {
        ctx.say(&format!("Noted: {message}")).await?;
    }

    ctx.step(
        "generate_outlines",
        "Building the outline",
        &format!("{} paragraphs outlined.", angles + 4),
    )
    .await?;
    ctx.step(
        "search_sources",
        "Searching for sources",
        "5 sources found.",
    )
    .await?;
    ctx.step("scrape_sources", "Reading the sources", "5 sources read.")
        .await?;
    ctx.emit("sources_ready", json!({ "count": 5 })).await?;

    let words = ctx
        .ask(
            "wordCount",
            json!({
                "question": "What word count should I target?",
                "inputType": "number",
                "allowCustom": true,
                "suggestions": ["500", "800", "1200", "2000", "3000"],
            }),
        )
        .await?;
    let target = words
        .as_i64()
        .or_else(|| words.as_str().and_then(|s| s.trim().parse().ok()))
        .filter(|n| (50..=20_000).contains(n))
        .ok_or_else(|| RunError::Failed("That word count is not usable.".to_string()))?;

    ctx.ask(
        "citationStyle",
        json!({
            "question": "Which citation format?",
            "inputType": "select",
            "allowCustom": false,
            "options": [
                option("APA"), option("MLA"), option("Chicago"),
                option("Harvard"), option("IEEE"), option("None"),
            ],
        }),
    )
    .await?;

    ctx.say("Thanks. Writing your essay now.").await?;

    let step_id = Uuid::new_v4();
    ctx.emit(
        "step_start",
        json!({ "stepId": step_id, "tool": "write_essay", "title": "Writing the essay" }),
    )
    .await?;
    ctx.emit("writing_started", json!({ "targetWords": target }))
        .await?;
    // A real draft may overshoot its target; so does this one.
    for percent in [20, 45, 70, 95, 104] {
        ctx.pause().await;
        ctx.emit(
            "write_progress",
            json!({ "words": target * percent / 100, "targetWords": target }),
        )
        .await?;
    }
    ctx.emit(
        "step_done",
        json!({ "stepId": step_id, "summary": format!("{} words written.", target * 104 / 100) }),
    )
    .await?;

    Ok(())
}

/// Default wait for an answer before a run gives up.
pub const DEFAULT_ASK_TIMEOUT: Duration = Duration::from_secs(30 * 60);

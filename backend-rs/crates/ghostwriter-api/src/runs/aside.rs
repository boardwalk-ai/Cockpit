//! A message the user sends while a run is going. It is answered at once by
//! the fast model, without stopping the run, and then handed to the run:
//!
//! - an instruction is kept as a directive (every later writer, reviser and
//!   outliner brief carries it) and, if the essay is being written, the
//!   writer starts again with it;
//! - "stop" stops the run;
//! - a run waiting on a question is woken: the agent hears the message and
//!   asks again.
//!
//! The quick reply costs no credits.

use serde_json::{json, Value};
use uuid::Uuid;

use super::{emit, finish, Outcome};
use crate::agent::context::AiSnapshot;
use crate::agent::prompt;
use crate::llm::{system, user, ChatRequest};
use crate::AppState;

/// Quick replies one run may get per minute; past that, messages go to the
/// run unanswered.
const REPLIES_PER_MINUTE: i64 = 10;

#[derive(Debug, PartialEq, Eq)]
pub enum Kind {
    Question,
    Instruction,
    Stop,
    Chat,
}

impl Kind {
    fn parse(text: &str) -> Self {
        match text.trim().to_lowercase().as_str() {
            "instruction" => Self::Instruction,
            "stop" => Self::Stop,
            "question" => Self::Question,
            _ => Self::Chat,
        }
    }
}

/// Answers the message, acts on it, and hands it to the run.
pub async fn handle(st: AppState, run_id: Uuid, project_id: Uuid, text: String) {
    // The agent asked something in plain text and waits: this message is the
    // reply it asked for, not a message on the side.
    let awaited: Option<bool> = sqlx::query_scalar(
        "SELECT status = 'waiting_for_user' AND pending_question IS NULL FROM runs WHERE id = $1",
    )
    .bind(run_id)
    .fetch_optional(&st.db)
    .await
    .unwrap_or(None);
    if awaited == Some(true) {
        if let Err(error) = deliver(&st, run_id, text, true).await {
            tracing::warn!(%run_id, %error, "aside: reply not delivered");
        }
        return;
    }

    let quick = match quick_reply(&st, run_id, project_id, &text).await {
        Ok(quick) => quick,
        Err(error) => {
            tracing::warn!(%run_id, %error, "aside: no quick reply");
            None
        }
    };

    // Only a message that may change the work sets a waiting question aside
    // (to be asked again in its light); a question or a "thanks" leaves the
    // card where it is.
    let mut changes_the_work = true;
    let for_run = match quick {
        None => text,
        Some((reply, kind)) => {
            if let Err(error) = emit(
                &st,
                run_id,
                "assistant_message",
                json!({ "text": reply, "aside": true }),
            )
            .await
            {
                tracing::warn!(%run_id, %error, "aside: reply not logged");
                return;
            }
            match kind {
                Kind::Stop => {
                    st.hub.abort(run_id);
                    if let Err(error) = finish(&st, run_id, Outcome::Cancelled).await {
                        tracing::error!(%run_id, %error, "aside: could not stop the run");
                    }
                    return;
                }
                Kind::Instruction => {
                    if let Err(error) = add_directive(&st, run_id, &text).await {
                        tracing::warn!(%run_id, %error, "aside: directive not kept");
                    }
                    st.hub.request_rewrite(run_id, &text);
                }
                Kind::Question | Kind::Chat => changes_the_work = false,
            }
            prompt::aside_note(&text, &reply)
        }
    };

    if let Err(error) = deliver(&st, run_id, for_run, changes_the_work).await {
        tracing::warn!(%run_id, %error, "aside: message not delivered");
    }
}

/// The fast model's reply and its reading of the message, or `None` when
/// there is no model or the run has had its share of quick replies.
async fn quick_reply(
    st: &AppState,
    run_id: Uuid,
    project_id: Uuid,
    text: &str,
) -> Result<Option<(String, Kind)>, String> {
    let recent: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM run_events WHERE run_id = $1 AND type = 'assistant_message' \
         AND payload->>'aside' = 'true' AND created_at > now() - interval '1 minute'",
    )
    .bind(run_id)
    .fetch_one(&st.db)
    .await
    .map_err(|e| e.to_string())?;
    if recent >= REPLIES_PER_MINUTE {
        return Ok(None);
    }
    let Some((llm, mut models)) = crate::agent::client(st).await else {
        return Ok(None);
    };
    // The run's model and voice, as fixed when it started.
    let ai: Option<AiSnapshot> =
        sqlx::query_scalar::<_, Option<Value>>("SELECT context->'ai' FROM runs WHERE id = $1")
            .bind(run_id)
            .fetch_optional(&st.db)
            .await
            .map_err(|e| e.to_string())?
            .flatten()
            .and_then(|v| serde_json::from_value(v).ok());
    models.apply(ai.as_ref());
    let ai = ai.unwrap_or_default();

    let situation = situation(st, run_id, project_id)
        .await
        .map_err(|e| e.to_string())?;
    let reply = llm
        .chat(ChatRequest {
            model: models.secondary,
            messages: vec![
                system(format!(
                    "{}{}",
                    prompt::ASIDE,
                    prompt::persona(&ai.name, ai.voice.as_deref())
                )),
                user(format!("{situation}\n\nTHE USER'S MESSAGE\n{text}")),
            ],
            temperature: Some(0.3),
            json: true,
            tools: Vec::new(),
            reasoning: None,
        })
        .await?;
    let parsed = octo_common::llm::parse_json_loose(&reply.content).unwrap_or(Value::Null);
    let answer = parsed["reply"].as_str().map(str::trim).unwrap_or_default();
    if answer.is_empty() {
        return Err("the quick reply was empty".into());
    }
    let terms = octo_common::ai::masked_terms(st.octopilot.as_ref()).await;
    let (answer, _) = octo_common::ai::mask(answer, &terms, &ai.name);
    Ok(Some((
        answer,
        Kind::parse(parsed["kind"].as_str().unwrap_or_default()),
    )))
}

/// What the run is about and what it is doing, for the quick reply.
async fn situation(st: &AppState, run_id: Uuid, project_id: Uuid) -> Result<String, sqlx::Error> {
    let (title, instruction): (String, String) =
        sqlx::query_as("SELECT title, instruction FROM projects WHERE id = $1")
            .bind(project_id)
            .fetch_one(&st.db)
            .await?;
    let question: Option<String> = sqlx::query_scalar(
        "SELECT pending_question->>'question' FROM runs WHERE id = $1 AND status = 'waiting_for_user'",
    )
    .bind(run_id)
    .fetch_optional(&st.db)
    .await?
    .flatten();
    let step: Option<String> = sqlx::query_scalar(
        "SELECT s.payload->>'title' FROM run_events s \
         WHERE s.run_id = $1 AND s.type = 'step_start' AND NOT EXISTS ( \
             SELECT 1 FROM run_events e WHERE e.run_id = $1 \
               AND e.type IN ('step_done', 'step_error') \
               AND e.payload->>'stepId' = s.payload->>'stepId') \
         ORDER BY s.seq DESC LIMIT 1",
    )
    .bind(run_id)
    .fetch_optional(&st.db)
    .await?
    .flatten();
    let directives = directives(st, project_id).await?;

    let doing = match (question, step) {
        (Some(question), _) => format!("Waiting for the user to answer: {question}"),
        (None, Some(step)) => format!("Working on: {step}"),
        (None, None) => "Between steps.".to_string(),
    };
    let mut out = format!("THE ESSAY\n{title}\nBrief: {instruction}\n\nRIGHT NOW\n{doing}");
    if !directives.is_empty() {
        out.push_str(&format!(
            "\n\nINSTRUCTIONS ALREADY GIVEN\n- {}",
            directives.join("\n- ")
        ));
    }
    Ok(out)
}

/// Every instruction the user gave on this project, oldest first.
pub async fn directives(st: &AppState, project_id: Uuid) -> Result<Vec<String>, sqlx::Error> {
    sqlx::query_scalar(
        "SELECT d FROM runs r CROSS JOIN LATERAL jsonb_array_elements_text(r.directives) d \
         WHERE r.project_id = $1 ORDER BY r.created_at",
    )
    .bind(project_id)
    .fetch_all(&st.db)
    .await
}

async fn add_directive(st: &AppState, run_id: Uuid, text: &str) -> Result<(), sqlx::Error> {
    sqlx::query(
        "UPDATE runs SET directives = directives || jsonb_build_array($2::text) WHERE id = $1",
    )
    .bind(run_id)
    .bind(text)
    .execute(&st.db)
    .await?;
    Ok(())
}

/// Hands the message to the run: set against a question it is waiting on
/// (`set_aside`: it hears the message and asks again), to a run that is
/// working, or kept for when a worker picks it up.
async fn deliver(
    st: &AppState,
    run_id: Uuid,
    text: String,
    set_aside: bool,
) -> Result<(), sqlx::Error> {
    let pending: Option<String> = sqlx::query_scalar(
        "SELECT pending_question->>'field' FROM runs WHERE id = $1 AND status = 'waiting_for_user'",
    )
    .bind(run_id)
    .fetch_optional(&st.db)
    .await?
    .flatten();
    if let Some(field) = pending {
        if set_aside {
            let value = json!({ "userMessage": text });
            if super::answer(st, run_id, &field, value, true).await? {
                return Ok(());
            }
        } else {
            // For the agent, which reads it once the question is answered.
            if st.hub.deliver_message(run_id, text.clone()) {
                return Ok(());
            }
            sqlx::query(
                "UPDATE runs SET inbox = inbox || jsonb_build_array($2::text) WHERE id = $1",
            )
            .bind(run_id)
            .bind(&text)
            .execute(&st.db)
            .await?;
            return Ok(());
        }
    }

    let _guard = st.hub.lock(run_id).await;
    if st.hub.deliver_message(run_id, text.clone()) {
        return Ok(());
    }
    // No worker holds the run: keep the message for whoever picks it up, and
    // wake a run that is parked waiting for exactly this.
    let woken: Option<String> = sqlx::query_scalar(
        "UPDATE runs SET inbox = inbox || jsonb_build_array($2::text), updated_at = now(), \
             status = CASE WHEN status = 'waiting_for_user' AND pending_question IS NULL \
                 THEN 'queued' ELSE status END \
         WHERE id = $1 RETURNING status",
    )
    .bind(run_id)
    .bind(&text)
    .fetch_optional(&st.db)
    .await?;
    if woken.as_deref() == Some("queued") {
        st.worker.wake();
    }
    Ok(())
}

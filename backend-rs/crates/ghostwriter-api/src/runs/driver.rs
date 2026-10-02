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
use crate::documents::{self, AgentSave, DocError};
use crate::humanize::{self, Provider};
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

impl From<DocError> for RunError {
    fn from(e: DocError) -> Self {
        match e {
            DocError::Locked => {
                RunError::Failed("Another run is writing this document.".to_string())
            }
            DocError::Db(e) => RunError::Db(e),
        }
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

/// Placeholder sources for the scripted run.
fn scripted_sources() -> Vec<Value> {
    [
        (
            "Sea Level Rise Scenarios",
            "Sweet, W.",
            "2022",
            "NOAA",
            "https://example.org/noaa-slr",
        ),
        (
            "Managed Retreat",
            "Hino, M.",
            "2017",
            "Nature Climate Change",
            "https://example.org/retreat",
        ),
        (
            "Coastal Flood Costs",
            "Hallegatte, S.",
            "2013",
            "Nature Climate Change",
            "https://example.org/flood-costs",
        ),
        (
            "Living with Water",
            "Dircke, P.",
            "2020",
            "Delta Programme",
            "https://example.org/living-with-water",
        ),
        (
            "Tides and Cities",
            "Ward, P.",
            "2018",
            "Urban Climate",
            "https://example.org/tides-cities",
        ),
    ]
    .into_iter()
    .map(|(title, author, year, publisher, url)| {
        json!({
            "url": url,
            "title": title,
            "author": author,
            "publishedYear": year,
            "publisher": publisher,
        })
    })
    .collect()
}

/// The scripted run: the real workflow's steps and questions, canned content.
async fn scripted(ctx: &mut RunCtx) -> Result<(), RunError> {
    ctx.emit("user_message", json!({ "text": ctx.instruction }))
        .await?;

    // An essay already written: this run is a revision.
    let written: Option<String> = sqlx::query_scalar(
        "SELECT body FROM documents WHERE project_id = $1 AND btrim(body) <> ''",
    )
    .bind(ctx.project_id)
    .fetch_optional(&ctx.st.db)
    .await?;
    if let Some(body) = written {
        return scripted_revise(ctx, &body).await;
    }

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

    let sources = scripted_sources();
    let choice = ctx
        .ask(
            "sourceReviewChoice",
            json!({
                "question": "Sources are ready. Would you like to review them before I start writing?",
                "inputType": "select",
                "allowCustom": false,
                "options": [option("One Shot"), option("Review Sources")],
            }),
        )
        .await?;
    let mut kept = sources.clone();
    if choice.as_str() == Some("Review Sources") {
        let review = ctx
            .ask(
                "sourceReview",
                json!({
                    "question": "Review each source. Add a note to steer its summary, or leave it out.",
                    "inputType": "sourceReview",
                    "allowCustom": false,
                    "sources": sources,
                }),
            )
            .await?;
        let rejected: Vec<&str> = review
            .as_array()
            .map(|notes| {
                notes
                    .iter()
                    .filter(|note| note["rejected"] == true)
                    .filter_map(|note| note["url"].as_str())
                    .collect()
            })
            .unwrap_or_default();
        kept.retain(|source| !rejected.contains(&source["url"].as_str().unwrap_or_default()));
    }
    ctx.step(
        "compact_sources",
        "Summarising the sources",
        &format!("{} sources ready to cite.", kept.len()),
    )
    .await?;
    ctx.emit(
        "sources_ready",
        json!({ "count": kept.len(), "sources": kept }),
    )
    .await?;

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

    let style = ctx
        .ask(
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
    let style = documents::style_key(style.as_str().unwrap_or_default());
    let words = scripted_write(ctx, target, style).await?;
    ctx.emit(
        "step_done",
        json!({ "stepId": step_id, "summary": format!("{words} words written.") }),
    )
    .await?;

    if ctx.st.config.scripted_humanizer {
        scripted_humanize(ctx).await?;
    }

    Ok(())
}

/// The scripted run's humanizer step: the same questions the agent asks, and a
/// canned humanizer. "StealthGPT" merges the paragraphs, as the real one does,
/// so the paragraph question and its restore can be seen too.
async fn scripted_humanize(ctx: &mut RunCtx) -> Result<(), RunError> {
    let choice = ctx
        .ask(
            "humanizerChoice",
            json!({
                "question": "Your essay is ready. Would you like to humanize it?",
                "inputType": "select",
                "allowCustom": false,
                "options": [option("StealthGPT"), option("UndetectableAI"), option("Skip")],
            }),
        )
        .await?;
    let Some(provider) = choice.as_str().and_then(Provider::parse) else {
        return Ok(());
    };

    let original: String = sqlx::query_scalar("SELECT body FROM documents WHERE project_id = $1")
        .bind(ctx.project_id)
        .fetch_one(&ctx.st.db)
        .await?;
    let merged = provider == Provider::StealthGpt;
    let humanized = if merged {
        humanize::paragraphs(&original).join(" ")
    } else {
        original.clone()
    };
    let step_id = Uuid::new_v4();
    let words = scripted_rewrite(
        ctx,
        step_id,
        "humanize_essay",
        &format!("Humanizing with {}", provider.label()),
        &humanized,
    )
    .await?;
    ctx.emit(
        "step_done",
        json!({ "stepId": step_id, "summary": format!("Humanized with {} · {words} words.", provider.label()) }),
    )
    .await?;

    if !merged {
        return Ok(());
    }
    let split = ctx
        .ask(
            "paragraphSplitChoice",
            json!({
                "question": "The humanizer merged the paragraphs. Should I restore them?",
                "inputType": "select",
                "allowCustom": false,
                "options": [
                    { "label": "Restore paragraphs", "value": "AI split" },
                    { "label": "Leave as is", "value": "Skip split" },
                ],
            }),
        )
        .await?;
    if split == "AI split" {
        let step_id = Uuid::new_v4();
        scripted_rewrite(
            ctx,
            step_id,
            "split_paragraphs",
            "Restoring the paragraphs",
            &original,
        )
        .await?;
        ctx.emit(
            "step_done",
            json!({ "stepId": step_id, "summary": format!("{} paragraphs restored.", humanize::paragraphs(&original).len()) }),
        )
        .await?;
    }
    Ok(())
}

/// Replaces the essay body the way the agent's humanizer tools do: locked,
/// a version kept, saved, unlocked. Emits `step_start`; the caller ends the step.
async fn scripted_rewrite(
    ctx: &RunCtx,
    step_id: Uuid,
    tool: &str,
    title: &str,
    body: &str,
) -> Result<i64, RunError> {
    let st = &ctx.st;
    let (project_id, run_id) = (ctx.project_id, ctx.run_id);
    ctx.emit(
        "step_start",
        json!({ "stepId": step_id, "tool": tool, "title": title }),
    )
    .await?;
    documents::begin_agent_write(&st.db, project_id, run_id, "humanize").await?;
    st.docs.changed(project_id);
    ctx.pause().await;
    let save = AgentSave {
        body: Some(body),
        ..AgentSave::default()
    };
    let (rev, words) = documents::save_agent(&st.db, project_id, run_id, save).await?;
    documents::unlock(&st.db, &st.docs, project_id, run_id).await?;
    ctx.emit(
        "document_updated",
        json!({ "rev": rev, "wordCount": words }),
    )
    .await?;
    Ok(words)
}

/// Writes a canned essay into the document the way the agent does: locked,
/// streamed to open editors, saved as it goes, then unlocked.
async fn scripted_write(ctx: &RunCtx, target: i64, style: &str) -> Result<i64, RunError> {
    let st = &ctx.st;
    let (db, docs) = (&st.db, &st.docs);
    let (project_id, run_id) = (ctx.project_id, ctx.run_id);

    documents::begin_agent_write(db, project_id, run_id, "agent_write").await?;
    docs.begin(project_id);
    ctx.emit("writing_started", json!({ "targetWords": target }))
        .await?;

    // A real draft may overshoot its target; so does this one.
    let length = target * 104 / 100;
    let draft = canned_essay(length);
    let essay = first_words(&draft, length as usize);
    let mut streamed = 0;
    for percent in [20, 45, 70, 95, 104] {
        let words = target * percent / 100;
        let upto = first_words(essay, words as usize).len();
        // Typed out over the pause, a word at a time, for an open editor.
        let pieces: Vec<&str> = essay[streamed..upto].split_inclusive(' ').collect();
        let beat = st.config.scripted_step / pieces.len().max(1) as u32;
        if beat.is_zero() {
            docs.append(project_id, &essay[streamed..upto]);
        } else {
            for piece in pieces {
                docs.append(project_id, piece);
                tokio::time::sleep(beat).await;
            }
        }
        streamed = upto;

        let save = AgentSave {
            body: Some(&essay[..upto]),
            ..AgentSave::default()
        };
        let (rev, _) = documents::save_agent(db, project_id, run_id, save).await?;
        docs.committed(project_id, rev);
        ctx.emit(
            "write_progress",
            json!({ "words": words, "targetWords": target }),
        )
        .await?;
    }

    let title: String = ctx.instruction.chars().take(80).collect();
    let save = AgentSave {
        body: Some(essay),
        bibliography: Some(SCRIPTED_BIBLIOGRAPHY),
        title: Some(title.trim()),
        style: Some(style),
        ..AgentSave::default()
    };
    let (rev, words) = documents::save_agent(db, project_id, run_id, save).await?;
    documents::unlock(db, docs, project_id, run_id).await?;
    ctx.emit(
        "document_updated",
        json!({ "rev": rev, "wordCount": words }),
    )
    .await?;
    Ok(words)
}

/// A canned revision: the essay comes back with a closing note that quotes
/// the request, written the way the agent writes (locked, streamed, saved).
async fn scripted_revise(ctx: &mut RunCtx, body: &str) -> Result<(), RunError> {
    let st = &ctx.st;
    let (db, docs) = (&st.db, &st.docs);
    let (project_id, run_id) = (ctx.project_id, ctx.run_id);
    let step_id = Uuid::new_v4();
    ctx.emit(
        "step_start",
        json!({ "stepId": step_id, "tool": "revise_essay", "title": "Revising the essay" }),
    )
    .await?;

    let current = crate::pricing::count_words(body);
    documents::begin_agent_write(db, project_id, run_id, "agent_revise").await?;
    docs.begin(project_id);
    ctx.emit("writing_started", json!({ "targetWords": current }))
        .await?;

    let revised = format!(
        "{}\n\nRevision note: {}",
        body.trim(),
        ctx.instruction.trim()
    );
    let pieces: Vec<&str> = revised.split_inclusive("\n\n").collect();
    let beat = st.config.scripted_step / pieces.len().max(1) as u32;
    let mut sent = 0;
    for piece in &pieces {
        docs.append(project_id, piece);
        sent += piece.len();
        if !beat.is_zero() {
            tokio::time::sleep(beat).await;
        }
        let save = AgentSave {
            body: Some(revised[..sent].trim()),
            ..AgentSave::default()
        };
        let (rev, words) = documents::save_agent(db, project_id, run_id, save).await?;
        docs.committed(project_id, rev);
        ctx.emit(
            "write_progress",
            json!({ "words": words, "targetWords": current }),
        )
        .await?;
    }
    let save = AgentSave {
        body: Some(revised.trim()),
        ..AgentSave::default()
    };
    let (rev, words) = documents::save_agent(db, project_id, run_id, save).await?;
    documents::unlock(db, docs, project_id, run_id).await?;
    ctx.emit(
        "document_updated",
        json!({ "rev": rev, "wordCount": words }),
    )
    .await?;
    ctx.emit(
        "step_done",
        json!({ "stepId": step_id, "summary": format!("Revised · {words} words.") }),
    )
    .await?;
    ctx.say("Done. I added your note at the end of the essay.")
        .await
}

const SCRIPTED_SENTENCES: [&str; 6] = [
    "This draft was written by the scripted driver, so no model was called.",
    "Each paragraph stands in for the argument a real run would make from its sources.",
    "The claims here are placeholders, but the shape of the essay is real.",
    "A citation would sit at the end of a sentence like this one (Author, 2024).",
    "The text streams into the editor as it is written and is saved every few seconds.",
    "When the run ends, the document unlocks and can be edited.",
];

const SCRIPTED_BIBLIOGRAPHY: &str = "Author, A. (2024). A placeholder source. Example Press.
     Writer, B. (2023). Another placeholder source. Example Journal, 1(1), 1-10.";

/// About `words` words of placeholder prose, in paragraphs of four sentences.
fn canned_essay(words: i64) -> String {
    let mut essay = String::new();
    let mut count = 0;
    let mut sentences = SCRIPTED_SENTENCES.iter().cycle().enumerate();
    while count < words {
        let (index, sentence) = sentences.next().expect("cycle never ends");
        if index > 0 {
            essay.push_str(if index % 4 == 0 {
                "

"
            } else {
                " "
            });
        }
        essay.push_str(sentence);
        count += sentence.split_whitespace().count() as i64;
    }
    essay
}

/// The start of `text` up to the end of its `n`th word.
fn first_words(text: &str, n: usize) -> &str {
    let mut ends = text
        .split_whitespace()
        .map(|word| word.as_ptr() as usize - text.as_ptr() as usize + word.len());
    match n {
        0 => "",
        n => ends.nth(n - 1).map_or(text, |end| &text[..end]),
    }
}

/// Default wait for an answer before a run gives up.
pub const DEFAULT_ASK_TIMEOUT: Duration = Duration::from_secs(30 * 60);

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_canned_essay_is_cut_at_whole_words() {
        let essay = canned_essay(120);
        assert!(crate::pricing::count_words(&essay) >= 120);
        assert!(essay.contains(
            "

"
        ));

        let start = first_words(&essay, 5);
        assert_eq!(start, "This draft was written by");
        assert_eq!(first_words(&essay, 0), "");
        assert_eq!(first_words("one two", 9), "one two");
        let cut = first_words(&essay, 100);
        assert_eq!(crate::pricing::count_words(cut), 100);
        assert!(!cut.ends_with(char::is_whitespace));
    }
}

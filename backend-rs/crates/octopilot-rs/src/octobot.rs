//! OctoBot — the essay-critique chat. OpenRouter-backed (model + key from the
//! shared DB). Returns `{ "message": "..." }`, matching the Flutter
//! `AssistService.chat` contract.

use axum::extract::State;
use axum::Json;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::openrouter::{call_json, parse_json_loose, ChatMessage};
use crate::{db, AppState};

fn tone_flavor(tone: &str) -> &'static str {
    match tone {
        "roast" => "ROAST the essay mercilessly but usefully. Savage, funny, \
            sarcastic — use 💀 😂 sparingly. The user asked for it, so go in, but \
            every jab must point at a real, fixable problem.",
        "mentor" => "Be a warm, encouraging mentor. Lead with what works, then \
            give concrete, kind guidance on what to improve.",
        _ => "Be honest and direct — a sharp, fair reader. No flattery, no \
            cruelty. Say what is strong and what is weak, specifically.",
    }
}

#[derive(Deserialize)]
pub struct ChatBody {
    pub message: String,
    #[serde(default)]
    pub history: Vec<HistoryTurn>,
    #[serde(default)]
    pub tone: String,
    #[serde(default)]
    pub mode: String, // 'chat' | 'criticism'
    #[serde(default)]
    pub essay: String,
}

#[derive(Deserialize)]
pub struct HistoryTurn {
    pub role: String,
    pub content: String,
}

#[derive(Serialize)]
pub struct ChatReply {
    pub message: String,
}

pub async fn chat(
    State(st): State<AppState>,
    Json(body): Json<ChatBody>,
) -> Result<Json<ChatReply>, crate::error::ApiError> {
    let key = db::openrouter_key(&st.db).await?;
    let model = db::model(&st.db, "primary_model", "anthropic/claude-sonnet-4-6").await;

    let essay = body.essay.trim();
    let essay_block = if essay.is_empty() {
        "(The student hasn't written anything substantial yet.)".to_string()
    } else {
        format!("The student's essay so far:\n\"\"\"\n{}\n\"\"\"", &essay.chars().take(8000).collect::<String>())
    };
    let mode_directive = if body.mode == "criticism" {
        "The user is in CRITICISM mode: focus your reply on critiquing the essay \
         — thesis, structure, evidence, clarity — with specific, actionable notes."
    } else {
        "The user is in CHAT mode: reply conversationally. Only give a full \
         critique if they clearly ask for one."
    };

    let system = format!(
        "You are Octo, an essay-critique assistant at Octopilot AI. {flavor}\n\
         {mode}\n\
         Address the essay directly — reference what is actually written, never \
         generic advice. Keep replies tight (a few short paragraphs or bullets).\n\
         {essay_block}\n\n\
         Respond ONLY as JSON: {{\"message\": \"your reply here\"}}.",
        flavor = tone_flavor(&body.tone),
        mode = mode_directive,
        essay_block = essay_block,
    );

    let mut messages = vec![ChatMessage { role: "system", content: system }];
    for turn in body.history.iter().rev().take(8).rev() {
        let role = if turn.role == "user" { "user" } else { "assistant" };
        messages.push(ChatMessage { role, content: turn.content.clone() });
    }
    // Ensure the latest user message is present even if history omitted it.
    if body.history.last().map(|t| t.content.as_str()) != Some(body.message.as_str()) {
        messages.push(ChatMessage { role: "user", content: body.message.clone() });
    }

    let raw = call_json(&st.http, &key, &model, messages, 0.7).await?;
    let message = parse_json_loose(&raw)
        .and_then(|v| extract_message(&v))
        .unwrap_or(raw);

    Ok(Json(ChatReply { message }))
}

/// Pulls a human-readable reply out of whatever JSON the model returned.
fn extract_message(v: &Value) -> Option<String> {
    if let Some(m) = v.get("message").and_then(|x| x.as_str()) {
        return Some(m.to_string());
    }
    if let Some(m) = v.get("reply").and_then(|x| x.as_str()) {
        return Some(m.to_string());
    }
    // A structured critique → flatten to text.
    if v.get("type").and_then(|x| x.as_str()) == Some("critique") {
        let mut out = String::new();
        for (label, arr) in [("Grammar", "grammar"), ("Style", "style")] {
            if let Some(items) = v.get(arr).and_then(|x| x.as_array()) {
                for it in items {
                    let t = it.get("title").and_then(|x| x.as_str()).unwrap_or("");
                    let note = it.get("note").or_else(|| it.get("suggestion"))
                        .and_then(|x| x.as_str()).unwrap_or("");
                    if !t.is_empty() || !note.is_empty() {
                        out.push_str(&format!("• [{label}] {t}{}{note}\n",
                            if t.is_empty() { "" } else { ": " }));
                    }
                }
            }
        }
        if let Some(s) = v.get("summary").and_then(|x| x.as_str()) {
            out.push_str(&format!("\n{s}"));
        }
        if !out.trim().is_empty() {
            return Some(out.trim().to_string());
        }
    }
    None
}

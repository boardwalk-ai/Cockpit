//! OpenRouter, streaming, with metering: every call caps `max_tokens`,
//! names the `user` (tasklist A6) and asks for `usage`, whose exact cost is
//! recorded in `llm_usage` (P1). Keys and models come from the octopilot DB
//! as in the Python service (`api_keys`, `system_settings.primary_model`).

use std::time::Duration;

use futures::{Stream, StreamExt};
use serde_json::{json, Value};
use sqlx::PgPool;
use uuid::Uuid;

const BASE: &str = "https://openrouter.ai/api/v1";

/// What a streamed completion yields: text, then (once) what it cost.
#[derive(Debug, Clone, PartialEq)]
pub enum Piece {
    Text(String),
    Usage(Usage),
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct Usage {
    pub generation_id: Option<String>,
    pub prompt_tokens: i64,
    pub completion_tokens: i64,
    pub cached_tokens: i64,
    /// USD, as OpenRouter bills it.
    pub cost: f64,
}

pub struct Call<'a> {
    pub http: &'a reqwest::Client,
    pub key: &'a str,
    pub model: &'a str,
    pub messages: Vec<Value>,
    pub max_tokens: u32,
    pub temperature: f32,
    pub user: Uuid,
}

/// The key and the model for `setting` (falls back to `fallback_model`).
pub async fn credentials(shared: Option<&PgPool>, setting: &str, fallback_model: &str) -> (Option<String>, String) {
    let Some(pool) = shared else { return (None, fallback_model.to_string()) };
    let key = octo_common::llm::openrouter_key(pool).await;
    let model = octo_common::llm::model(pool, setting, fallback_model).await;
    (key, model)
}

/// Reads one OpenRouter SSE `data:` payload.
pub fn parse_line(data: &str) -> Vec<Piece> {
    let Ok(v) = serde_json::from_str::<Value>(data) else { return vec![] };
    let mut out = Vec::new();
    if let Some(t) = v["choices"][0]["delta"]["content"].as_str() {
        if !t.is_empty() {
            out.push(Piece::Text(t.to_string()));
        }
    }
    if v["usage"].is_object() {
        let u = &v["usage"];
        out.push(Piece::Usage(Usage {
            generation_id: v["id"].as_str().map(str::to_string),
            prompt_tokens: u["prompt_tokens"].as_i64().unwrap_or(0),
            completion_tokens: u["completion_tokens"].as_i64().unwrap_or(0),
            cached_tokens: u["prompt_tokens_details"]["cached_tokens"].as_i64().unwrap_or(0),
            cost: u["cost"].as_f64().unwrap_or(0.0),
        }));
    }
    out
}

pub async fn stream(c: Call<'_>) -> Result<impl Stream<Item = Result<Piece, String>>, String> {
    let body = json!({
        "model": c.model,
        "messages": c.messages,
        "stream": true,
        "max_tokens": c.max_tokens,
        "temperature": c.temperature,
        "user": c.user.to_string(),
        "usage": { "include": true },
    });
    let res = c
        .http
        .post(format!("{BASE}/chat/completions"))
        .bearer_auth(c.key)
        .header("HTTP-Referer", "https://cockpit.octopilot.ai")
        .header("X-Title", "Cockpit Study Studio")
        .timeout(Duration::from_secs(300))
        .json(&body)
        .send()
        .await
        .map_err(|e| format!("openrouter: {e}"))?;
    if !res.status().is_success() {
        let status = res.status();
        let text = res.text().await.unwrap_or_default();
        return Err(format!("openrouter {status}: {}", text.chars().take(300).collect::<String>()));
    }
    let mut bytes = res.bytes_stream();
    Ok(async_stream::stream! {
        let mut buf = String::new();
        while let Some(chunk) = bytes.next().await {
            let chunk = match chunk { Ok(c) => c, Err(e) => { yield Err(e.to_string()); return; } };
            buf.push_str(&String::from_utf8_lossy(&chunk));
            while let Some(i) = buf.find('\n') {
                let line = buf[..i].trim().to_string();
                buf.drain(..=i);
                let Some(data) = line.strip_prefix("data:") else { continue };
                let data = data.trim();
                if data == "[DONE]" { return; }
                for p in parse_line(data) { yield Ok(p); }
            }
        }
    })
}

/// The `llm_usage` table (created by the service when it owns migrations).
pub async fn ensure_schema(cockpit: &PgPool) -> sqlx::Result<()> {
    sqlx::query(
        "CREATE TABLE IF NOT EXISTS llm_usage (\
           id uuid PRIMARY KEY, user_id uuid NOT NULL, studio_id uuid, feature varchar(32) NOT NULL, \
           model varchar(120) NOT NULL, generation_id varchar(120), prompt_tokens integer NOT NULL DEFAULT 0, \
           completion_tokens integer NOT NULL DEFAULT 0, cached_tokens integer NOT NULL DEFAULT 0, \
           cost_usd numeric(12,6) NOT NULL DEFAULT 0, created_at timestamptz NOT NULL DEFAULT now())",
    )
    .execute(cockpit)
    .await?;
    sqlx::query("CREATE INDEX IF NOT EXISTS ix_llm_usage_user_at ON llm_usage (user_id, created_at)")
        .execute(cockpit)
        .await?;
    Ok(())
}

pub async fn record(cockpit: &PgPool, user: Uuid, studio: Option<Uuid>, feature: &str, model: &str, u: &Usage) {
    let r = sqlx::query(
        "INSERT INTO llm_usage (id, user_id, studio_id, feature, model, generation_id, prompt_tokens, \
         completion_tokens, cached_tokens, cost_usd) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10::numeric)",
    )
    .bind(Uuid::new_v4())
    .bind(user)
    .bind(studio)
    .bind(feature)
    .bind(model)
    .bind(&u.generation_id)
    .bind(u.prompt_tokens as i32)
    .bind(u.completion_tokens as i32)
    .bind(u.cached_tokens as i32)
    .bind(format!("{:.6}", u.cost))
    .execute(cockpit)
    .await;
    if let Err(e) = r {
        tracing::warn!("llm_usage: {e}");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_text_and_the_final_usage() {
        assert_eq!(
            parse_line(r#"{"id":"gen-1","choices":[{"delta":{"content":"Hi"}}]}"#),
            vec![Piece::Text("Hi".into())]
        );
        let last = parse_line(
            r#"{"id":"gen-1","choices":[{"delta":{"content":""}}],"usage":{"prompt_tokens":1200,"completion_tokens":300,"prompt_tokens_details":{"cached_tokens":800},"cost":0.0081}}"#,
        );
        assert_eq!(
            last,
            vec![Piece::Usage(Usage {
                generation_id: Some("gen-1".into()),
                prompt_tokens: 1200,
                completion_tokens: 300,
                cached_tokens: 800,
                cost: 0.0081
            })]
        );
        assert!(parse_line("not json").is_empty());
    }
}

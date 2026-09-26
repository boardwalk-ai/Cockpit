//! Minimal OpenRouter JSON-mode client — a port of the web `callJson` helper.
//! Retries transient failures and drops `response_format` once if the model
//! rejects it.

use serde::Serialize;
use serde_json::Value;

use crate::error::ApiError;

const URL: &str = "https://openrouter.ai/api/v1/chat/completions";
const MAX_RETRIES: u32 = 2;

#[derive(Serialize, Clone)]
pub struct ChatMessage {
    pub role: &'static str,
    pub content: String,
}

fn retryable(status: u16) -> bool {
    matches!(status, 408 | 409 | 425 | 429 | 500 | 502 | 503 | 504)
}

/// Call OpenRouter expecting JSON content back. Returns the raw message string.
pub async fn call_json(
    http: &reqwest::Client,
    api_key: &str,
    model: &str,
    messages: Vec<ChatMessage>,
    temperature: f32,
) -> Result<String, ApiError> {
    let mut use_json_mode = true;
    for attempt in 0..=MAX_RETRIES {
        let mut payload = serde_json::json!({
            "model": model,
            "messages": messages,
            "temperature": temperature,
        });
        if use_json_mode {
            payload["response_format"] = serde_json::json!({ "type": "json_object" });
        }

        let resp = http
            .post(URL)
            .bearer_auth(api_key)
            .header("HTTP-Referer", "https://octopilotai.com")
            .header("X-Title", "OctoPilot AI")
            .json(&payload)
            .send()
            .await;

        match resp {
            Ok(r) if r.status().is_success() => {
                let data: Value = r.json().await?;
                let content = data["choices"][0]["message"]["content"]
                    .as_str()
                    .unwrap_or("")
                    .to_string();
                if content.is_empty() {
                    return Err(ApiError::bad_gateway("OpenRouter returned empty content"));
                }
                return Ok(content);
            }
            Ok(r) => {
                let status = r.status().as_u16();
                if use_json_mode && status == 400 {
                    use_json_mode = false; // retry once without response_format
                    continue;
                }
                if !retryable(status) || attempt == MAX_RETRIES {
                    let text = r.text().await.unwrap_or_default();
                    return Err(ApiError::bad_gateway(format!(
                        "OpenRouter {status}: {text}"
                    )));
                }
            }
            Err(_) if attempt < MAX_RETRIES => {}
            Err(e) => return Err(ApiError::bad_gateway(format!("OpenRouter: {e}"))),
        }
        tokio::time::sleep(std::time::Duration::from_millis(400 * (attempt as u64 + 1))).await;
    }
    Err(ApiError::bad_gateway("OpenRouter: exhausted retries"))
}

/// Loose JSON parse — tolerates code fences and surrounding prose.
pub fn parse_json_loose(raw: &str) -> Option<Value> {
    let mut text = raw.trim();
    if let Some(rest) = text.strip_prefix("```") {
        text = rest
            .trim_start_matches("json")
            .trim_start_matches("JSON")
            .trim_start_matches('\n')
            .trim();
        if let Some(end) = text.rfind("```") {
            text = text[..end].trim();
        }
    }
    if let Ok(v) = serde_json::from_str::<Value>(text) {
        return Some(v);
    }
    // Fallback: first [...] array or {...} object substring.
    for (open, close) in [('[', ']'), ('{', '}')] {
        if let (Some(s), Some(e)) = (text.find(open), text.rfind(close)) {
            if e > s {
                if let Ok(v) = serde_json::from_str::<Value>(&text[s..=e]) {
                    return Some(v);
                }
            }
        }
    }
    None
}

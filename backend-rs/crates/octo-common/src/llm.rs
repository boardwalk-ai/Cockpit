//! OpenRouter client shared by the Rust services: keys and model choices come
//! from the shared octopilot DB (`api_keys`, `system_settings`), never env, so
//! admins switch models without a deploy.
//!
//! Chat (plain + streaming), vision (image in the prompt) and speech-to-text
//! (`/api/v1/audio/transcriptions`).

use std::time::Duration;

use futures::{Stream, StreamExt};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sqlx::{PgPool, Row};

const BASE: &str = "https://openrouter.ai/api/v1";

/// An active OpenRouter key, least-used first.
pub async fn openrouter_key(pool: &PgPool) -> Option<String> {
    sqlx::query(
        "SELECT key FROM api_keys WHERE provider ILIKE 'openrouter' AND is_active = true \
         ORDER BY usage_count ASC NULLS FIRST LIMIT 1",
    )
    .fetch_optional(pool)
    .await
    .ok()
    .flatten()
    .map(|r| r.get::<String, _>("key"))
}

/// A `system_settings` value.
pub async fn setting(pool: &PgPool, key: &str) -> Option<String> {
    sqlx::query("SELECT value FROM system_settings WHERE key = $1")
        .bind(key)
        .fetch_optional(pool)
        .await
        .ok()
        .flatten()
        .and_then(|r| r.try_get::<Option<String>, _>("value").ok().flatten())
        .filter(|s| !s.trim().is_empty())
}

pub async fn model(pool: &PgPool, key: &str, default: &str) -> String {
    setting(pool, key)
        .await
        .unwrap_or_else(|| default.to_string())
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    pub role: String,
    /// A string, or an array of content parts (text + image_url) for vision.
    pub content: Value,
}

impl Message {
    pub fn system(text: impl Into<String>) -> Self {
        Self {
            role: "system".into(),
            content: Value::String(text.into()),
        }
    }
    pub fn user(text: impl Into<String>) -> Self {
        Self {
            role: "user".into(),
            content: Value::String(text.into()),
        }
    }
    /// A user message with an image (PNG/JPEG bytes as a data URL).
    pub fn user_with_image(text: impl Into<String>, mime: &str, b64: &str) -> Self {
        Self {
            role: "user".into(),
            content: json!([
                { "type": "text", "text": text.into() },
                { "type": "image_url", "image_url": { "url": format!("data:{mime};base64,{b64}") } }
            ]),
        }
    }
}

#[derive(Debug, Clone, Default)]
pub struct ChatOptions {
    pub temperature: Option<f32>,
    pub max_tokens: Option<u32>,
    /// Ask for a JSON object back.
    pub json: bool,
}

#[derive(Debug, Clone, Default)]
pub struct Usage {
    pub prompt_tokens: u32,
    pub completion_tokens: u32,
}

#[derive(Clone)]
pub struct OpenRouter {
    http: reqwest::Client,
    key: String,
}

impl OpenRouter {
    pub fn new(http: reqwest::Client, key: impl Into<String>) -> Self {
        Self {
            http,
            key: key.into(),
        }
    }

    fn body(model: &str, messages: &[Message], o: &ChatOptions, stream: bool) -> Value {
        let mut b = json!({ "model": model, "messages": messages, "stream": stream });
        if let Some(t) = o.temperature {
            b["temperature"] = json!(t);
        }
        if let Some(m) = o.max_tokens {
            b["max_tokens"] = json!(m);
        }
        if o.json {
            b["response_format"] = json!({ "type": "json_object" });
        }
        b
    }

    /// One completion → (text, usage).
    pub async fn chat(
        &self,
        model: &str,
        messages: &[Message],
        o: &ChatOptions,
    ) -> Result<(String, Usage), String> {
        let res = self
            .http
            .post(format!("{BASE}/chat/completions"))
            .bearer_auth(&self.key)
            .timeout(Duration::from_secs(120))
            .json(&Self::body(model, messages, o, false))
            .send()
            .await
            .map_err(|e| format!("openrouter: {e}"))?;
        let status = res.status();
        let v: Value = res
            .json()
            .await
            .map_err(|e| format!("openrouter body: {e}"))?;
        if !status.is_success() {
            return Err(format!(
                "openrouter {status}: {}",
                v["error"]["message"].as_str().unwrap_or("error")
            ));
        }
        let text = v["choices"][0]["message"]["content"]
            .as_str()
            .unwrap_or("")
            .to_string();
        let usage = Usage {
            prompt_tokens: v["usage"]["prompt_tokens"].as_u64().unwrap_or(0) as u32,
            completion_tokens: v["usage"]["completion_tokens"].as_u64().unwrap_or(0) as u32,
        };
        Ok((text, usage))
    }

    /// Streams content deltas (SSE from OpenRouter). The stream ends at `[DONE]`.
    pub async fn chat_stream(
        &self,
        model: &str,
        messages: &[Message],
        o: &ChatOptions,
    ) -> Result<impl Stream<Item = Result<String, String>>, String> {
        let res = self
            .http
            .post(format!("{BASE}/chat/completions"))
            .bearer_auth(&self.key)
            .timeout(Duration::from_secs(300))
            .json(&Self::body(model, messages, o, true))
            .send()
            .await
            .map_err(|e| format!("openrouter: {e}"))?;
        if !res.status().is_success() {
            let status = res.status();
            let body = res.text().await.unwrap_or_default();
            return Err(format!("openrouter {status}: {body}"));
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
                    if let Ok(v) = serde_json::from_str::<Value>(data) {
                        if let Some(t) = v["choices"][0]["delta"]["content"].as_str() {
                            if !t.is_empty() { yield Ok(t.to_string()); }
                        }
                    }
                }
            }
        })
    }

    /// Speech-to-text. `format`: ogg, webm, wav, mp3, flac, m4a, aac.
    pub async fn transcribe(
        &self,
        model: &str,
        audio: &[u8],
        format: &str,
        language: Option<&str>,
        words: bool,
    ) -> Result<Transcription, String> {
        use base64::Engine;
        let mut body = json!({
            "model": model,
            "input_audio": { "data": base64::engine::general_purpose::STANDARD.encode(audio), "format": format },
            "response_format": "verbose_json",
        });
        if words {
            body["timestamp_granularities"] = json!(["word", "segment"]);
        }
        if let Some(l) = language {
            body["language"] = json!(l);
        }
        let res = self
            .http
            .post(format!("{BASE}/audio/transcriptions"))
            .bearer_auth(&self.key)
            .timeout(Duration::from_secs(600))
            .json(&body)
            .send()
            .await
            .map_err(|e| format!("openrouter stt: {e}"))?;
        let status = res.status();
        let v: Value = res
            .json()
            .await
            .map_err(|e| format!("openrouter stt body: {e}"))?;
        if !status.is_success() {
            return Err(format!(
                "openrouter stt {status}: {}",
                v["error"]["message"].as_str().unwrap_or("error")
            ));
        }
        Ok(Transcription::from_json(&v))
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Word {
    pub word: String,
    pub start: f64,
    pub end: f64,
    #[serde(default)]
    pub speaker: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Segment {
    pub text: String,
    pub start: f64,
    pub end: f64,
    #[serde(default)]
    pub speaker: Option<String>,
    #[serde(default)]
    pub confidence: Option<f64>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Transcription {
    pub text: String,
    pub language: Option<String>,
    pub duration: Option<f64>,
    pub segments: Vec<Segment>,
    pub words: Vec<Word>,
}

impl Transcription {
    pub fn from_json(v: &Value) -> Self {
        let segs = v["segments"].as_array().cloned().unwrap_or_default();
        let words = v["words"].as_array().cloned().unwrap_or_default();
        let speaker = |x: &Value| {
            x["speaker"]
                .as_str()
                .map(str::to_string)
                .or_else(|| x["speaker"].as_i64().map(|n| n.to_string()))
        };
        Transcription {
            text: v["text"].as_str().unwrap_or("").trim().to_string(),
            language: v["language"].as_str().map(str::to_string),
            duration: v["duration"].as_f64(),
            segments: segs
                .iter()
                .map(|s| Segment {
                    text: s["text"].as_str().unwrap_or("").trim().to_string(),
                    start: s["start"].as_f64().unwrap_or(0.0),
                    end: s["end"].as_f64().unwrap_or(0.0),
                    speaker: speaker(s),
                    // Whisper-style avg_logprob → rough 0..1 confidence.
                    confidence: s["confidence"]
                        .as_f64()
                        .or_else(|| s["avg_logprob"].as_f64().map(|l| l.exp().clamp(0.0, 1.0))),
                })
                .filter(|s| !s.text.is_empty())
                .collect(),
            words: words
                .iter()
                .map(|w| Word {
                    word: w["word"].as_str().unwrap_or("").to_string(),
                    start: w["start"].as_f64().unwrap_or(0.0),
                    end: w["end"].as_f64().unwrap_or(0.0),
                    speaker: speaker(w),
                })
                .collect(),
        }
    }
}

/// Pulls the first JSON object out of a model reply (tolerates code fences
/// and prose around it).
pub fn parse_json_loose(text: &str) -> Option<Value> {
    if let Ok(v) = serde_json::from_str::<Value>(text.trim()) {
        return Some(v);
    }
    let start = text.find(['{', '['])?;
    let end = text.rfind(['}', ']'])?;
    serde_json::from_str(&text[start..=end]).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_verbose_json() {
        let v = json!({
            "text": " Glycolysis happens in the cytoplasm. ",
            "language": "en",
            "segments": [{ "text": "Glycolysis happens", "start": 0.0, "end": 1.2, "avg_logprob": -0.1, "speaker": 0 }],
            "words": [{ "word": "Glycolysis", "start": 0.0, "end": 0.6 }]
        });
        let t = Transcription::from_json(&v);
        assert_eq!(t.text, "Glycolysis happens in the cytoplasm.");
        assert_eq!(t.segments[0].speaker.as_deref(), Some("0"));
        assert!(t.segments[0].confidence.unwrap() > 0.8);
        assert_eq!(t.words.len(), 1);
    }

    #[test]
    fn loose_json() {
        assert_eq!(parse_json_loose("```json\n{\"a\":1}\n```").unwrap()["a"], 1);
        assert!(parse_json_loose("no json here").is_none());
    }
}

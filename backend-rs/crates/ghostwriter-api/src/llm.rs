//! The model, behind a trait so tests can script it.
//!
//! The orchestrator needs tool calls, which the shared `octo_common::llm`
//! client does not speak, so this is a thin OpenRouter client of its own.

use std::time::Duration;

use axum::async_trait;
use futures::stream::BoxStream;
use futures::StreamExt;
use serde_json::{json, Value};

const BASE: &str = "https://openrouter.ai/api/v1";

#[derive(Clone, Debug, Default)]
pub struct ChatRequest {
    pub model: String,
    /// OpenAI-style messages, including `tool` results and assistant
    /// `tool_calls`.
    pub messages: Vec<Value>,
    pub temperature: Option<f32>,
    /// Ask for a JSON object back.
    pub json: bool,
    /// Function tool specs; empty for a plain completion.
    pub tools: Vec<Value>,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct ToolCall {
    pub id: String,
    pub name: String,
    /// The arguments as the model wrote them: a JSON object, as text.
    pub arguments: String,
}

#[derive(Clone, Debug, Default)]
pub struct ChatReply {
    pub content: String,
    pub tool_calls: Vec<ToolCall>,
}

pub type TextStream = BoxStream<'static, Result<String, String>>;

#[async_trait]
pub trait Llm: Send + Sync {
    /// One completion.
    async fn chat(&self, request: ChatRequest) -> Result<ChatReply, String>;
    /// One completion, as content deltas.
    async fn stream(&self, request: ChatRequest) -> Result<TextStream, String>;
}

pub fn system(text: impl Into<String>) -> Value {
    json!({ "role": "system", "content": text.into() })
}

pub fn user(text: impl Into<String>) -> Value {
    json!({ "role": "user", "content": text.into() })
}

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

    fn body(request: &ChatRequest, stream: bool) -> Value {
        let mut body = json!({
            "model": request.model,
            "messages": request.messages,
            "stream": stream,
        });
        if let Some(temperature) = request.temperature {
            body["temperature"] = json!(temperature);
        }
        if request.json {
            body["response_format"] = json!({ "type": "json_object" });
        }
        if !request.tools.is_empty() {
            body["tools"] = json!(request.tools);
            body["tool_choice"] = json!("auto");
        }
        body
    }

    fn post(
        &self,
        request: &ChatRequest,
        stream: bool,
        timeout: Duration,
    ) -> reqwest::RequestBuilder {
        self.http
            .post(format!("{BASE}/chat/completions"))
            .bearer_auth(&self.key)
            .header("HTTP-Referer", "https://octopilotai.com")
            .header("X-Title", "OctoPilot AI")
            .timeout(timeout)
            .json(&Self::body(request, stream))
    }
}

#[async_trait]
impl Llm for OpenRouter {
    async fn chat(&self, request: ChatRequest) -> Result<ChatReply, String> {
        let response = self
            .post(&request, false, Duration::from_secs(180))
            .send()
            .await
            .map_err(|e| {
                tracing::warn!(error = %e, "model request failed");
                "the model did not answer".to_string()
            })?;
        let status = response.status();
        let body: Value = response
            .json()
            .await
            .map_err(|e| format!("model reply unreadable: {e}"))?;
        if !status.is_success() || body.get("error").is_some() {
            // The provider's message can name the model: logged, never shown.
            tracing::warn!(%status, error = %body["error"], "model call refused");
            return Err(format!("the model could not answer ({})", status.as_u16()));
        }

        let message = &body["choices"][0]["message"];
        let tool_calls = message["tool_calls"]
            .as_array()
            .map(|calls| {
                calls
                    .iter()
                    .map(|call| ToolCall {
                        id: call["id"].as_str().unwrap_or_default().to_string(),
                        name: call["function"]["name"]
                            .as_str()
                            .unwrap_or_default()
                            .to_string(),
                        arguments: call["function"]["arguments"]
                            .as_str()
                            .unwrap_or("{}")
                            .to_string(),
                    })
                    .collect()
            })
            .unwrap_or_default();
        Ok(ChatReply {
            content: message["content"].as_str().unwrap_or_default().to_string(),
            tool_calls,
        })
    }

    async fn stream(&self, request: ChatRequest) -> Result<TextStream, String> {
        let response = self
            .post(&request, true, Duration::from_secs(300))
            .send()
            .await
            .map_err(|e| {
                tracing::warn!(error = %e, "model request failed");
                "the model did not answer".to_string()
            })?;
        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            tracing::warn!(%status, %body, "model stream refused");
            return Err(format!("the model could not answer ({})", status.as_u16()));
        }

        let mut bytes = response.bytes_stream();
        Ok(async_stream::stream! {
            let mut buffer = String::new();
            while let Some(chunk) = bytes.next().await {
                let chunk = match chunk {
                    Ok(chunk) => chunk,
                    Err(e) => { yield Err(e.to_string()); return; }
                };
                buffer.push_str(&String::from_utf8_lossy(&chunk));
                while let Some(end) = buffer.find('\n') {
                    let line = buffer[..end].trim().to_string();
                    buffer.drain(..=end);
                    let Some(data) = line.strip_prefix("data:") else { continue };
                    let data = data.trim();
                    if data == "[DONE]" { return; }
                    if let Ok(value) = serde_json::from_str::<Value>(data) {
                        if let Some(text) = value["choices"][0]["delta"]["content"].as_str() {
                            if !text.is_empty() { yield Ok(text.to_string()); }
                        }
                    }
                }
            }
        }
        .boxed())
    }
}

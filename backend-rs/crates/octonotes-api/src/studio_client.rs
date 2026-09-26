//! Talking to Study Studio's backend. Study Studio owns its tables, so
//! OctoNotes never writes them directly: it creates studios, uploads material
//! and starts builds through Study Studio's own API, and only READS the Study
//! Studio DB (progress, topics, mastery).
//!
//! Today that API is the FastAPI service (SSE responses for create/build,
//! multipart upload). If Study Studio moves to Rust, swap the implementation
//! behind `StudioClient`; nothing else in OctoNotes changes.

use serde_json::Value;
use uuid::Uuid;

/// Who the call is for: the user's own Firebase token (request time), and/or
/// a service key + the user's id (background work, once Study Studio accepts it).
#[derive(Clone, Default)]
pub struct OnBehalf {
    pub bearer: Option<String>,
    pub user_id: Option<Uuid>,
}

#[derive(Clone)]
pub enum StudioClient {
    Http { http: reqwest::Client, base: String, service_key: Option<String> },
    /// Not configured.
    None,
}

impl StudioClient {
    pub fn new(http: reqwest::Client, base: Option<String>, service_key: Option<String>) -> Self {
        match base {
            Some(b) => StudioClient::Http { http, base: b.trim_end_matches('/').to_string(), service_key },
            None => StudioClient::None,
        }
    }

    fn req(&self, method: reqwest::Method, path: &str, who: &OnBehalf) -> Result<reqwest::RequestBuilder, String> {
        let StudioClient::Http { http, base, service_key } = self else { return Err("Study Studio API is not configured".into()) };
        let mut r = http.request(method, format!("{base}{path}"));
        if let Some(t) = &who.bearer {
            r = r.bearer_auth(t);
        }
        if let (Some(k), Some(u)) = (service_key, who.user_id) {
            r = r.header("X-Service-Key", k).header("X-On-Behalf-Of", u.to_string());
        }
        // Local dev (Study Studio with ALLOW_DEV_USER_HEADER): identify by id.
        if who.bearer.is_none() {
            if let Some(u) = who.user_id {
                r = r.header("X-User-Id", u.to_string());
            }
        }
        Ok(r)
    }

    /// `POST /studios` (SSE) → new studio id.
    pub async fn create_studio(&self, who: &OnBehalf, title: &str, subject: Option<&str>) -> Result<Uuid, String> {
        let res = self.req(reqwest::Method::POST, "/studios", who)?
            .json(&serde_json::json!({ "title": title, "subject": subject }))
            .send().await.map_err(|e| format!("study studio: {e}"))?;
        let data = sse_data(res).await?;
        data["id"].as_str().and_then(|s| Uuid::parse_str(s).ok()).ok_or_else(|| format!("study studio: no studio id in {data}"))
    }

    /// `POST /studios/{id}/documents` (multipart) → ingest job accepted.
    pub async fn upload(&self, who: &OnBehalf, studio: Uuid, filename: &str, bytes: Vec<u8>) -> Result<Value, String> {
        let part = reqwest::multipart::Part::bytes(bytes).file_name(filename.to_string()).mime_str("text/markdown").map_err(|e| e.to_string())?;
        let res = self.req(reqwest::Method::POST, &format!("/studios/{studio}/documents"), who)?
            .multipart(reqwest::multipart::Form::new().part("file", part))
            .send().await.map_err(|e| format!("study studio upload: {e}"))?;
        let status = res.status();
        let v: Value = res.json().await.unwrap_or(Value::Null);
        if !status.is_success() {
            return Err(format!("study studio upload {status}: {v}"));
        }
        Ok(v)
    }

    /// `POST /studios/{id}/build` (SSE) → build id.
    pub async fn start_build(&self, who: &OnBehalf, studio: Uuid) -> Result<Uuid, String> {
        let res = self.req(reqwest::Method::POST, &format!("/studios/{studio}/build"), who)?.send().await.map_err(|e| format!("study studio build: {e}"))?;
        let data = sse_data(res).await?;
        data["buildId"].as_str().and_then(|s| Uuid::parse_str(s).ok()).ok_or_else(|| format!("study studio: no build id in {data}"))
    }
}

/// Reads an SSE response to the end and returns the first `data` event's
/// JSON; an `error` event becomes Err.
async fn sse_data(res: reqwest::Response) -> Result<Value, String> {
    let status = res.status();
    let text = res.text().await.map_err(|e| e.to_string())?;
    if !status.is_success() {
        return Err(format!("study studio {status}: {text}"));
    }
    for frame in text.replace("\r\n", "\n").split("\n\n") {
        let (mut ev, mut data) = (String::new(), String::new());
        for line in frame.lines() {
            if let Some(v) = line.strip_prefix("event:") { ev = v.trim().to_string(); }
            if let Some(v) = line.strip_prefix("data:") { data.push_str(v.trim_start()); }
        }
        match ev.as_str() {
            "data" => return serde_json::from_str(&data).map_err(|e| format!("study studio: bad data: {e}")),
            "error" => return Err(format!("study studio: {data}")),
            _ => {}
        }
    }
    Err("study studio: empty response".into())
}

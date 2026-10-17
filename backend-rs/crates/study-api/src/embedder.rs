//! The bge-m3 embedder over HTTP: Hugging Face text-embeddings-inference
//! (TEI, Rust) in production. One request shape serves both TEI (`inputs`,
//! returns a bare list) and the old Python service (`texts`, returns
//! `{vectors}`), so `EMBED_SERVICE_URL` can point at either.

use std::time::Duration;

use serde_json::{json, Value};

use crate::AppState;

pub fn body(texts: &[String]) -> Value {
    json!({ "inputs": texts, "texts": texts, "truncate": true, "normalize": true })
}

/// The vectors in a reply (TEI's list, or Python's `{vectors}`).
pub fn parse(v: Value) -> Option<Vec<Vec<f32>>> {
    let list = match v {
        Value::Array(_) => v,
        Value::Object(mut m) => m.remove("vectors")?,
        _ => return None,
    };
    serde_json::from_value(list).ok()
}

/// One call, no retries; None on any failure.
pub async fn embed_once(state: &AppState, texts: &[String], wait: Duration) -> Result<Vec<Vec<f32>>, String> {
    let url = format!("{}/embed", state.config.embed_service_url.trim_end_matches('/'));
    let r = state.http.post(url).timeout(wait).json(&body(texts)).send().await.map_err(|e| e.to_string())?;
    if !r.status().is_success() {
        return Err(format!("embed HTTP {}", r.status()));
    }
    let v: Value = r.json().await.map_err(|e| e.to_string())?;
    let vecs = parse(v).ok_or("embed: no vectors in the reply")?;
    if vecs.len() != texts.len() {
        return Err(format!("embed returned {} vectors for {} texts", vecs.len(), texts.len()));
    }
    Ok(vecs)
}

/// Up when `/health` answers (TEI: only once the model is loaded).
pub async fn healthy(state: &AppState) -> bool {
    let url = format!("{}/health", state.config.embed_service_url.trim_end_matches('/'));
    matches!(state.http.get(url).timeout(Duration::from_secs(3)).send().await, Ok(r) if r.status().is_success())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_tei_and_python_replies() {
        assert_eq!(parse(json!([[0.5, 1.0]])), Some(vec![vec![0.5, 1.0]]));
        assert_eq!(parse(json!({"vectors": [[0.25]]})), Some(vec![vec![0.25]]));
        assert_eq!(parse(json!({"error": "x"})), None);
    }
}

//! Text out of an uploaded file, **page by page** where the file has pages,
//! so chunks and citations can say "p.12". Digital PDFs are read locally;
//! scans, office files and images go to Hirara (OCR in English and Burmese).

use base64::Engine;
use serde_json::{json, Value};

/// One page of text (`number` is 1-based; None when the source has no pages
/// we can tell apart, e.g. OCR of a whole file).
#[derive(Debug, Clone, PartialEq)]
pub struct Page {
    pub number: Option<i32>,
    pub text: String,
}

const MIN_CHARS: usize = 20;
const MIN_PER_PAGE: usize = 40;
const OCR_LANGUAGES: [&str; 2] = ["en", "my"];

/// A real text layer: enough characters overall and per page (a scan often
/// still carries a few header glyphs).
pub fn usable(text_len: usize, pages: usize) -> bool {
    text_len >= MIN_CHARS && text_len / pages.max(1) >= MIN_PER_PAGE
}

pub struct Hirara<'a> {
    pub http: &'a reqwest::Client,
    pub url: &'a str,
    pub token: &'a str,
}

impl Hirara<'_> {
    async fn call(&self, tool: &str, arguments: Value) -> Result<Value, String> {
        let mut req = self
            .http
            .post(format!("{}/call", self.url.trim_end_matches('/')))
            .timeout(std::time::Duration::from_secs(300))
            .json(&json!({ "name": tool, "arguments": arguments }));
        if !self.token.is_empty() {
            req = req.bearer_auth(self.token);
        }
        let r = req.send().await.map_err(|e| format!("hirara {tool}: {e}"))?;
        if !r.status().is_success() {
            return Err(format!("hirara {tool}: HTTP {}", r.status()));
        }
        r.json().await.map_err(|e| format!("hirara {tool}: {e}"))
    }
}

/// OCR, tried twice: Hirara answers 200 with empty text and an `error`
/// when its engine times out (seen while the box was busy embedding).
async fn ocr(hirara: &Hirara<'_>, b64: &str) -> Result<String, String> {
    let mut why = String::new();
    for attempt in 0..2 {
        if attempt > 0 {
            tokio::time::sleep(std::time::Duration::from_secs(5)).await;
        }
        let r = hirara.call("ocr_read", json!({ "file_base64": b64, "languages": OCR_LANGUAGES })).await?;
        let t = text_of(&r);
        if !t.is_empty() {
            return Ok(t);
        }
        why = r.get("error").and_then(Value::as_str).unwrap_or("").to_string();
        tracing::warn!(attempt, error = %why, "ocr returned no text");
    }
    if why.is_empty() {
        Ok(String::new())
    } else {
        Err(format!("Couldn't read the text in this file ({why})."))
    }
}

fn text_of(v: &Value) -> String {
    for k in ["text", "markdown"] {
        if let Some(t) = v.get(k).and_then(Value::as_str) {
            if !t.trim().is_empty() {
                return t.trim().to_string();
            }
        }
    }
    String::new()
}

/// The embedded text layer, one entry per page. Never panics (some PDFs
/// make the parser panic).
pub fn pdf_pages(data: &[u8]) -> Vec<String> {
    let data = data.to_vec();
    std::panic::catch_unwind(move || pdf_extract::extract_text_from_mem_by_pages(&data).ok())
        .ok()
        .flatten()
        .unwrap_or_default()
}

fn ext(name: &str) -> String {
    name.rsplit_once('.').map(|(_, e)| e.to_ascii_lowercase()).unwrap_or_default()
}

pub async fn extract(
    hirara: &Hirara<'_>,
    filename: &str,
    mime: &str,
    data: &[u8],
) -> Result<Vec<Page>, String> {
    let e = ext(filename);
    let whole = |text: String| Ok(vec![Page { number: None, text }]);

    if mime.starts_with("text/") || matches!(e.as_str(), "txt" | "md" | "markdown") {
        return whole(String::from_utf8_lossy(data).into_owned());
    }

    let b64 = base64::engine::general_purpose::STANDARD.encode(data);

    if mime == "application/pdf" || e == "pdf" {
        let bytes = data.to_vec();
        let pages = tokio::task::spawn_blocking(move || pdf_pages(&bytes)).await.unwrap_or_default();
        let total: usize = pages.iter().map(|p| p.trim().chars().count()).sum();
        if usable(total, pages.len()) {
            return Ok(pages
                .into_iter()
                .enumerate()
                .map(|(i, text)| Page { number: Some(i as i32 + 1), text })
                .filter(|p| !p.text.trim().is_empty())
                .collect());
        }
        // A scan: Hirara's reader, then OCR.
        let read = hirara.call("pdf_read", json!({ "pdf_base64": b64 })).await.ok();
        let text = read.as_ref().map(text_of).unwrap_or_default();
        if usable(text.chars().count(), pages.len()) {
            return whole(text);
        }
        let t = ocr(hirara, &b64).await?;
        return whole(if t.is_empty() { text } else { t });
    }

    let office = matches!(e.as_str(), "doc" | "docx" | "ppt" | "pptx" | "xls" | "xlsx" | "odt" | "odp" | "rtf")
        || mime.contains("officedocument")
        || mime.contains("msword")
        || mime.contains("ms-powerpoint")
        || mime.contains("ms-excel");
    if office {
        let r = hirara.call("office_read", json!({ "file_base64": b64, "filename": filename })).await?;
        return whole(text_of(&r));
    }

    if mime.starts_with("image/") || matches!(e.as_str(), "png" | "jpg" | "jpeg" | "gif" | "webp" | "heic" | "bmp" | "tif" | "tiff") {
        return whole(ocr(hirara, &b64).await?);
    }

    if mime.starts_with("audio/") || mime.starts_with("video/") {
        return Err("Audio and video aren't supported yet.".into());
    }
    Err(format!("No text extractor for {filename} ({mime})."))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn usable_layer() {
        assert!(!usable(10, 1));
        assert!(usable(400, 2));
        assert!(!usable(60, 3)); // 20 chars a page: a scan
    }

    #[test]
    fn garbage_pdf_is_empty_not_a_panic() {
        assert!(pdf_pages(b"not a pdf at all").is_empty());
    }
}

//! Stateless tool proxies — Dictionary, Thesaurus, Paraphraser. Ported from the
//! OctopilotWeb routes; the JSON shapes match the Flutter `DictResult` /
//! `ThesResult` models so the client deserializes them directly.

use axum::extract::{Query, State};
use axum::Json;
use serde::{Deserialize, Serialize};

use crate::error::ApiError;
use crate::AppState;

#[derive(Deserialize)]
pub struct WordQuery {
    pub word: String,
}

// ── response DTOs (camelCase, mirrors the Dart models) ───────────────────────
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DictDefinition {
    pub definition: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub example: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DictMeaning {
    pub part_of_speech: String,
    pub definitions: Vec<DictDefinition>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DictResult {
    pub word: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub phonetic: Option<String>,
    pub meanings: Vec<DictMeaning>,
    pub synonyms: Vec<String>,
    pub antonyms: Vec<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ThesWord {
    pub word: String,
    pub score: i64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ThesResult {
    pub word: String,
    pub synonyms: Vec<ThesWord>,
    pub antonyms: Vec<ThesWord>,
}

// ── dictionaryapi.dev shapes ─────────────────────────────────────────────────
#[derive(Deserialize)]
struct ApiDefinition {
    definition: String,
    example: Option<String>,
    #[serde(default)]
    synonyms: Vec<String>,
    #[serde(default)]
    antonyms: Vec<String>,
}
#[derive(Deserialize)]
struct ApiMeaning {
    #[serde(rename = "partOfSpeech")]
    part_of_speech: String,
    definitions: Vec<ApiDefinition>,
    #[serde(default)]
    synonyms: Vec<String>,
    #[serde(default)]
    antonyms: Vec<String>,
}
#[derive(Deserialize)]
struct ApiPhonetic {
    text: Option<String>,
}
#[derive(Deserialize)]
struct ApiEntry {
    word: String,
    phonetic: Option<String>,
    #[serde(default)]
    phonetics: Vec<ApiPhonetic>,
    meanings: Vec<ApiMeaning>,
}

pub async fn dictionary(
    State(st): State<AppState>,
    Query(q): Query<WordQuery>,
) -> Result<Json<DictResult>, ApiError> {
    let word = q.word.trim();
    if word.is_empty() {
        return Err(ApiError::bad_request("missing word"));
    }
    let url = format!(
        "https://api.dictionaryapi.dev/api/v2/entries/en/{}",
        urlencoding::encode(word)
    );
    let resp = st.http.get(url).send().await?;
    if resp.status() == reqwest::StatusCode::NOT_FOUND {
        return Err(ApiError::not_found(format!("no definition for '{word}'")));
    }
    let entries: Vec<ApiEntry> = resp
        .error_for_status()?
        .json()
        .await
        .map_err(|e| ApiError::bad_gateway(format!("bad dictionary response: {e}")))?;

    let first = entries
        .first()
        .ok_or_else(|| ApiError::not_found(format!("no definition for '{word}'")))?;

    let phonetic = first
        .phonetic
        .clone()
        .or_else(|| first.phonetics.iter().find_map(|p| p.text.clone()));

    let mut synonyms = Vec::new();
    let mut antonyms = Vec::new();
    let mut meanings = Vec::new();
    for e in &entries {
        for m in &e.meanings {
            synonyms.extend(m.synonyms.iter().cloned());
            antonyms.extend(m.antonyms.iter().cloned());
            let mut defs = Vec::new();
            for d in &m.definitions {
                synonyms.extend(d.synonyms.iter().cloned());
                antonyms.extend(d.antonyms.iter().cloned());
                defs.push(DictDefinition {
                    definition: d.definition.clone(),
                    example: d.example.clone(),
                });
            }
            meanings.push(DictMeaning {
                part_of_speech: m.part_of_speech.clone(),
                definitions: defs,
            });
        }
    }
    dedup(&mut synonyms);
    dedup(&mut antonyms);

    Ok(Json(DictResult {
        word: first.word.clone(),
        phonetic,
        meanings,
        synonyms,
        antonyms,
    }))
}

fn dedup(v: &mut Vec<String>) {
    let mut seen = std::collections::HashSet::new();
    v.retain(|s| seen.insert(s.to_lowercase()));
    v.truncate(12);
}

// ── datamuse ─────────────────────────────────────────────────────────────────
#[derive(Deserialize)]
struct DatamuseWord {
    word: String,
    #[serde(default)]
    score: i64,
}

pub async fn thesaurus(
    State(st): State<AppState>,
    Query(q): Query<WordQuery>,
) -> Result<Json<ThesResult>, ApiError> {
    let word = q.word.trim();
    if word.is_empty() {
        return Err(ApiError::bad_request("missing word"));
    }
    let enc = urlencoding::encode(word);
    let syn_url = format!("https://api.datamuse.com/words?rel_syn={enc}&max=14");
    let ant_url = format!("https://api.datamuse.com/words?rel_ant={enc}&max=10");

    let (syn, ant) = tokio::join!(fetch_datamuse(&st, &syn_url), fetch_datamuse(&st, &ant_url));

    Ok(Json(ThesResult {
        word: word.to_string(),
        synonyms: syn?,
        antonyms: ant?,
    }))
}

async fn fetch_datamuse(st: &AppState, url: &str) -> Result<Vec<ThesWord>, ApiError> {
    let rows: Vec<DatamuseWord> = st.http.get(url).send().await?.json().await?;
    Ok(rows
        .into_iter()
        .map(|r| ThesWord {
            word: r.word,
            score: r.score,
        })
        .collect())
}

// ── paraphraser (undetectable.ai) ────────────────────────────────────────────
#[derive(Deserialize)]
pub struct ParaphraseBody {
    pub text: String,
}
#[derive(Serialize)]
pub struct ParaphraseResult {
    pub text: String,
}

pub async fn paraphrase(
    State(st): State<AppState>,
    Json(body): Json<ParaphraseBody>,
) -> Result<Json<ParaphraseResult>, ApiError> {
    let text = body.text.trim().to_string();
    if text.is_empty() {
        return Ok(Json(ParaphraseResult { text }));
    }
    // Key comes from the shared DB (system_settings.undetectable_api_key), with
    // the env var as an override; passthrough when neither is set.
    let key = match st.config.humanizer_api_key.clone() {
        Some(k) => Some(k),
        None => crate::db::setting(&st.db, "undetectable_api_key")
            .await
            .filter(|s| !s.trim().is_empty()),
    };
    let Some(key) = key else {
        return Ok(Json(ParaphraseResult { text }));
    };
    let out = humanize_undetectable(&st, &key, &text).await?;
    Ok(Json(ParaphraseResult { text: out }))
}

#[derive(Serialize)]
struct SubmitReq<'a> {
    content: &'a str,
    readability: &'a str,
    purpose: &'a str,
    strength: &'a str,
    model: &'a str,
}
#[derive(Deserialize)]
struct SubmitResp {
    id: Option<String>,
}
#[derive(Deserialize)]
struct DocResp {
    output: Option<String>,
    status: Option<String>,
}

async fn humanize_undetectable(st: &AppState, key: &str, text: &str) -> Result<String, ApiError> {
    let submit: SubmitResp = st
        .http
        .post("https://humanize.undetectable.ai/submit")
        .header("apikey", key)
        .json(&SubmitReq {
            content: text,
            readability: "High School",
            purpose: "Essay",
            strength: "More Human",
            model: "v11",
        })
        .send()
        .await?
        .json()
        .await?;
    let Some(id) = submit.id else {
        return Ok(text.to_string());
    };
    for _ in 0..10 {
        tokio::time::sleep(std::time::Duration::from_secs(2)).await;
        let doc: DocResp = st
            .http
            .post("https://humanize.undetectable.ai/document")
            .header("apikey", key)
            .json(&serde_json::json!({ "id": id }))
            .send()
            .await?
            .json()
            .await?;
        if let Some(out) = doc.output {
            return Ok(out);
        }
        if doc.status.as_deref() == Some("failed") {
            break;
        }
    }
    Ok(text.to_string())
}

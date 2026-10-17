//! The wire contract with the Flutter app (`packages/study_studio`): the
//! same camelCase fields as `Backend/app/dto.py`. Topics and scenarios are
//! stored as JSON payloads; reading them through these types fills defaults
//! and drops build-only keys (`relatesTo`, `buildsOn`, `_otherTitles`), as the
//! Python models do.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

fn two() -> i32 {
    2
}
fn three() -> i32 {
    3
}
fn ten() -> i32 {
    10
}
fn six() -> i32 {
    6
}
fn start_ease() -> f64 {
    2.5
}
fn definition() -> String {
    "definition".into()
}
fn fresh() -> String {
    "fresh".into()
}
fn yes() -> bool {
    true
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Flashcard {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub topic_id: String,
    #[serde(default)]
    pub front: String,
    #[serde(default)]
    pub back: String,
    #[serde(default = "definition", rename = "type")]
    pub kind: String,
    #[serde(default = "two")]
    pub difficulty: i32,
    #[serde(default = "fresh")]
    pub status: String,
    #[serde(default)]
    pub due_date: Option<DateTime<Utc>>,
    #[serde(default)]
    pub reps: i32,
    #[serde(default)]
    pub interval_days: f64,
    #[serde(default = "start_ease")]
    pub ease: f64,
    #[serde(default)]
    pub lapses: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct QuizQuestion {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub topic_id: String,
    #[serde(rename = "type", default)]
    pub kind: String,
    #[serde(default)]
    pub question: String,
    #[serde(default)]
    pub choices: Vec<String>,
    #[serde(default)]
    pub answer: String,
    #[serde(default)]
    pub explanation: String,
    #[serde(default = "two")]
    pub difficulty: i32,
    #[serde(default)]
    pub related_concept: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct SourceReference {
    #[serde(default)]
    pub file_name: String,
    #[serde(default)]
    pub snippet: String,
    #[serde(default)]
    pub page: Option<i32>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct SourceFile {
    pub id: String,
    pub name: String,
    #[serde(rename = "type")]
    pub kind: String,
    #[serde(default = "yes")]
    pub processed: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Concept {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub meaning: String,
    #[serde(default)]
    pub example: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ConceptLink {
    #[serde(rename = "from", default)]
    pub from: String,
    #[serde(default)]
    pub label: String,
    #[serde(default)]
    pub to: Option<String>,
    #[serde(default)]
    pub to_topic: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Topic {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub studio_id: String,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub subject: String,
    #[serde(default)]
    pub summary: Vec<String>,
    #[serde(default)]
    pub concepts: Vec<Concept>,
    #[serde(default)]
    pub concept_links: Vec<ConceptLink>,
    #[serde(default)]
    pub definition: String,
    #[serde(default)]
    pub simple_explanation: String,
    #[serde(default)]
    pub detailed_explanation: String,
    #[serde(default)]
    pub why_it_matters: String,
    #[serde(default)]
    pub examples: Vec<String>,
    #[serde(default)]
    pub common_mistakes: Vec<String>,
    #[serde(default)]
    pub related_topic_ids: Vec<String>,
    #[serde(default)]
    pub prerequisites: Vec<String>,
    #[serde(default)]
    pub memory_hooks: Vec<String>,
    #[serde(default)]
    pub sources: Vec<SourceReference>,
    #[serde(default)]
    pub flashcards: Vec<Flashcard>,
    #[serde(default)]
    pub quiz_questions: Vec<QuizQuestion>,
    #[serde(default = "three")]
    pub difficulty: i32,
    #[serde(default = "three")]
    pub importance: i32,
    #[serde(default = "ten")]
    pub estimated_study_time_minutes: i32,
    #[serde(default)]
    pub mastery: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ScenarioClue {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub label: String,
    #[serde(default)]
    pub detail: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ScenarioOption {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub label: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Scenario {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub studio_id: String,
    #[serde(default)]
    pub title: String,
    #[serde(default = "three")]
    pub difficulty: i32,
    #[serde(default = "six")]
    pub estimated_minutes: i32,
    #[serde(default)]
    pub skills: Vec<String>,
    #[serde(default)]
    pub ai_note: String,
    #[serde(default)]
    pub problem: String,
    #[serde(default)]
    pub question: String,
    #[serde(default)]
    pub clues: Vec<ScenarioClue>,
    #[serde(default)]
    pub options: Vec<ScenarioOption>,
    #[serde(default)]
    pub correct_option_id: String,
    #[serde(default)]
    pub reasoning: String,
    #[serde(default)]
    pub outcome_label: String,
    #[serde(default)]
    pub related_topics: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Studio {
    pub id: String,
    pub title: String,
    pub subject: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub last_studied: Option<DateTime<Utc>>,
    pub source_files: Vec<SourceFile>,
    pub topics: Vec<Topic>,
    pub scenarios: Vec<Scenario>,
    /// A build still running, for "Building 3 of 8" on the studio's row.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub build: Option<BuildState>,
    /// Who shared it, on a studio added from a share link.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub shared_by: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct BuildState {
    pub id: String,
    pub status: String,
    pub lessons_done: i32,
    pub lessons_total: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Me {
    pub id: String,
    pub email: Option<String>,
    pub credits: Option<i32>,
    /// For the profile button in the app header.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub photo_url: Option<String>,
}

/// The app's `SourceFileType` for an uploaded document.
pub fn file_type(filename: &str, mime: &str) -> &'static str {
    let name = filename.to_ascii_lowercase();
    let ext = name.rsplit('.').next().unwrap_or("");
    match ext {
        "pdf" => "pdf",
        "doc" | "docx" | "odt" | "rtf" => "docx",
        "ppt" | "pptx" | "odp" | "key" => "pptx",
        "png" | "jpg" | "jpeg" | "gif" | "webp" | "heic" | "bmp" => "image",
        "mp3" | "wav" | "m4a" | "aac" | "ogg" | "flac" => "audio",
        "mp4" | "mov" | "webm" | "mkv" | "avi" => "video",
        _ if mime.starts_with("image/") => "image",
        _ if mime.starts_with("audio/") => "audio",
        _ if mime.starts_with("video/") => "video",
        _ if mime == "application/pdf" => "pdf",
        _ => "txt",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_stored_payload_reads_like_python() {
        // Build-only keys are dropped; missing fields get the DTO defaults.
        let raw = serde_json::json!({
            "id": "gen_1", "studioId": "s", "title": "TCP", "subject": "",
            "definition": "d", "simpleExplanation": "", "detailedExplanation": "",
            "whyItMatters": "", "relatesTo": ["UDP"], "_otherTitles": ["x"],
            "flashcards": [{"id": "fc_1", "topicId": "gen_1", "front": "Q", "back": "A"}],
            "conceptLinks": [{"from": "a", "label": "is", "toTopic": "UDP"}]
        });
        let t: Topic = serde_json::from_value(raw).unwrap();
        let out = serde_json::to_value(&t).unwrap();
        assert!(out.get("relatesTo").is_none());
        assert_eq!(out["flashcards"][0]["ease"], 2.5);
        assert_eq!(out["flashcards"][0]["status"], "fresh");
        assert_eq!(out["flashcards"][0]["type"], "definition");
        assert_eq!(out["conceptLinks"][0]["from"], "a");
        assert_eq!(out["conceptLinks"][0]["to"], serde_json::Value::Null);
        assert_eq!(out["estimatedStudyTimeMinutes"], 10);
    }

    #[test]
    fn file_types() {
        assert_eq!(file_type("Lecture 5.PDF", ""), "pdf");
        assert_eq!(file_type("notes.docx", ""), "docx");
        assert_eq!(file_type("scan", "image/png"), "image");
        assert_eq!(file_type("x.md", "text/markdown"), "txt");
    }
}

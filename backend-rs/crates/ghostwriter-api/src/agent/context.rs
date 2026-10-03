//! What a run has gathered so far. Tools read and write it; it is saved to
//! `runs.context` after every step.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Context {
    pub instruction: String,
    pub essay_topic: Option<String>,
    pub essay_type: Option<String>,
    pub thesis: Option<String>,
    pub plan_notes: Option<String>,
    pub search_queries: Vec<String>,
    pub focus_options: Vec<String>,
    /// The angles the user picked.
    pub focus: Vec<String>,
    pub outlines: Vec<Outline>,
    pub search_results: Vec<Source>,
    pub scraped: Vec<ScrapedSource>,
    pub compacted: Vec<CompactedSource>,
    pub word_count: Option<i64>,
    pub citation_style: Option<String>,
    /// Title-page answers: studentName, instructorName, …
    pub format: BTreeMap<String, String>,
    pub words_written: i64,
    /// Set by `finalize_document`: the essay is delivered.
    pub export_ready: bool,
    /// Revisions made in this run (each is charged on its own).
    pub revisions: i64,
    /// Times the essay was humanized in this run (each is charged on its own).
    pub humanizations: i64,
    /// The humanizer last used on the essay, if any.
    pub humanized_by: Option<String>,
    /// How many paragraphs the essay had before it was humanized: what
    /// `split_paragraphs` restores.
    pub paragraphs_before_humanize: usize,
    /// Times the sources were evaluated in this run: only the first may ask
    /// for another search.
    pub source_evaluations: i64,
    /// What the last `critique_essay` found.
    pub critique_issues: Vec<CritiqueIssue>,
    /// The user's review of the sources: notes to steer each summary, and
    /// the ones to leave out.
    pub source_review: Vec<SourceNote>,
    /// The model and voice the run started with. Kept for the life of the
    /// run, so one picked up again later runs the same way.
    pub ai: Option<AiSnapshot>,
}

/// The user's AI choice, as a run uses it.
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct AiSnapshot {
    pub model_id: Option<String>,
    /// The name the AI goes by ("Octo v2 Pro").
    pub name: String,
    pub orchestrator: Option<String>,
    pub writer: Option<String>,
    pub fast: Option<String>,
    pub credit_multiplier: f64,
    /// How it talks in chat (the personality's prompt).
    pub voice: Option<String>,
}

impl Default for AiSnapshot {
    fn default() -> Self {
        Self {
            model_id: None,
            name: "GhostWriter".into(),
            orchestrator: None,
            writer: None,
            fast: None,
            credit_multiplier: 1.0,
            voice: None,
        }
    }
}

impl AiSnapshot {
    pub fn from_choice(choice: &octo_common::ai::Choice) -> Self {
        let mut snapshot = Self::default();
        if let Some(model) = &choice.model {
            snapshot.model_id = Some(model.id.clone());
            snapshot.name = model.display_name.clone();
            snapshot.orchestrator = Some(model.orchestrator_model.clone());
            snapshot.writer = Some(model.writer_model.clone());
            snapshot.fast = Some(model.fast_model.clone());
            snapshot.credit_multiplier = model.credit_multiplier;
        }
        snapshot.voice = choice.personality.as_ref().map(|p| p.prompt.clone());
        snapshot
    }
}

/// One weakness the critic found in the essay.
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct CritiqueIssue {
    /// Which paragraph, numbered from 1.
    pub paragraph: usize,
    /// `thesis`, `evidence`, `clarity`, `citations`, `length` or `structure`.
    #[serde(rename = "type")]
    pub kind: String,
    pub description: String,
    pub major: bool,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct SourceNote {
    pub url: String,
    pub focus_note: Option<String>,
    pub rejected: bool,
}

impl Context {
    /// The user's note on `url`, if they reviewed it.
    pub fn review_of(&self, url: &str) -> Option<&SourceNote> {
        self.source_review
            .iter()
            .find(|note| note.url.eq_ignore_ascii_case(url))
    }
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Outline {
    /// `Introduction`, `Body Paragraph` or `Conclusion`.
    #[serde(rename = "type")]
    pub kind: String,
    pub title: String,
    pub description: String,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Source {
    pub url: String,
    pub title: String,
    pub author: Option<String>,
    pub published_year: Option<String>,
    pub publisher: Option<String>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ScrapedSource {
    #[serde(flatten)]
    pub source: Source,
    pub full_content: String,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct CompactedSource {
    #[serde(flatten)]
    pub source: Source,
    pub summary: String,
}

/// The title-page fields the document has, by the name the agent asks under.
pub const FORMAT_FIELDS: [(&str, &str); 5] = [
    ("studentName", "studentName"),
    ("instructorName", "instructorName"),
    ("institutionName", "institutionName"),
    ("courseInfo", "courseName"),
    ("essayDate", "date"),
];

impl Context {
    /// Records the user's answer to `field`.
    pub fn apply_answer(&mut self, field: &str, value: &Value) {
        let text = match value {
            Value::String(s) => s.trim().to_string(),
            other => other.to_string(),
        };
        if text.is_empty() {
            return;
        }

        match field {
            "wordCount" => {
                let parsed = value
                    .as_i64()
                    .or_else(|| value.as_f64().map(|f| f.round() as i64))
                    .or_else(|| text.parse().ok());
                if let Some(words) = parsed.filter(|w| *w > 0) {
                    self.word_count = Some(words);
                }
            }
            "citationStyle" => self.citation_style = Some(text),
            "sourceReview" => {
                // An array of { url, focusNote?, rejected? }, or its text.
                let notes = match value {
                    Value::Array(_) => serde_json::from_value(value.clone()).ok(),
                    _ => serde_json::from_str::<Vec<SourceNote>>(&text).ok(),
                };
                if let Some(notes) = notes {
                    self.source_review = notes;
                }
            }
            "essayFocus" => {
                // A JSON array, sent either as an array or as its text.
                let picked = match value {
                    Value::Array(items) => Some(items.clone()),
                    _ => serde_json::from_str::<Vec<Value>>(&text).ok(),
                };
                if let Some(items) = picked {
                    self.focus = items
                        .iter()
                        .filter_map(|v| v.as_str())
                        .map(|s| s.trim().to_string())
                        .filter(|s| !s.is_empty())
                        .collect();
                }
            }
            _ => {
                if FORMAT_FIELDS.iter().any(|(asked, _)| *asked == field) {
                    self.format.insert(field.to_string(), text);
                }
            }
        }
    }

    /// The title-page answers, keyed the way the document stores them.
    pub fn document_fields(&self) -> Value {
        let mut fields = serde_json::Map::new();
        for (asked, stored) in FORMAT_FIELDS {
            if let Some(answer) = self.format.get(asked) {
                fields.insert(stored.to_string(), Value::String(answer.clone()));
            }
        }
        Value::Object(fields)
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    #[test]
    fn answers_land_in_the_right_place() {
        let mut ctx = Context::default();

        ctx.apply_answer("wordCount", &json!(800));
        assert_eq!(ctx.word_count, Some(800));
        ctx.apply_answer("wordCount", &json!("1200"));
        assert_eq!(ctx.word_count, Some(1200));
        ctx.apply_answer("wordCount", &json!("lots"));
        assert_eq!(ctx.word_count, Some(1200)); // unusable answers change nothing

        ctx.apply_answer("citationStyle", &json!(" MLA "));
        assert_eq!(ctx.citation_style.as_deref(), Some("MLA"));

        ctx.apply_answer("essayFocus", &json!(["Economic impact", " Policy "]));
        assert_eq!(ctx.focus, ["Economic impact", "Policy"]);
        ctx.apply_answer("essayFocus", &json!("[\"History\"]"));
        assert_eq!(ctx.focus, ["History"]);
        ctx.apply_answer("essayFocus", &json!("__suggest_more__"));
        assert_eq!(ctx.focus, ["History"]); // a request for more is not a pick

        ctx.apply_answer("studentName", &json!("Ada Lovelace"));
        ctx.apply_answer("courseInfo", &json!("HIST 101"));
        ctx.apply_answer("essayDate", &json!("October 2, 2026"));
        ctx.apply_answer("favouriteColour", &json!("red"));
        assert_eq!(
            ctx.document_fields(),
            json!({
                "studentName": "Ada Lovelace",
                "courseName": "HIST 101",
                "date": "October 2, 2026",
            })
        );
    }
}

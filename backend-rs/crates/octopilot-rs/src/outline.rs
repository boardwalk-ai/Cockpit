//! Outline generation — OpenRouter-backed (model + key from the shared DB).
//! Returns `[{type,title,description,bullets}]`, matching the Flutter
//! `AssistService.outline` / `OutlineData` contract.

use axum::extract::State;
use axum::Json;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::openrouter::{call_json, parse_json_loose, ChatMessage};
use crate::{db, AppState};

#[derive(Deserialize)]
pub struct OutlineBody {
    pub topic: String,
    #[serde(default)]
    pub assignment: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct OutlineSection {
    #[serde(rename = "type")]
    pub kind: String,
    pub title: String,
    pub description: String,
    pub bullets: Vec<String>,
}

pub async fn outline(
    State(st): State<AppState>,
    Json(body): Json<OutlineBody>,
) -> Result<Json<Vec<OutlineSection>>, crate::error::ApiError> {
    let topic = body.topic.trim();
    if topic.is_empty() {
        return Err(crate::error::ApiError::bad_request("missing topic"));
    }
    let key = db::openrouter_key(&st.db).await?;
    let model = db::model(&st.db, "primary_model", "anthropic/claude-sonnet-4-6").await;

    let assignment_block = if body.assignment.trim().is_empty() {
        String::new()
    } else {
        format!(
            "\nThe outline must satisfy this assignment brief:\n{}\n",
            body.assignment.trim().chars().take(2000).collect::<String>()
        )
    };

    let system = "You are an academic writing planner. Produce a clear, logical \
        essay outline: one Introduction section, two to four Body Paragraph \
        sections each covering a distinct point, and one Conclusion section. \
        Each section has a short title, a one-sentence description, and 2–4 \
        concrete bullet points. Respond ONLY as JSON of the form \
        {\"outlines\":[{\"type\":\"Introduction|Body Paragraph|Conclusion\",\
        \"title\":\"...\",\"description\":\"...\",\"bullets\":[\"...\"]}]}."
        .to_string();

    let user = format!("Essay topic: {topic}{assignment_block}");

    let raw = call_json(
        &st.http,
        &key,
        &model,
        vec![
            ChatMessage { role: "system", content: system },
            ChatMessage { role: "user", content: user },
        ],
        0.4,
    )
    .await?;

    let parsed = parse_json_loose(&raw).unwrap_or(Value::Null);
    let rows = match &parsed {
        Value::Array(a) => a.clone(),
        Value::Object(o) => o
            .get("outlines")
            .and_then(|v| v.as_array())
            .cloned()
            .or_else(|| o.values().find_map(|v| v.as_array().cloned()))
            .unwrap_or_default(),
        _ => Vec::new(),
    };

    let sections = rows
        .into_iter()
        .filter_map(|r| {
            let title = r.get("title")?.as_str()?.to_string();
            Some(OutlineSection {
                kind: r
                    .get("type")
                    .and_then(|x| x.as_str())
                    .unwrap_or("Body Paragraph")
                    .to_string(),
                title,
                description: r
                    .get("description")
                    .and_then(|x| x.as_str())
                    .unwrap_or("")
                    .to_string(),
                bullets: r
                    .get("bullets")
                    .and_then(|x| x.as_array())
                    .map(|a| {
                        a.iter()
                            .filter_map(|b| b.as_str().map(|s| s.to_string()))
                            .collect()
                    })
                    .unwrap_or_default(),
            })
        })
        .collect();

    Ok(Json(sections))
}

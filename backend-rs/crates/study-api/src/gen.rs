//! What a studio build asks the model and how its replies become topics and
//! scenarios: the prompts (verbatim from `services/generate.py`, checked
//! against a dump of the Python strings in `tests/fixtures`), the tolerant
//! JSON reader, and the shaping into the payloads `generated_topics` /
//! `generated_scenarios` keep. No I/O here; `build.rs` runs it.
//!
//! Where Python would have dropped a whole lesson over one odd value (a
//! number where a string belongs), this keeps the lesson and writes the value
//! as text, so every stored payload reads back through `dto::Topic`.

use std::collections::{HashMap, HashSet};

use serde_json::{json, Map, Value};
use uuid::Uuid;

use crate::search::Hit;

// --- Pass 1: outline -------------------------------------------------------
pub const OUTLINE_SYSTEM: &str = "You are a curriculum designer. From the study material, produce a lesson \
outline as strict JSON. Ground it ONLY in the material — never invent. \
Output JSON only: no markdown, no commentary.";

pub const OUTLINE_HINT: &str = r#"List the lessons this material should be broken into — ONE per distinct concept
or section. Let the material decide the count (don't merge unrelated concepts,
don't cap it): a short note may be 2-3, a chapter 6-12, a full textbook 20+.
Cover the WHOLE material, ordered the way it should be studied.

Return ONLY JSON: an array of
{"title": str, "scope": str, "buildsOn": [str], "relatesTo": [str]}
where scope is a one-line note on exactly what that lesson should cover,
buildsOn lists the titles of EARLIER lessons in this array that it directly
relies on (0-2, often none), and relatesTo lists the titles of OTHER lessons in
this array it is closely connected to without depending on them (0-3).
Use the exact titles. No prose outside JSON.
Titles are short names, not sentences: 2-5 words, no colon, no numbering
(e.g. "TCP congestion control", not "Understanding how TCP controls congestion")."#;

// --- Pass 2: one call per lesson --------------------------------------------
pub const DETAIL_SYSTEM: &str = "You are an expert tutor writing ONE in-depth study lesson. Use ONLY the \
provided material — never invent facts. Be thorough and concrete. Output a \
single JSON object only: no markdown, no commentary.";

pub const CONCEPTS_SPEC: &str = r#""concepts": [                      // 4-8 key ideas of THIS lesson
    {"name": str, "meaning": str, "example": str}, ...
  ],                                 // name: 1-4 words; meaning: one plain sentence; example: one short concrete case
  "links": [                         // 4-10 relationships the material actually states
    {"from": str, "label": str, "to": str}, ...
  ],                                 // from/to: a concept name above, or an exact title from OTHER LESSONS;
                                     // label: a 1-3 word verb phrase read "from label to", e.g. "causes", "is part of", "halves", "contrasts with""#;

const DETAIL_TEMPLATE: &str = r#"Write a rich, complete lesson on "@TITLE@".
Focus: @SCOPE@
@OTHERS@
Return ONLY a JSON object:
{
  "title": "@TITLE@",
  "summary": [str, str, str],        // EXACTLY 3 key points, each ONE plain sentence of at most 12 words
  "definition": str,                 // 1-2 precise sentences
  "simpleExplanation": str,          // plain-language, "explain like I'm 10"
  "detailedExplanation": str,        // THOROUGH: multiple paragraphs, mechanisms, how/why it works
  "whyItMatters": str,               // 2-4 sentences on real-world relevance
  "examples": [str, ...],            // 2-4 concrete worked examples
  "commonMistakes": [str, ...],      // 2-4 pitfalls learners hit
  "memoryHooks": [str, ...],         // 1-3 mnemonics / analogies
  "flashcards": [{"front": str, "back": str}, ...],   // 6-10
  "quizQuestions": [                                     // 4-6, MIX the types below
    {
      "type": "multipleChoice" | "trueFalse" | "shortAnswer" | "fillBlank",
      "question": str,                 // for fillBlank, put a "____" blank inside the sentence
      "choices": [str],                // multipleChoice: 4 options; trueFalse: ["True","False"]; shortAnswer/fillBlank: []
      "answer": str,                   // the exact correct answer; must equal one choice for multipleChoice/trueFalse
      "explanation": str
    }, ...
  ],
  "difficulty": 1-5, "importance": 1-5,
@CONCEPTS@
}
Vary the quiz question types to suit THIS subject, don't use only multipleChoice:
- conceptual / reasoning topics favor multipleChoice and trueFalse
- terminology, facts, formulas, vocabulary favor shortAnswer and fillBlank
- keep shortAnswer and fillBlank answers to 1-3 words so they can be auto-graded
- when there are 3+ questions, include at least two different types
Base everything ONLY on the provided material."#;

pub fn others_line(others: &[String]) -> String {
    if others.is_empty() {
        return String::new();
    }
    format!("OTHER LESSONS in this course: {}\n", others.join("; "))
}

pub fn detail_hint(title: &str, scope: &str, others: &[String]) -> String {
    DETAIL_TEMPLATE
        .replace("@CONCEPTS@", CONCEPTS_SPEC)
        .replace("@OTHERS@", &others_line(others))
        .replace("@SCOPE@", scope)
        .replace("@TITLE@", title)
        .trim()
        .to_string()
}

// --- Scenarios -------------------------------------------------------------
pub const SCENARIO_SYSTEM: &str = "You are an instructional designer building APPLICATION scenarios that test \
reasoning, not recall — realistic situations the learner must diagnose. \
Ground everything ONLY in the material; never invent facts. Output strict \
JSON only: no markdown, no commentary.";

pub const SCENARIO_HINT: &str = r#"From the material, create realistic application scenarios — situations where the
learner must REASON through a problem, not recall a fact. Make as many as the
material genuinely supports (typically 5-10), ordered easy → hard.

Return ONLY JSON: an array. Each scenario:
{
  "title": str,                    // short case name
  "difficulty": 1-5,
  "estimatedMinutes": int,
  "skills": [str],                 // 2-4 skills being tested
  "aiNote": str,                   // one line, e.g. "Multiple concepts may be required."
  "problem": str,                  // the situation, 2-4 short sentences
  "question": str,                 // what the learner must determine
  "clues": [{"label": str, "detail": str}],  // 3-5 things to investigate + what each reveals
  "options": [str, str, str, str], // 4 candidate first actions (only one is best)
  "correctIndex": 0,               // index (0-3) of the best first action
  "reasoning": str,                // WHY that action is right; rule out the others
  "outcomeLabel": str,             // short result, e.g. "Likely issue: Layer 3"
  "relatedTopics": [str]           // 2-3 related topic titles from the material
}
Base everything ONLY on the provided material. No prose outside the JSON."#;

// --- Connections (studios built before the outline had them) ----------------
pub const CONNECT_SYSTEM: &str = "You are a curriculum designer. Given a course's lesson titles in study \
order, say how they connect. Output JSON only: no markdown, no commentary.";

pub fn connect_hint(titles: &[String]) -> String {
    let listed = titles.iter().map(|t| format!("- {t}")).collect::<Vec<_>>().join("\n");
    format!(
        "Lessons, in the order they are studied:\n{listed}\n\n\
Return ONLY a JSON object mapping EVERY title above to\n\
{{\"buildsOn\": [str], \"relatesTo\": [str]}}:\n\
buildsOn = titles of EARLIER lessons it directly relies on (0-2, often none);\n\
relatesTo = titles of OTHER lessons it is closely connected to without\n\
depending on them (0-3). Use the exact titles."
    )
}

// --- Concept maps for lessons built before they existed ---------------------
pub const CONCEPT_SYSTEM: &str = "You are a tutor drawing a concept map of ONE lesson. Use ONLY the lesson \
text given — never invent. Output a single JSON object only.";

pub fn concept_question(title: &str, others: &[String]) -> String {
    format!("Lesson: \"{title}\"\n{}Return ONLY a JSON object:\n{{\n{CONCEPTS_SPEC}\n}}", others_line(others))
}

/// The lesson's own text, for its concept map (first 12,000 characters).
pub fn concept_context(topic: &Value) -> String {
    let mut parts = Vec::new();
    for k in ["definition", "simpleExplanation", "detailedExplanation", "whyItMatters"] {
        let s = text(topic.get(k));
        if !s.trim().is_empty() {
            parts.push(s.trim().to_string());
        }
    }
    let mut out = parts.join("\n\n");
    let examples: Vec<String> = strings(topic.get("examples")).iter().map(|e| format!("- {e}")).collect();
    if !examples.is_empty() {
        out.push_str("\n\nExamples:\n");
        out.push_str(&examples.join("\n"));
    }
    out.chars().take(12_000).collect()
}

// --- Limits -----------------------------------------------------------------
/// Material sent to the outline and scenario passes (characters).
pub const CONTEXT_CHAR_BUDGET: usize = 120_000;
/// A lesson's material when retrieval finds nothing (Python sent the whole
/// 120k budget here; capped so one lesson can't cost a whole outline).
pub const LESSON_FALLBACK_CHARS: usize = 24_000;
pub const OUTLINE_MAX_TOKENS: u32 = 3_000;
pub const DETAIL_MAX_TOKENS: u32 = 5_000;
pub const SCENARIO_MAX_TOKENS: u32 = 8_000;
pub const CONNECT_MAX_TOKENS: u32 = 1_500;
pub const CONCEPT_MAX_TOKENS: u32 = 1_800;
pub const DETAIL_CONCURRENCY: usize = 8;
pub const DETAIL_TOP_K: i64 = 8;

const QUIZ_TYPES: [&str; 4] = ["multipleChoice", "trueFalse", "shortAnswer", "fillBlank"];

// --- Helpers ------------------------------------------------------------------
/// Python's `str(x)` for a JSON value: strings as they are, `None` empty,
/// booleans `True` / `False`, anything else as JSON.
pub fn text(v: Option<&Value>) -> String {
    match v {
        None | Some(Value::Null) => String::new(),
        Some(Value::String(s)) => s.clone(),
        Some(Value::Bool(b)) => if *b { "True" } else { "False" }.into(),
        Some(other) => other.to_string(),
    }
}

/// A list of strings from whatever the model sent (non-lists → empty).
pub fn strings(v: Option<&Value>) -> Vec<String> {
    v.and_then(Value::as_array).map(|a| a.iter().map(|x| text(Some(x))).collect()).unwrap_or_default()
}

/// Python's `int(raw.get(key, d) or d)`, tolerant of "4" and 4.0.
fn int_or(v: Option<&Value>, d: i64) -> i64 {
    match v {
        Some(Value::Number(n)) => n.as_i64().or_else(|| n.as_f64().map(|f| f as i64)).filter(|x| *x != 0).unwrap_or(d),
        Some(Value::String(s)) => s.trim().parse::<f64>().ok().map(|f| f as i64).filter(|x| *x != 0).unwrap_or(d),
        Some(Value::Bool(true)) => 1,
        _ => d,
    }
}

fn hex(n: usize) -> String {
    Uuid::new_v4().simple().to_string()[..n].to_string()
}

fn truthy(v: Option<&Value>) -> bool {
    match v {
        None | Some(Value::Null) => false,
        Some(Value::Bool(b)) => *b,
        Some(Value::String(s)) => !s.is_empty(),
        Some(Value::Array(a)) => !a.is_empty(),
        Some(Value::Object(o)) => !o.is_empty(),
        Some(Value::Number(n)) => n.as_f64() != Some(0.0),
    }
}

/// Parses JSON from a model reply, tolerating code fences and junk around
/// it, and an array cut off mid-object. Same salvage steps as Python.
pub fn parse_json(raw: &str) -> Option<Value> {
    let mut t = raw.trim().to_string();
    if t.starts_with("```") {
        let inner = t.split("```").nth(1).unwrap_or("");
        t = inner.strip_prefix("json").unwrap_or(inner).trim().to_string();
    }
    if let Ok(v) = serde_json::from_str::<Value>(&t) {
        return Some(v);
    }
    for (open, close) in [('[', ']'), ('{', '}')] {
        let (Some(start), Some(end)) = (t.find(open), t.rfind(close)) else { continue };
        if end <= start {
            continue;
        }
        if let Ok(v) = serde_json::from_str::<Value>(&t[start..=end]) {
            return Some(v);
        }
        if open == '[' {
            if let Some(cut) = t.rfind('}').filter(|c| *c > start) {
                if let Ok(v) = serde_json::from_str::<Value>(&format!("{}]", &t[start..=cut])) {
                    return Some(v);
                }
            }
        }
    }
    None
}

/// `parsed` if it is a list, else `parsed[key]` (a model sometimes wraps it).
fn list_in(parsed: Option<Value>, key: &str) -> Vec<Value> {
    match parsed {
        Some(Value::Array(a)) => a,
        Some(Value::Object(mut o)) => match o.remove(key) {
            Some(Value::Array(a)) => a,
            _ => vec![],
        },
        _ => vec![],
    }
}

fn dedup(v: Vec<String>) -> Vec<String> {
    let mut seen = HashSet::new();
    v.into_iter().filter(|x| seen.insert(x.clone())).collect()
}

// --- Outline ---------------------------------------------------------------------
#[derive(Debug, Clone, PartialEq)]
pub struct Lesson {
    pub title: String,
    pub scope: String,
    pub builds_on: Vec<String>,
    pub relates_to: Vec<String>,
}

/// The outline from the model's reply: lessons with a title; `buildsOn` only
/// names earlier lessons (≤ 2), `relatesTo` other real lessons (≤ 3).
pub fn outline(reply: &str) -> Vec<Lesson> {
    let mut out: Vec<Lesson> = Vec::new();
    for it in list_in(parse_json(reply), "lessons") {
        let Some(o) = it.as_object() else { continue };
        if !truthy(o.get("title")) {
            continue;
        }
        let earlier: HashSet<&str> = out.iter().map(|l| l.title.as_str()).collect();
        let builds_on: Vec<String> =
            strings(o.get("buildsOn")).into_iter().filter(|t| earlier.contains(t.as_str())).take(2).collect();
        out.push(Lesson {
            title: text(o.get("title")),
            scope: o.get("scope").map(|s| text(Some(s))).unwrap_or_default(),
            builds_on,
            relates_to: strings(o.get("relatesTo")),
        });
    }
    let titles: HashSet<String> = out.iter().map(|l| l.title.clone()).collect();
    for l in &mut out {
        let rel = dedup(std::mem::take(&mut l.relates_to));
        l.relates_to = rel
            .into_iter()
            .filter(|t| titles.contains(t) && *t != l.title && !l.builds_on.contains(t))
            .take(3)
            .collect();
    }
    out
}

/// The studio's chunks joined up to the budget (stops at the first that
/// doesn't fit, like Python).
pub fn material(chunks: &[String], budget: usize) -> String {
    let mut used = 0;
    let mut out = Vec::new();
    for c in chunks {
        let n = c.chars().count();
        if used + n > budget {
            break;
        }
        out.push(c.as_str());
        used += n;
    }
    out.join("\n\n")
}

/// Citations for a lesson: one per document, top 4, with its page.
pub fn hits_to_sources(hits: &[Hit], names: &HashMap<Uuid, String>) -> Vec<Value> {
    let mut seen = HashSet::new();
    let mut out = Vec::new();
    for h in hits {
        if !seen.insert(h.document_id) {
            continue;
        }
        let snippet: String = h.content.trim().replace('\n', " ").chars().take(220).collect();
        out.push(json!({
            "fileName": names.get(&h.document_id).cloned().unwrap_or_else(|| "Uploaded material".into()),
            "snippet": snippet,
            "page": h.page,
        }));
        if out.len() >= 4 {
            break;
        }
    }
    out
}

// --- Shaping ----------------------------------------------------------------------
/// A lesson reply → the stored topic payload (camelCase TopicDTO).
/// `raw` may carry `prerequisites`, `relatesTo` and `_otherTitles`.
pub fn shape_topic(raw: &Value, studio_id: &str, sources: Vec<Value>) -> Value {
    let topic_id = format!("gen_{}", hex(10));
    let get = |k: &str| raw.get(k);
    let flashcards: Vec<Value> = get("flashcards")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_object)
        .map(|fc| {
            json!({
                "id": format!("fc_{}", hex(8)),
                "topicId": topic_id,
                "front": text(fc.get("front")),
                "back": text(fc.get("back")),
                "type": "definition",
                "difficulty": 2,
                "status": "fresh",
            })
        })
        .collect();
    let quiz: Vec<Value> = get("quizQuestions")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_object)
        .map(|q| {
            let mut choices = strings(q.get("choices"));
            let given = q.get("type").and_then(Value::as_str).filter(|t| QUIZ_TYPES.contains(t));
            let kind = match given {
                Some(t) => t,
                None if choices.len() > 2 => "multipleChoice",
                None if choices.len() == 2 => "trueFalse",
                None => "shortAnswer",
            };
            match kind {
                "trueFalse" => choices = vec!["True".into(), "False".into()],
                "shortAnswer" | "fillBlank" => choices.clear(),
                _ => {}
            }
            json!({
                "id": format!("q_{}", hex(8)),
                "topicId": topic_id,
                "type": kind,
                "question": text(q.get("question")),
                "choices": choices,
                "answer": text(q.get("answer")),
                "explanation": text(q.get("explanation")),
                "difficulty": 2,
            })
        })
        .collect();
    let summary: Vec<String> =
        strings(get("summary")).into_iter().map(|s| s.trim().to_string()).filter(|s| !s.is_empty()).take(4).collect();
    let (concepts, links) = shape_concepts(raw, &topic_id);
    let title = match get("title") {
        None => "Untitled Topic".to_string(),
        v => text(v),
    };
    json!({
        "id": topic_id,
        "studioId": studio_id,
        "title": title,
        "subject": text(get("subject")),
        "summary": summary,
        "definition": text(get("definition")),
        "simpleExplanation": text(get("simpleExplanation")),
        "detailedExplanation": text(get("detailedExplanation")),
        "whyItMatters": text(get("whyItMatters")),
        "examples": strings(get("examples")),
        "commonMistakes": strings(get("commonMistakes")),
        "relatedTopicIds": [],
        "prerequisites": strings(get("prerequisites")),
        "relatesTo": strings(get("relatesTo")),
        "memoryHooks": strings(get("memoryHooks")),
        "sources": sources,
        "concepts": concepts,
        "conceptLinks": links,
        "flashcards": flashcards,
        "quizQuestions": quiz,
        "difficulty": int_or(get("difficulty"), 3),
        "importance": int_or(get("importance"), 3),
        "estimatedStudyTimeMinutes": 12,
        "mastery": 0.0,
    })
}

/// A concept map from a reply: concepts (≤ 8, unique names ≤ 60 chars) and
/// links (≤ 12) between them, or to another lesson's title as `toTopic`.
pub fn shape_concepts(raw: &Value, topic_id: &str) -> (Vec<Value>, Vec<Value>) {
    let mut concepts = Vec::new();
    let mut by_name: HashMap<String, String> = HashMap::new();
    for (i, c) in raw.get("concepts").and_then(Value::as_array).into_iter().flatten().enumerate() {
        let Some(c) = c.as_object() else { continue };
        let name = text(c.get("name")).trim().to_string();
        let key = name.to_lowercase();
        if name.is_empty() || by_name.contains_key(&key) || name.chars().count() > 60 {
            continue;
        }
        let cid = format!("{topic_id}_c{i}");
        by_name.insert(key, cid.clone());
        concepts.push(json!({
            "id": cid,
            "name": name,
            "meaning": text(c.get("meaning")).trim(),
            "example": text(c.get("example")).trim(),
        }));
        if concepts.len() >= 8 {
            break;
        }
    }
    let others: HashMap<String, String> = strings(raw.get("_otherTitles"))
        .into_iter()
        .map(|t| (t.trim().to_lowercase(), t.trim().to_string()))
        .collect();
    let mut links = Vec::new();
    let mut seen: HashSet<(String, String)> = HashSet::new();
    for l in raw.get("links").and_then(Value::as_array).into_iter().flatten() {
        let Some(l) = l.as_object() else { continue };
        let a = by_name.get(&text(l.get("from")).trim().to_lowercase()).cloned();
        let label = text(l.get("label")).split_whitespace().take(4).collect::<Vec<_>>().join(" ");
        let to_name = text(l.get("to")).trim().to_lowercase();
        let Some(a) = a.filter(|_| !label.is_empty()) else { continue };
        match by_name.get(&to_name) {
            Some(b) if *b != a && !seen.contains(&(a.clone(), b.clone())) => {
                seen.insert((a.clone(), b.clone()));
                links.push(json!({ "from": a, "label": label, "to": b }));
            }
            Some(_) => {}
            None => {
                if let Some(title) = others.get(&to_name) {
                    if seen.insert((a.clone(), to_name.clone())) {
                        links.push(json!({ "from": a, "label": label, "toTopic": title }));
                    }
                }
            }
        }
        if links.len() >= 12 {
            break;
        }
    }
    (concepts, links)
}

/// A scenario reply → the stored payload (ScenarioDTO). Option ids keep
/// their position in the reply, as Python numbers them before filtering.
pub fn shape_scenario(raw: &Value, studio_id: &str) -> Value {
    let options: Vec<Value> = raw
        .get("options")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .enumerate()
        .filter(|(_, o)| !text(Some(o)).trim().is_empty())
        .map(|(i, o)| json!({ "id": format!("opt_{i}"), "label": text(Some(o)) }))
        .collect();
    let ci = raw.get("correctIndex").and_then(Value::as_i64).filter(|c| *c >= 0 && (*c as usize) < options.len());
    let correct = match ci {
        Some(c) => options[c as usize]["id"].clone(),
        None => options.first().map(|o| o["id"].clone()).unwrap_or_else(|| json!("opt_0")),
    };
    let clues: Vec<Value> = raw
        .get("clues")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_object)
        .filter(|c| truthy(c.get("label")))
        .map(|c| json!({ "id": format!("clue_{}", hex(6)), "label": text(c.get("label")), "detail": text(c.get("detail")) }))
        .collect();
    let title = match raw.get("title") {
        None => "Scenario".to_string(),
        v => text(v),
    };
    json!({
        "id": format!("scn_{}", hex(10)),
        "studioId": studio_id,
        "title": title,
        "difficulty": int_or(raw.get("difficulty"), 3),
        "estimatedMinutes": int_or(raw.get("estimatedMinutes"), 6),
        "skills": strings(raw.get("skills")),
        "aiNote": text(raw.get("aiNote")),
        "problem": text(raw.get("problem")),
        "question": text(raw.get("question")),
        "clues": clues,
        "options": options,
        "correctOptionId": correct,
        "reasoning": text(raw.get("reasoning")),
        "outcomeLabel": text(raw.get("outcomeLabel")),
        "relatedTopics": strings(raw.get("relatedTopics")),
    })
}

pub fn scenarios(reply: &str, studio_id: &str) -> Vec<Value> {
    list_in(parse_json(reply), "scenarios")
        .iter()
        .filter(|s| s.is_object() && truthy(s.get("problem")))
        .map(|s| shape_scenario(s, studio_id))
        .collect()
}

/// title → (buildsOn, relatesTo), real titles only: buildsOn from earlier
/// lessons (≤ 2), relatesTo from any other (≤ 3).
pub fn clean_connections(raw: Option<Value>, titles: &[String]) -> HashMap<String, (Vec<String>, Vec<String>)> {
    let mut out = HashMap::new();
    let Some(Value::Object(m)) = raw else { return out };
    let order: HashMap<&str, usize> = titles.iter().enumerate().map(|(i, t)| (t.as_str(), i)).collect();
    for (title, links) in m {
        let (Some(&me), Some(links)) = (order.get(title.as_str()), links.as_object()) else { continue };
        let before: Vec<String> = strings(links.get("buildsOn"))
            .into_iter()
            .filter(|t| order.get(t.as_str()).is_some_and(|i| *i < me))
            .collect();
        let builds_on: Vec<String> = dedup(before).into_iter().take(2).collect();
        let relates: Vec<String> = strings(links.get("relatesTo"))
            .into_iter()
            .filter(|t| order.contains_key(t.as_str()) && *t != title && !builds_on.contains(t))
            .collect();
        out.insert(title, (builds_on, dedup(relates).into_iter().take(3).collect()));
    }
    out
}

// --- Keeping ids across a rebuild -------------------------------------------------
fn norm(v: Option<&Value>) -> String {
    text(v).to_lowercase().split_whitespace().collect::<Vec<_>>().join(" ")
}

/// Normalized title → (topic id, normalized card front → card id), from the
/// studio's topics before a rebuild. The first topic of a title wins.
pub fn keep_map(payloads: &[Value]) -> HashMap<String, (String, HashMap<String, String>)> {
    let mut out = HashMap::new();
    for p in payloads {
        let title = norm(p.get("title"));
        let Some(tid) = p.get("id").and_then(Value::as_str).filter(|t| !t.is_empty()) else { continue };
        if title.is_empty() || out.contains_key(&title) {
            continue;
        }
        let mut cards = HashMap::new();
        for c in p.get("flashcards").and_then(Value::as_array).into_iter().flatten() {
            let (Some(id), front) = (c.get("id").and_then(Value::as_str).filter(|i| !i.is_empty()), norm(c.get("front"))) else {
                continue;
            };
            if !front.is_empty() {
                cards.insert(front, id.to_string());
            }
        }
        out.insert(title, (tid.to_string(), cards));
    }
    out
}

/// A rebuilt topic takes the old id of the topic with its title (and its
/// cards the old ids of cards with the same front), so progress stays.
pub fn carry_ids(mut payload: Value, keep: &HashMap<String, (String, HashMap<String, String>)>) -> Value {
    let Some((tid, cards)) = keep.get(&norm(payload.get("title"))) else { return payload };
    let Some(obj) = payload.as_object_mut() else { return payload };
    obj.insert("id".into(), json!(tid));
    for key in ["flashcards", "quizQuestions"] {
        for item in obj.get_mut(key).and_then(Value::as_array_mut).into_iter().flatten() {
            if let Some(m) = item.as_object_mut() {
                m.insert("topicId".into(), json!(tid));
            }
        }
    }
    for c in obj.get_mut("flashcards").and_then(Value::as_array_mut).into_iter().flatten() {
        let front = norm(c.get("front"));
        if let (Some(id), Some(m)) = (cards.get(&front), c.as_object_mut()) {
            m.insert("id".into(), json!(id));
        }
    }
    payload
}

/// A lesson reply with the outline's facts added before shaping.
pub fn lesson_raw(mut obj: Map<String, Value>, lesson: &Lesson, others: &[String]) -> Value {
    obj.entry("title").or_insert_with(|| json!(lesson.title));
    obj.insert("prerequisites".into(), json!(lesson.builds_on));
    obj.insert("_otherTitles".into(), json!(others));
    obj.insert("relatesTo".into(), json!(lesson.relates_to));
    Value::Object(obj)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture() -> Value {
        serde_json::from_str(include_str!("../tests/fixtures/build_prompts.json")).unwrap()
    }

    fn s(v: &Value) -> &str {
        v.as_str().unwrap()
    }

    #[test]
    fn prompts_match_python_exactly() {
        let f = fixture();
        let others = vec!["Slow start".to_string(), "Routing \"basics\"".to_string()];
        assert_eq!(OUTLINE_SYSTEM, s(&f["outline_system"]));
        assert_eq!(OUTLINE_HINT, s(&f["outline_hint"]));
        assert_eq!(DETAIL_SYSTEM, s(&f["detail_system"]));
        assert_eq!(detail_hint("TCP congestion control", "How TCP reacts to loss", &others), s(&f["detail_hint"]));
        assert_eq!(detail_hint("Only lesson", "Everything", &[]), s(&f["detail_hint_alone"]));
        assert_eq!(SCENARIO_SYSTEM, s(&f["scenario_system"]));
        assert_eq!(SCENARIO_HINT, s(&f["scenario_hint"]));
        assert_eq!(CONNECT_SYSTEM, s(&f["connect_system"]));
        assert_eq!(connect_hint(&["A".into(), "B".into(), "C".into()]), s(&f["connect_hint"]));
        assert_eq!(CONCEPT_SYSTEM, s(&f["concept_system"]));
        assert_eq!(concept_question("TCP congestion control", &others), s(&f["concept_question"]));
        let topic = json!({"id": "gen_abc", "title": "TCP congestion control", "definition": "Def.", "simpleExplanation": "",
            "detailedExplanation": "Long.", "whyItMatters": "Matters.", "examples": ["e1", "e2"]});
        assert_eq!(concept_context(&topic), s(&f["concept_context"]));
    }

    #[test]
    fn json_salvage_like_python() {
        for case in fixture()["parse_cases"].as_array().unwrap() {
            let got = parse_json(s(&case[0]));
            let want = if case[1].is_null() { None } else { Some(case[1].clone()) };
            assert_eq!(got, want, "{}", case[0]);
        }
    }

    /// Replaces random ids with their position so two shapes compare.
    fn mask(v: &Value) -> Value {
        let t = v.to_string();
        let re = |p: &str, n: usize, t: String| -> String {
            let mut out = String::new();
            let mut rest = t.as_str();
            while let Some(i) = rest.find(p) {
                out.push_str(&rest[..i + p.len()]);
                rest = &rest[i + p.len()..];
                let k = rest.chars().take(n).filter(|c| c.is_ascii_hexdigit()).count();
                if k == n {
                    out.push_str(&"x".repeat(n));
                    rest = &rest[n..];
                }
            }
            out.push_str(rest);
            out
        };
        let t = re("gen_", 10, t);
        let t = re("fc_", 8, t);
        let t = re("q_", 8, t);
        let t = re("scn_", 10, t);
        let t = re("clue_", 6, t);
        serde_json::from_str(&t).unwrap()
    }

    #[test]
    fn shapes_like_python() {
        let f = fixture();
        let raw = json!({"title": "T", "summary": ["  a ", "", "b", "c", "d", "e"], "examples": ["x"], "difficulty": "4", "importance": null,
          "flashcards": [{"front": "F1", "back": "B1"}], "quizQuestions": [
           {"type": "multipleChoice", "question": "Q", "choices": ["a","b","c","d"], "answer": "a", "explanation": "e"},
           {"question": "TF?", "choices": ["yes", "no"], "answer": "True"},
           {"type": "fillBlank", "question": "x ____", "choices": ["z"], "answer": "y"},
           {"question": "SA", "answer": "w"}],
          "concepts": [{"name": "Window", "meaning": "m", "example": "x"}, {"name": "window"}, {"name": "Loss", "meaning": "m2"}, {"name": ""}],
          "links": [{"from": "Window", "label": "  is   cut   by  loss  now ", "to": "Loss"}, {"from": "Loss", "label": "precedes", "to": "slow start"},
                    {"from": "Window", "label": "x", "to": "Window"}, {"from": "Nope", "label": "y", "to": "Loss"}],
          "_otherTitles": ["Slow start"], "prerequisites": ["P"], "relatesTo": ["R"]});
        let got = shape_topic(&raw, "studio-1", vec![json!({"fileName": "f.pdf", "snippet": "s", "page": null})]);
        assert_eq!(mask(&got), mask(&f["shaped_topic"]));
        // and it reads back as a topic
        serde_json::from_value::<crate::dto::Topic>(got).unwrap();

        let sc = shape_scenario(
            &json!({"title": "S", "difficulty": 2, "options": ["a", " ", "c", "d"], "correctIndex": 2,
                    "clues": [{"label": "L", "detail": "D"}, {"detail": "no label"}], "problem": "P", "skills": ["k"]}),
            "studio-1",
        );
        assert_eq!(mask(&sc), mask(&f["shaped_scenario"]));
        serde_json::from_value::<crate::dto::Scenario>(sc).unwrap();
    }

    #[test]
    fn odd_values_become_text_not_a_lost_lesson() {
        let t = shape_topic(&json!({"title": 7, "examples": "one", "quizQuestions": [{"type": "trueFalse", "answer": true}]}), "s", vec![]);
        assert_eq!(t["title"], "7");
        assert_eq!(t["examples"], json!([]));
        assert_eq!(t["quizQuestions"][0]["answer"], "True");
        serde_json::from_value::<crate::dto::Topic>(t).unwrap();
    }

    #[test]
    fn connections_like_python() {
        let titles: Vec<String> = ["A", "B", "C"].map(String::from).to_vec();
        let got = clean_connections(
            Some(json!({"A": {"buildsOn": ["B"], "relatesTo": ["B", "C", "A", "X"]}, "B": {"buildsOn": ["A", "A"], "relatesTo": ["A", "C"]},
                        "C": {"buildsOn": ["A", "B", "C"]}, "Z": {}})),
            &titles,
        );
        let want = fixture()["connections"].clone();
        for t in &titles {
            let (b, r) = &got[t];
            assert_eq!(json!(b), want[t]["buildsOn"], "{t}");
            assert_eq!(json!(r), want[t]["relatesTo"], "{t}");
        }
    }

    #[test]
    fn ids_carry_like_python() {
        let f = fixture();
        let keep = keep_map(&[
            json!({"id": "gen_1", "title": "  TCP  Basics ", "flashcards": [{"id": "fc_1", "front": "What is TCP?"}, {"id": "fc_2", "front": ""}]}),
            json!({"id": "gen_2", "title": "tcp basics"}),
        ]);
        assert_eq!(keep.len(), 1);
        assert_eq!(keep["tcp basics"].0, "gen_1");
        assert_eq!(json!(keep["tcp basics"].1), f["keep"]["tcp basics"]["cards"]);
        let carried = carry_ids(
            json!({"id": "gen_new", "title": "TCP basics", "flashcards": [{"id": "fc_n", "front": "what is  tcp?", "topicId": "gen_new"},
                   {"id": "fc_m", "front": "Other"}], "quizQuestions": [{"id": "q_1", "topicId": "gen_new"}]}),
            &keep,
        );
        assert_eq!(carried, f["carried"]);
    }

    #[test]
    fn outline_keeps_only_real_links() {
        let o = outline(
            r#"```json
[{"title":"A","scope":"a","buildsOn":["B"],"relatesTo":["B","B","Q"]},
 {"title":"B","buildsOn":["A","A","Z"],"relatesTo":["A","C"]},
 {"scope":"no title"},
 {"title":"C","buildsOn":["A","B","A"],"relatesTo":["A","B","C"]}]
```"#,
        );
        assert_eq!(o.iter().map(|l| l.title.as_str()).collect::<Vec<_>>(), ["A", "B", "C"]);
        assert_eq!(o[0].builds_on, Vec::<String>::new());
        assert_eq!(o[0].relates_to, ["B"]);
        assert_eq!(o[1].builds_on, ["A", "A"]); // Python keeps repeats here too
        assert_eq!(o[1].relates_to, ["C"]);
        assert_eq!(o[2].builds_on, ["A", "B"]);
        assert_eq!(o[2].relates_to, Vec::<String>::new());
        assert_eq!(outline(r#"{"lessons":[{"title":"X"}]}"#).len(), 1);
        assert!(outline("sorry").is_empty());
    }

    #[test]
    fn material_stops_at_the_budget() {
        let c = vec!["aaaa".to_string(), "bbbb".into(), "cc".into()];
        assert_eq!(material(&c, 9), "aaaa\n\nbbbb");
        assert_eq!(material(&c, 3), "");
    }
}

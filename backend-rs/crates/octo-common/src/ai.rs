//! App-wide AI settings, read from the shared octopilot DB: the models users
//! choose from (each a bundle of real models behind one name, "Octo v2
//! Pro"), the personalities, each user's choice per app, and the OctoCredit
//! price table. Admins write these tables directly; services read them
//! through a one-minute cache. The tables are in `shared-sql/`.
//!
//! Everything here degrades quietly: no tables, no rows or a failed query
//! means "no choice", and the caller keeps its own defaults.

use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use uuid::Uuid;

/// How long the catalog and the price table are kept before re-reading.
const CACHE_FOR: Duration = Duration::from_secs(60);

/// The scopes a user can set a choice for. `global` covers every app.
pub const SCOPES: [&str; 3] = ["global", "ghostwriter", "study_studio"];

/// One model as users see it, and the real models behind it.
#[derive(Clone, Debug, sqlx::FromRow)]
pub struct Model {
    pub id: String,
    pub display_name: String,
    pub tagline: String,
    /// Drives the work: picks tools, talks to the user.
    pub orchestrator_model: String,
    /// Writes and revises the essay.
    pub writer_model: String,
    /// Quick work: summaries, checks, quick replies.
    pub fast_model: String,
    /// `free` or `pro`.
    pub min_plan: String,
    pub credit_multiplier: f64,
    pub is_default: bool,
}

impl Model {
    pub fn pro_only(&self) -> bool {
        self.min_plan == "pro"
    }
}

#[derive(Clone, Debug, sqlx::FromRow)]
pub struct Personality {
    pub id: String,
    pub display_name: String,
    pub description: String,
    /// How it talks. Chat only: never the essay.
    pub prompt: String,
    pub is_default: bool,
}

#[derive(Clone, Debug, Default)]
pub struct Catalog {
    pub models: Vec<Model>,
    pub personalities: Vec<Personality>,
}

/// The OctoCredit price table (Finance-approved defaults).
#[derive(Clone, Copy, Debug, PartialEq, sqlx::FromRow)]
pub struct Pricing {
    pub gen_words_per_dollar: f64,
    pub hum_words_per_dollar: f64,
    pub sources_per_dollar: f64,
    pub oc_per_dollar: f64,
    pub min_charge: i32,
    pub round_to: i32,
}

impl Default for Pricing {
    fn default() -> Self {
        Self {
            gen_words_per_dollar: 30_000.0,
            hum_words_per_dollar: 3_000.0,
            sources_per_dollar: 50.0,
            oc_per_dollar: 100.0,
            min_charge: 100,
            round_to: 100,
        }
    }
}

impl Pricing {
    /// What one operation costs: its estimated API cost in OctoCredits times
    /// `multiplier`, rounded up to the next `round_to`, never below
    /// `min_charge`.
    pub fn charge(
        &self,
        words_generated: i64,
        words_humanized: i64,
        sources: i64,
        multiplier: f64,
    ) -> i32 {
        let per = |n: i64, per_dollar: f64| {
            if per_dollar > 0.0 {
                n.max(0) as f64 / per_dollar
            } else {
                0.0
            }
        };
        let cost_usd = per(words_generated, self.gen_words_per_dollar)
            + per(words_humanized, self.hum_words_per_dollar)
            + per(sources, self.sources_per_dollar);
        let round_to = f64::from(self.round_to.max(1));
        let credits =
            (cost_usd * self.oc_per_dollar * multiplier.max(0.0) / round_to).ceil() * round_to;
        (credits as i32).max(self.min_charge)
    }
}

/// What a user runs with in one app.
#[derive(Clone, Debug, Default)]
pub struct Choice {
    pub model: Option<Model>,
    pub personality: Option<Personality>,
    /// The user is on a Pro plan.
    pub pro: bool,
}

/// A user's saved choice for one scope. `None` = follow the wider scope.
#[derive(Clone, Debug, Default, Serialize, Deserialize, sqlx::FromRow)]
pub struct Preference {
    pub scope: String,
    pub model_id: Option<String>,
    pub personality_id: Option<String>,
}

#[derive(Default)]
struct Cache {
    catalog: Option<(Instant, Catalog)>,
    pricing: Option<(Instant, Pricing)>,
}

/// The shared AI settings, cached per process.
#[derive(Clone, Default)]
pub struct AiSettings {
    cache: Arc<Mutex<Cache>>,
}

impl AiSettings {
    /// Enabled models and personalities, in their admin order.
    pub async fn catalog(&self, pool: &PgPool) -> Catalog {
        if let Some((at, catalog)) = &self.cache.lock().unwrap().catalog {
            if at.elapsed() < CACHE_FOR {
                return catalog.clone();
            }
        }
        let models = sqlx::query_as::<_, Model>(
            "SELECT id, display_name, tagline, orchestrator_model, writer_model, fast_model, \
                    min_plan, credit_multiplier::float8 AS credit_multiplier, is_default \
             FROM ai_models WHERE enabled ORDER BY sort, display_name",
        )
        .fetch_all(pool)
        .await;
        let personalities = sqlx::query_as::<_, Personality>(
            "SELECT id, display_name, description, prompt, is_default \
             FROM ai_personalities WHERE enabled ORDER BY sort, display_name",
        )
        .fetch_all(pool)
        .await;
        let catalog = match (models, personalities) {
            (Ok(models), Ok(personalities)) => Catalog {
                models,
                personalities,
            },
            (Err(error), _) | (_, Err(error)) => {
                tracing::warn!(%error, "ai settings: catalog not readable");
                Catalog::default()
            }
        };
        self.cache.lock().unwrap().catalog = Some((Instant::now(), catalog.clone()));
        catalog
    }

    /// The price table, or the defaults when there is none.
    pub async fn pricing(&self, pool: &PgPool) -> Pricing {
        if let Some((at, pricing)) = &self.cache.lock().unwrap().pricing {
            if at.elapsed() < CACHE_FOR {
                return *pricing;
            }
        }
        let pricing = sqlx::query_as::<_, Pricing>(
            "SELECT gen_words_per_dollar::float8 AS gen_words_per_dollar, \
                    hum_words_per_dollar::float8 AS hum_words_per_dollar, \
                    sources_per_dollar::float8 AS sources_per_dollar, \
                    oc_per_dollar::float8 AS oc_per_dollar, min_charge, round_to \
             FROM pricing_config LIMIT 1",
        )
        .fetch_optional(pool)
        .await
        .unwrap_or_else(|error| {
            tracing::warn!(%error, "ai settings: price table not readable");
            None
        })
        .unwrap_or_default();
        self.cache.lock().unwrap().pricing = Some((Instant::now(), pricing));
        pricing
    }

    /// Drops the cache, so the next read sees the tables as they are now.
    pub fn refresh(&self) {
        *self.cache.lock().unwrap() = Cache::default();
    }

    /// What `user_id` runs with in `app`: their choice for the app, else
    /// their global choice, else the admin default. A model the user may not
    /// use (Pro only, or turned off) falls back the same way.
    pub async fn choice(&self, pool: &PgPool, user_id: Uuid, app: &str) -> Choice {
        let catalog = self.catalog(pool).await;
        let pro = is_pro(pool, user_id).await;
        let prefs = preferences(pool, user_id).await;
        let pref = |scope: &str| prefs.iter().find(|p| p.scope == scope);
        let wanted = [pref(app), pref("global")];

        let usable = |m: &&Model| pro || !m.pro_only();
        let model = wanted
            .iter()
            .flatten()
            .filter_map(|p| p.model_id.as_deref())
            .find_map(|id| catalog.models.iter().filter(usable).find(|m| m.id == id))
            .or_else(|| catalog.models.iter().filter(usable).find(|m| m.is_default))
            .or_else(|| catalog.models.iter().find(usable))
            .cloned();
        let personality = wanted
            .iter()
            .flatten()
            .filter_map(|p| p.personality_id.as_deref())
            .find_map(|id| catalog.personalities.iter().find(|p| p.id == id))
            .or_else(|| catalog.personalities.iter().find(|p| p.is_default))
            .cloned();
        Choice {
            model,
            personality,
            pro,
        }
    }
}

/// True when the user is on a Pro plan.
pub async fn is_pro(pool: &PgPool, user_id: Uuid) -> bool {
    sqlx::query_scalar::<_, Option<String>>("SELECT plan FROM users WHERE id = $1")
        .bind(user_id)
        .fetch_optional(pool)
        .await
        .ok()
        .flatten()
        .flatten()
        .is_some_and(|plan| plan.to_lowercase().contains("pro"))
}

/// The user's saved choices, one per scope they set.
pub async fn preferences(pool: &PgPool, user_id: Uuid) -> Vec<Preference> {
    sqlx::query_as::<_, Preference>(
        "SELECT scope, model_id, personality_id FROM user_ai_preferences WHERE user_id = $1",
    )
    .bind(user_id)
    .fetch_all(pool)
    .await
    .unwrap_or_default()
}

/// Saves a user's choice for `scope`. `None` leaves a field as it is;
/// `Some(None)` clears it (follow the wider scope).
pub async fn set_preference(
    pool: &PgPool,
    user_id: Uuid,
    scope: &str,
    model_id: Option<Option<&str>>,
    personality_id: Option<Option<&str>>,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO user_ai_preferences (user_id, scope, model_id, personality_id) \
         VALUES ($1, $2, $4, $6) \
         ON CONFLICT (user_id, scope) DO UPDATE SET \
             model_id = CASE WHEN $3 THEN EXCLUDED.model_id ELSE user_ai_preferences.model_id END, \
             personality_id = CASE WHEN $5 THEN EXCLUDED.personality_id \
                 ELSE user_ai_preferences.personality_id END, \
             updated_at = now()",
    )
    .bind(user_id)
    .bind(scope)
    .bind(model_id.is_some())
    .bind(model_id.flatten())
    .bind(personality_id.is_some())
    .bind(personality_id.flatten())
    .execute(pool)
    .await?;
    Ok(())
}

/// Names that would give away the model or the company behind it. Admins
/// can replace the list (`system_settings.ai_masked_terms`, comma-separated).
/// Matched as whole words, case-sensitive, so "meta-analysis" or a "claude"
/// in a quote's lower case is left alone.
pub const MASKED_TERMS: [&str; 18] = [
    "ChatGPT",
    "GPT-5",
    "GPT-4o",
    "GPT-4",
    "GPT-3.5",
    "GPT",
    "OpenAI",
    "Claude",
    "Anthropic",
    "Gemini",
    "Llama",
    "LLaMA",
    "Mistral",
    "Mixtral",
    "DeepSeek",
    "Qwen",
    "Grok",
    "OpenRouter",
];

/// The masked terms in force: the admin's list, or [`MASKED_TERMS`].
pub async fn masked_terms(pool: Option<&PgPool>) -> Vec<String> {
    if let Some(pool) = pool {
        if let Some(list) = crate::llm::setting(pool, "ai_masked_terms").await {
            let terms: Vec<String> = list
                .split(',')
                .map(str::trim)
                .filter(|t| !t.is_empty())
                .map(str::to_string)
                .collect();
            if !terms.is_empty() {
                return terms;
            }
        }
    }
    MASKED_TERMS.iter().map(|t| t.to_string()).collect()
}

/// Replaces every whole-word `terms` in `text` with `name`. Longer terms are
/// tried first, so "GPT-4o" goes as one. Returns whether anything changed.
pub fn mask(text: &str, terms: &[String], name: &str) -> (String, bool) {
    let mut terms: Vec<&str> = terms.iter().map(String::as_str).collect();
    terms.sort_by_key(|t| std::cmp::Reverse(t.len()));
    let word = |c: Option<char>| c.is_some_and(|c| c.is_alphanumeric() || c == '_');

    let mut out = String::with_capacity(text.len());
    let mut changed = false;
    let mut rest = text;
    let mut before: Option<char> = None;
    'scan: while !rest.is_empty() {
        if !word(before) {
            for term in &terms {
                if let Some(after) = rest.strip_prefix(term) {
                    // "GPT-4" must not eat the start of "GPT-4.1".
                    let next = after.chars().next();
                    if !word(next)
                        && next != Some('-')
                        && !(next == Some('.')
                            && after[1..].starts_with(|c: char| c.is_ascii_digit()))
                    {
                        out.push_str(name);
                        changed = true;
                        before = name.chars().last();
                        rest = after;
                        continue 'scan;
                    }
                }
            }
        }
        let c = rest.chars().next().unwrap();
        out.push(c);
        before = Some(c);
        rest = &rest[c.len_utf8()..];
    }
    (out, changed)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn terms() -> Vec<String> {
        MASKED_TERMS.iter().map(|t| t.to_string()).collect()
    }

    #[test]
    fn masks_whole_names_only() {
        let (out, changed) = mask("I am Claude, made by Anthropic.", &terms(), "Octo v2");
        assert_eq!(out, "I am Octo v2, made by Octo v2.");
        assert!(changed);
        let (out, _) = mask("Running on GPT-4o and OpenRouter", &terms(), "Octo");
        assert_eq!(out, "Running on Octo and Octo");
        // Not whole words, or not the brand's spelling: left alone.
        let text = "A meta-analysis of claude-like tides; Claudette; GPTs";
        assert_eq!(mask(text, &terms(), "Octo"), (text.to_string(), false));
    }

    #[test]
    fn prices_like_the_python_table() {
        let p = Pricing::default();
        assert_eq!(p.charge(800, 0, 0, 1.0), 100);
        assert_eq!(p.charge(30_001, 0, 0, 1.0), 200);
        assert_eq!(p.charge(0, 6_500, 0, 1.0), 300);
        assert_eq!(p.charge(0, 0, 51, 1.0), 200);
        // A dearer model costs more once past the minimum.
        assert_eq!(p.charge(30_000, 0, 0, 2.0), 200);
        assert_eq!(p.charge(800, 0, 0, 2.0), 100);
        let cheaper = Pricing {
            min_charge: 50,
            round_to: 10,
            ..p
        };
        assert_eq!(cheaper.charge(800, 0, 0, 1.0), 50);
    }
}

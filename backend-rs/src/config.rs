/// Runtime configuration, all from the environment so nothing secret is baked
/// into the binary.
#[derive(Clone)]
pub struct Config {
    /// Firebase project whose ID tokens we accept (same one octopilot uses).
    /// Empty ⇒ auth disabled (dev): the `X-User-Id` header is trusted instead.
    pub firebase_project_id: String,
    /// undetectable.ai key for the paraphraser; when absent the endpoint is a
    /// no-op passthrough so the rest of the API still runs locally.
    pub humanizer_api_key: Option<String>,
    /// OpenRouter key for source search / outline; absent ⇒ those endpoints 503.
    pub openrouter_api_key: Option<String>,
    pub openrouter_model: String,
    /// Upstream page scraper (the octopilot backend).
    pub upstream_scraper: String,
    /// Shared Postgres (keys, models, users/credits, essays live here).
    pub database_url: String,
    pub port: u16,
}

impl Config {
    pub fn from_env() -> Self {
        Self {
            firebase_project_id: std::env::var("FIREBASE_PROJECT_ID")
                .unwrap_or_else(|_| "octopilot-ai-7b29e".to_string()),
            humanizer_api_key: env_opt("HUMANIZER_API_KEY"),
            openrouter_api_key: env_opt("OPENROUTER_API_KEY"),
            openrouter_model: std::env::var("OPENROUTER_MODEL")
                .unwrap_or_else(|_| "openai/gpt-4o-mini".to_string()),
            upstream_scraper: std::env::var("UPSTREAM_SCRAPER")
                .unwrap_or_else(|_| "https://api.octopilotai.com/api/scrape".to_string()),
            database_url: std::env::var("DATABASE_URL").unwrap_or_else(|_| {
                "postgres://octopilot:OctoPilot2025@localhost:5432/octopilot".to_string()
            }),
            port: std::env::var("PORT")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(8787),
        }
    }
}

fn env_opt(key: &str) -> Option<String> {
    std::env::var(key).ok().filter(|s| !s.is_empty())
}

/// Runtime configuration, all from the environment so nothing secret is baked
/// into the binary. OpenRouter keys and models are deliberately NOT here — they
/// come from the shared DB (`api_keys` / `system_settings`).
#[derive(Clone, Debug)]
pub struct Config {
    /// The `ghostwriter` database — owned by this service (migrations run at
    /// startup).
    pub ghostwriter_database_url: String,
    /// Shared octopilot DB (users, OctoCredits, keys, models). Absent ⇒
    /// header-derived dev identities and no credits.
    pub octopilot_database_url: Option<String>,
    /// Firebase project whose ID tokens we accept. Empty ⇒ auth disabled
    /// (local dev): the `X-User-Id` header is trusted instead.
    pub firebase_project_id: String,
    /// Exact browser origins allowed by CORS (comma-separated `CORS_ORIGINS`).
    pub cors_origins: Vec<String>,
    /// Also allow any `http://localhost:*` / `http://127.0.0.1:*` origin
    /// (Flutter web dev server). Turn off in production.
    pub cors_allow_localhost: bool,
    pub port: u16,
    /// Listen address: `127.0.0.1` in production (nginx in front), `0.0.0.0` in dev.
    pub bind: String,
    /// Ledger `credit_type` used for OctoCredit charges.
    pub credits_ledger_type: String,
    /// Disable charging (dev without the shared DB).
    pub credits_enabled: bool,
    /// `json` for structured logs (production), anything else for text.
    pub log_format: String,
}

impl Config {
    pub fn from_env() -> Self {
        Self {
            ghostwriter_database_url: std::env::var("GHOSTWRITER_DATABASE_URL").unwrap_or_else(
                |_| "postgres://postgres:postgres@127.0.0.1:5432/ghostwriter".to_string(),
            ),
            octopilot_database_url: env_opt("OCTOPILOT_DATABASE_URL"),
            firebase_project_id: std::env::var("FIREBASE_PROJECT_ID")
                .unwrap_or_else(|_| "octopilot-ai-7b29e".to_string()),
            cors_origins: list("CORS_ORIGINS"),
            cors_allow_localhost: flag("CORS_ALLOW_LOCALHOST", true),
            port: std::env::var("PORT")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(8791),
            bind: std::env::var("BIND").unwrap_or_else(|_| "0.0.0.0".into()),
            credits_ledger_type: std::env::var("CREDITS_LEDGER_TYPE")
                .unwrap_or_else(|_| "octo".into()),
            credits_enabled: flag("CREDITS_ENABLED", true),
            log_format: std::env::var("LOG_FORMAT").unwrap_or_else(|_| "text".into()),
        }
    }
}

fn env_opt(key: &str) -> Option<String> {
    std::env::var(key).ok().filter(|s| !s.trim().is_empty())
}

fn flag(key: &str, default: bool) -> bool {
    std::env::var(key)
        .map(|v| !matches!(v.trim(), "false" | "0" | "no"))
        .unwrap_or(default)
}

fn list(key: &str) -> Vec<String> {
    std::env::var(key)
        .unwrap_or_default()
        .split(',')
        .map(|s| s.trim().trim_end_matches('/').to_string())
        .filter(|s| !s.is_empty())
        .collect()
}

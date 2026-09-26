/// Runtime configuration, all from the environment so nothing secret is baked
/// into the binary. OpenRouter keys and models are deliberately NOT here — they
/// come from the shared DB (`api_keys` / `system_settings`), as in octopilot-rs.
#[derive(Clone, Debug)]
pub struct Config {
    /// `notes_db` — owned by this service (migrations run at startup).
    pub notes_database_url: String,
    /// Shared octopilot DB (users, OctoCredits). Absent ⇒ `/v1/me` returns the
    /// token identity only.
    pub octopilot_database_url: Option<String>,
    /// Study Studio business DB, read-only. Not used until Phase 1.
    pub studio_database_url: Option<String>,
    /// Firebase project whose ID tokens we accept. Empty ⇒ auth disabled
    /// (local dev): the `X-User-Id` header is trusted instead.
    pub firebase_project_id: String,
    /// Exact browser origins allowed by CORS (comma-separated `CORS_ORIGINS`).
    pub cors_origins: Vec<String>,
    /// Also allow any `http://localhost:*` / `http://127.0.0.1:*` origin
    /// (Flutter web dev server). Turn off in production.
    pub cors_allow_localhost: bool,
    pub port: u16,
}

impl Config {
    pub fn from_env() -> Self {
        Self {
            notes_database_url: std::env::var("NOTES_DATABASE_URL").unwrap_or_else(|_| {
                "postgres://postgres:postgres@127.0.0.1:5432/octonotes".to_string()
            }),
            octopilot_database_url: env_opt("OCTOPILOT_DATABASE_URL"),
            studio_database_url: env_opt("STUDIO_DATABASE_URL"),
            firebase_project_id: std::env::var("FIREBASE_PROJECT_ID")
                .unwrap_or_else(|_| "octopilot-ai-7b29e".to_string()),
            cors_origins: std::env::var("CORS_ORIGINS")
                .unwrap_or_default()
                .split(',')
                .map(|s| s.trim().trim_end_matches('/').to_string())
                .filter(|s| !s.is_empty())
                .collect(),
            cors_allow_localhost: std::env::var("CORS_ALLOW_LOCALHOST")
                .map(|v| v != "false" && v != "0")
                .unwrap_or(true),
            port: std::env::var("PORT")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(8790),
        }
    }
}

fn env_opt(key: &str) -> Option<String> {
    std::env::var(key).ok().filter(|s| !s.trim().is_empty())
}

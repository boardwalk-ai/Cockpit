//! Settings from the environment (same names as the Python service where
//! they overlap, so one `.env` serves both during the cutover).

#[derive(Clone, Debug)]
pub struct Config {
    pub bind: String,
    pub port: u16,
    /// Studios, topics, progress, schedules, events.
    pub cockpit_database_url: String,
    /// RAG chunks (pgvector).
    pub vector_database_url: String,
    /// The octopilot DB: users, OctoCredits, API keys, settings. Optional in dev.
    pub shared_database_url: Option<String>,
    pub firebase_project_id: String,
    pub embed_service_url: String,
    pub log_format: String,
}

fn var(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|v| !v.trim().is_empty())
}

impl Config {
    pub fn from_env() -> Self {
        Self {
            bind: var("BIND").unwrap_or_else(|| "127.0.0.1".into()),
            port: var("PORT").and_then(|p| p.parse().ok()).unwrap_or(8110),
            cockpit_database_url: var("COCKPIT_DATABASE_URL")
                .unwrap_or_else(|| "postgres://localhost/cockpit".into()),
            vector_database_url: var("VECTOR_DATABASE_URL")
                .unwrap_or_else(|| "postgres://localhost/vector".into()),
            shared_database_url: var("SHARED_DATABASE_URL"),
            firebase_project_id: var("FIREBASE_PROJECT_ID").unwrap_or_default(),
            embed_service_url: var("EMBED_SERVICE_URL").unwrap_or_default(),
            log_format: var("LOG_FORMAT").unwrap_or_else(|| "text".into()),
        }
    }
}

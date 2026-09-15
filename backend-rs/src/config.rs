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
    pub port: u16,
}

impl Config {
    pub fn from_env() -> Self {
        Self {
            firebase_project_id: std::env::var("FIREBASE_PROJECT_ID")
                .unwrap_or_else(|_| "octopilot-ai-7b29e".to_string()),
            humanizer_api_key: std::env::var("HUMANIZER_API_KEY")
                .ok()
                .filter(|s| !s.is_empty()),
            port: std::env::var("PORT")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(8787),
        }
    }
}

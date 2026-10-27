/// Runtime configuration, all from the environment so nothing secret is baked
/// into the binary. OpenRouter keys and models are deliberately NOT here — they
/// come from the shared DB (`api_keys` / `system_settings`), as in octopilot-rs.
#[derive(Clone, Debug)]
pub struct Config {
    /// `notes_db` — owned by this service (migrations run at startup).
    pub notes_database_url: String,
    /// Shared octopilot DB (users, OctoCredits, keys, models). Absent ⇒
    /// token-derived dev identities and no credits.
    pub octopilot_database_url: Option<String>,
    /// Study Studio business DB, read-only.
    pub studio_database_url: Option<String>,
    /// Study Studio RAG vector DB, read-only.
    pub studio_vector_database_url: Option<String>,
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
    /// `api`, `worker` or `all` (default): which loops this process runs.
    pub role: String,
    pub workers: usize,
    /// Base URL clients reach this API at (signed local blob links).
    pub public_base_url: String,
    /// Local blob folder when S3 isn't configured.
    pub storage_dir: String,
    pub storage_signing_key: String,
    pub s3_endpoint: Option<String>,
    pub s3_bucket: String,
    pub s3_access_key: String,
    pub s3_secret_key: String,
    pub s3_region: String,
    pub redis_url: Option<String>,
    /// BGE-m3 embed service (`POST /embed`); absent ⇒ deterministic offline embedder.
    pub embed_url: Option<String>,
    /// Study Studio API (FastAPI today) for conversions.
    pub study_studio_api_url: Option<String>,
    pub study_studio_service_key: Option<String>,
    /// Keys for service-to-service calls into this API (The Deck), comma-separated.
    pub service_keys: Vec<String>,
    /// Ledger `credit_type` used for OctoCredit charges.
    pub credits_ledger_type: String,
    /// Disable charging (dev without the shared DB).
    pub credits_enabled: bool,
    /// Transcribe recordings on the server (OpenRouter). Off: the recording
    /// phone's on-device captions are the transcript.
    pub server_asr: bool,
    /// The handwritten-formula reader (deploy/formula), loopback.
    pub formula_url: String,
    /// Bearer token for `/metrics` from outside loopback.
    pub metrics_token: Option<String>,
    /// `json` for structured logs (production), anything else for text.
    pub log_format: String,
}

impl Config {
    pub fn from_env() -> Self {
        let port = std::env::var("PORT")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(8790);
        Self {
            notes_database_url: std::env::var("NOTES_DATABASE_URL").unwrap_or_else(|_| {
                "postgres://postgres:postgres@127.0.0.1:5432/octonotes".to_string()
            }),
            octopilot_database_url: env_opt("OCTOPILOT_DATABASE_URL"),
            studio_database_url: env_opt("STUDIO_DATABASE_URL"),
            studio_vector_database_url: env_opt("STUDIO_VECTOR_DATABASE_URL"),
            firebase_project_id: std::env::var("FIREBASE_PROJECT_ID")
                .unwrap_or_else(|_| "octopilot-ai-7b29e".to_string()),
            cors_origins: list("CORS_ORIGINS"),
            cors_allow_localhost: flag("CORS_ALLOW_LOCALHOST", true),
            port,
            bind: std::env::var("BIND").unwrap_or_else(|_| "0.0.0.0".into()),
            role: std::env::var("ROLE").unwrap_or_else(|_| "all".into()),
            workers: std::env::var("WORKERS")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(4),
            public_base_url: std::env::var("PUBLIC_BASE_URL")
                .unwrap_or_else(|_| format!("http://127.0.0.1:{port}")),
            storage_dir: std::env::var("STORAGE_DIR").unwrap_or_else(|_| "./data/blobs".into()),
            storage_signing_key: std::env::var("STORAGE_SIGNING_KEY")
                .unwrap_or_else(|_| uuid::Uuid::new_v4().to_string()),
            s3_endpoint: env_opt("S3_ENDPOINT"),
            s3_bucket: std::env::var("S3_BUCKET").unwrap_or_else(|_| "octonotes".into()),
            s3_access_key: std::env::var("S3_ACCESS_KEY").unwrap_or_default(),
            s3_secret_key: std::env::var("S3_SECRET_KEY").unwrap_or_default(),
            s3_region: std::env::var("S3_REGION").unwrap_or_else(|_| "us-east-1".into()),
            redis_url: env_opt("REDIS_URL"),
            embed_url: env_opt("EMBED_URL"),
            study_studio_api_url: env_opt("STUDY_STUDIO_API_URL"),
            study_studio_service_key: env_opt("STUDY_STUDIO_SERVICE_KEY"),
            service_keys: list("SERVICE_KEYS"),
            credits_ledger_type: std::env::var("CREDITS_LEDGER_TYPE")
                .unwrap_or_else(|_| "octo".into()),
            credits_enabled: flag("CREDITS_ENABLED", true),
            server_asr: flag("SERVER_ASR", false),
            formula_url: std::env::var("FORMULA_URL").unwrap_or_else(|_| "http://127.0.0.1:8096".into()),
            metrics_token: env_opt("METRICS_TOKEN"),
            log_format: std::env::var("LOG_FORMAT").unwrap_or_else(|_| "text".into()),
        }
    }

    pub fn runs_api(&self) -> bool {
        self.role != "worker"
    }

    pub fn runs_worker(&self) -> bool {
        self.role != "api"
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

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
    /// MinIO / S3 for uploaded files.
    pub object_store_endpoint: String,
    pub object_store_region: String,
    pub object_store_bucket: String,
    pub object_store_access_key: String,
    pub object_store_secret_key: String,
    /// Hirara: OCR and office-document extraction.
    pub hirara_hub_url: String,
    pub hirara_hub_token: String,
    /// Run the ingest worker in this process (off while Go still ingests).
    pub ingest_worker: bool,
    pub ingest_workers: usize,
    pub max_upload_mb: usize,
    /// Run studio builds in this process (off while Python still builds).
    pub build_worker: bool,
    pub build_workers: usize,
    /// Create/alter this service's tables at startup (chunks.page/heading,
    /// llm_usage). On at the cutover; off while only shadowing.
    pub migrate: bool,
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
            object_store_endpoint: var("OBJECT_STORE_ENDPOINT")
                .unwrap_or_else(|| "http://127.0.0.1:9000".into()),
            object_store_region: var("OBJECT_STORE_REGION").unwrap_or_else(|| "us-east-1".into()),
            object_store_bucket: var("OBJECT_STORE_BUCKET").unwrap_or_else(|| "cockpit-rag".into()),
            object_store_access_key: var("OBJECT_STORE_ACCESS_KEY").unwrap_or_default(),
            object_store_secret_key: var("OBJECT_STORE_SECRET_KEY").unwrap_or_default(),
            hirara_hub_url: var("HIRARA_HUB_URL").unwrap_or_else(|| "http://127.0.0.1:8080".into()),
            hirara_hub_token: var("HIRARA_HUB_TOKEN").unwrap_or_default(),
            ingest_worker: var("INGEST_WORKER").is_some_and(|v| v == "1" || v == "true"),
            ingest_workers: var("INGEST_WORKERS").and_then(|v| v.parse().ok()).unwrap_or(2),
            build_worker: var("BUILD_WORKER").is_some_and(|v| v == "1" || v == "true"),
            build_workers: var("BUILD_WORKERS").and_then(|v| v.parse().ok()).unwrap_or(2),
            max_upload_mb: var("MAX_UPLOAD_MB").and_then(|v| v.parse().ok()).unwrap_or(50),
            migrate: var("MIGRATE").is_some_and(|v| v == "1" || v == "true"),
        }
    }
}

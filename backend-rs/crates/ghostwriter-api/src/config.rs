use std::time::Duration;

use crate::runs::driver::DEFAULT_PARK_AFTER;

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
    /// How long a run waits in memory for an answer before it is parked
    /// (let go until the answer comes).
    pub park_after: Duration,
    /// Runs one worker drives at once.
    pub worker_slots: usize,
    /// How often the worker looks for queued runs (it is also woken).
    pub worker_poll: Duration,
    /// How long a worker's claim on a run lasts without renewal.
    pub run_lease: Duration,
    /// Pause between steps of the scripted driver, so a person can follow it.
    pub scripted_step: Duration,
    /// Whether the scripted driver offers to humanize the essay at the end.
    pub scripted_humanizer: bool,
    /// `agent` (the model drives the run) or `scripted` (canned run, no model).
    pub driver: String,
    /// The Octopilot scraper service (`GET <url>?url=…`).
    pub scraper_url: String,
    /// The Firebase service-account key file used to send push
    /// notifications. Unset = no push.
    pub fcm_service_account_file: Option<String>,
    /// How often deleted accounts' data is swept.
    pub sweep_every: Duration,
    /// Staging only: verified emails that get an account on first sign-in
    /// (lowercase). Empty in production.
    pub account_allowlist: Vec<String>,
    /// The OctoCredits such an account starts with.
    pub starting_credits: i32,
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
            park_after: millis("PARK_AFTER_MS").unwrap_or(DEFAULT_PARK_AFTER),
            worker_slots: std::env::var("WORKER_SLOTS")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(32),
            worker_poll: millis("WORKER_POLL_MS").unwrap_or(Duration::from_secs(1)),
            run_lease: millis("RUN_LEASE_MS").unwrap_or(Duration::from_secs(30)),
            scripted_step: millis("SCRIPTED_STEP_MS").unwrap_or(Duration::from_millis(900)),
            scripted_humanizer: flag("SCRIPTED_HUMANIZER", true),
            driver: std::env::var("GHOSTWRITER_DRIVER").unwrap_or_else(|_| "agent".into()),
            scraper_url: std::env::var("SCRAPER_URL")
                .unwrap_or_else(|_| "https://api.octopilotai.com/api/scrape".into()),
            fcm_service_account_file: env_opt("FCM_SERVICE_ACCOUNT_FILE"),
            sweep_every: millis("SWEEP_EVERY_MS").unwrap_or(Duration::from_secs(600)),
            account_allowlist: list("ACCOUNT_ALLOWLIST")
                .into_iter()
                .map(|e| e.to_lowercase())
                .collect(),
            starting_credits: std::env::var("STARTING_CREDITS")
                .ok()
                .and_then(|s| s.trim().parse().ok())
                .unwrap_or(0),
        }
    }
}

fn millis(key: &str) -> Option<Duration> {
    std::env::var(key)
        .ok()
        .and_then(|s| s.trim().parse().ok())
        .map(Duration::from_millis)
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

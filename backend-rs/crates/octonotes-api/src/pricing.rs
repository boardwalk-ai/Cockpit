//! OctoCredit prices for OctoNotes actions. PROPOSAL — Finance has not
//! confirmed pricing. Each price can be changed without a deploy through
//! `system_settings` key `octonotes_price_<action>` (100 OC = $1).

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use axum::extract::State;
use axum::Json;
use octo_common::ApiError;
use serde::Serialize;
use serde_json::json;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::jobs::{Job, JobResult};
use crate::realtime::Event;
use crate::AppState;

/// (action, default OC, unit) — the proposal table from the backend report.
pub const DEFAULTS: &[(&str, i32, &str)] = &[
    ("asr_hour", 30, "per lecture hour, metered"),
    ("suggest", 2, "per inline AI suggestion"),
    ("command", 5, "per Magic Bar command"),
    ("recognize", 3, "per handwriting recognition"),
    ("summarize", 10, "per summary"),
    ("organize", 10, "per organization preview"),
    ("research_quick", 10, "per quick research"),
    ("research_standard", 20, "per standard research"),
    ("research_deep", 40, "per deep research"),
    ("smart_notes", 20, "per session review"),
    ("conversion_base", 100, "per Study Studio conversion"),
    ("conversion_item", 2, "per generated learning item"),
];

type Prices = (HashMap<String, i32>, Option<Instant>);

#[derive(Clone, Default)]
pub struct PriceCache {
    inner: Arc<Mutex<Prices>>,
}

impl PriceCache {
    /// Forget cached prices (next read goes to `system_settings`).
    pub fn invalidate(&self) {
        *self.inner.lock().expect("price cache") = Prices::default();
    }
}

pub async fn price(st: &AppState, action: &str) -> i32 {
    let default = DEFAULTS.iter().find(|(a, _, _)| *a == action).map(|d| d.1).unwrap_or(0);
    {
        let guard = st.prices.inner.lock().expect("price cache");
        if guard.1.is_some_and(|t| t.elapsed() < Duration::from_secs(60)) {
            return guard.0.get(action).copied().unwrap_or(default);
        }
    }
    let mut map = HashMap::new();
    if let Some(pool) = &st.octopilot {
        let rows: Vec<(String, Option<String>)> = sqlx::query_as("SELECT key, value FROM system_settings WHERE key LIKE 'octonotes_price_%'")
            .fetch_all(pool)
            .await
            .unwrap_or_default();
        for (k, v) in rows {
            if let Some(n) = v.and_then(|v| v.trim().parse::<i32>().ok()).filter(|n| *n >= 0) {
                map.insert(k.trim_start_matches("octonotes_price_").to_string(), n);
            }
        }
    }
    let value = map.get(action).copied().unwrap_or(default);
    *st.prices.inner.lock().expect("price cache") = (map, Some(Instant::now()));
    value
}

#[derive(Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct PriceItem {
    pub action: String,
    pub credits: i32,
    pub unit: String,
}

#[utoipa::path(get, path = "/v1/me/pricing", tag = "account", responses((status = 200, body = Vec<PriceItem>)))]
pub async fn list(State(st): State<AppState>, _caller: crate::ctx::Caller) -> Result<Json<Vec<PriceItem>>, ApiError> {
    let mut out = Vec::new();
    for (action, _, unit) in DEFAULTS {
        out.push(PriceItem { action: action.to_string(), credits: price(&st, action).await, unit: unit.to_string() });
    }
    Ok(Json(out))
}

/// Charges and tells every open app the new balance.
pub async fn charge(st: &AppState, user_id: Uuid, amount: i32, source_ref: &str, reason: &str) -> Result<i32, ApiError> {
    let out = st.credits.charge(user_id, amount, source_ref, reason, json!({ "app": "octonotes" })).await?;
    if out.charged {
        if let Some(b) = out.balance {
            st.hub.user(user_id, Event::new("credits.updated", json!({ "octoCredits": b }), None)).await;
        }
        Ok(amount)
    } else {
        Ok(0)
    }
}

/// Charges metered transcription: 1 hour = `asr_hour` OC. Only whole credits
/// are charged; leftover seconds wait for the next run.
pub async fn job_meter(st: AppState, _job: Job) -> JobResult {
    let per_hour = price(&st, "asr_hour").await.max(0);
    if per_hour == 0 || !st.credits.active() {
        return Ok(());
    }
    let seconds_per_credit = 3600.0 / per_hour as f64;
    let users: Vec<Uuid> = sqlx::query_scalar("SELECT DISTINCT user_id FROM usage_meter WHERE kind = 'asr_seconds' AND charged_at IS NULL")
        .fetch_all(&st.notes)
        .await
        .map_err(|e| e.to_string())?;
    for user in users {
        let rows: Vec<(i64, f64)> = sqlx::query_as(
            "SELECT id, quantity FROM usage_meter WHERE user_id = $1 AND kind = 'asr_seconds' AND charged_at IS NULL ORDER BY id",
        )
        .bind(user)
        .fetch_all(&st.notes)
        .await
        .map_err(|e| e.to_string())?;
        // Whole credits for everything uncharged; leftover seconds carry over
        // as one new uncharged row, so nothing is lost or billed twice.
        let total: f64 = rows.iter().map(|r| r.1).sum();
        let credits = (total / seconds_per_credit).floor() as i32;
        if credits == 0 {
            continue;
        }
        let last_id = rows.last().map(|r| r.0).unwrap_or(0);
        let reference = format!("octonotes:asr:{user}:{last_id}");
        match charge(&st, user, credits, &reference, "OctoNotes live transcription").await {
            Ok(_) => {}
            Err(e) if e.code == Some("insufficient_credits") => {
                // Out of credits: turn live transcription off for their live sessions.
                let _ = sqlx::query("UPDATE sessions SET config = jsonb_set(config, '{liveTranscription}', 'false') WHERE user_id = $1 AND status IN ('live', 'paused')")
                    .bind(user)
                    .execute(&st.notes)
                    .await;
                st.hub.user(user, Event::new("transcription.state", json!({ "on": false, "reason": "insufficient_credits" }), None)).await;
                continue;
            }
            Err(e) => return Err(e.message),
        }
        let remainder = total - credits as f64 * seconds_per_credit;
        let mut tx = st.notes.begin().await.map_err(|e| e.to_string())?;
        sqlx::query("UPDATE usage_meter SET charged_at = now() WHERE id = ANY($1)")
            .bind(rows.iter().map(|r| r.0).collect::<Vec<_>>())
            .execute(&mut *tx)
            .await
            .map_err(|e| e.to_string())?;
        if remainder > 0.001 {
            sqlx::query("INSERT INTO usage_meter (user_id, kind, quantity, ref) VALUES ($1, 'asr_seconds', $2, $3) ON CONFLICT DO NOTHING")
                .bind(user)
                .bind(remainder)
                .bind(format!("carry:{user}:{last_id}"))
                .execute(&mut *tx)
                .await
                .map_err(|e| e.to_string())?;
        }
        tx.commit().await.map_err(|e| e.to_string())?;
    }
    Ok(())
}

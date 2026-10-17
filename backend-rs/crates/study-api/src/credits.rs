//! OctoCredits for AI work (tasklist P4). Prices are set by the admin side
//! in the octopilot DB's `system_settings`, never in code:
//!
//! - `study_price_<feature>` — a fixed price for one `ask`, `concepts`,
//!   `connections` or `build`;
//! - else `study_credits_per_usd` — the real OpenRouter cost × this rate,
//!   rounded up (at least 1 credit).
//!
//! Neither set → that feature is free (as before). A fixed price is paid
//! before the call (see `reserve`) and given back if the call yields
//! nothing; a metered one needs at least 1 credit before and is charged its
//! real cost after. Short → 402 `insufficient_credits` and no AI call. Each
//! charge is taken once per `source_ref` (a retry never charges twice).

use std::sync::Mutex;
use std::time::{Duration, Instant};

use octo_common::credits::Credits;
use serde_json::{json, Value};
use sqlx::{PgPool, Row};
use uuid::Uuid;

use crate::AppState;

const CACHE: Duration = Duration::from_secs(60);

#[derive(Debug, Clone, Default, PartialEq)]
pub struct Prices {
    pub per_usd: Option<f64>,
    /// (feature, credits)
    pub fixed: Vec<(String, i32)>,
}

impl Prices {
    pub fn from_rows(rows: &[(String, String)]) -> Self {
        let mut p = Prices::default();
        for (k, v) in rows {
            let v = v.trim().trim_matches('"');
            if k == "study_credits_per_usd" {
                p.per_usd = v.parse::<f64>().ok().filter(|r| *r > 0.0);
            } else if let Some(f) = k.strip_prefix("study_price_") {
                if let Ok(n) = v.parse::<i32>() {
                    if n >= 0 {
                        p.fixed.push((f.to_string(), n));
                    }
                }
            }
        }
        p
    }

    fn fixed(&self, feature: &str) -> Option<i32> {
        self.fixed.iter().find(|(f, _)| f == feature).map(|(_, n)| *n)
    }

    /// Credits needed before starting (None = free).
    pub fn needed(&self, feature: &str) -> Option<i32> {
        match self.fixed(feature) {
            Some(n) => Some(n),
            None => self.per_usd.map(|_| 1),
        }
    }

    /// What a finished call costs the user (None = free).
    pub fn charge(&self, feature: &str, cost_usd: f64) -> Option<i32> {
        if let Some(n) = self.fixed(feature) {
            return Some(n);
        }
        let rate = self.per_usd?;
        let n = (cost_usd.max(0.0) * rate - 1e-9).ceil();
        Some((n as i32).max(1))
    }
}

/// The prices, read at most once a minute.
#[derive(Default)]
pub struct PriceCache(Mutex<Option<(Instant, Prices)>>);

pub async fn prices(state: &AppState) -> Prices {
    if let Some((at, p)) = state.prices.0.lock().unwrap().as_ref() {
        if at.elapsed() < CACHE {
            return p.clone();
        }
    }
    let p = match &state.shared {
        Some(pool) => load(pool).await,
        None => Prices::default(),
    };
    *state.prices.0.lock().unwrap() = Some((Instant::now(), p.clone()));
    p
}

async fn load(pool: &PgPool) -> Prices {
    let rows = sqlx::query("SELECT key, value::text AS value FROM system_settings WHERE key = 'study_credits_per_usd' OR key LIKE 'study_price_%'")
        .fetch_all(pool)
        .await;
    match rows {
        Ok(rows) => Prices::from_rows(&rows.iter().map(|r| (r.get("key"), r.get::<Option<String>, _>("value").unwrap_or_default())).collect::<Vec<_>>()),
        Err(e) => {
            tracing::warn!("prices: {e}");
            Prices::default()
        }
    }
}

fn ledger(state: &AppState) -> Credits {
    Credits::new(state.shared.clone(), "octo", true)
}

/// Not enough credits to start: the message and the SSE error data.
#[derive(Debug, Clone)]
pub struct Short {
    pub needed: i32,
    pub balance: i32,
}

impl Short {
    pub fn data(&self) -> Value {
        json!({
            "message": format!("You need {} OctoCredits for this, but you have {}.", self.needed, self.balance),
            "code": "insufficient_credits",
            "needed": self.needed,
            "balance": self.balance,
        })
    }
}

/// Before an AI call: enough credits for `feature`?
pub async fn precheck(state: &AppState, user: Uuid, feature: &str) -> Result<(), Short> {
    let Some(needed) = prices(state).await.needed(feature) else { return Ok(()) };
    if needed <= 0 {
        return Ok(());
    }
    let balance = match ledger(state).balance(user).await {
        Ok(b) => b.unwrap_or(0),
        Err(e) => {
            // Can't read the balance: let the work run, the charge decides.
            tracing::warn!(%user, "credits balance: {e:?}");
            return Ok(());
        }
    };
    if balance < needed {
        return Err(Short { needed, balance });
    }
    Ok(())
}

/// One AI action's credits. A fixed price is taken before the call, so a
/// user who leaves mid-answer has still paid for what the AI already cost;
/// it is given back if the call yields nothing. A metered price can only be
/// known after the call, so it is charged then.
pub struct Hold {
    user: Uuid,
    feature: String,
    source_ref: String,
    paid: bool,
}

impl Hold {
    /// The call is done: charge it, unless it was paid up front.
    pub async fn settle(self, state: &AppState, cost_usd: f64, meta: Value) {
        if !self.paid {
            settle(state, self.user, &self.feature, &self.source_ref, cost_usd, meta).await;
        }
    }

    /// The call gave the user nothing: hand back what was paid up front.
    pub async fn release(self, state: &AppState) {
        if !self.paid {
            return;
        }
        let reason = format!("study studio {}: no result", self.feature);
        if let Err(e) = ledger(state).refund(self.user, &self.source_ref, &reason).await {
            tracing::warn!(user = %self.user, source_ref = %self.source_ref, "credits refund: {e:?}");
        }
    }
}

/// Before an AI call: pay a fixed price now, or check a metered one can be
/// paid. Short → no AI call. `source_ref` names this one action.
pub async fn reserve(state: &AppState, user: Uuid, feature: &str, source_ref: String, meta: Value) -> Result<Hold, Short> {
    let mut hold = Hold { user, feature: feature.to_string(), source_ref, paid: false };
    let Some(price) = prices(state).await.fixed(feature).filter(|n| *n > 0) else {
        precheck(state, user, feature).await?;
        return Ok(hold);
    };
    let credits = ledger(state);
    let reason = format!("study studio {feature}");
    let meta = json!({ "feature": feature, "detail": meta });
    match credits.charge(user, price, &hold.source_ref, &reason, meta).await {
        Ok(_) => hold.paid = true,
        Err(e) if e.code == Some("insufficient_credits") => {
            let balance = credits.balance(user).await.ok().flatten().unwrap_or(0);
            return Err(Short { needed: price, balance });
        }
        // The ledger can't be reached: let the work run, settle tries again.
        Err(e) => tracing::warn!(%user, source_ref = %hold.source_ref, "credits charge up front: {e:?}"),
    }
    Ok(hold)
}

/// After an AI call: take its price once for `source_ref`.
pub async fn settle(state: &AppState, user: Uuid, feature: &str, source_ref: &str, cost_usd: f64, meta: Value) {
    let Some(amount) = prices(state).await.charge(feature, cost_usd) else { return };
    let credits = ledger(state);
    let reason = format!("study studio {feature}");
    let meta = json!({ "feature": feature, "costUsd": cost_usd, "detail": meta });
    match credits.charge(user, amount, source_ref, &reason, meta.clone()).await {
        Ok(_) => {}
        Err(e) if e.code == Some("insufficient_credits") => {
            // Spent meanwhile (or the call cost more than was left): take the rest.
            let left = credits.balance(user).await.ok().flatten().unwrap_or(0).min(amount);
            if left > 0 {
                if let Err(e) = credits.charge(user, left, source_ref, &reason, meta).await {
                    tracing::warn!(%user, source_ref, "credits charge: {e:?}");
                }
            }
        }
        Err(e) => tracing::warn!(%user, source_ref, "credits charge: {e:?}"),
    }
}

/// A finished build: the sum of its calls, once.
pub async fn settle_build(state: &AppState, user: Uuid, studio: Uuid, build: Uuid) {
    let cost: f64 = sqlx::query_scalar("SELECT COALESCE(SUM(cost_usd), 0)::float8 FROM llm_usage WHERE build_id = $1")
        .bind(build)
        .fetch_one(&state.cockpit)
        .await
        .unwrap_or(0.0);
    settle(state, user, "build", &format!("study:build:{build}"), cost, json!({ "studio": studio, "build": build })).await;
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rows(r: &[(&str, &str)]) -> Prices {
        Prices::from_rows(&r.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect::<Vec<_>>())
    }

    #[test]
    fn free_until_the_admin_sets_a_price() {
        let p = rows(&[]);
        assert_eq!(p.needed("ask"), None);
        assert_eq!(p.charge("ask", 0.03), None);
    }

    #[test]
    fn metered_rounds_up_and_charges_at_least_one() {
        let p = rows(&[("study_credits_per_usd", "1000")]);
        assert_eq!(p.needed("ask"), Some(1));
        assert_eq!(p.charge("ask", 0.0285), Some(29));
        assert_eq!(p.charge("ask", 0.025), Some(25));
        assert_eq!(p.charge("ask", 0.0), Some(1));
    }

    #[test]
    fn a_fixed_price_wins_for_its_feature() {
        let p = rows(&[("study_credits_per_usd", "\"500\""), ("study_price_build", "50"), ("study_price_x", "no")]);
        assert_eq!(p.needed("build"), Some(50));
        assert_eq!(p.charge("build", 0.9), Some(50));
        assert_eq!(p.charge("concepts", 0.017), Some(9));
        assert_eq!(p.charge("x", 0.001), Some(1));
    }
}

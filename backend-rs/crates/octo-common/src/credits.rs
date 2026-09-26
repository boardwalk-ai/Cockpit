//! OctoCredits — ONE central balance (`users.octo_credits`) shared by
//! OctoNotes, Study Studio and OctopilotWeb, and any of them may deduct.
//! Every writer follows the same protocol so concurrent apps never overspend
//! and a retry never double-charges:
//!
//! 1. `SELECT … FROM users WHERE id = $1 FOR UPDATE` (serializes writers per user,
//!    the same lock octopilot-api takes);
//! 2. a ledger row with this `source_ref` already exists → no-op (retry);
//! 3. balance < amount → 402 `insufficient_credits`;
//! 4. insert the `credit_ledger` row (`source_ref` = `{app}:{action}:{id}`,
//!    unique) and decrement `users.octo_credits`; commit.
//!
//! Refunds are a positive entry with `source_ref = '{original}:refund'`.
//! ⚠ Verify the live post-migration `credit_ledger` columns before enabling in
//! production (the repo only has the pre-migration snapshot).

use axum::http::StatusCode;
use serde::Serialize;
use serde_json::{json, Value};
use sqlx::{PgPool, Row};
use uuid::Uuid;

use crate::error::ApiError;

#[derive(Clone)]
pub struct Credits {
    pool: Option<PgPool>,
    ledger_type: String,
    enabled: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChargeOutcome {
    /// False when this `source_ref` was already charged (a retry).
    pub charged: bool,
    pub amount: i32,
    pub balance: Option<i32>,
}

impl Credits {
    pub fn new(pool: Option<PgPool>, ledger_type: impl Into<String>, enabled: bool) -> Self {
        Self {
            pool,
            ledger_type: ledger_type.into(),
            enabled,
        }
    }

    /// Charging is live (shared DB configured and not disabled).
    pub fn active(&self) -> bool {
        self.enabled && self.pool.is_some()
    }

    pub async fn balance(&self, user_id: Uuid) -> Result<Option<i32>, ApiError> {
        let Some(pool) = &self.pool else {
            return Ok(None);
        };
        Ok(
            sqlx::query_scalar("SELECT COALESCE(octo_credits, 0) FROM users WHERE id = $1")
                .bind(user_id)
                .fetch_optional(pool)
                .await?,
        )
    }

    /// Fails with 402 before any paid work starts.
    pub async fn precheck(&self, user_id: Uuid, amount: i32) -> Result<(), ApiError> {
        if !self.active() || amount <= 0 {
            return Ok(());
        }
        let balance = self.balance(user_id).await?.unwrap_or(0);
        if balance < amount {
            return Err(insufficient(amount, balance));
        }
        Ok(())
    }

    /// Deducts `amount` once per `source_ref`.
    pub async fn charge(
        &self,
        user_id: Uuid,
        amount: i32,
        source_ref: &str,
        reason: &str,
        metadata: Value,
    ) -> Result<ChargeOutcome, ApiError> {
        let Some(pool) = &self.pool else {
            return Ok(ChargeOutcome {
                charged: false,
                amount,
                balance: None,
            });
        };
        if !self.enabled || amount <= 0 {
            return Ok(ChargeOutcome {
                charged: false,
                amount,
                balance: self.balance(user_id).await?,
            });
        }
        let mut tx = pool.begin().await?;
        let balance: Option<i32> = sqlx::query_scalar(
            "SELECT COALESCE(octo_credits, 0) FROM users WHERE id = $1 FOR UPDATE",
        )
        .bind(user_id)
        .fetch_optional(&mut *tx)
        .await?;
        let balance = balance.ok_or_else(|| ApiError::not_found("no account"))?;
        let exists: Option<Uuid> =
            sqlx::query_scalar("SELECT id FROM credit_ledger WHERE source_ref = $1")
                .bind(source_ref)
                .fetch_optional(&mut *tx)
                .await?;
        if exists.is_some() {
            return Ok(ChargeOutcome {
                charged: false,
                amount,
                balance: Some(balance),
            });
        }
        if balance < amount {
            return Err(insufficient(amount, balance));
        }
        sqlx::query(
            "INSERT INTO credit_ledger (user_id, credit_type, entry_type, amount, available_amount, source_ref, reason, metadata_json) \
             VALUES ($1, $2, 'usage_deduction', $3, 0, $4, $5, $6)",
        )
        .bind(user_id)
        .bind(&self.ledger_type)
        .bind(-amount)
        .bind(source_ref)
        .bind(reason)
        .bind(metadata.to_string())
        .execute(&mut *tx)
        .await?;
        let new_balance: i32 = sqlx::query_scalar("UPDATE users SET octo_credits = COALESCE(octo_credits, 0) - $2 WHERE id = $1 RETURNING octo_credits")
            .bind(user_id)
            .bind(amount)
            .fetch_one(&mut *tx)
            .await?;
        tx.commit().await?;
        Ok(ChargeOutcome {
            charged: true,
            amount,
            balance: Some(new_balance),
        })
    }

    /// Gives back a charge (failed build …). Once per original `source_ref`;
    /// a no-op if the original was never charged.
    pub async fn refund(
        &self,
        user_id: Uuid,
        original_ref: &str,
        reason: &str,
    ) -> Result<ChargeOutcome, ApiError> {
        let Some(pool) = &self.pool else {
            return Ok(ChargeOutcome {
                charged: false,
                amount: 0,
                balance: None,
            });
        };
        let mut tx = pool.begin().await?;
        sqlx::query("SELECT id FROM users WHERE id = $1 FOR UPDATE")
            .bind(user_id)
            .fetch_optional(&mut *tx)
            .await?;
        let original =
            sqlx::query("SELECT amount FROM credit_ledger WHERE source_ref = $1 AND user_id = $2")
                .bind(original_ref)
                .bind(user_id)
                .fetch_optional(&mut *tx)
                .await?;
        let Some(original) = original else {
            return Ok(ChargeOutcome {
                charged: false,
                amount: 0,
                balance: None,
            });
        };
        let amount = -original.get::<i32, _>("amount");
        let refund_ref = format!("{original_ref}:refund");
        let done: Option<Uuid> =
            sqlx::query_scalar("SELECT id FROM credit_ledger WHERE source_ref = $1")
                .bind(&refund_ref)
                .fetch_optional(&mut *tx)
                .await?;
        if done.is_some() || amount <= 0 {
            return Ok(ChargeOutcome {
                charged: false,
                amount,
                balance: None,
            });
        }
        sqlx::query(
            "INSERT INTO credit_ledger (user_id, credit_type, entry_type, amount, available_amount, source_ref, reason) \
             VALUES ($1, $2, 'usage_refund', $3, 0, $4, $5)",
        )
        .bind(user_id)
        .bind(&self.ledger_type)
        .bind(amount)
        .bind(&refund_ref)
        .bind(reason)
        .execute(&mut *tx)
        .await?;
        let balance: i32 = sqlx::query_scalar("UPDATE users SET octo_credits = COALESCE(octo_credits, 0) + $2 WHERE id = $1 RETURNING octo_credits")
            .bind(user_id)
            .bind(amount)
            .fetch_one(&mut *tx)
            .await?;
        tx.commit().await?;
        Ok(ChargeOutcome {
            charged: true,
            amount,
            balance: Some(balance),
        })
    }
}

pub fn insufficient(needed: i32, balance: i32) -> ApiError {
    ApiError::new(
        StatusCode::PAYMENT_REQUIRED,
        format!("This costs {needed} OctoCredits, but you have {balance}."),
    )
    .with_code("insufficient_credits")
    .with_details(json!({ "needed": needed, "balance": balance }))
}

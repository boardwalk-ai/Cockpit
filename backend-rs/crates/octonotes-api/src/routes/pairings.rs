//! Recording on another phone. A session has at most two devices: the
//! receiver (phone or PC, where the session is worked on: live transcript,
//! notes, pencil) and the recorder (always a phone). The receiver asks for a
//! pairing and shows its 6-digit code or a QR with its secret; the phone,
//! signed in to the same account, claims it; when the receiver starts the
//! session it hands the session over, and the phone joins it as the recorder
//! (`POST /v1/sessions/{id}/recordings`).
//!
//! An unclaimed pairing lasts 10 minutes; a paired one 30 more to be started.

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{DateTime, Duration, Utc};
use octo_common::ApiError;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::ctx::Caller;
use crate::routes::devices::ensure_owned;
use crate::AppState;

const UNCLAIMED_FOR: i64 = 10;
const PAIRED_FOR: i32 = 30;
const RECORDER_PLATFORMS: [&str; 2] = ["android", "ios"];

/// What either phone sees of a pairing.
#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct Pairing {
    pub id: Uuid,
    /// `waiting` | `paired` | `started` | `expired` | `cancelled`
    pub status: String,
    pub code: String,
    /// Only for the receiver, which draws the QR from it (`octonotes-pair:<secret>`).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub secret: Option<String>,
    pub receiver_device: DeviceRef,
    pub recorder_device: Option<DeviceRef>,
    pub session_id: Option<Uuid>,
    pub expires_at: DateTime<Utc>,
}

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct DeviceRef {
    pub id: Uuid,
    pub name: String,
    pub platform: String,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct CreatePairing {
    /// The phone that will run the session.
    pub receiver_device_id: Uuid,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ClaimPairing {
    /// The 6-digit code, typed in…
    pub code: Option<String>,
    /// …or the QR's text (`octonotes-pair:<secret>`) or bare secret.
    pub secret: Option<String>,
    /// The phone that will record.
    pub device_id: Uuid,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct StartPairing {
    pub session_id: Uuid,
}

fn random_code() -> String {
    format!("{:06}", Uuid::new_v4().as_u128() % 1_000_000)
}

fn status_of(r: &sqlx::postgres::PgRow) -> String {
    if r.get::<Option<DateTime<Utc>>, _>("cancelled_at").is_some() {
        "cancelled"
    } else if r.get::<Option<DateTime<Utc>>, _>("started_at").is_some() {
        "started"
    } else if r.get::<DateTime<Utc>, _>("expires_at") <= Utc::now() {
        "expired"
    } else if r.get::<Option<DateTime<Utc>>, _>("claimed_at").is_some() {
        "paired"
    } else {
        "waiting"
    }
    .into()
}

const SELECT: &str = "SELECT p.*, v.name AS v_name, v.platform AS v_platform, r.name AS r_name, r.platform AS r_platform \
     FROM session_pairings p JOIN devices v ON v.id = p.receiver_device_id LEFT JOIN devices r ON r.id = p.recorder_device_id";

fn to_pairing(r: &sqlx::postgres::PgRow, with_secret: bool) -> Pairing {
    Pairing {
        id: r.get("id"),
        status: status_of(r),
        code: r.get("code"),
        secret: with_secret.then(|| r.get("secret")),
        receiver_device: DeviceRef {
            id: r.get("receiver_device_id"),
            name: r.get("v_name"),
            platform: r.get("v_platform"),
        },
        recorder_device: r.get::<Option<Uuid>, _>("recorder_device_id").map(|id| DeviceRef {
            id,
            name: r.get::<Option<String>, _>("r_name").unwrap_or_default(),
            platform: r.get::<Option<String>, _>("r_platform").unwrap_or_default(),
        }),
        session_id: r.get("session_id"),
        expires_at: r.get("expires_at"),
    }
}

async fn load(st: &AppState, caller: &Caller, id: Uuid) -> Result<sqlx::postgres::PgRow, ApiError> {
    sqlx::query(&format!("{SELECT} WHERE p.id = $1 AND p.user_id = $2"))
        .bind(id)
        .bind(caller.user_id)
        .fetch_optional(&st.notes)
        .await?
        .ok_or_else(|| ApiError::not_found("pairing not found"))
}

fn not_now(r: &sqlx::postgres::PgRow, code: &'static str) -> ApiError {
    ApiError::new(StatusCode::CONFLICT, format!("This pairing is {}.", status_of(r))).with_code(code)
}

#[utoipa::path(post, path = "/v1/pairings", tag = "pairings", request_body = CreatePairing,
    responses((status = 201, body = Pairing)))]
pub async fn create(
    State(st): State<AppState>,
    caller: Caller,
    Json(req): Json<CreatePairing>,
) -> Result<(StatusCode, Json<Pairing>), ApiError> {
    let mut conn = st.notes.acquire().await?;
    ensure_owned(&mut conn, &caller, req.receiver_device_id).await?;
    // A code none of this user's open pairings already shows.
    let mut code = random_code();
    for _ in 0..8 {
        let taken: Option<Uuid> = sqlx::query_scalar(
            "SELECT id FROM session_pairings WHERE user_id = $1 AND code = $2 AND expires_at > now() AND cancelled_at IS NULL",
        )
        .bind(caller.user_id)
        .bind(&code)
        .fetch_optional(&mut *conn)
        .await?;
        if taken.is_none() {
            break;
        }
        code = random_code();
    }
    let id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO session_pairings (id, user_id, code, secret, receiver_device_id, expires_at) VALUES ($1, $2, $3, $4, $5, $6)",
    )
    .bind(id)
    .bind(caller.user_id)
    .bind(&code)
    .bind(Uuid::new_v4().simple().to_string())
    .bind(req.receiver_device_id)
    .bind(Utc::now() + Duration::minutes(UNCLAIMED_FOR))
    .execute(&mut *conn)
    .await?;
    drop(conn);
    let row = load(&st, &caller, id).await?;
    Ok((StatusCode::CREATED, Json(to_pairing(&row, true))))
}

#[utoipa::path(post, path = "/v1/pairings/claim", tag = "pairings", request_body = ClaimPairing,
    responses((status = 200, body = Pairing), (status = 404, description = "No such code (or it expired)"),
        (status = 403, description = "The QR belongs to another account")))]
pub async fn claim(
    State(st): State<AppState>,
    caller: Caller,
    Json(req): Json<ClaimPairing>,
) -> Result<Json<Pairing>, ApiError> {
    let mut conn = st.notes.acquire().await?;
    ensure_owned(&mut conn, &caller, req.device_id).await?;
    // The recorder is always a phone (two PCs never pair).
    let platform: String = sqlx::query_scalar("SELECT platform FROM devices WHERE id = $1")
        .bind(req.device_id)
        .fetch_one(&mut *conn)
        .await?;
    if !RECORDER_PLATFORMS.contains(&platform.as_str()) {
        return Err(ApiError::bad_request("Only a phone can record. Open OctoNotes on your phone and pair from there.")
            .with_code("recorder_not_phone"));
    }
    let secret =req.secret.as_deref().map(str::trim).filter(|s| !s.is_empty());
    let code = req.code.as_deref().map(str::trim).filter(|s| !s.is_empty());
    let found: Option<Uuid> = match (secret, code) {
        (Some(secret), _) => {
            let secret = secret.strip_prefix("octonotes-pair:").unwrap_or(secret);
            let row: Option<(Uuid, Uuid)> = sqlx::query_as("SELECT id, user_id FROM session_pairings WHERE secret = $1")
                .bind(secret)
                .fetch_optional(&mut *conn)
                .await?;
            match row {
                Some((_, owner)) if owner != caller.user_id => {
                    return Err(ApiError::new(
                        StatusCode::FORBIDDEN,
                        "This code is for another account. Sign in with the same account on both phones.",
                    )
                    .with_code("other_account"))
                }
                r => r.map(|(id, _)| id),
            }
        }
        (None, Some(code)) if code.len() == 6 && code.chars().all(|c| c.is_ascii_digit()) => {
            sqlx::query_scalar(
                "SELECT id FROM session_pairings WHERE user_id = $1 AND code = $2 AND cancelled_at IS NULL \
                 AND started_at IS NULL AND expires_at > now() ORDER BY created_at DESC LIMIT 1",
            )
            .bind(caller.user_id)
            .bind(code)
            .fetch_optional(&mut *conn)
            .await?
        }
        _ => return Err(ApiError::bad_request("Send the 6-digit code or the QR.")),
    };
    let id = found.ok_or_else(|| ApiError::not_found("No pairing with that code. Check it, or make a new one."))?;
    let claimed = sqlx::query(
        "UPDATE session_pairings SET recorder_device_id = $3, claimed_at = now(), \
             expires_at = now() + make_interval(mins => $4) \
         WHERE id = $1 AND user_id = $2 AND cancelled_at IS NULL AND started_at IS NULL AND expires_at > now() \
           AND receiver_device_id <> $3 AND (recorder_device_id IS NULL OR recorder_device_id = $3)",
    )
    .bind(id)
    .bind(caller.user_id)
    .bind(req.device_id)
    .bind(PAIRED_FOR)
    .execute(&mut *conn)
    .await?
    .rows_affected();
    drop(conn);
    let row = load(&st, &caller, id).await?;
    if claimed == 0 {
        let receiver: Uuid = row.get("receiver_device_id");
        return Err(if receiver == req.device_id {
            ApiError::bad_request("This device runs the session. Scan or type the code on your phone.")
        } else {
            not_now(&row, "not_waiting")
        });
    }
    Ok(Json(to_pairing(&row, false)))
}

#[utoipa::path(get, path = "/v1/pairings/{id}", tag = "pairings", responses((status = 200, body = Pairing)))]
pub async fn get(State(st): State<AppState>, caller: Caller, Path(id): Path<Uuid>) -> Result<Json<Pairing>, ApiError> {
    let row = load(&st, &caller, id).await?;
    Ok(Json(to_pairing(&row, false)))
}

#[utoipa::path(post, path = "/v1/pairings/{id}/start", tag = "pairings", request_body = StartPairing,
    responses((status = 200, body = Pairing), (status = 409, description = "No phone has paired yet")))]
pub async fn start(
    State(st): State<AppState>,
    caller: Caller,
    Path(id): Path<Uuid>,
    Json(req): Json<StartPairing>,
) -> Result<Json<Pairing>, ApiError> {
    let owned: Option<Uuid> =
        sqlx::query_scalar("SELECT id FROM sessions WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL")
            .bind(req.session_id)
            .bind(caller.user_id)
            .fetch_optional(&st.notes)
            .await?;
    if owned.is_none() {
        return Err(ApiError::not_found("session not found"));
    }
    // One recorder per session: another phone already recording it blocks this one.
    let other: Option<Uuid> = sqlx::query_scalar(
        "SELECT sd.device_id FROM session_devices sd, session_pairings p \
         WHERE p.id = $1 AND p.user_id = $3 AND sd.session_id = $2 AND sd.role = 'recorder' \
           AND sd.device_id IS DISTINCT FROM p.recorder_device_id LIMIT 1",
    )
    .bind(id)
    .bind(req.session_id)
    .bind(caller.user_id)
    .fetch_optional(&st.notes)
    .await?;
    if other.is_some() {
        return Err(ApiError::new(StatusCode::CONFLICT, "Another phone is already recording this session.")
            .with_code("has_recorder"));
    }
    sqlx::query(
        "UPDATE session_pairings SET session_id = $3, started_at = now() \
         WHERE id = $1 AND user_id = $2 AND claimed_at IS NOT NULL AND started_at IS NULL \
           AND cancelled_at IS NULL AND expires_at > now()",
    )
    .bind(id)
    .bind(caller.user_id)
    .bind(req.session_id)
    .execute(&st.notes)
    .await?;
    let row = load(&st, &caller, id).await?;
    // Started now, or already with this very session (a retry): fine.
    if row.get::<Option<Uuid>, _>("session_id") != Some(req.session_id) {
        return Err(not_now(&row, "not_paired"));
    }
    Ok(Json(to_pairing(&row, false)))
}

#[utoipa::path(delete, path = "/v1/pairings/{id}", tag = "pairings", responses((status = 204)))]
pub async fn cancel(State(st): State<AppState>, caller: Caller, Path(id): Path<Uuid>) -> Result<StatusCode, ApiError> {
    sqlx::query(
        "UPDATE session_pairings SET cancelled_at = COALESCE(cancelled_at, now()) WHERE id = $1 AND user_id = $2 AND started_at IS NULL",
    )
    .bind(id)
    .bind(caller.user_id)
    .execute(&st.notes)
    .await?;
    Ok(StatusCode::NO_CONTENT)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn codes_are_six_digits() {
        for _ in 0..500 {
            let c = random_code();
            assert_eq!(c.len(), 6);
            assert!(c.chars().all(|x| x.is_ascii_digit()));
        }
    }
}

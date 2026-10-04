//! Files attached to a project (src/attachments.rs): the text is taken out
//! and a card made; the file itself is not kept.

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;
use base64::Engine as _;
use octo_common::ApiError;
use serde::Deserialize;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::attachments::{self, Card, Kind};
use crate::ctx::Caller;
use crate::AppState;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Upload {
    /// Chosen by the client, so a retried upload is not read twice.
    pub id: Uuid,
    pub name: String,
    /// The file, base64.
    pub data: String,
}

/// Pages read free per file; past them, each page costs OctoCredits.
const FREE_PAGES: i64 = 10;
const PAGE_CREDITS: i64 = 2;

async fn setting(st: &AppState, key: &str, default: i64) -> i64 {
    let Some(pool) = &st.octopilot else {
        return default;
    };
    octo_common::llm::setting(pool, key)
        .await
        .and_then(|v| v.trim().parse().ok())
        .unwrap_or(default)
}

/// `POST /v1/projects/:id/attachments` — reads a file into the project.
pub async fn upload(
    State(st): State<AppState>,
    caller: Caller,
    Path(project_id): Path<Uuid>,
    Json(body): Json<Upload>,
) -> Result<(StatusCode, Json<Value>), ApiError> {
    let owned: Option<Uuid> =
        sqlx::query_scalar("SELECT id FROM projects WHERE id = $1 AND user_id = $2")
            .bind(project_id)
            .bind(caller.user_id)
            .fetch_optional(&st.db)
            .await?;
    owned.ok_or_else(|| ApiError::not_found("project not found"))?;

    // A retry of an upload that went through.
    let existing: Option<(Uuid, Uuid, Value)> =
        sqlx::query_as("SELECT project_id, user_id, card FROM attachments WHERE id = $1")
            .bind(body.id)
            .fetch_optional(&st.db)
            .await?;
    if let Some((project, user, card)) = existing {
        if project == project_id && user == caller.user_id {
            return Ok((StatusCode::OK, Json(with_id(card, body.id))));
        }
        return Err(
            ApiError::new(StatusCode::CONFLICT, "that attachment id is in use")
                .with_code("attachment_id_taken"),
        );
    }

    let name: String = body.name.trim().chars().take(200).collect();
    let name = if name.is_empty() {
        "file".to_string()
    } else {
        name
    };
    let bytes = base64::engine::general_purpose::STANDARD
        .decode(body.data.trim())
        .map_err(|_| ApiError::bad_request("data is not base64"))?;
    if bytes.len() > attachments::MAX_BYTES {
        return Err(ApiError::new(
            StatusCode::PAYLOAD_TOO_LARGE,
            "The file is larger than 20 MB.",
        )
        .with_code("too_large"));
    }
    let (kind, mime) = attachments::sniff(&bytes, &name).ok_or_else(|| {
        ApiError::new(
            StatusCode::UNSUPPORTED_MEDIA_TYPE,
            "Attach a PDF, a Word document (.docx), a text file or a photo.",
        )
        .with_code("unsupported_file")
    })?;

    let (llm, models) = crate::agent::client(&st).await.ok_or_else(|| {
        ApiError::new(
            StatusCode::SERVICE_UNAVAILABLE,
            "Reading files is not available right now.",
        )
    })?;
    let unreadable = |message: String| {
        ApiError::new(StatusCode::UNPROCESSABLE_ENTITY, message).with_code("unreadable")
    };

    let (text, pages) = if kind == Kind::Image {
        let vision = match &st.octopilot {
            Some(pool) => {
                octo_common::llm::model(pool, "ghostwriter_vision_model", &models.secondary).await
            }
            None => models.secondary.clone(),
        };
        let text = attachments::read_image(llm.as_ref(), &vision, &bytes, mime)
            .await
            .map_err(unreadable)?;
        (text, 1)
    } else {
        let extracted = attachments::extract(kind, bytes)
            .await
            .map_err(unreadable)?;
        (extracted.text, extracted.pages)
    };

    // The first pages are free; the rest cost OctoCredits.
    let free = setting(&st, "ghostwriter_free_pages", FREE_PAGES).await;
    let per_page = setting(&st, "ghostwriter_page_credits", PAGE_CREDITS).await;
    let paid = (pages as i64 - free).max(0);
    let cost = (paid * per_page).clamp(0, i32::MAX as i64) as i32;
    if cost > 0 && st.credits.active() {
        st.credits
            .precheck(caller.user_id, cost)
            .await
            .map_err(|e| {
                ApiError::new(
                    StatusCode::PAYMENT_REQUIRED,
                    format!("Reading this file needs {cost} OctoCredits: {}", e.message),
                )
                .with_code("insufficient_credits")
            })?;
    }

    let card: Card = attachments::read_card(
        llm.as_ref(),
        &models.secondary,
        body.id,
        &name,
        &text,
        pages,
    )
    .await;
    let card_json = serde_json::to_value(&card).unwrap_or_default();
    sqlx::query(
        "INSERT INTO attachments (id, project_id, user_id, kind, pages, card, text) \
         VALUES ($1, $2, $3, $4, $5, $6, $7) ON CONFLICT (id) DO NOTHING",
    )
    .bind(body.id)
    .bind(project_id)
    .bind(caller.user_id)
    .bind(kind.as_str())
    .bind(pages as i32)
    .bind(&card_json)
    .bind(&text)
    .execute(&st.db)
    .await?;

    if cost > 0 && st.credits.active() {
        let charged = st
            .credits
            .charge(
                caller.user_id,
                cost,
                &format!("ghostwriter:read:{}", body.id),
                "Reading an attached file",
                json!({ "projectId": project_id, "attachmentId": body.id, "pages": pages }),
            )
            .await;
        if let Err(error) = charged {
            tracing::error!(attachment = %body.id, error = %error.message, "could not charge for a file");
        }
    }
    Ok((StatusCode::CREATED, Json(card_json)))
}

/// `GET /v1/projects/:id/attachments` — the project's files, as cards.
pub async fn list(
    State(st): State<AppState>,
    caller: Caller,
    Path(project_id): Path<Uuid>,
) -> Result<Json<Value>, ApiError> {
    let rows: Vec<(Uuid, Value, Option<String>)> = sqlx::query_as(
        "SELECT id, card, role FROM attachments WHERE project_id = $1 AND user_id = $2 \
         ORDER BY created_at",
    )
    .bind(project_id)
    .bind(caller.user_id)
    .fetch_all(&st.db)
    .await?;
    let items: Vec<Value> = rows
        .into_iter()
        .map(|(id, card, role)| {
            let mut card = with_id(card, id);
            card["role"] = json!(role);
            card
        })
        .collect();
    Ok(Json(json!({ "items": items })))
}

/// `DELETE /v1/attachments/:id` — takes a file back before it is used.
pub async fn remove(
    State(st): State<AppState>,
    caller: Caller,
    Path(id): Path<Uuid>,
) -> Result<StatusCode, ApiError> {
    sqlx::query("DELETE FROM attachments WHERE id = $1 AND user_id = $2")
        .bind(id)
        .bind(caller.user_id)
        .execute(&st.db)
        .await?;
    Ok(StatusCode::NO_CONTENT)
}

fn with_id(mut card: Value, id: Uuid) -> Value {
    card["id"] = json!(id);
    card
}

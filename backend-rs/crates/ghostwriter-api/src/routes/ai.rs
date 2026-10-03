//! The user's AI settings: which model and personality they run with, for
//! every app or for one. The catalog comes from the shared DB (admins write
//! it); the real models behind a name never leave the server.

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;
use octo_common::ai::{self, Choice, SCOPES};
use octo_common::ApiError;
use serde::Deserialize;
use serde_json::{json, Map, Value};
use sqlx::PgPool;

use super::present;
use crate::ctx::Caller;
use crate::AppState;

fn shared_db(st: &AppState) -> Result<&PgPool, ApiError> {
    st.octopilot
        .as_ref()
        .ok_or_else(|| ApiError::unavailable("AI settings are not available right now"))
}

/// `GET /v1/ai/catalog` — the models and personalities to choose from.
/// `locked`: a Pro model, and the user is not on Pro.
pub async fn catalog(State(st): State<AppState>, caller: Caller) -> Result<Json<Value>, ApiError> {
    let pool = shared_db(&st)?;
    let catalog = st.ai.catalog(pool).await;
    let pro = ai::is_pro(pool, caller.user_id).await;
    Ok(Json(json!({
        "pro": pro,
        "models": catalog.models.iter().map(|m| json!({
            "id": m.id,
            "name": m.display_name,
            "tagline": m.tagline,
            "pro": m.pro_only(),
            "locked": m.pro_only() && !pro,
            "default": m.is_default,
        })).collect::<Vec<_>>(),
        "personalities": catalog.personalities.iter().map(|p| json!({
            "id": p.id,
            "name": p.display_name,
            "description": p.description,
            "default": p.is_default,
        })).collect::<Vec<_>>(),
    })))
}

fn choice_json(choice: &Choice) -> Value {
    json!({
        "model": choice.model.as_ref().map(|m| &m.id),
        "personality": choice.personality.as_ref().map(|p| &p.id),
    })
}

async fn preferences_json(st: &AppState, pool: &PgPool, caller: &Caller) -> Value {
    let saved = ai::preferences(pool, caller.user_id).await;
    let mut scopes = Map::new();
    for scope in SCOPES {
        let pref = saved.iter().find(|p| p.scope == scope);
        scopes.insert(
            scope.to_string(),
            pref.map_or(
                Value::Null,
                |p| json!({ "model": p.model_id, "personality": p.personality_id }),
            ),
        );
    }
    let mut effective = Map::new();
    for app in SCOPES.iter().filter(|s| **s != "global") {
        let choice = st.ai.choice(pool, caller.user_id, app).await;
        effective.insert(app.to_string(), choice_json(&choice));
    }
    json!({ "scopes": scopes, "effective": effective })
}

/// `GET /v1/ai/preferences` — what the user saved per scope (`null` =
/// nothing saved there), and what each app runs with as a result.
pub async fn preferences(
    State(st): State<AppState>,
    caller: Caller,
) -> Result<Json<Value>, ApiError> {
    let pool = shared_db(&st)?;
    Ok(Json(preferences_json(&st, pool, &caller).await))
}

#[derive(Deserialize)]
pub struct PutPreference {
    /// Absent: leave it. `null`: follow the wider scope. An id: use it.
    #[serde(default, deserialize_with = "present")]
    pub model: Option<Option<String>>,
    #[serde(default, deserialize_with = "present")]
    pub personality: Option<Option<String>>,
}

/// `PUT /v1/ai/preferences/:scope` — save the user's choice for `global`
/// (every app) or one app. 403 `pro_required` for a Pro model off Pro.
pub async fn put_preference(
    State(st): State<AppState>,
    caller: Caller,
    Path(scope): Path<String>,
    Json(body): Json<PutPreference>,
) -> Result<Json<Value>, ApiError> {
    let pool = shared_db(&st)?;
    if !SCOPES.contains(&scope.as_str()) {
        return Err(ApiError::bad_request(format!(
            "scope must be one of {}",
            SCOPES.join(", ")
        )));
    }
    let catalog = st.ai.catalog(pool).await;
    if let Some(Some(id)) = &body.model {
        let model = catalog
            .models
            .iter()
            .find(|m| &m.id == id)
            .ok_or_else(|| ApiError::bad_request("unknown model"))?;
        if model.pro_only() && !ai::is_pro(pool, caller.user_id).await {
            return Err(
                ApiError::new(StatusCode::FORBIDDEN, "this model needs a Pro plan")
                    .with_code("pro_required"),
            );
        }
    }
    if let Some(Some(id)) = &body.personality {
        if !catalog.personalities.iter().any(|p| &p.id == id) {
            return Err(ApiError::bad_request("unknown personality"));
        }
    }

    ai::set_preference(
        pool,
        caller.user_id,
        &scope,
        body.model.as_ref().map(|m| m.as_deref()),
        body.personality.as_ref().map(|p| p.as_deref()),
    )
    .await?;
    Ok(Json(preferences_json(&st, pool, &caller).await))
}

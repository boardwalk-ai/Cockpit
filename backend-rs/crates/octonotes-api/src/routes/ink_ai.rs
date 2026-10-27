//! Handwriting recognition (Panel 6). The selected strokes are rendered to a
//! PNG in pure Rust (tiny-skia) and read by a vision model. The result is a
//! separate layer the student confirms or corrects — ink is never changed.

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;
use base64::Engine;
use octo_common::llm::{parse_json_loose, ChatOptions, Message};
use octo_common::ApiError;
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::{PgConnection, Row};
use tiny_skia::{LineCap, LineJoin, Paint, PathBuilder, Pixmap, Stroke as SkStroke, Transform};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::ai::{self, Llm, Role};
use crate::ctx::Caller;
use crate::routes::ink;
use crate::{access, pricing, AppState};

type Strokes = Vec<(String, String, f32, Vec<(f32, f32, f32)>)>;

/// Renders strokes (tool, #AARRGGBB, width, points) black-on-white, fitted to
/// at most 1024 px with a margin.
pub fn render_png(strokes: &Strokes) -> Option<Vec<u8>> {
    let pts: Vec<(f32, f32)> = strokes
        .iter()
        .flat_map(|s| s.3.iter().map(|p| (p.0, p.1)))
        .collect();
    let (minx, maxx) = pts
        .iter()
        .fold((f32::MAX, f32::MIN), |a, p| (a.0.min(p.0), a.1.max(p.0)));
    let (miny, maxy) = pts
        .iter()
        .fold((f32::MAX, f32::MIN), |a, p| (a.0.min(p.1), a.1.max(p.1)));
    if pts.is_empty() {
        return None;
    }
    let pad = 24.0;
    let (w, h) = (
        (maxx - minx).max(1.0) + 2.0 * pad,
        (maxy - miny).max(1.0) + 2.0 * pad,
    );
    let scale = (1024.0 / w.max(h)).min(4.0);
    let mut pix = Pixmap::new((w * scale).ceil() as u32, (h * scale).ceil() as u32)?;
    pix.fill(tiny_skia::Color::WHITE);
    let tf = Transform::from_row(
        scale,
        0.0,
        0.0,
        scale,
        (pad - minx) * scale,
        (pad - miny) * scale,
    );
    for (tool, _color, width, points) in strokes {
        if tool == "highlighter" || points.is_empty() {
            continue;
        }
        let mut pb = PathBuilder::new();
        pb.move_to(points[0].0, points[0].1);
        for p in points.iter().skip(1) {
            pb.line_to(p.0, p.1);
        }
        if points.len() == 1 {
            pb.line_to(points[0].0 + 0.1, points[0].1);
        }
        let Some(path) = pb.finish() else { continue };
        let mut paint = Paint::default();
        paint.set_color_rgba8(0, 0, 0, 255);
        paint.anti_alias = true;
        let stroke = SkStroke {
            width: width.max(1.5),
            line_cap: LineCap::Round,
            line_join: LineJoin::Round,
            ..Default::default()
        };
        pix.stroke_path(&path, &paint, &stroke, tf, None);
    }
    pix.encode_png().ok()
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct RecognizeRequest {
    pub stroke_ids: Vec<Uuid>,
}

#[utoipa::path(post, path = "/v1/ink/pages/{id}/recognize", tag = "ink", params(("id" = Uuid, Path)), request_body = RecognizeRequest,
    responses((status = 201, description = "{recognition: {id, text, confidence, status}, creditsCharged}")))]
pub async fn recognize(
    State(st): State<AppState>,
    caller: Caller,
    Path(page_id): Path<Uuid>,
    Json(req): Json<RecognizeRequest>,
) -> Result<(StatusCode, Json<Value>), ApiError> {
    if req.stroke_ids.is_empty() || req.stroke_ids.len() > 2000 {
        return Err(ApiError::bad_request("select 1..2000 strokes"));
    }
    let mut conn = st.notes.acquire().await?;
    let session_id: Uuid = sqlx::query_scalar(
        "SELECT session_id FROM ink_pages WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL",
    )
    .bind(page_id)
    .bind(caller.user_id)
    .fetch_optional(&mut *conn)
    .await?
    .ok_or_else(|| ApiError::not_found("page not found"))?;
    access::session(&mut conn, &caller, session_id).await?;
    let strokes = ink::strokes_for_render(&mut conn, page_id, &req.stroke_ids).await?;
    drop(conn);
    let png = render_png(&strokes).ok_or_else(|| ApiError::bad_request("no strokes to read"))?;
    let price = pricing::price(&st, "recognize").await;
    ai::guard(&st, &caller, price).await?;
    let run = ai::start_run(
        &st,
        &caller,
        Some(session_id),
        "recognize",
        None,
        &json!([{ "type": "ink", "pageId": page_id, "strokes": req.stroke_ids.len() }]),
    )
    .await?;
    let llm = Llm::for_role(&st, Role::Vision).await;
    let model = llm.model_name();
    let messages = vec![Message::user_with_image(
        "This is handwriting from a student's lecture notes. Transcribe it exactly (keep formulas like H2O or ATP). \
         Reply with JSON only: {\"text\": string, \"confidence\": number between 0 and 1}.",
        "image/png",
        &base64::engine::general_purpose::STANDARD.encode(&png),
    )];
    let offline = json!({ "text": format!("[offline handwriting: {} strokes]", strokes.len()), "confidence": 0.5 }).to_string();
    let (text, usage) = match llm
        .complete(
            &messages,
            &ChatOptions {
                temperature: Some(0.0),
                max_tokens: Some(600),
                json: true,
            },
            || offline,
        )
        .await
    {
        Ok(r) => r,
        Err(e) => {
            ai::fail_run(&st, run, &e.message).await;
            return Err(e);
        }
    };
    let v = parse_json_loose(&text).unwrap_or_default();
    let recognized = v["text"].as_str().unwrap_or("").trim().to_string();
    let confidence = v["confidence"].as_f64().unwrap_or(0.5).clamp(0.0, 1.0) as f32;
    let id: Uuid = sqlx::query_scalar(
        "INSERT INTO ink_recognitions (page_id, session_id, user_id, stroke_ids, text, confidence, ai_run_id) VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING id")
        .bind(page_id).bind(session_id).bind(caller.user_id).bind(&req.stroke_ids).bind(&recognized).bind(confidence).bind(run)
        .fetch_one(&st.notes).await?;
    let recognition = json!({ "id": id, "pageId": page_id, "text": recognized, "confidence": confidence, "status": "proposed", "strokeIds": req.stroke_ids });
    let charged = ai::finish_run(
        &st,
        &caller,
        run,
        ai::Outcome {
            kind: "recognize",
            response: &recognition,
            model: &model,
            usage: &usage,
            price,
        },
    )
    .await?;
    Ok((
        StatusCode::CREATED,
        Json(json!({ "recognition": recognition, "creditsCharged": charged })),
    ))
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct ReviewRecognition {
    /// `confirmed` | `corrected`
    pub status: String,
    pub text: Option<String>,
}

#[utoipa::path(patch, path = "/v1/ink/recognitions/{id}", tag = "ink", params(("id" = Uuid, Path)), request_body = ReviewRecognition,
    responses((status = 200)))]
pub async fn review(
    State(st): State<AppState>,
    caller: Caller,
    Path(id): Path<Uuid>,
    Json(req): Json<ReviewRecognition>,
) -> Result<Json<Value>, ApiError> {
    let text = match (req.status.as_str(), req.text.as_deref().map(str::trim)) {
        ("confirmed", _) => None,
        ("corrected", Some(t)) if !t.is_empty() && t.len() <= 10_000 => Some(t.to_string()),
        ("corrected", _) => return Err(ApiError::bad_request("corrected needs text")),
        _ => {
            return Err(ApiError::bad_request(
                "status must be confirmed or corrected",
            ))
        }
    };
    let row = sqlx::query("UPDATE ink_recognitions SET status = $3, text = COALESCE($4, text) WHERE id = $1 AND user_id = $2 RETURNING page_id, text, confidence, status")
        .bind(id).bind(caller.user_id).bind(&req.status).bind(text).fetch_optional(&st.notes).await?
        .ok_or_else(|| ApiError::not_found("recognition not found"))?;
    Ok(Json(
        json!({ "id": id, "pageId": row.get::<Uuid, _>("page_id"), "text": row.get::<String, _>("text"),
                    "confidence": row.get::<f32, _>("confidence"), "status": row.get::<String, _>("status") }),
    ))
}

/// (text, page id, page ordinal) for "Send to Typewriter".
pub async fn recognition_text(
    conn: &mut PgConnection,
    caller: &Caller,
    session_id: Uuid,
    id: Uuid,
) -> Result<(String, Uuid, i32), ApiError> {
    let row = sqlx::query("SELECT r.text, r.page_id, p.ordinal FROM ink_recognitions r JOIN ink_pages p ON p.id = r.page_id \
                           WHERE r.id = $1 AND r.user_id = $2 AND r.session_id = $3")
        .bind(id).bind(caller.user_id).bind(session_id).fetch_optional(conn).await?
        .ok_or_else(|| ApiError::not_found("recognition not found"))?;
    Ok((row.get("text"), row.get("page_id"), row.get("ordinal")))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn renders_png() {
        let strokes: Strokes = vec![(
            "pen".into(),
            "#FF000000".into(),
            3.0,
            vec![(10.0, 10.0, 0.5), (60.0, 40.0, 0.5), (90.0, 12.0, 0.5)],
        )];
        let png = render_png(&strokes).expect("png");
        assert_eq!(&png[..4], b"\x89PNG");
        assert!(render_png(&Vec::new()).is_none());
    }
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct DeviceRecognition {
    pub stroke_ids: Vec<Uuid>,
    pub text: String,
    #[serde(default)]
    pub confidence: f32,
}

/// The page's session, when the caller may use it.
async fn page_session(st: &AppState, caller: &Caller, page_id: Uuid) -> Result<Uuid, ApiError> {
    let mut conn = st.notes.acquire().await?;
    let session_id: Uuid = sqlx::query_scalar("SELECT session_id FROM ink_pages WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL")
        .bind(page_id)
        .bind(caller.user_id)
        .fetch_optional(&mut *conn)
        .await?
        .ok_or_else(|| ApiError::not_found("page not found"))?;
    access::session(&mut conn, caller, session_id).await?;
    Ok(session_id)
}

/// Text the phone read from a line of handwriting itself (on-device, free).
/// Kept as confirmed: the student wrote it and sees it in the page's notes.
#[utoipa::path(post, path = "/v1/ink/pages/{id}/recognitions", tag = "ink", params(("id" = Uuid, Path)),
    request_body = DeviceRecognition, responses((status = 201)))]
pub async fn add_recognition(
    State(st): State<AppState>,
    caller: Caller,
    Path(page_id): Path<Uuid>,
    Json(req): Json<DeviceRecognition>,
) -> Result<(StatusCode, Json<Value>), ApiError> {
    let text = req.text.trim();
    if text.is_empty() || text.len() > 2000 || req.stroke_ids.is_empty() || req.stroke_ids.len() > 500 {
        return Err(ApiError::bad_request("needs text (≤2000) and 1..500 strokes"));
    }
    let session_id = page_session(&st, &caller, page_id).await?;
    let confidence = req.confidence.clamp(0.0, 1.0);
    let id: Uuid = sqlx::query_scalar(
        "INSERT INTO ink_recognitions (page_id, session_id, user_id, stroke_ids, text, confidence, status) \
         VALUES ($1,$2,$3,$4,$5,$6,'confirmed') RETURNING id",
    )
    .bind(page_id)
    .bind(session_id)
    .bind(caller.user_id)
    .bind(&req.stroke_ids)
    .bind(text)
    .bind(confidence)
    .fetch_one(&st.notes)
    .await?;
    Ok((
        StatusCode::CREATED,
        Json(json!({ "id": id, "pageId": page_id, "text": text, "confidence": confidence, "status": "confirmed", "strokeIds": req.stroke_ids })),
    ))
}

/// A page's handwriting as text, oldest first, while any of its ink is left.
#[utoipa::path(get, path = "/v1/ink/pages/{id}/recognitions", tag = "ink", params(("id" = Uuid, Path)), responses((status = 200)))]
pub async fn list_recognitions(
    State(st): State<AppState>,
    caller: Caller,
    Path(page_id): Path<Uuid>,
) -> Result<Json<Value>, ApiError> {
    page_session(&st, &caller, page_id).await?;
    let items: Value = sqlx::query_scalar(
        "SELECT COALESCE(json_agg(json_build_object('id', r.id, 'text', r.text, 'status', r.status, 'strokeIds', r.stroke_ids, \
             'createdAt', r.created_at) ORDER BY r.created_at), '[]') \
         FROM ink_recognitions r WHERE r.page_id = $1 \
         AND EXISTS (SELECT 1 FROM ink_strokes s WHERE s.id = ANY(r.stroke_ids) AND s.deleted_at IS NULL)",
    )
    .bind(page_id)
    .fetch_one(&st.notes)
    .await?;
    Ok(Json(json!({ "items": items })))
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct FormulaRequest {
    pub stroke_ids: Vec<Uuid>,
}

/// Reads the selected ink as a formula (LaTeX) with the formula reader on
/// this server: free, no AI run. Kept as the page's text as `$$…$$`.
#[utoipa::path(post, path = "/v1/ink/pages/{id}/formula", tag = "ink", params(("id" = Uuid, Path)),
    request_body = FormulaRequest, responses((status = 201)))]
pub async fn formula(
    State(st): State<AppState>,
    caller: Caller,
    Path(page_id): Path<Uuid>,
    Json(req): Json<FormulaRequest>,
) -> Result<(StatusCode, Json<Value>), ApiError> {
    if req.stroke_ids.is_empty() || req.stroke_ids.len() > 2000 {
        return Err(ApiError::bad_request("select 1..2000 strokes"));
    }
    let session_id = page_session(&st, &caller, page_id).await?;
    let strokes = {
        let mut conn = st.notes.acquire().await?;
        ink::strokes_for_render(&mut conn, page_id, &req.stroke_ids).await?
    };
    let png = render_png(&strokes).ok_or_else(|| ApiError::bad_request("no strokes to read"))?;
    let res = st
        .http
        .post(format!("{}/formula", st.config.formula_url.trim_end_matches('/')))
        .header("content-type", "image/png")
        .body(png)
        .timeout(std::time::Duration::from_secs(30))
        .send()
        .await
        .map_err(|e| {
            tracing::warn!(error = %e, "formula reader unreachable");
            ApiError::unavailable("formula reading isn't available right now")
        })?;
    if !res.status().is_success() {
        tracing::warn!(status = %res.status(), "formula reader failed");
        return Err(ApiError::unavailable("couldn't read that formula"));
    }
    let v: Value = res.json().await.map_err(|_| ApiError::unavailable("couldn't read that formula"))?;
    let latex = v["latex"].as_str().unwrap_or("").trim().to_string();
    if latex.is_empty() {
        return Err(ApiError::bad_request("no formula found in that ink"));
    }
    let confidence = v["score"].as_f64().unwrap_or(0.5).clamp(0.0, 1.0) as f32;
    let text = format!("$${latex}$$");
    // The formula replaces any plain-text reading of the same ink.
    sqlx::query("DELETE FROM ink_recognitions WHERE page_id = $1 AND stroke_ids <@ $2")
        .bind(page_id)
        .bind(&req.stroke_ids)
        .execute(&st.notes)
        .await?;
    let id: Uuid = sqlx::query_scalar(
        "INSERT INTO ink_recognitions (page_id, session_id, user_id, stroke_ids, text, confidence, status) \
         VALUES ($1,$2,$3,$4,$5,$6,'confirmed') RETURNING id",
    )
    .bind(page_id)
    .bind(session_id)
    .bind(caller.user_id)
    .bind(&req.stroke_ids)
    .bind(&text)
    .bind(confidence)
    .fetch_one(&st.notes)
    .await?;
    Ok((
        StatusCode::CREATED,
        Json(json!({ "id": id, "pageId": page_id, "text": text, "latex": latex, "confidence": confidence, "status": "confirmed", "strokeIds": req.stroke_ids })),
    ))
}

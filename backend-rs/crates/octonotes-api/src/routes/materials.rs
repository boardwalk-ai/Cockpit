//! Materials & Slides (Panel 8). The original file is never modified; pages
//! get extracted text (text layer, or vision OCR for scans/photos), a render
//! when the tools exist (`pdftoppm`, LibreOffice), and join retrieval.

use std::path::PathBuf;

use axum::extract::{Multipart, Path, State};
use axum::http::StatusCode;
use axum::Json;
use base64::Engine;
use chrono::{DateTime, Utc};
use octo_common::llm::{parse_json_loose, ChatOptions, Message};
use octo_common::ApiError;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sqlx::{PgConnection, Row};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::ai::{Llm, Role};
use crate::ctx::Caller;
use crate::jobs::{self, Job, JobResult};
use crate::realtime::Event;
use crate::{access, AppState};

const MAX_UPLOAD: usize = 50 * 1024 * 1024;

#[derive(Debug, Serialize, sqlx::FromRow, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct Material {
    pub id: Uuid,
    pub session_id: Uuid,
    pub filename: String,
    #[serde(rename = "type")]
    #[sqlx(rename = "type")]
    pub kind: String,
    pub mime: String,
    pub bytes: i64,
    pub state: String,
    pub error: Option<String>,
    pub page_count: i32,
    pub origin: String,
    pub studio_id: Option<Uuid>,
    pub created_at: DateTime<Utc>,
}

const COLUMNS: &str = "id, session_id, filename, type, mime, bytes, state, error, page_count, origin, studio_id, created_at";

#[derive(Debug, Serialize, sqlx::FromRow, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct Page {
    pub number: i32,
    pub title: String,
    pub ocr_text: String,
    pub ocr_confidence: String,
    pub has_image: bool,
    pub active_from_ms: Option<i64>,
    pub active_to_ms: Option<i64>,
    /// How many note blocks link to this page.
    pub note_block_links: i64,
}

/// Detects the material type from magic bytes (never trusts the extension alone).
pub fn sniff(bytes: &[u8], filename: &str) -> Option<(&'static str, &'static str)> {
    let lower = filename.to_lowercase();
    if bytes.starts_with(b"%PDF") {
        return Some(("pdf", "application/pdf"));
    }
    if bytes.starts_with(b"PK\x03\x04") && lower.ends_with(".pptx") {
        return Some(("pptx", "application/vnd.openxmlformats-officedocument.presentationml.presentation"));
    }
    if bytes.starts_with(b"\x89PNG") {
        return Some(("image", "image/png"));
    }
    if bytes.starts_with(b"\xFF\xD8\xFF") {
        return Some(("image", "image/jpeg"));
    }
    if bytes.len() > 12 && &bytes[..4] == b"RIFF" && &bytes[8..12] == b"WEBP" {
        return Some(("image", "image/webp"));
    }
    None
}

#[utoipa::path(post, path = "/v1/sessions/{id}/materials", tag = "materials", params(("id" = Uuid, Path)),
    request_body(content_type = "multipart/form-data", description = "`file` (PDF, PPTX, PNG/JPEG/WEBP) and optional `kind` = whiteboardPhoto | handout"),
    responses((status = 201, body = Material)))]
pub async fn upload(State(st): State<AppState>, caller: Caller, Path(session_id): Path<Uuid>, mut form: Multipart) -> Result<(StatusCode, Json<Material>), ApiError> {
    {
        let mut conn = st.notes.acquire().await?;
        access::writable_session(&mut conn, &caller, session_id).await?;
    }
    let (mut file, mut name, mut kind_override) = (None::<Vec<u8>>, String::from("material"), None::<String>);
    while let Some(field) = form.next_field().await.map_err(|e| ApiError::bad_request(format!("bad form: {e}")))? {
        match field.name() {
            Some("file") => {
                name = field.file_name().unwrap_or("material").to_string();
                let data = field.bytes().await.map_err(|e| ApiError::bad_request(format!("upload failed: {e}")))?;
                if data.len() > MAX_UPLOAD {
                    return Err(ApiError::new(StatusCode::PAYLOAD_TOO_LARGE, "files over 50 MB need the upload URL flow").with_code("too_large"));
                }
                file = Some(data.to_vec());
            }
            Some("kind") => kind_override = field.text().await.ok(),
            _ => {}
        }
    }
    let bytes = file.ok_or_else(|| ApiError::bad_request("missing file field"))?;
    let (mut kind, mime) = sniff(&bytes, &name).ok_or_else(|| ApiError::bad_request("unsupported file — use PDF, PPTX, PNG, JPEG or WEBP").with_code("unsupported_type"))?;
    if let Some(k) = kind_override.as_deref() {
        match (k, kind) {
            ("whiteboardPhoto", "image") => kind = "whiteboardPhoto",
            ("handout", "pdf" | "image") => kind = "handout",
            _ => {}
        }
    }
    let safe_name: String = name.chars().filter(|c| !matches!(c, '/' | '\\' | '\0')).take(200).collect();
    let id = Uuid::new_v4();
    let ext = safe_name.rsplit('.').next().filter(|e| e.len() <= 5).unwrap_or("bin").to_lowercase();
    let key = format!("{}/{session_id}/materials/{id}/original.{ext}", caller.user_id);
    st.storage.put(&key, &bytes, mime).await.map_err(ApiError::unavailable)?;
    let m = sqlx::query_as::<_, Material>(&format!(
        "INSERT INTO materials (id, session_id, user_id, filename, type, mime, bytes, object_key, state) \
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,'processing') RETURNING {COLUMNS}"
    ))
    .bind(id)
    .bind(session_id)
    .bind(caller.user_id)
    .bind(&safe_name)
    .bind(kind)
    .bind(mime)
    .bind(bytes.len() as i64)
    .bind(&key)
    .fetch_one(&st.notes)
    .await?;
    jobs::enqueue(&st.notes, Some(caller.user_id), "material.process", json!({ "materialId": id, "sessionId": session_id }), Some(&format!("material:{id}"))).await?;
    Ok((StatusCode::CREATED, Json(m)))
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct UploadUrlRequest {
    pub filename: String,
    pub bytes: i64,
}

/// Large files (up to 500 MB) go straight to object storage.
#[utoipa::path(post, path = "/v1/sessions/{id}/materials/upload-url", tag = "materials", params(("id" = Uuid, Path)),
    request_body = UploadUrlRequest, responses((status = 200, description = "{materialId, uploadUrl}"), (status = 409, description = "local storage: use multipart")))]
pub async fn upload_url(State(st): State<AppState>, caller: Caller, Path(session_id): Path<Uuid>, Json(req): Json<UploadUrlRequest>) -> Result<Json<Value>, ApiError> {
    if !(1..=500 * 1024 * 1024).contains(&req.bytes) {
        return Err(ApiError::bad_request("bytes must be 1..500 MB"));
    }
    {
        let mut conn = st.notes.acquire().await?;
        access::writable_session(&mut conn, &caller, session_id).await?;
    }
    let id = Uuid::new_v4();
    let ext = req.filename.rsplit('.').next().filter(|e| e.len() <= 5).unwrap_or("bin").to_lowercase();
    let key = format!("{}/{session_id}/materials/{id}/original.{ext}", caller.user_id);
    let url = st.storage.upload_url(&key, 3600).await.map_err(ApiError::unavailable)?
        .ok_or_else(|| ApiError::new(StatusCode::CONFLICT, "direct upload not available; use multipart").with_code("use_multipart"))?;
    sqlx::query("INSERT INTO materials (id, session_id, user_id, filename, type, mime, bytes, object_key, state) VALUES ($1,$2,$3,$4,'pdf','application/octet-stream',$5,$6,'uploading')")
        .bind(id).bind(session_id).bind(caller.user_id).bind(&req.filename).bind(req.bytes).bind(&key)
        .execute(&st.notes).await?;
    Ok(Json(json!({ "materialId": id, "uploadUrl": url, "expiresIn": 3600 })))
}

#[utoipa::path(post, path = "/v1/materials/{id}/uploaded", tag = "materials", params(("id" = Uuid, Path)), responses((status = 202, body = Material)))]
pub async fn uploaded(State(st): State<AppState>, caller: Caller, Path(id): Path<Uuid>) -> Result<(StatusCode, Json<Material>), ApiError> {
    let key: Option<String> = sqlx::query_scalar("SELECT object_key FROM materials WHERE id = $1 AND user_id = $2 AND state = 'uploading'")
        .bind(id).bind(caller.user_id).fetch_optional(&st.notes).await?.flatten();
    let key = key.ok_or_else(|| ApiError::not_found("pending upload not found"))?;
    let head = st.storage.get(&key).await.map_err(|_| ApiError::bad_request("file not uploaded yet"))?;
    let name: String = sqlx::query_scalar("SELECT filename FROM materials WHERE id = $1").bind(id).fetch_one(&st.notes).await?;
    let (kind, mime) = sniff(&head, &name).ok_or_else(|| ApiError::bad_request("unsupported file").with_code("unsupported_type"))?;
    let m = sqlx::query_as::<_, Material>(&format!("UPDATE materials SET state = 'processing', type = $2, mime = $3, bytes = $4 WHERE id = $1 RETURNING {COLUMNS}"))
        .bind(id).bind(kind).bind(mime).bind(head.len() as i64).fetch_one(&st.notes).await?;
    jobs::enqueue(&st.notes, Some(caller.user_id), "material.process", json!({ "materialId": id, "sessionId": m.session_id }), Some(&format!("material:{id}"))).await?;
    Ok((StatusCode::ACCEPTED, Json(m)))
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct FromStudio {
    pub studio_id: Uuid,
    pub document_id: Uuid,
}

/// Attach a file the student already uploaded to Study Studio (no copy: its
/// indexed text becomes the pages).
#[utoipa::path(post, path = "/v1/sessions/{id}/materials/from-studio", tag = "materials", params(("id" = Uuid, Path)),
    request_body = FromStudio, responses((status = 201, body = Material)))]
pub async fn from_studio(State(st): State<AppState>, caller: Caller, Path(session_id): Path<Uuid>, Json(req): Json<FromStudio>) -> Result<(StatusCode, Json<Material>), ApiError> {
    let studio = st.studio.as_ref().ok_or_else(|| ApiError::unavailable("Study Studio is not connected"))?;
    let vectors = st.studio_vector.as_ref().ok_or_else(|| ApiError::unavailable("Study Studio index is not connected"))?;
    {
        let mut conn = st.notes.acquire().await?;
        access::writable_session(&mut conn, &caller, session_id).await?;
    }
    let doc = sqlx::query("SELECT d.filename, d.mime, d.bytes FROM documents d JOIN studios s ON s.id = d.studio_id \
                           WHERE d.id = $1 AND d.studio_id = $2 AND s.user_id = $3")
        .bind(req.document_id).bind(req.studio_id).bind(caller.user_id).fetch_optional(studio).await?
        .ok_or_else(|| ApiError::not_found("Study Studio document not found"))?;
    let chunks: Vec<String> = sqlx::query_scalar("SELECT content FROM chunks WHERE document_id = $1 AND user_id = $2 ORDER BY ordinal")
        .bind(req.document_id).bind(caller.user_id).fetch_all(vectors).await?;
    let filename: String = doc.get("filename");
    // ~1500 characters per page.
    let mut pages: Vec<String> = Vec::new();
    for c in chunks {
        match pages.last_mut() {
            Some(p) if p.len() + c.len() < 1500 => { p.push('\n'); p.push_str(&c); }
            _ => pages.push(c),
        }
    }
    let mut tx = st.notes.begin().await?;
    let m = sqlx::query_as::<_, Material>(&format!(
        "INSERT INTO materials (session_id, user_id, filename, type, mime, bytes, state, page_count, origin, studio_id, studio_document_id) \
         VALUES ($1,$2,$3,'handout',$4,$5,'done',$6,'studio',$7,$8) RETURNING {COLUMNS}"))
        .bind(session_id).bind(caller.user_id).bind(&filename).bind(doc.get::<String, _>("mime")).bind(doc.get::<i32, _>("bytes") as i64)
        .bind(pages.len() as i32).bind(req.studio_id).bind(req.document_id).fetch_one(&mut *tx).await?;
    for (i, text) in pages.iter().enumerate() {
        sqlx::query("INSERT INTO material_pages (material_id, number, title, ocr_text, ocr_confidence) VALUES ($1,$2,$3,$4,'high')")
            .bind(m.id).bind(i as i32 + 1).bind(first_line(text)).bind(text).execute(&mut *tx).await?;
    }
    jobs::enqueue_tx(&mut tx, Some(caller.user_id), "embed.session", json!({ "sessionId": session_id }), None).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(m)))
}

fn first_line(text: &str) -> String {
    text.lines().map(str::trim).find(|l| !l.is_empty()).map(|l| l.chars().take(120).collect()).unwrap_or_default()
}

#[utoipa::path(get, path = "/v1/sessions/{id}/materials", tag = "materials", params(("id" = Uuid, Path)), responses((status = 200, body = Vec<Material>)))]
pub async fn list(State(st): State<AppState>, caller: Caller, Path(session_id): Path<Uuid>) -> Result<Json<Vec<Material>>, ApiError> {
    let mut conn = st.notes.acquire().await?;
    access::session(&mut conn, &caller, session_id).await?;
    Ok(Json(sqlx::query_as::<_, Material>(&format!("SELECT {COLUMNS} FROM materials WHERE session_id = $1 AND deleted_at IS NULL ORDER BY created_at"))
        .bind(session_id).fetch_all(&mut *conn).await?))
}

async fn owned(conn: &mut PgConnection, caller: &Caller, id: Uuid) -> Result<(Uuid, String), ApiError> {
    let row: Option<(Uuid, String)> = sqlx::query_as("SELECT m.session_id, m.filename FROM materials m JOIN sessions s ON s.id = m.session_id \
        WHERE m.id = $1 AND m.user_id = $2 AND m.deleted_at IS NULL AND s.deleted_at IS NULL")
        .bind(id).bind(caller.user_id).fetch_optional(conn).await?;
    row.ok_or_else(|| ApiError::not_found("material not found"))
}

#[utoipa::path(get, path = "/v1/materials/{id}/pages", tag = "materials", params(("id" = Uuid, Path)), responses((status = 200, body = Vec<Page>)))]
pub async fn pages(State(st): State<AppState>, caller: Caller, Path(id): Path<Uuid>) -> Result<Json<Vec<Page>>, ApiError> {
    let mut conn = st.notes.acquire().await?;
    owned(&mut conn, &caller, id).await?;
    Ok(Json(sqlx::query_as::<_, Page>(
        "SELECT p.number, p.title, p.ocr_text, p.ocr_confidence, p.render_key IS NOT NULL AS has_image, p.active_from_ms, p.active_to_ms, \
             (SELECT count(*) FROM links l WHERE l.to_kind = 'slide' AND l.to_id = p.material_id::text || ':' || p.number) AS note_block_links \
         FROM material_pages p WHERE p.material_id = $1 ORDER BY p.number")
        .bind(id).fetch_all(&mut *conn).await?))
}

#[utoipa::path(get, path = "/v1/materials/{id}/pages/{n}/image", tag = "materials", params(("id" = Uuid, Path), ("n" = i32, Path)),
    responses((status = 200, description = "{url, expiresIn}")))]
pub async fn page_image(State(st): State<AppState>, caller: Caller, Path((id, n)): Path<(Uuid, i32)>) -> Result<Json<Value>, ApiError> {
    let mut conn = st.notes.acquire().await?;
    owned(&mut conn, &caller, id).await?;
    let key: Option<String> = sqlx::query_scalar("SELECT render_key FROM material_pages WHERE material_id = $1 AND number = $2")
        .bind(id).bind(n).fetch_optional(&mut *conn).await?.flatten();
    let key = key.ok_or_else(|| ApiError::not_found("no image for this page"))?;
    Ok(Json(json!({ "url": st.storage.url(&key, 900).await.map_err(ApiError::unavailable)?, "expiresIn": 900 })))
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct LinkBlock {
    pub block_id: Uuid,
}

#[utoipa::path(post, path = "/v1/materials/{id}/pages/{n}/link", tag = "materials", params(("id" = Uuid, Path), ("n" = i32, Path)),
    request_body = LinkBlock, responses((status = 204)))]
pub async fn link(State(st): State<AppState>, caller: Caller, Path((id, n)): Path<(Uuid, i32)>, Json(req): Json<LinkBlock>) -> Result<StatusCode, ApiError> {
    let mut conn = st.notes.acquire().await?;
    let (session_id, _) = owned(&mut conn, &caller, id).await?;
    let ok: Option<Uuid> = sqlx::query_scalar("SELECT id FROM blocks WHERE id = $1 AND session_id = $2 AND deleted_at IS NULL")
        .bind(req.block_id).bind(session_id).fetch_optional(&mut *conn).await?;
    ok.ok_or_else(|| ApiError::not_found("block not found"))?;
    sqlx::query("INSERT INTO links (session_id, user_id, from_kind, from_id, to_kind, to_id) VALUES ($1,$2,'block',$3,'slide',$4) ON CONFLICT DO NOTHING")
        .bind(session_id).bind(caller.user_id).bind(req.block_id.to_string()).bind(format!("{id}:{n}")).execute(&mut *conn).await?;
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ActivePage {
    /// Lecture time the slide came up.
    pub at_ms: i64,
}

/// Follow Lecture: marks the slide on screen now (closes the previous one).
#[utoipa::path(post, path = "/v1/materials/{id}/pages/{n}/active", tag = "materials", params(("id" = Uuid, Path), ("n" = i32, Path)),
    request_body = ActivePage, responses((status = 204)))]
pub async fn set_active(State(st): State<AppState>, caller: Caller, Path((id, n)): Path<(Uuid, i32)>, Json(req): Json<ActivePage>) -> Result<StatusCode, ApiError> {
    let mut tx = st.notes.begin().await?;
    let (session_id, _) = owned(&mut tx, &caller, id).await?;
    sqlx::query("UPDATE material_pages p SET active_to_ms = $2 FROM materials m WHERE m.id = p.material_id AND m.session_id = $1 \
                 AND p.active_from_ms IS NOT NULL AND p.active_to_ms IS NULL")
        .bind(session_id).bind(req.at_ms).execute(&mut *tx).await?;
    let res = sqlx::query("UPDATE material_pages SET active_from_ms = $3, active_to_ms = NULL WHERE material_id = $1 AND number = $2")
        .bind(id).bind(n).bind(req.at_ms).execute(&mut *tx).await?;
    if res.rows_affected() == 0 {
        return Err(ApiError::not_found("page not found"));
    }
    tx.commit().await?;
    st.hub.session(session_id, Event::new("slide.changed", json!({ "materialId": id, "page": n, "atMs": req.at_ms }), None)).await;
    Ok(StatusCode::NO_CONTENT)
}

#[utoipa::path(delete, path = "/v1/materials/{id}", tag = "materials", params(("id" = Uuid, Path)), responses((status = 204)))]
pub async fn delete(State(st): State<AppState>, caller: Caller, Path(id): Path<Uuid>) -> Result<StatusCode, ApiError> {
    let mut conn = st.notes.acquire().await?;
    let (session_id, _) = owned(&mut conn, &caller, id).await?;
    sqlx::query("UPDATE materials SET deleted_at = now() WHERE id = $1").bind(id).execute(&mut *conn).await?;
    jobs::enqueue(&st.notes, Some(caller.user_id), "embed.session", json!({ "sessionId": session_id }), None).await?;
    Ok(StatusCode::NO_CONTENT)
}

/// `"{materialId}:{page}"` → parts.
pub fn parse_page_ref(s: &str) -> Result<(Uuid, i32), ApiError> {
    let (m, p) = s.split_once(':').ok_or_else(|| ApiError::bad_request("slide ref must be materialId:page"))?;
    Ok((Uuid::parse_str(m).map_err(|_| ApiError::bad_request("bad material id"))?, p.parse().map_err(|_| ApiError::bad_request("bad page number"))?))
}

/// (title, text, filename) of a page in the caller's session.
pub async fn page_text(conn: &mut PgConnection, caller: &Caller, session_id: Uuid, material: Uuid, page: i32) -> Result<(String, String, String), ApiError> {
    let row = sqlx::query("SELECT p.title, p.ocr_text, m.filename FROM material_pages p JOIN materials m ON m.id = p.material_id \
                           WHERE p.material_id = $1 AND p.number = $2 AND m.session_id = $3 AND m.user_id = $4 AND m.deleted_at IS NULL")
        .bind(material).bind(page).bind(session_id).bind(caller.user_id).fetch_optional(conn).await?
        .ok_or_else(|| ApiError::not_found("slide not found"))?;
    Ok((row.get("title"), row.get("ocr_text"), row.get("filename")))
}

// ── processing ──────────────────────────────────────────────────────────────

struct Extracted {
    text: String,
    render: Option<Vec<u8>>,
    confidence: &'static str,
}

pub async fn job_process(st: AppState, job: Job) -> JobResult {
    let id: Uuid = serde_json::from_value(job.payload["materialId"].clone()).map_err(|e| e.to_string())?;
    let row = sqlx::query("SELECT session_id, user_id, type, mime, object_key FROM materials WHERE id = $1 AND deleted_at IS NULL")
        .bind(id).fetch_optional(&st.notes).await.map_err(|e| e.to_string())?;
    let Some(row) = row else { return Ok(()) };
    let (session_id, user_id, kind, mime, key): (Uuid, Uuid, String, String, Option<String>) =
        (row.get("session_id"), row.get("user_id"), row.get("type"), row.get("mime"), row.get("object_key"));
    let Some(key) = key else { return Ok(()) };
    let bytes = st.storage.get(&key).await?;

    let result: Result<Vec<Extracted>, String> = match kind.as_str() {
        "pdf" | "handout" if bytes.starts_with(b"%PDF") => extract_pdf(&bytes).await,
        "pptx" => extract_pptx(&bytes).await,
        _ => Ok(vec![Extracted { text: String::new(), render: Some(bytes.clone()), confidence: "low" }]),
    };
    let mut pages = match result {
        Ok(p) => p,
        Err(e) => {
            sqlx::query("UPDATE materials SET state = 'fail', error = $2 WHERE id = $1").bind(id).bind(&e).execute(&st.notes).await.map_err(|e| e.to_string())?;
            st.hub.session(session_id, Event::new("job.progress", json!({ "kind": "material.failed", "materialId": id, "error": e }), None)).await;
            return Ok(());
        }
    };
    // Pages with no text but an image (scans, photos): vision OCR.
    for p in pages.iter_mut().filter(|p| p.text.trim().is_empty() && p.render.is_some()) {
        let img = p.render.as_ref().expect("render");
        let image_mime = if img.starts_with(b"\xFF\xD8\xFF") { "image/jpeg" } else if img.starts_with(b"RIFF") { "image/webp" } else { "image/png" };
        let _ = &mime;
        if let Ok(text) = vision_ocr(&st, img, image_mime).await {
            p.text = text;
            p.confidence = if p.text.is_empty() { "low" } else { "medium" };
        }
    }
    let mut tx = st.notes.begin().await.map_err(|e| e.to_string())?;
    sqlx::query("DELETE FROM material_pages WHERE material_id = $1").bind(id).execute(&mut *tx).await.map_err(|e| e.to_string())?;
    for (i, p) in pages.iter().enumerate() {
        let n = i as i32 + 1;
        let render_key = match &p.render {
            Some(img) => {
                let k = format!("{user_id}/{session_id}/materials/{id}/page-{n:04}.png");
                let stored = if kind == "pdf" || kind == "pptx" || kind == "handout" { st.storage.put(&k, img, "image/png").await.map(|_| k) } else { Ok(key.clone()) };
                stored.ok()
            }
            None => None,
        };
        sqlx::query("INSERT INTO material_pages (material_id, number, title, ocr_text, ocr_confidence, render_key) VALUES ($1,$2,$3,$4,$5,$6)")
            .bind(id).bind(n).bind(first_line(&p.text)).bind(&p.text).bind(p.confidence).bind(render_key)
            .execute(&mut *tx).await.map_err(|e| e.to_string())?;
    }
    sqlx::query("UPDATE materials SET state = 'done', page_count = $2, error = NULL WHERE id = $1")
        .bind(id).bind(pages.len() as i32).execute(&mut *tx).await.map_err(|e| e.to_string())?;
    jobs::enqueue_tx(&mut tx, Some(user_id), "embed.session", json!({ "sessionId": session_id }), None).await.map_err(|e| e.to_string())?;
    tx.commit().await.map_err(|e| e.to_string())?;
    st.hub.session(session_id, Event::new("job.progress", json!({ "kind": "material.done", "materialId": id, "pages": pages.len() }), None)).await;
    Ok(())
}

async fn extract_pdf(bytes: &[u8]) -> Result<Vec<Extracted>, String> {
    let owned = bytes.to_vec();
    let texts = tokio::task::spawn_blocking(move || pdf_extract::extract_text_from_mem_by_pages(&owned))
        .await
        .map_err(|e| e.to_string())?
        .map_err(|e| format!("could not read PDF: {e}"))?;
    let renders = render_pdf(bytes).await.unwrap_or_default();
    Ok(texts
        .into_iter()
        .enumerate()
        .map(|(i, t)| {
            let text = t.split_whitespace().collect::<Vec<_>>().join(" ");
            Extracted { confidence: if text.is_empty() { "low" } else { "high" }, text, render: renders.get(i).cloned() }
        })
        .collect())
}

/// Page PNGs via poppler's `pdftoppm` (none when it isn't installed).
async fn render_pdf(bytes: &[u8]) -> Option<Vec<Vec<u8>>> {
    let dir = temp_dir();
    tokio::fs::create_dir_all(&dir).await.ok()?;
    let input = dir.join("in.pdf");
    tokio::fs::write(&input, bytes).await.ok()?;
    let ok = tokio::process::Command::new("pdftoppm")
        .args(["-png", "-r", "72", "-l", "300"])
        .arg(&input)
        .arg(dir.join("page"))
        .status()
        .await
        .ok()?
        .success();
    let mut out = Vec::new();
    if ok {
        let mut names: Vec<PathBuf> = std::fs::read_dir(&dir).ok()?.filter_map(|e| e.ok().map(|e| e.path())).filter(|p| p.extension().is_some_and(|x| x == "png")).collect();
        names.sort();
        for n in names {
            out.push(tokio::fs::read(n).await.ok()?);
        }
    }
    let _ = tokio::fs::remove_dir_all(&dir).await;
    ok.then_some(out)
}

fn temp_dir() -> PathBuf {
    std::env::temp_dir().join(format!("octonotes-material-{}", Uuid::new_v4()))
}

/// Slide text from the PPTX XML (`ppt/slides/slideN.xml`, `<a:t>` runs), in
/// slide order; renders via LibreOffice → PDF → pdftoppm when available.
async fn extract_pptx(bytes: &[u8]) -> Result<Vec<Extracted>, String> {
    let owned = bytes.to_vec();
    let texts = tokio::task::spawn_blocking(move || -> Result<Vec<String>, String> {
        let mut zip = zip::ZipArchive::new(std::io::Cursor::new(owned)).map_err(|e| format!("not a PPTX: {e}"))?;
        let mut slides: Vec<(u32, String)> = Vec::new();
        for i in 0..zip.len() {
            let mut f = zip.by_index(i).map_err(|e| e.to_string())?;
            let name = f.name().to_string();
            let Some(num) = name.strip_prefix("ppt/slides/slide").and_then(|r| r.strip_suffix(".xml")).and_then(|n| n.parse::<u32>().ok()) else { continue };
            let mut xml = String::new();
            std::io::Read::read_to_string(&mut f, &mut xml).map_err(|e| e.to_string())?;
            slides.push((num, slide_text(&xml)));
        }
        slides.sort_by_key(|s| s.0);
        Ok(slides.into_iter().map(|s| s.1).collect())
    })
    .await
    .map_err(|e| e.to_string())??;
    let renders = render_pptx(bytes).await.unwrap_or_default();
    Ok(texts
        .into_iter()
        .enumerate()
        .map(|(i, text)| Extracted { confidence: if text.is_empty() { "low" } else { "high" }, text, render: renders.get(i).cloned() })
        .collect())
}

/// Text runs of one slide, one line per paragraph.
pub fn slide_text(xml: &str) -> String {
    use quick_xml::events::Event as X;
    let mut reader = quick_xml::Reader::from_str(xml);
    let (mut out, mut line, mut in_t) = (Vec::<String>::new(), String::new(), false);
    loop {
        match reader.read_event() {
            Ok(X::Start(e)) if e.name().as_ref() == b"a:t" => in_t = true,
            Ok(X::End(e)) if e.name().as_ref() == b"a:t" => in_t = false,
            Ok(X::End(e)) if e.name().as_ref() == b"a:p" => {
                if !line.trim().is_empty() {
                    out.push(line.trim().to_string());
                }
                line.clear();
            }
            Ok(X::Text(t)) if in_t => line.push_str(&t.unescape().unwrap_or_default()),
            Ok(X::Eof) | Err(_) => break,
            _ => {}
        }
    }
    if !line.trim().is_empty() {
        out.push(line.trim().to_string());
    }
    out.join("\n")
}

async fn render_pptx(bytes: &[u8]) -> Option<Vec<Vec<u8>>> {
    let dir = temp_dir();
    tokio::fs::create_dir_all(&dir).await.ok()?;
    let input = dir.join("in.pptx");
    tokio::fs::write(&input, bytes).await.ok()?;
    let ok = tokio::process::Command::new("soffice")
        .args(["--headless", "--convert-to", "pdf", "--outdir"])
        .arg(&dir)
        .arg(&input)
        .status()
        .await
        .ok()?
        .success();
    let pdf = if ok { tokio::fs::read(dir.join("in.pdf")).await.ok() } else { None };
    let _ = tokio::fs::remove_dir_all(&dir).await;
    render_pdf(&pdf?).await
}

async fn vision_ocr(st: &AppState, image: &[u8], mime: &str) -> Result<String, String> {
    let llm = Llm::for_role(st, Role::Vision).await;
    let b64 = base64::engine::general_purpose::STANDARD.encode(image);
    let messages = vec![Message::user_with_image(
        "Transcribe all readable text in this lecture slide / board photo, top to bottom. Reply with JSON: {\"text\": string}.",
        mime,
        &b64,
    )];
    let (text, _) = llm
        .complete(&messages, &ChatOptions { temperature: Some(0.0), max_tokens: Some(1500), json: true }, || json!({ "text": "" }).to_string())
        .await
        .map_err(|e| e.message)?;
    Ok(parse_json_loose(&text).and_then(|v| v["text"].as_str().map(str::to_string)).unwrap_or_default())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pptx_slide_text() {
        let xml = r#"<p:sld><p:txBody><a:p><a:r><a:t>Electron Transport</a:t></a:r><a:r><a:t> Chain</a:t></a:r></a:p><a:p><a:r><a:t>O&#8322; is the final acceptor</a:t></a:r></a:p></p:txBody></p:sld>"#;
        assert_eq!(slide_text(xml), "Electron Transport Chain\nO₂ is the final acceptor");
    }

    #[test]
    fn sniffing() {
        assert_eq!(sniff(b"%PDF-1.7", "x.pdf").unwrap().0, "pdf");
        assert_eq!(sniff(b"\x89PNG\r\n", "a.png").unwrap().0, "image");
        assert!(sniff(b"MZ\x90", "virus.pdf").is_none());
        assert!(sniff(b"PK\x03\x04", "archive.zip").is_none());
    }
}

//! The project's document, as the agent writes it.
//!
//! While a run writes, the document is locked to that run: `locked_by_run`
//! is set, and every write here checks it. A snapshot goes into
//! `document_versions` before the first change, so an agent edit can be undone.
//! Editor saves and restores are in `routes::documents`.

use serde_json::Value;
use sqlx::{PgConnection, PgPool};
use uuid::Uuid;

use crate::live_docs::LiveDocs;

/// Why a document write did not happen.
#[derive(Debug)]
pub enum DocError {
    /// Another run holds the lock, or this run lost it.
    Locked,
    Db(sqlx::Error),
}

impl From<sqlx::Error> for DocError {
    fn from(e: sqlx::Error) -> Self {
        DocError::Db(e)
    }
}

/// The citation styles the document knows. Anything else reads as APA.
pub fn style_key(citation_style: &str) -> &'static str {
    match citation_style.trim().to_lowercase().as_str() {
        "mla" => "mla",
        "chicago" => "chicago",
        "harvard" => "harvard",
        "ieee" => "ieee",
        "none" => "none",
        _ => "apa",
    }
}

/// Locks the document to `run_id` and snapshots it as it stands.
pub async fn begin_agent_write(
    db: &PgPool,
    project_id: Uuid,
    run_id: Uuid,
    reason: &str,
) -> Result<(), DocError> {
    let mut tx = db.begin().await?;
    let locked_by: Option<Uuid> =
        sqlx::query_scalar("SELECT locked_by_run FROM documents WHERE project_id = $1 FOR UPDATE")
            .bind(project_id)
            .fetch_one(&mut *tx)
            .await?;
    if locked_by.is_some_and(|holder| holder != run_id) {
        return Err(DocError::Locked);
    }

    snapshot(&mut tx, project_id, reason).await?;
    sqlx::query("UPDATE documents SET locked_by_run = $2 WHERE project_id = $1")
        .bind(project_id)
        .bind(run_id)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;
    Ok(())
}

/// Saves the document as it stands into `document_versions`.
pub async fn snapshot(
    conn: &mut PgConnection,
    project_id: Uuid,
    reason: &str,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO document_versions (project_id, rev, reason, snapshot)          SELECT project_id, rev, $2, to_jsonb(documents) - 'locked_by_run'          FROM documents WHERE project_id = $1",
    )
    .bind(project_id)
    .bind(reason)
    .execute(conn)
    .await?;
    Ok(())
}

/// What the agent sets when it saves. `None` leaves a column as it is.
#[derive(Default)]
pub struct AgentSave<'a> {
    pub body: Option<&'a str>,
    pub bibliography: Option<&'a str>,
    pub title: Option<&'a str>,
    pub style: Option<&'a str>,
    pub sources: Option<&'a Value>,
    pub fields: Option<&'a Value>,
}

/// Saves the agent's text. Returns the new `rev` and the body's word count.
/// The run must hold the lock.
pub async fn save_agent(
    db: &PgPool,
    project_id: Uuid,
    run_id: Uuid,
    save: AgentSave<'_>,
) -> Result<(i64, i64), DocError> {
    let mut tx = db.begin().await?;
    // A new body replaces any rich text the editor had stored for the old one.
    let saved: Option<(i64, String)> = sqlx::query_as(
        "UPDATE documents SET \
             body = COALESCE($3, body), \
             delta = CASE WHEN $3 IS NULL THEN delta ELSE NULL END, \
             bibliography = COALESCE($4, bibliography), \
             title = COALESCE($5, title), \
             style = COALESCE($6, style), \
             sources = COALESCE($7, sources), \
             fields = COALESCE($8, fields), \
             rev = rev + 1, updated_at = now() \
         WHERE project_id = $1 AND locked_by_run = $2 \
         RETURNING rev, body",
    )
    .bind(project_id)
    .bind(run_id)
    .bind(save.body)
    .bind(save.bibliography)
    .bind(save.title)
    .bind(save.style)
    .bind(save.sources)
    .bind(save.fields)
    .fetch_optional(&mut *tx)
    .await?;
    let (rev, body) = saved.ok_or(DocError::Locked)?;

    let words = crate::pricing::count_words(&body);
    sqlx::query("UPDATE projects SET word_count = $2, updated_at = now() WHERE id = $1")
        .bind(project_id)
        .bind(words as i32)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;
    Ok((rev, words))
}

/// Releases the run's lock, if it holds it, and tells open editors.
pub async fn unlock(
    db: &PgPool,
    docs: &LiveDocs,
    project_id: Uuid,
    run_id: Uuid,
) -> Result<(), sqlx::Error> {
    let released = sqlx::query(
        "UPDATE documents SET locked_by_run = NULL WHERE project_id = $1 AND locked_by_run = $2",
    )
    .bind(project_id)
    .bind(run_id)
    .execute(db)
    .await?
    .rows_affected();
    if released > 0 {
        docs.changed(project_id);
    }
    Ok(())
}

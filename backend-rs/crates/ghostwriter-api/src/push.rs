//! Push notifications: a run tells the user's phones when it needs them and
//! nobody is watching it.
//!
//! Sent through Firebase Cloud Messaging (`octo_common::push`).

use std::collections::BTreeMap;

use uuid::Uuid;

pub use octo_common::push::{FcmPusher, NoPusher, Notice, PushError, Pusher};

use crate::AppState;

/// The Android notification channel the app creates.
pub const ANDROID_CHANNEL: &str = "ghostwriter";
/// Notification text is cut to this many characters.
const BODY_LIMIT: usize = 180;

/// What happened in a run that is worth a notification.
pub enum RunNews<'a> {
    /// The agent asked something and waits.
    Question(&'a str),
    Finished,
    Failed(&'a str),
}

fn shorten(text: &str) -> String {
    let text = text.trim();
    if text.chars().count() <= BODY_LIMIT {
        return text.to_string();
    }
    let cut: String = text.chars().take(BODY_LIMIT - 1).collect();
    format!("{}…", cut.trim_end())
}

/// Tells the project owner's devices about `news`, in the background. The
/// caller decides whether anyone is watching; this only delivers.
pub fn notify_run(st: &AppState, project_id: Uuid, run_id: Uuid, news: RunNews<'_>) {
    if !st.pusher.enabled() {
        return;
    }
    let (kind, body) = match news {
        RunNews::Question(question) => ("question", shorten(question)),
        RunNews::Finished => ("done", "GhostWriter has finished. Tap to open.".to_string()),
        RunNews::Failed(message) => ("fatal", shorten(&format!("GhostWriter stopped. {message}"))),
    };
    let st = st.clone();
    tokio::spawn(async move {
        if let Err(error) = deliver(&st, project_id, run_id, kind, body).await {
            tracing::warn!(%run_id, %error, "push: could not look up the devices");
        }
    });
}

async fn deliver(
    st: &AppState,
    project_id: Uuid,
    run_id: Uuid,
    kind: &str,
    body: String,
) -> Result<(), sqlx::Error> {
    let Some((user_id, title)): Option<(Uuid, String)> =
        sqlx::query_as("SELECT user_id, title FROM projects WHERE id = $1")
            .bind(project_id)
            .fetch_optional(&st.db)
            .await?
    else {
        return Ok(());
    };
    let devices: Vec<(Uuid, String)> =
        sqlx::query_as("SELECT id, token FROM devices WHERE user_id = $1 ORDER BY updated_at")
            .bind(user_id)
            .fetch_all(&st.db)
            .await?;
    if devices.is_empty() {
        return Ok(());
    }

    let notice = Notice {
        title,
        body,
        data: BTreeMap::from([
            ("type".to_string(), kind.to_string()),
            ("projectId".to_string(), project_id.to_string()),
            ("runId".to_string(), run_id.to_string()),
        ]),
        ..Default::default()
    };
    for (device_id, token) in devices {
        match st.pusher.send(&token, &notice).await {
            Ok(()) => {}
            Err(PushError::Unregistered) => {
                sqlx::query("DELETE FROM devices WHERE id = $1 AND token = $2")
                    .bind(device_id)
                    .bind(&token)
                    .execute(&st.db)
                    .await?;
            }
            Err(PushError::Other(error)) => {
                tracing::warn!(%run_id, %device_id, %error, "push: not delivered");
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn long_text_is_cut_with_an_ellipsis() {
        assert_eq!(shorten("  Short.  "), "Short.");
        let long = "word ".repeat(100);
        let cut = shorten(&long);
        assert_eq!(cut.chars().count(), BODY_LIMIT);
        assert!(cut.ends_with("word…"));
    }
}

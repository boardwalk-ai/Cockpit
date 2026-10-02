//! Live text for the read-only editor.
//!
//! While the agent writes, the text it has streamed so far is held here, ahead
//! of what is saved in `documents`. An editor that opens the document stream
//! gets that text in its first snapshot and every later piece as a delta, so it
//! shows the essay as it is written. A client with only the chat open never
//! subscribes, and the writer's sends go nowhere.
//!
//! Any other change to a document (a write ending, an editor save, a restore)
//! is announced as [`DocSignal::Changed`]; the stream re-reads the document and
//! sends it whole.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use tokio::sync::broadcast;
use uuid::Uuid;

#[derive(Clone, Debug)]
pub enum DocSignal {
    /// A write began. The body now starts from this text.
    Began { body: String },
    /// Text appended to the body.
    Delta(String),
    /// The text so far is saved at this `rev`.
    Committed(i64),
    /// The saved document changed; read it again.
    Changed,
}

struct Entry {
    signals: broadcast::Sender<DocSignal>,
    /// The body as streamed so far, while a write is in progress.
    body: Option<String>,
}

impl Entry {
    fn new() -> Self {
        Self {
            signals: broadcast::channel(256).0,
            body: None,
        }
    }

    fn idle(&self) -> bool {
        self.body.is_none() && self.signals.receiver_count() == 0
    }
}

/// The documents this process is streaming or being watched on, by project.
#[derive(Clone, Default)]
pub struct LiveDocs {
    entries: Arc<Mutex<HashMap<Uuid, Entry>>>,
}

impl LiveDocs {
    /// A receiver for the document's signals from now on, and the body a write
    /// has streamed so far (`None` when no write is in progress). Taken
    /// together, so no delta falls between the two.
    pub fn subscribe(&self, project_id: Uuid) -> (broadcast::Receiver<DocSignal>, Option<String>) {
        let mut entries = self.entries.lock().unwrap();
        // Forget documents nobody is writing or watching any more.
        entries.retain(|_, entry| !entry.idle());
        let entry = entries.entry(project_id).or_insert_with(Entry::new);
        (entry.signals.subscribe(), entry.body.clone())
    }

    /// A write is starting on an empty body.
    pub fn begin(&self, project_id: Uuid) {
        let mut entries = self.entries.lock().unwrap();
        let entry = entries.entry(project_id).or_insert_with(Entry::new);
        entry.body = Some(String::new());
        // No subscribers is fine: the body is kept for whoever comes next.
        let _ = entry.signals.send(DocSignal::Began {
            body: String::new(),
        });
    }

    /// Appends text a write has produced.
    pub fn append(&self, project_id: Uuid, text: &str) {
        if text.is_empty() {
            return;
        }
        let mut entries = self.entries.lock().unwrap();
        let Some(entry) = entries.get_mut(&project_id) else {
            return;
        };
        let Some(body) = entry.body.as_mut() else {
            return;
        };
        body.push_str(text);
        let _ = entry.signals.send(DocSignal::Delta(text.to_string()));
    }

    /// The write's text so far is saved at `rev`.
    pub fn committed(&self, project_id: Uuid, rev: i64) {
        if let Some(entry) = self.entries.lock().unwrap().get(&project_id) {
            let _ = entry.signals.send(DocSignal::Committed(rev));
        }
    }

    /// The saved document changed. Ends any write's live text: from here on
    /// the database is the whole truth.
    pub fn changed(&self, project_id: Uuid) {
        let mut entries = self.entries.lock().unwrap();
        let Some(entry) = entries.get_mut(&project_id) else {
            return;
        };
        entry.body = None;
        let _ = entry.signals.send(DocSignal::Changed);
        if entry.idle() {
            entries.remove(&project_id);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_late_subscriber_gets_the_text_so_far_then_the_rest() {
        let docs = LiveDocs::default();
        let project = Uuid::new_v4();
        docs.begin(project);
        docs.append(project, "Coastal ");
        docs.append(project, "cities");

        let (mut signals, body) = docs.subscribe(project);
        assert_eq!(body.as_deref(), Some("Coastal cities"));

        docs.append(project, " live");
        docs.committed(project, 3);
        docs.changed(project);
        assert!(matches!(signals.try_recv(), Ok(DocSignal::Delta(t)) if t == " live"));
        assert!(matches!(signals.try_recv(), Ok(DocSignal::Committed(3))));
        assert!(matches!(signals.try_recv(), Ok(DocSignal::Changed)));

        // The write is over: a new subscriber reads the database instead.
        assert_eq!(docs.subscribe(project).1, None);
    }

    #[test]
    fn nothing_is_kept_for_a_document_nobody_writes_or_watches() {
        let docs = LiveDocs::default();
        let project = Uuid::new_v4();
        docs.append(project, "ignored: no write in progress");
        docs.changed(project);
        assert!(docs.entries.lock().unwrap().is_empty());

        let (signals, _) = docs.subscribe(project);
        drop(signals);
        docs.subscribe(Uuid::new_v4());
        assert!(!docs.entries.lock().unwrap().contains_key(&project));
    }
}

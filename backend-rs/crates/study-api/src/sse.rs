//! The API speaks `text/event-stream`: named events whose data is JSON
//! (`item`, `data`, `delta`, `citations`, `progress`, `ok`, then `done`, or
//! `error`). Same names and shapes as the Python service.

use std::convert::Infallible;

use axum::response::sse::{Event, KeepAlive, Sse};
use futures::stream::{self, Stream};
use serde::Serialize;
use serde_json::json;

pub type SseStream = Sse<Box<dyn Stream<Item = Result<Event, Infallible>> + Send + Unpin>>;

pub fn event(name: &str, data: &impl Serialize) -> Event {
    Event::default()
        .event(name)
        .data(serde_json::to_string(data).unwrap_or_else(|_| "{}".into()))
}

pub fn done() -> Event {
    Event::default().event("done").data("{}")
}

pub fn error(message: impl Into<String>) -> Event {
    Event::default()
        .event("error")
        .data(json!({ "message": message.into() }).to_string())
}

/// An error with machine-readable fields (`message` plus e.g. `code`).
pub fn error_data(data: &serde_json::Value) -> Event {
    Event::default().event("error").data(data.to_string())
}

/// A finished list of events as a response.
pub fn events(list: Vec<Event>) -> SseStream {
    let s = stream::iter(list.into_iter().map(Ok));
    Sse::new(Box::new(s) as Box<dyn Stream<Item = _> + Send + Unpin>).keep_alive(KeepAlive::default())
}

/// One payload, then done.
pub fn one(data: &impl Serialize) -> SseStream {
    events(vec![event("data", data), done()])
}

/// The write acknowledgement: `ok`, then done.
pub fn ack() -> SseStream {
    events(vec![event("ok", &json!({ "ok": true })), done()])
}

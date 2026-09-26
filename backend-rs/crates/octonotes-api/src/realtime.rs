//! Live fan-out of session events to every connected device.
//!
//! Inside one process a `tokio::sync::broadcast` channel per session carries
//! events to its WebSockets. With `REDIS_URL` set, every publish also goes to
//! Redis channel `session:{id}` and each instance relays what other instances
//! published, so any instance can serve any device. Nothing lives only here:
//! clients catch up from `notes_db` with `?sinceRev=` after a reconnect.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use serde::{Deserialize, Serialize};
use serde_json::Value;
use tokio::sync::broadcast;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Event {
    #[serde(rename = "type")]
    pub kind: String,
    pub data: Value,
    /// Layer revision after the change, when the event carries one.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rev: Option<i64>,
    /// Instance that published it (drops our own echo from Redis).
    #[serde(default, skip_serializing)]
    pub origin: String,
}

impl Event {
    pub fn new(kind: &str, data: Value, rev: Option<i64>) -> Self {
        Self { kind: kind.to_string(), data, rev, origin: String::new() }
    }
}

type Channels = Arc<Mutex<HashMap<String, broadcast::Sender<Event>>>>;

#[derive(Clone)]
pub struct Hub {
    channels: Channels,
    instance: String,
    redis: Option<RedisPublisher>,
}

#[derive(Clone)]
pub struct RedisPublisher {
    pub(crate) conn: redis::aio::ConnectionManager,
}

impl Hub {
    pub fn local() -> Self {
        Self {
            channels: Arc::new(Mutex::new(HashMap::new())),
            instance: Uuid::new_v4().to_string(),
            redis: None,
        }
    }

    /// Hub that also publishes to / relays from Redis.
    pub async fn with_redis(url: &str) -> Result<Self, redis::RedisError> {
        let client = redis::Client::open(url)?;
        let conn = redis::aio::ConnectionManager::new(client.clone()).await?;
        let mut hub = Self::local();
        hub.redis = Some(RedisPublisher { conn });
        hub.spawn_relay(client);
        Ok(hub)
    }

    fn sender(&self, channel: &str) -> broadcast::Sender<Event> {
        let mut map = self.channels.lock().expect("hub lock");
        map.entry(channel.to_string())
            .or_insert_with(|| broadcast::channel(512).0)
            .clone()
    }

    pub fn subscribe(&self, channel: &str) -> broadcast::Receiver<Event> {
        self.sender(channel).subscribe()
    }

    fn deliver_local(&self, channel: &str, event: Event) {
        let sender = {
            let map = self.channels.lock().expect("hub lock");
            map.get(channel).cloned()
        };
        if let Some(tx) = sender {
            let _ = tx.send(event);
        }
    }

    /// Publish to everyone watching `channel` (`session:{id}` or `user:{id}`).
    pub async fn publish(&self, channel: &str, mut event: Event) {
        event.origin = self.instance.clone();
        self.deliver_local(channel, event.clone());
        if let Some(r) = &self.redis {
            let mut conn = r.conn.clone();
            let payload = serde_json::json!({ "origin": self.instance, "event": event });
            let res: Result<(), _> = redis::cmd("PUBLISH")
                .arg(channel)
                .arg(payload.to_string())
                .query_async(&mut conn)
                .await;
            if let Err(e) = res {
                tracing::warn!(error = %e, "redis publish failed");
            }
        }
    }

    pub async fn session(&self, session_id: Uuid, event: Event) {
        self.publish(&format!("session:{session_id}"), event).await;
    }

    pub async fn user(&self, user_id: Uuid, event: Event) {
        self.publish(&format!("user:{user_id}"), event).await;
    }

    /// Relays events other instances published to our local subscribers.
    fn spawn_relay(&self, client: redis::Client) {
        let hub = self.clone();
        tokio::spawn(async move {
            use futures::StreamExt;
            loop {
                let conn = match client.get_async_pubsub().await {
                    Ok(c) => c,
                    Err(e) => {
                        tracing::warn!(error = %e, "redis relay connect failed; retrying");
                        tokio::time::sleep(std::time::Duration::from_secs(3)).await;
                        continue;
                    }
                };
                let mut pubsub = conn;
                for pattern in ["session:*", "user:*", "deck:*"] {
                    if let Err(e) = pubsub.psubscribe(pattern).await {
                        tracing::warn!(error = %e, "redis psubscribe failed");
                    }
                }
                let mut stream = pubsub.on_message();
                while let Some(msg) = stream.next().await {
                    let channel = msg.get_channel_name().to_string();
                    let Ok(payload) = msg.get_payload::<String>() else { continue };
                    let Ok(v) = serde_json::from_str::<Value>(&payload) else { continue };
                    if v.get("origin").and_then(Value::as_str) == Some(hub.instance.as_str()) {
                        continue;
                    }
                    if let Ok(event) = serde_json::from_value::<Event>(v["event"].clone()) {
                        hub.deliver_local(&channel, event);
                    }
                }
                tracing::warn!("redis relay stream ended; reconnecting");
            }
        });
    }
}

//! Load test: N concurrent live lectures against a running octonotes-api.
//!
//! Each lecture: register a device, create a session, open the live
//! WebSocket, start a recording, then for every chunk upload audio + write a
//! note block, and finally complete the recording. Reports request latency
//! (p50/p95/max) per operation, errors, and the lag from a chunk upload to its
//! `transcript.stable` event on the socket.
//!
//!   cargo run --release -p octonotes-api --example loadtest -- \
//!       http://127.0.0.1:8790 20 30 200
//!   (base URL, lectures, chunks per lecture, ms between chunks)
//!
//! Users `load-0 … load-{N-1}` must exist in the octopilot users table (dev:
//! the stand-in DB), or run the API with auth disabled and no shared DB.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use futures::{SinkExt, StreamExt};
use serde_json::{json, Value};
use tokio_tungstenite::tungstenite::Message;
use uuid::Uuid;

#[derive(Default)]
struct Stats {
    latency: HashMap<&'static str, Vec<f64>>,
    errors: HashMap<String, usize>,
    lag: Vec<f64>,
}

type Shared = Arc<Mutex<Stats>>;

async fn timed(stats: &Shared, op: &'static str, req: reqwest::RequestBuilder) -> Option<Value> {
    let start = Instant::now();
    let res = req.send().await;
    let ms = start.elapsed().as_secs_f64() * 1000.0;
    stats
        .lock()
        .unwrap()
        .latency
        .entry(op)
        .or_default()
        .push(ms);
    let error = match res {
        Ok(r) if r.status().is_success() => return r.json().await.ok().or(Some(Value::Null)),
        Ok(r) => format!("{op} {}", r.status()),
        Err(e) => format!("{op} {}", e.without_url()),
    };
    *stats.lock().unwrap().errors.entry(error).or_default() += 1;
    None
}

async fn lecture(base: String, i: usize, chunks: usize, interval: u64, stats: Shared) {
    let http = reqwest::Client::new();
    let user = format!("load-{i}");
    let h = |r: reqwest::RequestBuilder| {
        r.header("x-user-id", user.clone())
            .header("x-client-version", "loadtest/1")
    };
    let device = Uuid::new_v4();
    timed(
        &stats,
        "device",
        h(http.post(format!("{base}/v1/devices")))
            .json(&json!({ "id": device, "name": format!("Phone {i}"), "platform": "android" })),
    )
    .await;
    let Some(session) = timed(
        &stats,
        "session",
        h(http.post(format!("{base}/v1/sessions")))
            .json(&json!({ "title": format!("Load lecture {i}") })),
    )
    .await
    else {
        return;
    };
    let sid = session["id"].as_str().unwrap_or_default().to_string();

    // Live socket: record when each chunk's transcript arrives.
    let sent: Arc<Mutex<HashMap<i64, Instant>>> = Arc::default();
    let ws_url = format!("{}/v1/sessions/{sid}/live", base.replacen("http", "ws", 1));
    let (sent2, stats2, user2) = (sent.clone(), stats.clone(), user.clone());
    let listener = tokio::spawn(async move {
        let Ok((mut ws, _)) = tokio_tungstenite::connect_async(ws_url).await else {
            *stats2
                .lock()
                .unwrap()
                .errors
                .entry("ws connect".into())
                .or_default() += 1;
            return 0usize;
        };
        let _ = ws
            .send(Message::Text(
                json!({ "type": "auth", "userId": user2, "deviceId": device }).to_string(),
            ))
            .await;
        let mut got = 0;
        while let Ok(Some(Ok(msg))) = tokio::time::timeout(Duration::from_secs(60), ws.next()).await
        {
            if let Message::Text(t) = msg {
                let v: Value = serde_json::from_str(&t).unwrap_or_default();
                if v["type"] == "transcript.stable" {
                    if let Some(at) = v["data"]["chunkSeq"]
                        .as_i64()
                        .and_then(|s| sent2.lock().unwrap().get(&s).copied())
                    {
                        stats2.lock().unwrap().lag.push(at.elapsed().as_secs_f64());
                    }
                    got += 1;
                    if got >= chunks {
                        break;
                    }
                }
            }
        }
        got
    });

    let rid = Uuid::new_v4();
    timed(
        &stats,
        "recording.start",
        h(http.post(format!("{base}/v1/sessions/{sid}/recordings")))
            .json(&json!({ "id": rid, "deviceId": device })),
    )
    .await;
    let mut position: Option<String> = None;
    for seq in 0..chunks {
        let mut audio = b"OggS".to_vec();
        audio.extend(std::iter::repeat_n((seq % 251) as u8, 16 * 1024));
        sent.lock().unwrap().insert(seq as i64, Instant::now());
        timed(
            &stats,
            "chunk.upload",
            h(http.put(format!(
                "{base}/v1/recordings/{rid}/chunks/{seq}?startMs={}&durationMs=10000",
                seq * 10_000
            )))
            .header("content-type", "audio/ogg")
            .body(audio),
        )
        .await;
        let key = octonotes_api::positions::between(position.as_deref(), None);
        timed(&stats, "blocks.ops", h(http.post(format!("{base}/v1/sessions/{sid}/blocks/ops"))).json(&json!({ "deviceId": device, "ops": [{
            "clientOpId": format!("{sid}-{seq}"), "op": "upsert", "blockId": Uuid::new_v4(),
            "block": { "type": "paragraph", "text": format!("Note {seq} during lecture {i}"), "position": key } }] }))).await;
        position = Some(key);
        tokio::time::sleep(Duration::from_millis(interval)).await;
    }
    timed(
        &stats,
        "recording.complete",
        h(http.post(format!("{base}/v1/recordings/{rid}/complete")))
            .json(&json!({ "lastSeq": chunks - 1 })),
    )
    .await;
    let got = listener.await.unwrap_or(0);
    if got < chunks {
        *stats
            .lock()
            .unwrap()
            .errors
            .entry("transcript events missing".into())
            .or_default() += chunks - got;
    }
}

fn pct(v: &mut [f64], p: f64) -> f64 {
    if v.is_empty() {
        return 0.0;
    }
    v.sort_by(|a, b| a.partial_cmp(b).unwrap());
    v[((v.len() as f64 - 1.0) * p).round() as usize]
}

#[tokio::main]
async fn main() {
    let args: Vec<String> = std::env::args().collect();
    let base = args
        .get(1)
        .cloned()
        .unwrap_or_else(|| "http://127.0.0.1:8790".into());
    let lectures: usize = args.get(2).and_then(|s| s.parse().ok()).unwrap_or(20);
    let chunks: usize = args.get(3).and_then(|s| s.parse().ok()).unwrap_or(30);
    let interval: u64 = args.get(4).and_then(|s| s.parse().ok()).unwrap_or(200);
    println!("load test: {lectures} lectures × {chunks} chunks, {interval} ms apart → {base}");
    let stats: Shared = Arc::default();
    let start = Instant::now();
    let tasks: Vec<_> = (0..lectures)
        .map(|i| tokio::spawn(lecture(base.clone(), i, chunks, interval, stats.clone())))
        .collect();
    for t in tasks {
        let _ = t.await;
    }
    let wall = start.elapsed().as_secs_f64();
    let mut s = stats.lock().unwrap();
    let total: usize = s.latency.values().map(Vec::len).sum();
    println!(
        "\n{total} requests in {wall:.1} s ({:.0} req/s)\n",
        total as f64 / wall
    );
    println!(
        "{:<20} {:>7} {:>9} {:>9} {:>9}",
        "operation", "count", "p50 ms", "p95 ms", "max ms"
    );
    let mut ops: Vec<_> = s.latency.keys().copied().collect();
    ops.sort();
    for op in ops {
        let v = s.latency.get_mut(op).unwrap();
        let n = v.len();
        println!(
            "{op:<20} {n:>7} {:>9.1} {:>9.1} {:>9.1}",
            pct(v, 0.5),
            pct(v, 0.95),
            pct(v, 1.0)
        );
    }
    let lag = &mut s.lag;
    println!(
        "\ntranscript lag (upload → transcript.stable): n={} p50={:.2}s p95={:.2}s max={:.2}s",
        lag.len(),
        pct(lag, 0.5),
        pct(lag, 0.95),
        pct(lag, 1.0)
    );
    if s.errors.is_empty() {
        println!("errors: none");
    } else {
        println!("errors: {:?}", s.errors);
    }
}

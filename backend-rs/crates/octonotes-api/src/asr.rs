//! Speech-to-text (decided: OpenRouter `/api/v1/audio/transcriptions` first).
//!
//! OpenRouter is request/response only, so transcription is chunk by chunk:
//! - live pass (`asr.chunk`): each uploaded chunk → a fast model → stable
//!   segments pushed over the WebSocket, ~chunk length + model time behind;
//! - faithful pass (`transcript.faithful`): the joined recording once → a
//!   better model with word timestamps + diarization → `faithful_text` and
//!   speakers. `raw_text` is never touched.
//!
//! Without an OpenRouter key (dev/tests) an offline stand-in produces
//! deterministic text so the whole pipeline still runs.

use octo_common::llm::{self, OpenRouter, Segment, Transcription, Word};
use serde_json::json;
use sqlx::Row;
use uuid::Uuid;

use crate::jobs::{Job, JobResult};
use crate::realtime::Event;
use crate::{revs, AppState};

pub const LIVE_MODEL_SETTING: &str = "octonotes_asr_live_model";
pub const FAITHFUL_MODEL_SETTING: &str = "octonotes_asr_faithful_model";
const LIVE_DEFAULT: &str = "openai/gpt-4o-mini-transcribe";
const FAITHFUL_DEFAULT: &str = "openai/gpt-4o-transcribe";

/// Which engine transcribes.
pub enum Asr {
    OpenRouter { client: OpenRouter, model: String },
    Offline,
}

impl Asr {
    pub async fn for_pass(st: &AppState, faithful: bool) -> Asr {
        let Some(pool) = &st.octopilot else {
            return Asr::Offline;
        };
        let Some(key) = llm::openrouter_key(pool).await else {
            return Asr::Offline;
        };
        let model = if faithful {
            llm::model(pool, FAITHFUL_MODEL_SETTING, FAITHFUL_DEFAULT).await
        } else {
            llm::model(pool, LIVE_MODEL_SETTING, LIVE_DEFAULT).await
        };
        Asr::OpenRouter {
            client: OpenRouter::new(st.http.clone(), key),
            model,
        }
    }

    pub async fn transcribe(
        &self,
        audio: &[u8],
        format: &str,
        duration_ms: i64,
        words: bool,
        label: &str,
    ) -> Result<Transcription, String> {
        match self {
            Asr::OpenRouter { client, model } => {
                client.transcribe(model, audio, format, None, words).await
            }
            Asr::Offline => Ok(offline(duration_ms, label)),
        }
    }
}

/// Deterministic stand-in transcript: the label, then roughly one word per
/// second of audio, word-timed like a real verbose_json response.
fn offline(duration_ms: i64, label: &str) -> Transcription {
    let secs = (duration_ms as f64 / 1000.0).max(0.5);
    let mut tokens: Vec<String> = format!("[offline transcript] {label}")
        .split_whitespace()
        .map(str::to_string)
        .collect();
    let target = secs.ceil() as usize;
    let mut i = 0;
    while tokens.len() < target {
        tokens.push(format!("w{i}"));
        i += 1;
    }
    let n = tokens.len() as f64;
    let words: Vec<Word> = tokens
        .iter()
        .enumerate()
        .map(|(i, w)| Word {
            word: w.clone(),
            start: secs * i as f64 / n,
            end: secs * (i as f64 + 1.0) / n,
            speaker: None,
        })
        .collect();
    let text = tokens.join(" ");
    Transcription {
        text: text.clone(),
        language: Some("en".into()),
        duration: Some(secs),
        segments: vec![Segment {
            text,
            start: 0.0,
            end: secs,
            speaker: None,
            confidence: Some(0.9),
        }],
        words,
    }
}

/// Drops words at the start of `text` that repeat the end of `previous`
/// (chunks may overlap by ~2 s so words aren't cut at the boundary).
pub fn dedupe_overlap(previous: &str, text: &str) -> String {
    let prev: Vec<&str> = previous.split_whitespace().collect();
    let cur: Vec<&str> = text.split_whitespace().collect();
    let norm = |w: &str| {
        w.trim_matches(|c: char| !c.is_alphanumeric())
            .to_lowercase()
    };
    let max = prev.len().min(cur.len()).min(12);
    for k in (1..=max).rev() {
        let tail = &prev[prev.len() - k..];
        let head = &cur[..k];
        if tail.iter().zip(head).all(|(a, b)| norm(a) == norm(b)) {
            return cur[k..].join(" ");
        }
    }
    text.trim().to_string()
}

fn map_speaker(raw: Option<&str>) -> &'static str {
    match raw.map(|s| s.to_lowercase()) {
        None => "unknown",
        // Diarization labels: the first speaker in a lecture is usually the
        // professor; the student corrects mistakes (Correct Speaker).
        Some(s) if s == "0" || s == "a" || s == "speaker_0" || s == "spk_0" => "professor",
        Some(_) => "speaker1",
    }
}

fn ext_format(key: &str) -> &'static str {
    match key.rsplit('.').next().unwrap_or("") {
        "webm" => "webm",
        "wav" => "wav",
        "m4a" | "mp4" => "m4a",
        _ => "ogg",
    }
}

/// Live pass for one chunk. Idempotent: re-running replaces that chunk's
/// segments.
pub async fn job_chunk(st: AppState, job: Job) -> JobResult {
    let rid: Uuid =
        serde_json::from_value(job.payload["recordingId"].clone()).map_err(|e| e.to_string())?;
    let seq = job.payload["seq"].as_i64().ok_or("seq missing")? as i32;
    let row = sqlx::query(
        "SELECT c.object_key, c.start_ms, c.duration_ms, r.session_id, r.user_id, \
                COALESCE((s.config->>'liveTranscription')::boolean, true) AS live \
         FROM audio_chunks c JOIN recordings r ON r.id = c.recording_id JOIN sessions s ON s.id = r.session_id \
         WHERE c.recording_id = $1 AND c.seq = $2 AND s.deleted_at IS NULL",
    )
    .bind(rid)
    .bind(seq)
    .fetch_optional(&st.notes)
    .await
    .map_err(|e| e.to_string())?;
    let Some(row) = row else { return Ok(()) };
    let (key, start_ms, duration_ms, session_id, user_id, live): (
        String,
        i64,
        i32,
        Uuid,
        Uuid,
        bool,
    ) = (
        row.get("object_key"),
        row.get("start_ms"),
        row.get("duration_ms"),
        row.get("session_id"),
        row.get("user_id"),
        row.get("live"),
    );
    if !live {
        sqlx::query(
            "UPDATE audio_chunks SET asr_status = 'skipped' WHERE recording_id = $1 AND seq = $2",
        )
        .bind(rid)
        .bind(seq)
        .execute(&st.notes)
        .await
        .map_err(|e| e.to_string())?;
        return Ok(());
    }
    let audio = st.storage.get(&key).await?;
    let asr = Asr::for_pass(&st, false).await;
    let t = asr
        .transcribe(
            &audio,
            ext_format(&key),
            duration_ms as i64,
            false,
            &format!("recording chunk {seq}"),
        )
        .await?;

    let mut tx = st.notes.begin().await.map_err(|e| e.to_string())?;
    revs::lock(&mut tx, session_id, revs::TRANSCRIPT)
        .await
        .map_err(|e| e.to_string())?;
    let previous: Option<String> = sqlx::query_scalar(
        "SELECT raw_text FROM transcript_segments WHERE recording_id = $1 AND chunk_seq = $2 ORDER BY ordinal DESC LIMIT 1",
    )
    .bind(rid)
    .bind(seq - 1)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|e| e.to_string())?;
    sqlx::query("DELETE FROM transcript_segments WHERE recording_id = $1 AND chunk_seq = $2")
        .bind(rid)
        .bind(seq)
        .execute(&mut *tx)
        .await
        .map_err(|e| e.to_string())?;

    let segments = if t.segments.is_empty() && !t.text.is_empty() {
        vec![Segment {
            text: t.text.clone(),
            start: 0.0,
            end: duration_ms as f64 / 1000.0,
            speaker: None,
            confidence: None,
        }]
    } else {
        t.segments.clone()
    };
    let mut ids = Vec::new();
    let mut rev = 0;
    for (i, seg) in segments.iter().enumerate() {
        let text = if i == 0 {
            dedupe_overlap(previous.as_deref().unwrap_or(""), &seg.text)
        } else {
            seg.text.clone()
        };
        if text.is_empty() {
            continue;
        }
        rev = revs::bump(&mut tx, session_id, revs::TRANSCRIPT)
            .await
            .map_err(|e| e.to_string())?;
        let speaker = map_speaker(seg.speaker.as_deref());
        let id: Uuid = sqlx::query_scalar(
            "INSERT INTO transcript_segments (session_id, recording_id, user_id, chunk_seq, ordinal, start_ms, end_ms, \
                 raw_text, speaker, speaker_original, speaker_conf, asr_conf, status, language, layer_rev) \
             VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$9,$10,$11,'stable',$12,$13) RETURNING id",
        )
        .bind(session_id)
        .bind(rid)
        .bind(user_id)
        .bind(seq)
        .bind(i as i32)
        .bind(start_ms + (seg.start * 1000.0) as i64)
        .bind(start_ms + (seg.end * 1000.0).max(seg.start * 1000.0 + 1.0) as i64)
        .bind(&text)
        .bind(speaker)
        .bind(if seg.speaker.is_some() { 0.7f32 } else { 0.0f32 })
        .bind(seg.confidence.unwrap_or(0.8) as f32)
        .bind(&t.language)
        .bind(rev)
        .fetch_one(&mut *tx)
        .await
        .map_err(|e| e.to_string())?;
        ids.push(id);
    }
    sqlx::query("UPDATE audio_chunks SET asr_status = 'done' WHERE recording_id = $1 AND seq = $2")
        .bind(rid)
        .bind(seq)
        .execute(&mut *tx)
        .await
        .map_err(|e| e.to_string())?;
    meter(
        &mut tx,
        session_id,
        user_id,
        "asr_seconds",
        duration_ms as f64 / 1000.0,
        &format!("live:{rid}:{seq}"),
    )
    .await?;
    tx.commit().await.map_err(|e| e.to_string())?;

    if !ids.is_empty() {
        st.hub
            .session(
                session_id,
                Event::new(
                    "transcript.stable",
                    json!({ "segmentIds": ids, "recordingId": rid, "chunkSeq": seq }),
                    Some(rev),
                ),
            )
            .await;
        let _ = crate::jobs::enqueue(
            &st.notes,
            Some(user_id),
            "embed.session",
            json!({ "sessionId": session_id }),
            Some(&format!(
                "embed:{session_id}:{}",
                chrono::Utc::now().timestamp() / 30
            )),
        )
        .await;
    }
    Ok(())
}

/// Records metered usage once per `ref` (charged later in batches).
pub async fn meter(
    conn: &mut sqlx::PgConnection,
    session_id: Uuid,
    user_id: Uuid,
    kind: &str,
    quantity: f64,
    reference: &str,
) -> Result<(), String> {
    sqlx::query(
        "INSERT INTO usage_meter (session_id, user_id, kind, quantity, ref) VALUES ($1,$2,$3,$4,$5) ON CONFLICT (kind, ref) DO NOTHING",
    )
    .bind(session_id)
    .bind(user_id)
    .bind(kind)
    .bind(quantity)
    .bind(reference)
    .execute(conn)
    .await
    .map(|_| ())
    .map_err(|e| e.to_string())
}

/// Faithful pass over the joined recording: word-timed text per live segment
/// (by time overlap) + diarized speakers. Leaves `raw_text` and any student
/// correction untouched.
pub async fn job_faithful(st: AppState, job: Job) -> JobResult {
    let rid: Uuid =
        serde_json::from_value(job.payload["recordingId"].clone()).map_err(|e| e.to_string())?;
    let row = sqlx::query(
        "SELECT session_id, user_id, audio_key, duration_ms FROM recordings WHERE id = $1",
    )
    .bind(rid)
    .fetch_optional(&st.notes)
    .await
    .map_err(|e| e.to_string())?;
    let Some(row) = row else { return Ok(()) };
    let (session_id, user_id, audio_key, duration_ms): (Uuid, Uuid, Option<String>, i64) = (
        row.get("session_id"),
        row.get("user_id"),
        row.get("audio_key"),
        row.get("duration_ms"),
    );
    let Some(audio_key) = audio_key else {
        return Err("recording not assembled yet".into());
    };
    let audio = st.storage.get(&audio_key).await?;
    let asr = Asr::for_pass(&st, true).await;
    let t = asr
        .transcribe(
            &audio,
            ext_format(&audio_key),
            duration_ms,
            true,
            "faithful pass",
        )
        .await?;

    // Words (or segments when the model returns no words) on the recording timeline.
    let timed: Vec<(f64, f64, String, Option<String>)> = if !t.words.is_empty() {
        t.words
            .iter()
            .map(|w| {
                (
                    w.start * 1000.0,
                    w.end * 1000.0,
                    w.word.clone(),
                    w.speaker.clone(),
                )
            })
            .collect()
    } else {
        t.segments
            .iter()
            .map(|s| {
                (
                    s.start * 1000.0,
                    s.end * 1000.0,
                    s.text.clone(),
                    s.speaker.clone(),
                )
            })
            .collect()
    };
    let recording_start: i64 = 0;
    let segs: Vec<(Uuid, i64, i64)> = sqlx::query_as(
        "SELECT id, start_ms, end_ms FROM transcript_segments WHERE recording_id = $1 ORDER BY start_ms",
    )
    .bind(rid)
    .fetch_all(&st.notes)
    .await
    .map_err(|e| e.to_string())?;

    let mut tx = st.notes.begin().await.map_err(|e| e.to_string())?;
    revs::lock(&mut tx, session_id, revs::TRANSCRIPT)
        .await
        .map_err(|e| e.to_string())?;
    let mut updated = Vec::new();
    let mut rev = 0;
    let n = segs.len();
    for (i, (id, start, end)) in segs.iter().enumerate() {
        // Each item goes to the segment containing its midpoint; the last
        // segment takes anything after it.
        let words: Vec<&(f64, f64, String, Option<String>)> = timed
            .iter()
            .filter(|(s, e, _, _)| {
                let mid = (s + e) / 2.0 + recording_start as f64;
                (mid >= *start as f64 || i == 0) && (mid < *end as f64 || i + 1 == n)
            })
            .collect();
        if words.is_empty() {
            continue;
        }
        let text = words
            .iter()
            .map(|w| w.2.trim())
            .filter(|w| !w.is_empty())
            .collect::<Vec<_>>()
            .join(" ");
        let speaker = words.iter().find_map(|w| w.3.clone());
        rev = revs::bump(&mut tx, session_id, revs::TRANSCRIPT)
            .await
            .map_err(|e| e.to_string())?;
        sqlx::query(
            "UPDATE transcript_segments SET faithful_text = $2, \
                 speaker = CASE WHEN $3::text IS NULL OR speaker <> speaker_original THEN speaker ELSE $3 END, \
                 speaker_original = COALESCE($3, speaker_original), \
                 speaker_conf = CASE WHEN $3::text IS NULL THEN speaker_conf ELSE 0.8 END, \
                 words = $4, revision = revision + 1, layer_rev = $5 WHERE id = $1",
        )
        .bind(id)
        .bind(text)
        .bind(speaker.as_deref().map(|s| map_speaker(Some(s))))
        .bind(serde_json::to_value(words.iter().map(|w| json!({ "word": w.2, "startMs": w.0 as i64, "endMs": w.1 as i64 })).collect::<Vec<_>>()).ok())
        .bind(rev)
        .execute(&mut *tx)
        .await
        .map_err(|e| e.to_string())?;
        updated.push(*id);
    }
    meter(
        &mut tx,
        session_id,
        user_id,
        "asr_faithful_seconds",
        duration_ms as f64 / 1000.0,
        &format!("faithful:{rid}"),
    )
    .await?;
    tx.commit().await.map_err(|e| e.to_string())?;
    if !updated.is_empty() {
        st.hub
            .session(
                session_id,
                Event::new(
                    "transcript.faithful",
                    json!({ "segmentIds": updated, "recordingId": rid }),
                    Some(rev),
                ),
            )
            .await;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn overlap_dedupe() {
        assert_eq!(
            dedupe_overlap(
                "the electron transport chain",
                "transport chain uses oxygen"
            ),
            "uses oxygen"
        );
        assert_eq!(
            dedupe_overlap("glycolysis.", "Glycolysis makes ATP"),
            "makes ATP"
        );
        assert_eq!(dedupe_overlap("", "hello world"), "hello world");
        assert_eq!(dedupe_overlap("abc", "def"), "def");
    }
}

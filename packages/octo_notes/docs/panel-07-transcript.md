# Panel 7 — Live Transcript (full specification)

Authoritative spec for the transcript panel. `MEMORY.md` holds the condensed
status; read this before extending it.

## 1. Main goals
Read transcription as produced · distinguish live partial from stable text ·
follow the current moment · pause auto-scroll · play audio from any timestamp ·
search · correct mistakes · rename/correct speakers · link sections to typed or
handwritten notes · see connected slides + markers · use selections as AI context
· recover after an offline lecture · access the original raw transcript after AI
processing.

## 2. Transcript layers (never collapse these)
- **Raw Live Transcript** — original ASR output captured during the lecture.
- **Faithful Transcript** — a more accurate post-processed version (punctuation,
  paragraph breaks, speaker labels, course terminology, obvious mistakes). Must
  **not** summarize, reorganize, or remove content.
- **Smart Notes** — AI-organized notes (Panel 11 / reviewed in Panel 13). Must
  **never** overwrite the Raw or Faithful transcript.

## 3. Panel structure
Title · recording/transcription status · search · Follow Live toggle · current
delay · expand/collapse · Open Full Transcript · segments · speaker labels ·
timestamps · correction controls · audio playback · linked slide/note indicators
· bottom status. Header example: `Live Transcript · Live · 3 seconds behind ·
Following Live`.

## 4. Panel sizes
- **Collapsed** — live status, latest stable line, current timestamp, expand.
- **Docked** — ~3–6 segments beneath the canvas.
- **Expanded** — larger area for search/correct/review.
- **Full Transcript** — main workspace for full review, still with audio + source
  links. Opening full transcript stays part of Panel 7 (not a new numbered panel).

## 5. Partial vs stable
- **Partial** — currently recognizing: lighter/muted, subtle live indicator, no
  permanent note links, at the bottom; may change as the speaker continues.
- **Stable** — finalized: stable segment ID, start/end timestamps, speaker label,
  audio-chunk refs, confidence score, source-device info. Must not repeatedly
  rewrite itself live.

## 6. Stability rules
Becomes stable when: service marks final · meaningful pause · new speaker · a
reasonable length. After stabilization: new speech = new segment · text does not
jump · corrections become recorded revisions · later post-processing creates
another faithful version rather than erasing raw. Protects the student's reading
position.

## 7. Follow Live
Enabled: stay near the latest segment, new stable segments append at the bottom,
restrained current-line indicator. On scroll up: Follow Live pauses; does not pull
back down; a **Jump to Live** button appears; a count can show new segments (e.g.
"8 new transcript segments · Jump to Live").

## 8. Timestamps & playback
Every stable segment links to an exact audio range. Selecting a timestamp: start
slightly before the segment, highlight words as audio plays, small waveform,
rewind/forward, speed, return to live. Controls: Play/Pause · Back 10s · Forward
10s · 0.75×/1×/1.25×/1.5×/2× · volume · Open Recording. If the chunk hasn't
uploaded: "Audio saved on Hein's iPhone · Upload pending".

## 9. Speaker labels
Show only confident labels: Professor · Student · Speaker 1 · Unknown Speaker.
Students can rename · merge identities · split a wrongly-combined segment · mark
as Student Question · apply a name to future matching segments. Low-confidence
detection must not pretend to know who spoke.

## 10. Corrections
Edit stable text. Actions: Correct Text · Correct Speaker · Split Segment · Merge
with Previous · Restore Original · Report Recognition Error. Preserve: original
ASR text · post-processed text · student correction · correction timestamp ·
correcting user. A future AI pass must not overwrite a student correction.

## 11. Selection actions
Add to Notes · Quote · Explain · Summarize · Define · Research · Mark Important ·
Create Question · Correct Text · Copy Link. Add to Notes → source-linked block in
Panel 5. Explain/Summarize → Panel 9. Research → Panel 10. Original transcript
stays unchanged.

## 12. Typewriter connections
An inserted selection contains speaker · timestamp · short excerpt · audio link ·
transcript reference. Example: `Professor · 18:32 — "The net result is two ATP and
two NADH."` The reference stays traceable even if the visible wording is later
corrected.

## 13. Magic Pencil connections
A handwritten region can link to a segment ("Linked to Magic Pencil · Page 3");
selecting opens the region. A selection can also become a source card on the
canvas.

## 14–15. Slides & markers
Segments link to current slide / PDF page / board photo / handout / slide-change
marker (chip like `Week 4 Slides · Slide 7` opens Panel 8). Markers from Panel 4
(Important/Question/Confusing/Exam Hint/Slide Change) appear beside the segment as
separate metadata — they never edit the transcript text.

## 16. Search & filtering
Search by phrase/speaker/timestamp/topic/marker/slide/corrected/low-confidence/
student-questions/exam-hints; results open the exact transcript + audio position.
Filters: All Speakers · Professor Only · Questions · Markers · Corrections ·
Linked Notes · Low Confidence.

## 17. Live vs post-class
Live available → near-real-time partial + stable, synchronized across devices.
Delayed → recording continues, panel shows the delay, delayed segments catch up.
No connection → audio protected locally, panel shows last transcript, post-class
transcription begins when audio is available ("Recording safely offline ·
Transcription will resume after connection returns").

## 18. Post-class faithful processing
A higher-accuracy pass may improve terminology, speaker separation, punctuation,
paragraph structure, formulas/acronyms, obvious errors. UI: View Faithful
Transcript · Compare with Raw · Restore Raw Wording · Review Major Corrections.
It cannot remove explanations, examples, questions, warnings, or repetition to
shorten the lecture.

## 19. Language & terminology
Support selected + multiple languages, course vocabulary, professor names,
technical terms, acronyms, student correction dictionaries. Confirmed corrections
improve future transcription without changing earlier raw records.

## 20. Cross-device
Phone: latest stable lines + status + basic markers/expand. Desktop/web: docked or
full transcript, search/playback/correction/insertion. Tablet: bottom drawer,
links to handwriting + slides. All devices share the same segment IDs + timestamp
references.

## 22. Required interface states
Waiting for speech · listening · partial · stable · following live · follow paused
· recording paused · transcription delayed · offline recording · reconnecting ·
post-class processing · faithful ready · low-confidence segment · unknown speaker ·
correcting · corrected · audio upload pending · audio unavailable · search results
· no results · read-only · transcription failure.

## 23. Privacy & access
Transcript access inherits session permissions; protect like the recording;
sharing a transcript doesn't auto-share audio; speaker names stay editable;
corrections/authorship preserved; user controls audio + transcript deletion;
status stays transparent.

## 24. Data structure — `TranscriptSegment`
Segment ID · session ID · start/end · raw ASR text · faithful text · corrected
text · partial/stable · speaker ID · speaker confidence · transcription confidence
· language · audio-chunk refs · recording-device ID · slide ref · marker refs ·
typewriter links · magic pencil links · revision history · sync state. The UI
picks the display version while preserving every source version.

## 25. Performance
Partial text within a few seconds · stable append without resetting scroll ·
virtualized long transcripts · search without downloading all audio · quick
timestamp playback when chunk available · one update doesn't rerender everything ·
delays never affect recording · usable across multi-hour lectures.

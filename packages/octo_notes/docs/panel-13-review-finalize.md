# Panel 13 — Session Review & Finalize (ON-P13, full specification)

Authoritative spec. `MEMORY.md` holds the condensed status. Panel 13 is the
full-screen review workspace shown after **Finish Session**. It is an
**evidence-based final review system**, not a basic save/export screen.
Supported on all devices (desktop/web/tablet side-by-side; phone = guided steps).

## 1. Purpose
Bring every version of the lecture into one place so the student can compare
**Original Sources · Raw Transcript · Student Notes · AI Assistance · Smart Notes
· Final Notes**, review what happened, resolve pending issues, and approve the
final document before saving to The Deck. These are **six layers inside one
panel**, not six extra panels.

## 2. Core principle
Finalization creates an **approved version** without deleting or replacing the
underlying material. Preserved: original audio · raw transcript · typed notes ·
original ink/diagrams · photos/uploads · AI suggestions/research · organization
history · source & timestamp links. Final Notes become the main readable
document; every original source stays accessible.

## 4. Entry flow
Finish Session → OctoNotes (1) stops/confirms recording, (2) checks device sync,
(3) uploads remaining audio/ink/images, (4) processes final transcript segments,
(5) builds Smart Notes, (6) opens Panel 13. If anything is still uploading the
student can enter review but **finalization stays temporarily unavailable**.

## 5. The six review layers
1. **Original Sources** — audio, original Magic Pencil ink, diagrams, board
   photos, slides, PDFs, timestamp markers. **Read-only** here; editing a final
   note must never alter the original file.
2. **Raw Transcript** — faithful chronological transcript: speaker labels,
   timestamps, uncertain words, confidence, waveform, slide links, student
   markers, in-session corrections. Corrections create a **corrected layer**
   while preserving the raw result. (raw "grading" → corrected "gradient", etc.)
3. **Student Notes** — only material the student created (typewriter, handwriting,
   diagrams, questions, highlights, manual headings, tasks). Transcript/AI content
   must NOT be shown as student-written. Keeps creation time + device source.
4. **AI Assistance** — explanations, research, breakdowns, definitions, proposed
   corrections, exam hints, headings, organization recs, unaccepted suggestions.
   Each shows a decision state: **Accepted / Edited & accepted / Pending /
   Rejected**. Pending AI must be resolved or excluded before Final Notes.
5. **Smart Notes** — OctoNotes' proposed organized version (topics, headings,
   grouped notes, relevant transcript excerpts, approved explanations,
   definitions, examples, questions, exam hints, slide/source links). Still a
   **proposal** until Final Notes is approved.
6. **Final Notes** — the student-approved main document for The Deck. Student can
   edit wording, reorder, remove/restore a block, approve/reject AI, change
   headings, confirm sources, add a summary, rename, pick Deck destination.
   Removing from Final Notes does **not** delete it from its original layer.

## 6. Interface layout
- **A. Review header** — session title · course/week · date · duration · review
  status · device sync status · save destination. e.g. "Cellular Respiration
  Lecture · Biology 101 • Week 4 • 42:16 · Review Required — 3 items remaining".
- **B. Layer navigation** (left) — the six layers, each with a status indicator:
  green check = reviewed · blue dot = open · yellow number = pending decision ·
  red warning = problem · grey = not yet processed.
- **C. Comparison workspace** (centre) — open two layers side by side via a
  **Compare With** dropdown. Useful pairs: Raw Transcript vs Student Notes ·
  Student Notes vs Smart Notes · AI vs Smart Notes · Smart Notes vs Final Notes ·
  Original Source vs Final Notes. Selecting one block highlights its related
  source on the other side.
- **D. Audio timeline** (persistent) — play/pause · ±10s · speed · search
  transcript · timestamp markers · follow transcript · play audio of a selected
  block. "18:32 / 42:16". Selecting a transcript-derived statement jumps to its
  audio timestamp.
- **E. Review checklist** (right) — All devices synchronized · Audio upload
  complete · Raw transcript processed · Original ink preserved · N transcript
  uncertainties · N AI decisions pending · N unresolved student question · Final
  Notes destination selected. Selecting an item jumps to the affected block.

## 7. Block-level review controls
Open Original Source · Play Audio · View Transcript · Accept · Reject · Edit
Before Accepting · Include in Final Notes · Exclude from Final Notes · Restore
Original · View Source History. Provenance labels: Student Typed · Magic Pencil •
Original Ink · Transcript • 18:32 · Week 4 Slides • Slide 7 · AI Explanation ·
External Research · Smart Organization.

## 8. Change highlighting (Smart Notes vs Final Notes)
green = added · blue = moved/reorganized · yellow = edited wording · red =
excluded · purple = AI-generated/expanded. Colouring can be hidden for a clean
reading preview (**Show Changes** toggle).

## 9. Transcript uncertainty review
Low-confidence sections form a focused queue. "The proton [grading/gradient]
powers ATP synthase." Actions: Play Audio · Choose Suggested Word · Type
Correction · Mark as Unclear · Exclude from Final Notes. Raw stays unchanged; the
correction is a linked corrected version.

## 10. AI approval review
Pending AI additions form a separate queue. Each: proposed content · reason ·
supporting notes/transcript · course-material source · external source (if used)
· intended position. Actions: Accept · Edit & Accept · Reject · Save as Research
Only. No pending AI enters Final Notes automatically.

## 11. Finalization controls (persistent bottom bar)
Back to Session · Save Review Draft · Preview Final Notes · Finalize & Save.

## 12. Save destination
Pick a Deck location (The Deck › Biology 101 › Lectures › Week 4). Confirm note
title · course · topic · lecture date · tags · instructor · related materials.
The Deck is the destination/organization system, separate from capture/review.

## 13. Finalization confirmation
Summary: "42:16 audio preserved · 126 transcript blocks preserved · 34
student-created blocks preserved · 5 AI additions approved · 3 AI suggestions
rejected · 4 source materials linked · Final Notes will be saved to Biology 101 /
Lectures / Week 4". Primary: Finalize Session · Secondary: Continue Reviewing.

## 14. Panel states
Preparing review · Review ready · Pending synchronization (finalize disabled,
review continues) · Missing source (note preserved + flagged) · Transcript
uncertainty · Pending AI decisions · Conflict detected · Ready to finalize ·
Saving · Saved successfully · Offline (local draft only until sync + server
confirm) · Finalization error (nothing deleted/partially replaced; retry from
saved review state).

## 15. AI behaviour
Can: flag transcript uncertainty, suggest corrections, compare notes vs lecture,
detect missing topics, build Smart Notes, suggest an outline, find unresolved
questions, check claims have sources, suggest what enters Final Notes.
Cannot: alter original audio, rewrite raw student notes, approve its own
additions, delete rejected/excluded material, finalize the session, or save into
Study Studio without student approval.

## 16. Saved output
A persistent session package: original source archive · raw transcript ·
corrected transcript layer · Student Notes · AI Assistance · Smart Notes · Final
Notes · review decisions · source/timestamp links · organization structure · Deck
destination · session metadata · revision history · finalization timestamp. Final
Notes = main document; other layers remain accessible via the session archive.

## 17. Connections
Panel 12 (device sync check before finalize) · Panel 11 (approved structure →
Smart Notes layer) · earlier live panels supply traceable content layers · The
Deck stores Final Notes + archive as one structured session · Panel 14 (post-
finalize Study Studio recommendations) · Panel 15 (conversion preview). Panel 13
itself does not create Study Studio activities.

## 18. Technical notes
Core objects: SessionArchive · OriginalSource · TranscriptVersion ·
StudentNoteLayer · AIAssistanceItem · SmartNotesVersion · FinalNotesDocument ·
ReviewDecision · ProvenanceLink · FinalizationManifest · SessionRevision. Every
Final Notes block retains: final block ID · origin block ID · source layer ·
source device · source timestamp · audio ref · slide/material ref · AI-generation
status · student approval state · revision history. Finalization is transactional
& idempotent: validate sync → validate required decisions → create immutable
source refs → save Final Notes → save manifest → mark finalized → trigger Panel
14. Any failure leaves the previous review state intact and retryable. Revalidate
AI suggestions if source blocks change. Use block-level comparisons, not
whole-layer text diffs.

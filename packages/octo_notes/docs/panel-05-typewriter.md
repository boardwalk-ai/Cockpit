# Panel 5 — Typewriter (full specification)

The authoritative spec for the Typewriter workspace. `MEMORY.md` holds the
condensed durable facts and points here for detail. When a mock/screenshot is
ambiguous, read this before building.

## 1. Students should be able to
- Type without interruption or input delay.
- Use structured note blocks.
- Write only keywords / short phrases when moving quickly.
- Ask AI to expand selected content.
- Connect notes to transcript timestamps.
- Link blocks to slides and course materials.
- Rearrange blocks manually.
- Preview AI organization without destabilizing the live canvas.
- Distinguish their writing from AI-generated material.
- Continue working offline.
- Switch to Magic Pencil without losing typed content.

## 2. Core principle
The student's typed notes are the **authoritative Student Notes layer**.
AI *can*: suggest, explain, expand, research, categorize, propose movement.
AI *cannot* silently rewrite, delete, or move student-written blocks.

## 3. Canvas structure
Document title · Typewriter/Magic Pencil switcher · compact formatting toolbar ·
block-based writing area · block handles · timestamp indicators · source & slide
links · contextual selection toolbar · Magic Bar access · autosave/sync status.
The canvas should resemble a **clean academic document, not a chat window**.

## 4. Core block types
- **Text**: Paragraph, Heading 1, Heading 2, Heading 3, Bulleted list,
  Numbered list, Checklist, Quote.
- **Academic**: Definition, Key Idea, Formula, Example, Question, Exam Hint,
  Warning, Assignment, Summary.
- **Rich-content**: Table, Image, Diagram, Slide reference, PDF excerpt,
  Transcript excerpt, Audio timestamp, Divider.

Each block has a **stable ID** so it can be moved, linked, restored, and
referenced without losing its connections.

## 5. Writing & formatting
Toolbar · keyboard shortcuts · markdown-style shortcuts · slash commands ·
text-selection controls. Examples: `#` → heading, `-` → bullet, `[]` → checklist.

## 6. Block controls (every block)
Drag · Duplicate · Delete · Convert block type · Indent · Outdent · Move up/down ·
Link to topic · Link to transcript · Link to slide · Send to AI ·
Add to Study Studio selection · View block history.
The drag handle stays **subtle until hovered or selected**.

## 7. Fast keyword note-taking
Students may type only keywords (e.g. `Glycolysis / cytoplasm / 2 ATP / no oxygen`).
OctoNotes shows a **restrained** suggestion: "Expand these keywords?" — selecting
it sends the block to Panel 9 **without replacing the original text**. Actions:
Insert Below · Add as Explanation · Replace Selection.

## 8. Shorthand expansion
Personal or course-level shorthand. Two kinds:
- **Mechanical expansion** — instantly expands known abbreviations, no AI.
- **AI-assisted expansion** — uses lecture context/transcript/materials; stays a
  **preview until approved**.

## 9. Timestamp connections
While recording is active, new blocks can auto-store the current audio time.
Timestamp may stay hidden until hover or block selection.

## 10. Transcript interaction
Drag/insert a transcript section into the canvas. A transcript reference shows:
Speaker · Timestamp · short excerpt · Play-audio action · Open-in-transcript action.

## 11. Materials & slide connections
Blocks connect to Panel 8 materials. Drag a slide in · link a block to the current
slide · insert image/diagram · attach a PDF excerpt · add a board photo · open the
source beside the note. Source chip e.g. `Week 4 Slides · Slide 7` opens the exact
material location.

## 12. Text-selection actions
On selection, a small contextual toolbar: Explain · Expand · Simplify · Define ·
Example · Research · Compare · Ask AI · Highlight · Link Source.
AI actions open Panel 9 or a temporary suggestion card — they **must not**
immediately change the selected text.

## 13. Magic Bar behavior
Acts on: selected words · current block · multiple blocks · transcript segment ·
slide · diagram · whole note. Example commands: "Explain this in simpler terms." ·
"Give me a real-world example." · "Compare this with the professor's explanation." ·
"Find what I missed in this section." · "Turn these keywords into complete notes." ·
"Organize these blocks by topic." · "Create three review questions."
The system must **show what context will be sent** before running a broad command.

## 14. AI-content distinction
AI-generated content stays visually + technically identifiable: small AI icon ·
pale tinted border · label ("AI Suggestion") · linked source references ·
Insert/Dismiss controls. After insertion, origin + sources remain stored.
Inspectable states: **Student written · AI inserted by student · AI suggestion not
yet inserted**.

## 15. Manual & AI organization
- **Manual**: drag blocks immediately between headings/topics.
- **AI (Panel 11)**: may propose new headings, topic groups, block movements,
  duplicate removal, combined explanations. During active typing AI must **not**
  move blocks automatically — it shows e.g. "6 organizational changes ready to
  review"; the student previews & approves separately.

## 16. Course & Study Studio connections
Blocks can link to: Course · Topic · Assignment · Exam · Deck page · Study Studio
topic · existing study activity. "Add to Study Studio Selection" does **not**
create a Study Studio immediately — the selection is used later in Panels 14 & 15.

## 17. Switching to Magic Pencil (Panel 6)
Typed blocks stay saved · scroll position remembered · recording continues ·
transcript continues · AI ops continue in background · Magic Pencil opens at its
last page. Typewriter and Magic Pencil are **two student-input layers in one
session**.

## 18. Autosave & offline (offline on Android & iOS — this is Flutter)
Every edit saves **locally immediately**. Sync is **block-level** (editing one
block never rewrites the whole note). Status chips: Saved · Saving · Offline ·
Reconnecting · Conflict · Synced. Typing must stay available when internet is down,
audio is uploading, transcription is delayed, AI is unavailable, or another device
disconnects.

## 19. Undo & version recovery
Undo · Redo · Block history · Restore deleted block · Restore earlier version ·
Recover unsynchronized edits · Review AI replacements. If one block changes on two
devices, **preserve both versions** rather than silently discarding one.

## 20. Responsive behavior
- **Desktop/web**: full block editor · persistent toolbar · drag handles ·
  transcript underneath · materials & AI beside the canvas · keyboard-first.
- **Tablet**: touch-friendly handles · collapsible toolbar · prominent pencil
  switch · selection actions above the keyboard · dragging must not fight scroll.
- **Mobile**: basic typing & block editing · simplified toolbar · Quick Notes from
  Panel 4 can be expanded · complex tables/diagrams/organization are easier on a
  larger device.

## 21. Required interface states (Panel 5 needs designs for)
Empty canvas · normal editing · live recording connected · note-only session ·
selected text · selected block · multiple blocks selected · AI suggestion pending ·
AI suggestion ready · transcript-linked block · slide-linked block · offline
editing · reconnecting · saving · sync conflict · read-only note · unsupported
content block · restored deleted block · large-note loading.

## 22. Technical data structure — `TypedBlock`
Block ID · Session ID · Parent section · Ordering position · Block type · Rich text ·
Formatting marks · Student-or-approved-AI origin · Created timestamp · Modified
timestamp · Creating device · Transcript anchors · Audio timestamps · Slide/material
references · Topic links · Assignment links · Study Studio selection state · Revision
number · Sync state.
Unapproved AI material is stored as a **separate `AISuggestion`**, not inside the
student block.

## 23. Performance expectations
Typing never depends on a network response · cursor position stays stable during
transcript updates · blocks save locally immediately · remote sync is debounced ·
AI runs asynchronously · large notes render progressively · moving one block does
not rewrite every block order · Typewriter↔Magic Pencil switch feels immediate.

## 25. Acceptance criteria — Panel 5 succeeds when
Students can take notes with **no AI enabled** · typing stays immediate while
recording + transcription run · keyword notes can receive optional AI expansions ·
student text is never silently replaced · blocks link to exact transcript & audio
moments · slides/source material stay traceable · manual block movement is
immediate · AI organization stays preview-based · notes stay editable offline ·
switching to Magic Pencil preserves both input layers · approved AI insertions
retain origin + sources · conflicting edits stay recoverable.

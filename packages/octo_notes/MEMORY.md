# OctoNotes — Project Memory

Durable facts about the OctoNotes app. Read this before working on `packages/octo_notes`.

## How we work (read first)
- **The UI is specified as numbered "Panels."** A mock/screenshot shows *what* a
  panel looks like; the written docs define *how* it must behave.
- **When a screenshot is ambiguous or underspecified, ASK for the panel's
  documentation before building.** The user has detailed written specs and will
  paste them. Don't guess behavior from pixels alone.
- Long specs live in `docs/` (one file per panel). `MEMORY.md` stays a short
  index of durable facts + pointers.

## Panel map (known so far)
- **Panel 1** — Home (`/notes`, `octo_notes_home_page.dart`). Built.
- **Panel 3** — **Live Session Hub** (ON-P03, **REDESIGNED** per boss/team, in
  progress). `/notes/session` = new simplified hub
  (`presentation/live/live_session_hub_page.dart`): a big **Live Transcription**
  strip with an **On/Off** toggle + an **animated single-line subtitle**
  (slides up one line at a time when On), then **two big tappable cards**
  (Typewriter · Magic Pencil) that each open **full-screen** (routes
  `/notes/session/type` and `/notes/session/pencil`, both reuse
  `OctoNotesSessionPage`; pencil passes `startInPencil: true`), plus **Summarize**
  (bottom-center) and **Finalize** (bottom-right → `/notes/review`). **No
  recording header** — Finalize replaces Finish Session. Borderless.
  **In-place swap (per the 2 team sketches, built):** the cards, Typewriter editor
  and Magic Pencil canvas all live in the hub's **middle region** — the Live
  Transcription strip + Subtitles (top) and Summarize/Finalize (bottom) stay
  persistent; a **Close (×)** on each editor returns to the cards. Typewriter view
  = `_TypewriterView`: a **Search** bar + a big note `TextField` + a right
  **"Relevant Data"** panel whose cards each have **"Add to note"** (appends into
  the editor) + an **Upload** button (bottom-left, typewriter-only). Magic Pencil
  view = reuses `MagicPencilWorkspace` (full canvas) + Close. All verified live.
  The old combined workspace (`octo_notes_session_page.dart`) is kept only at
  `/notes/session/full` for reference.
  **Finalize / Export screen (built):** hub **Finalize** → `/notes/finalize`
  (`presentation/live/session_finalize_page.dart`) — **replaces Panel 13 in the
  redesign flow** (per boss). Shows a **Summary** ("gist divided by topic" — one
  panel split into topic columns Glycolysis / ETC / Role of Oxygen, each with a
  per-topic include toggle so the student *chooses which content to take*), a
  **Smart Organization** panel (outline tree + category chips), and a **Download
  PDF** action (exports the included topics). Borderless. All verified live.
  **Still to do on this redesign:** the Typewriter note is a plain `TextField`
  (not the rich block editor P5); Search / Upload / Summarize / Download-PDF are
  **mocked** (sample data + snackbars — no real course search, file pick, AI
  summarize, or PDF generation yet); the finalize Summary/Organization content is
  hardcoded (not derived from the actual note). Panel 13 review still exists at
  `/notes/review` but the hub no longer routes to it. Full spec:
  `docs/panel-03-live-workspace.md`.
- **Panel 4** — Mobile recording companion / Quick Capture
  (`/notes/record`, `octo_notes_record_page.dart`). Built. This is what the
  *recording device* (a phone) shows: transport, quick-capture markers, live
  transcript peek. Mobile-first; also has a distributed desktop layout.
- **Panel 5** — **Typewriter** editor. The center canvas **inside the Panel 3
  shell** (`/notes/session`, `octo_notes_session_page.dart`). **Functional editor**
  backed by
  `domain/notes_controller.dart` + `domain/notes_models.dart`. Full spec:
  `docs/panel-05-typewriter.md`. Also reached via the New Session dialog.
- **Panel 6** — **Magic Pencil** canvas. Built (functional vector-ink) —
  `presentation/magic_pencil/magic_pencil_workspace.dart` +
  `domain/ink_controller.dart` + `domain/ink_models.dart`. Shown by the
  Typewriter/Magic Pencil toggle inside `/notes/session`; both layers share one
  session and persist across the toggle.
- **Panel 7** — **Live Transcript**. Built (functional) —
  `presentation/transcript/live_transcript_panel.dart` +
  `domain/transcript_controller.dart` (+ `_playback.dart`) +
  `domain/transcript_models.dart`. Full spec: `docs/panel-07-transcript.md`.
  Bottom dock of `/notes/session`: collapsed one-liner ⇄ expanded (≈46%) ⇄ full
  (≈82%, in-session, not a separate route).
- **Panel 8** — **Materials & Slides**. Built (functional split-view) —
  `presentation/materials/materials_panel.dart` +
  `domain/materials_controller.dart` + `domain/materials_models.dart`. Opens as
  the wide (500px) Materials rail panel in `/notes/session`. Full spec:
  `docs/panel-08-materials.md`.
- **Panel 9** — **Magic Bar & AI Assistant**. Built (functional) —
  `presentation/ai/ai_assistant_panel.dart` + `domain/ai_assistant_controller.dart`.
  Opens as the wide (500px) AI rail tab in `/notes/session`. Full spec:
  `docs/panel-09-ai-assistant.md`. (The Magic Bar "Ask OctoNotes" strip lives in
  the Typewriter footer; the inline suggestion cards are the same approval model.)
- **Panel 10** — **Research & Explanations**. Built (functional) —
  `presentation/research/research_panel.dart` + `domain/research_controller.dart`.
  Opens as the wide (500px) Research rail tab; Panel 9 "Research Further" routes
  here. Full spec: `docs/panel-10-research.md`.
- **Panel 11** — **Smart Organization**. Built (functional, preview-based) —
  `presentation/organization/organize_panel.dart` +
  `domain/organization_controller.dart`. Opens as the wide (500px) Organize rail
  tab. Full spec: `docs/panel-11-organization.md`.
- **Panel 13** — **Session Review & Finalize**. Built (functional, in-memory) —
  `presentation/review/session_review_page.dart` + `domain/review_controller.dart`.
  Own route `/notes/review`; the session top bar's **Finish Session** button
  navigates here. Full spec: `docs/panel-13-review-finalize.md`.
- **Panel 14** — **Study Studio Recommendations**. Built (functional, in-memory,
  **borderless**) — `presentation/recommendations/final_notes_page.dart` +
  `domain/recommendations_controller.dart`. Hosted on the finalized **Final
  Notes** view (`/notes/final`), reached from Panel 13's *Finalize & Save*. Full
  spec: `docs/panel-14-study-recommendations.md`.
- **Panel 15** — **Study Studio Conversion Preview**. Built (functional,
  in-memory, **borderless**) — `presentation/conversion/conversion_preview_page.dart`
  + `domain/conversion_controller.dart`. Own route `/notes/convert`, reached from
  Panel 14's *Review Study Studio Conversion* button. Full spec:
  `docs/panel-15-conversion-preview.md`. **This completes the 15-panel map.**

The 4 rail tabs are now each a real 500px panel (Materials=Panel 8, AI=Panel 9,
Research=Panel 10, Organize=Panel 11). The old placeholder `_RailPanel` /
`_OrganizePanel` / `_MiniSuggestion` / `_MaterialCard` in the session file were
removed.

## Panel 5 — Typewriter (core principles; details in `docs/panel-05-typewriter.md`)
- **Student's typed notes are the authoritative layer.** AI may suggest, explain,
  expand, research, categorize, propose movement — but **never silently rewrite,
  delete, or move student-written blocks.**
- Every block has a **stable ID**; unapproved AI content is a **separate
  `AISuggestion`**, never written into the student block.
- **Typing never waits on the network.** Save locally immediately; sync at
  **block level** (debounced); stay fully editable **offline** (Android & iOS).
- AI content stays **visually + technically distinguishable** (icon, tinted
  border, "AI Suggestion" label, source refs); origin + sources persist after
  insertion. Three inspectable origins: student-written · AI-inserted-by-student ·
  AI-suggestion-not-yet-inserted.
- AI organization is **preview-based** ("N changes ready to review"), never
  auto-applied during typing. Manual drag-reorder is immediate.
- Switching Typewriter↔Magic Pencil preserves both input layers, scroll, recording,
  transcript, and background AI.
- Canvas should read like a **clean academic document, not a chat window.**

### Panel 5 — what's implemented (as of this build)
The domain layer (`domain/notes_models.dart`, `domain/notes_controller.dart`) is
a **local-first, in-memory** store; there is no disk persistence or real backend
yet (sync is simulated at block level). Implemented:
- `TypedBlock` (stable IDs, all §22 fields, origin student vs AI) + `AiSuggestion`
  as a **separate** model. AI never mutates blocks — suggestions require approval.
- All 25 block types (text / academic / rich) with distinct rendering.
- Real per-block typing (immediate), markdown shortcuts (`#`/`-`/`[]`/`>`/`1.`),
  `/` slash menu, Enter=new block, Backspace-at-empty=merge.
- Drag-reorder + full block menu (duplicate/delete/convert/indent/outdent/move/
  link-slide/link-transcript/send-to-AI/add-to-Study-Studio/history).
- Focused-block action bar + text-selection context menu → create suggestions.
- AI suggestion cards (Insert Below / Add as Explanation / Replace Selection /
  Dismiss); approving inserts an **AI-origin block that keeps its sources**.
- Keyword-expand chip, sync-state footer (saved/saving/offline/reconnecting/
  conflict/synced) with an offline toggle + "Keep both" conflict resolve,
  structural undo/redo, Study Studio selection, empty-canvas state.
- Right rail: Materials (Panel 8), AI = live suggestions (Panel 9), Organize =
  preview-based "N changes ready to review" (Panel 11). Magic Pencil toggle
  preserves typed blocks (Panel 6 itself is a placeholder).

**Still not done** (see §18–19, §22 in the doc): real on-device persistence
(Hive/sqlite) + block-level remote sync, true version history / restore-deleted,
real conflict merge, table/diagram/image editing, rich-text marks (bold/italic
actually applied).

### Panel 6 — Magic Pencil (as of this build)
Functional, local-first, in-memory vector-ink canvas. Full spec:
`docs/panel-06-magic-pencil.md`. Implemented (P0 + some P1): real drawing
(pen/pencil/highlighter, pressure captured), stroke-erase, **lasso select**
(polygon + marquee fallback), shapes (rect/circle/line), text boxes, colour +
width, multi-page rail + Add Page, paper backgrounds (blank/lined/grid/dotted),
undo/redo, **vector stroke storage** (never flattened), "Original Ink Preserved".
Separate **recognition layer** (async, confidence %, Confirm/Correct) + **AI
Explanation** (Explain/Expand → Add as Typed Note / Send to Typewriter / Dismiss)
never mutate ink. **Convert to Text / Send to Typewriter** insert a Typewriter
block via `NotesController.addConvertedFromInk` with a `Magic Pencil · Page N ·
time` backlink — realising "two input layers in one session" (both persist
across the toggle).
**Not done** (P1/future): real handwriting OCR (recognition is mocked), formula/
diagram interpretation + clean previews, board-photo perspective tools, infinite
Free Canvas, palm/tilt/stylus tuning, and on-device persistence/sync.

### Panel 7 — Live Transcript (as of this build)
Functional, local-first, in-memory. Full spec: `docs/panel-07-transcript.md`.
Preserves **three layers** — `rawText` (never overwritten) · `faithfulText?` ·
`correctedText?`; `displayText` = corrected ?? faithful ?? raw. Implemented:
partial vs stable segments, "Live · N seconds behind", **Raw Transcript
Preserved**, Follow Live toggle + scroll-pause + **Jump to Live**, audio player
(play/pause/±10s/waveform-seek/speed/volume, "Audio from Hein's iPhone"), speaker
chips (Professor/Student/Unknown, low-confidence marker), per-segment markers
(Exam Hint etc.) + slide chips + ⋮ menu, **corrections** (Correct Text / Correct
Speaker / Restore Original — raw kept as revisions), select-segment action bar
(**Add to Notes / Explain / Research / Correct** + "Linked to Typewriter"),
search + filters (§16), bottom status, no-results state. **Add to Notes / Quote**
inserts a Typewriter quote block via `NotesController.addFromTranscript` with a
`Transcript · Speaker · time` backlink.
**Not done** (spec): real ASR/live streaming + partial→stable lifecycle,
post-class faithful pass + Compare-with-Raw, virtualized rendering for multi-hour
transcripts, real audio playback + word highlighting, multi-language, and the
full offline recovery/upload-pending flows.

### Panel 8 — Materials & Slides (as of this build)
Functional, in-memory split-view. Full spec: `docs/panel-08-materials.md`.
Non-destructive: original source never modified ("Original Source Preserved").
Model note: the page class is **`SlidePage`** (renamed from MaterialPage to avoid
clashing with Flutter's `MaterialPage`). Implemented: header (file selector,
Slide N of 24, prev/next), **Follow Lecture** toggle + manual-nav pause + **Return
to Live Slide**, "Active 18:20–21:05" window, in-document search, vertical
**thumbnail strip** (active highlight + link/annotation icons), a stylized slide
**preview** (schematic ETC diagram for slide 7; titled placeholder otherwise),
actions **Link to Note / Annotate / Ask AI / Add Excerpt**, Deck breadcrumb,
**Related Transcript** + Open in Transcript, "Linked to N note blocks". Cross-panel
wiring: Link to Note / Add Excerpt → `NotesController.addFromSlide` (source-linked
Typewriter block); Annotate → switches to Magic Pencil; Open in Transcript → opens
the Panel 7 dock.
**Not done** (spec): real file rendering (PDF/PPTX) + progressive loading, real
OCR + confidence-correction prompts, slide↔audio timeline detection, board-photo
perspective tools, The Deck browser + source versioning, offline caching states,
"What Did the Professor Add?", and most of the §26 interface states.

### Panel 9 — Magic Bar & AI Assistant (as of this build)
Functional, in-memory. Full spec: `docs/panel-09-ai-assistant.md`. Behaves like a
command system, not a chatbot. Implemented: **context chips** ("Using: Typewriter
Block / Transcript · 18:20–18:44 / Week 4 Slides · Slide 7", removable) + Change
Context (Whole Section / Whole Session); command field + quick commands
(Explain/Expand/Simplify/Summarize/What did I miss?); **source-grounded response
card** with per-point source chips, "Course sources agree" / conflict box; the
**What Did I Miss?** structured checklist (each point links to its evidence);
approval actions **Insert Selected / Insert Below / Add as Suggestions / Research
Further / Dismiss**; follow-up field; AI history model; "AI cannot change notes
without approval" footer. Approvals go through `NotesController.insertAiBlock`
(origin `aiInsertedByStudent`, sources retained) — never mutates student text
directly (spec §13, §27). Research Further routes to the Research rail (Panel 10).
**Not done** (spec): real LLM + streaming/cancel, real context resolution from the
live selection, Panel 11 organization routing preview, Quick Suggestions chips on
the canvas, grouped-by-location history UI, offline queueing, and most §23 states.

### Panel 10 — Research & Explanations (as of this build)
Functional, in-memory. Full spec: `docs/panel-10-research.md`. Evidence-gathering
(vs Panel 9's fast explanations). Implemented: context chips (Student Question /
Transcript · 19:02–19:08 / Slide 7); **scope selector** (Course Sources First /
External Sources) with "Course materials searched first"; editable research
question + follow-up; **Supported Explanation** card (AI interpretation, distinct
green, "N sources agree", "Every claim is linked to evidence"); **evidence cards**
(`SourceKind` → Lecture Transcript / Course Slide / Textbook…; excerpt kept
**separate** from the AI summary; external clearly labeled "External Source" +
trust badge; locator + Open button); approval actions **Add as Explanation /
Insert Below / Save Research / Dismiss** → `NotesController.insertAiBlock`;
"Nothing enters your notes without approval". Course sources are listed first;
external-only scope drops the course cards.
**Not done** (spec): real course/external search + ranking, Deep Research + async,
claim-level source markers inside the explanation text, source-conflict cards,
saved-research history UI, paywall/unavailable states, offline queueing, §29
states.

### Panel 11 — Smart Organization (as of this build)
Functional, **preview-based, non-destructive** (spec §3). Full spec:
`docs/panel-11-organization.md`. Implemented: header "N suggestions found"; scope
(Selected/Current section/Entire Note); Auto-Organize toggle; **Original ⇄
Organized Preview** toggle; **Suggestions / Outline / Categories** internal tabs;
category chips (Topics 3 / Definitions 4 / Questions 1 / Exam Hints 2); **Proposed
Outline** tree (Cellular Respiration › Glycolysis / ETC › Role of Oxygen · ATP
Synthase / Student Questions); **suggestion cards** (checkbox + reason +
confidence badge + block label + Dismiss); low-confidence shows "Placement
uncertain — review recommended" and is unchecked; preview summary (N sections /
blocks moved / categories); **Apply Selected / Apply All / Dismiss** as one
reversible pass; **Undo Last Organization**; "Original Notes Preserved — every
change is reversible". Apply marks proposals applied (removes from the list) and
enables Undo — it does **not** yet reorder real `NotesController` blocks (the note
has no section model yet), so this is the approval/preview layer only.
**Not done** (spec): real block/section reordering + metadata operations, live
"Organize New Content" placement, drag-reorder in the outline, persistent
organization rules, per-suggestion note highlighting, colour-coded preview diff,
and most §10 states.

### Panel 13 — Session Review & Finalize (as of this build)
Functional, in-memory, non-destructive, **borderless** (DESIGN.md). Full spec:
`docs/panel-13-review-finalize.md`. A full-screen review workspace reached from
**Finish Session** (`/notes/review`). Implemented: header (title · course/week ·
42:16 · **All Devices Synced** · **Review Required — N items** = open checklist
items); persistent **audio timeline** (play/pause · ±10s · pseudo-waveform with
progress fill · position/total · speed cycle · "Lecture Audio · Hein's iPhone");
**six review layers** in one panel with left-nav status indicators (green check =
reviewed · blue dot = open · yellow number = pending · red = problem · grey =
not processed) + "34 student blocks • 126 transcript blocks"; **comparison
workspace** — two `Compare With` dropdowns (default Student Notes vs Smart Notes),
per-layer block lists, **Show Changes** toggle for a clean reading preview;
block rendering by kind (H1 w/ red underline, sections, headings, bullets,
question/transcript/ink/AI **cards** on the sanctioned subtle surface) with
**provenance chips** (Student Typed · Transcript • 18:32 · Slide 7 · Magic Pencil
• Original Ink · AI Organized · External Research) and **§8 change chips** (green
Added · blue Moved · purple AI · red Excluded · yellow Edited); Smart-column
**block actions** (Open Source · Accept · Exclude → `acceptBlock`/`excludeBlock`);
right panel **Review Checklist** (N of 8, progress bar, clickable rows jump to the
affected layer) + **Save to The Deck** (Biology 101 / Lectures / Week 4 · Change)
+ **Originals Preserved** notice; bottom bar (Autosaving/draft-saved · Back to
Session · Save Review Draft · **Preview Final Notes** dialog (clean, included-only)
· **Finalize & Save** → §13 confirmation summary → `finalize()` marks Final Notes
reviewed). Cross-panel: session page **Finish Session** now routes to `/notes/review`
(back arrow still just pops).
**Not done** (spec): real transcript-uncertainty queue (§9) + AI approval queue
(§10) as focused resolvers, per-block "jump highlights matching source on the
other side" is text-key based only, real Deck destination picker, transactional/
idempotent finalization + session archive/manifest persistence, Panel 12 sync
gating, Panel 14 recommendations trigger, and most §14 states (Saving/Saved/
Offline/Conflict/Error). Finalize is allowed even with open items (finalizes
what's approved); no real Final Notes editing/reorder/restore yet.

### Panel 14 — Study Studio Recommendations (as of this build)
Functional, in-memory, **borderless** (DESIGN.md). Full spec:
`docs/panel-14-study-recommendations.md`. The finalized **Final Notes** page
(`/notes/final`) with a right recommendation drawer. Implemented: header (Final
Notes · title · "Saved to The Deck" as a dot+label); **finalized note** on the
left (success status line, Outline eyebrow-nav, sections w/ subtle source tags,
Student Question / Exam Hint as icon+coloured-eyebrow callouts, footer meta);
**recommendation drawer** — summary ("3 topics detected" + "2 Ready"/"1 Needs
Review" dot+labels + source note); **topic blocks** (checkbox + title + readiness
dot+label + counts meta + **activity chips** Teach Me/Quiz Me/Flashcards/
Lightning Recall/Scenarios + sources meta line + View in Notes / Why Recommended;
selected = faint red `OctoHoverRow` tint; Needs-Review not auto-selected, offers
Review Question / Include Anyway); **Choose Sections Manually** (flips to a
"14 blocks selected" manual summary); **selection summary** (Eyebrow + names +
Clear/Select-All-Ready); assurance lines; bottom **Not Now** / **Review Study
Studio Conversion** (enabled when ≥1 selected/manual → stubbed snackbar for Panel
15). Recommendation-only gateway: no Study Studio is created here.
**Not done** (spec): real topic detection/clustering + readiness scoring,
per-source "open the original block/slide/transcript", real manual block-picking
UI, topic customization (rename/merge/split), Already-in-Studio + Note-updated/
stale + Analyzing/Offline/Error states (§16), autosave/restore of selection, and
the actual Panel 15 handoff.

### Panel 15 — Study Studio Conversion Preview (as of this build)
Functional, in-memory, **borderless** (DESIGN.md). Full spec:
`docs/panel-15-conversion-preview.md`. Full-screen 3-column conversion checkpoint
(`/notes/convert`) reached from Panel 14. Implemented: header (title + "Review
exactly what OctoNotes will send…" + source + **Source Note Finalized**); a 3-step
**stepper** (Material Selected ✓ · Configure Activities • · Destination); **left**
Selected Material (metric groups 2 topics/19 blocks/2 transcript/1 diagram/3
slides, selected-topic rows w/ Edit, Source Coverage + Strong-coverage status,
coverage tags, source rows, Preview Sources, "Every generated activity will link
back to its source"); **middle** Proposed Learning Activities (per-activity row =
icon + name + target + **count stepper** + scope + toggle; Mock Exam disabled "Not
enough material"; **Learning Level** Foundation/Balanced/Challenging segmented;
Detected Topics w/ subtopics + coverage); **right** Destination (**Create New /
Update Existing** segmented; existing-studio match w/ mastery 68% / last studied /
topics; **Update Strategy** radios — Add New / Update Matching *(Recommended)* /
Keep Existing; "Preserve mastery and study history" assurance; **Conversion
Summary** metrics — topics / activity types / learning items planned (= Σ enabled
counts) / source connections; "Original OctoNotes material will remain unchanged");
bottom bar (draft saved · Back to Recommendations · Save Conversion Draft · Preview
Sources · "Nothing is created until you approve" · **Create/Update & Generate** →
§20 confirmation → `generate()` snackbar). Reuses `StudyActivity` from
`recommendations_controller`. Nothing is created and the source note is never
mutated until approval.
**Not done** (spec): real per-topic activity assignment UI, block-level
include/exclude + expand-to-blocks, topic rename/merge/split/reorder + warnings
(§9), real existing-vs-new diff (§17), Create-New full form, real generation job +
progress stages (§21) + success screen (§22) + Open Study Studio handoff, source
snapshots/idempotency/resumable job (§27), and the §23 states (Offline/Partial/
Error/Source-updated).

## What it is
- **Octopilothub is a super-app.** It hosts multiple detachable apps (Cockpit modules).
  - `study_studio` — Study Studio (existing app).
  - `octo_notes` — **OctoNotes** (this app: lecture recording, notes, transcription, AI processing).
  - The Deck, DocOct — future apps.
- OctoNotes plugs in as a `CockpitModule` (like `StudyStudioModule`), rootPath `/notes`.

## The Deck
- "The Deck" is a **future unification/storage system** across all apps.
- **Not built yet.** For now, wherever a note's storage location is needed, reuse
  the Study Studio (`study_studio`) equivalent — don't build a separate Deck.

## Design rules (must follow)
- **Desktop / PC layout first** (for now). Mobile comes later.
- **Default theme = Dark.** Light theme also exists and ships in-app; users switch
  it from Settings later. Light is **not pure white** — a warm **cream / off-white**
  (the shared `CockpitTheme` light surface `0xFFF6F1E7`), never clinical `#FFF`.
- **All buttons = Material "pill" design** (fully rounded). OctoNotes overrides the
  shared button radius (`md`) to `pill` in its own theme.
- **Single font: Plus Jakarta Sans** (400/500/600/700) for EVERYTHING — no
  secondary. **OFL**, bundled ONCE in **`cockpit_ui`** (shared) as family
  `packages/cockpit_ui/PlusJakartaSans`. Set in `BorderlessTheme.font`, reused by
  `OctoNotesTheme._font`. Package fonts need the `packages/<pkg>/<family>` prefix
  or they silently fall back — never use the bare name.
- History: Google Sans (proprietary, dropped) → Work Sans → Poppins →
  **Plus Jakarta Sans** (final). The design system now lives in `cockpit_ui`
  (`BorderlessTheme`) so OctoNotes AND Study Studio share one look — see [[../../cockpit_ui]].

## Design system — Borderless / typography-first (Swiss / GitBook)
📐 **Full spec: `DESIGN.md`** (read it before building any panel from a mockup).
Grouping comes from **whitespace, type hierarchy, alignment, proximity** — NOT
boxes. Implemented in `OctoNotesTheme` + `presentation/widgets/octo_widgets.dart`.
- ❌ no card borders, ❌ no heavy dividers, ❌ no card-on-card, ❌ no heavy
  shadows, ❌ not everything in a rounded rectangle.
- ✅ whitespace, ✅ strong type hierarchy (large tight headings), ✅ alignment,
  ✅ subtle background changes only where earned, ✅ proximity, ✅ restrained
  color (red = functional accent only).
- Shared borderless primitives: `Eyebrow` (muted section label), `OctoSurface`
  (subtle-fill group, no border), `OctoHoverRow` (interactive row, hover not
  outline), `OctoChip`, `LiveDot`, `Waveform`. Reuse these on every panel.
- Buttons: solid filled **pill** (primary, no ring); text/tonal for secondary.
- **Home page is the reference implementation** of this style. Modal + Session
  page still need converting to match (were built in the older bordered style).
- Use **proper Material icons** (rounded/outlined Material set), not ad-hoc glyphs.
- **Sidebar removed for now.** Instead, a **hamburger** icon sits at the top-left of
  the OctoNotes header (opens a Drawer holding the app nav).

## Panels built
- **1 Home**, **2 New Session** — fully borderless+Poppins (canonical style).
- **4 Record**, **5 Typewriter/session**, **6 Magic Pencil**, **7 Transcript**,
  **8 Materials**, **9 AI Assistant**, **10 Research**, **11 Organization** — built
  by a parallel effort (domain/ controllers + docs/panel-05..11); functional +
  theme-wrapped (Poppins) but NOT yet strict-borderless converted.
- **12 Connected Devices & Sync** (ON-P12) — `presentation/devices/`, opened from
  the session header's tappable "Live Sync" indicator. Borderless+Poppins.
- **13 Session Review & Finalize** (ON-P13) — `presentation/review/`, reached from
  the session's **Finish Session** button (`/notes/review`). Borderless.
- **14 Study Studio Recommendations** (ON-P14) — `presentation/recommendations/`,
  the finalized Final Notes page (`/notes/final`) reached from Panel 13's
  *Finalize & Save*. Borderless.
- **15 Study Studio Conversion Preview** (ON-P15) — `presentation/conversion/`
  (`/notes/convert`), reached from Panel 14. Borderless. **15-panel map complete.**
- Flow: session `/notes/session` (**P3 shell**) → Finish → `/notes/review` (P13) →
  Finalize → `/notes/final` (P14) → Review Conversion → `/notes/convert` (P15) →
  Generate.
- **Gaps: none structural** — all panels 1–15 exist (P3 = the session workspace).
  Remaining are P1 *behaviours* on P3 (see its doc): the three §10 session
  configurations (Take Notes / Capture Lecture / Both), and the §13 Stop-Recording
  vs Finish separation + "another device still recording" confirm dialog (Finish &
  Stop / Leave but Keep Recording / Cancel) + Leave-keeps-phone-recording.

## Hosting
- **Do NOT deploy/host until the whole app is finished.** Build locally end-to-end
  first; server hosting comes at the end.

## Home page (Page 1) — what a student must be able to do immediately
- Start a new note-taking session · begin recording a lecture instantly ·
  return to a live session running on another device · continue an unfinished note ·
  check transcription / AI-processing progress · open recent completed notes ·
  see material recommended for Study Studio · search notes and filter by
  course / status / date / note type · see where a note is stored in The Deck.

# Panel 3 — Live Session Workspace (ON-P03, full specification)

Authoritative spec. `MEMORY.md` holds the condensed status. **Panel 3 is the
shell that holds Panels 5–12 — it does not replace them.** It is the shared
environment where students type or write notes while recording, transcription,
materials, AI, research, organization and device sync operate around them.
Surface: full workspace (desktop/web/tablet; phone uses Panel 4 instead).

> **Already built** as `presentation/session/octo_notes_session_page.dart`
> (`/notes/session`). This doc records the spec + the P1 behaviours still open.

## 2. Core principle
The **note canvas is always central**. AI/transcription/slides support
note-taking without moving content or interrupting typing. Normal desktop
structure: top = session/recording controls · center = Typewriter or Magic Pencil
· bottom = Live Transcript · right = Materials/AI/Research/Organization · popover =
Connected Devices & Sync. **Only one right-side tool panel open at a time.**

## 3. Header + recording controls
Header: back to Home · title · course/topic · Deck destination · session status ·
recording timer · recording source · pause/stop · connected-device indicator ·
sync status · Finish Session · overflow. Recording controls: start · pause ·
resume · stop · add marker · view source. **Stop Recording and Finish Session are
separate** — a student may stop audio but keep writing.

## 4–5. Central canvas + switching
Center hosts Panel 5 (Typewriter) or Panel 6 (Magic Pencil) via a switcher.
Switching must NOT delete typed notes, flatten ink, interrupt recording, restart
transcription, replace one input layer with another, or jump the lecture
timestamp. Typed + handwritten stay **separate source layers** in one session; an
indicator can show the other canvas has content ("Magic Pencil · 3 pages").

## 6. Live Transcript (Panel 7)
Resizable bottom dock: collapse · expand · resize · follow live · pause
auto-scroll · jump to now · open full · select text · link a transcript moment to
a note block. New transcription must not rewrite earlier text or move the cursor.

## 7–8. Right tools + Magic Bar
Switchable tabs (one at a time, whole side collapsible): Materials (P8) · AI
Assistant (P9) · Research (P10) · Organization (P11). The **Magic Bar** stays
available without occupying space: a small command field · shortcut (⌘K) ·
text-selection toolbar · pencil-selection toolbar · AI tab. Commands: "Explain
this", "Give me an example", "What did I miss?", "Compare my notes with the
lecture", "Find a reliable definition", "Organize this section". Results are
suggestions/previews — **never auto-inserted**.

## 9. Cross-device (via Panel 12)
Phone records → desktop gets status → audio uploads in recoverable chunks → live
transcript (P7) → student types (P5) → a tablet can join for Magic Pencil → all
devices update one session. Header shows roles ("iPhone — Recording · MacBook —
Typewriter · iPad — Magic Pencil"). **Closing the desktop must not stop phone
recording.**

## 10. Three session configurations
- **Take Notes** — canvas active, recording disabled, AI/materials/organization
  still available, no mic permission.
- **Capture Lecture** — audio + transcript active, canvas minimal, markers/photos/
  occasional notes; post-class transcription if live fails.
- **Take Notes + Capture** — canvas + recording together, transcript follows, AI
  compares notes vs lecture, missed concepts suggested without rewriting.
Recording is optional, not the foundation.

## 11–12. Preservation + autosave
Preserve distinct layers: original audio/materials · raw transcript · typed notes
· original ink/diagrams · AI assistance · research · organization preview · final
approved notes. AI never silently erases/replaces; a proposal offers Insert /
Replace selection / Add beneath / Keep as linked explanation / Dismiss.
**Local-first**: notes, ink, markers save locally immediately, sync when possible.
Status: Saved / Saving / Offline / Reconnecting / Uploading audio / Transcribing /
Conflict. Canvas must not freeze while audio uploads, AI generates, materials load,
a device reconnects or the transcript updates.

## 13. Leaving / finishing
- **Leave Workspace** — returns to Panel 1, session preserved; if a phone is
  recording, it continues.
- **Stop Recording** — stops only audio; the note session stays open.
- **Finish Session** — ends capture and routes to **Panel 13**. If another device
  is still recording, ask: Finish Session and Stop Recording · Leave Workspace but
  Keep Recording · Cancel (prevents accidentally stopping the phone).

## 15. Responsive
Desktop: canvas gets most width; right tools ~25–30% when open; transcript = a
resizable bottom dock; tools can collapse to an icon rail. Tablet landscape:
canvas central, materials split-view, transcript small drawer, AI side drawer.
Tablet portrait: one surface dominates; tools/transcript as overlays; switching
preserves canvas position. Phone: use Panel 4, not a compressed desktop.

## 16. Required states
Loading (cached first) · Note-only · Live connected · Recording locally · Paused
(notes editable) · Offline capture · Reconnecting · Delayed transcription · AI
unavailable · Material unavailable · Sync conflict (localized) · Session ending
(secure pending) · Read-only (no edit permission / finalized shared view).

## 17–18. Architecture + performance
Coordinate **separate synchronized data layers** (session metadata · typed blocks
· ink pages/strokes · audio-chunk refs · transcript segments · material refs · AI
suggestions · research · organization proposals · device presence · layout prefs)
rather than one huge document — so transcript/audio/AI/editing update
independently; don't rebuild the workspace when one transcript segment changes.
Cached content appears almost immediately; typing/pencil never wait on network;
remote status ~2s; transcript appends without resetting scroll/cursor; AI/research
async; audio uploads in recoverable chunks; slides/PDFs load progressively.

## 19. Priority
P0 — header · Typewriter/Magic Pencil container · recording status/controls ·
bottom transcript dock · right-tab framework · connected-device status · autosave/
offline · leave/stop/finish · route to Panel 13. **(All P0 implemented.)**
P1 — flexible resizing · saved layouts · slide-following · "What Did I Miss?" ·
cross-device presence · transcript-to-note links · AI notes-vs-lecture comparison ·
advanced conflict recovery.

## 20. Acceptance
Type/write with no AI/network delay · recording optional · phone records while
computer takes notes · switching canvases preserves both layers · transcript
updates don't destabilize the canvas · one right panel visible · AI never changes
notes without approval · closing desktop doesn't stop phone · offline recover/sync
· Finish routes all preserved layers into Panel 13.

## Build status (this repo)
Implemented in `octo_notes_session_page.dart`: the P0 shell — header + recording
controls (pause/stop are still no-ops), Typewriter⇄Magic Pencil toggle preserving
both layers, right icon-rail with the four 500px panels (one at a time,
collapsible), Live Transcript bottom dock (collapsed ⇄ ~46% ⇄ ~82%), Magic Bar
("Ask OctoNotes" + ⌘K + selection toolbar), local-first autosave footer +
Go-offline, Live Sync popover (Panel 12), **Finish Session → `/notes/review`
(Panel 13)**.
**Not done** (P1 + spec gaps): the §10 session-configuration modes (Take Notes /
Capture / Both) aren't modeled; §13 Stop-Recording is a no-op distinct action and
the "another device still recording" three-way confirm dialog + Leave-keeps-phone-
recording aren't built; saved workspace layouts, drag panel-resizing, live device-
presence roles in the header, and real audio/transcription pipelines are pending
(shared with Panels 6–12's "not done").

# Panel 11 — Smart Organization (ON-P11, full specification)

Authoritative spec. `MEMORY.md` holds the condensed status. Panel 11 detects
topics/categories/structure and proposes an organized version **without altering
the original** — an intelligent organization layer, not an automatic rewriter.
Desktop/web/tablet (not a primary phone workspace).

## 1. Purpose
Turn messy live notes into a structured document without interrupting capture or
destroying the original. Identifies main topics/subtopics, definitions, examples,
formulas, questions, tasks, important facts, exam hints, research & AI
explanations — then proposes grouping, titling, reordering, or conversion.

## 3. Core principle — two layers
- **Original note layer** — preserves typing, handwriting, transcript blocks,
  diagrams, inserted material.
- **Organized note layer** — controls headings, categories, block placement,
  presentation.
Moving a block in the organized note must not erase/alter its source. Every action
is reversible.

## 4. Layout
Main workspace stays visible (mixed blocks); selecting a suggestion highlights the
affected blocks. The drawer has three internal views:
- **Suggestions** — individual proposals: affected block · current location ·
  proposed location · reason · confidence · Accept/Dismiss. Examples: "Move this
  question under Electron Transport Chain", "Convert this sentence into a
  definition", "Group these three blocks under Glycolysis", "Create a heading for
  ATP Production", "Move this professor example below the related definition".
- **Outline** — collapsible tree (Cellular Respiration › Glycolysis / Krebs Cycle
  / Electron Transport Chain › Role of Oxygen · Proton Gradient · ATP Synthase /
  Student Questions / Exam Hints); sections/blocks drag to reorder.
- **Categories** — detected content types (Topic / Definition / Example / Formula
  / Question / Task / Exam Hint / Research / AI Explanation); selecting one
  highlights matching blocks.

## 5. Main controls
Top: Organize Scope (Selected blocks / Current section / Entire note) · Auto-
Organize toggle · Preview Organized Version · status ("12 suggestions found").
Bottom: Apply Selected · Apply All · Dismiss · Undo Last Organization. The primary
button stays disabled until at least one proposal is selected.

## 6. Organization modes
- **Suggestions Only** (default) — detects improvements, changes nothing until
  approved. Safest.
- **Organize New Content Live** — new notes drop into existing sections by the
  student's rules, with a short reversible notice ("Transcript block added under
  Electron Transport Chain").
- **Full Note Organization** — analyzes the whole note, proposes a complete
  structure, previewed before applying.

## 7. Preview system
Preview opens a temporary view without changing the note. Switch Original ⇄
Organized Preview. Colour coding: green = new section/placement · blue = moved
block · yellow = recategorized · red = possible duplicate/conflict. Summary: "4
sections created · 8 blocks moved · 3 categories assigned · 1 possible duplicate".
Nothing is permanent until Apply.

## 8. Provenance preservation
Every organized block keeps its identity + source: Student Typed · Magic Pencil •
Original Ink Available · Lecture Transcript • 19:08 · Week 4 Slides • Slide 7 · AI
Explanation · External Research • OpenStax Biology 2e. Moving a transcript-derived
statement carries its timestamp/audio; organized handwriting still opens the
original ink; AI-created content stays visibly AI-marked.

## 9. Automatic rules
Persistent rules: keep student questions in their topic · unresolved questions in
a separate section · definitions before examples · formulas in dedicated blocks ·
transcript evidence beneath typed notes · professor exam hints in one section · do
not move diagrams automatically. Save for: current note / current course / all
future sessions.

## 10. Panel states
Normal · Analyzing ("Analyzing 48 note blocks…", typing continues) · Live update ·
No changes needed ("Your notes are already well organized") · Empty note ·
Low-confidence ("Placement uncertain — review recommended", never auto-applied) ·
Editing conflict (proposal pauses + recalculates) · Offline (existing usable, new
analysis queued) · Error (note unaffected).

## 11. Connections
Receives Typewriter blocks, Magic Pencil handwriting/diagrams, live transcript
blocks, material/slide refs, AI suggestions, research/explanation blocks. Panel 10
research enters as a labeled block Panel 11 can place but not rewrite. On save, The
Deck receives the organized version + outline/categories + source connections +
preserved original + organization history/undo. Improves Study Studio conversion
quality (flashcards from definitions, quiz from concepts, Teach Me from topics,
formula practice, scenario questions, Lightning Recall, review from unresolved
questions) but does not initiate conversion.

## 12. Data saved
Final section outline · block order · content categories · accepted proposals ·
dismissed proposals · student rules · auto-organize preference · organization
revision history · original-to-organized block relationships · source/timestamp
links.

## 13. Technical notes
The original note is a stable block ledger; organization mostly changes metadata,
not content. Block fields: Block ID · Session ID · content type · author type ·
source type · source reference · parent section ID · display order · semantic
category · AI confidence · created/updated · version. Proposals are stored as
operations: Create section · Move block · Group blocks · Assign category · Convert
block type · Merge headings · Flag possible duplicate. Only approved operations
mutate the organized view. Applying several proposals is **one reversible
transaction**. Live sync transmits block-order + section metadata without
duplicating/overwriting the original content.

# Panel 6 — Magic Pencil Canvas (ON-P06, full specification)

Authoritative spec for the Magic Pencil workspace. `MEMORY.md` holds the
condensed status; read this before extending the canvas.

## 1. Overview
Central editing canvas inside the Live Session Workspace (Panel 3). Primary
devices: tablets + stylus; secondary: desktop/web view + limited edit. Purpose:
preserve natural handwriting, diagrams, formulas, annotations while adding a
**non-destructive** layer of OCR, semantic recognition, AI assistance, and source
connections.

## 2. Main goals
Write with minimal latency · draw diagrams organically · write formulas/chemistry
· annotate slides/PDFs/images/board photos · search handwriting via background
recognition · select keywords for AI without losing ink · convert handwriting to
typed blocks · link ink regions to transcript timestamps · preserve original ink
as vector data · write offline · switch to Typewriter without losing content or
interrupting recording/transcription.

## 3. Core principle
- **Authoritative layer:** the student's original ink is preserved as the
  unchangeable Student Notes layer.
- **Separation:** recognition, AI annotations, cleanup live in a separate
  semantic/transparent layer.
- **No automated intrusion:** never auto-replace handwriting with text, flatten
  diagrams to images, correct formulas, move ink, erase shorthand, or clean up
  drawings without explicit approval. The student can always return to the exact
  original strokes.

## 4. Canvas modes
1. **Blank Notes** — blank/lined/grid/dotted paper + course templates.
2. **Annotate Material** — locked source under a separate transparent ink layer
   (slides/PDF/images/handouts/board photos); ink stored separately.
3. **Free Canvas (P1)** — infinite surface for mind maps/diagrams. Page-based +
   material annotation prioritised for V1.

## 5. Toolbar & writing physics
Tools: pen, pencil, highlighter, eraser, lasso, shape, text box, image, formula
region, pointer, colour, thickness, undo, redo. Controls: Add Page, Page
Overview, Change Background, Insert Material, Search Handwriting, More. Toolbar
supports left/right-handed placement. Physics: palm rejection, pressure, tilt,
smooth rendering, predictive stabilisation; stylus = ink, finger = navigate.
Local-first: rendering + save immediate, zero network dependency.

## 6. Stroke storage
Every stroke stored as **vector data**, not a flattened image. Each stroke:
coordinates, pressure, tilt, time, tool, colour, thickness, page ID, device ID,
audio timestamp, revision state — so it can be resized/recoloured/moved/undone
and stays searchable + audio-linked.

## 7. Recognition & confidence
Runs asynchronously **after a pause** (no active lag). Recognises words,
headings, bullets, numbered points, checklists, shorthand, underlining, circled
concepts, emphasis, arrows/connections, questions, labels. These form a **hidden
semantic layer** for search / AI context / topic detection / Study Studio — never
modifying visible handwriting. Confidence: **high** → auto into searchable layer;
**medium** → usable but inspectable; **low** → subtle suggestion ("Did you write
'ATP synthase'?" · Confirm / Correct / Ignore / Keep as Ink Only). Low confidence
never becomes authoritative without approval.

## 8. Lasso & AI operations
Lasso selects words/lines/formulas/diagrams/labels. Menu: Move, resize, copy,
duplicate, delete · **Convert to Text** · AI: Explain, Expand, Research, Organize,
Link Timestamp, Add to Study Studio. Keyword expansion references nearby ink +
transcript + slides + materials; result can be added as a typed explanation, a
handwriting-side card, sent to Typewriter, or kept in the AI panel — **original
ink untouched**. Handwriting→Typewriter shows original ink + recognised preview +
confidence warnings + destination; the typed block keeps a backlink ("Converted
from Magic Pencil · Page 3 · 18:32") and the ink remains.

## 9. Shape & formula interpretation
Diagram recognition: boxes, circles, arrows, lines, branches, timelines,
processes, cause/effect, labelled structures → explain, check missing labels,
convert to a clean diagram (preview, never auto-overwrite), or make study
questions. Formula recognition: fractions, exponents, subscripts, roots,
integrals, summations, matrices, chemical equations, accounting/stats → rendered
preview **beside** the handwritten original.

## 10. Source, board photo, audio sync
Board photos from Panel 4 imported as backgrounds to crop/rotate/correct-
perspective/highlight/label/annotate on a separate overlay. Strokes made while
recording group into timestamped regions; selecting a region's timestamp plays
audio, scrolls the Live Transcript (Panel 7), highlights the active slide, or
shows nearby typed notes.

## 11. Responsive
- **Tablet landscape:** full canvas, toolbar top/side, materials split view,
  transcript bottom drawer, AI right.
- **Tablet portrait:** maximise canvas, collapse toolbars, transcript/AI as
  overlays/drawers.
- **Desktop/web:** view, search recognised content, move/resize via mouse, typed
  comments, AI actions.
- **Mobile:** view pages, review recognition, simple annotations.

## 12. Roadmap
- **P0 (V1 core):** pen/highlighter/eraser/lasso · palm rejection + pressure
  vector strokes + stabiliser · multi-page, backgrounds, undo/redo, immediate
  local autosave · offline writing, non-destructive slide/PDF annotation,
  timestamp links · basic OCR, Typewriter switching, cross-device stroke sync.
- **P1 (future):** formula/diagram recognition + rendering · AI keyword expansion
  + handwriting→typewriter · deep search, shape cleanup, low-confidence
  correction · board-photo annotation · Study Studio selection + Free Canvas.

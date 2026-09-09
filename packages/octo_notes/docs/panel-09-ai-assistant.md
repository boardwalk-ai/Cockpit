# Panel 9 — Magic Bar & AI Assistant (ON-P09, full specification)

Authoritative spec. `MEMORY.md` holds the condensed status. Panel 9 behaves like
an **intelligent command system**, not a generic chatbot floating beside the
notes.

## 1. Main goals
Select exactly what AI analyzes · ask in natural language · explain/simplify ·
expand keywords · compare notes vs transcript/slides · identify what was missed ·
generate examples/definitions/questions · send searches to Panel 10 · send
structural changes to Panel 11 · insert/replace/retain/dismiss output · see which
sources produced an answer · keep student notes separate from AI.

## 2. Two surfaces
- **Magic Bar** — compact command field ("Ask OctoNotes or type a command…"),
  reachable via ⌘K, selected-text/ink toolbars, transcript/slide actions, the AI
  tab, or a mobile action sheet.
- **AI Assistant** — larger sidebar/drawer: active context · streaming response ·
  sources · suggestion actions · previous requests · follow-ups.

## 3. Context targeting
Targets: selected word/sentence · Typewriter block(s) · handwritten region ·
diagram · formula · transcript segment/time range · slide · PDF excerpt · board
photo · current section · whole note · whole session. **Use the smallest relevant
context by default.**

## 4. Context chips
Before submitting, show removable chips: `Using: Selected Typewriter Block ·
Transcript · 18:20–18:44 · Week 4 Slides · Slide 7`. Students can remove/add a
source, view source, change time range, Use Whole Section, Use Whole Session
(explicit — slower/costlier).

## 5. Core commands
Understanding (Explain/Simplify/Define/Give an Example/Explain Step by Step/Explain
This Diagram/Explain This Formula) · Expansion (Expand Keywords/Complete This
Thought/Add Missing Context/Add Professor's Explanation/Turn into Full Notes) ·
Comparison (Compare with Transcript/Slide · Compare Typed and Handwritten · Find
Contradictions · What Did the Professor Add? · What Did I Miss?) · Transformation
(Summarize/Shorten/Convert to Bullets/Turn into a Table/Turn into Questions/Create
a Definition Block/Rewrite More Clearly) · Routing (Research This / Organize These
Notes / Add to Study Studio Selection).

## 6–7. Natural language + routing
Free-text commands allowed; Panel 9 decides whether to answer directly or route:
Explain/simplify/expand + use attached slides/transcript → Panel 9 · external
search → Panel 10 · reorganize/move blocks → Panel 11 (preview) · change student
text → Panel 9 preview requiring approval · Study Studio content → Panel 15 ·
edit transcript → Panel 7 correction · clean handwriting → Panel 6 recognition.
Panel 9 coordinates but never duplicates other panels' full UIs.

## 8. Keyword expansion
Select keywords (`ETC — proton gradient — ATP synthase`) → Expand → grounded
answer with AI Suggestion label, source context, transcript timestamp, slide ref,
confidence, approval actions. The original keyword block stays untouched.

## 9. "What Did I Miss?"
Compares student notes vs relevant transcript range vs slides vs handwriting vs
markers vs existing AI additions. Result = "Missing from your notes" list; each
point links to its transcript timestamp / source slide. Actions: Insert Selected ·
Add as Suggestions · Open Sources · Dismiss.

## 10. Response-card structure
Request title · context used · AI content · source references · confidence/limits ·
output actions · follow-up field. Actions: Insert Below · Add as Explanation ·
Replace Selection · Keep in AI Panel · Copy · Research Further · Organize · Dismiss.
**Only Replace Selection modifies existing student text, and requires explicit
approval.**

## 11. Source grounding (priority order)
Selected student content → relevant transcript → attached slides/materials → other
authorized course notes → external research (Panel 10). Every grounded response
shows references (`Sources: Transcript · 18:32 · Week 4 Slides · Slide 7 · Magic
Pencil · Page 3`). If unsupported, say so clearly.

## 12. Source conflicts
Never silently pick one. Example: "Your note says '4 ATP', while the professor and
Slide 7 state a net gain of '2 ATP'." Actions: Review Transcript · Open Slide ·
Keep My Note · Correct My Note · Ask AI to Explain Difference.

## 13. Approval model
States: Generated → Previewed → Approved → Dismissed. Content stays an
`AISuggestion` until approval. Approve as: new block · beneath original · convert
to explanation · replace selection · side note · save only in AI history. All
changes support Undo.

## 14. Student/AI distinction
AI content: AI icon · pale tinted border · "AI Suggestion" label · source line ·
approval controls. AI must never mimic student handwriting, professor-quote
formatting, raw transcript, or original slide content. Approved AI text keeps its
origin metadata in the final note.

## 15. Live-session behavior
Stay closed unless opened · subtle suggestion counts ("2 AI suggestions ready") ·
no auto pop-ups · never move the active block · stream without blocking typing ·
allow cancel · queue completed answers · avoid re-analyzing the whole session.

## 16. Quick Suggestions
Optional quiet chips: Define term · Expand keywords · Missing explanation · Possible
exam hint · Connect to slide · Compare with transcript. Small chips, not big cards;
disable-able anytime.

## 17. Follow-ups
"Make it simpler." · "Give another example." · "Use only the lecture." · "Show
where the professor said this." · "Turn it into bullets." · "Research further." ·
"Add only the second point." Inherit the original context unless changed.

## 18. AI history
Session-specific: original command · context refs · response · sources · student
action · approval state · time. Grouped by source location (Typewriter · ETC ·
Transcript · 18:20–18:44 · Slide 7 · Magic Pencil · Page 3), not one endless chat.

## 19–20. Panel 10 / 11 relationships
Panel 10: if materials don't fully answer, offer "Research external sources?" →
opens Panel 10 with the question, context, sources already checked, requested
scope; external info is labeled + sourced. Panel 11: organize/group/outline/move →
Panel 11 produces a structural preview; Panel 9 never moves blocks directly.

## 21. Diagram & formula support
Analyze selected Magic Pencil regions: Explain Diagram · Identify Labels · Check
Missing Step · Convert Formula · Give Worked Example · Compare with Slide. AI gets
the recognition layer, original ink ref, nearby transcript, related material; the
result stays separate from the ink.

## 22. Responsive
Desktop/web: Magic Bar at the canvas bottom; AI as right-side tab; chips above the
input; results stream in the sidebar. Tablet: slide-over drawer; ink visible
beneath; chips scroll horizontally; touch-friendly inserts. Mobile: bottom-sheet
Magic Bar; quick commands first; concise responses; hand off heavy work.

## 23. Required interface states
No context · selected text/ink · transcript/slide context · multiple sources ·
generating · streaming · ready · inserted · dismissed · follow-up · source
conflict · insufficient context · research required · organization required ·
offline · AI unavailable · cancelled · error · rate/usage limit · read-only.

## 24. Offline
Manual notes stay available. When AI is down: commands can queue (student choice),
context preserved, cancellable; nothing auto-inserts on reconnect; completed
results appear as pending suggestions.

## 25. Privacy
AI reads only authorized session content · whole-session access is visible ·
external research doesn't expose private notes unnecessarily · history inherits
permissions · clearing history doesn't delete approved blocks · raw audio not sent
unless authorized · analytics carry no raw student content.

## 26. Data structure
- **AIRequest** — Request ID · Session ID · Command · Requesting user · Context
  refs · Target action · Created time · Processing state.
- **AIContextReference** — Object type/ID · Selected range · Transcript timestamp ·
  Slide/page ref · Permission state · Context snapshot version.
- **AISuggestion** — Suggestion ID · Request ID · Generated content · Source refs ·
  Confidence · Intended destination · Approval state · Student action · Revisions.
- **AIActionRecord** — Inserted / Replaced / Retained / Routed / Dismissed / Undone.

## 27. Architecture
Separate: context resolver · command router · course-material retrieval · AI
generation · source attribution · suggestion storage · approved-mutation service ·
AI history · Panel 10/11 routing. **The generation service never mutates student
blocks directly; approved actions go through the note-editing layer.**

## 28. Performance
Magic Bar opens immediately · chips resolve without reloading full files · short
commands respond within a few seconds · typing/pencil unaffected · streaming
cancellable · whole-session analysis async · safe caching for identical context ·
closed panels don't keep rendering.

## 29. Priority
- **P0** — Magic Bar · selected-text/transcript/slide context · Explain/Simplify/
  Expand/Define/Summarize · source refs · streaming · Insert Below/Replace
  Selection/Keep/Dismiss · AI/student distinction · session AI history.
- **P1** — handwriting/diagram context · What Did I Miss? · multi-source compare ·
  source-conflict detection · Panel 10/11 routing · Quick Suggestions · course
  vocabulary · whole-session analysis · Study Studio selection.

## 30. Acceptance criteria
Students always know the analyzed content · AI works on precise selections · notes
unchanged until approval · responses show sources · research → Panel 10 · structure
→ Panel 11 · no interruption to typing/handwriting · What Did I Miss links every
point to evidence · conflicts stay visible · approved AI retains origin · dismissed
suggestions don't reappear immediately · AI failure doesn't affect manual notes.

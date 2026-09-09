# Panel 15 — Study Studio Conversion Preview (ON-P15, full specification)

Authoritative spec. `MEMORY.md` holds the condensed status. Panel 15 is the final
OctoNotes checkpoint before selected notes become Study Studio material — a
**transparent, editable conversion checkpoint**, not a one-click black box or an
internal Study Studio learning screen. Nothing is created/updated until the
student gives final approval. Large modal / full-screen workspace (desktop/tablet
3 sections; phone = guided steps). Completes the 15-panel OctoNotes map; the
actual tutoring/quizzes/flashcards belong to Study Studio.

## 1. Purpose
Review exactly which notes transfer · detected topics/subtopics · included sources
· proposed activities · create-new vs update-existing · how existing mastery &
history are protected.

## 3. Entry paths
Receives material from Panel 14 (AI-recommended topics or manual selection),
individual blocks, one or several sessions, or notes chosen later from The Deck.
e.g. "2 topics selected · Glycolysis · Electron Transport Chain".

## 4–5. Structure & header
Header: "Study Studio Conversion Preview" + "Review exactly what OctoNotes will
send before generation begins." · source "Cellular Respiration Lecture · Biology
101 • Week 4" · status "Source Note Finalized" · #topics · #blocks · source
revision · AI-vs-manual · last saved. A **stepper**: 1 Material Selected (done) ·
2 Configure Activities (current) · 3 Destination.

## 6–7. Selected Material
Summary: "2 topics · 19 note blocks · 2 transcript excerpts · 1 Magic Pencil
diagram · 3 linked slides · 2 approved AI explanations". Selected topics listed;
each expandable to its exact blocks. Actions: Add Material · Remove Material ·
Return to Recommendations · View Original Note · Open Source. Block-level: every
block shows provenance (Final Notes · Student Typed · Magic Pencil • Original Ink ·
Transcript • 18:32 · Slide 7 · Approved AI explanation · Approved research ·
Student question · Exam hint) and can be **excluded from conversion without
deleting** it from OctoNotes/The Deck.

## 8–9. Detected Topics
Final topic hierarchy Study Studio will receive (Glycolysis › Location/Inputs/
Outputs/ATP/NADH; Electron Transport Chain › Inner membrane/Electron transfer/
Proton gradient/ATP synthase/Role of oxygen). Student can rename · merge · split ·
reorder · remove a subtopic · move a block between topics · add a custom topic —
**conversion only, never rewrites Final Notes**. Topic **warnings**: unresolved
question · low-confidence transcript · missing explanation · weak coverage ·
duplicate topic · AI needs approval · source unavailable → Review · Fix · Exclude
· Include knowingly · Return to Panel 14.

## 10–12. Proposed Learning Activities
Per-topic activities with proposed **generation targets** (not yet created):
Teach Me (2 lessons) · Quiz Me (15 questions) · Flashcards (24 cards) · Lightning
Recall (12 prompts) · Scenarios (4 applications) · Mock Exam (Not enough material →
not selected). Each activity: toggle on/off · adjust count · choose which topics ·
change learning level · why-recommended · supporting sources. **Learning Level**:
Foundation / Balanced / Challenging (default Balanced). Activities configurable
per topic so unsupported activities aren't generated everywhere.

## 13–14. Source coverage & traceability
Which materials support each topic (Glycolysis ← Final Notes, Transcript
18:25–18:44, Slides 4–6; ETC ← Student Notes, Transcript 19:02–19:16, Magic Pencil
diagram, Slides 7–8). Coverage: Strong / Partial / Needs review; selecting a
source opens the original block/timestamp/slide/diagram. **All generated Study
Studio material must retain source links** (flashcard→definition, quiz answer→Slide
7 + transcript 19:08, Teach Me→Final Notes section, scenario→student question,
diagram activity→original ink) and stay traceable inside Study Studio.

## 15–17. Destination
**Create New** (title/course/topics/optional description) or **Update Existing**
(match e.g. "Biology 101 — Cellular Respiration · existing topics Glycolysis &
Krebs Cycle · last studied 3 days ago · current mastery 68%"). Update modes: **Add
New Material** · **Update Matching Topics** (recommended) · **Keep Existing Content
Unchanged**. Any mode preserves prior mastery, quiz attempts, flashcard history,
spaced-repetition schedules, weak-area tracking, study progress, user-created
material. Show a compact existing-vs-new comparison and state "Existing progress
and study history will be preserved."

## 18–20. Summary, controls & confirmation
Summary (e.g. "2 topics · 19 source blocks · 5 activity types · 15 quiz questions
· 24 flashcards · 12 recall prompts · 4 scenarios · 7 source connections ·
existing mastery & history preserved · Nothing has been created yet"). Bottom bar:
Back to Recommendations · Save Conversion Draft · Preview Sources · **Create Study
Studio / Update Study Studio** (label follows destination). Must show "Study Studio
will use only the material shown in this preview" and "Original OctoNotes material
will remain unchanged." Confirmation dialog: destination · topics · activity types
· source count · existing-progress protection · expected AI generation → Create and
Generate / Update and Generate · secondary Continue Editing.

## 21–22. Generation & success
After confirm, a resumable handoff: Validating sources · Creating topic structure
· Generating Teach Me / quiz / flashcards / recall prompts · Connecting source
references · Finalizing. Student may leave; original notes stay available. Success:
"Study Studio is ready · Cellular Respiration · 2 topics · 5 activity types · 51
learning items · All sources linked" → Open Study Studio · Return to Final Notes ·
View in The Deck. This ends the OctoNotes handoff.

## 23. Panel states
Preparing preview · Preview ready · No material selected (→ Panel 14/manual) · No
activities selected (block start) · Existing Study Studio found · Source warning ·
Source note updated (Refresh / Continue with Saved Revision) · Offline (draft kept)
· Creating · Partially completed (retry failed portion without duplicating) ·
Conversion error (nothing damaged; retry safely) · Complete.

## 24. AI behaviour
Can: detect/organize topics, propose activities + counts, match an existing studio,
detect duplicates, generate approved activities after confirmation, link to
sources, explain suggestions. Cannot: include unselected material, use rejected AI,
modify the OctoNotes session, overwrite mastery history, create/update before
confirmation, or silently remove existing user-created study material.

## 25. Saved output
Conversion draft ID · source Final Notes IDs + revisions · selected topic/block IDs
· source refs · activity plan + counts · learning level · create-or-update choice ·
existing studio ID · update mode · approval · generation-job status · provenance
map · created studio ID · timestamp. Original note ↔ resulting studio reference
each other.

## 26. Connections
Panel 14 supplies topics/activities/blocks/sources; returning to 14 keeps the
draft. The Deck keeps the finalized note and gains a "Connected Study Studio: …"
relationship (not turned into a studio UI). After approval, Panel 15 creates/updates
the Study Studio and transfers topic structure, approved source material, the
activity-generation plan, provenance links and course metadata; all later learning
UI belongs to Study Studio.

## 27. Technical notes
Objects: StudyStudioConversionDraft · ConversionSourceSnapshot · SelectedTopic ·
SelectedSourceBlock · ActivityGenerationPlan · StudyStudioDestination ·
ExistingStudioMatch · UpdateStrategy · ConversionJob · GeneratedActivityManifest ·
SourceProvenanceMap. Rules: tie each draft to specific Final Notes revisions; store
immutable source snapshots; revalidate sources before conversion; idempotency key
for create/update; prevent duplicate generation on retry; resumable background job;
track each activity type independently; preserve successful results if one type
fails; never mutate the source note; diff new material vs existing studio; preserve
mastery/history on update; create bidirectional OctoNotes↔Study-Studio references;
retain block/slide/diagram/timestamp provenance. For an existing studio the update
is **additive and versioned** — do not replace the project until the new manifest
validates.

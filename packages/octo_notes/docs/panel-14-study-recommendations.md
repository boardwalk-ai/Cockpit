# Panel 14 — Study Studio Recommendations (ON-P14, full specification)

Authoritative spec. `MEMORY.md` holds the condensed status. Panel 14 analyzes the
**finalized** OctoNotes session and recommends which notes/sections/topic
clusters are complete enough to become Study Studio learning sessions. It is an
**intelligent recommendation + selection gateway**, NOT an auto-transfer. It only
prepares the selection — creation happens after approval in **Panel 15**.
Surface: embedded right drawer (desktop/tablet), bottom sheet (phone).

## 1. Purpose
Answers: what topics are present · which have enough to study · which sections go
together · what activities suit each · which still need clarification · new vs
existing Study Studio. Student accepts AI topics or picks parts manually.

## 3. Entry points
Opens right after Panel 13 finalizes ("Session finalized and saved to The Deck ·
OctoNotes found 3 topics ready for Study Studio" → View Recommendations / Not
Now). Also reachable later from the finalized session, the Deck note menu ("Turn
into Study Studio"), or the OctoPilot command bar. Dismissing never deletes it.

## 4. Layout
Finalized note stays visible; the drawer holds: (1) recommendation summary, (2)
filters/scope, (3) topic cards, (4) manual selection, (5) selection summary, (6)
Continue to Panel 15.

## 5. Summary
"Study Studio Recommendations · 3 topics detected • 2 ready • 1 needs review" +
source note "Cellular Respiration Lecture · Biology 101 • Week 4" + plain-language
explanation that it reviewed the approved Final Notes.

## 6. Scope
By default uses: approved Final Notes · student notes in Final Notes · approved
transcript excerpts · approved AI explanations · linked slides/materials ·
accepted research · final organization structure. Does NOT auto-use: rejected AI ·
excluded blocks · unresolved transcript · unapproved research · unrelated raw
transcript · deleted blocks · private material. "Include Additional Material" adds
from the preserved archive intentionally.

## 7. Topic cards (examples)
- **Glycolysis — Ready**: 6 concepts · 3 definitions · 2 examples · 1 exam hint ·
  2 slides. Activities: Teach Me · Quiz Me · Flashcards · Lightning Recall.
  Sources: Final Notes · Transcript 18:25–18:44 · Week 4 Slides 4–6. Actions:
  Select · View in Notes · View Sources · Why Recommended.
- **Electron Transport Chain — Ready**: 8 concepts · 4 definitions · 1 diagram ·
  2 student questions · 1 exam hint. Activities: Teach Me · Quiz Me · Flashcards ·
  Scenarios · Lightning Recall. Sources: Student Notes · Magic Pencil diagram ·
  Transcript 19:02–19:16 · Week 4 Slides 7–8.
- **Role of Oxygen — Needs Review**: one unresolved student question + one
  low-confidence transcript phrase. Actions: Review Question · Play Audio · Add
  Missing Explanation · Include Anyway · Exclude. **Not auto-selected.**

## 8. Readiness (four states)
**Ready** (sufficient approved+connected material) · **Needs Review** (useful but
unresolved question / transcript uncertainty / weak sources) · **Limited
Material** (detected but not enough) · **Already in Study Studio** (course match →
Update Existing / Create Separate / Ignore). Panel 15 shows the final
create-vs-update choice.

## 9. Readiness signals
Topic coherence · usable concept count · definitions/explanations · examples ·
questions/exam hints · source coverage · transcript confidence · diagrams/formulas
· Panel-13 approval · existing-studio match · outstanding sync/conflict. Show a
plain-language "Why this is ready", not just a score.

## 10. Activity recommendations (only suggestions; Panel 14 does NOT generate)
Teach Me (explanations/processes) · Quiz Me (testable facts) · Flashcards
(definitions/terms/formulas) · Lightning Recall (rapid retrieval) · Scenarios /
Oral Exam (applied reasoning) · Mock Exam (enough assessment-style material).

## 11. Selection controls
Per-card checkbox. Global: Select All Ready · Clear Selection · Ready Only · Needs
Review · Already in Study Studio · Choose Sections Manually. Multiple clusters go
to Panel 15 together. "2 topics selected · Glycolysis and Electron Transport
Chain" → primary **Review Study Studio Conversion**.

## 12. Manual selection
"Choose Sections Manually" flips the note into selection mode: entire note · one
heading · multiple sections · individual blocks · a diagram · student questions ·
transcript excerpts · linked slides · approved research. Summary e.g. "14 blocks
selected · 2 transcript excerpts · 1 Magic Pencil diagram · 3 linked slides", then
moves to Panel 15 like an AI selection.

## 13. Topic customization (affects only the conversion selection, never Final Notes)
Rename · merge clusters · split · remove a block · add a section · include/exclude
a source · change activities · assign course · mark as exam prep.

## 14. Source traceability
Each topic shows origins: Final Notes · Student Typed · Magic Pencil • Original
Ink · Transcript • 18:32 · Week 4 Slides • Slide 7 · AI Explanation • Approved ·
External Research • OpenStax Biology 2e. Selecting a source opens the original;
the link must survive conversion.

## 15. Student-control assurance
Bottom: "Nothing will be created without your approval." Student owns which topics
/ blocks / unresolved material / activities are used, new-vs-existing studio, and
whether conversion happens at all.

## 16. Panel states
Analyzing ("Finding topics ready for Study Studio…", note stays usable) ·
Recommendations ready · No recommendations (manual still available) · Needs review
· Existing session detected · Note updated ("based on an earlier version" →
Refresh / Continue with Previous) · Offline (existing visible, new analysis waits)
· Analysis error (note stays safely finalized) · Source unavailable (recommendation
flagged).

## 17. AI behaviour
Can: detect topics/subtopics, group blocks, judge sufficiency, recommend
activities, detect unresolved questions + weak sources, suggest merge/split,
identify an existing related studio. Cannot: create a session automatically,
include rejected material, treat AI text as student-written, remove anything from
Final Notes, resolve unclear transcript without approval, or send to Study Studio
without the student continuing through Panel 15.

## 18. Saved state
Source Final Notes ID + revision · recommendation IDs · cluster names · included/
excluded block IDs · source refs · readiness states · recommended + student-
selected activities · selected topics · dismissed recommendations · manual
selections · existing-studio matches · last analysis time · recommendation
version. Selections persist across close/reopen.

## 19. Connections
Panel 13 supplies the approved Final Notes (never silently includes excluded
content). Panel 14 passes to Panel 15: selected clusters · selected blocks ·
sources · suggested activities · manual changes · possible existing-studio
matches. The Deck stores the finalized note; Panel 14 reopens from it but is not
part of the Deck file manager. Study Studio: Panel 14 recommends the handoff only.

## 20. Technical notes
Objects: StudyRecommendationSet · StudyTopicCandidate · TopicCluster ·
ReadinessAssessment · ActivityRecommendation · SourceSelection · ManualSelection ·
ExistingStudioMatch · ConversionDraft. Each candidate: recommendation ID · Final
Notes ID + revision · title · included block IDs · source refs · readiness status
+ reasons · suggested + student-selected activities · existing-studio match ·
selection state · timestamps. Rules: tie recommendations to a Final Notes
revision; editing Final Notes marks older recommendations stale; cluster at block
level; source links survive conversion; selection autosaves; duplicate detection
is course-aware; produce a **conversion draft**, not activities; reopening
restores the last selection; repeated attempts must not create duplicate studios.

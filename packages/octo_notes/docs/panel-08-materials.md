# Panel 8 — Materials & Slides (full specification)

Authoritative spec for the materials/slides panel. `MEMORY.md` holds the
condensed status; read this before extending it. Implementation note: the page
model is `SlidePage` (renamed from the spec's `MaterialPage` to avoid clashing
with Flutter's `MaterialPage`).

## 1. Main goals
View materials beside notes · move quickly between files/pages/slides · follow the
professor's current slide · link slides to transcript timestamps · trace links to
typed/handwritten notes · annotate via Magic Pencil · select on-screen text (OCR)
· ask AI about a page/selection · compare slides vs spoken explanation · use Deck
files without duplicating the Deck UI · access materials offline · preserve the
exact original source.

## 2. Core principle — separate, non-overlapping layers
Original Source · rendered preview · extracted/OCR text · student annotations ·
transcript & note connections · AI interpretations. **AI, OCR, and annotations
must never modify the original file.**

## 3. Supported materials
PDF · PPTX · slide images · photos · whiteboard photos · scanned handouts ·
course diagrams · Deck files · on-the-fly uploads from a connected device. (More
formats + web sources later.)

## 4. Layout states (not separate panels)
- **Sidebar** — narrow: current slide, basic nav, material selector, quick actions.
- **Split View** — notes + materials side-by-side (~60–70% notes / 30–40%
  materials on desktop).
- **Expanded Viewer** — material takes over the workspace for deep reading, search,
  OCR correction, annotation, page linking.

## 5. Header
Current material name · material selector · Add Material · local search · page/
slide numbers · Follow Lecture status · expand/collapse · more actions. Example:
`Week 4 Slides · Slide 7 of 24 · Following Lecture`.

## 6. File selector
Each entry: file type · page count · upload status · OCR status · annotation count
· Deck location · offline availability.

## 7. Page/slide navigation
Prev/Next · direct page input · thumbnail strip · heading outline · in-document
search · zoom (Fit width / Fit page) · rotation · full-screen. Arrow keys when
focused; scroll position preserved when returning to the note canvas.

## 8. Thumbnails & outline
Thumbnails overlay icons for: active slide, transcript links, linked note blocks,
Pencil annotations, user markers, available AI explanations. Outline = PDF
bookmarks or extracted headings.

## 9. Follow Lecture
Keeps pace with the instructor's active slide via: manual changes from other
students · Panel 4 "Slide Change" markers · uploaded presentation timeline ·
transcript context · image comparison · AI detection (suggestions only if low
confidence). Manual page change pauses Follow Lecture (no forced snap-back); a
**Return to Live Slide** button appears.

## 10. Slide↔audio sync
Each active window records material/slide ID, start/end timestamps, detection
method + confidence, manual corrections, related transcript segments + markers.
Example: `Slide 7 active from 18:20–21:05`. Selecting it plays that audio and
scrolls Panel 7 to the moment.

## 11. Transcript connections
Shows transcript moments tied to the slide, e.g. `18:32 — "The net result is two
ATP and two NADH."`. Actions: Open in Transcript · Play Audio · Add to Notes ·
Correct Slide Link · Remove Link. One slide can connect to multiple timestamps.

## 12. Typewriter connections
Link Current Slide · Insert Slide Preview · Insert Selected Image · Add Text
Excerpt · Add Diagram · Create Source Block · Link Current Note Block. Blocks are
labeled with a source ref (`Week 4 Slides · Slide 7`) that resolves even if moved.

## 13. Magic Pencil connections
"Annotate" opens the sheet as a locked background in Panel 6; ink lives on a
separate overlay. Returning shows an overlay icon on the thumbnail; the file is
never flattened.

## 14. Text extraction / OCR
Searchable layer across native PDF text, slide layout text, scans, embedded
photos, diagram node labels. Selecting text → Add to Notes / Explain / Define /
Research / Compare / Copy / Link to Transcript / Correct OCR. Extracted text stays
in a separate hidden index.

## 15. OCR confidence
High → auto searchable/selectable. Medium → selectable, marked auto-extracted.
Low → correction prompt (Confirm / Correct / Ignore / Use Image Only). AI won't
quote low-confidence OCR without an uncertainty warning.

## 16. Whiteboard/slide photography
Phone captures (Panel 4) sync here: perspective correction, crop, rotate,
brightness/contrast, OCR + ink overlays, auto timestamp linking, "Mark as board
photo" / "Replace slide preview". `Whiteboard Photo · Captured at 18:44`; original
always recoverable.

## 17. AI actions
Explain This Slide / Summarize This Page / Define Selected Term / Give an Example /
Compare with My Notes / What Did the Professor Add? / Find Missing Context / Create
Review Questions / Research This Claim. Attached materials are primary context
before web search; outputs are drafts requiring approval.

## 18. "What Did the Professor Add?"
Compares slide content vs transcript during the slide's window vs the student's
notes; isolates verbal examples, off-slide definitions, warnings, exam hints,
assignments, spoken corrections — each linked to exact timestamps.

## 19. Adding materials
Upload via file explorer / camera / photos / drag-drop / Deck / mobile push.
Background tasks: upload progress, render preview, thumbnails, OCR, offline cache.
The note canvas stays interactive during processing.

## 20. The Deck relationship
Compact navigator: file name + save location, last modified, permissions. Path
`The Deck / Biology 101 / Resources / Week 4 Slides`. Actions: Open in The Deck /
Attach to Session / Manage Versions. Does not replicate full folder admin.

## 21. Source versioning
A session freezes the file version used in class. Newer upload → "A newer version
is available": Keep Session Version / View New Version / Replace and Preserve
Links. Replacing must not break timestamps, notes, or annotation refs.

## 22. Source preservation
Catalog: file hash, original filename, size, uploader + timestamp, version, Deck
path, permissions, previews, OCR indices, ink layers. Removing from a session does
not delete the original from The Deck.

## 23. Offline
"Available Offline" caches current doc, layouts, thumbnails, OCR/native text, ink,
and all transcript/note links. Offline: navigate cached pages, draw ink, queue new
links for sync. Uncached pages show "Unavailable Offline".

## 24. Cross-device
Desktop/web: split navigation, deep search, OCR, AI. Tablet: full-canvas split,
stylus overlay, thumb thumbnail scrub. Phone: capture board photos, upload
handouts, monitor current slide, track markers. Slide number + nav sync when
Follow Lecture is active.

## 26. Required interface states
No materials · uploading · processing/rendering · viewing · Follow Lecture active/
paused · search active · OCR processing · low-confidence OCR prompt · annotation
mode · offline cached/unavailable · upload failure · unsupported format · missing
permissions · source removed · newer version detected · broken trace links ·
read-only presentation · high-volume progressive loading.

## 27. Privacy & security
Materials inherit Deck folder permissions · no access via guessed URLs · AI reads
only authorized/attached materials · malicious files rejected · sharing a note
doesn't distribute the background PDF unless shared · clippings carry origin refs.

## 28. Data structure
- **`MaterialAsset`** — MaterialID · SessionID · FileType · OriginalFilename ·
  StorageURI · FileHash · Version · DeckLocationID · PageCount · ProcessingState ·
  OfflineCachedState · PermissionState.
- **`SlidePage`** (spec: MaterialPage) — PageID · MaterialID · PageNumber ·
  ThumbnailURI · PreviewURI · NativeTextContent · OcrTextContent ·
  OcrConfidenceScore · BoundingBoxes.
- **`MaterialTimelineLink`** — LinkID · PageID · AudioStart/End · TranscriptSegment
  IDs · DetectionMethod · DetectionConfidence · UserVerificationStatus.
- **Additional** — AnnotationLayer · TypewriterSourceLink · MagicPencilSourceLink ·
  BoardPhotoMetadata · SourceRevision · AiContextReference.

## 29. Performance
Thumbnails before hi-res pages · preload current + adjacent · progressive PDF
render · async OCR · slide changes never delay typing/recording · opening a bundle
doesn't download every attachment · cached slides < 100 ms · slide-metadata updates
never re-render the note workspace.

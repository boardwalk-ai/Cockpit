# Study Studio mobile — Chris + Amirjon

Shared branch: `intern/amirjon-chris/study-studio-mobile`.

## One remaining task — Amirjon: Teach Me mobile

- [ ] Finish and verify the independent mobile layout in
  `lib/src/presentation/teach_me/teach_me_page.dart`.

Keep the existing lesson/AI behavior and desktop presentation. Use the shared
`isMobilePlatform(context)` gate from `widgets/studio_scaffold.dart` and the
mobile components in `widgets/mobile_layout.dart`. The route already inherits
48px standard Material control targets through `StudyMobileSurface`.

Acceptance: readable lesson, examples and source material at 320px and 390px;
no horizontal overflow; reachable controls with the keyboard open; lesson/AI
interactions preserved; wide desktop unchanged. Add Teach Me to the page matrix
in `test/presentation/mobile_layout_test.dart` and exercise its lesson flow.
This page's implementation was deliberately left untouched for Amirjon.

## Chris's completed scope

Audited the other 19 routed pages against the latest upstream implementation.
Existing independent phone bodies are reused where appropriate rather than
replacing their state or business logic. Fixed mobile-only layout problems and
added the shared platform gate and control theme.

| Pages | Mobile work |
| --- | --- |
| Home, dashboard | Stacked resume content; wrapping metadata and actions |
| Upload, building, ready | Wrapping CTAs and captions; vertical build statistics |
| Topic library, topic detail | Shared mobile gate; labelled, bounded filters; wrapping topic metadata |
| Quiz, recall, scenario | Wrapping headings, progress and confidence labels; recall statistics reflow |
| Flashcards | Existing independent mobile body retained and verified |
| Progress, mastery report | Separate progress list; one-column report and vertical learning journey |
| Study plan, knowledge graph | Wrapping topic details; vertical mobile schedule; graph gestures retained |
| Analytics | Full-width chart cards rather than cramped side-by-side cards |
| Ask AI | Mobile context bottom sheet restores access to desktop sidebar content |
| Manage | Vertical version history and wrapping update details |
| Welcome back | Independent readable phone overview with large tool rows and stacked insight cards |

`isMobilePlatform` selects Android/iOS or a viewport narrower than 900px. Wide
desktop retains its existing widget branches. Standard controls have a 48px
minimum target on mobile. No repository, API, AI or authentication behavior was
changed. Existing demo/placeholder features retain their original behavior.

## Verification

From `packages/study_studio`:

```sh
flutter test test/presentation/mobile_layout_test.dart
```

The matrix loads the bundled Outfit font and exercises all 19 pages at 320px,
390px and 1280px, including scrolling, plus Android/iOS/Windows gate checks.
Browser preview uses test-only provider overrides outside the repository;
production data sources remain unchanged. Browser checks cover mobile search,
the context sheet, mobile/desktop rendering, and runtime errors.

The PR remains draft until Amirjon finishes Teach Me. Do not mark the entire
assignment complete or merge it while that checkbox remains open.

# Octopilot Cockpit — Project Architecture

**App:** Octopilot Cockpit (Flutter super-app, Web + Android + iOS)
**First module:** Study Studio (detachable, feature-flagged)
**Backend:** custom API (REST + streaming) — Flutter is a client
**AI:** behind a swappable `AiService` interface (provider decided later)

---

## 0. Stack decisions (determined)

| Concern | Choice | Why |
|---|---|---|
| Repo layout | **Melos monorepo** (`apps/` + `packages/`) | True detachable modules; each module is its own package |
| State management | **Riverpod** (`flutter_riverpod` + `riverpod_generator`) | Modular, testable, no BuildContext coupling |
| Routing | **go_router** | Declarative, deep links + clean web URLs, per-module route trees |
| Models / immutability | **freezed** + **json_serializable** | Sealed unions, copyWith, JSON for the API |
| Networking | **dio** (wrapped in `ApiClient`) | Interceptors, streaming, retries |
| Local cache | **hive** (light) | Offline study objects, flashcard due dates |
| Module contract | `CockpitModule` interface + `ModuleRegistry` | Shell loads only enabled modules |
| Flags | build config + backend RemoteConfig + local override | `study_studio_enabled = yes/no` |

> Override-friendly: swap Riverpod→Bloc or Melos→single-app without touching the layering; the package boundaries stay.

---

## 1. Top-level folder structure

```
cockpit/                              # repo root = H:\Cockpit
├── melos.yaml                        # monorepo orchestration (bootstrap, scripts)
├── pubspec.yaml                      # workspace root (Dart workspaces)
├── analysis_options.yaml             # shared lints
├── README.md
├── docs/
│   ├── ARCHITECTURE.md               # this file
│   ├── DATA_MODELS.md                # Study Object schema + backend models
│   └── API.md                        # endpoint contract
│
├── apps/
│   └── cockpit/                      # the runnable shell super-app
│       ├── lib/
│       │   ├── main_dev.dart         # flavor entrypoints
│       │   ├── main_prod.dart
│       │   ├── bootstrap.dart        # init: env, DI, error zone
│       │   ├── app.dart              # MaterialApp.router + global theme
│       │   ├── routing/
│       │   │   └── app_router.dart   # go_router; aggregates module routes
│       │   ├── modules/
│       │   │   └── registered_modules.dart   # module list, gated by flags
│       │   ├── home/                 # Cockpit Home (app launcher grid)
│       │   └── settings/             # global settings, module toggles, theme
│       ├── assets/                   # see §4 Media
│       ├── android/  ios/  web/      # platform shells (from `flutter create`)
│       └── pubspec.yaml
│
├── packages/
│   ├── cockpit_core/                 # foundation: network, config, module contract
│   ├── cockpit_ui/                   # design system = GLOBAL CONTROLS (§3)
│   ├── cockpit_module/               # CockpitModule interface + registry types
│   └── study_studio/                 # THE detachable module (§ Frontend)
│
└── backend/                          # custom API (separate service, §6)
```

---

## 2. Pages (screens)

### Cockpit shell (apps/cockpit)
| Page | Route | Purpose |
|---|---|---|
| Cockpit Home | `/` | App launcher — tile per enabled module |
| Settings | `/settings` | Global theme controls + **module toggles** |

### Study Studio module (packages/study_studio) — spec screen order
| # | Page | Route | MVP? |
|---|---|---|---|
| 1 | Study Studio Home | `/study` | ✅ |
| 2 | Upload Materials | `/study/upload` | ✅ |
| 3 | Building / Processing | `/study/build/:jobId` | ✅ |
| 4 | Studio Dashboard | `/study/:studioId` | ✅ |
| 5 | Topic Library | `/study/:studioId/topics` | ✅ |
| 6 | Topic Detail | `/study/:studioId/topics/:topicId` | ✅ |
| 7 | Teach Me | `/study/:studioId/teach/:topicId` | ✅ |
| 8 | Quiz Me | `/study/:studioId/quiz` | ✅ |
| 9 | Flashcards | `/study/:studioId/flashcards` | ✅ |
| 10 | Progress / Weak Topics | `/study/:studioId/progress` | ✅ (basic) |
| 11 | Lightning Recall | `/study/:studioId/recall` | Phase 2 |
| 12 | Scenario Mode | `/study/:studioId/scenario` | Phase 2 |
| 13 | Visualize | `/study/:studioId/visualize/:topicId` | Phase 2 |
| 14 | Review Schedule | `/study/:studioId/review` | Phase 2 |

Each page lives in `presentation/<page>/` with a `*_page.dart` (route widget) + `widgets/` (page-local) + a Riverpod controller in `application/`.

---

## 3. Global controls (design system → `packages/cockpit_ui`)

The two global control axes from the brief — **Colors (Primary, Secondary, Tertiary)** and **Fonts (Primary, Secondary, Tertiary)** — are design tokens, theme-able and remote-overridable.

```
packages/cockpit_ui/
└── lib/
    ├── cockpit_ui.dart                  # barrel export
    └── src/
        ├── tokens/
        │   ├── color_tokens.dart        # primary, secondary, tertiary + surface/semantic
        │   ├── typography_tokens.dart   # fontPrimary, fontSecondary, fontTertiary + text styles
        │   ├── spacing_tokens.dart
        │   └── radius_tokens.dart
        ├── theme/
        │   ├── cockpit_theme.dart        # ThemeData light/dark built from tokens
        │   └── theme_controller.dart     # Riverpod controller (runtime swap + remote)
        └── components/                   # shared widgets used app-wide
            ├── buttons/  cards/  chips/  inputs/  progress/  empty_states/
```

- `color_tokens.dart` exposes `primary / secondary / tertiary` (+ derived surfaces, on-colors, semantic success/warn/error). One place to rebrand the whole app.
- `typography_tokens.dart` maps `fontPrimary / fontSecondary / fontTertiary` to families (§4) and builds the `TextTheme`.
- `ThemeController` lets these be changed at runtime (and later pulled from backend RemoteConfig), satisfying "might add more later."

---

## 4. Media (assets → `apps/cockpit/assets/`, declared in pubspec)

```
assets/
├── fonts/              # Primary / Secondary / Tertiary families (.ttf/.otf)
├── images/
│   ├── branding/       # logo, wordmark, splash
│   └── illustrations/  # empty states, onboarding
├── icons/              # module icons (Study Studio tile), nav icons
└── animations/         # Lottie for Building/Processing screen step animations
```

- **Fonts** wired in `pubspec.yaml` under `flutter: fonts:` and referenced only via `typography_tokens.dart` (never hard-coded in widgets).
- **Building screen** uses `animations/` (Lottie) so processing shows real step cards, not a bare spinner (per spec).
- Module-specific media can also live in `packages/study_studio/assets/` and be exported by the package.

---

## 5. Module controls (feature flags → `packages/cockpit_core` + shell)

The detachability contract. Every module implements `CockpitModule`; the shell only mounts enabled ones.

```
packages/cockpit_module/lib/src/
├── cockpit_module.dart        # interface: id, title, icon, routes(), launcherTile(), init()
├── module_manifest.dart       # metadata + default-enabled
└── module_registry.dart       # holds active modules, builds aggregate routes

packages/cockpit_core/lib/src/config/
├── app_config.dart            # env, base url, flavor
├── feature_flags.dart         # FeatureFlags { studyStudioEnabled: bool, ... }
└── remote_config.dart         # fetch/override flags from backend
```

```dart
abstract class CockpitModule {
  String get id;                       // 'study_studio'
  String get title;                    // 'Study Studio'
  IconData get icon;
  bool get enabledByDefault;
  List<RouteBase> routes();            // contributes its go_router subtree
  LauncherTile launcherTile();         // tile on Cockpit Home
  Future<void> init(Ref ref);          // register providers/services
}
```

**Three detach levels for `study_studio_enabled`:**
1. **Runtime toggle** — flag off ⇒ shell hides tile + skips route registration. (`Settings` screen + RemoteConfig)
2. **Build flavor** — exclude from `registered_modules.dart` for a given build.
3. **Physical detach** — remove `study_studio` from `apps/cockpit/pubspec.yaml`; app still compiles because the shell depends only on the `CockpitModule` interface, not the implementation.

`apps/cockpit/lib/modules/registered_modules.dart`:
```dart
final modules = <CockpitModule>[
  if (flags.studyStudioEnabled) StudyStudioModule(),
  // future modules…
];
```

---

## 6. Frontend (study_studio package — Clean-ish layering)

```
packages/study_studio/lib/
├── study_studio.dart                 # public barrel (exports StudyStudioModule only)
└── src/
    ├── study_studio_module.dart      # implements CockpitModule (routes + tile + DI)
    │
    ├── domain/                       # pure Dart, no Flutter/IO
    │   ├── entities/                 # StudyObject(Topic), Studio, SourceFile,
    │   │                             #   Flashcard, QuizQuestion, Scenario, Progress
    │   ├── repositories/             # abstract: StudioRepository, TeachRepository, …
    │   └── usecases/                 # BuildStudio, GenerateQuiz, ScoreAnswer, ReviewCard…
    │
    ├── data/
    │   ├── dtos/                     # freezed/json_serializable mirrors of API
    │   ├── mappers/                  # DTO ⇄ entity
    │   ├── datasources/
    │   │   ├── remote/               # calls ApiClient (cockpit_core)
    │   │   └── local/                # hive cache (offline topics, due cards)
    │   ├── ai/
    │   │   ├── ai_service.dart       # INTERFACE (extract, teach, quiz, flashcards)
    │   │   ├── stub_ai_service.dart  # canned data — used until provider chosen
    │   │   └── remote_ai_service.dart# delegates to backend AI endpoints
    │   └── repositories/             # concrete repo impls
    │
    ├── application/                  # Riverpod controllers/notifiers (one per feature)
    │   ├── studio_list_controller.dart
    │   ├── upload_controller.dart
    │   ├── build_controller.dart     # subscribes to build-status stream
    │   ├── teach_controller.dart
    │   ├── quiz_controller.dart
    │   ├── flashcard_controller.dart
    │   └── progress_controller.dart
    │
    └── presentation/
        ├── home/  upload/  building/  dashboard/  topic_library/  topic_detail/
        ├── teach_me/  quiz_me/  flashcards/  progress/
        ├── lightning_recall/  scenario/  visualize/  review_schedule/   # Phase 2
        └── widgets/                  # StudioCard, TopicCard, FlashcardView, QuizQuestionCard…
```

**Data flow:** `presentation` → `application` (Riverpod) → `usecases` → `repositories` (abstract) → `data` impl → `ApiClient`/`AiService`/`hive`. Swapping `StubAiService`→`RemoteAiService` is a one-line DI change.

---

## 7. Backend (custom API → `backend/`)

Separate service the Flutter client calls. Language open — **recommended: Dart Frog** (share entity code with the app) or FastAPI/NestJS. The AI pipeline lives here behind its own interface so the provider stays swappable server-side.

```
backend/
├── lib/src/
│   ├── routes/                # HTTP handlers (see API surface below)
│   ├── services/
│   │   ├── ingestion/         # file parse, text extract, OCR
│   │   ├── pipeline/          # 12-step: chunk→topic detect→study-object→
│   │   │                      #   relationships→quiz→flashcards→difficulty→
│   │   │                      #   importance→mastery init
│   │   ├── ai/
│   │   │   ├── ai_provider.dart       # INTERFACE (provider-agnostic)
│   │   │   ├── claude_provider.dart   # default impl when chosen
│   │   │   └── prompts/               # extraction / teach / quiz / flashcard
│   │   └── scoring/           # mastery formula, weak-topic detection
│   ├── models/                # Studio, SourceFile, Topic, QuizQuestion,
│   │                          #   Flashcard, UserProgress (mirror DATA_MODELS.md)
│   ├── repositories/          # DB access
│   └── jobs/                  # async build worker (Upload → Studio)
├── storage/                   # uploaded files / object store config
└── pubspec.yaml (or package.json / pyproject.toml)
```

**API surface (consumed by the Flutter `data/datasources/remote`):**

| Method | Endpoint | Purpose |
|---|---|---|
| `POST` | `/studios` | create studio + start build job (multipart upload) |
| `GET` | `/studios` | list studios (home cards) |
| `GET` | `/studios/{id}` | dashboard data |
| `POST` | `/studios/{id}/files` | add files (add / rebuild / new options) |
| `GET` (SSE/WS) | `/studios/{id}/build` | streamed processing steps + progress % |
| `GET` | `/studios/{id}/topics` | topic library (filter/sort/search) |
| `GET` | `/topics/{id}` | topic detail (full Study Object + sources) |
| `POST` | `/teach` | grounded tutor chat turn |
| `GET` | `/topics/{id}/quiz` · `POST /quiz/answer` | quiz questions + scoring |
| `GET` | `/topics/{id}/flashcards` · `POST /flashcards/{id}/review` | cards + SR review |
| `GET` | `/studios/{id}/progress` · `POST /progress/events` | mastery + weak topics |
| `GET` | `/config` | RemoteConfig: flags (`study_studio_enabled`) + theme tokens |

Flutter side: `cockpit_core/network/ApiClient` (dio) handles base URL, auth header, error mapping; module datasources call typed methods over it.

---

## 8. Build order (next steps)

1. `flutter create` the shell at `apps/cockpit` + melos workspace, the 4 packages.
2. `cockpit_ui` tokens (colors/fonts) + theme → visible global controls.
3. `cockpit_module` contract + shell `ModuleRegistry` + `study_studio_enabled` toggle in Settings.
4. `study_studio` entities + `StubAiService` + the 8 MVP pages with mock data → **web-runnable demo**.
5. Wire `RemoteAiService` + `ApiClient` once backend endpoints exist.

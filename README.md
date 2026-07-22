# Boardwalks LLC — Internship Program

Welcome to the team 👋 — **Phase 2: Desktop (PC) Design.**

## Where we are now

Study Studio's mobile screens are built and merged. **The Lead is now starting
the backend**, so the UI needs to be *desktop-ready* in parallel — when the API
lands, the app should already look right on a PC, not just on a phone.

**Your mission for this phase:**

> **Design the desktop (PC) view of the app.** Take the app screen by screen,
> look at it the way a user on a laptop would, and lay it out so it's
> comfortable and looks intentional on a wide screen — not a phone column
> floating in the middle of a 1440px monitor.

> **Not everything on every screen needs to be redesigned.** Just see the whole
> app from the user's perspective and design the PC version for the user's
> convenience.

Some screens already have a good desktop layout (see **References** below) — use
those as the bar. Others are still phone-only and need your attention. Part of
the job is *judging* which is which.

## The app map — every page you can browse

Run the app (below) and open these routes. Web uses hash routing (`/#/…`).
`:studioId` is `bio` (Biology Midterm Studio) or `mbr` (MBR Training Studio).

### App shell
| Route | Page |
| ----- | ---- |
| `/` | Cockpit Home |
| `/settings` | Settings |

### Study Studio — top level
| Route | Page |
| ----- | ---- |
| `/study` | Study Home |
| `/study/upload` | Create Study Studio / Upload |
| `/study/build/:jobId` | Building / Processing |
| `/study/welcome` | Welcome Back |

### Study Studio — inside a studio (`/study/:studioId/…`)
| Route | Page |
| ----- | ---- |
| `/study/:studioId` | Dashboard — Inside the Studio |
| `…/ready` | Ready |
| `…/topics` | Topic Library |
| `…/topics/:topicId` | Topic Detail |
| `…/teach/:topicId` | Teach Me |
| `…/quiz` | Quiz Me |
| `…/flashcards` | Flashcards |
| `…/progress` | Progress |
| `…/study-plan` | Study Plan |
| `…/knowledge-graph` | Knowledge Graph |
| `…/analytics` | Study Analytics |
| `…/ask-ai` | Ask AI |
| `…/manage` | Manage Study Studio |

Example: `http://localhost:PORT/#/study/bio/analytics`.
`:topicId` for `bio`: `bio_dna`, `bio_meiosis`, `bio_photo`.

## You are not starting from zero — the foundation is laid

A responsive foundation already exists in
`packages/study_studio/lib/src/presentation/widgets/studio_scaffold.dart`.
**Build on it — do not reinvent it.**

- **`isDesktop(context)`** — `true` when width ≥ `kStudioDesktop` (900). Branch
  your layout on this.
- **`StudioShell`** — wraps a page and renders the **navigation rail on
  desktop** / **bottom nav on phone** automatically. Every page should sit
  inside a `StudioShell`.
- **`ContentColumn(maxWidth: …)`** — centers content and caps its width so a
  page doesn't stretch edge-to-edge on a huge monitor (phone screens use ~480,
  desktop dashboards use ~1160).
- **Design tokens (`packages/cockpit_ui`)** — `CockpitColors`, `CockpitSpacing`,
  `CockpitRadii`, `CockpitFonts` (Outfit, global). **Never hard-code a hex or a
  magic number** — read from `Theme.of(context).colorScheme` and the tokens.
- **`StudyPalette`** (`presentation/widgets/studio_palette.dart`) — the shared
  decorative status/accent swatches (`success/warning/danger/info` +
  `violet/pink/…`). Reuse these instead of inlining `Color(0xFF…)`.

### The desktop pattern (copy this shape)

```dart
return StudioShell(
  selectedIndex: 1,
  child: SafeArea(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final desktop = isDesktop(context);
        return SingleChildScrollView(
          child: ContentColumn(
            maxWidth: desktop ? 1160 : 480,
            child: desktop
                ? Row(children: [/* multi-column desktop layout */])
                : Column(children: [/* the existing phone layout */]),
          ),
        );
      },
    ),
  ),
);
```

**References — already done to the desktop bar:**
- `presentation/dashboard/dashboard_page.dart` — responsive grid via `isDesktop`
- `presentation/ask_ai/ask_ai_page.dart` — two-column (content + sidebar)
- `presentation/analytics/study_analytics_page.dart` — two-column dashboard
- Screens 1–7 (Home, Upload, Building, Ready, Dashboard, Teach Me, Quiz Me)

## Who owns what — 5 interns, split by flow

You own a **flow**, not a random pile of pages — so one person keeps a whole
area of the app visually consistent. Audit every page in your flow on desktop
and bring the weak ones up to the bar.

| Intern | Flow | Pages |
| ------ | ---- | ----- |
| **#1** | Shell & Entry | Cockpit Home · Settings · Study Home · Welcome Back |
| **#2** | Create & Enter | Upload · Building · Dashboard · Ready |
| **#3** | Learn | Teach Me · Topic Library · Topic Detail |
| **#4** | Practice | Quiz Me · Flashcards · Progress |
| **#5** | Intelligence | Study Plan · Knowledge Graph · Analytics · Ask AI · Manage |

*(The Lead can rebalance this — talk to them if your flow is too heavy or too
light.)*

## Coordinate — this is a team, not five solo tasks

Design **consistency** is the whole point of a super-app. Screens designed in
five silos will clash.

- **Stay in touch with each other.** Agree on shared desktop conventions *before*
  you build: content max-width, nav-rail behaviour, card grid gutters, breakpoint
  (use the shared `kStudioDesktop = 900`), two-column vs. three-column rules.
- **Eliminate duplication.** If two of you need the same desktop widget (a
  two-column shell, a wide stat row, a sidebar), build it **once** in
  `presentation/widgets/` and share it. Don't copy-paste layouts.
- **Coordinate at the seams.** Pages that link to each other (Dashboard →
  Teach Me → Quiz Me) must feel like one app. Check your neighbour's flow.
- If a decision affects everyone (a new shared breakpoint, a token change), raise
  it with the group and the Lead — don't decide it alone in your branch.

## Ground rules

1. **Desktop first, don't break phone.** Add the desktop layout behind
   `isDesktop(context)`; the existing phone layout must still work.
2. **Use `cockpit_ui` tokens + `StudioShell`/`ContentColumn`.** No hard-coded
   colours or magic numbers.
3. **Mock data only.** No backend yet — pull from
   `packages/study_studio/lib/src/data/mock/mock_data.dart` or add realistic mock
   objects. Never wire real network calls.
4. **`flutter analyze` must report _No issues found_** before you open your PR.
5. **Never touch `main`.** `main` is protected — no direct commits, no merges,
   no force-push, ever.

## Getting started

```bash
git clone https://github.com/boardwalk-ai/Cockpit.git
cd Cockpit
git checkout dev
git checkout -b intern/<your-name>/desktop-<flow>

flutter pub get

cd apps/cockpit
flutter run -d chrome   # web is easiest for design work
```

## Submission

- **Fork-based Pull Request.** Work on a branch *or* fork the repo — **your
  decision**. Open your PR **into `dev`** (never `main`) and tag the Lead.
- **Submission date: open** (not fixed yet). Quality and consistency over speed.

## Definition of done

- [ ] The page looks intentional and comfortable on a desktop (≥ 1280 wide)
- [ ] Wrapped in `StudioShell`; desktop behind `isDesktop(context)`; phone still works
- [ ] Uses `cockpit_ui` tokens / `StudyPalette` — no hard-coded colours or magic numbers
- [ ] Shared desktop widgets live in `presentation/widgets/`, not copy-pasted
- [ ] Mock data only, no real network calls
- [ ] `flutter analyze` is clean
- [ ] PR opened into `dev`, not `main`

Questions? Ask your Lead — and talk to each other. Build something you're proud
to demo. 🚀

# Boardwalks LLC — Internship Program

Welcome to the team 👋

## What you'll be doing

You will be designing and building our new selling tool — **Study Studio**.

Study Studio is a module inside the **Octopilot Cockpit** super‑app. A user
uploads their study materials (PDFs, slides, notes, audio…) and the app turns
them into a structured, interactive AI learning environment — Teach Me, Quiz Me,
Flashcards, Lightning Recall, Scenario Mode, Visualize, Progress, and more.

The whole app is built with **Flutter** (one codebase for Web + Android + iOS).

Your job is simple:

> **Take your assigned pages and rebuild them so they match the design image
> exactly — pixel‑precise — using mock data.** Then open a Pull Request.

## Ground rules (read this twice)

1. **Finish your assigned task.** You own your pages end to end — layout,
   spacing, colours, states, and navigation.
2. **Match the design image exactly.** The design image the Lead places in
   `docs/designs/` is the single source of truth. If something is unclear, ask
   the Lead — do not guess and ship something different.
3. **Use mock data only.** There is no backend yet. Pull from the existing mock
   data (`packages/study_studio/lib/src/data/mock/mock_data.dart`) or add your
   own mock objects. Never wire real network calls.
4. **Work on a branch. Open a PR.** One branch per task, e.g.
   `intern/<your-name>/screen-08-ai-mastery-report`. When done, open a Pull
   Request **into the `dev` branch** (not `main`).
5. **Never touch `main` without the Lead's explicit instruction.** No direct
   commits, no merges, no force‑push. Ever. `main` is protected.
6. **Keep it clean.** `flutter analyze` must report **No issues found** before
   you open your PR.

## Getting started

```bash
# 1. Clone and switch to your branch off dev
git clone https://github.com/boardwalk-ai/Cockpit.git
cd Cockpit
git checkout dev
git checkout -b intern/<your-name>/screen-08-ai-mastery-report

# 2. Get dependencies (monorepo uses a pub workspace)
flutter pub get

# 3. Run the app (web is easiest for design work)
cd apps/cockpit
flutter run -d chrome
```

The app opens on **Cockpit Home → Study Studio**. From there you can reach every
screen (Home → Upload → Building → Ready → Studio dashboard → Teach Me / Quiz Me
/ Flashcards …).

## The design language (match this)

Screens **1–7 are already built** — study them and copy their look and feel:

- **Font:** `Outfit` (already bundled and set globally — do not change it).
- **Design tokens:** always use `packages/cockpit_ui` — `CockpitColors`,
  `CockpitSpacing`, `CockpitRadii`, and the shared widgets (`CockpitCard`,
  `ProgressRing`, `StatTile`, `TagChip`, `StudioShell`, …). **Never
  hard‑code a hex colour or a magic number** — read from the theme
  (`Theme.of(context).colorScheme`) and the token classes.
- **Style:** clean, academic, modern, friendly. White background, rounded glass
  cards (radius 16–24), soft shadows, blue→purple gradients. Not childish.
- **Reference pages** (copy these patterns):
  - `.../presentation/home/study_home_page.dart` (Screen 1)
  - `.../presentation/upload/upload_page.dart` (Screen 2)
  - `.../presentation/building/building_page.dart` (Screen 3)
  - `.../presentation/ready/ready_page.dart` (Screen 4)
  - `.../presentation/dashboard/dashboard_page.dart` (Screen 5)
  - `.../presentation/teach_me/teach_me_page.dart` (Screen 6)
  - `.../presentation/quiz_me/quiz_me_page.dart` (Screen 7)

All Study Studio pages live under
`packages/study_studio/lib/src/presentation/<feature>/`.

## Your assignment — Screens 8–17

Each intern owns **two screens**. The design image for every screen is in
[`docs/designs/`](docs/designs/). **The image is the single source of truth** —
build the page so a reviewer can't tell it apart from the image.

| Intern | Screens | Titles | Where it lives |
| ------ | ------- | ------ | -------------- |
| **Intern #1** | **8, 9** | AI Mastery Report · Lightning Recall | `presentation/mastery_report/` (new) · `presentation/lightning_recall/` (new) |
| **Intern #2** | **10, 11** | Flashcards · Scenario Mode | `presentation/flashcards/flashcards_page.dart` · `presentation/scenario/` (new) |
| **Intern #3** | **12, 13** | AI Study Plan · Knowledge Graph | `presentation/study_plan/` (new) · `presentation/knowledge_graph/` (new) |
| **Intern #4** | **14, 15** | Ask AI · Manage Study Studio | `presentation/ask_ai/` (new) · `presentation/manage/` (new) |
| **Intern #5** | **16, 17** | Study Analytics · Welcome Back | `presentation/analytics/` (new) · `presentation/welcome/` (new) |

### What each task means

> **Intern #1** — Build **Screen 8 (AI Mastery Report)** and **Screen 9
> (Lightning Recall)** to match `docs/designs/Screen 8 (AI Mastery Report).jpg`
> and `Screen 9 (Lightning Recall).jpg` exactly, pixel‑precise, using mock data.
>
> **Intern #2** — Build **Screen 10 (Flashcards)** and **Screen 11 (Scenario
> Mode)** to match `docs/designs/Screen 10 (Flashcards).jpg` and `Screen 11
> (Scenario Mode).jpg` exactly, pixel‑precise, using mock data.
>
> **Intern #3** — Build **Screen 12 (AI Study Plan)** and **Screen 13 (Knowledge
> Graph)** to match `docs/designs/Screen 12 (AI Study Plan).jpg` and `Screen 13
> (Knowledge Graph).jpg` exactly, pixel‑precise, using mock data.
>
> **Intern #4** — Build **Screen 14 (Ask AI)** and **Screen 15 (Manage Study
> Studio)** to match `docs/designs/Screen 14 (Ask AI).jpg` and `Screen 15 (Manage
> Study Studio).jpg` exactly, pixel‑precise, using mock data.
>
> **Intern #5** — Build **Screen 16 (Study Analytics)** and **Screen 17 (Welcome
> Back)** to match `docs/designs/Screen 16 (Study Analytics).jpg` and `Screen 17
> (Welcome Back).jpg` exactly, pixel‑precise, using mock data.

## How to build a page (checklist)

1. Open your design image in `docs/designs/` and study every detail — spacing,
   font weights, icon choices, colours, and every state (empty, loading,
   selected, correct/incorrect, etc.).
2. Find (or create) your page file under `presentation/<feature>/`.
3. If the page is **new**, register its route in
   `packages/study_studio/lib/src/study_studio_module.dart` (copy how the
   existing routes are declared) so it's reachable in the app.
4. Build the UI with `cockpit_ui` tokens + shared widgets. Match the reference
   screens' structure (constrained max width 480, `SafeArea`, gradient buttons,
   etc.).
5. Feed it **mock data** from `mock_data.dart` (or add your own mock objects —
   keep them realistic).
6. Run `flutter analyze` — it must say **No issues found**.
7. Run the app and click through your page in the browser. Compare side‑by‑side
   with the design image.
8. Commit, push your branch, and open a **PR into `dev`**. Tag the Lead for
   review.

## Definition of done

- [ ] Looks like the design image (a reviewer can't tell them apart)
- [ ] Uses `cockpit_ui` tokens — no hard‑coded colours or magic numbers
- [ ] Uses mock data, no real network calls
- [ ] `flutter analyze` is clean
- [ ] New pages are reachable via a route
- [ ] PR opened into `dev`, not `main`

Questions? Ask your Lead before you assume. Good luck — build something you're
proud to demo. 🚀

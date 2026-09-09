# OctoNotes fonts

**Primary font: Work Sans** — the most-seen font (see `../../MEMORY.md`).

- **License:** SIL Open Font License (OFL) — free to bundle and ship, including
  in a public production app.
- Bundled here: `WorkSans-Regular.ttf` (400), `WorkSans-Medium.ttf` (500),
  `WorkSans-Bold.ttf` (700), fetched from Google Fonts.
- Declared in `packages/octo_notes/pubspec.yaml` and wired as the `Work Sans`
  family in `OctoNotesTheme`.

**Secondary font: Outfit** — bundled by `apps/cockpit`, used for labels, buttons
and chips, and as the fallback for any missing Work Sans weight.

> Note: we deliberately did **not** use *Google Sans* — it is Google's
> proprietary brand font (not OFL) and isn't licensed for bundling in a
> third-party public app. Only *Google Sans Code* (monospace) is open.

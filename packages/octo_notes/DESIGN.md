# OctoNotes — Design System

The single source of truth for how OctoNotes looks and is built. Read this before
translating any screenshot/mockup into a panel. Pair it with `MEMORY.md`.

> **North star:** Borderless / typography-first (Swiss · GitBook · Linear · Stripe-docs).
> **Grouping comes from whitespace, hierarchy, alignment and proximity — never boxes.**

---

## 0. Translating a mockup → implementation

Mockups are delivered in **light mode**. The app default is **dark**. So:

1. **Never copy the mockup's whites/greys literally.** Map everything onto the
   theme tokens below (they auto-flip between dark & the cream light theme).
2. **Strip the boxes.** A mockup often draws cards/borders to show grouping.
   Re-express that grouping with **space + an eyebrow label**, not an outline.
3. **Keep only the backgrounds that earn it** — a live strip, a suggestion block.
   Everything else sits directly on the page surface.
4. Reuse the primitives in `presentation/widgets/octo_widgets.dart`. If you're
   about to write `Border.all(...)`, stop — you almost certainly want space.

### The rule, visually
```
❌  ┌───────────────┐        ✅   QUICK START            ← eyebrow (muted, spaced)
    │ Heading       │
    │ Text          │             Start Recording        ← proximity groups these
    └───────────────┘             New Note
                                  Continue Last Session
```

**Do:** whitespace · type hierarchy · alignment · subtle bg (sparingly) ·
indentation · proximity · restrained color.
**Don't:** borders · heavy dividers · card-on-card · heavy shadows · everything
inside a rounded rectangle.

---

## 1. Font — Plus Jakarta Sans (single font)

- **One font, everywhere:** Plus Jakarta Sans (400 / 500 / 600 / 700). No secondary.
- Bundled **once in `cockpit_ui`** (shared design package), so every app uses the
  same font.
- ⚠️ **GOTCHA:** because it's declared in a *package*, Flutter namespaces the
  family. The correct family string is **`packages/cockpit_ui/PlusJakartaSans`**,
  NOT the bare name (which silently falls back to the platform font). It's set
  once in `BorderlessTheme.font` (and reused by `OctoNotesTheme`) — never
  hard-code a family in a widget.

### Weight usage
| Weight | Use for |
|---|---|
| 700 Bold | Page titles / big headings (`headlineLarge`, `displaySmall`) |
| 600 SemiBold | Section & item titles (`headline*`, `title*`), active labels |
| 500 Medium | Buttons, chips, meta labels |
| 400 Regular | Body text |

---

## 2. Color — restrained, token-driven

Read colors from `Theme.of(context).colorScheme` (or `CockpitColors.brand` for
semantic success/warning). **Never hard-code a hex.** Dark is default; light is
warm **cream**, never clinical white.

| Role | Token | Dark | Meaning |
|---|---|---|---|
| Accent | `colorScheme.primary` | `#E11D2E` red | LIVE, primary buttons, active state, links — **functional only** |
| Page bg | `colorScheme.surface` | `#0C0B0A` | the page |
| Text | `colorScheme.onSurface` | `#F4EEE0` | primary text (soft off-white) |
| Muted text | `colorScheme.onSurfaceVariant` | `#A99F8E` | meta, eyebrows, secondary |
| Subtle raise | `colorScheme.surfaceContainerLow` | `#141210` | `OctoSurface` bg |
| Chip / field bg | `surfaceContainerHigh` / `Highest` | `#201D17` / `#29251E` | inputs, chips |
| Success | `CockpitColors.brand.success` | `#3FB27F` green | Ready, Saved, synced dot |
| Highlight | `colorScheme.tertiary` | `#E8B84B` gold | starred/callout highlight |

**Restraint rule:** on any given screen, red should appear only a handful of
times. If everything is red, nothing is.

---

## 3. Typography scale

Configured in `OctoNotesTheme._typography`. Headings are large + tight
(negative letter-spacing); body is airy (line-height ~1.55).

| Style | Where |
|---|---|
| `headlineMedium` (700) | Page title ("OctoNotes", note H1) |
| `headlineSmall` (600) | Major heading |
| `titleMedium` / `titleSmall` (600) | Section item titles, block titles |
| `bodyLarge` / `bodyMedium` (400, h 1.55) | Body copy |
| `labelSmall` (600, tracked) | **Eyebrow** section labels (uppercase) |
| `labelMedium` (500) | Buttons, chips, meta |

**Eyebrow = the workhorse of grouping.** Every section starts with an `Eyebrow`
(muted, uppercase, letter-spaced) followed by ~16px of space, then content.

---

## 4. Spacing & rhythm

Use `CockpitSpacing` tokens — never magic numbers.

| Token | px | Typical use |
|---|---|---|
| `xxs` | 2 | title→subtitle |
| `xs` | 4 | icon↔text tight |
| `sm` | 8 | between related rows |
| `md` | 12 | row inner padding |
| `lg` | 16 | eyebrow→content, intra-group |
| `xl` | 24 | `OctoSurface` padding |
| `xxl` | 32 | header→first section |
| `xxxl` | 48 | **between major sections** & desktop page padding |

**Radii:** `CockpitRadii.md` (12) blocks · `lg` (16) surfaces · `pill` (999)
buttons/chips/badges. **Elevation:** effectively 0 everywhere. No drop shadows.

### Layout
- **PC-first.** Desktop breakpoint: `width >= 900` (`kOctoDesktop`).
- Page content centered, `maxWidth: 1180`, page padding `xxxl` on desktop.
- Editorial reading columns cap ~`760`.

---

## 5. Primitives (`presentation/widgets/octo_widgets.dart`)

**Always reach for these first.** Add new shared primitives here, don't inline.

| Widget | Use for | Notes |
|---|---|---|
| `Eyebrow('Section')` | every section label | uppercased, muted, tracked |
| `OctoSurface` | a *soft group* that earns a subtle bg | `surfaceContainerLow`, rounded, **no border**, optional `onTap` |
| `OctoHoverRow` | any interactive row (notes, list items, nav) | transparent by default, **hover** bg only; `selected` → faint red tint |
| `OctoChip('Tag')` | tags / topics | subtle fill pill, no border |
| `LiveDot(label:'LIVE')` | live/recording badge | solid red pill |
| `Waveform()` | audio activity | decorative bars |

### Buttons
- **Primary action:** `FilledButton` → solid red **pill, no ring**.
- **Secondary:** `TextButton` (red text) or `OutlinedButton` (renders as a
  subtle-filled pill — the theme strips the outline).
- Never put a 1px ring on a button here (that was the old cockpit style).

### Inputs
- Borderless: subtle fill (`surfaceContainerHigh`), no outline; focus shows a
  thin red underline-less border via the theme. Just use `TextField` with the
  default `InputDecoration` (theme handles it).

---

## 6. Recurring components (build them the same way every time)

- **Section** = `Eyebrow` + `SizedBox(lg)` + content. Sections separated by `xxxl`.
- **List row** (note / continue / nav) = `OctoHoverRow` → `Row[ leading icon,
  lg gap, Expanded(title + muted meta), actions, chevron ]`. No dividers between
  rows — spacing carries it.
- **Meta line** = muted `bodySmall`, parts joined with ` · `. The course/tag is
  the one bit of red.
- **Live strip / suggestion** = `OctoSurface` (the sanctioned subtle bg).
- **Status** = colored `Icons.circle` (8px) + label. success=green, live=red.

---

## 7. Icons

Material **rounded/outlined** set only (`uses-material-design: true`). Muted
(`onSurfaceVariant`) by default; red only when the icon is the accent (primary
action, active). Common: `mic_none_rounded`, `menu_rounded`,
`chevron_right_rounded`, `check_circle_rounded`, `auto_awesome_rounded`.

---

## 8. Checklist before you ship a panel

- [ ] No `Border.all` / visible dividers (spacing instead)?
- [ ] Every section led by an `Eyebrow`?
- [ ] Colors from tokens, red used sparingly?
- [ ] Poppins via theme (no bare `'Poppins'`, no inline family)?
- [ ] Reused `octo_widgets` primitives?
- [ ] `flutter analyze packages/octo_notes` → **No issues**?
- [ ] Reads well in **both** dark (default) and the cream light theme?

---

## 9. Reference implementation

`presentation/home/octo_notes_home_page.dart` is the canonical example of this
style. When in doubt, match it. (Modal + Session page are being converted to it.)

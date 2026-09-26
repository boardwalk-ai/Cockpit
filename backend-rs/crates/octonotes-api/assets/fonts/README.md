# Export fonts

Plus Jakarta Sans (Regular, Bold) — the app's single font, copied from
`packages/cockpit_ui/assets/fonts` so the server build (which only ships
`backend-rs/`) can embed it in PDF exports. Licensed under the SIL Open Font
License 1.1 (free to bundle and redistribute). It has no Myanmar glyphs, so
Burmese text in PDF exports needs an additional font (e.g. Noto Sans Myanmar).

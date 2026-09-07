# Hypertime app icon — handoff (approved direction: 1a "Dark glass slab")

Source artboard: `Hypertime App Icon.dc.html` (option 1a).

## What's in this folder

- `AppIcon.appiconset/` — drop-in Xcode asset catalog folder: all 10 required macOS PNG slots
  (16/32/128/256/512 pt at 1x and 2x) plus `Contents.json`. Note: 2x files are named `*-2x.png` and `Contents.json` references them by that exact name — Xcode resolves by the filename field, so no renaming is required (rename to `@2x` only if your tooling insists, updating Contents.json to match). Copy the whole folder into
  `Assets.xcassets/` and it is done — no Xcode slot-dragging needed.
- `assets/appicon.svg` — the 1024 master SVG (full design: gradient slab, sheen, crown tick, accent dot).
- `assets/appicon-small.svg` — the simplified small-size source used for the 16/32 pt slots.

## Design spec

Master (128 pt and up):
- Full-bleed square; macOS applies the squircle mask and system shadow itself. Do NOT pre-round or pre-shadow.
- Background: linear gradient 165°, #3E4D7D → #1D2340 (58%) → #111524, with a cool radial sheen
  (#8FB0E0 @ 35%, center 28%/18%) and 1-px-scale top-light / bottom-shade edges baked in.
- Glyph: stopwatch ring r6 + crown tick, stroke #FFFFFF @ 92%, weight 1.3 (glyph-space, 18-unit grid,
  scaled 56.9× and centered at 512/512). Tracking dot r2.2 fixed #0A84FF (the icon does not follow the
  user's system accent — only in-app UI does).

Small sizes (16 pt and 32 pt slots, incl. @2x = the 16/32/64 px files):
- Crown tick removed; ring recentered at 9/9 and enlarged to r6.4; stroke weight 2.0; dot r2.6 in white
  (accent blue anti-aliases to mud at these sizes). Sheen and edge lights dropped — flat gradient only.

## If regenerating from SVG instead of using the PNGs

Render `appicon.svg` for 128 px and up, `appicon-small.svg` for 64 px and below, at exactly the
pixel sizes in `Contents.json`. No padding: the artwork is authored full-bleed to the 1024 canvas.

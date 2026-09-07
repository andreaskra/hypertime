# Hypertime — design handoff (Phase 2)

Source artboards: `Hypertime UI Concept v2.dc.html` (v1 kept for history). All dimensions are 1x pt.
Tokens: `tokens.json` in this folder — transcribe 1:1 into `DesignTokens.swift`.
Accent: design uses the system accent (`controlAccentColor`); nothing depends on it being blue (verified against purple/green/orange).

## Artboard → view map

| Brief name | Artboard (v2 canvas) | Notes |
|---|---|---|
| A-popup hero | "Hero · focused, 4 today rows" | annotated: 380 w, r18, pad 16, field 30 h, rows 28 h, buttons 28 h, gaps 8/12 |
| A-popup dropdown | "Dropdown open — overlays the today list" | dropdown = popover material, z-over dimmed today list |
| A-popup amount states | "Amount editing (frozen) · amount invalid" | parser accepts 0:45, 45m, 0.75h |
| A-popup list states | "Today list · row focused, row editing, row invalid" | full-row accent ring = keyboard focus |
| A-popup scroll | "6 rows, scrolled" | 6 rows max (168 pt), edge fades, 3 pt overlay scrollbar |
| A-popup passive | "Passive — auto-hides after 20 s" | thinner glass, no rings, top-edge drain |
| A-popup paused | "Paused" | amber square indicator, Resume in header, ↩ adds + resumes |
| A-popup empty | "Empty — fresh launch (dark)" | ~150 pt, no list, Discard disabled |
| A-popup fallback | "Reduce Transparency fallback" | solid #F2F2F6 / #1E1E23, stronger hairlines |
| A-pause | "A-pause · Pause chooser" | 240 pt popover, chips, custom field uses same parser |
| A-icon | "A-icon · Menu bar" | template image; state by shape (ring / dot / bars) |
| A-reports Day | "Day view — TodayList component" | SAME component as popup list + Total + Add project… |
| A-reports Week/Month/Year | respective artboards | today column accent 16%; month = intensity cells, click → Day |
| A-export | "A-export · Export sheet" | sheet material, CSV preview line |
| A-settings | "A-settings · Settings window" | 480 pt, grouped rows |
| A-appicon | "A-appicon · App icon" | assets/appicon.svg (render 1024 PNG from it) |

## Popup anatomy (top → bottom)

1. Header 20 pt: question (11 secondary) · state line (11 secondary + 6 pt indicator) · pause icon button 20×20.
2. Project combobox 30 pt, r10. Focus = accent 0.5 pt border + 3 pt accent@32% ring. Text selected on focus.
3. Amount-to-add 26 pt SF Pro Rounded tabular, centered; "+" prefix in accent, semibold. Caption 10 pt tertiary:
   "since last check-in · ↩ adds it to ‹project›". Live ticks in place (tabular, zero layout shift); freezes on edit.
4. Hairline separator, then TODAY list: section label row (10 pt caps, day total right), rows 28 pt r8:
   6 pt indicator slot · name (13, medium if current) · time (12 tabular right). Max 6 visible, then scrolls.
5. Button row 28 pt: Discard (left, red-text ghost, ⌘⌫) · spacer · Close (secondary, esc) · Confirm (primary, ↩).

Panel: top edge anchored under the menu bar icon; grows DOWNWARD only. ~150 pt empty → 260–320 pt with 4–6 rows. Width 380, max 400.

## Focus & keyboard

Tab order: project field → amount field → today rows (top→bottom) → Confirm.
- Popup gains focus: project field focused, all text selected.
- ↑/↓ move dropdown highlight while it is open; typing filters; row for a new name = Create "…".
- Enter: commits from project/amount field; saves the row when inside the list. Esc: closes from anywhere (time keeps counting).
- ⌘⌫: Discard (throw away accumulated amount). Disabled when amount is 0:00:00.
- Focus rings: 3 pt accent@32% glow + accent 0.5 pt border (fields/buttons); full-row 2.5 pt ring for list rows.
  Increase Contrast: ring opacity 32%→50%, hairlines one step up, secondary text → textSecondary highContrast values.

## Motion & focus note

All durations/curves in tokens.motion. Key decisions:
- Nothing animates continuously; only the changing digit moves (150 ms, changed digit only).
- Discard: amount field collapses + clears (120 ms) then standard dismiss (120 ms) — ≤ 250 ms total. Reads as "thrown away", not punished.
- Passive auto-hide: 20 s linear 2 pt top-edge drain (autoHideDrain color — neutral, not accent, not red). Hover/click cancels. Ends with the standard dismiss.
- Invalid: 2-cycle 300 ms shake + invalid tint; hint text ("Try 1:30 or 90m") below the field; never a modal.
- Reduce Motion: everything becomes a 120 ms crossfade; the auto-hide drain becomes a static hairline that disappears with the popup.

## Dropdown vs today list (must stay distinct)

Dropdown: popover material (near-opaque), r10, large shadow, anchored to the field, rows 26 pt, match chars in accent bold,
Create-row with accent + badge, NO time values. While open the today list dims to 45%.
Today list: inline on panel material, flat, TODAY label, right-aligned times, edit-in-place. Never both interactive at once.

## Assets (this folder)

- assets/menubar-idle.svg / menubar-tracking.svg / menubar-paused.svg — 18×18 template glyphs, black on transparent.
  Export PNG @1x/@2x from these. Glyph is optically ~14 pt.
- assets/appicon.svg — 1024 source for the app icon (render PNG; system masks the rounded rect).

## Open items

- SF Pro Rounded for timeAdd is a proposal; SF Pro Text with tabular figures is the approved fallback.
- Month-cell hover tooltip styling follows the system tooltip; no custom design.

# Hypertime — Design Brief (for Claude Design)

This brief asks for the complete visual design of Hypertime, a macOS menu-bar time
tracker. Engineering is building the backbone now ([PLAN.md](PLAN.md), Phase 1) with
unstyled UI; your handoff drives Phase 2, where every screen is rebuilt to match your
artboards pixel for pixel. Read §7 first so the deliverables are shaped for that handoff.

---

## 1. Product in one paragraph

Hypertime lives in the menu bar and quietly counts time against one "current project".
Every 30 minutes (configurable) a tiny glass popup floats in without stealing focus and asks
"What are you working on?", with the time since the last answer (e.g. `0:30:00`) ticking in
a field. The user answers with a couple of keystrokes: Cmd+Tab to it, type or arrow to a
project, optionally Tab and correct the amount, Enter. That amount is **added** to the
chosen project and focus snaps back to where they were. The popup also lists today's
projects with their totals, each editable in place. Occasionally they open a Reports window to fix a day, look at a week or
month, or export a CSV. They can pause tracking for a while or until 07:00 tomorrow.

## 2. Audience and feel

One person, a developer, who wants a tool that feels like a precision instrument, not a
productivity dashboard. Interaction time per check-in is 2–4 seconds; the design must be
legible at a glance and never demand attention.

Personality, in order of priority:
1. **Glass.** Transparency and translucency everywhere it makes sense: the popup is a slab
   of frosted glass floating over the desktop; windows use layered materials; controls sit
   *in* the glass rather than on top of it. Depth comes from blur, tint, inner highlights
   and soft shadows, not from borders.
2. **Calm.** Low-contrast surfaces, high-contrast text and numbers. Nothing pulses or
   demands. Tracking state is visible but quiet.
3. **Precise.** Times use tabular (monospaced-digit) figures. Alignment is exact. The
   live counter ticks without layout shifts.
4. **Native.** It must feel like it shipped with macOS 15: SF Pro, standard control
   heights, system focus rings (or a designed equivalent with the same affordance),
   respects light/dark, accent color, Reduce Transparency, Increase Contrast, Reduce Motion.

Reference points (for spirit, not copying): the macOS Control Center tiles, Spotlight's
panel, Raycast's command window, the iOS 26 Liquid Glass language rendered with macOS 15
materials, and a well-made mechanical stopwatch.

## 3. Hard constraints

- Platform: macOS 15 (Sequoia). Liquid Glass APIs are **not** available; glass is built
  from `NSVisualEffectView` materials (`hudWindow`, `popover`, `menu`, `sidebar`,
  `underWindowBackground`, `fullScreenUI`, `sheet`) with `behindWindow` blending, plus
  custom tint layers, gradient strokes and shadows. Design within what that can render:
  blur radius is system-controlled; you control material choice, tint color/opacity, stroke,
  shadow, corner radius, and any overlaid gradients.
- Typography: SF Pro (Text/Display as size dictates), SF Mono or SF Pro with tabular figures
  for times. Sizes should map to macOS text styles (11 caption, 13 body, 15 title3, 22 title,
  28+ largeTitle). Minimum body text 13 pt in the popup.
- Colors must be specified for light **and** dark appearance, and use semantic names.
  The user's system accent color must be usable as the primary accent (design with the
  default blue, but nothing may depend on it being blue).
- Reduce Transparency: every glass surface needs a solid fallback color (light and dark).
- Increase Contrast: strokes and secondary text need a stronger variant.
- Reduce Motion: every animation needs a crossfade-or-nothing equivalent.
- All interactive elements must have a visible keyboard-focus state; the popup is
  keyboard-first.
- Menu bar icon: template image (single color, alpha only), 18×18 pt canvas, glyph
  optically ~14 pt, provided @1x and @2x (and as SVG). No color; the system tints it.
- Window minimum sizes and control heights follow the macOS HIG (regular size controls,
  22 pt min hit height in lists, 28 pt buttons).

## 4. Screens and states (content inventory)

Design every screen in light and dark. Where a state is listed, produce an artboard or
clearly annotated variant.

### 4.1 Menu bar icon (A-icon)
Three states: **idle** (not tracking), **tracking**, **paused**. Optional variant with the
elapsed time for the current project rendered as menu-bar text next to the glyph
(`1:32:10`, tabular figures). Propose a glyph that reads as "time" at 14 pt without being
a generic clock; hourglass, ring, or abstract mark are all acceptable. The paused state
should be distinguishable from idle at a glance.

Status menu (right-click): native `NSMenu`; nothing to design beyond icon glyphs for
items if you want them (Pause, Reports, Export, Settings, Quit).

### 4.2 Check-in popup (A-popup) — the hero
Floating glass panel anchored under the menu bar icon, target width 340–400 pt, height as
compact as legibility allows (~150 pt with an empty today list, ~260–320 pt with 4–6
projects; the panel grows downward, its top edge stays anchored). No title bar, no traffic
lights. Draggable by background.

Content:
- Heading: "What are you working on?" (small, secondary). Consider a compact current-state
  line ("Tracking Hypertime · 1:32:10" or "Paused until 07:00").
- **Project field** (combobox): shows the current project name, selected on focus. A
  chevron indicates the dropdown. Below it, when focused or when the user types, a list of
  up to 6 matches; matched characters highlighted; highlighted row moves with ↑/↓; the row
  for a new name reads `Create "Design review"`. Show the list open and closed.
- **Time-to-add field**: the time accrued since the last commit, live-ticking (`0:32:10`),
  tabular figures; visibly editable, and visibly an *amount to add* (a leading `+`, a label
  like "add", or placement that makes the addition obvious). States: live (ticking, subtle),
  editing (frozen, focused), invalid (red-ish tint + short hint like "Try 1:30 or 90m",
  never a modal), empty (idle launch).
- **Today list**: every project with time today, one row each: name, live total (tabular,
  the current project's total ticks along with the pending time), editable in place. The
  current project is marked. Rows show hover, editing and invalid states. Max 6 rows
  visible, then it scrolls. Must be clearly a *different thing* from the project-match
  dropdown that overlays it while typing (see §9).
- **Buttons**: Close (secondary/ghost, Esc: hides, time keeps counting), **Discard**
  (destructive-secondary, ⌘⌫: throws the accumulated amount away) and Confirm (primary,
  default-button look, shows the ↩ symbol). Discard must never be mistakable for Close.
  A small **Pause** affordance (icon button or menu) that opens the pause chooser (§4.3).
  Keyboard hints may be shown very quietly (e.g. `esc` / `⌘⌫` / `↩`).

States to design:
1. Passive (appeared without focus; the user is elsewhere): identical layout, but visibly
   "unfocused" (no focus ring, slightly lower contrast or a thinner glass) so it is clear
   keystrokes are not going here. It auto-hides after 20 s unless hovered or clicked;
   optionally show a very quiet countdown affordance (a thin ring or edge line draining),
   nothing that reads as an alarm.
2. Focused, list closed.
3. Focused, list open with a query typed and matches highlighted.
4. Focused, list open, "Create …" row highlighted.
5. Time-to-add field focused and edited.
6. Time invalid.
6b. Today list: 1 row, 6 rows, scrolled; a row being edited; a row invalid; empty (no time today).
7. Paused (header shows "Paused until 07:00", a Resume affordance; Confirm still commits
   and resumes).
8. Idle (fresh launch: no current project; field placeholder "Project name").
9. Reduce Transparency fallback.
10. Multi-line / long project name truncation behavior.

### 4.3 Pause chooser (A-pause)
A small popover or inline segment growing out of the popup: presets 15 m · 30 m · 1 h ·
2 h · Until 07:00 · Custom (a time text field using the same parser). One click applies.
Also design the "paused" state of the popup header and the status icon (§4.1).

### 4.4 Reports window (A-reports)
Standard resizable window, ~760×540 pt default, glass content area, transparent title bar
with an integrated toolbar:
- Period kind segmented control: Day · Week · Month · Year.
- ◀ ▶ navigation, "Today", period title (`Mon 7 Sep 2026`, `Week 37 · 7–13 Sep 2026`,
  `September 2026`, `2026`).
- Export button (opens §4.5), search/filter optional.

Views:
- **Day**: the same today-list component as the popup, for any day: each project with an
  editable total, a total row, and an "Add project…" row. Current tracking project marked (live
  ticking if today). Row hover, selected, editing, invalid states. Context menu for rename /
  archive / delete (native menu, no design needed).
- **Week**: projects as rows, 7 day columns plus total; cells editable; column totals.
  Today column subtly emphasized.
- **Month**: projects as rows, days as columns (28–31, compact); cells not editable, clicking
  a cell jumps to that day. Consider a heat/intensity tint per cell rather than numbers
  everywhere, with numbers on hover or for totals. Row and column totals.
- **Year**: projects as rows, 12 month columns plus total; a small per-month bar or
  intensity strip is welcome.
- Empty states: no projects yet; period with no time.

### 4.5 Export sheet (A-export)
Sheet on the Reports window: scope (This month · This year · Date range with two date
pickers), delimiter (`,` / `;`), cell format (`H:MM:SS` / decimal hours), include totals.
Primary "Export…" (opens the system save panel), Cancel. Show one CSV preview line if it
helps understanding.

### 4.6 Settings window (A-settings)
Glass window ~480×420 pt, single page or two tabs:
- Tracking: check-in interval (Off, 15, 30, 45, 60, 90, 120 min), pause on sleep/lock,
  morning hour for "until morning".
- Appearance: time display style, show elapsed time in menu bar.
- System: launch at login, show in Dock & Cmd+Tab (with a one-line explanation that the
  Dock icon is what makes Cmd+Tab possible).
- Export defaults.

### 4.7 App icon (A-appicon)
1024×1024 macOS app icon (rounded-rect masked by the system). Should share DNA with the
menu bar glyph. Shown in the Dock (see D-07) and in login items, so it must hold up at
16 pt too.

## 5. Interaction and motion

| Moment | Intent | Duration / curve (proposal, refine as you see fit) |
|---|---|---|
| Popup appear (passive) | Slide 6 pt down + fade in, no bounce, not attention-grabbing | 180 ms, ease-out |
| Popup appear (focused via Cmd+Tab/click) | Same, may add a slight scale from 0.98 | 180 ms, ease-out |
| Popup dismiss (Esc, Close, auto-hide) | Fade + 4 pt up | 120 ms, ease-in |
| Discard | Amount field collapses/clears, then dismiss | ≤ 250 ms total |
| List open/close | Height animation, rows fade in staggered ≤ 30 ms | 160 ms |
| Highlight moves (↑/↓) | Highlight pill slides between rows | 90 ms |
| Live counter tick | Digits change in place; optional subtle vertical roll for changed digits only | 150 ms |
| Commit | Confirm button flashes success; popup dismisses | ≤ 250 ms total |
| Invalid time | 2-cycle horizontal shake of the field, tint to invalid color | 300 ms |
| Pause / resume | Icon state crossfade; popup header crossfade | 200 ms |

Everything falls back to a 120 ms crossfade under Reduce Motion.

Keyboard focus: the project field is focused with all text selected when the popup gains
focus; ↑/↓ move the match-list highlight; Tab moves to the time-to-add field, then down
through the today-list rows, then to Confirm; Enter commits from the project or time field
and saves a row when inside the today list; Esc closes from anywhere. Focus rings must be visible on glass in both
appearances — design a ring/glow that works on translucent backgrounds.

## 6. Design system to define

Provide a token set that engineering will transcribe 1:1 into `DesignTokens.swift`:
- **Materials**: for each surface (popup, window content, popover, list highlight, field
  background) the `NSVisualEffectView` material, blending mode, tint color + opacity
  (light/dark), and the solid fallback color.
- **Color roles** (light/dark, plus increased-contrast variants where different): text
  primary/secondary/tertiary, accent (system), on-accent, invalid, success, separator,
  stroke (glass edge highlight top, glass edge shadow bottom), field background, row hover,
  row selected, tracking indicator, paused indicator, idle indicator.
- **Typography**: role → font, size, weight, tracking, tabular flag (heading, body, caption,
  time-live, time-large, list row, keyboard hint).
- **Spacing & radii**: 4 pt base scale; corner radii for panel, window, field, button, row.
- **Elevation**: shadow specs for panel and popover (color, opacity, blur, offset) in light
  and dark.
- **Icons**: SF Symbols names for everything except the menu bar glyph and app icon, which
  you supply.
- **Motion**: durations and curves from §5 as tokens.

## 7. Deliverables and handoff format

1. Artboards for every screen and state in §4, light and dark, at 1x pt dimensions, with
   spacing annotations on the popup and the day/week report rows.
2. `tokens.json` with the structure below (engineering will consume it verbatim):
   ```json
   {
     "color": { "textPrimary": { "light": "#111111", "dark": "#F2F2F2", "highContrastLight": "#000000", "highContrastDark": "#FFFFFF" } },
     "material": { "panel": { "material": "hudWindow", "blending": "behindWindow", "tint": { "light": "#FFFFFF80", "dark": "#1C1C1E80" }, "fallback": { "light": "#F4F4F6", "dark": "#1E1E22" } } },
     "font": { "timeLive": { "family": "SF Pro Rounded", "size": 28, "weight": "medium", "tabular": true } },
     "radius": { "panel": 18, "field": 10, "button": 9, "row": 8 },
     "space": { "1": 4, "2": 8, "3": 12, "4": 16, "5": 24 },
     "shadow": { "panel": { "light": { "color": "#00000033", "blur": 40, "y": 12 }, "dark": { "color": "#00000080", "blur": 40, "y": 12 } } },
     "motion": { "popupAppear": { "duration": 180, "curve": "easeOut" } }
   }
   ```
3. Assets: menu bar glyph states as SVG plus PNG @1x/@2x (template, black on transparent);
   app icon as 1024 PNG (and layered source if available).
4. A one-page "motion & focus" note covering §5 decisions and any deviations.
5. A component sheet: field, combobox row, button (primary/secondary/ghost, default/hover/
   pressed/focused/disabled), segmented control, table cell (normal/hover/editing/invalid/
   today), pause chips.

Naming: use the names from this brief (A-popup, A-reports…) and the token keys above so the
Phase 2 agent can map artboards to views without guessing.

## 8. Things to avoid

- Card-on-card layouts, heavy borders, drop shadows on text, gradients that fight the
  desktop wallpaper behind the glass.
- Any element that animates continuously while tracking (the only moving thing is the
  digit that changes each second).
- Color as the only carrier of state (icon states need shape differences too).
- Anything that would not survive Reduce Transparency: if a screen only works because of
  the blur, redesign it.
- Custom title bars or window chrome on the Reports/Settings windows beyond a transparent
  title bar with an integrated toolbar.

## 9. Questions the design should answer explicitly

1. How does a passive (unfocused) popup look different from a focused one?
2. How is the "Create …" row visually distinct from existing projects?
3. Where does the pause affordance live in the popup without cluttering the 3-second path?
4. What does the menu bar look like with elapsed time on, in a crowded menu bar?
5. How do month/year grids stay readable with 15+ projects?
6. How do the project-match dropdown (opens while typing) and the today list (always
   visible) coexist in one small panel without the user confusing the two? Both are lists
   of project names.
7. How does the popup make "this amount will be added" unmistakable, so the user never
   reads the time field as a total?
8. How are Close, Discard and Confirm laid out so the 3-second path (Enter) stays
   dominant, Close stays harmless, and Discard is clearly destructive but not alarming?

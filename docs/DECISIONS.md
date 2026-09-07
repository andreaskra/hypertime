# Decisions log

Append-only. One entry per decision that refines or deviates from `PLAN.md`.

| Date | Ref | Decision | Why |
|---|---|---|---|
| 2026-09-07 | — | Plan and design brief written; no code yet. | Kickoff. |
| 2026-09-07 | D-07 | Dock icon accepted as the price of Cmd+Tab. | User confirmed. |
| 2026-09-07 | D-08, D-13, A-06, A-07 | Commit **adds** the time-field value; field is pre-filled with pending time since last commit; pending is provisionally attributed to the current project; today list with editable totals in popup and Reports Day view. | User: "committing time in the time-field should always add to the total" plus a list of today's projects with editable totals. |
| 2026-09-07 | A-01 | Sleep/lock time discarded; tracking auto-pauses. | User confirmed. |
| 2026-09-07 | A-03 | App launches idle and shows the popup. | User confirmed. |
| 2026-09-07 | D-10 | Bare integer = minutes, bare decimal = hours. | User confirmed. |
| 2026-09-07 | D-02 | Minimum target macOS 15; glass via NSVisualEffectView materials. | User confirmed. |
| 2026-09-07 | — | Bundle identifier `com.hypertime.app`, display name "Hypertime". | User: go with default. |
| 2026-09-07 | D-14 | Passive popup auto-hides after 20 s (setting); engagement cancels it; the bucket keeps accumulating. Close also keeps the bucket. | User request. |
| 2026-09-07 | R-04 | Dedicated Discard button (⌘⌫) drops the pending bucket, hides the popup, returns focus; tracking continues. | User request. |
| 2026-09-07 | D-15 | Editing the amount edits the bucket: the committed amount replaces pending; no hidden remainders. | User: "if I change the amount I am adjusting the bucket itself". |
| 2026-09-07 | D-12 | CSV defaults: comma delimiter, full stop decimal separator. | User confirmed. |
| 2026-09-07 | D-03 | Tests use **swift-testing** (`import Testing`), not XCTest. | Bundled with the Swift 6.2 toolchain; parameterised tests encode the §5.2 table directly. |
| 2026-09-07 | D-03 | GRDB pinned to 7.11.1; core + tests build in Swift 6 language mode, the app target in Swift 5 mode. | Strict concurrency where it pays; AppKit/SwiftUI glue is far cheaper in Swift 5 mode. |
| 2026-09-07 | §8 | Added a `--self-test` launch argument: a headless smoke test of the AppKit layer (status item, panel show/position/focus, commit, total editing, reports, CSV) against a throwaway DB. | The app target has no unit tests in Phase 1; this makes the parts a human cannot easily check repeatable and automatable. |
| 2026-09-07 | R-16 | The login item is only auto-registered when the app runs from `/Applications`; elsewhere it is logged and skipped. | `launchAtLogin` defaults to true, and registering a `dist/` dev build as a login item pollutes the user's system. |
| 2026-09-07 | §6.10 | Reports Day/Week cells use a shared `InlineTotalField` (Enter/blur saves, Esc reverts) instead of the popup's Tab-chained `TotalField`. | The popup needs the exact focus chain of §6.4; a report grid does not, and the normal key-view loop is better there. |
| 2026-09-07 | R-07 | The project dropdown is open exactly while the project field owns the keyboard (derived from focus), not while a field-editor session is active. | Ending the editing session on mouse-down would close the list before the click on a row landed. |
| 2026-09-07 | §6.4 | While a live-updating field (the time field) is first responder, the refresh re-selects its text. | Otherwise the per-second rewrite drops the "select all", and the first keystroke appends instead of replacing. |
| 2026-09-07 | §6.5 | An empty project field never falls back to the current project: commit refuses and focuses the field. | Matches §6.5; a silent fallback would attribute time the user did not name. |
| 2026-09-07 | §6.6 / Phase 2 | Menu bar icons are SF Symbols (`clock`, `clock.fill`, `pause.circle`) and there is no app icon yet. | Phase 1 is explicitly unstyled; icons arrive with the design handoff. |
| 2026-09-07 | Phase 1 | Manual checklist: the mechanics that can be checked without a human (panel shows without focus, positioning, commit/discard/total editing, reports, CSV, pending model, midnight split, gaps, pause/resume, restore) are covered by `swift test` (89 tests) plus `--self-test`. The items that need a person at the keyboard — R-08/R-09/R-10 focus behaviour with another app frontmost, D-14 hover cancelling auto-hide, A-01 lid close, R-16 login item from /Applications, multi-display placement, Reduce Transparency — are still open. | The building agent cannot drive Cmd+Tab, another app's focus, or the lid. |
| 2026-09-07 | Phase 2 | Handoff zip contained `tokens.json`, `HANDOFF.md` and the four SVG assets, but **not** the `Hypertime UI Concept v2.dc.html` artboards. Phase 2 was built against the written anatomy plus tokens; drift-versus-artboard QA is still open. | The written handoff specifies every size, state and behaviour, so the build did not need to block on the artboards. |
| 2026-09-07 | §7.1 | `DesignTokens.swift` transcribes `tokens.json` 1:1. Colours are `NSColor(name:dynamicProvider:)`, so light/dark **and** both Increase Contrast variants resolve automatically. No view contains a literal colour, size, radius or duration. | One source of truth; a diff against `tokens.json` stays readable. |
| 2026-09-07 | §7.2 | `GlassBackground` = `NSVisualEffectView` + tint + top/bottom highlight stroke, with an opaque fallback under Reduce Transparency. An extra `opaqueSurfaces` environment flag forces the fallback for `--screenshots`. | Window-server materials cannot be captured off screen. |
| 2026-09-07 | tokens.shadow | Panel and window shadows use the **native window shadow**, not the token values; dropdown and popover shadows do use the tokens. | A custom window shadow needs transparent padding around the panel, which breaks the "grows downward from a fixed anchor" positioning and makes the padding swallow clicks. |
| 2026-09-07 | motion.digitTick | The live amount updates in place (tabular figures, no layout shift) but individual digits are not animated. | The token notes the vertical roll as optional; a per-digit animator is a lot of machinery for a 150 ms detail. Easy to add later behind the same token. |
| 2026-09-07 | §6.4 | Added `.confirm` to `CheckInFocus` so Tab ends at the Confirm button, and the panel now handles Tab/Return/Space when no text field is first responder. | Phase 1 mapped that step to "no focus", which contradicted §6.4 and the handoff's tab order. |
| 2026-09-07 | R-05 | `prepareForShow` falls back to the most recently used project when nothing is being tracked. | R-05 asks for the most recently used project to be preselected; Phase 1 left the field empty on a fresh launch. |
| 2026-09-07 | A-icon | Menu bar glyphs and the app icon are drawn with Core Graphics from the SVG geometry (`MenuBarGlyph`, `IconRenderer`), and `build-app.sh` packs the icon with `iconutil`. | Keeps them crisp at every scale factor and avoids checking raster assets or an asset catalogue into the repo. |
| 2026-09-07 | A-pause | The pause chooser is an `NSPopover` with chips and a custom-duration field; the status item keeps its native submenu, whose "Custom…" opens the same popover. | Matches the A-pause artboard where the popup asks for a pause; a menu bar right-click is still a menu. |
| 2026-09-07 | A-export | The export sheet is presented as a real sheet on the Reports window when it is open, otherwise as its own window. | "A-export · Export sheet" plus the sheet material; Export is also reachable from the menu bar with no window open. |
| 2026-09-07 | §6.10 | Reports Day view reproduces the today list's shape (rows, indicator slot, editable total) rather than instantiating the popup's `TodayListView`. | The popup's component carries the §6.4 Tab chain; a report grid must use the normal key-view loop. |
| 2026-09-07 | §7.6 | Added `--screenshots <dir>`: renders every screen in light/dark × normal/Increase Contrast to `docs/screenshots` via `cacheDisplay` on a real hosting view. | Screenshots of other processes' windows cannot be captured from an agent shell; this renders the real AppKit hierarchy, text fields included. |


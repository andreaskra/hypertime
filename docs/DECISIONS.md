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


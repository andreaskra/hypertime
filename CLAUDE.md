# Hypertime — agent notes

Start with `docs/PLAN.md`. It is the contract: requirement IDs (R-xx), decisions (D-xx),
assumptions (A-xx), component specs, and the phase plan with acceptance checklists.
`docs/DESIGN_BRIEF.md` describes the design handoff that Phase 2 consumes.
`docs/DECISIONS.md` records every decision that refines or deviates from the plan.

Status: **Phases 0–3 complete.** The design handoff lives in `docs/design-handoff/handoff/`
(`tokens.json`, `HANDOFF.md`, SVG assets). What is still open is listed at the bottom of
`docs/DECISIONS.md`: the manual checklist items that need a person at the keyboard, and the
artboard-drift pass (the artboards were not part of the handoff zip).

## Rules
- `Sources/HypertimeCore` must not import AppKit or SwiftUI. Everything in it is tested with `swift test`.
- Never call `Date()` in core code; use the injected `Clock`.
- All persistence goes through `Store`. All UI binds to view models only.
- No view may contain a literal colour, size, radius, font or duration: everything comes from
  `Views/Components/DesignTokens.swift`, which transcribes `tokens.json` 1:1.
- `GlassBackground` is the only place that touches `NSVisualEffectView`; it falls back to a solid
  colour under Reduce Transparency.
- Record every decision that deviates from or refines the plan in `docs/DECISIONS.md` (date, ID, decision, why).

## Commands
```bash
swift build
swift test                              # 105 tests, swift-testing (import Testing)
swift test --enable-code-coverage
scripts/build-app.sh                    # -> dist/Hypertime.app (ad-hoc signed)
scripts/run.sh                          # kills running instance, builds, opens
scripts/run.sh --seed-demo              # separate demo database (6 projects, 90 days)
scripts/release.sh                      # signed .app + .zip + .dmg (add --notarize to submit)
dist/Hypertime.app/Contents/MacOS/Hypertime --self-test   # headless AppKit smoke test
dist/Hypertime.app/Contents/MacOS/Hypertime --screenshots docs/screenshots
dist/Hypertime.app/Contents/MacOS/Hypertime --render-icon <out> <appiconset>
```

`--self-test` exercises the status item, panel positioning and focus behaviour, the commit
flow, total editing, reports and CSV export against a throwaway database, then exits
non-zero on the first failure. Run it after touching anything in `Sources/Hypertime`.

## Layout
- `Sources/HypertimeCore` — Foundation-only library (§3 of the plan).
- `Sources/Hypertime/App` — AppDelegate, AppModel and the AppKit controllers.
- `Sources/Hypertime/ViewModels` — `CheckInViewModel`, `ReportsViewModel`, `SettingsViewModel`.
- `Sources/Hypertime/Views` — SwiftUI views; `Views/Components` holds the design system
  (`DesignTokens`, `GlassBackground`, `Chrome` for focus rings/buttons/shake, and
  `EditableField`, which wraps `NSTextField` for the exact keyboard model in §6.4).
- `docs/screenshots` — regenerated design-QA renders; see the README there for the two caveats.

## Environment
macOS 15.7, Xcode 26.3, Swift 6.2. Core and tests build in Swift 6 language mode, the app
target in Swift 5 mode (AppKit-heavy). GRDB 7.11.1 via SwiftPM.
XcodeGen is not installed (optional: `brew install xcodegen && xcodegen generate`);
`open Package.swift` is enough for core work.

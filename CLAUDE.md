# Hypertime — agent notes

Start with `docs/PLAN.md`. It is the contract: requirement IDs (R-xx), decisions (D-xx),
assumptions (A-xx), component specs, and the phase plan with acceptance checklists.
`docs/DESIGN_BRIEF.md` describes the design handoff that Phase 2 consumes.

## Rules
- `Sources/HypertimeCore` must not import AppKit or SwiftUI. Everything in it is tested with `swift test`.
- Never call `Date()` in core code; use the injected `Clock`.
- All persistence goes through `Store`. All UI binds to view models only.
- Phase 1 builds unstyled but fully functional UI. Do not spend time on visuals before the design handoff.
- Record every decision that deviates from or refines the plan in `docs/DECISIONS.md` (date, ID, decision, why).

## Commands (once Phase 0 exists)
```bash
swift build
swift test
scripts/build-app.sh      # -> dist/Hypertime.app
scripts/run.sh            # kills running instance, builds, opens
scripts/run.sh --seed-demo
```

## Environment
macOS 15.7, Xcode 26.3, Swift 6.2. XcodeGen is not installed (optional: `brew install xcodegen`).

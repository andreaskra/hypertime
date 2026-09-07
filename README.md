# Hypertime

A glass-and-transparency menu-bar time tracker for macOS. It periodically asks
"What are you working on?" in a tiny floating popup that never steals focus, is reachable
with Cmd+Tab, and gets out of the way after one keystroke.

Status: **Phase 1 complete** — the backbone works end to end behind a deliberately unstyled UI.

- [docs/PLAN.md](docs/PLAN.md) — requirements, architecture, component specs, phased build plan
- [docs/DESIGN_BRIEF.md](docs/DESIGN_BRIEF.md) — brief for the visual design (Claude Design)
- [docs/DECISIONS.md](docs/DECISIONS.md) — running log of decisions made during the build

## Build and run

```bash
swift test                  # 89 tests over HypertimeCore
scripts/run.sh              # build dist/Hypertime.app and launch it
scripts/run.sh --seed-demo  # same, against a seeded demo database
```

`dist/Hypertime.app/Contents/MacOS/Hypertime --self-test` runs a headless smoke test of the
AppKit layer and exits non-zero on failure.

## Build order

1. ~~Phase 0 — scaffolding (SwiftPM package, app bundle script)~~ done
2. ~~Phase 1 — backbone + functional unstyled UI, fully tested core~~ done
3. Phase 2 — UI rebuilt from the design handoff ← next
4. Phase 3 — hardening and packaging

Target: macOS 15+, Swift 6, SwiftUI + AppKit, SQLite via GRDB. Local-only for now.

## What works today

- Menu bar status item with tracking / paused / idle states and a full context menu.
- Non-activating check-in popup: appears without stealing focus, auto-hides after 20 s,
  fuzzy project dropdown, free-text time parsing, editable today list.
- Pending-bucket tracking model: nothing is written until you confirm, totals stay correct
  across midnight, sleep, lock, pause and quit.
- Reports for day / week / month / year with editable totals, CSV export, settings,
  login item and Cmd+Tab support.

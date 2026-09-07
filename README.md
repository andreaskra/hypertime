# Hypertime

A glass-and-transparency menu-bar time tracker for macOS. It periodically asks
"What are you working on?" in a tiny floating popup that never steals focus, is reachable
with Cmd+Tab, and gets out of the way after one keystroke.

Status: **planning**. Nothing is built yet.

- [docs/PLAN.md](docs/PLAN.md) — requirements, architecture, component specs, phased build plan
- [docs/DESIGN_BRIEF.md](docs/DESIGN_BRIEF.md) — brief for the visual design (Claude Design)
- [docs/DECISIONS.md](docs/DECISIONS.md) — running log of decisions made during the build

## Build order

1. Phase 0 — scaffolding (SwiftPM package, app bundle script)
2. Phase 1 — backbone + functional unstyled UI, fully tested core
3. Phase 2 — UI rebuilt from the design handoff
4. Phase 3 — hardening and packaging

Target: macOS 15+, Swift 6, SwiftUI + AppKit, SQLite via GRDB. Local-only for now.

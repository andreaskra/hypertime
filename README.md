# Hypertime

A glass-and-transparency menu-bar time tracker for macOS. It periodically asks
"What are you working on?" in a tiny floating popup that never steals focus, is reachable
with Cmd+Tab, and gets out of the way after one keystroke.

Status: **feature complete** (Phases 0–3 of [docs/PLAN.md](docs/PLAN.md)). Local-only; there is
no account, no network access and no telemetry.

---

## Install

Download `Hypertime-<version>.dmg`, drag **Hypertime** to `/Applications` and launch it.

Running from `/Applications` matters for one feature: "Launch at login" only registers
reliably from there. If macOS says the app is from an unidentified developer, the build was
signed ad-hoc rather than notarised — right-click the app and choose **Open** once.

Requires macOS 15 or later (Apple silicon or Intel).

## First run

Hypertime starts **idle** and shows its popup without taking focus. Type what you are working
on and press ↩. That first confirm starts tracking; from then on the app asks again every
30 minutes (configurable, or off).

The menu bar icon shows the state at a glance: an empty dial when idle, a filled dot while
tracking, two bars while paused.

## How tracking works

Time accrues into a **pending bucket** — the amount since your last check-in. Nothing is
written to a project until you confirm, so an unanswered popup can never misfile your time.

- **Confirm (↩)** adds the amount in the field to the selected project's total for today,
  empties the bucket and continues tracking that project.
- **Close (esc)** hides the popup and leaves the bucket running. The next check-in offers the
  larger amount.
- **Discard (⌘⌫)** throws the bucket away and starts a fresh one. Today's totals do not change.
- Editing the amount edits the bucket itself: confirm `0:20` out of `1:05` and the remaining
  45 minutes are gone, not hidden.

Time is never counted while the Mac sleeps or the screen is locked. Tracking pauses
automatically and resumes with a check-in when you come back. Quitting stops tracking; the app
does not resume on its own at launch.

## Keyboard

| Key | Where | Does |
|---|---|---|
| ↩ | anywhere in the popup | confirm: add the amount to the selected project |
| esc | anywhere in the popup | close and hand focus back |
| ⌘⌫ | anywhere in the popup | discard the pending amount |
| ↑ / ↓ | project field | move through the matching projects |
| ↑ / ↓ | amount field | ±1 min (⇧ ±5 min, ⌥ ±1 h) |
| ⇥ / ⇧⇥ | popup | project → amount → today's rows → Confirm |
| ↩ | a row in today's list | save that total and stay open |
| ⌘⇥ | anywhere | bring Hypertime forward with the popup focused |
| ⌘← / ⌘→ | Reports | previous / next period |
| ⌘T | Reports | jump to today |
| ⌘1…⌘4 | Reports | day / week / month / year |

Typing a name that does not exist offers **Create "…"** as the first row; ↩ creates the project
and starts tracking it.

## Time formats

Every duration field understands the same free text. Hours, minutes and seconds only — never
dates.

| You type | Means |
|---|---|
| `1:30`, `1:30:15` | 1 h 30 m, 1 h 30 m 15 s |
| `1h`, `1h 30m`, `1h30`, `1h30m15s` | unit forms, in any order |
| `90m`, `90 min`, `90 minutes`, `1 Std 30 Min` | German unit words work too |
| `1.5h`, `1,5h`, `.5h`, `2.5m` | decimals on any unit |
| `90` | a bare whole number is **minutes** |
| `1.5` | a bare decimal is **hours** |
| *(empty)* | zero |
| `+15m`, `-30m` | adjust an existing total (in the today list and Reports only) |

A single project can hold at most 24 hours on one day.

## Reports and editing

**Reports…** (⌘R, or the menu bar menu) opens day, week, month and year views.

- **Day** lists every project with time that day; click a total to set it.
- **Week** is a project × day grid; every cell is editable, and today's column is tinted.
- **Month** shows one intensity square per day — click one to open that day.
- **Year** breaks down by month — click one to open that month.
- Right-click a project row to rename, archive or delete it.

Typing an absolute value (`2h`) **sets** a total; typing `+15m` or `-30m` **adjusts** it. Editing
the current project's total folds the pending bucket in first, so nothing is counted twice.

## CSV export

**Export CSV** offers this month, this year or an arbitrary date range, and writes a matrix:
rows are dates, columns are projects, cells are that project's time on that day.

```
Date,Admin,Design System,Total
2026-09-01,1:20:00,0:00:00,1:20:00
2026-09-02,0:00:00,2:05:00,2:05:00
Total,1:20:00,2:05:00,3:25:00
```

Every date in the range appears, including empty ones. The file is UTF-8 with a BOM and CRLF
line endings (RFC 4180), so Excel and Numbers both open it cleanly. The delimiter (`,` or `;`),
the cell format (`1:30:15`, `1:30` or decimal hours) and the totals row and column are all
settings, and can be overridden per export.

## Settings

Check-in interval · pause on sleep and lock · morning hour for "pause until 07:00" ·
passive popup auto-hide · time display format · elapsed time in the menu bar · week start ·
Dock and Cmd+Tab visibility · launch at login · CSV defaults.

Your data lives in a single SQLite file:

```
~/Library/Application Support/Hypertime/hypertime.sqlite
```

Back it up by copying that file. If it ever becomes unreadable, Hypertime moves it aside as
`hypertime-corrupt-<timestamp>.sqlite`, starts fresh and tells you where the old one went.

---

## Development

```bash
swift test                  # 101 tests over HypertimeCore
scripts/run.sh              # build dist/Hypertime.app and launch it
scripts/run.sh --seed-demo  # same, against a seeded demo database
scripts/release.sh          # signed .app + .zip + .dmg in dist/
```

Hidden launch arguments: `--self-test` (headless AppKit smoke test, non-zero on failure),
`--screenshots <dir>` (design QA renders), `--render-icon <out> <appiconset>` (AppIcon.iconset).

- [docs/PLAN.md](docs/PLAN.md) — requirements, architecture, component specs, phase plan
- [docs/DESIGN_BRIEF.md](docs/DESIGN_BRIEF.md) — the brief the visual design was made from
- [docs/design-handoff/handoff/](docs/design-handoff/handoff/) — tokens, handoff notes, assets
- [docs/DECISIONS.md](docs/DECISIONS.md) — every decision that refined or deviated from the plan
- [docs/SYNC.md](docs/SYNC.md) — how a future backend would consume the change log
- [CLAUDE.md](CLAUDE.md) — notes for agents working in this repo

Target: macOS 15+, Swift 6, SwiftUI + AppKit, SQLite via GRDB.

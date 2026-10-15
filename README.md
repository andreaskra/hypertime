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

On the very first launch Hypertime has no projects yet, so it shows its popup without taking
focus and waits. Type what you are working on and press ↩.

After that it picks tracking straight back up on whatever you were last working on, every time
it launches — you do not have to start it by hand. The popup still appears so you can see what
it resumed on and change it. Turn this off with "Start tracking when Hypertime launches" in
Settings if you would rather begin each session deliberately.

While tracking, the app asks what you are working on every 30 minutes (configurable, or off).

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

Time is never counted while the Mac sleeps, while the screen is locked, or while you are simply
not there: after ten minutes without a keystroke or a mouse move (configurable, or off)
Hypertime stops and gives the idle stretch back, so a laptop left awake overnight does not
invent a night's work. Touching it again picks up where you left off.

 Tracking pauses
automatically and resumes with a check-in when you come back. Quitting stops tracking, and the
hours the app spends closed are never counted — a relaunch starts a fresh bucket from that
moment.

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

## Tasks

The popup carries a todo list above the day breakdown. `+` opens a task under the project in the
field. Click a task and it takes the clock — its time books to the task *and* to its project, so
the project total always contains its tasks rather than sitting beside them. Click it again to
pause; starting another task parks the first. The checkmark finishes a task: it leaves the list,
its time stays.

Give a task a timer from its `⋯` menu and the row counts down. At zero Hypertime comes forward
and asks: **Finish**, or **Keep working** — which drops the countdown and carries on. While a
task is running the regular check-in stays quiet, because the question is already answered.

Unfinished tasks carry over to the next day. The `⋯` menu also moves a task to another project,
renames it, and deletes it — deleting keeps the time on the project, since the work happened.

## Reports and editing

**Reports…** (⌘R, the `⋯` menu in the popup, or the menu bar menu) opens day, week, month and
year views. The popup itself steps through days with `‹ calendar ›` — days with tracked time
carry a dot in the calendar.

- **Chart or table**, toggled in the toolbar. The chart stacks projects per day (or per month
  for a year); tick a project to hide it, click one to show it alone, "Select all" to reset.
- **Totals and averages** for whatever range is on screen: per calendar day, per day actually
  worked, and the total.
- **Slide the window** with the toolbar's ⟷ toggle: the arrows then move one day at a time, so
  you can look at any arbitrary seven- or thirty-day stretch rather than only calendar weeks.
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

Check-in interval · start tracking on launch · pause on sleep and lock · idle timeout ·
morning hour for "pause until 07:00" ·
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
swift test                  # 139 tests over HypertimeCore
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

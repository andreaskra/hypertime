# Hypertime — Implementation Plan

Menu-bar time tracker for macOS. Local-only in this iteration. This document is the
contract for the building agent: Phase 1 builds the complete backbone with an unstyled
but fully functional UI; Phase 2 replaces the visuals with the design handoff described
in [DESIGN_BRIEF.md](DESIGN_BRIEF.md); Phase 3 hardens and packages.

Read fully before writing code. Every requirement has an ID (R-xx) so tasks, tests and
acceptance criteria can reference it.

---

## 1. Requirements

### 1.1 Menu bar & popup
- **R-01** App lives in the menu bar (NSStatusItem). Clicking the icon toggles the popup.
- **R-02** The popup ("check-in") asks what the user is working on. It shows the current
  project in a text field with dropdown, and a second text field holding the **time to
  add**, pre-filled with the time tracked since the last commit (the pending bucket, §5.5).
  Below the fields, a **today list** shows every project with time today and its total in
  an editable text field.
- **R-03** The time field is free text. Its content is parsed on commit. Supported formats:
  see §5.2. Hours, minutes, seconds only. No dates.
- **R-04** Confirm **adds** the parsed time-field value to the selected project's total
  for today, resets the pending bucket, and makes that project the current one. Close
  hides the popup without changes; the pending bucket keeps accumulating. A dedicated
  **Discard** button throws the pending bucket away (its time is lost, a fresh bucket
  starts now), hides the popup and returns focus; tracking continues on the current project.
- **R-05** The dropdown lists projects, most recently used first. The most recently used
  project is preselected.
- **R-06** Typing a name that does not exist creates a new project on commit.
- **R-07** The dropdown filters as you type using fuzzy matching (§5.4).
- **R-08** The popup can appear **without stealing focus** from the frontmost app
  (periodic check-in, tracking resume, launch). A passive popup auto-hides after 20 s
  (setting) unless the user engages with it; the bucket keeps accumulating.
- **R-09** After confirm or escape, focus returns to the app that was frontmost before the
  user interacted with the popup.
- **R-10** The app is reachable via Cmd+Tab. Activating it via Cmd+Tab shows the popup
  and gives it keyboard focus.
- **R-11** Keyboard model while the popup has focus: typing edits the project name;
  ↑/↓ move the project selection; Tab moves to the time field (Shift+Tab back);
  Enter commits; Esc closes and returns focus.

### 1.2 Tracking
- **R-12** While tracking, time accrues to the current project's total for the current
  local day, continuously, as wall-clock time.
- **R-13** A periodic check-in popup appears at a configurable interval (default 30 min)
  while tracking, without stealing focus (R-08).
- **R-14** Tracking can be paused for a selectable duration (15 m, 30 m, 1 h, 2 h, custom
  parsed duration) or "until 07:00 tomorrow". While paused nothing accrues and check-ins
  are suppressed. When the pause ends, tracking resumes on the same project and a
  check-in appears.
- **R-15** Quitting the app stops tracking. On launch the app is idle and shows the
  popup; tracking starts on the first commit. (Assumption A-03.)
- **R-16** The app registers itself as a login item ("autostart"), toggleable in settings.

### 1.3 History, reports, export
- **R-17** Per-project tracked time for any day can be edited: today via the today list
  in the popup, any day via the Reports Day view. Editing a total **sets** it; relative
  input (`+15m`) adjusts it.
- **R-18** The user can navigate to past days and view totals by day, week, month and year.
- **R-19** CSV export: rows are dates, columns are projects, cells are the time for that
  project on that day. Export scopes: month, year, arbitrary date range.

### 1.4 Look & feel
- **R-20** Transparency and glass heavy, beautiful, native. Handled by the design handoff
  and Phase 2. Must degrade gracefully with "Reduce transparency" enabled.

---

## 2. Decisions and assumptions

Decisions are fixed unless the user overrides them. Assumptions are flagged so the user
can correct them; the agent proceeds with the stated default.

| ID | Decision / assumption |
|---|---|
| D-01 | Language/stack: Swift 6 (Swift 5 language mode acceptable for AppKit-heavy code), SwiftUI for views, AppKit for status item, panels, focus and keyboard handling. |
| D-02 | Minimum deployment target **macOS 15** (the user's machine runs 15.7). Liquid Glass (`glassEffect`, macOS 26) is not available on the target machine. Glass is built with `NSVisualEffectView` materials plus custom layering (see brief). |
| D-03 | Build system: SwiftPM package is the single source of truth (`HypertimeCore` library + `Hypertime` executable target). A script assembles `Hypertime.app`. Optional: XcodeGen `project.yml` for Xcode debugging (`brew install xcodegen`). No hand-maintained `.xcodeproj`. |
| D-04 | Persistence: SQLite via **GRDB.swift** (SPM). Rationale: migrations, queries for reports, trivially syncable to a backend later. DB at `~/Library/Application Support/Hypertime/hypertime.sqlite`. |
| D-05 | Day totals are the source of truth (`day_entry.seconds`). The engine adds deltas; manual edits set the value. An append-only `change_log` records every mutation for later sync/undo. |
| D-06 | Day boundary = local midnight in the current time zone. Accrual that crosses midnight is split between the two days. |
| D-07 | Cmd+Tab visibility requires `NSApp.setActivationPolicy(.regular)`, which necessarily shows a Dock icon. Setting "Show in Dock and Cmd+Tab" (default on). Turning it off makes the app `.accessory` (menu bar only, no Cmd+Tab). |
| D-08 | Committing **adds** the time-field value to today's total of the selected project; it never sets. The field is pre-filled with the pending time accrued since the last commit, so a plain Enter attributes exactly that time. Editing a total (today list, Reports) sets the value; relative input (`+15m`) adjusts it there. The popup's add field accepts absolute durations only. |
| D-09 | Committing while paused resumes tracking. Committing while idle starts tracking. |
| D-13 | **Pending bucket model.** While tracking, time accrues into an in-memory `pending` bucket (project, seconds, since = last commit). It is not written to `day_entry` until a commit. Reports and the today list attribute pending time provisionally to the current project, so totals are always right even if the user never answers a check-in. A commit writes the (possibly edited) amount to the selected project and resets the bucket. |
| D-10 | Bare number parsing: integer → minutes, decimal → hours (`90` = 1:30:00, `1.5` = 1:30:00). |
| D-11 | Week starts on Monday (setting: Monday/Sunday). Week numbering: ISO 8601. |
| D-12 | CSV: RFC 4180, UTF-8 with BOM (Excel friendly), delimiter `,` and decimal separator `.` (confirmed; a `;` / `,` option stays in settings), cell format setting (`H:MM:SS` default, or decimal hours with 2 decimals). Includes every date in range, even empty ones. Trailing `Total` column and `Total` row. |
| A-01 | Time while the Mac sleeps or the screen is locked is **not** counted. Tracking auto-pauses on sleep/lock and resumes on wake/unlock (setting, default on). A resume shows the check-in popup. |
| D-14 | A **passive** popup auto-hides after 20 s (setting `passivePopupAutoHideSeconds`, 0 = never). Any engagement (panel becomes key, mouse enters, a click) cancels the timer. Auto-hide never changes focus. A focused popup never auto-hides. Pending time keeps accumulating in all cases. |
| A-03 | On launch the app does not resume tracking on its own; it shows the popup with the last project preselected and waits for a commit (R-15). |
| A-04 | Per-project daily total is capped at 24 h; the parser rejects larger values. |
| A-05 | Idle detection (no input for N minutes) is out of scope for this iteration; the architecture leaves a hook for it. |
| D-15 | Editing the amount in the time field edits the bucket itself: the committed amount replaces pending entirely. Smaller → the remainder is discarded, never kept hidden. Larger → the surplus is simply a manual addition. (Confirmed by the user.) |
| A-07 | Pending time is auto-committed to the current project at local midnight (the pre-midnight part into the previous day), on stop/quit, and before any edit of a total. Pause, sleep and lock preserve the bucket unchanged, so after a break the popup still offers the unattributed time. |

---

## 3. Architecture

```
┌────────────────────────── Hypertime.app (executable target) ──────────────────────────┐
│ AppDelegate                                                                            │
│  ├─ ActivationController      activation policy, Cmd+Tab handling, focus restore       │
│  ├─ StatusItemController      NSStatusItem, icon states, context menu                  │
│  ├─ CheckInPanelController    NSPanel (non-activating), positioning, show/hide modes   │
│  ├─ ReportsWindowController   NSWindow hosting SwiftUI ReportsView                     │
│  ├─ SettingsWindowController  NSWindow hosting SwiftUI SettingsView                    │
│  ├─ ExportController          NSSavePanel + CSVExporter                                │
│  ├─ LoginItemController       SMAppService                                             │
│  └─ SystemEventsObserver      sleep/wake, lock/unlock, timezone/day change             │
│ ViewModels (@Observable, @MainActor): CheckInViewModel, ReportsViewModel, SettingsVM   │
│ Views (SwiftUI): CheckInView, ProjectField (NSViewRepresentable), TimeField, Reports…  │
└──────────────────────────────────────▲────────────────────────────────────────────────┘
                                       │ AppModel (single @MainActor object owning everything below)
┌──────────────────────────── HypertimeCore (library, Foundation only) ─────────────────┐
│ Models          Project, LocalDate, Seconds, DayEntry, TrackingStatus, Period          │
│ TimeParser      text → Seconds (absolute or relative)                                  │
│ TimeFormatter   Seconds → text (display styles)                                        │
│ FuzzyMatcher    query × [Project] → ranked matches                                     │
│ Store           GRDB-backed persistence, migrations, change_log                        │
│ TrackingEngine  state machine: idle / tracking / paused; ticks; midnight split          │
│ PauseScheduler  computes pause-until dates ("until 07:00 tomorrow")                    │
│ Reports         aggregation for day/week/month/year                                    │
│ CSVExporter     matrix export                                                          │
│ Settings        typed wrapper over UserDefaults                                        │
│ Clock           protocol (now(), timeZone) with SystemClock and TestClock              │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

Rules:
- `HypertimeCore` has **no AppKit/SwiftUI imports**. Everything in it is unit-testable with `swift test`.
- All persistence goes through `Store`. All time reads go through `Clock` (never `Date()` directly) so tests can control time.
- The UI binds only to view models. View models talk only to `AppModel`/engine/store. Phase 2 can replace every view without touching anything below the view-model layer.

### 3.1 Repository layout

```
hypertime/
├── README.md
├── CLAUDE.md                      # pointers + build/test commands for agents
├── docs/
│   ├── PLAN.md                    # this file
│   ├── DESIGN_BRIEF.md            # brief for Claude Design
│   └── DECISIONS.md               # running log of decisions made during the build
├── Package.swift
├── Sources/
│   ├── HypertimeCore/             # library (see §3)
│   └── Hypertime/                 # app executable (AppKit + SwiftUI)
│       ├── App/                   # AppDelegate, AppModel, controllers
│       ├── ViewModels/
│       ├── Views/
│       │   ├── CheckIn/
│       │   ├── Reports/
│       │   ├── Settings/
│       │   └── Components/        # GlassBackground, DesignTokens, etc. (Phase 2)
│       └── Resources/
│           ├── Info.plist
│           ├── Hypertime.entitlements
│           └── Assets.xcassets    # menu bar icon (template), app icon
├── Tests/
│   └── HypertimeCoreTests/
├── scripts/
│   ├── build-app.sh               # swift build -c release → Hypertime.app (ad-hoc signed)
│   ├── run.sh                     # build + open, kills previous instance
│   └── seed-demo-data.sh          # launches with --seed-demo for design QA
└── .gitignore
```

`Info.plist` essentials: `LSUIElement` = **false** (D-07; the app switches policy at runtime),
`NSHumanReadableCopyright`, `CFBundleIdentifier` = `com.hypertime.app` (placeholder, ask user),
`LSMinimumSystemVersion` = 15.0, `NSSupportsAutomaticTermination` = false,
`NSSupportsSuddenTermination` = false.

---

## 4. Data model

### 4.1 Core types (Swift)

```swift
public typealias Seconds = Int

public struct LocalDate: Hashable, Comparable, Codable, Sendable {   // never a Date; avoids TZ bugs
    public var year: Int, month: Int, day: Int
    public init(_ date: Date, calendar: Calendar)
    public var isoString: String                      // "2026-09-07"
    public static func parse(_ iso: String) -> LocalDate?
    public func adding(days: Int, calendar: Calendar) -> LocalDate
    public func startOfDay(calendar: Calendar) -> Date
}

public struct Project: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var createdAt: Date
    public var lastUsedAt: Date?
    public var isArchived: Bool
}

public struct DayEntry: Hashable, Codable, Sendable { public var projectID: UUID; public var day: LocalDate; public var seconds: Seconds }

public enum TrackingStatus: Equatable, Sendable {
    case idle
    case tracking(projectID: UUID, since: Date)
    case paused(projectID: UUID, until: Date, reason: PauseReason)
}
public enum PauseReason: String, Codable, Sendable { case manual, systemSleep, screenLock }

public enum Period: Hashable, Sendable {
    case day(LocalDate)
    case week(isoYear: Int, isoWeek: Int)
    case month(year: Int, month: Int)
    case year(Int)
    public func range(calendar: Calendar, weekStart: Weekday) -> ClosedRange<LocalDate>
    public func previous(...) -> Period; public func next(...) -> Period
    public static func containing(_ date: LocalDate, kind: PeriodKind, ...) -> Period
}
```

### 4.2 SQLite schema (GRDB migration `v1`)

```sql
CREATE TABLE project (
  id            TEXT PRIMARY KEY,                 -- UUID string
  name          TEXT NOT NULL UNIQUE COLLATE NOCASE,
  created_at    REAL NOT NULL,                    -- unix seconds
  last_used_at  REAL,
  archived      INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE day_entry (
  project_id    TEXT NOT NULL REFERENCES project(id) ON DELETE CASCADE,
  day           TEXT NOT NULL,                    -- "YYYY-MM-DD" local date
  seconds       INTEGER NOT NULL DEFAULT 0 CHECK (seconds >= 0 AND seconds <= 86400),
  updated_at    REAL NOT NULL,
  PRIMARY KEY (project_id, day)
);
CREATE INDEX day_entry_day ON day_entry(day);
CREATE TABLE app_state (                          -- persisted engine state, one row per key
  key           TEXT PRIMARY KEY,                 -- current_project_id, status, paused_until, pause_reason,
  value         TEXT                              -- last_tick_at, pending_seconds, pending_since, last_check_in_at
);
CREATE TABLE change_log (                         -- append-only, for sync/undo later
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  at            REAL NOT NULL,
  kind          TEXT NOT NULL,                    -- project.create/rename/archive, entry.set, entry.add
  payload       TEXT NOT NULL                     -- JSON
);
```

Prune `change_log` rows older than 90 days on launch. Rows with `seconds = 0` are allowed
but the reports layer treats missing and zero identically.

### 4.3 Store API

```swift
public final class Store: Sendable {                // wraps GRDB DatabaseQueue; all methods synchronous, called from main actor
    public init(path: String, clock: Clock) throws  // runs migrations
    public static func inMemory(clock: Clock) throws -> Store

    // Projects
    public func projects(includeArchived: Bool = false) throws -> [Project]      // sorted lastUsedAt desc, then name
    public func project(id: UUID) throws -> Project?
    public func project(named: String) throws -> Project?                        // case-insensitive, trimmed
    public func findOrCreateProject(named: String) throws -> Project             // trims; rejects empty
    public func renameProject(id: UUID, to: String) throws
    public func setArchived(id: UUID, _ archived: Bool) throws
    public func deleteProject(id: UUID) throws                                   // cascades
    public func touchProject(id: UUID) throws                                    // last_used_at = now

    // Entries
    public func seconds(project: UUID, day: LocalDate) throws -> Seconds
    public func setSeconds(project: UUID, day: LocalDate, _ seconds: Seconds) throws   // clamps 0...86400
    public func addSeconds(project: UUID, day: LocalDate, _ delta: Seconds) throws     // clamps
    public func entries(in range: ClosedRange<LocalDate>) throws -> [DayEntry]
    public func projectsWithEntries(in range: ClosedRange<LocalDate>) throws -> [Project]

    // Engine state
    public func loadEngineState() throws -> PersistedEngineState?
    public func saveEngineState(_ s: PersistedEngineState?) throws

    // Observation
    public var changes: AsyncStream<StoreChange>                                  // fires after any write (main actor)
}
```

---

## 5. Core component specifications

### 5.1 Clock
```swift
public protocol Clock: Sendable { func now() -> Date; var timeZone: TimeZone { get }; var calendar: Calendar { get } }
public struct SystemClock: Clock { ... }                    // calendar = .autoupdatingCurrent with firstWeekday from settings
public final class TestClock: Clock { public var now: Date; public func advance(by:) }
```

### 5.2 TimeParser

```swift
public enum ParsedTime: Equatable { case absolute(Seconds); case relative(Seconds) }
public enum TimeParseError: Error, Equatable { case empty, unrecognized, duplicateUnit, outOfRange, minutesOutOfRange, secondsOutOfRange }
public struct TimeParser {
    public init(decimalSeparators: Set<Character> = [".", ","])
    public func parse(_ text: String) throws -> ParsedTime
    public func apply(_ parsed: ParsedTime, to current: Seconds) -> Seconds          // clamps 0...86400
}
```

Grammar (case-insensitive, whitespace tolerant, one leading `+`/`-` makes it relative):
1. Colon forms: `H:MM` (hours:minutes), `H:MM:SS`. `MM` and `SS` must be `0...59`; `H` any integer `0...24`. `1:5` → 1:05:00.
2. Unit forms, any order, each unit at most once:
   hours `h, hr, hrs, hour, hours, std`; minutes `m, min, mins, minute, minutes`;
   seconds `s, sec, secs, second, seconds`. Whitespace optional between number and unit and between groups.
   A trailing bare number after a unit takes the next smaller unit: `1h30` = 1h 30m, `1h30m15` = 1h 30m 15s.
3. Decimals with `.` or `,` are allowed on any unit: `1.5h`, `1,5h`, `.5h`, `2.5m` (= 150 s).
4. Bare number: integer → minutes; decimal → hours (D-10).
5. Empty or whitespace only → `.absolute(0)` (an empty time field means zero).
6. Result must be `0...86400` (A-04). Anything else → `outOfRange`.

Test table (must be encoded as unit tests):

| input | result |
|---|---|
| `1:30` | 5400 |
| `1:30:15` | 5415 |
| `0:05` | 300 |
| `1:5` | 3900 |
| `1:75` | error minutesOutOfRange |
| `1h` | 3600 |
| `1h 30m` | 5400 |
| `1h30` | 5400 |
| `1h30m15s` | 5415 |
| `90m` / `90 min` / `90 minutes` | 5400 |
| `1.5h` / `1,5h` / `1.5 hours` | 5400 |
| `.5h` | 1800 |
| `5400s` | 5400 |
| `90` | 5400 |
| `1.5` | 5400 |
| `2 hours 5 minutes 3 seconds` | 7503 |
| `30m 1h` | 5400 |
| `1 Std 30 Min` | 5400 |
| `` / `   ` | 0 |
| `24h` | 86400 |
| `25h` / `1500m` | error outOfRange |
| `1h 1h` | error duplicateUnit |
| `abc` / `1x` / `1::2` | error unrecognized |
| `+15m` | relative 900 |
| `-1:00` | relative −3600 |
| apply(relative −3600, to 1800) | 0 (clamped) |

### 5.3 TimeFormatter

```swift
public enum TimeStyle { case clock /* 1:30:15 */, clockNoSeconds /* 1:30 */, units /* 1h 30m */, decimalHours /* 1.50 */ }
public struct TimeFormatter { public func string(_ s: Seconds, style: TimeStyle, decimalSeparator: String = ".") -> String }
```
`clock` never pads hours (`0:05:00`, `12:00:00`). `units` omits zero components except when total is zero (`0m`).
The time field shows `clock` style by default (setting can change it). Round trip: `parse(format(x)) == x` for all styles except `decimalHours`.

### 5.4 FuzzyMatcher

```swift
public struct FuzzyMatch<T> { public let item: T; public let score: Int; public let matchedIndices: [Int] }
public enum FuzzyMatcher {
    public static func rank<T>(_ query: String, in items: [T], key: (T) -> String, recency: (T) -> Date?) -> [FuzzyMatch<T>]
}
```
- Case- and diacritic-insensitive (`folding(options: [.caseInsensitive, .diacriticInsensitive])`).
- Subsequence match required (every query char appears in order). Score: +10 per matched char, +15 bonus if match starts at index 0, +8 for each match at a word boundary, +5 per consecutive match, −1 per gap character. Ties broken by `recency` desc, then name.
- Empty query → all items, ordered by recency desc then name. `matchedIndices` are returned so the UI can highlight.
- Also exposes `exactMatch(query, in:)` (case-insensitive, trimmed) used by commit to decide "existing vs new".

### 5.5 TrackingEngine

```swift
public struct PendingTime: Equatable, Sendable { public var projectID: UUID; public var seconds: Seconds; public var since: Date }

@MainActor public final class TrackingEngine {
    public init(store: Store, clock: Clock, settings: Settings)
    public private(set) var status: TrackingStatus
    public private(set) var currentProjectID: UUID?           // remembered even when idle/paused
    public private(set) var pending: PendingTime?             // unattributed time since the last commit (D-13)
    public var events: AsyncStream<TrackingEvent>             // .statusChanged, .tick(pending), .checkInDue, .pauseEnded

    public func start(projectID: UUID)                        // idle/paused → tracking on projectID; keeps pending
    public func commit(projectID: UUID, seconds: Seconds)     // store.addSeconds(projectID, today, seconds); pending = nil;
                                                              // touchProject; start(projectID); lastCommitAt = now
    public func setTotal(projectID: UUID, day: LocalDate, seconds: Seconds) // autoCommitPending() first (A-07), then store.setSeconds
    public func discardPending()                               // pending = fresh bucket (0 s, since = now); lastCommitAt = now; status unchanged (R-04)
    public func pause(until: Date, reason: PauseReason)       // keeps pending
    public func resume()                                       // paused → tracking on currentProjectID
    public func stop()                                         // autoCommitPending(); → idle (used on quit)
    public func liveSeconds(project: UUID, day: LocalDate) -> Seconds  // stored + pending.seconds if project == pending.projectID && day == today
    public func tick()                                         // called by a 1 s timer; also callable from tests
    public func restore()                                      // on launch: load state; per A-03 becomes idle but keeps currentProjectID; drops pending (already auto-committed on quit; after a crash, restores persisted pending and auto-commits it)
    private func autoCommitPending()                           // commit(pending.projectID, pending.seconds) without touching lastCheckInAt
}
```

Tick algorithm (`tracking` only):
1. `now = clock.now()`, `delta = now − lastTickAt`. If `delta > maxGap` (setting, default 120 s) or `delta < 0` the machine was asleep, frozen, or the clock moved: discard the gap (A-01), set `lastTickAt = now`, return.
2. If `LocalDate(lastTickAt) != LocalDate(now)`: split delta at local midnight. Add the pre-midnight part to `pending`, auto-commit pending into the previous day for the current project (A-07), then start a fresh bucket (`since = midnight`) with the post-midnight part (D-06).
3. Otherwise `pending.seconds += delta` (create the bucket with `since = lastCommitAt` if nil). Persist `pending` to `app_state` every 15 s and on every state change (crash safety; nothing goes to `day_entry` until a commit).
4. `nextCheckInAt = max(lastCommitAt, lastCheckInShownAt) + checkInInterval`. If `now ≥ nextCheckInAt` and interval ≠ off → emit `.checkInDue`, set `lastCheckInShownAt = now`. A dismissed popup therefore comes back one interval later with the larger pending amount.
5. `paused`: if `now ≥ until` → `resume()` and emit `.pauseEnded` (UI shows the popup).

Persisted state (`app_state`): status kind, project id, tracking_since, paused_until, pause_reason, last_tick_at, pending_seconds, pending_since, last_check_in_at, last_commit_at. Saved on every state change and every persist tick. After a crash at most 15 s of pending time is lost, which is acceptable.

### 5.6 PauseScheduler
```swift
public enum PausePreset: CaseIterable { case m15, m30, h1, h2, untilMorning, custom }
public struct PauseScheduler {
    public func until(_ preset: PausePreset, customDuration: Seconds? = nil, now: Date, calendar: Calendar, morningHour: Int = 7) -> Date
}
```
`untilMorning`: next occurrence of `07:00` local strictly after `now` (if it is 03:00 that is today 07:00; if 09:00, tomorrow 07:00). Morning hour is a setting.

### 5.7 Reports
```swift
public struct ReportRow: Identifiable { public let project: Project; public let seconds: Seconds; public let perDay: [LocalDate: Seconds] }
public struct Report { public let period: Period; public let days: [LocalDate]; public let rows: [ReportRow]; public let total: Seconds; public let perDayTotal: [LocalDate: Seconds] }
public struct ReportBuilder { public init(store: Store, engine: TrackingEngine?, clock: Clock, weekStart: Weekday)
                              public func report(for period: Period) throws -> Report }
```
Rows: projects with any time in the period, plus the current project even if zero, sorted by seconds desc then name. When `engine` is provided and the period includes today, pending time is included for the current project (D-13) so the day view is live and totals never under-report.

### 5.8 CSVExporter
```swift
public struct CSVOptions { public var delimiter: Character = ","; public var cellStyle: TimeStyle = .clock; public var includeBOM = true; public var includeTotals = true; public var decimalSeparator = "." }
public enum ExportScope { case month(year: Int, month: Int); case year(Int); case range(ClosedRange<LocalDate>) }
public struct CSVExporter {
    public init(store: Store, clock: Clock)
    public func csv(scope: ExportScope, options: CSVOptions) throws -> String
    public static func suggestedFilename(scope: ExportScope) -> String     // Hypertime-2026-09.csv | Hypertime-2026.csv | Hypertime-2026-09-01_2026-09-15.csv
}
```
Layout: header `Date,<Project…>,Total`; one row per date in range (all dates, chronological); projects = those with any time in scope, sorted by name; empty cells are `0:00:00` (or `0.00`). If `includeTotals`, a final `Total` row. Fields containing delimiter, quote or newline are quoted per RFC 4180. Line ending `\r\n`.

### 5.9 Settings
`Settings` is a typed `UserDefaults` wrapper with a `didChange` stream. Keys and defaults:

| key | default |
|---|---|
| checkInIntervalMinutes | 30 (0 = off; choices 15/30/45/60/90/120); counted from the last commit or last shown check-in, whichever is later |
| launchAtLogin | true (mirrors SMAppService status) |
| showInDockAndCmdTab | true |
| showElapsedInMenuBar | false |
| weekStart | monday |
| timeDisplayStyle | clock |
| pauseOnSleepAndLock | true |
| morningHour | 7 |
| maxGapSeconds | 120 |
| csvDelimiter / csvCellStyle / csvIncludeTotals | `,` / clock / true |
| flushIntervalSeconds | 15 |
| passivePopupAutoHideSeconds | 20 (0 = never) |

---

## 6. macOS integration specifications (app target)

### 6.1 Activation policy & Cmd+Tab (R-10, D-07)
- At launch: `NSApp.setActivationPolicy(settings.showInDockAndCmdTab ? .regular : .accessory)`. Re-apply when the setting changes.
- Provide a minimal main menu programmatically (App menu with Quit; **Edit menu** with Cut/Copy/Paste/Select All — otherwise Cmd+C/V do not work in the text fields; Window menu). Without a main menu a `.regular` app looks broken when activated.
- `applicationDidBecomeActive`: if the activation was not initiated by our own code (`ActivationController.isSelfActivating == false`) → `CheckInPanelController.show(mode: .focused)`. This is the Cmd+Tab path. Also handle `applicationShouldHandleReopen` (Dock icon click) the same way.
- When the app has no visible windows and gets activated, the panel must still appear under the status item.

### 6.2 Focus restore (R-09)
- `ActivationController` observes `NSWorkspace.shared.notificationCenter` `didActivateApplicationNotification` and keeps `previousApp: NSRunningApplication?` = last activated app that is not us. This is more reliable than reading `frontmostApplication` at activation time (by then it is already us).
- `returnFocus()`: `panel.orderOut(nil)`; then `NSApp.hide(nil)` if `previousApp` is nil, otherwise `previousApp.activate()` (on macOS 14+: `NSApp.yieldActivation(to: previousApp)` first). Called on Esc, Close, and after Confirm. If the popup was shown passively and the user never focused it, closing it must not activate anything.

### 6.3 Check-in panel (R-02, R-08, R-11)
- `NSPanel` subclass `CheckInPanel`: `styleMask = [.nonactivatingPanel, .borderless, .fullSizeContentView]`, `level = .floating`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]`, `isFloatingPanel = true`, `hidesOnDeactivate = false`, `isMovableByWindowBackground = true`, `backgroundColor = .clear`, `isOpaque = false`, `hasShadow = true`. Override `canBecomeKey` → true, `canBecomeMain` → false.
- Content: `NSHostingView(rootView: CheckInView(viewModel:))`. In Phase 1 the hosting view sits inside an `NSVisualEffectView` (`.hudWindow`, `.behindWindow`, corner radius 16) so glass mechanics are proven early. Layout top to bottom: heading/state line, project field (with the match dropdown overlaying everything below it while open), time-to-add field, **today list** (`TodayListView`: one row per project with time today, live total in an editable `TotalField`, current project marked, up to 6 rows visible then scrolls), buttons row (Pause, Close, Confirm). The panel resizes with the list; the anchor point under the status item stays fixed.
- `show(mode:)`:
  - `.passive` (timer, resume, launch): position, `orderFrontRegardless()`. Does **not** call `NSApp.activate`. Panel is not key; keyboard goes nowhere until the user clicks it or Cmd+Tabs. Starts the auto-hide timer (D-14); the timer is cancelled by `windowDidBecomeKey`, `mouseEntered` (tracking area over the whole panel) or any click, and on expiry calls `hide()` only (no focus change).
  - `.focused` (status item click, Cmd+Tab): `isSelfActivating = true; NSApp.activate(); panel.makeKeyAndOrderFront(nil); isSelfActivating = false`, then focus the project field and select all its text.
- Clicking into a passive panel makes it key (`becomesKeyOnlyIfNeeded = false`); `windowDidBecomeKey` records that the user engaged so `returnFocus` knows to hand focus back.
- Buttons row: **Discard** (destructive-secondary, ⌘⌫; the text-field delegate intercepts `deleteToBeginningOfLine:` only when ⌘ is held), **Close** (Esc), **Confirm** (↩, default button).
- Positioning: centered horizontally under the status item button's screen frame, 6 pt below the menu bar; clamp to the screen's `visibleFrame`. If the status item is hidden (menu bar overflow), fall back to top-right of the main screen.
- Hide: `orderOut(nil)`. `hide()` never activates anything by itself; `returnFocus()` does.
- Toggle from status item click: if visible and key → hide + returnFocus; if visible and not key → make focused; if hidden → show focused.

### 6.4 Keyboard handling inside the panel (R-11)
Use AppKit text fields wrapped in `NSViewRepresentable` for deterministic key handling (SwiftUI's `onKeyPress` is acceptable for the list but not for intercepting Tab/Enter/Esc inside text fields):
- `ProjectField`: `NSTextField` with `NSTextFieldDelegate.control(_:textView:doCommandBy:)`:
  `moveUp:` / `moveDown:` → move selection in the filtered list (wraps), field text = selected project name with the typed prefix preserved for filtering (combobox semantics: the field shows the highlighted name; typing again re-filters);
  `insertNewline:` → commit; `cancelOperation:` → close+returnFocus; `insertTab:` → focus time field; `insertBacktab:` → no-op.
  Text change → `viewModel.query = text` → list refilters via `FuzzyMatcher`; highlighted row resets to first result. If there is no exact match the first row is the synthetic "Create “<query>”" row.
- `TimeField` (time to add): `NSTextField` with the same delegate: `insertNewline:` commit, `cancelOperation:` close, `insertTab:` → first today-list row (or Confirm button if the list is empty), `insertBacktab:` → project field. `moveUp:`/`moveDown:` adjust by ±1 min (±5 min with Shift, ±1 h with Option), formatted back into the field.
- Live time: while the time field is not being edited it shows `engine.pending.seconds`, updating every second. The first keystroke freezes it (`isEditingTime = true`); clearing the field back to empty unfreezes it. Switching the highlighted project does **not** change the field: the amount to add is independent of the project (D-08). If pending is nil (idle) the field starts empty and commit with an empty field adds 0 (it just starts tracking).
- `TotalField` (today list rows): same delegate. `insertNewline:` saves that total via `engine.setTotal` and keeps the popup open; `insertTab:`/`insertBacktab:` move down/up the list, then to Confirm / back to the time field; `cancelOperation:` reverts the row and closes the popup. Blur saves if valid. Relative input allowed here (`+15m`).
- The panel's `keyDown` handles Esc as a fallback when no text field is first responder.

### 6.5 Commit flow (R-04, R-06, D-08, D-09)
```
commit():
  name = trimmed project field text; if empty → shake/error, return
  parsed = try TimeParser.parse(timeField.text) → on error or .relative: mark time field invalid, focus it, return
  project = store.project(named: name) ?? store.findOrCreateProject(named: name)
  engine.commit(projectID: project.id, seconds: parsed.absolute)             // adds, resets pending, starts/resumes tracking
  panel.hide(); activation.returnFocus()

discard():
  engine.discardPending()                                                    // bucket → 0, tracking continues
  panel.hide(); activation.returnFocus()

close():                                                                     // Esc / Close button / auto-hide
  panel.hide(); if user had engaged → activation.returnFocus()               // bucket untouched, keeps accumulating

editTotal(row, text):                                                        // today list and Reports Day view
  parsed = try TimeParser.parse(text) → on error: mark row invalid, return
  seconds = parser.apply(parsed, to: engine.liveSeconds(row.project, day))   // absolute sets, relative adjusts
  engine.setTotal(projectID: row.project, day: day, seconds: seconds)        // auto-commits pending first (A-07)
```

### 6.6 Status item (R-01)
- `NSStatusItem` with template image, 18×18 pt. States: idle, tracking, paused. Optional title text (elapsed today for current project, monospaced digits, updated every second when `showElapsedInMenuBar`).
- Left click → toggle panel (focused). Right click or Control-click → menu:
  `Tracking: <project> · 1:32:10` (disabled title row) / `Pause ▸` (15 m, 30 m, 1 h, 2 h, Custom…, Until 07:00) or `Resume` / `Reports…` / `Export CSV ▸` (This month, This year, Date range…) / `Settings…` / separator / `Launch at Login` (checkbox) / `Quit Hypertime`.
- Menu is built via `NSMenu` (not SwiftUI `MenuBarExtra`) so left-click and right-click can differ (`button.sendAction(on: [.leftMouseUp, .rightMouseUp])`).

### 6.7 System events (A-01)
- `NSWorkspace.willSleepNotification` → if tracking and `pauseOnSleepAndLock`: flush, `engine.pause(until: .distantFuture, reason: .systemSleep)`.
- `NSWorkspace.didWakeNotification` → if paused with reason `.systemSleep` → `engine.resume()`, show panel passive.
- Screen lock/unlock via `DistributedNotificationCenter.default()` names `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` → same with reason `.screenLock`.
- `NSCalendarDayChanged`, `NSSystemTimeZoneDidChange` → force a tick and refresh views.
- `applicationWillTerminate` → `engine.stop()` (flush + persist idle) (R-15).

### 6.8 Timers
One `Timer` (1 s, tolerance 0.2 s) on the main run loop calling `engine.tick()`; a second only for UI refresh is not needed since `tick` emits `.tick` events. Timers must survive the panel being hidden.

### 6.9 Login item (R-16)
`SMAppService.mainApp.register()` / `.unregister()`; read `.status` to render the checkbox; surface `.requiresApproval` with a hint linking to System Settings › General › Login Items. Only reliable when the app runs from `/Applications` — the build script warns if not.

### 6.10 Reports window (R-17, R-18)
Standard resizable `NSWindow` (titled, `.fullSizeContentView`, transparent titlebar) hosting `ReportsView`. Behavior:
- Segmented period kind (Day / Week / Month / Year), ◀ ▶ navigation, "Today" button, period title (`Mon 7 Sep 2026`, `Week 37 · 7–13 Sep 2026`, `September 2026`, `2026`).
- Day: the same `TodayListView` component as the popup, for any day (editable `TotalField` per row, saves on Enter/blur via `engine.setTotal`), an "Add project…" row, total. For today, pending time is shown live for the current project and auto-committed before an edit (A-07).
- Week/Month/Year: per-project totals, plus a per-day breakdown (a grid; for Year a per-month breakdown). Cells in Week view are editable; Month/Year cells open the Day view on click.
- Keyboard: ⌘← / ⌘→ previous/next period, ⌘T today, ⌘1–4 period kind.
- Project management (rename, archive, delete with confirmation) via context menu on a row.

### 6.11 Export (R-19)
Menu item or Reports toolbar button opens a small sheet: scope (This month / This year / Custom range with two date pickers, prefilled with the currently displayed period), delimiter, cell style, totals. "Export…" runs `NSSavePanel` with `suggestedFilename`, writes the file, reveals it optionally.

### 6.12 Settings window
`SettingsView` (SwiftUI `Form`) bound to `Settings`. Sections: Tracking (interval, pause on sleep/lock, morning hour), Appearance (time style, elapsed in menu bar), System (launch at login, show in Dock/Cmd+Tab), Export defaults.

---

## 7. Phases

### Phase 0 — Scaffolding (½ day)
Tasks:
1. `git init`, `.gitignore` (`.build/`, `*.xcodeproj`, `DerivedData/`, `dist/`).
2. `Package.swift`: platforms `.macOS(.v15)`; products `HypertimeCore` (library), `Hypertime` (executable); dependency `GRDB.swift` (pin latest 7.x); test target.
3. `scripts/build-app.sh`: `swift build -c release --product Hypertime`, assemble `dist/Hypertime.app/Contents/{MacOS,Resources}`, copy `Info.plist`, compile `Assets.xcassets` with `actool` (or ship PNGs and an `.icns` built with `iconutil` in Phase 3), `codesign --force --sign - --entitlements … dist/Hypertime.app`. `scripts/run.sh` kills any running instance then `open dist/Hypertime.app`.
4. Optional `project.yml` for XcodeGen and a note in `CLAUDE.md` on how to generate the Xcode project for debugging.
5. `CLAUDE.md`: how to build, test, run; where the plan lives; the "core has no AppKit" rule.

Acceptance: `swift build` and `swift test` pass with a placeholder test; `scripts/run.sh` launches an app showing a status item.

### Phase 1 — Backbone + functional (unstyled) UI (3–4 days)
Build everything in §4–§6 with plain, unstyled SwiftUI/AppKit controls. Visual quality is explicitly not a goal here, but every interaction and every mechanic must work, because Phase 2 only reskins.

Order of work (each step ends with green tests):
1. `Clock`, `LocalDate`, `Period` (+ tests for ranges, ISO weeks across year boundaries, DST days, week start Sunday/Monday).
2. `TimeParser`, `TimeFormatter` (+ the full table in §5.2, round-trip property test).
3. `FuzzyMatcher` (+ tests for ranking, diacritics, empty query, exact match).
4. `Store` with GRDB migrations (+ tests using `Store.inMemory`: CRUD, case-insensitive uniqueness, clamping, cascade delete, change_log, range queries).
5. `TrackingEngine` + `PauseScheduler` (+ tests with `TestClock`: pending accrual, commit adds and resets, commit to a different project drops provisional attribution, smaller/larger committed amounts (D-15), discardPending, auto-commit at midnight/stop/setTotal (A-07), pause preserves pending, gap discard, negative delta, auto-resume, check-in schedule from max(lastCommit, lastShown), restore after crash, 24 h cap).
6. `Reports`, `CSVExporter` (+ tests: exact CSV strings for a fixture month, quoting, `;` delimiter, decimal style, totals, empty scope, filename).
7. App target: `AppModel`, `ActivationController`, `StatusItemController`, `CheckInPanelController`, system events, login item, main menu.
8. `CheckInView` + `ProjectField` + `TimeField` + `ProjectList` + `TodayListView`/`TotalField` with full keyboard model (§6.4), commit flow and total editing (§6.5).
9. Reports window, Settings window, Export sheet, pause submenu with custom duration.
10. `--seed-demo` launch argument: creates 6 projects and 90 days of plausible data into a separate DB path (`hypertime-demo.sqlite`), used for screenshots and design QA.
11. Manual verification checklist (below) executed and recorded in `docs/DECISIONS.md` with any deviations.

Manual acceptance checklist (Phase 1):
- [ ] R-08: with TextEdit focused, wait for the check-in timer (set interval to 1 min for the test): popup appears, TextEdit keeps keyboard focus, typing goes to TextEdit.
- [ ] R-10: Cmd+Tab to Hypertime: popup appears with project field focused and text selected; typing filters; ↑/↓ move; Tab reaches time field; Enter commits; popup hides; TextEdit is frontmost again (R-09).
- [ ] R-09: click into a passive popup from Safari, press Esc → Safari frontmost again.
- [ ] D-08/D-13: with interval set to 1 min, wait for the check-in: time field shows ~1:00 and ticks; plain Enter adds it to the project (today list total grows by that amount, pending resets to 0:00). Repeat, edit the field to `0:20` before Enter → only 20 s added. Dismiss a check-in with Esc → it returns one interval later with the larger pending amount.
- [ ] D-14: passive popup hides by itself after 20 s while TextEdit keeps focus; hovering it cancels the auto-hide; the bucket kept counting (next popup shows the larger amount). Close (Esc) also keeps the bucket.
- [ ] R-04 Discard: with 5 min pending, press Discard → popup hides, focus returns, next popup starts from 0:00, today's total did not grow.
- [ ] R-17: edit a total in the popup's today list (`2h`, then `+15m`) → Reports Day view shows the same numbers; editing the current project's total first folds in pending.
- [ ] R-06/R-07: type "new thing" → "Create" row highlighted → Enter creates the project and starts tracking it.
- [ ] R-12/D-06: set the Mac clock across midnight (or use `--seed-demo` + TestClock tests) — day split verified in tests; manually verify counter keeps running across the panel being hidden.
- [ ] R-14: pause 15 m → icon shows paused, no check-ins, menu shows "Resume"; "Until 07:00" computes the right date; auto-resume shows popup.
- [ ] A-01: close the lid / lock screen for 3 min → no time accrued, popup shown on unlock.
- [ ] R-15: quit → relaunch → idle with last project preselected, no time accrued while quit.
- [ ] R-16: login item toggles and survives relaunch (app copied to /Applications).
- [ ] R-17/R-18: edit yesterday's total in Reports Day view; navigate week/month/year; values match.
- [ ] R-19: export month/year/range; open in Numbers and Excel; totals correct.
- [ ] Cmd+C/V work in fields; Reduce Transparency on → panel still readable.
- [ ] Multiple displays: popup appears under the status item on the display that has the menu bar.

Deliverable: a working, ugly app. Tag `v0.1-backbone`.

### Phase 2 — UI per design handoff (2–3 days, starts when the design handoff is available)
Input: the handoff described in `DESIGN_BRIEF.md` §7 (artboards, tokens JSON, assets, motion notes).
1. Create `Views/Components/DesignTokens.swift` from `tokens.json` (colors as `Color`/`NSColor` with light/dark variants, radii, spacing, typography, materials, shadows, durations/curves). No literal colors or sizes in views; everything references tokens.
2. `GlassBackground` component: `NSVisualEffectView` (material and blending from tokens) + optional tint layer + inner highlight stroke + shadow, with an automatic solid fallback when `NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency` is true. Used by the panel, the reports window content, popovers and the settings window.
3. Rebuild `CheckInView`, `ProjectList` (with highlighted match characters), `TimeField` (validation state), buttons, pause menu/popover, empty/idle/paused states exactly as designed; keep the view models untouched. Focus rings and keyboard states must match the design's focus specs.
4. Reports, Export sheet, Settings per artboards. Menu bar icons from the handoff (template images @1x/@2x), app icon.
5. Motion: panel appear/disappear, list filtering, live counter digit changes, pause state transitions — per the brief's motion table; all respect `accessibilityDisplayShouldReduceMotion`.
6. Light/dark, increased contrast, reduce transparency, large text: verify with screenshots of every screen in every mode; store them in `docs/screenshots/` for review.
7. Design QA pass with `--seed-demo`, fix drift versus artboards; record intentional deviations in `docs/DECISIONS.md`.

Acceptance: every artboard has a matching screenshot; Phase 1 checklist re-run and green; no view contains literal colors/sizes.

### Phase 3 — Hardening & packaging (1–2 days)
1. Crash and edge cases: DB missing/corrupt (recreate with backup copy), time zone change while tracking, daylight saving transitions, clock set backwards (negative delta → treat as gap), 0-interval check-in, very long project names, hundreds of projects (list virtualization), deleting the currently tracked project (engine → idle).
2. Performance: launch < 300 ms to status item; tick cost negligible; reports for a year with 50 projects < 50 ms.
3. Signing/notarization script (Developer ID if available; otherwise ad-hoc with instructions), DMG or zip via `scripts/release.sh`. Sparkle updates are out of scope.
4. `README.md` user docs: install, first run, keyboard cheatsheet, time formats, CSV layout.
5. Backend readiness note: `change_log` format and how a sync adapter would consume it (no implementation).

---

## 8. Testing strategy
- `swift test` covers all of `HypertimeCore`; target ≥ 90 % line coverage in `TimeParser`, `TrackingEngine`, `CSVExporter`, `Period`.
- Engine tests always use `TestClock` and `Store.inMemory`. Never sleep in tests.
- App target has no unit tests in Phase 1; behavior is verified by the manual checklist. In Phase 3 add XCUITest-free smoke tests via `--seed-demo --screenshot <dir>` (renders each window to PNG headlessly) if time permits.
- Every bug found during manual QA gets a core-level regression test where possible.

## 9. Conventions
- Swift 6 strict concurrency where feasible; `@MainActor` on engine, view models, controllers. `Store` is `Sendable` and internally serialized by GRDB.
- No force unwraps outside tests. Errors surface to the user via a non-modal inline message in the relevant view, never `NSAlert` for routine cases.
- Commit messages: `core:`, `app:`, `ui:`, `docs:`, `build:` prefixes.
- Log with `os.Logger` subsystem `com.hypertime.app`, categories `engine`, `panel`, `store`.

## 10. Open questions

None. All questions were answered on 2026-09-07; see `DECISIONS.md`. New questions raised
during the build go there with the default that was applied.

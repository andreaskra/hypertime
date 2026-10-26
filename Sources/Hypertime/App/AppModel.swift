import CoreGraphics
import Foundation
import HypertimeCore

/// Wall-clock time for the app. The calendar follows the week-start setting.
struct AppClock: Clock {
    let settings: Settings

    func now() -> Date { Date() }

    var timeZone: TimeZone { .autoupdatingCurrent }

    var calendar: Calendar {
        var c = Calendar.autoupdatingCurrent
        c.timeZone = .autoupdatingCurrent
        c.firstWeekday = settings.weekStart.calendarIndex
        c.minimumDaysInFirstWeek = 4
        return c
    }
}

/// Single owner of everything below the UI. Controllers and view models talk to this.
@MainActor
final class AppModel {
    let settings: Settings
    let clock: Clock
    let store: Store
    let engine: TrackingEngine
    let parser = TimeParser()
    let formatter = TimeFormatter()
    let pauseScheduler = PauseScheduler()
    let systemLoadSource: SystemLoadSource
    let isDemo: Bool

    private var timer: Timer?
    private var eventTask: Task<Void, Never>?

    /// Set by the app delegate.
    var onCheckInDue: (() -> Void)?
    var onPauseEnded: (() -> Void)?
    var onTick: (() -> Void)?
    var onStatusChanged: (() -> Void)?
    var onDataChanged: (() -> Void)?
    var onTaskTimerExpired: ((UUID) -> Void)?
    var onSystemLoad: ((SystemLoad) -> Void)?

    /// The machine's own figures, refreshed on the same heartbeat as everything else.
    ///
    /// Sampled whether or not the popup is open: processor usage only exists as a difference
    /// between two reads, so a source that is only read when the popup opens reports nothing
    /// the first time every time. Three counter reads a second cost nothing measurable.
    private(set) var systemLoad = SystemLoad()

    init(arguments: [String] = CommandLine.arguments) throws {
        isDemo = arguments.contains("--seed-demo") || arguments.contains("--screenshots")
        let isSelfTest = arguments.contains("--self-test") || arguments.contains("--screenshots")
        settings = isSelfTest ? Settings.ephemeral(name: "self-test") : Settings()
        let clock = AppClock(settings: settings)
        self.clock = clock
        let path: String
        if isSelfTest {
            path = NSTemporaryDirectory() + "hypertime-self-test-\(UUID().uuidString).sqlite"
        } else {
            path = Store.defaultPath(filename: isDemo ? "hypertime-demo.sqlite" : "hypertime.sqlite")
        }
        store = try Store(path: path, clock: clock)
        engine = TrackingEngine(store: store, clock: clock, settings: settings)
        systemLoadSource = MachSystemLoadSource(clock: clock)
        systemLoadSource.prime()

        if isDemo {
            try DemoData.seed(store: store, clock: clock)
        }
        engine.restore()
        Log.app.info("Started (demo: \(self.isDemo, privacy: .public)) db: \(self.store.path, privacy: .public)")
    }

    // MARK: - Lifecycle

    func start() {
        // Housekeeping that must happen every launch but not before the UI is up.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            try? self.store.pruneChangeLog()
            try? self.store.pruneSlices()
            self.refreshColorSlots()
            LoginItemController.synchronise(settings: self.settings)
        }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.engine.tick()
                self.engine.checkIdle(systemIdleSeconds: Self.systemIdleSeconds())
                self.sampleSystemLoad()
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        let events = engine.events
        eventTask = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                switch event {
                case .checkInDue: self.onCheckInDue?()
                case .pauseEnded: self.onPauseEnded?()
                case .tick: self.onTick?()
                case .statusChanged: self.onStatusChanged?(); self.onDataChanged?()
                case .dataChanged: self.refreshColorSlots(); self.onDataChanged?()
                case .tasksChanged: self.onDataChanged?()
                case .taskTimerExpired(let id): self.onTaskTimerExpired?(id)
                }
            }
        }
    }

    /// Primes the processor counters at launch so the first popup is not reporting 0 %,
    /// and refreshes everything on each heartbeat after that.
    func sampleSystemLoad() {
        let sample = systemLoadSource.sample()
        guard sample != systemLoad else { return }
        systemLoad = sample
        onSystemLoad?(sample)
    }

    func shutDown() {
        timer?.invalidate()
        timer = nil
        engine.stop()
        engine.finishEvents()
        eventTask?.cancel()
    }

    // MARK: - Convenience

    /// Seconds since the Mac last saw any human input. Reads a timestamp the window server
    /// already keeps — no input monitoring, no permission prompt.
    static func systemIdleSeconds() -> Seconds {
        guard let anyEvent = CGEventType(rawValue: ~0) else { return 0 }
        let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyEvent)
        return seconds.isFinite && seconds > 0 ? Int(seconds) : 0
    }

    var reportBuilder: ReportBuilder {
        ReportBuilder(store: store, engine: engine, clock: clock, weekStart: settings.weekStart)
    }

    var exporter: CSVExporter { CSVExporter(store: store, clock: clock) }

    var today: LocalDate { LocalDate(clock.now(), calendar: clock.calendar) }

    var currentProject: Project? {
        guard let id = engine.currentProjectID else { return nil }
        return try? store.project(id: id)
    }

    // MARK: - Tasks

    /// A project's permanent place in the categorical palette (TLD-07), or the neutral
    /// "Other" slot once the palette runs out.
    ///
    /// Cached: the chart asks this once per segment per frame, and a database read per bar is
    /// not what the colour of a bar should cost.
    func colorSlot(for project: UUID) -> Int {
        if let slot = colorSlots[project] { return slot }
        refreshColorSlots()
        return colorSlots[project] ?? Tokens.Series.maxSlots
    }

    private var colorSlots: [UUID: Int] = [:]

    func refreshColorSlots() {
        var slots: [UUID: Int] = [:]
        for project in (try? store.projects(includeArchived: true)) ?? [] {
            let slot = project.colorSlot ?? Tokens.Series.maxSlots
            slots[project.id] = slot < Tokens.Series.maxSlots ? slot : Tokens.Series.maxSlots
        }
        colorSlots = slots
    }

    func slices(since: Date) -> [Slice] {
        (try? store.slices(from: since, to: clock.now().addingTimeInterval(Timeline.grain))) ?? []
    }

    func projectName(_ id: UUID) -> String? { (try? store.project(id: id))??.name }

    /// "14:20–14:30", in the user's own clock format, and "yesterday 23:50–00:00" when the
    /// bracket is on the other side of midnight — a 24-hour window spans two days, so a bare
    /// clock time names two moments and picks neither.
    func clockRange(from: Date, to: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = clock.calendar
        formatter.timeZone = clock.timeZone
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("j:mm")
        let span = formatter.string(from: from) + "–" + formatter.string(from: to)
        let day = LocalDate(from, calendar: clock.calendar)
        return day == today ? span : "yesterday " + span
    }

    func openTasks() -> [TaskItem] { (try? store.tasks()) ?? [] }

    func task(_ id: UUID) -> TaskItem? { try? store.task(id: id) }

    /// Tasks with time inside a day, keyed by project, for the indented breakdown rows.
    func taskBreakdown(for day: LocalDate) -> [UUID: [(task: TaskItem, seconds: Seconds)]] {
        let totals = (try? store.taskTotals(in: day...day)) ?? [:]
        guard !totals.isEmpty else { return [:] }
        let all = (try? store.tasks(includeCompleted: true)) ?? []
        var result: [UUID: [(TaskItem, Seconds)]] = [:]
        for task in all {
            var seconds = totals[task.id] ?? 0
            if task.id == engine.activeTaskID, day == today {
                seconds = engine.liveTaskSeconds(task.id)
            }
            guard seconds > 0 else { continue }
            result[task.projectID, default: []].append((task, seconds))
        }
        return result.mapValues { $0.sorted { $0.1 > $1.1 } }
    }

    @discardableResult
    func createTask(title: String, projectName: String) -> TaskItem? {
        let name = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        // Fall back to whatever is being tracked, then to the most recent project, so a task
        // typed before any project is named still has somewhere to live.
        let project = name.isEmpty
            ? (currentProject ?? projects().first)
            : try? store.findOrCreateProject(named: name)
        guard let project else { return nil }
        return try? store.createTask(projectID: project.id, title: title)
    }

    func projects() -> [Project] {
        (try? store.projects()) ?? []
    }

    func todayRows() -> [ReportRow] { rows(for: today) }

    func rows(for day: LocalDate) -> [ReportRow] {
        (try? reportBuilder.report(for: .day(day)).rows) ?? []
    }

    func day(_ day: LocalDate, offsetBy delta: Int) -> LocalDate {
        day.adding(days: delta, calendar: clock.calendar)
    }

    /// "Mon 7 Oct" — the popup's label for a day that is not today.
    func dayLabel(_ day: LocalDate) -> String {
        Period.day(day).shortTitle(calendar: clock.calendar, weekStart: settings.weekStart)
    }

    func monthGrid(for month: LocalDate) -> [[LocalDate?]] {
        Period.monthGrid(containing: month, calendar: clock.calendar, weekStart: settings.weekStart)
    }

    var weekdayInitials: [String] {
        Period.weekdayInitials(calendar: clock.calendar, weekStart: settings.weekStart)
    }

    func monthTitle(_ month: LocalDate) -> String {
        Period.month(year: month.year, month: month.month)
            .title(calendar: clock.calendar, weekStart: settings.weekStart)
    }

    func daysWithTime(inMonthOf day: LocalDate) -> Set<LocalDate> {
        let month = Period.month(year: day.year, month: day.month)
        let range = month.range(calendar: clock.calendar, weekStart: settings.weekStart)
        return (try? store.daysWithTime(in: range)) ?? []
    }

    func liveSeconds(project: UUID, day: LocalDate) -> Seconds {
        (try? engine.liveSeconds(project: project, day: day)) ?? 0
    }

    /// Total tracked today across all projects, including pending time.
    func todayTotal() -> Seconds {
        todayRows().reduce(0) { $0 + $1.seconds }
    }

    func display(_ seconds: Seconds) -> String {
        formatter.string(seconds, style: settings.timeDisplayStyle)
    }

    // MARK: - Commands

    /// Commit flow (§6.5). Returns false when the input is not usable.
    @discardableResult
    func commit(name: String, timeText: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let seconds = try? parser.parseAbsolute(timeText) else { return false }
        guard let project = try? store.findOrCreateProject(named: trimmed) else { return false }
        engine.commit(projectID: project.id, seconds: seconds)
        Log.engine.info("Committed \(seconds)s to \(project.name, privacy: .public)")
        return true
    }

    /// Total editing (§6.5). Absolute input sets, relative input adjusts.
    @discardableResult
    func editTotal(project: UUID, day: LocalDate, text: String) -> Bool {
        guard let parsed = try? parser.parse(text) else { return false }
        let seconds = parser.apply(parsed, to: liveSeconds(project: project, day: day))
        engine.setTotal(projectID: project, day: day, seconds: seconds)
        return true
    }

    /// Starts tracking a project without attributing any time to it — the header's play button.
    /// Goes through `commit` with zero seconds so the check-in clock restarts from now.
    @discardableResult
    func startTracking(name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let project = try? store.findOrCreateProject(named: trimmed) else { return false }
        engine.commit(projectID: project.id, seconds: 0)
        Log.engine.info("Started tracking \(project.name, privacy: .public)")
        return true
    }

    func pause(_ preset: PausePreset, customDuration: Seconds? = nil) {
        let until = pauseScheduler.until(preset,
                                        customDuration: customDuration,
                                        now: clock.now(),
                                        calendar: clock.calendar,
                                        morningHour: settings.morningHour)
        engine.pause(until: until, reason: .manual)
    }

    func statusSummary() -> String {
        switch engine.status {
        case .idle:
            return "Not tracking"
        case .tracking:
            let name = currentProject?.name ?? "—"
            return "Tracking: \(name) · \(formatter.string(engine.pendingSeconds, style: .clock))"
        case .paused(_, let until, _):
            let f = DateFormatter()
            f.calendar = clock.calendar
            f.timeZone = clock.timeZone
            f.dateFormat = until.timeIntervalSince(clock.now()) > 12 * 3600 ? "d MMM HH:mm" : "HH:mm"
            return "Paused until \(f.string(from: until))"
        }
    }
}

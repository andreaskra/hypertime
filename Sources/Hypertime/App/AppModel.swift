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
            LoginItemController.synchronise(settings: self.settings)
        }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.engine.tick() }
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
                case .dataChanged: self.onDataChanged?()
                case .tasksChanged: self.onDataChanged?()
                case .taskTimerExpired(let id): self.onTaskTimerExpired?(id)
                }
            }
        }
    }

    func shutDown() {
        timer?.invalidate()
        timer = nil
        engine.stop()
        engine.finishEvents()
        eventTask?.cancel()
    }

    // MARK: - Convenience

    var reportBuilder: ReportBuilder {
        ReportBuilder(store: store, engine: engine, clock: clock, weekStart: settings.weekStart)
    }

    var exporter: CSVExporter { CSVExporter(store: store, clock: clock) }

    var today: LocalDate { LocalDate(clock.now(), calendar: clock.calendar) }

    var currentProject: Project? {
        guard let id = engine.currentProjectID else { return nil }
        return try? store.project(id: id)
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

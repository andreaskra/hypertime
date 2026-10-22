import Foundation

public struct ReportRow: Identifiable, Sendable {
    public let project: Project
    public let seconds: Seconds
    public let perDay: [LocalDate: Seconds]

    public var id: UUID { project.id }

    public init(project: Project, seconds: Seconds, perDay: [LocalDate: Seconds]) {
        self.project = project
        self.seconds = seconds
        self.perDay = perDay
    }

    public func seconds(on day: LocalDate) -> Seconds { perDay[day] ?? 0 }
}

public struct Report: Sendable {
    public let period: Period
    public let days: [LocalDate]
    public let rows: [ReportRow]
    public let total: Seconds
    public let perDayTotal: [LocalDate: Seconds]

    public init(period: Period, days: [LocalDate], rows: [ReportRow], total: Seconds, perDayTotal: [LocalDate: Seconds]) {
        self.period = period
        self.days = days
        self.rows = rows
        self.total = total
        self.perDayTotal = perDayTotal
    }

    public func total(on day: LocalDate) -> Seconds { perDayTotal[day] ?? 0 }
    public var isEmpty: Bool { rows.isEmpty }
}

/// Aggregates stored entries (plus live pending time) for a period (§5.7).
@MainActor
public struct ReportBuilder {
    private let store: Store
    private let engine: TrackingEngine?
    private let clock: Clock
    private let weekStart: Weekday

    public init(store: Store, engine: TrackingEngine?, clock: Clock, weekStart: Weekday) {
        self.store = store
        self.engine = engine
        self.clock = clock
        self.weekStart = weekStart
    }

    public func report(for period: Period) throws -> Report {
        let calendar = clock.calendar
        let range = period.range(calendar: calendar, weekStart: weekStart)
        let days = LocalDate.days(in: range, calendar: calendar)
        let today = LocalDate(clock.now(), calendar: calendar)

        var perProject: [UUID: [LocalDate: Seconds]] = [:]
        for entry in try store.entries(in: range) where entry.seconds > 0 {
            perProject[entry.projectID, default: [:]][entry.day, default: 0] += entry.seconds
        }

        // Provisional pending time for the current project (D-13).
        if let pending = engine?.pending, pending.seconds > 0, range.contains(today) {
            perProject[pending.projectID, default: [:]][today, default: 0] += pending.seconds
        }

        // Seconds a running task has banked but not yet flushed (TD-01). Without this a
        // project's total stands still between flushes while its task visibly ticks.
        if let unflushed = engine?.unflushedTaskTime, range.contains(today) {
            perProject[unflushed.projectID, default: [:]][today, default: 0] += unflushed.seconds
        }

        // The current project is always listed, even with zero time.
        if let current = engine?.currentProjectID {
            perProject[current] = perProject[current] ?? [:]
        }

        var projectsByID: [UUID: Project] = [:]
        for project in try store.projects(includeArchived: true) { projectsByID[project.id] = project }

        var rows: [ReportRow] = []
        var perDayTotal: [LocalDate: Seconds] = [:]
        var total = 0

        for (projectID, perDay) in perProject {
            guard let project = projectsByID[projectID] else { continue }
            let capped = perDay.mapValues { min($0, secondsPerDay) }
            let sum = capped.values.reduce(0, +)
            rows.append(ReportRow(project: project, seconds: sum, perDay: capped))
            total += sum
            for (day, seconds) in capped { perDayTotal[day, default: 0] += seconds }
        }

        rows.sort { a, b in
            if a.seconds != b.seconds { return a.seconds > b.seconds }
            return a.project.name.localizedCaseInsensitiveCompare(b.project.name) == .orderedAscending
        }

        return Report(period: period, days: days, rows: rows, total: total, perDayTotal: perDayTotal)
    }

    /// Rows for the popup's "today" list: every project with time today, current project first-class.
    public func todayRows() throws -> [ReportRow] {
        let today = LocalDate(clock.now(), calendar: clock.calendar)
        return try report(for: .day(today)).rows
    }
}

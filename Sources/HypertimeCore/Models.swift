import Foundation

public typealias Seconds = Int

/// Maximum time that can be booked on one project on one day (A-04).
public let secondsPerDay: Seconds = 86_400

public enum Weekday: String, Codable, CaseIterable, Sendable {
    case sunday, monday

    /// `Calendar.firstWeekday` index.
    public var calendarIndex: Int {
        switch self {
        case .sunday: return 1
        case .monday: return 2
        }
    }
}

/// A calendar day, independent of time zones. Never store a `Date` for a day.
public struct LocalDate: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = c.year ?? 1970
        self.month = c.month ?? 1
        self.day = c.day ?? 1
    }

    public var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { isoString }

    public static func parse(_ iso: String) -> LocalDate? {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              (1...12).contains(m), (1...31).contains(d)
        else { return nil }
        return LocalDate(year: y, month: m, day: d)
    }

    public static func today(_ clock: Clock) -> LocalDate {
        LocalDate(clock.now(), calendar: clock.calendar)
    }

    public var dateComponents: DateComponents {
        DateComponents(year: year, month: month, day: day)
    }

    /// Midnight at the start of this day, in the calendar's time zone.
    /// Falls back to noon-based resolution on DST gaps (e.g. Brazil, where midnight can not exist).
    public func startOfDay(calendar: Calendar) -> Date {
        if let d = calendar.date(from: dateComponents) {
            return calendar.startOfDay(for: d)
        }
        var comps = dateComponents
        comps.hour = 12
        if let noon = calendar.date(from: comps) {
            return calendar.startOfDay(for: noon)
        }
        return Date(timeIntervalSince1970: 0)
    }

    public func adding(days: Int, calendar: Calendar) -> LocalDate {
        guard days != 0 else { return self }
        var comps = dateComponents
        comps.hour = 12                                   // avoid DST midnight gaps
        guard let base = calendar.date(from: comps),
              let moved = calendar.date(byAdding: .day, value: days, to: base)
        else { return self }
        return LocalDate(moved, calendar: calendar)
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }

    /// All days from `self` through `other`, inclusive.
    public static func days(in range: ClosedRange<LocalDate>, calendar: Calendar) -> [LocalDate] {
        var out: [LocalDate] = []
        var cursor = range.lowerBound
        while cursor <= range.upperBound {
            out.append(cursor)
            let next = cursor.adding(days: 1, calendar: calendar)
            if next <= cursor { break }                   // paranoia: never loop forever
            cursor = next
        }
        return out
    }
}

public struct Project: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var createdAt: Date
    public var lastUsedAt: Date?
    public var isArchived: Bool

    public init(id: UUID = UUID(), name: String, createdAt: Date, lastUsedAt: Date? = nil, isArchived: Bool = false) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.isArchived = isArchived
    }
}

public struct DayEntry: Hashable, Codable, Sendable {
    public var projectID: UUID
    public var day: LocalDate
    public var seconds: Seconds

    public init(projectID: UUID, day: LocalDate, seconds: Seconds) {
        self.projectID = projectID
        self.day = day
        self.seconds = seconds
    }
}

public enum PauseReason: String, Codable, Sendable {
    case manual, systemSleep, screenLock
}

public enum TrackingStatus: Equatable, Sendable {
    case idle
    case tracking(projectID: UUID, since: Date)
    case paused(projectID: UUID, until: Date, reason: PauseReason)

    public var isTracking: Bool { if case .tracking = self { return true }; return false }
    public var isPaused: Bool { if case .paused = self { return true }; return false }
    public var isIdle: Bool { if case .idle = self { return true }; return false }

    public var projectID: UUID? {
        switch self {
        case .idle: return nil
        case .tracking(let id, _): return id
        case .paused(let id, _, _): return id
        }
    }
}

/// Unattributed time accrued since the last commit (D-13).
public struct PendingTime: Equatable, Sendable {
    public var projectID: UUID
    public var seconds: Seconds
    public var since: Date

    public init(projectID: UUID, seconds: Seconds, since: Date) {
        self.projectID = projectID
        self.seconds = seconds
        self.since = since
    }
}

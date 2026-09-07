import Foundation

/// Every time read in the core goes through a `Clock` so tests can control "now".
/// Production code must never call `Date()` directly.
public protocol Clock: Sendable {
    func now() -> Date
    var timeZone: TimeZone { get }
    var calendar: Calendar { get }
}

/// Wall-clock time in the user's current time zone.
public struct SystemClock: Clock {
    /// First weekday used by the derived calendar (1 = Sunday, 2 = Monday).
    public let firstWeekday: Int

    public init(firstWeekday: Int = 2) {
        self.firstWeekday = firstWeekday
    }

    public init(weekStart: Weekday) {
        self.firstWeekday = weekStart.calendarIndex
    }

    public func now() -> Date { Date() }

    public var timeZone: TimeZone { .autoupdatingCurrent }

    public var calendar: Calendar {
        var c = Calendar.autoupdatingCurrent
        c.timeZone = .autoupdatingCurrent
        c.firstWeekday = firstWeekday
        c.minimumDaysInFirstWeek = 4          // ISO 8601 week numbering
        return c
    }
}

/// Deterministic clock for tests.
public final class TestClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date
    private var _timeZone: TimeZone
    private var _firstWeekday: Int

    public init(now: Date = Date(timeIntervalSince1970: 0),
                timeZone: TimeZone = TimeZone(identifier: "Europe/Vienna") ?? .gmt,
                firstWeekday: Int = 2) {
        self._now = now
        self._timeZone = timeZone
        self._firstWeekday = firstWeekday
    }

    public var current: Date {
        get { lock.withLock { _now } }
        set { lock.withLock { _now = newValue } }
    }

    public var timeZone: TimeZone {
        get { lock.withLock { _timeZone } }
        set { lock.withLock { _timeZone = newValue } }
    }

    public var firstWeekday: Int {
        get { lock.withLock { _firstWeekday } }
        set { lock.withLock { _firstWeekday = newValue } }
    }

    public func now() -> Date { current }

    public var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        c.firstWeekday = firstWeekday
        c.minimumDaysInFirstWeek = 4
        return c
    }

    public func advance(by interval: TimeInterval) {
        lock.withLock { _now = _now.addingTimeInterval(interval) }
    }

    /// Sets the clock to a specific local date/time in the clock's own time zone.
    public func set(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, second: Int = 0) {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute; comps.second = second
        if let date = calendar.date(from: comps) { current = date }
    }
}

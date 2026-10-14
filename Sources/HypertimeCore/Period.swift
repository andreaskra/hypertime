import Foundation

public enum PeriodKind: String, CaseIterable, Hashable, Sendable {
    case day, week, month, year
}

/// A navigable reporting period. Week numbering follows ISO 8601 (D-11); with a Sunday week
/// start the same "at least 4 days in the first week" rule is applied to Sunday-based weeks.
public enum Period: Hashable, Sendable {
    case day(LocalDate)
    case week(isoYear: Int, isoWeek: Int)
    case month(year: Int, month: Int)
    case year(Int)

    public var kind: PeriodKind {
        switch self {
        case .day: return .day
        case .week: return .week
        case .month: return .month
        case .year: return .year
        }
    }

    // MARK: Construction

    public static func containing(_ date: LocalDate, kind: PeriodKind, calendar: Calendar, weekStart: Weekday) -> Period {
        switch kind {
        case .day:
            return .day(date)
        case .week:
            let cal = weekCalendar(calendar, weekStart: weekStart)
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: noon(date, cal))
            return .week(isoYear: comps.yearForWeekOfYear ?? date.year, isoWeek: comps.weekOfYear ?? 1)
        case .month:
            return .month(year: date.year, month: date.month)
        case .year:
            return .year(date.year)
        }
    }

    /// The same period kind, seen from a different anchor day.
    public func sameKind(containing date: LocalDate, calendar: Calendar, weekStart: Weekday) -> Period {
        Period.containing(date, kind: kind, calendar: calendar, weekStart: weekStart)
    }

    // MARK: Range

    public func range(calendar: Calendar, weekStart: Weekday) -> ClosedRange<LocalDate> {
        switch self {
        case .day(let d):
            return d...d

        case .week(let isoYear, let isoWeek):
            let cal = Period.weekCalendar(calendar, weekStart: weekStart)
            var comps = DateComponents()
            comps.yearForWeekOfYear = isoYear
            comps.weekOfYear = isoWeek
            comps.weekday = weekStart.calendarIndex
            comps.hour = 12
            guard let start = cal.date(from: comps) else {
                let d = LocalDate(year: isoYear, month: 1, day: 1)
                return d...d
            }
            let first = LocalDate(start, calendar: cal)
            return first...first.adding(days: 6, calendar: cal)

        case .month(let year, let month):
            let first = LocalDate(year: year, month: month, day: 1)
            let nextMonth = month == 12
                ? LocalDate(year: year + 1, month: 1, day: 1)
                : LocalDate(year: year, month: month + 1, day: 1)
            return first...nextMonth.adding(days: -1, calendar: calendar)

        case .year(let y):
            return LocalDate(year: y, month: 1, day: 1)...LocalDate(year: y, month: 12, day: 31)
        }
    }

    public func days(calendar: Calendar, weekStart: Weekday) -> [LocalDate] {
        LocalDate.days(in: range(calendar: calendar, weekStart: weekStart), calendar: calendar)
    }

    public func contains(_ date: LocalDate, calendar: Calendar, weekStart: Weekday) -> Bool {
        range(calendar: calendar, weekStart: weekStart).contains(date)
    }

    // MARK: Navigation

    public func previous(calendar: Calendar, weekStart: Weekday) -> Period { shifted(by: -1, calendar: calendar, weekStart: weekStart) }
    public func next(calendar: Calendar, weekStart: Weekday) -> Period { shifted(by: 1, calendar: calendar, weekStart: weekStart) }

    public func shifted(by delta: Int, calendar: Calendar, weekStart: Weekday) -> Period {
        switch self {
        case .day(let d):
            return .day(d.adding(days: delta, calendar: calendar))

        case .week:
            let cal = Period.weekCalendar(calendar, weekStart: weekStart)
            let start = range(calendar: cal, weekStart: weekStart).lowerBound
            let moved = start.adding(days: 7 * delta, calendar: cal)
            return Period.containing(moved, kind: .week, calendar: cal, weekStart: weekStart)

        case .month(let year, let month):
            let total = year * 12 + (month - 1) + delta
            return .month(year: (total - total.modulo(12)) / 12, month: total.modulo(12) + 1)

        case .year(let y):
            return .year(y + delta)
        }
    }

    /// The month of `date` laid out as calendar weeks, padded with nil to whole rows. Used by
    /// the day picker; pure date maths so it is testable without a view.
    public static func monthGrid(containing date: LocalDate,
                                 calendar: Calendar,
                                 weekStart: Weekday) -> [[LocalDate?]] {
        let month = Period.month(year: date.year, month: date.month)
        let days = month.days(calendar: calendar, weekStart: weekStart)
        guard let first = days.first else { return [] }

        let cal = weekCalendar(calendar, weekStart: weekStart)
        let weekday = cal.component(.weekday, from: noon(first, cal))
        // How many blanks sit before the 1st, given where the week starts.
        let leading = (weekday - weekStart.calendarIndex + 7) % 7

        var cells: [LocalDate?] = Array(repeating: nil, count: leading) + days.map { Optional($0) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    /// Single-letter weekday headers in the order the grid uses them.
    public static func weekdayInitials(calendar: Calendar,
                                       weekStart: Weekday,
                                       locale: Locale = .autoupdatingCurrent) -> [String] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        let symbols = formatter.veryShortWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        let offset = weekStart.calendarIndex - 1
        return (0..<7).map { symbols[($0 + offset) % symbols.count] }
    }

    // MARK: Titles

    /// Display title, e.g. "Mon 7 Sep 2026", "Week 37 · 7–13 Sep 2026", "September 2026", "2026".
    public func title(calendar: Calendar, weekStart: Weekday, locale: Locale = .autoupdatingCurrent) -> String {
        let range = range(calendar: calendar, weekStart: weekStart)
        switch self {
        case .day(let d):
            return Period.format(d, "EEE d MMM yyyy", calendar: calendar, locale: locale)

        case .week(_, let isoWeek):
            let lo = range.lowerBound, hi = range.upperBound
            let tail: String
            if lo.month == hi.month && lo.year == hi.year {
                tail = "\(lo.day)–" + Period.format(hi, "d MMM yyyy", calendar: calendar, locale: locale)
            } else if lo.year == hi.year {
                tail = Period.format(lo, "d MMM", calendar: calendar, locale: locale) + "–"
                     + Period.format(hi, "d MMM yyyy", calendar: calendar, locale: locale)
            } else {
                tail = Period.format(lo, "d MMM yyyy", calendar: calendar, locale: locale) + "–"
                     + Period.format(hi, "d MMM yyyy", calendar: calendar, locale: locale)
            }
            return "Week \(isoWeek) · \(tail)"

        case .month:
            return Period.format(range.lowerBound, "LLLL yyyy", calendar: calendar, locale: locale)

        case .year(let y):
            return String(y)
        }
    }

    public func shortTitle(calendar: Calendar, weekStart: Weekday, locale: Locale = .autoupdatingCurrent) -> String {
        switch self {
        case .day(let d): return Period.format(d, "EEE d MMM", calendar: calendar, locale: locale)
        case .week(_, let w): return "W\(w)"
        case .month: return Period.format(range(calendar: calendar, weekStart: weekStart).lowerBound, "LLL yyyy", calendar: calendar, locale: locale)
        case .year(let y): return String(y)
        }
    }

    // MARK: Helpers

    static func format(_ date: LocalDate, _ template: String, calendar: Calendar, locale: Locale) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = locale
        f.timeZone = calendar.timeZone
        f.dateFormat = template
        return f.string(from: noon(date, calendar))
    }

    static func noon(_ date: LocalDate, _ calendar: Calendar) -> Date {
        var comps = date.dateComponents
        comps.hour = 12
        return calendar.date(from: comps) ?? date.startOfDay(calendar: calendar)
    }

    static func weekCalendar(_ calendar: Calendar, weekStart: Weekday) -> Calendar {
        var c = calendar
        c.firstWeekday = weekStart.calendarIndex
        c.minimumDaysInFirstWeek = 4
        return c
    }
}

extension Int {
    /// Euclidean modulo: always in `0..<m` even for negative values.
    func modulo(_ m: Int) -> Int {
        let r = self % m
        return r < 0 ? r + m : r
    }
}

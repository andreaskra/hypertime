import Foundation
import Testing
@testable import HypertimeCore

private let clock = TestClock()             // Europe/Vienna, Monday start
private var cal: Calendar { clock.calendar }
private func d(_ iso: String) -> LocalDate { LocalDate.parse(iso)! }

@Suite("LocalDate")
struct LocalDateTests {

    @Test("iso round trip")
    func iso() {
        #expect(d("2026-09-07").isoString == "2026-09-07")
        #expect(LocalDate(year: 2026, month: 1, day: 5).isoString == "2026-01-05")
        #expect(LocalDate.parse("2026-9-7") == nil)
        #expect(LocalDate.parse("nope") == nil)
        #expect(LocalDate.parse("2026-13-01") == nil)
    }

    @Test("ordering")
    func ordering() {
        #expect(d("2026-01-31") < d("2026-02-01"))
        #expect(d("2025-12-31") < d("2026-01-01"))
        #expect(!(d("2026-02-01") < d("2026-02-01")))
    }

    @Test("adding days crosses months, years and DST")
    func adding() {
        #expect(d("2026-01-31").adding(days: 1, calendar: cal) == d("2026-02-01"))
        #expect(d("2026-12-31").adding(days: 1, calendar: cal) == d("2027-01-01"))
        #expect(d("2026-03-01").adding(days: -1, calendar: cal) == d("2026-02-28"))
        #expect(d("2024-03-01").adding(days: -1, calendar: cal) == d("2024-02-29"))   // leap year
        // DST switch in Europe/Vienna: 2026-03-29 (23 h day), 2026-10-25 (25 h day)
        #expect(d("2026-03-28").adding(days: 1, calendar: cal) == d("2026-03-29"))
        #expect(d("2026-03-29").adding(days: 1, calendar: cal) == d("2026-03-30"))
        #expect(d("2026-10-25").adding(days: 1, calendar: cal) == d("2026-10-26"))
    }

    @Test("startOfDay is local midnight, DST aware")
    func startOfDay() {
        let start = d("2026-03-29").startOfDay(calendar: cal)
        #expect(LocalDate(start, calendar: cal) == d("2026-03-29"))
        let next = d("2026-03-30").startOfDay(calendar: cal)
        #expect(next.timeIntervalSince(start) == 23 * 3600)                            // short day
        let longStart = d("2026-10-25").startOfDay(calendar: cal)
        let longNext = d("2026-10-26").startOfDay(calendar: cal)
        #expect(longNext.timeIntervalSince(longStart) == 25 * 3600)                    // long day
    }

    @Test("days(in:) enumerates inclusive ranges")
    func days() {
        #expect(LocalDate.days(in: d("2026-09-01")...d("2026-09-30"), calendar: cal).count == 30)
        #expect(LocalDate.days(in: d("2026-09-07")...d("2026-09-07"), calendar: cal) == [d("2026-09-07")])
        #expect(LocalDate.days(in: d("2026-02-01")...d("2026-03-01"), calendar: cal).count == 29)
    }
}

@Suite("Period")
struct PeriodTests {

    @Test("day range and navigation")
    func day() {
        let p = Period.day(d("2026-09-07"))
        #expect(p.range(calendar: cal, weekStart: .monday) == d("2026-09-07")...d("2026-09-07"))
        #expect(p.next(calendar: cal, weekStart: .monday) == .day(d("2026-09-08")))
        #expect(p.previous(calendar: cal, weekStart: .monday) == .day(d("2026-09-06")))
    }

    @Test("ISO week containing a date")
    func weekContaining() {
        #expect(Period.containing(d("2026-09-07"), kind: .week, calendar: cal, weekStart: .monday)
                == .week(isoYear: 2026, isoWeek: 37))
        #expect(Period.containing(d("2026-09-13"), kind: .week, calendar: cal, weekStart: .monday)
                == .week(isoYear: 2026, isoWeek: 37))
        // 1 Jan 2026 is a Thursday → ISO week 1 of 2026, starting 29 Dec 2025
        #expect(Period.containing(d("2026-01-01"), kind: .week, calendar: cal, weekStart: .monday)
                == .week(isoYear: 2026, isoWeek: 1))
        // 1 Jan 2021 is a Friday → ISO week 53 of 2020
        #expect(Period.containing(d("2021-01-01"), kind: .week, calendar: cal, weekStart: .monday)
                == .week(isoYear: 2020, isoWeek: 53))
    }

    @Test("week ranges across year boundaries")
    func weekRange() {
        #expect(Period.week(isoYear: 2026, isoWeek: 37).range(calendar: cal, weekStart: .monday)
                == d("2026-09-07")...d("2026-09-13"))
        #expect(Period.week(isoYear: 2026, isoWeek: 1).range(calendar: cal, weekStart: .monday)
                == d("2025-12-29")...d("2026-01-04"))
        #expect(Period.week(isoYear: 2020, isoWeek: 53).range(calendar: cal, weekStart: .monday)
                == d("2020-12-28")...d("2021-01-03"))
    }

    @Test("week navigation wraps the year")
    func weekNav() {
        let last = Period.containing(d("2026-12-31"), kind: .week, calendar: cal, weekStart: .monday)
        #expect(last == .week(isoYear: 2026, isoWeek: 53))
        #expect(last.next(calendar: cal, weekStart: .monday) == .week(isoYear: 2027, isoWeek: 1))
        #expect(Period.week(isoYear: 2026, isoWeek: 1).previous(calendar: cal, weekStart: .monday)
                == .week(isoYear: 2025, isoWeek: 52))
    }

    @Test("Sunday week start shifts the range")
    func sundayWeeks() {
        let p = Period.containing(d("2026-09-07"), kind: .week, calendar: cal, weekStart: .sunday)
        let range = p.range(calendar: cal, weekStart: .sunday)
        #expect(range == d("2026-09-06")...d("2026-09-12"))
        #expect(range.lowerBound.adding(days: 6, calendar: cal) == range.upperBound)
    }

    @Test("week that spans a DST change still has 7 days")
    func dstWeek() {
        let p = Period.containing(d("2026-03-29"), kind: .week, calendar: cal, weekStart: .monday)
        #expect(p.days(calendar: cal, weekStart: .monday).count == 7)
        let autumn = Period.containing(d("2026-10-25"), kind: .week, calendar: cal, weekStart: .monday)
        #expect(autumn.days(calendar: cal, weekStart: .monday).count == 7)
    }

    @Test("month and year ranges")
    func monthYear() {
        #expect(Period.month(year: 2026, month: 9).range(calendar: cal, weekStart: .monday)
                == d("2026-09-01")...d("2026-09-30"))
        #expect(Period.month(year: 2026, month: 2).range(calendar: cal, weekStart: .monday)
                == d("2026-02-01")...d("2026-02-28"))
        #expect(Period.month(year: 2024, month: 2).range(calendar: cal, weekStart: .monday)
                == d("2024-02-01")...d("2024-02-29"))
        #expect(Period.month(year: 2026, month: 12).range(calendar: cal, weekStart: .monday)
                == d("2026-12-01")...d("2026-12-31"))
        #expect(Period.year(2026).range(calendar: cal, weekStart: .monday)
                == d("2026-01-01")...d("2026-12-31"))
        #expect(Period.year(2026).days(calendar: cal, weekStart: .monday).count == 365)
    }

    @Test("month navigation wraps the year in both directions")
    func monthNav() {
        #expect(Period.month(year: 2026, month: 12).next(calendar: cal, weekStart: .monday) == .month(year: 2027, month: 1))
        #expect(Period.month(year: 2026, month: 1).previous(calendar: cal, weekStart: .monday) == .month(year: 2025, month: 12))
        #expect(Period.month(year: 2026, month: 3).shifted(by: -14, calendar: cal, weekStart: .monday) == .month(year: 2025, month: 1))
        #expect(Period.year(2026).next(calendar: cal, weekStart: .monday) == .year(2027))
    }

    @Test("titles")
    func titles() {
        let locale = Locale(identifier: "en_GB")
        #expect(Period.day(d("2026-09-07")).title(calendar: cal, weekStart: .monday, locale: locale) == "Mon 7 Sep 2026")
        #expect(Period.week(isoYear: 2026, isoWeek: 37).title(calendar: cal, weekStart: .monday, locale: locale)
                == "Week 37 · 7–13 Sep 2026")
        #expect(Period.month(year: 2026, month: 9).title(calendar: cal, weekStart: .monday, locale: locale) == "September 2026")
        #expect(Period.year(2026).title(calendar: cal, weekStart: .monday, locale: locale) == "2026")
        #expect(Period.week(isoYear: 2026, isoWeek: 1).title(calendar: cal, weekStart: .monday, locale: locale)
                == "Week 1 · 29 Dec 2025–4 Jan 2026")
    }

    @Test("kind and sameKind")
    func kinds() {
        #expect(Period.day(d("2026-09-07")).kind == .day)
        #expect(Period.week(isoYear: 2026, isoWeek: 37).kind == .week)
        #expect(Period.month(year: 2026, month: 9).kind == .month)
        #expect(Period.year(2026).kind == .year)
        #expect(Period.containing(d("2026-09-07"), kind: .day, calendar: cal, weekStart: .monday) == .day(d("2026-09-07")))
        #expect(Period.containing(d("2026-09-07"), kind: .month, calendar: cal, weekStart: .monday) == .month(year: 2026, month: 9))
        #expect(Period.containing(d("2026-09-07"), kind: .year, calendar: cal, weekStart: .monday) == .year(2026))
        #expect(Period.month(year: 2026, month: 9).sameKind(containing: d("2026-11-02"), calendar: cal, weekStart: .monday)
                == .month(year: 2026, month: 11))
    }

    @Test("short titles and a month-spanning week title")
    func shortTitles() {
        let locale = Locale(identifier: "en_GB")
        #expect(Period.day(d("2026-09-07")).shortTitle(calendar: cal, weekStart: .monday, locale: locale) == "Mon 7 Sep")
        #expect(Period.week(isoYear: 2026, isoWeek: 37).shortTitle(calendar: cal, weekStart: .monday, locale: locale) == "W37")
        #expect(Period.month(year: 2026, month: 9).shortTitle(calendar: cal, weekStart: .monday, locale: locale) == "Sep 2026")
        #expect(Period.year(2026).shortTitle(calendar: cal, weekStart: .monday, locale: locale) == "2026")
        // A week spanning two months inside one year.
        #expect(Period.week(isoYear: 2026, isoWeek: 40).title(calendar: cal, weekStart: .monday, locale: locale)
                == "Week 40 · 28 Sep–4 Oct 2026")
    }

    @Test("contains")
    func contains() {
        let p = Period.month(year: 2026, month: 9)
        #expect(p.contains(d("2026-09-30"), calendar: cal, weekStart: .monday))
        #expect(!p.contains(d("2026-10-01"), calendar: cal, weekStart: .monday))
    }
}

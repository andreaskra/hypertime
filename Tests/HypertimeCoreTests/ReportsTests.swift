import Foundation
import Testing
@testable import HypertimeCore

private func d(_ iso: String) -> LocalDate { LocalDate.parse(iso)! }

@MainActor
@Suite("Reports")
struct ReportsTests {
    let clock = TestClock()
    let store: Store
    let settings: Settings
    let engine: TrackingEngine
    let alpha: Project
    let beta: Project

    init() throws {
        clock.set(year: 2026, month: 9, day: 9, hour: 12)          // Wednesday
        store = try Store.inMemory(clock: clock)
        settings = Settings.ephemeral()
        engine = TrackingEngine(store: store, clock: clock, settings: settings)
        alpha = try store.findOrCreateProject(named: "Alpha")
        beta = try store.findOrCreateProject(named: "Beta")
        try store.setSeconds(project: alpha.id, day: d("2026-09-07"), 3600)
        try store.setSeconds(project: alpha.id, day: d("2026-09-09"), 1800)
        try store.setSeconds(project: beta.id, day: d("2026-09-08"), 7200)
        try store.setSeconds(project: beta.id, day: d("2026-08-31"), 600)
    }

    func builder(engine: TrackingEngine? = nil) -> ReportBuilder {
        ReportBuilder(store: store, engine: engine, clock: clock, weekStart: .monday)
    }

    @Test("day report")
    func day() throws {
        let report = try builder().report(for: .day(d("2026-09-07")))
        #expect(report.days == [d("2026-09-07")])
        #expect(report.rows.map(\.project.name) == ["Alpha"])
        #expect(report.total == 3600)
        #expect(report.total(on: d("2026-09-07")) == 3600)
    }

    @Test("week report is sorted by time desc then name")
    func week() throws {
        let report = try builder().report(for: .week(isoYear: 2026, isoWeek: 37))
        #expect(report.days.count == 7)
        #expect(report.rows.map(\.project.name) == ["Beta", "Alpha"])
        #expect(report.rows[0].seconds == 7200)
        #expect(report.rows[1].seconds == 5400)
        #expect(report.total == 12600)
        #expect(report.rows[1].seconds(on: d("2026-09-09")) == 1800)
        #expect(report.perDayTotal[d("2026-09-08")] == 7200)
    }

    @Test("month and year scope the range")
    func monthYear() throws {
        #expect(try builder().report(for: .month(year: 2026, month: 9)).total == 12600)
        #expect(try builder().report(for: .month(year: 2026, month: 8)).total == 600)
        #expect(try builder().report(for: .year(2026)).total == 13200)
        #expect(try builder().report(for: .month(year: 2026, month: 7)).isEmpty)
    }

    @Test("pending time shows up live for the current project (D-13)")
    func pendingIsLive() throws {
        engine.start(projectID: alpha.id)
        for _ in 0..<120 { clock.advance(by: 1); engine.tick() }

        let withEngine = try builder(engine: engine).report(for: .day(d("2026-09-09")))
        #expect(withEngine.rows.first { $0.project.id == alpha.id }?.seconds == 1920)
        #expect(withEngine.total == 1920)

        let withoutEngine = try builder().report(for: .day(d("2026-09-09")))
        #expect(withoutEngine.total == 1800)
    }

    @Test("pending time does not leak into other days")
    func pendingScoped() throws {
        engine.start(projectID: alpha.id)
        for _ in 0..<60 { clock.advance(by: 1); engine.tick() }
        let yesterday = try builder(engine: engine).report(for: .day(d("2026-09-08")))
        #expect(yesterday.rows.first { $0.project.id == alpha.id }?.seconds ?? 0 == 0)
    }

    @Test("the current project is listed even with no time")
    func currentProjectAlwaysListed() throws {
        engine.start(projectID: beta.id)
        let report = try builder(engine: engine).report(for: .day(d("2026-09-07")))
        #expect(report.rows.map(\.project.name) == ["Alpha", "Beta"])
        #expect(report.rows.last?.seconds == 0)
    }

    @Test("today rows for the popup list")
    func todayRows() throws {
        engine.start(projectID: alpha.id)
        for _ in 0..<30 { clock.advance(by: 1); engine.tick() }
        let rows = try builder(engine: engine).todayRows()
        #expect(rows.map(\.project.name) == ["Alpha"])
        #expect(rows[0].seconds == 1830)
    }

    @Test("archived projects still report their historic time")
    func archived() throws {
        try store.setArchived(id: beta.id, true)
        let report = try builder().report(for: .month(year: 2026, month: 9))
        #expect(report.rows.map(\.project.name) == ["Beta", "Alpha"])
    }
}

@Suite("CSVExporter")
struct CSVExporterTests {
    let clock = TestClock()
    let store: Store
    let exporter: CSVExporter

    init() throws {
        clock.set(year: 2026, month: 2, day: 15, hour: 12)
        store = try Store.inMemory(clock: clock)
        exporter = CSVExporter(store: store, clock: clock)
    }

    func seedFebruary() throws {
        let a = try store.findOrCreateProject(named: "Alpha")
        let b = try store.findOrCreateProject(named: "Beta, Inc")
        try store.setSeconds(project: a.id, day: d("2026-02-01"), 3600)
        try store.setSeconds(project: b.id, day: d("2026-02-01"), 1800)
        try store.setSeconds(project: a.id, day: d("2026-02-03"), 5415)
    }

    @Test("exact CSV for a fixture month")
    func fixtureMonth() throws {
        try seedFebruary()
        var options = CSVOptions()
        options.includeBOM = false
        let csv = try exporter.csv(scope: .range(d("2026-02-01")...d("2026-02-03")), options: options)
        #expect(csv == """
            Date,Alpha,"Beta, Inc",Total\r
            2026-02-01,1:00:00,0:30:00,1:30:00\r
            2026-02-02,0:00:00,0:00:00,0:00:00\r
            2026-02-03,1:30:15,0:00:00,1:30:15\r
            Total,2:30:15,0:30:00,3:00:15\r\n
            """)
    }

    @Test("BOM and full-month range")
    func fullMonth() throws {
        try seedFebruary()
        let csv = try exporter.csv(scope: .month(year: 2026, month: 2))
        #expect(csv.hasPrefix("\u{FEFF}Date,"))
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        #expect(lines.count == 1 + 28 + 1)                       // header + days + total
        #expect(lines.last?.hasPrefix("Total,") == true)
    }

    @Test("semicolon delimiter re-quotes the right fields")
    func semicolon() throws {
        try seedFebruary()
        var options = CSVOptions()
        options.includeBOM = false
        options.delimiter = ";"
        let csv = try exporter.csv(scope: .range(d("2026-02-01")...d("2026-02-01")), options: options)
        #expect(csv == """
            Date;Alpha;Beta, Inc;Total\r
            2026-02-01;1:00:00;0:30:00;1:30:00\r
            Total;1:00:00;0:30:00;1:30:00\r\n
            """)
    }

    @Test("decimal hours cell style with a comma separator")
    func decimalCells() throws {
        try seedFebruary()
        var options = CSVOptions()
        options.includeBOM = false
        options.cellStyle = .decimalHours
        options.decimalSeparator = ","
        options.delimiter = ";"
        let csv = try exporter.csv(scope: .range(d("2026-02-03")...d("2026-02-03")), options: options)
        #expect(csv == "Date;Alpha;Total\r\n2026-02-03;1,50;1,50\r\nTotal;1,50;1,50\r\n")
    }

    @Test("totals can be switched off")
    func withoutTotals() throws {
        try seedFebruary()
        var options = CSVOptions()
        options.includeBOM = false
        options.includeTotals = false
        let csv = try exporter.csv(scope: .range(d("2026-02-01")...d("2026-02-01")), options: options)
        #expect(csv == "Date,Alpha,\"Beta, Inc\"\r\n2026-02-01,1:00:00,0:30:00\r\n")
    }

    @Test("quotes inside project names are doubled")
    func quoting() throws {
        let p = try store.findOrCreateProject(named: "He said \"hi\"")
        try store.setSeconds(project: p.id, day: d("2026-02-01"), 60)
        var options = CSVOptions()
        options.includeBOM = false
        let csv = try exporter.csv(scope: .range(d("2026-02-01")...d("2026-02-01")), options: options)
        #expect(csv.hasPrefix("Date,\"He said \"\"hi\"\"\",Total\r\n"))
    }

    @Test("empty scope still emits every date")
    func emptyScope() throws {
        var options = CSVOptions()
        options.includeBOM = false
        let csv = try exporter.csv(scope: .range(d("2026-02-01")...d("2026-02-02")), options: options)
        #expect(csv == "Date,Total\r\n2026-02-01,0:00:00\r\n2026-02-02,0:00:00\r\nTotal,0:00:00\r\n")
    }

    @Test("suggested filenames")
    func filenames() {
        #expect(CSVExporter.suggestedFilename(scope: .month(year: 2026, month: 9)) == "Hypertime-2026-09.csv")
        #expect(CSVExporter.suggestedFilename(scope: .year(2026)) == "Hypertime-2026.csv")
        #expect(CSVExporter.suggestedFilename(scope: .range(d("2026-09-01")...d("2026-09-15")))
                == "Hypertime-2026-09-01_2026-09-15.csv")
    }
}

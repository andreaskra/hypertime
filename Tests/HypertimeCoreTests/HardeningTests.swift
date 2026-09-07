import Foundation
import Testing
@testable import HypertimeCore

private func d(_ iso: String) -> LocalDate { LocalDate.parse(iso)! }

private func temporaryPath(_ name: String = UUID().uuidString) -> String {
    NSTemporaryDirectory() + "hypertime-test-\(name).sqlite"
}

@Suite("Hardening — database")
struct StoreHardeningTests {

    @Test("a corrupt database is moved aside and recreated")
    func corruptDatabase() throws {
        let clock = TestClock()
        clock.set(year: 2026, month: 9, day: 7, hour: 12)
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        // A file that is not SQLite at all.
        try Data("this is not a database".utf8).write(to: URL(fileURLWithPath: path))

        let store = try Store(path: path, clock: clock)
        let quarantined = try #require(store.recoveredFromCorruption)
        defer { try? FileManager.default.removeItem(atPath: quarantined) }

        #expect(FileManager.default.fileExists(atPath: quarantined))
        #expect(quarantined.contains("corrupt-2026-09-07"))
        // The fresh database works.
        let project = try store.findOrCreateProject(named: "After recovery")
        try store.setSeconds(project: project.id, day: d("2026-09-07"), 60)
        #expect(try store.seconds(project: project.id, day: d("2026-09-07")) == 60)
    }

    @Test("a missing database file is simply created")
    func missingDatabase() throws {
        let clock = TestClock()
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try Store(path: path, clock: clock)
        #expect(store.recoveredFromCorruption == nil)
        #expect(try store.projects().isEmpty)
    }

    @Test("a missing parent directory is created")
    func missingDirectory() throws {
        let clock = TestClock()
        let directory = NSTemporaryDirectory() + "hypertime-test-\(UUID().uuidString)/nested"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let store = try Store(path: directory + "/db.sqlite", clock: clock)
        #expect(try store.projects().isEmpty)
    }

    @Test("very long project names are capped, not rejected")
    func longNames() throws {
        let clock = TestClock()
        let store = try Store.inMemory(clock: clock)
        let long = String(repeating: "ä", count: 500)
        let project = try store.findOrCreateProject(named: long)
        #expect(project.name.count == maxProjectNameLength)
        // Looking it up with the same over-long name finds the same project.
        #expect(try store.project(named: long)?.id == project.id)
        #expect(try store.findOrCreateProject(named: long).id == project.id)
    }

    @Test("hundreds of projects stay fast to rank")
    func manyProjects() throws {
        let clock = TestClock()
        let store = try Store.inMemory(clock: clock)
        for index in 0..<500 {
            _ = try store.findOrCreateProject(named: "Project \(index) · client \(index % 20)")
        }
        let projects = try store.projects()
        #expect(projects.count == 500)

        let started = Date()
        let ranked = FuzzyMatcher.rank("p4c", in: projects, key: \.name, recency: \.lastUsedAt)
        let elapsed = Date().timeIntervalSince(started)
        #expect(!ranked.isEmpty)
        #expect(elapsed < 0.1, "ranking 500 projects took \(elapsed)s")
    }
}

@MainActor
@Suite("Hardening — engine")
struct EngineHardeningTests {
    let clock = TestClock()
    let store: Store
    let settings: Settings
    let engine: TrackingEngine
    let alpha: Project

    init() throws {
        clock.set(year: 2026, month: 9, day: 7, hour: 9)
        store = try Store.inMemory(clock: clock)
        settings = Settings.ephemeral()
        engine = TrackingEngine(store: store, clock: clock, settings: settings)
        alpha = try store.findOrCreateProject(named: "Alpha")
    }

    func run(seconds: Int) {
        for _ in 0..<seconds { clock.advance(by: 1); engine.tick() }
    }

    @Test("deleting the tracked project stops tracking and drops its bucket")
    func deleteCurrentProject() throws {
        engine.start(projectID: alpha.id)
        run(seconds: 120)
        engine.projectDeleted(alpha.id)
        try store.deleteProject(id: alpha.id)

        #expect(engine.status == .idle)
        #expect(engine.currentProjectID == nil)
        #expect(engine.pending == nil)
        #expect(try store.projects(includeArchived: true).isEmpty)
        // Ticking after the deletion must not resurrect anything.
        run(seconds: 5)
        #expect(engine.pending == nil)
    }

    @Test("deleting another project leaves tracking alone")
    func deleteOtherProject() throws {
        let beta = try store.findOrCreateProject(named: "Beta")
        engine.start(projectID: alpha.id)
        run(seconds: 60)
        engine.projectDeleted(beta.id)
        #expect(engine.status.isTracking)
        #expect(engine.pending?.seconds == 60)
    }

    @Test("a time zone change while tracking does not lose or invent time")
    func timeZoneChange() throws {
        engine.start(projectID: alpha.id)
        run(seconds: 60)
        clock.timeZone = TimeZone(identifier: "Pacific/Auckland") ?? .gmt   // +10 h from Vienna
        run(seconds: 60)
        // The accrual is wall-clock, so it keeps counting; the day it lands on may change.
        #expect(engine.pending?.seconds ?? 0 >= 60)
        let today = engine.today
        let stored = try store.seconds(project: alpha.id, day: today)
        let live = try engine.liveSeconds(project: alpha.id, day: today)
        #expect(live >= stored)
        #expect(live <= 120)
    }

    @Test("accrual across a DST change stays wall-clock correct")
    func dstTransition() throws {
        // Europe/Vienna moves 02:00 → 03:00 on 29 March 2026.
        clock.set(year: 2026, month: 3, day: 29, hour: 1, minute: 59, second: 30)
        engine.start(projectID: alpha.id)
        run(seconds: 60)
        #expect(engine.pending?.seconds == 60)
        #expect(engine.today == d("2026-03-29"))

        // …and back on 25 October 2026, when 03:00 becomes 02:00.
        clock.set(year: 2026, month: 10, day: 25, hour: 2, minute: 59, second: 30)
        engine.tick()                                    // absorbs the clock jump as a gap (A-01)
        engine.discardPending()
        run(seconds: 60)
        #expect(engine.pending?.seconds == 60)
        #expect(engine.today == d("2026-10-25"))
    }

    @Test("ticking is cheap enough for a 1 s timer")
    func tickCost() {
        engine.start(projectID: alpha.id)
        let started = Date()
        for _ in 0..<20_000 { clock.advance(by: 1); engine.tick() }
        let elapsed = Date().timeIntervalSince(started)
        #expect(engine.pending?.seconds ?? 0 > 0)
        #expect(elapsed < 2.0, "20 000 ticks took \(elapsed)s")
    }

    @Test("a day of ticking never exceeds the 24 h cap")
    func fullDayOfTicks() {
        clock.set(year: 2026, month: 9, day: 7, hour: 0)
        engine.start(projectID: alpha.id)
        for _ in 0..<(24 * 60) { clock.advance(by: 60); engine.tick() }   // 1 min steps, gap-free
        #expect(engine.pendingSeconds <= secondsPerDay)
    }
}

@MainActor
@Suite("Hardening — reports performance")
struct ReportsPerformanceTests {

    @Test("a year with 50 projects builds in well under 50 ms")
    func yearReport() throws {
        let clock = TestClock()
        clock.set(year: 2026, month: 6, day: 15, hour: 12)
        let store = try Store.inMemory(clock: clock)
        let projects = try (0..<50).map { try store.findOrCreateProject(named: "Project \($0)") }

        var day = LocalDate(year: 2026, month: 1, day: 1)
        while day.year == 2026 {
            for project in projects.prefix(6) {
                try store.setSeconds(project: project.id, day: day, 3600)
            }
            day = day.adding(days: 1, calendar: clock.calendar)
        }

        let builder = ReportBuilder(store: store, engine: nil, clock: clock, weekStart: .monday)
        let started = Date()
        let report = try builder.report(for: .year(2026))
        let elapsed = Date().timeIntervalSince(started)

        #expect(report.rows.count == 6)
        #expect(report.total == 6 * 365 * 3600)
        #expect(elapsed < 0.05, "year report took \(elapsed)s")
    }
}

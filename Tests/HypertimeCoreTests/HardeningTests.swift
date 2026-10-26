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

@MainActor
@Suite("Hardening — relaunch")
struct RelaunchTests {
    let clock = TestClock()
    let store: Store
    let settings: Settings
    let project: Project

    init() throws {
        clock.set(year: 2026, month: 10, day: 26, hour: 9)
        store = try Store.inMemory(clock: clock)
        settings = Settings.ephemeral()
        project = try store.findOrCreateProject(named: "Alpha")
    }

    private var today: LocalDate { LocalDate(clock.now(), calendar: clock.calendar) }

    /// One launch, some ticking, then the process dies without a clean shutdown — which is
    /// what `pkill` during development, a crash, or a forced quit all look like.
    private func launchTickAndDie(seconds: Int) {
        let engine = TrackingEngine(store: store, clock: clock, settings: settings)
        engine.restore()
        for _ in 0..<seconds { clock.advance(by: 1); engine.tick() }
        engine.flush()                              // the 15 s persist that would have happened
    }

    @Test("a kill and relaunch books the time that passed, not the time that passed twice")
    func relaunchDoesNotDoubleBook() throws {
        settings.startTrackingOnLaunch = true
        let first = TrackingEngine(store: store, clock: clock, settings: settings)
        first.start(projectID: project.id)
        for _ in 0..<60 { clock.advance(by: 1); first.tick() }
        first.flush()

        // Ten relaunches, a minute of work each: eleven minutes in all.
        for _ in 0..<10 { launchTickAndDie(seconds: 60) }

        let banked = try store.seconds(project: project.id, day: today)
        #expect(banked <= 11 * 60,
                "eleven minutes of clock produced \(banked) s on the project")
    }

    @Test("relaunching without working books nothing at all")
    func idleRelaunchesBookNothing() throws {
        settings.startTrackingOnLaunch = true
        let first = TrackingEngine(store: store, clock: clock, settings: settings)
        first.start(projectID: project.id)
        for _ in 0..<300 { clock.advance(by: 1); first.tick() }
        first.flush()

        // The bucket is recovered once, and then relaunching changes nothing.
        launchTickAndDie(seconds: 0)
        let afterFirst = try store.seconds(project: project.id, day: today)
        for _ in 0..<5 { launchTickAndDie(seconds: 0) }
        let afterMore = try store.seconds(project: project.id, day: today)
        #expect(afterFirst == 300, "the crashed bucket is recovered once: \(afterFirst)")
        #expect(afterMore == afterFirst,
                "and never again: \(afterFirst) s became \(afterMore) s over five more launches")
    }

    @Test("repeated check-ins book the time since the last one, not since the morning")
    func repeatedCommitsDoNotCompound() throws {
        let engine = TrackingEngine(store: store, clock: clock, settings: settings)
        engine.start(projectID: project.id)

        var deltas: [Seconds] = []
        var previous = 0
        for _ in 0..<6 {
            for _ in 0..<90 { clock.advance(by: 1); engine.tick() }
            let shown = engine.pendingSeconds                 // what the popup offers
            engine.commit(projectID: project.id, seconds: shown)
            let banked = try store.seconds(project: project.id, day: today)
            deltas.append(banked - previous)
            previous = banked
        }

        #expect(deltas.allSatisfy { $0 <= 95 },
                "each check-in should book about ninety seconds, got \(deltas)")
        #expect(previous <= 6 * 95, "six checkins of ninety seconds became \(previous) s")
    }

    @Test("a check-in resets the amount the popup is offering")
    func commitClearsTheBucket() {
        let engine = TrackingEngine(store: store, clock: clock, settings: settings)
        engine.start(projectID: project.id)
        for _ in 0..<120 { clock.advance(by: 1); engine.tick() }
        #expect(engine.pendingSeconds == 120)
        engine.commit(projectID: project.id, seconds: engine.pendingSeconds)
        #expect(engine.pendingSeconds == 0, "still offering \(engine.pendingSeconds) s after a commit")
    }

    @Test("a bucket recovered once is never recovered again, however many readers there are")
    func recoveryIsIdempotent() throws {
        settings.startTrackingOnLaunch = false
        let first = TrackingEngine(store: store, clock: clock, settings: settings)
        first.start(projectID: project.id)
        for _ in 0..<300 { clock.advance(by: 1); first.tick() }
        first.flush()

        // Three engines open the same database without the first one ever tidying up, which
        // is what a second instance looks like from the database's side.
        for _ in 0..<3 {
            let other = TrackingEngine(store: store, clock: clock, settings: settings)
            other.restore()
        }
        let banked = try store.seconds(project: project.id, day: today)
        #expect(banked == 300, "the crashed five minutes were booked \(banked / 300) times over")
    }

    @Test("a bucket holding more seconds than the span it covers is capped at the span")
    func recoveryIsCappedAtItsOwnSpan() throws {
        settings.startTrackingOnLaunch = false
        var state = PersistedEngineState()
        state.kind = .tracking
        state.currentProjectID = project.id
        state.pendingProjectID = project.id
        state.pendingSince = clock.now().addingTimeInterval(-600)
        state.lastTickAt = clock.now()
        state.pendingSeconds = 30_000                      // nine hours inside a ten-minute span
        state.lastCommitAt = state.pendingSince
        try store.saveEngineState(state)

        let engine = TrackingEngine(store: store, clock: clock, settings: settings)
        engine.restore()
        let banked = try store.seconds(project: project.id, day: today)
        #expect(banked == 600, "ten minutes of clock recovered as \(banked) s")
    }

    /// What went wrong in the field, reproduced: a live engine ticking while something else
    /// keeps opening the same database and recovering its bucket. Each recovery books the
    /// whole bucket again, so ten minutes of clock becomes the sum of every reading of it.
    /// Nothing inside the engine can fix this — a dead instance and a live one look identical
    /// from the database — which is why `Store` takes an exclusive lock and the app refuses
    /// to be the second copy. This test exists to state the failure, not to pass by accident.
    @Test("the shape of the double-booking a second instance causes")
    func concurrentInstancesCompound() throws {
        settings.startTrackingOnLaunch = false
        let live = TrackingEngine(store: store, clock: clock, settings: settings)
        live.start(projectID: project.id)

        for _ in 0..<5 {
            for _ in 0..<60 { clock.advance(by: 1); live.tick() }
            live.flush()
            let second = TrackingEngine(store: store, clock: clock, settings: settings)
            second.restore()
        }

        let banked = try store.seconds(project: project.id, day: today)
        let elapsed = 5 * 60
        #expect(banked > elapsed,
                "the point of the lock is that this cannot happen in the app: \(banked) s booked for \(elapsed) s of clock")
    }
}

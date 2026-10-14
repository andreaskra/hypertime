import Foundation
import Testing
@testable import HypertimeCore

private func d(_ iso: String) -> LocalDate { LocalDate.parse(iso)! }

@Suite("Store")
struct StoreTests {
    let clock = TestClock()
    let store: Store

    init() throws {
        clock.set(year: 2026, month: 9, day: 7, hour: 10)
        store = try Store.inMemory(clock: clock)
    }

    @Test("create, find and list projects")
    func projects() throws {
        let a = try store.findOrCreateProject(named: "Hypertime")
        let b = try store.findOrCreateProject(named: "  Admin  ")
        #expect(b.name == "Admin")                                  // trimmed
        #expect(try store.projects().count == 2)
        #expect(try store.project(id: a.id)?.name == "Hypertime")
        #expect(try store.project(named: "HYPERTIME")?.id == a.id)  // case-insensitive
        #expect(try store.project(named: "nope") == nil)
    }

    @Test("findOrCreate is idempotent and case-insensitive")
    func idempotent() throws {
        let a = try store.findOrCreateProject(named: "Client")
        let b = try store.findOrCreateProject(named: "client")
        let c = try store.findOrCreateProject(named: " CLIENT ")
        #expect(a.id == b.id && b.id == c.id)
        #expect(try store.projects().count == 1)
        #expect(throws: StoreError.emptyName) { try store.findOrCreateProject(named: "   ") }
    }

    @Test("unicode-aware case-insensitive lookup")
    func unicodeNames() throws {
        let a = try store.findOrCreateProject(named: "Müller")
        #expect(try store.project(named: "müller")?.id == a.id)
        #expect(try store.findOrCreateProject(named: "MÜLLER").id == a.id)
    }

    @Test("projects sort by last used, then name")
    func ordering() throws {
        let a = try store.findOrCreateProject(named: "Beta")
        _ = try store.findOrCreateProject(named: "Alpha")
        let c = try store.findOrCreateProject(named: "Gamma")
        clock.advance(by: 60)
        try store.touchProject(id: a.id)
        clock.advance(by: 60)
        try store.touchProject(id: c.id)
        #expect(try store.projects().map(\.name) == ["Gamma", "Beta", "Alpha"])
    }

    @Test("rename rejects duplicates, allows the same project")
    func rename() throws {
        let a = try store.findOrCreateProject(named: "One")
        _ = try store.findOrCreateProject(named: "Two")
        #expect(throws: StoreError.duplicateName("two")) { try store.renameProject(id: a.id, to: "two") }
        try store.renameProject(id: a.id, to: "One Renamed")
        #expect(try store.project(id: a.id)?.name == "One Renamed")
        try store.renameProject(id: a.id, to: "ONE RENAMED")           // same project, different case
        #expect(try store.project(id: a.id)?.name == "ONE RENAMED")
        #expect(throws: StoreError.emptyName) { try store.renameProject(id: a.id, to: " ") }
    }

    @Test("archived projects are hidden unless asked for")
    func archive() throws {
        let a = try store.findOrCreateProject(named: "Old")
        try store.setArchived(id: a.id, true)
        #expect(try store.projects().isEmpty)
        #expect(try store.projects(includeArchived: true).count == 1)
        #expect(try store.project(id: a.id)?.isArchived == true)
        try store.setArchived(id: a.id, false)
        #expect(try store.projects().count == 1)
    }

    @Test("entries: set, add and clamp to 0…24 h")
    func entries() throws {
        let p = try store.findOrCreateProject(named: "P")
        #expect(try store.seconds(project: p.id, day: d("2026-09-07")) == 0)
        try store.setSeconds(project: p.id, day: d("2026-09-07"), 3600)
        #expect(try store.seconds(project: p.id, day: d("2026-09-07")) == 3600)
        #expect(try store.addSeconds(project: p.id, day: d("2026-09-07"), 900) == 4500)
        #expect(try store.addSeconds(project: p.id, day: d("2026-09-07"), -99999) == 0)
        try store.setSeconds(project: p.id, day: d("2026-09-07"), 999_999)
        #expect(try store.seconds(project: p.id, day: d("2026-09-07")) == 86400)
        try store.setSeconds(project: p.id, day: d("2026-09-07"), -5)
        #expect(try store.seconds(project: p.id, day: d("2026-09-07")) == 0)
    }

    @Test("range queries")
    func ranges() throws {
        let a = try store.findOrCreateProject(named: "A")
        let b = try store.findOrCreateProject(named: "B")
        try store.setSeconds(project: a.id, day: d("2026-09-01"), 600)
        try store.setSeconds(project: a.id, day: d("2026-09-15"), 1200)
        try store.setSeconds(project: b.id, day: d("2026-10-01"), 300)
        let september = d("2026-09-01")...d("2026-09-30")
        #expect(try store.entries(in: september).count == 2)
        #expect(try store.totalSeconds(in: september) == 1800)
        #expect(try store.projectsWithEntries(in: september).map(\.name) == ["A"])
        #expect(try store.projectsWithEntries(in: d("2026-09-01")...d("2026-10-31")).map(\.name) == ["A", "B"])
        #expect(try store.entries(in: d("2026-09-15")...d("2026-09-15")).first?.seconds == 1200)
    }

    @Test("deleting a project cascades to its entries")
    func cascade() throws {
        let p = try store.findOrCreateProject(named: "Doomed")
        try store.setSeconds(project: p.id, day: d("2026-09-07"), 600)
        try store.deleteProject(id: p.id)
        #expect(try store.projects(includeArchived: true).isEmpty)
        #expect(try store.entries(in: d("2026-01-01")...d("2026-12-31")).isEmpty)
    }

    @Test("every mutation is recorded in the change log")
    func changeLog() throws {
        let p = try store.findOrCreateProject(named: "Logged")
        try store.setSeconds(project: p.id, day: d("2026-09-07"), 600)
        _ = try store.addSeconds(project: p.id, day: d("2026-09-07"), 60)
        try store.renameProject(id: p.id, to: "Renamed")
        try store.setArchived(id: p.id, true)
        try store.deleteProject(id: p.id)
        let kinds = try store.changeLog().map(\.kind)
        #expect(kinds == ["project.delete", "project.archive", "project.rename", "entry.add", "entry.set", "project.create"])
        #expect(try store.changeLog().first { $0.kind == "entry.add" }?.payload.contains("\"delta\":\"60\"") == true)
    }

    @Test("change log is pruned after 90 days")
    func prune() throws {
        _ = try store.findOrCreateProject(named: "Old")
        clock.advance(by: 91 * 86_400)
        try store.pruneChangeLog()
        #expect(try store.changeLog().isEmpty)
    }

    @Test("engine state round trip")
    func engineState() throws {
        #expect(try store.loadEngineState() == nil)
        let id = UUID()
        let state = PersistedEngineState(
            kind: .paused,
            currentProjectID: id,
            trackingSince: Date(timeIntervalSince1970: 100),
            pausedUntil: Date(timeIntervalSince1970: 500),
            pauseReason: .screenLock,
            lastTickAt: Date(timeIntervalSince1970: 120),
            pendingProjectID: id,
            pendingSeconds: 42,
            pendingSince: Date(timeIntervalSince1970: 80),
            lastCheckInAt: Date(timeIntervalSince1970: 90),
            lastCommitAt: Date(timeIntervalSince1970: 70)
        )
        try store.saveEngineState(state)
        #expect(try store.loadEngineState() == state)
        try store.saveEngineState(nil)
        #expect(try store.loadEngineState() == nil)
    }

    @Test("writes notify observers")
    func observation() async throws {
        var iterator = store.changes.makeAsyncIterator()
        let task = Task { try store.findOrCreateProject(named: "Observed") }
        _ = try await task.value
        #expect(await iterator.next() == .projects)
    }
}

@Suite("Store — calendar marks")
struct StoreCalendarTests {

    @Test("daysWithTime lists only days that actually have time")
    func daysWithTime() throws {
        let clock = TestClock()
        clock.set(year: 2026, month: 10, day: 14, hour: 9)
        let store = try Store.inMemory(clock: clock)
        let a = try store.findOrCreateProject(named: "A")
        let b = try store.findOrCreateProject(named: "B")
        try store.setSeconds(project: a.id, day: d("2026-10-01"), 600)
        try store.setSeconds(project: b.id, day: d("2026-10-01"), 300)   // same day, two projects
        try store.setSeconds(project: a.id, day: d("2026-10-05"), 900)
        try store.setSeconds(project: a.id, day: d("2026-10-07"), 0)     // zero does not count
        try store.setSeconds(project: a.id, day: d("2026-11-02"), 60)    // outside the range

        let october = try store.daysWithTime(in: d("2026-10-01")...d("2026-10-31"))
        #expect(october == [d("2026-10-01"), d("2026-10-05")])
        #expect(try store.daysWithTime(in: d("2026-09-01")...d("2026-09-30")).isEmpty)
    }
}

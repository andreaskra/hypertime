import Foundation
import Testing
@testable import HypertimeCore

private func d(_ iso: String) -> LocalDate { LocalDate.parse(iso)! }

@MainActor
@Suite("TrackingEngine")
struct TrackingEngineTests {
    let clock = TestClock()
    let store: Store
    let settings: Settings
    let engine: TrackingEngine
    let alpha: Project
    let beta: Project

    init() throws {
        clock.set(year: 2026, month: 9, day: 7, hour: 9)
        store = try Store.inMemory(clock: clock)
        settings = Settings.ephemeral()
        engine = TrackingEngine(store: store, clock: clock, settings: settings)
        alpha = try store.findOrCreateProject(named: "Alpha")
        beta = try store.findOrCreateProject(named: "Beta")
    }

    /// Advances the clock in one-second steps, ticking each time (like the app's 1 s timer).
    func run(seconds: Int) {
        for _ in 0..<seconds {
            clock.advance(by: 1)
            engine.tick()
        }
    }

    @Test("starts idle with no pending time")
    func initialState() {
        #expect(engine.status == .idle)
        #expect(engine.pending == nil)
        #expect(engine.currentProjectID == nil)
    }

    @Test("pending accrues while tracking and nothing is written yet (D-13)")
    func accrual() throws {
        engine.start(projectID: alpha.id)
        run(seconds: 90)
        #expect(engine.pending?.seconds == 90)
        #expect(engine.pending?.projectID == alpha.id)
        #expect(try store.seconds(project: alpha.id, day: d("2026-09-07")) == 0)
        #expect(try engine.liveSeconds(project: alpha.id, day: d("2026-09-07")) == 90)
    }

    @Test("commit adds the given amount, resets the bucket and keeps tracking (D-08)")
    func commitAdds() throws {
        engine.start(projectID: alpha.id)
        run(seconds: 60)
        engine.commit(projectID: alpha.id, seconds: 60)
        #expect(try store.seconds(project: alpha.id, day: d("2026-09-07")) == 60)
        #expect(engine.pending?.seconds == 0)
        #expect(engine.status.isTracking)

        run(seconds: 30)
        engine.commit(projectID: alpha.id, seconds: 30)
        #expect(try store.seconds(project: alpha.id, day: d("2026-09-07")) == 90)   // adds, never sets
    }

    @Test("a smaller committed amount discards the remainder (D-15)")
    func commitSmaller() throws {
        engine.start(projectID: alpha.id)
        run(seconds: 300)
        engine.commit(projectID: alpha.id, seconds: 20)
        #expect(try store.seconds(project: alpha.id, day: d("2026-09-07")) == 20)
        #expect(engine.pending?.seconds == 0)
        run(seconds: 10)
        #expect(engine.pending?.seconds == 10)                                       // fresh bucket
    }

    @Test("a larger committed amount is simply a manual addition (D-15)")
    func commitLarger() throws {
        engine.start(projectID: alpha.id)
        run(seconds: 60)
        engine.commit(projectID: alpha.id, seconds: 3600)
        #expect(try store.seconds(project: alpha.id, day: d("2026-09-07")) == 3600)
    }

    @Test("committing to another project moves tracking and drops provisional attribution")
    func commitOtherProject() throws {
        engine.start(projectID: alpha.id)
        run(seconds: 120)
        #expect(try engine.liveSeconds(project: alpha.id, day: d("2026-09-07")) == 120)
        engine.commit(projectID: beta.id, seconds: 120)
        #expect(try store.seconds(project: alpha.id, day: d("2026-09-07")) == 0)
        #expect(try store.seconds(project: beta.id, day: d("2026-09-07")) == 120)
        #expect(engine.currentProjectID == beta.id)
        run(seconds: 5)
        #expect(try engine.liveSeconds(project: beta.id, day: d("2026-09-07")) == 125)
    }

    @Test("commit from idle starts tracking, from paused resumes it (D-09)")
    func commitStartsTracking() {
        engine.commit(projectID: alpha.id, seconds: 0)
        #expect(engine.status.isTracking)
        engine.pause(until: clock.now().addingTimeInterval(900), reason: .manual)
        #expect(engine.status.isPaused)
        engine.commit(projectID: alpha.id, seconds: 0)
        #expect(engine.status.isTracking)
    }

    @Test("discardPending throws the bucket away and keeps tracking (R-04)")
    func discard() throws {
        engine.start(projectID: alpha.id)
        run(seconds: 300)
        engine.discardPending()
        #expect(engine.pending?.seconds == 0)
        #expect(engine.status.isTracking)
        #expect(try store.seconds(project: alpha.id, day: d("2026-09-07")) == 0)
        run(seconds: 10)
        #expect(engine.pending?.seconds == 10)
    }

    @Test("pause preserves the bucket and stops accrual (R-14, A-07)")
    func pausePreservesPending() throws {
        engine.start(projectID: alpha.id)
        run(seconds: 100)
        engine.pause(until: clock.now().addingTimeInterval(900), reason: .manual)
        run(seconds: 200)
        #expect(engine.pending?.seconds == 100)
        #expect(engine.status.isPaused)
        engine.resume()
        run(seconds: 10)
        #expect(engine.pending?.seconds == 110)
    }

    @Test("a pause auto-resumes when it expires")
    func autoResume() async throws {
        engine.start(projectID: alpha.id)
        engine.pause(until: clock.now().addingTimeInterval(60), reason: .manual)
        run(seconds: 59)
        #expect(engine.status.isPaused)
        run(seconds: 2)
        #expect(engine.status.isTracking)
    }

    @Test("long gaps (sleep) and backwards clock jumps are discarded (A-01)")
    func gaps() throws {
        engine.start(projectID: alpha.id)
        run(seconds: 10)
        clock.advance(by: 3600)                       // machine slept
        engine.tick()
        #expect(engine.pending?.seconds == 10)
        clock.advance(by: -600)                       // clock moved backwards
        engine.tick()
        #expect(engine.pending?.seconds == 10)
        run(seconds: 5)
        #expect(engine.pending?.seconds == 15)
    }

    @Test("stop auto-commits the bucket and goes idle (R-15, A-07)")
    func stopFlushes() throws {
        engine.start(projectID: alpha.id)
        run(seconds: 45)
        engine.stop()
        #expect(engine.status == .idle)
        #expect(engine.pending == nil)
        #expect(try store.seconds(project: alpha.id, day: d("2026-09-07")) == 45)
    }

    @Test("setTotal folds pending in first, then sets (A-07, R-17)")
    func setTotalFoldsPending() throws {
        engine.start(projectID: alpha.id)
        run(seconds: 100)
        engine.setTotal(projectID: alpha.id, day: d("2026-09-07"), seconds: 7200)
        #expect(try store.seconds(project: alpha.id, day: d("2026-09-07")) == 7200)
        #expect(engine.pending?.seconds == 0)
        run(seconds: 5)
        #expect(try engine.liveSeconds(project: alpha.id, day: d("2026-09-07")) == 7205)
    }

    @Test("setTotal on another project keeps this project's pending time")
    func setTotalOtherProject() throws {
        engine.start(projectID: alpha.id)
        run(seconds: 100)
        engine.setTotal(projectID: beta.id, day: d("2026-09-07"), seconds: 60)
        #expect(try store.seconds(project: alpha.id, day: d("2026-09-07")) == 100)   // folded in
        #expect(try store.seconds(project: beta.id, day: d("2026-09-07")) == 60)
    }

    @Test("midnight splits the accrual between the two days (D-06)")
    func midnightSplit() throws {
        clock.set(year: 2026, month: 9, day: 7, hour: 23, minute: 59, second: 30)
        engine.start(projectID: alpha.id)
        run(seconds: 60)                              // 30 s before, 30 s after midnight
        #expect(try store.seconds(project: alpha.id, day: d("2026-09-07")) == 30)
        #expect(engine.pending?.seconds == 30)
        #expect(try engine.liveSeconds(project: alpha.id, day: d("2026-09-08")) == 30)
        #expect(engine.today == d("2026-09-08"))
    }

    @Test("check-in is due one interval after the last commit")
    func checkInSchedule() async throws {
        settings.checkInIntervalMinutes = 1
        let stream = engine.events

        engine.commit(projectID: alpha.id, seconds: 0)
        #expect(engine.nextCheckInAt == clock.now().addingTimeInterval(60))
        run(seconds: 59)
        #expect(engine.lastCheckInShownAt == nil)
        run(seconds: 2)
        #expect(engine.lastCheckInShownAt != nil)

        // Dismissed (not committed): it comes back one interval later, with more pending time.
        run(seconds: 59)
        run(seconds: 2)
        #expect(engine.pending?.seconds == 122)

        engine.finishEvents()
        var dueCount = 0
        for await event in stream where event == .checkInDue { dueCount += 1 }
        #expect(dueCount == 2)
    }

    @Test("committing pushes the next check-in one full interval out")
    func checkInResetsOnCommit() {
        settings.checkInIntervalMinutes = 1
        engine.start(projectID: alpha.id)
        run(seconds: 61)
        #expect(engine.lastCheckInShownAt != nil)
        engine.commit(projectID: alpha.id, seconds: 61)
        #expect(engine.nextCheckInAt == clock.now().addingTimeInterval(60))
        run(seconds: 30)
        #expect(engine.nextCheckInAt == clock.now().addingTimeInterval(30))
    }

    @Test("check-in interval 0 turns check-ins off")
    func checkInOff() {
        settings.checkInIntervalMinutes = 0
        engine.start(projectID: alpha.id)
        #expect(engine.nextCheckInAt == nil)
        run(seconds: 600)
        #expect(engine.pending?.seconds == 600)
    }

    @Test("daily total is capped at 24 h (A-04)")
    func dailyCap() throws {
        engine.commit(projectID: alpha.id, seconds: 86400)
        engine.commit(projectID: alpha.id, seconds: 3600)
        #expect(try store.seconds(project: alpha.id, day: d("2026-09-07")) == 86400)
    }

    @Test("restore picks tracking back up on the last project")
    func restoreResumes() throws {
        engine.start(projectID: alpha.id)
        run(seconds: 120)
        engine.stop()
        clock.advance(by: 8 * 3600)                    // the app was closed overnight

        let restored = TrackingEngine(store: store, clock: clock, settings: settings)
        restored.restore()
        #expect(restored.status.isTracking)
        #expect(restored.currentProjectID == alpha.id)
        #expect(restored.pendingSeconds == 0)          // none of the closed hours are work time
        #expect(try store.seconds(project: alpha.id, day: d("2026-09-07")) == 120)
    }

    @Test("the check-in clock restarts when tracking resumes on launch")
    func restoreRestartsCheckInClock() throws {
        settings.checkInIntervalMinutes = 30
        engine.start(projectID: alpha.id)
        run(seconds: 60)
        engine.stop()
        clock.advance(by: 8 * 3600)

        let restored = TrackingEngine(store: store, clock: clock, settings: settings)
        restored.restore()
        #expect(restored.nextCheckInAt == clock.now().addingTimeInterval(1800))
    }

    @Test("restore waits when start-on-launch is off (the old A-03 behaviour)")
    func restoreStaysIdleWhenDisabled() throws {
        settings.startTrackingOnLaunch = false
        engine.start(projectID: alpha.id)
        run(seconds: 120)
        engine.stop()

        let restored = TrackingEngine(store: store, clock: clock, settings: settings)
        restored.restore()
        #expect(restored.status == .idle)
        #expect(restored.currentProjectID == alpha.id)  // still preselects it (R-05)
        #expect(restored.pending == nil)
        #expect(try store.seconds(project: alpha.id, day: d("2026-09-07")) == 120)
    }

    @Test("restore does not resume a project deleted while the app was closed")
    func restoreSkipsDeletedProject() throws {
        engine.start(projectID: alpha.id)
        run(seconds: 60)
        engine.stop()
        try store.deleteProject(id: alpha.id)

        let restored = TrackingEngine(store: store, clock: clock, settings: settings)
        restored.restore()
        #expect(restored.status == .idle)
    }

    @Test("restore with nothing tracked before stays idle")
    func restoreWithoutHistory() {
        let restored = TrackingEngine(store: store, clock: clock, settings: settings)
        restored.restore()
        #expect(restored.status == .idle)
        #expect(restored.currentProjectID == nil)
    }

    @Test("restore after a crash recovers the persisted bucket, then resumes")
    func restoreAfterCrash() throws {
        engine.start(projectID: alpha.id)
        run(seconds: 200)
        engine.flush()                                 // simulates the last persist before a crash

        let restored = TrackingEngine(store: store, clock: clock, settings: settings)
        restored.restore()
        #expect(try store.seconds(project: alpha.id, day: d("2026-09-07")) == 200)
        #expect(restored.status.isTracking)
        #expect(restored.currentProjectID == alpha.id)
        #expect(restored.pendingSeconds == 0)          // the recovered time is banked, not pending
    }

    @Test("liveSeconds only adds pending to the right project and day")
    func liveSeconds() throws {
        engine.start(projectID: alpha.id)
        run(seconds: 50)
        #expect(try engine.liveSeconds(project: alpha.id, day: d("2026-09-07")) == 50)
        #expect(try engine.liveSeconds(project: beta.id, day: d("2026-09-07")) == 0)
        #expect(try engine.liveSeconds(project: alpha.id, day: d("2026-09-06")) == 0)
    }
}

@Suite("PauseScheduler")
struct PauseSchedulerTests {
    let clock = TestClock()
    let scheduler = PauseScheduler()

    @Test("fixed durations")
    func durations() {
        clock.set(year: 2026, month: 9, day: 7, hour: 10)
        let now = clock.now()
        #expect(scheduler.until(.m15, now: now, calendar: clock.calendar) == now.addingTimeInterval(900))
        #expect(scheduler.until(.m30, now: now, calendar: clock.calendar) == now.addingTimeInterval(1800))
        #expect(scheduler.until(.h1, now: now, calendar: clock.calendar) == now.addingTimeInterval(3600))
        #expect(scheduler.until(.h2, now: now, calendar: clock.calendar) == now.addingTimeInterval(7200))
        #expect(scheduler.until(.custom, customDuration: 4500, now: now, calendar: clock.calendar)
                == now.addingTimeInterval(4500))
    }

    @Test("until morning picks the next 07:00 strictly after now")
    func untilMorning() {
        clock.set(year: 2026, month: 9, day: 7, hour: 3)
        var until = scheduler.until(.untilMorning, now: clock.now(), calendar: clock.calendar)
        var comps = clock.calendar.dateComponents([.year, .month, .day, .hour], from: until)
        #expect(comps.day == 7 && comps.hour == 7)

        clock.set(year: 2026, month: 9, day: 7, hour: 9)
        until = scheduler.until(.untilMorning, now: clock.now(), calendar: clock.calendar)
        comps = clock.calendar.dateComponents([.year, .month, .day, .hour], from: until)
        #expect(comps.day == 8 && comps.hour == 7)

        // Exactly at 07:00 the next occurrence is tomorrow ("strictly after").
        clock.set(year: 2026, month: 9, day: 7, hour: 7)
        until = scheduler.until(.untilMorning, now: clock.now(), calendar: clock.calendar)
        comps = clock.calendar.dateComponents([.year, .month, .day, .hour], from: until)
        #expect(comps.day == 8 && comps.hour == 7)
    }

    @Test("morning hour is configurable and crosses month ends")
    func customMorning() {
        clock.set(year: 2026, month: 9, day: 30, hour: 23)
        let until = scheduler.until(.untilMorning, now: clock.now(), calendar: clock.calendar, morningHour: 5)
        let comps = clock.calendar.dateComponents([.year, .month, .day, .hour], from: until)
        #expect(comps.month == 10 && comps.day == 1 && comps.hour == 5)
    }
}

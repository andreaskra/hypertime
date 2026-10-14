import Foundation
import Testing
@testable import HypertimeCore

private func d(_ iso: String) -> LocalDate { LocalDate.parse(iso)! }

@MainActor
@Suite("TrackingEngine — tasks")
struct TaskEngineTests {
    let clock = TestClock()
    let store: Store
    let settings: Settings
    let engine: TrackingEngine
    let project: Project
    let other: Project

    init() throws {
        clock.set(year: 2026, month: 10, day: 14, hour: 9)
        store = try Store.inMemory(clock: clock)
        settings = Settings.ephemeral()
        engine = TrackingEngine(store: store, clock: clock, settings: settings)
        project = try store.findOrCreateProject(named: "Hypertime")
        other = try store.findOrCreateProject(named: "Admin")
    }

    func run(seconds: Int) {
        for _ in 0..<seconds { clock.advance(by: 1); engine.tick() }
    }

    @Test("a running task owns the clock and books to its project too")
    func taskOwnsTheClock() throws {
        let task = try store.createTask(projectID: project.id, title: "Deep work")
        engine.startTask(task)
        run(seconds: 60)

        #expect(engine.activeTaskID == task.id)
        #expect(engine.activeTaskSeconds == 60)
        #expect(engine.liveTaskSeconds(task.id) == 60)
        // Live totals include seconds not yet flushed.
        #expect(try engine.liveSeconds(project: project.id, day: d("2026-10-14")) == 60)
        // Nothing went to the pending bucket.
        #expect(engine.pendingSeconds == 0)
    }

    @Test("task seconds reach the database on the flush interval")
    func flushing() throws {
        settings.flushIntervalSeconds = 5
        let task = try store.createTask(projectID: project.id, title: "Flush me")
        engine.startTask(task)
        run(seconds: 12)
        #expect(try store.taskSeconds(task: task.id) > 0)
        #expect(try store.seconds(project: project.id, day: d("2026-10-14"))
                == store.taskSeconds(task: task.id))
    }

    @Test("starting a task leaves the pending bucket alone (TA-03)")
    func bucketUntouched() throws {
        engine.start(projectID: other.id)
        run(seconds: 30)
        #expect(engine.pendingSeconds == 30)

        let task = try store.createTask(projectID: project.id, title: "Switch")
        engine.startTask(task)
        run(seconds: 20)
        #expect(engine.pendingSeconds == 30)              // frozen, not claimed
        #expect(engine.activeTaskSeconds == 20)
    }

    @Test("stopping a task hands the clock back to the bucket (TA-01)")
    func stopReturnsToBucket() throws {
        let task = try store.createTask(projectID: project.id, title: "Pause me")
        engine.startTask(task)
        run(seconds: 30)
        engine.stopTask()

        #expect(engine.activeTaskID == nil)
        #expect(try store.taskSeconds(task: task.id) == 30)
        run(seconds: 10)
        #expect(engine.pendingSeconds == 10)              // the bucket is accruing again
        #expect(try store.taskSeconds(task: task.id) == 30)
    }

    @Test("starting another task banks the first")
    func switchTasks() throws {
        let a = try store.createTask(projectID: project.id, title: "A")
        let b = try store.createTask(projectID: other.id, title: "B")
        engine.startTask(a)
        run(seconds: 25)
        engine.startTask(b)
        run(seconds: 15)

        #expect(try store.taskSeconds(task: a.id) == 25)
        #expect(engine.activeTaskID == b.id)
        #expect(engine.activeTaskSeconds == 15)
        #expect(try store.seconds(project: project.id, day: d("2026-10-14")) == 25)
    }

    @Test("finishing banks the time and closes the task")
    func finish() throws {
        let task = try store.createTask(projectID: project.id, title: "Done soon")
        engine.startTask(task)
        run(seconds: 40)
        engine.finishTask(task.id)

        #expect(engine.activeTaskID == nil)
        #expect(try store.task(id: task.id)?.isComplete == true)
        #expect(try store.taskSeconds(task: task.id) == 40)
        #expect(try store.tasks().isEmpty)
    }

    @Test("check-ins stay quiet while a task runs (TD-03)")
    func checkInsSuppressed() async throws {
        settings.checkInIntervalMinutes = 1
        let task = try store.createTask(projectID: project.id, title: "Heads down")
        let stream = engine.events
        engine.startTask(task)
        run(seconds: 130)
        #expect(engine.lastCheckInShownAt == nil)

        engine.stopTask()
        run(seconds: 70)
        #expect(engine.lastCheckInShownAt != nil)         // and they come back afterwards

        engine.finishEvents()
        var due = 0
        for await event in stream where event == .checkInDue { due += 1 }
        #expect(due == 1)
    }

    @Test("a timer fires once at zero")
    func timerExpires() async throws {
        let task = try store.createTask(projectID: project.id, title: "Pomodoro", timerSeconds: 30)
        let stream = engine.events
        engine.startTask(task)
        #expect(engine.taskRemaining(task) == 30)
        run(seconds: 29)
        run(seconds: 5)
        #expect(engine.activeTaskSeconds == 34)

        engine.finishEvents()
        var fired = 0
        for await event in stream { if case .taskTimerExpired = event { fired += 1 } }
        #expect(fired == 1)                               // once, not every tick past zero
    }

    @Test("task time splits at midnight like everything else")
    func midnight() throws {
        clock.set(year: 2026, month: 10, day: 14, hour: 23, minute: 59, second: 30)
        let task = try store.createTask(projectID: project.id, title: "Across midnight")
        engine.startTask(task)
        run(seconds: 60)
        engine.stopTask()

        #expect(try store.taskSeconds(task: task.id, day: d("2026-10-14")) == 30)
        #expect(try store.taskSeconds(task: task.id, day: d("2026-10-15")) == 30)
        #expect(try store.seconds(project: project.id, day: d("2026-10-14")) == 30)
        #expect(try store.seconds(project: project.id, day: d("2026-10-15")) == 30)
    }

    @Test("quitting banks the task; a relaunch resumes the project, not the task (T-09)")
    func restore() throws {
        let task = try store.createTask(projectID: project.id, title: "Overnight")
        engine.startTask(task)
        run(seconds: 45)
        engine.stop()
        #expect(try store.taskSeconds(task: task.id) == 45)

        let restored = TrackingEngine(store: store, clock: clock, settings: settings)
        restored.restore()
        #expect(restored.activeTaskID == nil)
        #expect(restored.currentProjectID == project.id)
        #expect(restored.status.isTracking)
    }

    @Test("sleep banks the task and keeps it on resume")
    func pauseKeepsTask() throws {
        let task = try store.createTask(projectID: project.id, title: "Interrupted")
        engine.startTask(task)
        run(seconds: 20)
        engine.pause(until: .distantFuture, reason: .systemSleep)
        #expect(try store.taskSeconds(task: task.id) == 20)
        run(seconds: 30)
        #expect(try store.taskSeconds(task: task.id) == 20)   // nothing accrues while paused
        engine.resume()
        run(seconds: 10)
        #expect(engine.activeTaskID == task.id)
        #expect(engine.liveTaskSeconds(task.id) == 30)
    }

    @Test("deleting the running task stops the clock without booking more")
    func deleteRunning() throws {
        let task = try store.createTask(projectID: project.id, title: "Zap")
        engine.startTask(task)
        run(seconds: 30)
        engine.taskDeleted(task.id)
        try store.deleteTask(id: task.id)

        #expect(engine.activeTaskID == nil)
        // The 30 s were real work and stay on the project (TD-05).
        #expect(try store.seconds(project: project.id, day: d("2026-10-14")) == 30)
    }
}

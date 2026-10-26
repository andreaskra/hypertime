import Foundation
import Testing
@testable import HypertimeCore

@MainActor
@Suite("Timeline")
struct TimelineTests {
    let clock = TestClock()
    let store: Store
    let settings: Settings
    let engine: TrackingEngine
    let alpha: Project
    let beta: Project

    init() throws {
        clock.set(year: 2026, month: 10, day: 26, hour: 9)
        store = try Store.inMemory(clock: clock)
        settings = Settings.ephemeral()
        engine = TrackingEngine(store: store, clock: clock, settings: settings)
        alpha = try store.findOrCreateProject(named: "Alpha")
        beta = try store.findOrCreateProject(named: "Beta")
    }

    private func run(seconds: Int) {
        for _ in 0..<seconds { clock.advance(by: 1); engine.tick() }
    }

    private func allSlices() throws -> [Slice] {
        try store.slices(from: clock.now().addingTimeInterval(-Timeline.window),
                         to: clock.now().addingTimeInterval(Timeline.grain))
    }

    // MARK: - Brackets

    @Test("the window is a day of half-hour brackets")
    func grain() {
        #expect(Timeline.grain == 1800)
        #expect(Timeline.bucketCount == 48)
        // A bracket starts on its own boundary whatever moment inside it you ask about.
        let start = Timeline.bucketStart(for: Date(timeIntervalSince1970: 1_000_000_123))
        #expect(start.timeIntervalSince1970.truncatingRemainder(dividingBy: 1800) == 0)
        #expect(Timeline.bucketStart(for: start) == start)
        #expect(Timeline.bucketStart(for: start.addingTimeInterval(1799)) == start)
        #expect(Timeline.bucketStart(for: start.addingTimeInterval(1800)) != start)
    }

    @Test("a bracket that hides idle behind a majority of work still says so")
    func idleSurvivesDominance() {
        let now = clock.now()
        let bucket = Timeline.bucketStart(for: now.addingTimeInterval(-3600))
        let parts = [
            Slice(bucketStart: bucket, kind: .tracked, projectID: alpha.id, seconds: 1200),
            Slice(bucketStart: bucket, kind: .idle, projectID: nil, seconds: 600),
        ]
        let mark = Timeline.buckets(from: parts, now: now).first { !$0.isEmpty }
        #expect(mark?.dominant?.kind == .tracked, "twenty minutes of work wins a half hour")
        #expect(mark?.hasIdle == true, "…but the ten idle minutes inside it are not swallowed")
    }

    @Test("the strip is always a full day wide, known or not")
    func alwaysFullWidth() {
        let now = clock.now()
        let buckets = Timeline.buckets(from: [], now: now)
        #expect(buckets.count == Timeline.bucketCount)
        #expect(buckets.allSatisfy { $0.isEmpty })
        let inOrder = buckets.sorted { $0.start < $1.start }
        #expect(buckets == inOrder)
        // The last bracket is the one we are in; the first is a day earlier.
        #expect(buckets.last?.start == Timeline.bucketStart(for: now))
        #expect(now.timeIntervalSince(buckets[0].start) < Timeline.window + Timeline.grain)
    }

    @Test("slices outside the window are left out rather than squashed into the ends")
    func windowing() {
        let now = clock.now()
        let old = Slice(bucketStart: now.addingTimeInterval(-2 * Timeline.window),
                        kind: .tracked, projectID: alpha.id, seconds: 600)
        let inside = Slice(bucketStart: now.addingTimeInterval(-3600),
                           kind: .tracked, projectID: alpha.id, seconds: 600)
        let buckets = Timeline.buckets(from: [old, inside], now: now)
        #expect(buckets.filter { !$0.isEmpty }.count == 1)
        #expect(buckets.first(where: { !$0.isEmpty })?.dominant?.projectID == alpha.id)
    }

    // MARK: - Mixed brackets (TLD-05)

    @Test("the biggest share colours the mark and the rest stays readable")
    func mixed() {
        let now = clock.now()
        let bucket = Timeline.bucketStart(for: now.addingTimeInterval(-3600))
        let parts = [
            Slice(bucketStart: bucket, kind: .tracked, projectID: alpha.id, seconds: 120),
            Slice(bucketStart: bucket, kind: .idle, projectID: nil, seconds: 400),
            Slice(bucketStart: bucket, kind: .tracked, projectID: beta.id, seconds: 80),
        ]
        let mark = Timeline.buckets(from: parts, now: now).first { !$0.isEmpty }
        #expect(mark?.dominant?.kind == .idle, "idle wins a bracket it is the biggest part of (TLA-04)")
        #expect(mark?.isMixed == true)
        #expect(mark?.seconds == 600)
        #expect(mark?.hasIdle == true)
        // Every part survives for the hover readout, biggest first.
        #expect(mark?.parts.map(\.seconds) == [400, 120, 80])
    }

    @Test("parts of the same thing in one bracket are added, not listed twice")
    func merging() {
        let now = clock.now()
        let bucket = Timeline.bucketStart(for: now.addingTimeInterval(-3600))
        let parts = [
            Slice(bucketStart: bucket, kind: .tracked, projectID: alpha.id, seconds: 100),
            Slice(bucketStart: bucket.addingTimeInterval(61), kind: .tracked, projectID: alpha.id, seconds: 200),
        ]
        let mark = Timeline.buckets(from: parts, now: now).first { !$0.isEmpty }
        #expect(mark?.parts.count == 1)
        #expect(mark?.parts.first?.seconds == 300)
        #expect(mark?.isMixed == false)
    }

    // MARK: - What the engine records

    @Test("tracking writes itself onto the strip")
    func trackingIsRecorded() throws {
        engine.start(projectID: alpha.id)
        run(seconds: 120)
        engine.stop()
        let slices = try allSlices()
        #expect(slices.contains { $0.kind == .tracked && $0.projectID == alpha.id })
        let tracked = slices.filter { $0.kind == .tracked }.reduce(0) { $0 + $1.seconds }
        #expect(tracked == 120, "every counted second belongs to a bracket: \(tracked)")
    }

    @Test("a task's time lands on the strip under its project")
    func taskTimeIsRecorded() throws {
        let task = try store.createTask(projectID: beta.id, title: "Write it up")
        engine.start(projectID: alpha.id)
        engine.startTask(task)
        run(seconds: 90)
        engine.stopTask()
        let tracked = try allSlices().filter { $0.kind == .tracked }
        #expect(tracked.contains { $0.projectID == beta.id })
        #expect(!tracked.contains { $0.projectID == alpha.id },
                "a running task owns the clock, so the strip must not also credit the project behind it")
    }

    @Test("going idle repaints the stretch rather than leaving it as work")
    func idleIsRepainted() throws {
        settings.idleTimeoutMinutes = 10
        engine.start(projectID: alpha.id)
        run(seconds: 1200)                       // twenty minutes at the keyboard
        let workedBefore = try allSlices().filter { $0.kind == .tracked }.reduce(0) { $0 + $1.seconds }
        #expect(workedBefore == 1200)

        engine.checkIdle(systemIdleSeconds: 600) // ten of those minutes were nobody there
        let after = try allSlices()
        let worked = after.filter { $0.kind == .tracked }.reduce(0) { $0 + $1.seconds }
        let idle = after.filter { $0.kind == .idle }.reduce(0) { $0 + $1.seconds }
        #expect(idle == 600, "the idle stretch is on the strip: \(idle)")
        #expect(worked == 600, "and is no longer also counted as work: \(worked)")
    }

    @Test("time spent paused is on the strip too")
    func pausedIsRecorded() throws {
        engine.start(projectID: alpha.id)
        run(seconds: 60)
        engine.pause(until: clock.now().addingTimeInterval(3600), reason: .manual)
        run(seconds: 300)
        engine.resume()
        run(seconds: 60)
        let slices = try allSlices()
        #expect(slices.filter { $0.kind == .paused }.reduce(0) { $0 + $1.seconds } == 300)
        #expect(slices.filter { $0.kind == .tracked }.reduce(0) { $0 + $1.seconds } == 120)
    }

    @Test("a stretch the machine slept through is unknown, not idle")
    func sleepIsNotIdle() throws {
        engine.start(projectID: alpha.id)
        run(seconds: 60)
        clock.advance(by: 4 * 3600)              // lid closed
        engine.tick()
        let slices = try allSlices()
        #expect(slices.filter { $0.kind != .tracked }.isEmpty,
                "nothing is known about a gap, and inventing idle would be a different lie")
        #expect(slices.filter { $0.kind == .tracked }.reduce(0) { $0 + $1.seconds } == 60)
    }

    @Test("confirming somewhere else moves the marks with the time (TLD-08)")
    func commitReassigns() throws {
        engine.start(projectID: alpha.id)
        run(seconds: 300)
        engine.commit(projectID: beta.id, seconds: 300)
        let tracked = try allSlices().filter { $0.kind == .tracked }
        #expect(tracked.allSatisfy { $0.projectID == beta.id },
                "the strip and the day list have to agree about where the time went")
        #expect(tracked.reduce(0) { $0 + $1.seconds } == 300)
    }

    // MARK: - Colour slots (TLD-07)

    @Test("a project keeps its colour for life")
    func colourSlots() throws {
        #expect(alpha.colorSlot == 0)
        #expect(beta.colorSlot == 1)
        // Whatever happens to the ranking, the slot is the one it was given.
        _ = try store.addSeconds(project: beta.id, day: LocalDate(clock.now(), calendar: clock.calendar), 9999)
        let reloadedAlpha = try store.project(id: alpha.id)
        let reloadedBeta = try store.project(id: beta.id)
        #expect(reloadedAlpha?.colorSlot == 0)
        #expect(reloadedBeta?.colorSlot == 1)
    }

    @Test("a deleted project frees its colour for the next one")
    func colourReuse() throws {
        try store.deleteProject(id: alpha.id)
        let gamma = try store.findOrCreateProject(named: "Gamma")
        #expect(gamma.colorSlot == 0, "lowest free slot, rather than marching off the end of the palette")
    }

    // MARK: - Housekeeping

    @Test("slices older than a week are thrown away")
    func pruning() throws {
        let old = clock.now().addingTimeInterval(-8 * 86_400)
        try store.addSlice(bucketStart: old, kind: .tracked, project: alpha.id, 600)
        try store.addSlice(bucketStart: clock.now(), kind: .tracked, project: alpha.id, 600)
        try store.pruneSlices()
        let kept = try store.slices(from: Date(timeIntervalSince1970: 0),
                                    to: clock.now().addingTimeInterval(600))
        #expect(kept.count == 1)
        #expect(kept.first?.bucketStart ?? .distantPast > old)
    }
}

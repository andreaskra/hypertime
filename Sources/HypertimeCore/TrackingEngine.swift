import Foundation

public enum TrackingEvent: Sendable, Equatable {
    case statusChanged(TrackingStatus)
    case tick(PendingTime?)
    case checkInDue
    case pauseEnded
    /// A timed task reached zero and the user has to decide (T-12).
    case taskTimerExpired(UUID)
    /// Stored totals changed (commit, manual edit, auto-commit).
    case dataChanged
    /// Tasks were created, finished, deleted or switched.
    case tasksChanged
}

/// The tracking state machine (§5.5). Time accrues into an in-memory `pending` bucket and is
/// only written to `day_entry` on a commit (D-13).
@MainActor
public final class TrackingEngine {
    public let store: Store
    private let clock: Clock
    private let settings: Settings
    private let broadcaster = Broadcaster<TrackingEvent>()

    public private(set) var status: TrackingStatus = .idle
    /// Remembered even while idle or paused, so the popup can preselect it.
    public private(set) var currentProjectID: UUID?
    /// Unattributed time since the last commit (D-13).
    public private(set) var pending: PendingTime?

    /// The task that owns the clock, or nil when time flows into the pending bucket (TD-01).
    public private(set) var activeTaskID: UUID?
    private var taskProjectID: UUID?
    private var taskBaselineSeconds: Seconds = 0
    private var taskAccruedSinceStart: Seconds = 0
    private var taskUnwritten: Seconds = 0
    private var taskFraction: Double = 0
    private var taskTimerFired = false

    private var lastTickAt: Date
    private var lastCommitAt: Date
    public private(set) var lastCheckInShownAt: Date?
    private var lastPersistAt: Date
    private var fraction: Double = 0
    /// Sub-second carry for time the app spends paused or idle, which accrues to the timeline
    /// but to no counter.
    private var awayFraction: Double = 0

    public var events: AsyncStream<TrackingEvent> { broadcaster.stream }

    public init(store: Store, clock: Clock, settings: Settings) {
        self.store = store
        self.clock = clock
        self.settings = settings
        let now = clock.now()
        self.lastTickAt = now
        self.lastCommitAt = now
        self.lastPersistAt = now
    }

    // MARK: - Derived state

    public var today: LocalDate { LocalDate(clock.now(), calendar: clock.calendar) }

    /// Seconds the popup should offer to add: the pending bucket, or 0 when idle.
    public var pendingSeconds: Seconds { pending?.seconds ?? 0 }

    /// Stored total plus provisional pending time (D-13).
    public func liveSeconds(project: UUID, day: LocalDate) throws -> Seconds {
        var total = try store.seconds(project: project, day: day)
        if let pending, pending.projectID == project, day == today {
            total += pending.seconds
        }
        if taskProjectID == project, day == today { total += taskUnwritten }
        return min(total, secondsPerDay)
    }

    /// What the running task has accrued but not yet flushed to the database.
    ///
    /// Task time is committed as it happens (TD-01), so a report that reads only what has been
    /// written shows it arriving in flush-sized jumps — a project's figure standing still for
    /// fifteen seconds at a time while its task is plainly running.
    public var unflushedTaskTime: (projectID: UUID, seconds: Seconds)? {
        guard let projectID = taskProjectID, taskUnwritten > 0 else { return nil }
        return (projectID, taskUnwritten)
    }

    /// Everything the running task has accrued, including seconds not yet written.
    public var activeTaskSeconds: Seconds { taskBaselineSeconds + taskAccruedSinceStart }

    /// Seconds left on the running task's timer; negative once it has overshot.
    public func taskRemaining(_ task: TaskItem) -> Seconds? {
        guard let timer = task.timerSeconds else { return nil }
        let elapsed = task.id == activeTaskID ? activeTaskSeconds : ((try? store.taskSeconds(task: task.id)) ?? 0)
        return timer - elapsed
    }

    /// Live total for a task, so the list does not jump backwards between flushes.
    public func liveTaskSeconds(_ taskID: UUID) -> Seconds {
        let stored = (try? store.taskSeconds(task: taskID)) ?? 0
        return taskID == activeTaskID ? stored + taskUnwritten : stored
    }

    /// Date at which the next check-in is due, or nil when check-ins are off.
    public var nextCheckInAt: Date? {
        guard let interval = settings.checkInInterval else { return nil }
        let base = max(lastCommitAt, lastCheckInShownAt ?? .distantPast)
        return base.addingTimeInterval(interval)
    }

    // MARK: - Transitions

    /// idle/paused → tracking. Keeps the pending bucket and re-attributes it to `projectID`.
    public func start(projectID: UUID) {
        let now = clock.now()
        currentProjectID = projectID
        if pending != nil {
            pending?.projectID = projectID
        } else {
            pending = PendingTime(projectID: projectID, seconds: 0, since: lastCommitAt)
        }
        lastTickAt = now
        fraction = 0
        setStatus(.tracking(projectID: projectID, since: now))
    }

    // MARK: - Tasks (TD-01)

    /// Hands the clock to a task. The pending bucket is left exactly as it is: starting a task
    /// does not claim time that was accruing before it (TA-03).
    public func startTask(_ task: TaskItem) {
        flushTask()
        flushSlice()
        activeTaskID = task.id
        taskProjectID = task.projectID
        taskBaselineSeconds = (try? store.taskSeconds(task: task.id)) ?? 0
        taskAccruedSinceStart = 0
        taskUnwritten = 0
        taskFraction = 0
        taskTimerFired = false
        currentProjectID = task.projectID
        lastTickAt = clock.now()
        try? store.touchProject(id: task.projectID)
        setStatus(.tracking(projectID: task.projectID, since: clock.now()))
        broadcaster.send(.tasksChanged)
    }

    /// Stops the running task. Nothing is running afterwards: the bucket takes over again (TA-01).
    public func stopTask() {
        guard activeTaskID != nil else { return }
        flushTask()
        flushSlice()
        activeTaskID = nil
        taskProjectID = nil
        taskAccruedSinceStart = 0
        taskBaselineSeconds = 0
        taskFraction = 0
        taskTimerFired = false
        lastTickAt = clock.now()
        // The interval *resumes* when the task stops (TD-03): it does not fire the moment the
        // task ends just because it went unasked throughout.
        lastCheckInShownAt = clock.now()
        persist(force: true)
        broadcaster.send(.tasksChanged)
        broadcaster.send(.dataChanged)
    }

    /// Finishes the task and stops tracking it; its time stays where it was booked (T-04).
    public func finishTask(_ taskID: UUID) {
        if taskID == activeTaskID { flushTask() }
        flushSlice()
        try? store.completeTask(id: taskID)
        if taskID == activeTaskID { stopTask() }
        broadcaster.send(.tasksChanged)
        broadcaster.send(.dataChanged)
    }

    /// The task is going away; drop the clock without booking anything further.
    public func taskDeleted(_ taskID: UUID) {
        if taskID == activeTaskID {
            flushTask()
            flushSlice()
        flushSlice()
            stopTask()
        }
        broadcaster.send(.tasksChanged)
        broadcaster.send(.dataChanged)
    }

    /// Writes whatever the running task has accrued but not yet stored.
    private func flushTask() {
        guard let taskID = activeTaskID, let projectID = taskProjectID, taskUnwritten > 0 else { return }
        try? store.addTaskSeconds(task: taskID, project: projectID, day: today, taskUnwritten)
        taskUnwritten = 0
    }

    /// Adds `seconds` to today's total for `projectID`, resets the bucket and starts tracking (D-08).
    public func commit(projectID: UUID, seconds: Seconds) {
        let now = clock.now()
        if seconds > 0 {
            _ = try? store.addSeconds(project: projectID, day: today, seconds)
        }
        // The bucket was accruing against whatever was current; confirming it somewhere else
        // moves the marks with it, or the strip and the day list disagree (TLD-08).
        flushSlice()
        if let since = pending?.since ?? lastCommitAt as Date? {
            try? store.reassignSlices(from: since, to: now, project: projectID)
        }
        try? store.touchProject(id: projectID)
        pending = nil
        lastCommitAt = now
        start(projectID: projectID)
        broadcaster.send(.dataChanged)
    }

    /// Sets a stored total. Folds the pending bucket in first so it can not be double-counted (A-07).
    public func setTotal(projectID: UUID, day: LocalDate, seconds: Seconds) {
        autoCommitPending()
        try? store.setSeconds(project: projectID, day: day, seconds)
        broadcaster.send(.dataChanged)
    }

    /// Throws the pending bucket away and starts a fresh one; tracking continues (R-04).
    public func discardPending() {
        let now = clock.now()
        lastCommitAt = now
        fraction = 0
        if let projectID = pending?.projectID ?? currentProjectID {
            pending = PendingTime(projectID: projectID, seconds: 0, since: now)
        } else {
            pending = nil
        }
        persist()
        broadcaster.send(.tick(pending))
    }

    /// Pauses tracking. The bucket is preserved untouched (A-07).
    public func pause(until: Date, reason: PauseReason) {
        guard let projectID = currentProjectID else { return }
        flushTask()
        flushSlice()
        lastTickAt = clock.now()
        setStatus(.paused(projectID: projectID, until: until, reason: reason))
    }

    public func resume() {
        guard let projectID = currentProjectID else { return }
        start(projectID: projectID)
    }

    /// The project is about to be deleted: drop any time attributed to it and stop tracking it.
    /// Its pending bucket is discarded rather than committed — the entries go away with it.
    public func projectDeleted(_ projectID: UUID) {
        if taskProjectID == projectID {
            taskUnwritten = 0
            activeTaskID = nil
            taskProjectID = nil
        }
        if pending?.projectID == projectID {
            pending = nil
            fraction = 0
            lastCommitAt = clock.now()
        }
        if currentProjectID == projectID {
            currentProjectID = nil
            setStatus(.idle)
        } else {
            persist(force: true)
        }
        broadcaster.send(.dataChanged)
    }

    /// Flushes pending time and goes idle (quit, R-15).
    public func stop() {
        flushTask()
        flushSlice()
        activeTaskID = nil
        taskProjectID = nil
        autoCommitPending()
        pending = nil
        lastTickAt = clock.now()
        setStatus(.idle)
        broadcaster.send(.dataChanged)
    }

    // MARK: - Idle (A-05)

    /// The app measures how long the Mac has gone untouched and hands the number in; the engine
    /// decides what it means. Crossing the threshold rolls the idle stretch back out of whatever
    /// was accruing — it was never work — and pauses.
    public func checkIdle(systemIdleSeconds: Seconds) {
        guard let timeout = settings.idleTimeout else { return }

        if case .paused(_, _, .idle) = status {
            // Back at the keyboard: pick up where we left off.
            if systemIdleSeconds < timeout {
                resume()
                broadcaster.send(.pauseEnded)
            }
            return
        }

        guard status.isTracking, systemIdleSeconds >= timeout else { return }
        rollBack(seconds: systemIdleSeconds)
        // The stretch that was rolled back was not work, and the strip exists to say so: it is
        // repainted idle across the brackets it actually spanned.
        repaintIdle(seconds: systemIdleSeconds, endingAt: clock.now())
        pause(until: .distantFuture, reason: .idle)
    }

    /// Writes a past stretch as idle, bracket by bracket, taking the tracked seconds in each
    /// back out as it goes. Without the subtraction a rolled-back ten minutes would show as
    /// both worked and idle, which is the opposite of the point.
    private func repaintIdle(seconds: Seconds, endingAt end: Date) {
        guard seconds > 0 else { return }
        flushSlice()
        var remaining = seconds
        var cursor = end
        while remaining > 0 {
            let bucket = Timeline.bucketStart(for: cursor)
            let intoBucket = max(Int(cursor.timeIntervalSince(bucket)), 0)
            let chunk = min(remaining, max(intoBucket, 1))
            if let projectID = currentProjectID {
                try? store.addSlice(bucketStart: bucket, kind: .tracked, project: projectID, -chunk)
            }
            try? store.addSlice(bucketStart: bucket, kind: .idle, project: nil, chunk)
            remaining -= chunk
            cursor = bucket.addingTimeInterval(-1)
        }
    }

    /// One tick's worth of whatever the app is doing instead of working.
    private func recordAway(_ delta: TimeInterval) {
        guard delta > 0 else { return }
        awayFraction += delta
        let whole = Int(awayFraction)
        guard whole > 0 else { return }
        awayFraction -= Double(whole)
        if case .paused(_, _, let reason) = status {
            record(reason == .idle ? .idle : .paused, project: nil, seconds: whole)
        }
    }

    /// Seconds waiting to be written as one slice. Writing each second as it is counted cost
    /// a database round trip per tick, which the tick-cost test caught at once; a bracket's
    /// worth of the same thing is one row either way.
    private struct SliceBuffer {
        var bucketStart: Date
        var kind: SliceKind
        var projectID: UUID?
        var seconds: Seconds
    }

    private var sliceBuffer: SliceBuffer?

    private func record(_ kind: SliceKind, project: UUID?, seconds: Seconds) {
        guard seconds > 0 else { return }
        let bucket = Timeline.bucketStart(for: clock.now())
        if var buffer = sliceBuffer {
            if buffer.bucketStart == bucket, buffer.kind == kind, buffer.projectID == project {
                buffer.seconds += seconds
                sliceBuffer = buffer
                return
            }
            flushSlice()
        }
        sliceBuffer = SliceBuffer(bucketStart: bucket, kind: kind, projectID: project, seconds: seconds)
    }

    /// Writes the buffered slice. Anything that reads or rewrites slices has to call this
    /// first, or it works from a picture that is a bracket out of date.
    private func flushSlice() {
        defer { sliceBuffer = nil }
        guard let buffer = sliceBuffer, buffer.seconds > 0 else { return }
        try? store.addSlice(bucketStart: buffer.bucketStart, kind: buffer.kind,
                            project: buffer.projectID, buffer.seconds)
    }

    /// Removes time that turned out not to be work, from whichever counter took it.
    private func rollBack(seconds: Seconds) {
        guard seconds > 0 else { return }
        if let taskID = activeTaskID, let projectID = taskProjectID {
            let fromUnwritten = min(taskUnwritten, seconds)
            taskUnwritten -= fromUnwritten
            let remainder = seconds - fromUnwritten
            if remainder > 0 {
                try? store.addTaskSeconds(task: taskID, project: projectID, day: today, -remainder)
            }
            taskAccruedSinceStart = max(taskAccruedSinceStart - seconds, 0)
        } else if var bucket = pending {
            bucket.seconds = max(bucket.seconds - seconds, 0)
            pending = bucket
        }
        broadcaster.send(.dataChanged)
    }

    // MARK: - Ticking

    public func tick() {
        let now = clock.now()

        switch status {
        case .idle:
            lastTickAt = now
            return

        case .paused(_, let until, _):
            // Time spent away is the half of the record nothing else keeps, and it is the
            // half the strip exists to show (TL-01).
            let away = now.timeIntervalSince(lastTickAt)
            lastTickAt = now
            if away > 0, away <= TimeInterval(settings.maxGapSeconds) { recordAway(away) }
            if now >= until {
                resume()
                broadcaster.send(.pauseEnded)
            }
            return

        case .tracking:
            break
        }

        let delta = now.timeIntervalSince(lastTickAt)
        let maxGap = TimeInterval(settings.maxGapSeconds)

        // Sleep, freeze or a clock jump: the elapsed time is not work time (A-01).
        if delta < 0 || delta > maxGap {
            lastTickAt = now
            fraction = 0
            awayFraction = 0
            persist(force: true)
            broadcaster.send(.tick(pending))
            return
        }

        let previousDay = LocalDate(lastTickAt, calendar: clock.calendar)
        let currentDay = LocalDate(now, calendar: clock.calendar)

        if previousDay != currentDay {
            // Split at local midnight (D-06) and close the previous day.
            let midnight = currentDay.startOfDay(calendar: clock.calendar)
            let before = max(midnight.timeIntervalSince(lastTickAt), 0)
            let after = max(now.timeIntervalSince(midnight), 0)
            if activeTaskID != nil {
                accrueTask(before)
                flushTask(day: previousDay)
                accrueTask(after)
            } else {
                accrue(before)
                autoCommitPending(day: previousDay, since: midnight)
                accrue(after)
            }
        } else if activeTaskID != nil {
            accrueTask(delta)
        } else {
            accrue(delta)
        }

        lastTickAt = now
        checkTaskTimer()
        // A running task has already answered "what are you working on?" (TD-03).
        if activeTaskID == nil { checkCheckIn(now: now) }

        if now.timeIntervalSince(lastPersistAt) >= TimeInterval(settings.flushIntervalSeconds) {
            flushTask()
            flushSlice()
        flushSlice()
            persist(force: true)
        }
        broadcaster.send(.tick(pending))
    }

    private func accrue(_ delta: TimeInterval) {
        guard delta > 0, let projectID = currentProjectID else { return }
        if pending == nil {
            pending = PendingTime(projectID: projectID, seconds: 0, since: lastCommitAt)
        }
        fraction += delta
        let whole = Int(fraction)
        if whole > 0 {
            fraction -= Double(whole)
            let updated = min((pending?.seconds ?? 0) + whole, secondsPerDay)
            pending?.seconds = updated
            record(.tracked, project: projectID, seconds: whole)
        }
    }

    private func accrueTask(_ delta: TimeInterval) {
        guard delta > 0, activeTaskID != nil else { return }
        taskFraction += delta
        let whole = Int(taskFraction)
        guard whole > 0 else { return }
        taskFraction -= Double(whole)
        taskAccruedSinceStart += whole
        taskUnwritten += whole
        record(.tracked, project: taskProjectID, seconds: whole)
    }

    /// Fires once when a timed task reaches zero; "keep working" clears the timer so it stays quiet.
    private func checkTaskTimer() {
        guard !taskTimerFired, let taskID = activeTaskID,
              let task = try? store.task(id: taskID), let timer = task.timerSeconds,
              activeTaskSeconds >= timer else { return }
        taskTimerFired = true
        flushTask()
        flushSlice()
        broadcaster.send(.taskTimerExpired(taskID))
    }

    private func flushTask(day: LocalDate) {
        guard let taskID = activeTaskID, let projectID = taskProjectID, taskUnwritten > 0 else { return }
        try? store.addTaskSeconds(task: taskID, project: projectID, day: day, taskUnwritten)
        taskUnwritten = 0
    }

    private func checkCheckIn(now: Date) {
        guard let due = nextCheckInAt, now >= due else { return }
        lastCheckInShownAt = now
        persist(force: true)
        broadcaster.send(.checkInDue)
    }

    /// Marks a check-in as shown, so the next one is due one interval later.
    public func noteCheckInShown() {
        lastCheckInShownAt = clock.now()
        persist(force: true)
    }

    // MARK: - Auto-commit (A-07)

    /// Writes the pending bucket to its project without touching the check-in schedule.
    private func autoCommitPending(day: LocalDate? = nil, since: Date? = nil) {
        let now = clock.now()
        let target = day ?? today
        if let pending, pending.seconds > 0 {
            _ = try? store.addSeconds(project: pending.projectID, day: target, pending.seconds)
            try? store.touchProject(id: pending.projectID)
        }
        lastCommitAt = since ?? now
        fraction = 0
        if let projectID = pending?.projectID ?? currentProjectID, !status.isIdle {
            pending = PendingTime(projectID: projectID, seconds: 0, since: since ?? now)
        } else {
            pending = nil
        }
        persist(force: true)
    }

    // MARK: - Persistence

    /// Restores across launches. Crashed pending time is recovered, then tracking either picks
    /// up where it left off or waits, depending on `startTrackingOnLaunch`.
    public func restore() {
        guard let state = try? store.loadEngineState() else {
            persist(force: true)
            return
        }

        currentProjectID = state.currentProjectID
        lastCommitAt = state.lastCommitAt ?? clock.now()
        lastCheckInShownAt = state.lastCheckInAt

        // A crash left tracking state behind: recover the persisted bucket into its own day.
        if let seconds = state.pendingSeconds, seconds > 0,
           let projectID = state.pendingProjectID ?? state.currentProjectID {
            let day = LocalDate(state.lastTickAt ?? state.pendingSince ?? clock.now(), calendar: clock.calendar)
            _ = try? store.addSeconds(project: projectID, day: day, seconds)
            broadcaster.send(.dataChanged)
        }

        pending = nil
        activeTaskID = nil                              // picking a task back up is a decision (T-09)
        taskProjectID = nil
        lastTickAt = clock.now()

        // Time while the app was not running is never work time, so tracking always restarts
        // from a fresh bucket at "now" — including the check-in clock.
        if settings.startTrackingOnLaunch,
           let projectID = currentProjectID,
           (try? store.project(id: projectID)) != nil {
            lastCommitAt = clock.now()
            start(projectID: projectID)
        } else {
            status = .idle
            persist(force: true)
            broadcaster.send(.statusChanged(status))
        }
    }

    private func setStatus(_ new: TrackingStatus) {
        let changed = status != new
        status = new
        persist(force: true)
        if changed { broadcaster.send(.statusChanged(new)) }
    }

    private func persist(force: Bool = false) {
        let now = clock.now()
        guard force || now.timeIntervalSince(lastPersistAt) >= TimeInterval(settings.flushIntervalSeconds) else { return }
        lastPersistAt = now

        var state = PersistedEngineState()
        switch status {
        case .idle:
            state.kind = .idle
        case .tracking(let id, let since):
            state.kind = .tracking
            state.trackingSince = since
            state.currentProjectID = id
        case .paused(let id, let until, let reason):
            state.kind = .paused
            state.currentProjectID = id
            state.pausedUntil = until
            state.pauseReason = reason
        }
        state.currentProjectID = currentProjectID ?? state.currentProjectID
        state.lastTickAt = lastTickAt
        state.pendingProjectID = pending?.projectID
        state.pendingSeconds = pending?.seconds
        state.pendingSince = pending?.since
        state.lastCheckInAt = lastCheckInShownAt
        state.lastCommitAt = lastCommitAt
        try? store.saveEngineState(state)
    }

    // MARK: - Shutdown / testing hooks

    /// Forces a state write.
    public func flush() { persist(force: true) }

    /// Closes every `events` stream (app teardown; also makes event assertions terminate in tests).
    public func finishEvents() { broadcaster.finish() }
}

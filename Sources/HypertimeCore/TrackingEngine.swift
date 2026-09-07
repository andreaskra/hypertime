import Foundation

public enum TrackingEvent: Sendable, Equatable {
    case statusChanged(TrackingStatus)
    case tick(PendingTime?)
    case checkInDue
    case pauseEnded
    /// Stored totals changed (commit, manual edit, auto-commit).
    case dataChanged
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

    private var lastTickAt: Date
    private var lastCommitAt: Date
    public private(set) var lastCheckInShownAt: Date?
    private var lastPersistAt: Date
    private var fraction: Double = 0

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
        return min(total, secondsPerDay)
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

    /// Adds `seconds` to today's total for `projectID`, resets the bucket and starts tracking (D-08).
    public func commit(projectID: UUID, seconds: Seconds) {
        let now = clock.now()
        if seconds > 0 {
            _ = try? store.addSeconds(project: projectID, day: today, seconds)
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
        lastTickAt = clock.now()
        setStatus(.paused(projectID: projectID, until: until, reason: reason))
    }

    public func resume() {
        guard let projectID = currentProjectID else { return }
        start(projectID: projectID)
    }

    /// Flushes pending time and goes idle (quit, R-15).
    public func stop() {
        autoCommitPending()
        pending = nil
        lastTickAt = clock.now()
        setStatus(.idle)
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
            lastTickAt = now
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
            accrue(before)
            autoCommitPending(day: previousDay, since: midnight)
            accrue(after)
        } else {
            accrue(delta)
        }

        lastTickAt = now
        checkCheckIn(now: now)

        if now.timeIntervalSince(lastPersistAt) >= TimeInterval(settings.flushIntervalSeconds) {
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
        }
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

    /// Restores across launches. Per A-03 the app starts idle; crashed pending time is recovered.
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
        status = .idle
        lastTickAt = clock.now()
        persist(force: true)
        broadcaster.send(.statusChanged(status))
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

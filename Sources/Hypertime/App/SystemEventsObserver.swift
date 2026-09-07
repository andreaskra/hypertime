import AppKit
import HypertimeCore

/// Sleep/wake, screen lock/unlock, day and time-zone changes (§6.7, A-01).
@MainActor
final class SystemEventsObserver {
    private let model: AppModel
    private var tokens: [NSObjectProtocol] = []

    /// Called when tracking resumed by itself and the user should see the check-in.
    var onResumed: (() -> Void)?
    var onDayChanged: (() -> Void)?

    init(model: AppModel) {
        self.model = model

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] in self?.suspend(reason: .systemSleep) }
        observe(workspace, NSWorkspace.didWakeNotification) { [weak self] in self?.wake(reason: .systemSleep) }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] in self?.suspend(reason: .screenLock) }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] in self?.wake(reason: .screenLock) }

        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { [weak self] in self?.suspend(reason: .screenLock) }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in self?.wake(reason: .screenLock) }

        let center = NotificationCenter.default
        observe(center, .NSCalendarDayChanged) { [weak self] in
            self?.model.engine.tick()
            self?.onDayChanged?()
        }
        observe(center, .NSSystemTimeZoneDidChange) { [weak self] in
            self?.model.engine.tick()
            self?.onDayChanged?()
        }
    }

    deinit {
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            DistributedNotificationCenter.default().removeObserver(token)
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ handler: @escaping () -> Void) {
        tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { handler() }
        })
    }

    private func observe(_ center: DistributedNotificationCenter, _ name: Notification.Name, _ handler: @escaping () -> Void) {
        tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { handler() }
        })
    }

    /// Time while asleep or locked is not work time (A-01).
    private func suspend(reason: PauseReason) {
        guard model.settings.pauseOnSleepAndLock, model.engine.status.isTracking else { return }
        model.engine.flush()
        model.engine.pause(until: .distantFuture, reason: reason)
        Log.engine.info("Paused (\(reason.rawValue, privacy: .public))")
    }

    private func wake(reason: PauseReason) {
        guard case .paused(_, _, let current) = model.engine.status, current == reason else { return }
        model.engine.resume()
        Log.engine.info("Resumed after \(reason.rawValue, privacy: .public)")
        onResumed?()
    }
}

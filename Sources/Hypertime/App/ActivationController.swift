import AppKit

/// Activation policy, Cmd+Tab handling and focus restore (§6.1, §6.2).
@MainActor
final class ActivationController {
    /// True while *we* are activating the app, so `applicationDidBecomeActive` can tell a
    /// Cmd+Tab activation apart from one we triggered ourselves.
    private(set) var isSelfActivating = false

    /// The last application that was activated and is not us (R-09).
    private(set) var previousApp: NSRunningApplication?

    private var observer: NSObjectProtocol?

    init() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated { self?.previousApp = app }
        }
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    func applyActivationPolicy(showInDock: Bool) {
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
    }

    /// Activates us without confusing the Cmd+Tab detection.
    func activate(_ body: () -> Void) {
        isSelfActivating = true
        NSApp.activate()
        body()
        // The activation notification arrives asynchronously; keep the flag up until it has landed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.isSelfActivating = false }
    }

    /// Hands keyboard focus back to whatever the user was using before (R-09).
    func returnFocus() {
        guard let previous = previousApp, !previous.isTerminated else {
            NSApp.hide(nil)
            return
        }
        NSApp.yieldActivation(to: previous)
        previous.activate()
    }
}

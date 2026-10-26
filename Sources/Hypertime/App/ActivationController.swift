import AppKit

/// Activation policy, Cmd+Tab handling and focus restore (§6.1, §6.2).
@MainActor
final class ActivationController {
    /// `--self-test` drives the real windows, which means the real windows appear — on top of
    /// whatever the person at the keyboard is doing, every time it runs. Under this flag the
    /// app never takes activation and its windows are drawn fully transparent: everything the
    /// checks look at (frames, key status, first responder, field editors) still behaves
    /// exactly as it does on screen, because none of it depends on being *visible*.
    static var isHeadless = CommandLine.arguments.contains("--self-test")

    /// Makes a window inert for the duration of a headless run: invisible, transparent to the
    /// mouse, and never raised above what the person at the keyboard is actually doing. Alpha
    /// alone was not enough — an invisible window ordered front still swallows the cursor.
    static func neutralise(_ window: NSWindow?) {
        guard isHeadless, let window else { return }
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.level = .normal
        window.collectionBehavior.insert(.ignoresCycle)
        window.collectionBehavior.insert(.stationary)
    }

    /// Orders a window in without taking it, or the app, in front of anything.
    static func present(_ window: NSWindow) {
        neutralise(window)
        guard isHeadless else { return }
        window.orderFrontRegardless()
        window.makeKey()                    // key inside this app only; the system focus stays put
    }

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
        // A headless run never wants a Dock tile or a chance of being brought to the front.
        NSApp.setActivationPolicy(showInDock && !Self.isHeadless ? .regular : .accessory)
    }

    /// Activates us without confusing the Cmd+Tab detection.
    func activate(_ body: () -> Void) {
        isSelfActivating = true
        if !Self.isHeadless { NSApp.activate() }
        body()
        // The activation notification arrives asynchronously; keep the flag up until it has landed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.isSelfActivating = false }
    }

    /// Hands keyboard focus back to whatever the user was using before (R-09).
    func returnFocus() {
        guard !Self.isHeadless else { return }
        guard let previous = previousApp, !previous.isTerminated else {
            NSApp.hide(nil)
            return
        }
        NSApp.yieldActivation(to: previous)
        previous.activate()
    }
}

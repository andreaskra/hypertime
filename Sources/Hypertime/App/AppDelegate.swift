import AppKit
import SwiftUI
import HypertimeCore

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var activation: ActivationController!
    private var statusItem: StatusItemController!
    private var panel: CheckInPanelController!
    private var reports: ReportsWindowController!
    private var settingsWindow: SettingsWindowController!
    private var export: ExportController!
    private var systemEvents: SystemEventsObserver!
    private var settingsTask: Task<Void, Never>?

    private var pausePopover: NSPopover?

    /// True until the launch activation has been consumed, so it is not mistaken for Cmd+Tab.
    private var isLaunching = true

    /// Process start, used for the launch-time budget (< 300 ms to the status item).
    static let launchDate = NSRunningApplication.current.launchDate ?? Date()

    static func main() {
        _ = launchDate                      // pin the measurement to process start
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            model = try AppModel()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Hypertime could not open its database."
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        activation = ActivationController()
        activation.applyActivationPolicy(showInDock: model.settings.showInDockAndCmdTab)
        MainMenu.install(target: self)

        panel = CheckInPanelController(model: model, activation: activation)
        statusItem = StatusItemController(model: model)
        reports = ReportsWindowController(model: model, activation: activation)
        settingsWindow = SettingsWindowController(model: model, activation: activation)
        export = ExportController(model: model, activation: activation)
        systemEvents = SystemEventsObserver(model: model)

        wire()
        LoginItemController.synchronise(settings: model.settings)
        model.start()

        let launchMilliseconds = Date().timeIntervalSince(Self.launchDate) * 1000
        Log.app.notice("Status item ready \(launchMilliseconds, format: .fixed(precision: 0)) ms after launch")
        if let quarantined = model.store.recoveredFromCorruption {
            reportDatabaseRecovery(quarantined)
        }

        if let index = CommandLine.arguments.firstIndex(of: "--render-icon"),
           index + 1 < CommandLine.arguments.count {
            exit(IconRenderer.run(directory: CommandLine.arguments[index + 1]) ? 0 : 1)
        }

        if let index = CommandLine.arguments.firstIndex(of: "--screenshots"),
           index + 1 < CommandLine.arguments.count {
            ScreenshotRenderer.run(model: model, directory: CommandLine.arguments[index + 1])
            return
        }

        if CommandLine.arguments.contains("--self-test") {
            SelfTest.run(model: model, statusItem: statusItem, panel: panel)
            return
        }

        // Launch shows the popup without stealing focus (A-03, R-08).
        panel.show(mode: .passive)
        DispatchQueue.main.async { [weak self] in self?.isLaunching = false }
        Log.app.info("Launched")
    }

    /// The database could not be opened and was replaced. Rare and destructive enough to be worth
    /// interrupting for — routine errors stay inline (§9).
    private func reportDatabaseRecovery(_ quarantinedPath: String) {
        Log.store.error("Recovered from an unreadable database; old file at \(quarantinedPath, privacy: .public)")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Hypertime started with a new database."
        alert.informativeText = "The existing database could not be read, so it was moved aside and a new one was created. "
            + "Your previous file is still on disk:\n\n" + quarantinedPath
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Show in Finder")
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: quarantinedPath)])
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        settingsTask?.cancel()
        model?.shutDown()
    }

    /// Cmd+Tab into the app (R-10) and Dock icon clicks show the popup with focus.
    func applicationDidBecomeActive(_ notification: Notification) {
        guard !isLaunching, activation?.isSelfActivating == false else { return }
        // Coming back to Reports or Settings should not pop the check-in over them.
        if let key = NSApp.keyWindow, !(key is CheckInPanel) { return }
        panel.show(mode: .focused)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.show(mode: .focused)
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: - Wiring

    private func wire() {
        panel.anchorProvider = { [weak self] in self?.statusItem.button }
        panel.onPauseRequested = { [weak self] view in
            guard let self else { return }
            // Anchored under the pause icon button in the popup header.
            let anchor = NSRect(x: view.bounds.maxX - 36, y: view.bounds.maxY - 36, width: 20, height: 20)
            self.showPausePopover(anchor: anchor, in: view)
        }

        statusItem.onToggle = { [weak self] in self?.panel.toggle() }
        statusItem.onShowReports = { [weak self] in self?.reports.show() }
        statusItem.onShowSettings = { [weak self] in self?.settingsWindow.show() }
        statusItem.onCustomPause = { [weak self] in self?.askForCustomPause() }
        statusItem.onExport = { [weak self] scope in
            guard let self else { return }
            if let scope { self.export.exportDirectly(scope: scope) } else { self.export.show(period: nil) }
        }

        reports.onExport = { [weak self] period in self?.export.show(period: period) }
        export.hostWindowProvider = { [weak self] in self?.reports.window }

        model.onCheckInDue = { [weak self] in self?.panel.show(mode: .passive) }
        model.onPauseEnded = { [weak self] in self?.panel.show(mode: .passive) }
        model.onTick = { [weak self] in
            self?.panel.tick()
            self?.statusItem.refresh()
        }
        model.onStatusChanged = { [weak self] in self?.statusItem.refresh() }
        model.onDataChanged = { [weak self] in
            self?.panel.refresh()
            self?.reports.refresh()
        }

        systemEvents.onResumed = { [weak self] in self?.panel.show(mode: .passive) }
        systemEvents.onDayChanged = { [weak self] in
            self?.panel.refresh()
            self?.reports.refresh()
        }

        settingsWindow.viewModel.onActivationPolicyChanged = { [weak self] in
            guard let self else { return }
            self.activation.applyActivationPolicy(showInDock: self.model.settings.showInDockAndCmdTab)
        }
        settingsWindow.viewModel.onAppearanceChanged = { [weak self] in
            self?.statusItem.refresh()
            self?.panel.refresh()
            self?.reports.refresh()
        }
    }

    // MARK: - Menu actions

    @objc func showReports(_ sender: Any?) { reports.show() }
    @objc func showSettings(_ sender: Any?) { settingsWindow.show() }

    /// A-pause: the pause chooser popover (chips + custom duration, same parser).
    private func showPausePopover(anchor: NSRect, in view: NSView) {
        pausePopover?.close()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.contentViewController = NSHostingController(rootView: PausePopoverView(
            morningHour: model.settings.morningHour,
            validate: { [weak self] text in
                guard let self, let parsed = try? self.model.parser.parse(text) else { return nil }
                return abs(parsed.seconds)
            },
            onPick: { [weak self] preset, seconds in
                guard let self else { return }
                self.model.pause(preset, customDuration: seconds)
                self.pausePopover?.close()
                self.pausePopover = nil
                self.statusItem.refresh()
                self.panel.refresh()
            }
        ))
        popover.show(relativeTo: anchor, of: view, preferredEdge: .minY)
        pausePopover = popover
    }

    private func askForCustomPause() {
        guard let button = statusItem.button else { return }
        showPausePopover(anchor: button.bounds, in: button)
    }
}

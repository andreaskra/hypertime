import AppKit
import SwiftUI
import HypertimeCore

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var model: AppModel!
    private var activation: ActivationController!
    private var statusItem: StatusItemController!
    private var panel: CheckInPanelController!
    private var reports: ReportsWindowController!
    private var settingsWindow: SettingsWindowController!
    private var export: ExportController!
    private var systemEvents: SystemEventsObserver!
    private let loadItems = LoadStatusItems()
    private var settingsTask: Task<Void, Never>?

    private var pausePopover: NSPopover?
    private var menuPopover: NSPopover?
    private var dayPickerPopover: NSPopover?
    private var taskMenuPopover: NSPopover?

    /// True until the launch activation has been consumed, so it is not mistaken for Cmd+Tab.
    private var isLaunching = true

    /// Process start, for the launch-time budget (< 300 ms to the status item). Nil when the
    /// binary was run directly instead of launched, where there is no pre-main figure to have.
    static let launchDate = NSRunningApplication.current.launchDate
    /// Entry into our own code: everything before this is dyld and runtime setup, which the app
    /// can only influence by linking less.
    static let mainDate = Date()

    static func main() {
        _ = launchDate                      // pin the measurement to process start
        _ = mainDate
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Before the database is touched: rendering an icon needs no model, and opening the
        // real database for it would fail whenever the app is already running.
        if let index = CommandLine.arguments.firstIndex(of: "--render-icon"),
           index + 2 < CommandLine.arguments.count {
            exit(IconRenderer.run(source: CommandLine.arguments[index + 2],
                                  into: CommandLine.arguments[index + 1]) ? 0 : 1)
        }

        do {
            model = try AppModel()
        } catch StoreError.alreadyOpen {
            // Two tracking engines on one database book the same time twice over. The store
            // refuses to open at all, so nothing has been restored and nothing written.
            let alert = NSAlert()
            alert.messageText = "Hypertime is already running."
            alert.informativeText = "Another copy of Hypertime has this database open. "
                + "Only one can track time at a time, so this one will close."
            alert.runModal()
            NSApp.terminate(nil)
            return
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
        applyDockIcon()

        panel = CheckInPanelController(model: model, activation: activation)
        statusItem = StatusItemController(model: model)
        reports = ReportsWindowController(model: model, activation: activation)
        settingsWindow = SettingsWindowController(model: model, activation: activation)
        export = ExportController(model: model, activation: activation)
        systemEvents = SystemEventsObserver(model: model)

        wire()
        model.start()                       // also schedules the post-launch housekeeping

        let setUp = Date().timeIntervalSince(Self.mainDate) * 1000
        let total = Self.launchDate.map { Date().timeIntervalSince($0) * 1000 } ?? setUp
        Log.app.notice("Status item ready \(total, format: .fixed(precision: 0)) ms after launch, \(setUp, format: .fixed(precision: 0)) ms of it after main()")
        if let quarantined = model.store.recoveredFromCorruption {
            reportDatabaseRecovery(quarantined)
        }

        if let index = CommandLine.arguments.firstIndex(of: "--screenshots"),
           index + 1 < CommandLine.arguments.count {
            ScreenshotRenderer.run(model: model, directory: CommandLine.arguments[index + 1])
            return
        }

        if CommandLine.arguments.contains("--self-test") {
            SelfTest.run(model: model, statusItem: statusItem, panel: panel, settingsWindow: settingsWindow)
            return
        }

        // Launch shows the popup without stealing focus (A-03, R-08).
        showLaunchPopup()
        DispatchQueue.main.async { [weak self] in self?.isLaunching = false }
        Log.app.info("Launched")
    }

    /// Point the Dock tile at the icon inside the bundle we are actually running from. The Dock
    /// caches the tile it drew for a bundle, and rebuilding one in place — which every
    /// `build-app.sh` does — leaves it drawing whatever it cached first, which during development
    /// is the generic icon from before there was one. Setting it explicitly costs nothing and
    /// means the tile never disagrees with the build.
    private func applyDockIcon() {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: url) else { return }
        NSApp.applicationIconImage = icon
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

    /// The menu bar places the status item a beat after it is created; showing the popup before
    /// that anchors it to an off-screen frame and it lands in a corner. Waits up to a second.
    private func showLaunchPopup(attempt: Int = 0) {
        guard statusItem.screenFrame == nil, attempt < 20 else {
            panel.show(mode: .passive)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.showLaunchPopup(attempt: attempt + 1)
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
        panel.anchorProvider = { [weak self] in self?.statusItem.screenFrame }
        panel.onMenuRequested = { [weak self] view in
            guard let self else { return }
            let anchor = NSRect(x: view.bounds.maxX - 36, y: view.bounds.maxY - 36, width: 20, height: 20)
            self.showOverflowMenu(anchor: anchor, in: view)
        }
        panel.onDayPickerRequested = { [weak self] view in
            guard let self else { return }
            // Anchored on the calendar button, which sits on the day list's header row.
            let anchor = NSRect(x: 24, y: self.panel.dayHeaderY(in: view), width: 20, height: 18)
            self.showDayPicker(anchor: anchor, in: view)
        }
        panel.onTaskMenuRequested = { [weak self] task, anchor, view in
            self?.showTaskMenu(task, anchor: anchor, in: view)
        }
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
        model.onTaskTimerExpired = { [weak self] taskID in self?.panel.showTimerExpired(taskID) }
        model.onSystemLoad = { [weak self] load in self?.loadItems.update(load: load) }

        // The figures the user pinned to the menu bar last time, and a way back to the popup
        // from them — a number in the menu bar that does nothing when clicked is a tease.
        loadItems.onClick = { [weak self] in self?.panel.toggle() }
        loadItems.update(metrics: model.settings.menuBarMetrics)
        loadItems.update(load: model.systemLoad)
        panel.viewModel.onMenuBarMetricsChanged = { [weak self] in
            guard let self else { return }
            self.loadItems.update(metrics: self.model.settings.menuBarMetrics)
            self.loadItems.update(load: self.model.systemLoad)
        }
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

    func popoverDidClose(_ notification: Notification) {
        panel.isPresentingPopover = false
    }

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
        present(popover, anchor: anchor, in: view)
        pausePopover = popover
    }

    /// Reports and Settings, reachable from the popup itself.
    private func showOverflowMenu(anchor: NSRect, in view: NSView) {
        menuPopover?.close()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.contentViewController = NSHostingController(rootView: OverflowMenuView(groups: [
            [
                OverflowMenuView.Item("Reports…", symbol: Tokens.Icons.reports) { [weak self] in
                    self?.menuPopover?.close()
                    self?.reports.show()
                },
                OverflowMenuView.Item("Settings…", symbol: Tokens.Icons.settings) { [weak self] in
                    self?.menuPopover?.close()
                    self?.settingsWindow.show()
                },
            ],
            [
                OverflowMenuView.Item("Quit Hypertime", symbol: Tokens.Icons.quit, isDestructive: true) {
                    NSApp.terminate(nil)
                },
            ],
        ]))
        present(popover, anchor: anchor, in: view)
        menuPopover = popover
    }

    /// Jump to any day; days with tracked time are dotted.
    private func showDayPicker(anchor: NSRect, in view: NSView) {
        dayPickerPopover?.close()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.contentViewController = NSHostingController(rootView: DayPickerView(
            viewModel: panel.viewModel,
            onPick: { [weak self] day in
                self?.panel.viewModel.showDay(day)
                self?.dayPickerPopover?.close()
            }
        ))
        present(popover, anchor: anchor, in: view)
        dayPickerPopover = popover
    }

    /// A task's ⋯ menu, in the app's styling rather than a system menu.
    private func showTaskMenu(_ task: TaskItem, anchor: NSRect, in view: NSView) {
        taskMenuPopover?.close()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.contentViewController = NSHostingController(rootView: TaskMenuView(
            viewModel: panel.viewModel,
            task: task,
            onClose: { [weak self] in
                self?.taskMenuPopover?.close()
                self?.taskMenuPopover = nil
            }
        ))
        present(popover, anchor: anchor, in: view)
        taskMenuPopover = popover
    }

    /// Popovers steal key status from the panel; tell it so it does not dismiss underneath them.
    private func present(_ popover: NSPopover, anchor: NSRect, in view: NSView) {
        panel.isPresentingPopover = true
        popover.delegate = self
        popover.show(relativeTo: anchor, of: view, preferredEdge: .minY)
    }

    private func askForCustomPause() {
        guard let button = statusItem.button else { return }
        showPausePopover(anchor: button.bounds, in: button)
    }
}

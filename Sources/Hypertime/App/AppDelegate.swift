import AppKit
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

    /// True until the launch activation has been consumed, so it is not mistaken for Cmd+Tab.
    private var isLaunching = true

    static func main() {
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

        if CommandLine.arguments.contains("--self-test") {
            SelfTest.run(model: model, statusItem: statusItem, panel: panel)
            return
        }

        // Launch shows the popup without stealing focus (A-03, R-08).
        panel.show(mode: .passive)
        DispatchQueue.main.async { [weak self] in self?.isLaunching = false }
        Log.app.info("Launched")
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
        panel.onPauseRequested = { [weak self] view in self?.showPauseMenu(relativeTo: view) }

        statusItem.onToggle = { [weak self] in self?.panel.toggle() }
        statusItem.onShowReports = { [weak self] in self?.reports.show() }
        statusItem.onShowSettings = { [weak self] in self?.settingsWindow.show() }
        statusItem.onCustomPause = { [weak self] in self?.askForCustomPause() }
        statusItem.onExport = { [weak self] scope in
            guard let self else { return }
            if let scope { self.export.exportDirectly(scope: scope) } else { self.export.show(period: nil) }
        }

        reports.onExport = { [weak self] period in self?.export.show(period: period) }

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

    private func showPauseMenu(relativeTo view: NSView) {
        let menu = NSMenu()
        for preset in [PausePreset.m15, .m30, .h1, .h2, .untilMorning] {
            let item = NSMenuItem(title: preset.title(morningHour: model.settings.morningHour),
                                  action: #selector(pauseFromMenu(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = preset.rawValue
            menu.addItem(item)
        }
        let custom = NSMenuItem(title: "Custom…", action: #selector(askForCustomPause), keyEquivalent: "")
        custom.target = self
        menu.addItem(custom)
        menu.popUp(positioning: nil, at: NSPoint(x: 12, y: view.bounds.height - 40), in: view)
    }

    @objc private func pauseFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let preset = PausePreset(rawValue: raw) else { return }
        model.pause(preset)
        statusItem.refresh()
        panel.refresh()
    }

    @objc private func askForCustomPause() {
        let alert = NSAlert()
        alert.messageText = "Pause tracking for how long?"
        alert.informativeText = "For example 45m, 1:30 or 2h."
        alert.addButton(withTitle: "Pause")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: "45m")
        field.frame = NSRect(x: 0, y: 0, width: 200, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn,
              let parsed = try? model.parser.parse(field.stringValue) else { return }
        model.pause(.custom, customDuration: abs(parsed.seconds))
        statusItem.refresh()
        panel.refresh()
    }
}

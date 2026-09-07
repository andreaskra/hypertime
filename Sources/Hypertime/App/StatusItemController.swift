import AppKit
import HypertimeCore

/// Menu bar presence (R-01, §6.6). Left click toggles the popup, right click opens the menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    var onToggle: (() -> Void)?
    var onShowReports: (() -> Void)?
    var onShowSettings: (() -> Void)?
    var onExport: ((ExportScope?) -> Void)?
    var onCustomPause: (() -> Void)?

    var button: NSStatusBarButton? { statusItem.button }

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(buttonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }
        menu.delegate = self
        refresh()
    }

    // MARK: - Appearance

    func refresh() {
        guard let button = statusItem.button else { return }
        let state: MenuBarGlyph.State
        switch model.engine.status {
        case .idle: state = .idle
        case .tracking: state = .tracking
        case .paused: state = .paused
        }
        button.image = MenuBarGlyph.image(state)

        if model.settings.showElapsedInMenuBar, let project = model.currentProject {
            let seconds = model.liveSeconds(project: project.id, day: model.today)
            button.title = " " + model.formatter.string(seconds, style: .clockNoSeconds)
            button.font = Tokens.Typography.menuBarTime.nsFont
        } else {
            button.title = ""
        }
        button.toolTip = model.statusSummary()
    }

    // MARK: - Clicks

    @objc private func buttonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
            || (event?.modifierFlags.contains(.control) ?? false)

        if isRightClick {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            onToggle?()
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let title = NSMenuItem(title: model.statusSummary(), action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        if model.engine.status.isPaused {
            menu.addItem(item("Resume", #selector(resume)))
        } else {
            let pauseItem = NSMenuItem(title: "Pause", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for preset in [PausePreset.m15, .m30, .h1, .h2, .untilMorning] {
                let entry = item(preset.title(morningHour: model.settings.morningHour), #selector(pause(_:)))
                entry.representedObject = preset.rawValue
                submenu.addItem(entry)
            }
            submenu.addItem(item("Custom…", #selector(customPause)))
            pauseItem.submenu = submenu
            menu.addItem(pauseItem)
        }

        menu.addItem(.separator())
        menu.addItem(item("Reports…", #selector(showReports)))

        let exportItem = NSMenuItem(title: "Export CSV", action: nil, keyEquivalent: "")
        let exportMenu = NSMenu()
        let today = model.today
        let month = item("This Month", #selector(exportMonth))
        month.representedObject = today
        exportMenu.addItem(month)
        exportMenu.addItem(item("This Year", #selector(exportYear)))
        exportMenu.addItem(item("Date Range…", #selector(exportRange)))
        exportItem.submenu = exportMenu
        menu.addItem(exportItem)

        menu.addItem(item("Settings…", #selector(showSettings)))
        menu.addItem(.separator())

        let login = item("Launch at Login", #selector(toggleLoginItem))
        login.state = LoginItemController.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(item("Quit Hypertime", #selector(quit)))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: - Actions

    @objc private func resume() { model.engine.resume(); refresh() }

    @objc private func pause(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let preset = PausePreset(rawValue: raw) else { return }
        model.pause(preset)
        refresh()
    }

    @objc private func customPause() { onCustomPause?() }
    @objc private func showReports() { onShowReports?() }
    @objc private func showSettings() { onShowSettings?() }

    @objc private func exportMonth() {
        let today = model.today
        onExport?(.month(year: today.year, month: today.month))
    }

    @objc private func exportYear() { onExport?(.year(model.today.year)) }
    @objc private func exportRange() { onExport?(nil) }

    @objc private func toggleLoginItem() {
        LoginItemController.setEnabled(!LoginItemController.isEnabled, settings: model.settings)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

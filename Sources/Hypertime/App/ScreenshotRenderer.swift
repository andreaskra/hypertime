import AppKit
import SwiftUI
import HypertimeCore

/// `--screenshots <dir>`: renders every screen in light/dark, Increase Contrast and Reduce
/// Transparency into PNGs for the Phase 2 design QA pass (§7.6).
///
/// Rendering goes through `cacheDisplay(in:to:)` on a real hosting view, so AppKit content
/// (the text fields) is included. Window-server materials cannot be captured off-screen, so
/// glass surfaces render as their Reduce Transparency fallback; live glass must be checked on
/// screen.
@MainActor
enum ScreenshotRenderer {

    struct Mode {
        let suffix: String
        let appearance: NSAppearance.Name
    }

    static let modes = [
        Mode(suffix: "light", appearance: .aqua),
        Mode(suffix: "dark", appearance: .darkAqua),
        Mode(suffix: "light-contrast", appearance: .accessibilityHighContrastAqua),
        Mode(suffix: "dark-contrast", appearance: .accessibilityHighContrastDarkAqua),
    ]

    static func run(model: AppModel, directory: String) {
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        let checkIn = CheckInViewModel(model: model)
        let presentation = PanelPresentation()
        presentation.isAppeared = true
        presentation.mode = .focused

        let reports = ReportsViewModel(model: model)
        let settings = SettingsViewModel(model: model)
        let export = ExportViewModel(model: model, initialPeriod: .month(year: model.today.year, month: model.today.month))

        // Popup states. Tracking is started so the states match the artboards; the live amount
        // is a fixture value because the renderer never ticks the clock.
        if let project = model.projects().first {
            model.engine.start(projectID: project.id)
        }

        checkIn.prepareForShow()
        checkIn.timeText = "0:12:34"
        render("popup-hero", AnyView(CheckInView(viewModel: checkIn, presentation: presentation)), in: url)

        checkIn.focus = .project
        checkIn.projectTextChanged("e")
        render("popup-dropdown", AnyView(CheckInView(viewModel: checkIn, presentation: presentation)), in: url)

        checkIn.prepareForShow()
        checkIn.focus = .time
        checkIn.timeTextChanged("0:45")
        render("popup-amount-editing", AnyView(CheckInView(viewModel: checkIn, presentation: presentation)), in: url)

        checkIn.timeTextChanged("nonsense")
        checkIn.commit()
        render("popup-amount-invalid", AnyView(CheckInView(viewModel: checkIn, presentation: presentation)), in: url)

        checkIn.prepareForShow()
        checkIn.timeText = "0:12:34"
        if let first = checkIn.todayRows.first {
            checkIn.focus = .total(first.project.id)
        }
        render("popup-row-focused", AnyView(CheckInView(viewModel: checkIn, presentation: presentation)), in: url)

        let confirming = PanelPresentation()
        confirming.isAppeared = true
        confirming.mode = .focused
        confirming.commitPhase = .magnified
        checkIn.prepareForShow()
        checkIn.timeText = "0:12:34"
        render("popup-confirm-bounce", AnyView(CheckInView(viewModel: checkIn, presentation: confirming)), in: url)

        // Tasks: one running with a timer, one plain, plus the expiry alert.
        if let project = model.projects().first {
            let a = try? model.store.createTask(projectID: project.id, title: "Write the Phase 4 spec", timerSeconds: 1500)
            _ = try? model.store.createTask(projectID: project.id, title: "Review the artboards")
            _ = try? model.store.createTask(projectID: project.id, title: "Ship the release")
            if let a {
                // Bank the time first, so the countdown reads against it rather than from full.
                try? model.store.addTaskSeconds(task: a.id, project: project.id, day: model.today, 540)
                model.engine.startTask(a)
            }
            checkIn.prepareForShow()
            checkIn.timeText = "0:12:34"
            render("popup-tasks", AnyView(CheckInView(viewModel: checkIn, presentation: presentation)), in: url)

            if let a {
                render("task-menu", AnyView(TaskMenuView(viewModel: checkIn, task: a, onClose: {})), in: url,
                       backdrop: Tokens.Materials.popover)
                checkIn.expiredTaskID = a.id
                render("popup-task-timer", AnyView(CheckInView(viewModel: checkIn, presentation: presentation)), in: url)
                checkIn.expiredTaskID = nil
            }
            model.engine.stopTask()
            for task in model.openTasks() { try? model.store.deleteTask(id: task.id) }
            checkIn.prepareForShow()
        }

        let passive = PanelPresentation()
        passive.isAppeared = true
        passive.mode = .passive
        passive.isDraining = true
        passive.drainProgress = 0.6
        checkIn.prepareForShow()
        checkIn.timeText = "0:12:34"
        render("popup-passive", AnyView(CheckInView(viewModel: checkIn, presentation: passive)), in: url)

        model.engine.pause(until: model.clock.now().addingTimeInterval(3600), reason: .manual)
        checkIn.prepareForShow()
        checkIn.timeText = "0:12:34"
        render("popup-paused", AnyView(CheckInView(viewModel: checkIn, presentation: presentation)), in: url)
        model.engine.resume()

        // Fresh launch (empty database) and a today list long enough to scroll.
        if let empty = try? AppModel(arguments: ["--self-test"]) {
            let emptyCheckIn = CheckInViewModel(model: empty)
            emptyCheckIn.prepareForShow()
            render("popup-empty", AnyView(CheckInView(viewModel: emptyCheckIn, presentation: presentation)), in: url)

            let names = ["Hypertime", "Client · Müller", "Admin", "Design System", "Sales calls", "Learning", "Support"]
            let projects = names.compactMap { try? empty.store.findOrCreateProject(named: $0) }

            // Worst case for the overlay: projects to choose from, but nothing tracked today, so
            // the panel is at its shortest while the dropdown is at its tallest.
            emptyCheckIn.prepareForShow()
            emptyCheckIn.focus = .project
            emptyCheckIn.projectTextChanged("e")
            render("popup-dropdown-short", AnyView(CheckInView(viewModel: emptyCheckIn, presentation: presentation)), in: url)

            for project in projects {
                try? empty.store.setSeconds(project: project.id, day: empty.today, Int.random(in: 12...220) * 60)
            }
            emptyCheckIn.prepareForShow()
            emptyCheckIn.timeText = "0:12:34"
            render("popup-scrolled", AnyView(CheckInView(viewModel: emptyCheckIn, presentation: presentation)), in: url)
        }

        render("overflow-menu", AnyView(OverflowMenuView(groups: [
            [OverflowMenuView.Item("Reports…", symbol: Tokens.Icons.reports) {},
             OverflowMenuView.Item("Settings…", symbol: Tokens.Icons.settings) {}],
            [OverflowMenuView.Item("Quit Hypertime", symbol: Tokens.Icons.quit, isDestructive: true) {}],
        ])), in: url, backdrop: Tokens.Materials.popover)

        checkIn.prepareForShow()
        render("day-picker", AnyView(DayPickerView(viewModel: checkIn, onPick: { _ in })), in: url,
               backdrop: Tokens.Materials.popover)

        checkIn.prepareForShow()
        checkIn.stepDay(-1)
        checkIn.timeText = "0:12:34"
        render("popup-past-day", AnyView(CheckInView(viewModel: checkIn, presentation: presentation)), in: url)
        checkIn.goToToday()

        render("pause-popover", AnyView(PausePopoverView(morningHour: model.settings.morningHour,
                                                        validate: { try? model.parser.parse($0).seconds },
                                                        onPick: { _, _ in })), in: url,
               backdrop: Tokens.Materials.popover)

        // Reports.
        reports.presentation = .chart
        for kind in [PeriodKind.week, .month, .year] {
            reports.kind = kind
            render("chart-\(kind.rawValue)",
                   AnyView(ReportsView(viewModel: reports, onExport: {}).frame(width: Tokens.Size.reportsDefault.width,
                                                                              height: Tokens.Size.reportsDefault.height)),
                   in: url)
        }
        // The window remembers whatever size it was last left at; check the narrow end too.
        reports.kind = .week
        render("reports-narrow",
               AnyView(ReportsView(viewModel: reports, onExport: {})
                   .frame(width: Tokens.Size.reportsMinimum.width,
                          height: Tokens.Size.reportsMinimum.height)),
               in: url)

        reports.isSliding = true
        reports.kind = .week
        reports.go(-2)
        render("chart-sliding-week",
               AnyView(ReportsView(viewModel: reports, onExport: {}).frame(width: Tokens.Size.reportsDefault.width,
                                                                          height: Tokens.Size.reportsDefault.height)),
               in: url)
        reports.isSliding = false
        reports.goToToday()
        reports.presentation = .table

        for kind in [PeriodKind.day, .week, .month, .year] {
            reports.kind = kind
            render("reports-\(kind.rawValue)",
                   AnyView(ReportsView(viewModel: reports, onExport: {}).frame(width: Tokens.Size.reportsDefault.width,
                                                                              height: Tokens.Size.reportsDefault.height)),
                   in: url)
        }

        render("settings", AnyView(SettingsView(viewModel: settings)), in: url)
        render("export", AnyView(ExportView(viewModel: export, onExport: {}, onCancel: {})), in: url)

        FileHandle.standardError.write(Data("screenshots written to \(url.path)\n".utf8))
        exit(0)
    }

    /// Renders one view in every appearance mode. `backdrop` stands in for the chrome a
    /// surface gets from AppKit rather than from the view — an `NSPopover`'s background —
    /// without which a menu renders as invisible text on transparency.
    private static func render(_ name: String, _ view: AnyView, in directory: URL,
                               backdrop: Tokens.MaterialStyle? = nil) {
        for mode in modes {
            // Materials cannot be captured off-screen; draw their opaque fallback instead.
            let root = view
                .glassBackdrop(backdrop)
                .environment(\.opaqueSurfaces, true)
                .environment(\.forcesActiveAppearance, true)
            let hosting = NSHostingView(rootView: root)
            hosting.appearance = NSAppearance(named: mode.appearance)

            let window = NSWindow(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: mode.appearance)
            window.contentView = hosting
            window.setFrame(NSRect(origin: NSPoint(x: -5000, y: -5000), size: hosting.fittingSize), display: false)
            hosting.layoutSubtreeIfNeeded()
            window.displayIfNeeded()

            let bounds = hosting.bounds
            guard bounds.width > 1, bounds.height > 1,
                  let rep = hosting.bitmapImageRepForCachingDisplay(in: bounds) else { continue }
            rep.size = bounds.size
            hosting.cacheDisplay(in: bounds, to: rep)

            guard let data = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else { continue }
            try? data.write(to: directory.appendingPathComponent("\(name)-\(mode.suffix).png"))
        }
    }
}

private extension View {
    /// Paints a material behind the view, or nothing at all when there is none to paint.
    @ViewBuilder
    func glassBackdrop(_ style: Tokens.MaterialStyle?) -> some View {
        if let style { self.glass(style, radius: Tokens.Radius.panel) } else { self }
    }
}

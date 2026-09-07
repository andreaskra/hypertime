import AppKit
import HypertimeCore

/// `--self-test`: headless smoke test of the AppKit layer (status item, panel, commit flow,
/// reports, export). Complements `swift test`, which covers HypertimeCore only.
@MainActor
enum SelfTest {
    private nonisolated(unsafe) static var failures = 0

    static func run(model: AppModel, statusItem: StatusItemController, panel: CheckInPanelController) {
        let viewModel = panel.viewModel

        let launchMilliseconds = Date().timeIntervalSince(AppDelegate.launchDate) * 1000
        check("status item is ready within 300 ms of launch", launchMilliseconds < 300,
              String(format: "%.0f ms", launchMilliseconds))
        check("status item button exists", statusItem.button != nil)
        check("status item has a template image", statusItem.button?.image?.isTemplate == true)
        check("menu bar glyphs are 18×18 templates", [MenuBarGlyph.State.idle, .tracking, .paused].allSatisfy {
            let image = MenuBarGlyph.image($0)
            return image.isTemplate && image.size == NSSize(width: 18, height: 18)
        })
        check("app icon renders at 1024", MenuBarGlyph.appIcon(size: 1024).tiffRepresentation != nil)
        check("popup width matches the design token", CheckInView.width == Tokens.Size.popupWidth)

        // Seed a project the way a first commit would.
        let project = try? model.store.findOrCreateProject(named: "Self Test")
        check("project created", project != nil)

        panel.show(mode: .passive)
        check("panel is visible after a passive show", panel.isVisible)
        check("panel did not take focus", !panel.isKey)
        let frame = panelFrame(panel)
        check("panel has the expected width", abs(frame.width - CheckInView.width) < 1, "\(frame.width)")
        check("panel is taller than its minimum", frame.height >= 120, "\(frame.height)")
        if let screen = NSScreen.main {
            check("panel sits inside the visible frame", screen.visibleFrame.intersects(frame))
        }

        check("dropdown lists the project", viewModel.matches.contains { $0.name == "Self Test" })
        check("dropdown starts closed so the amount stays visible", !viewModel.showsProjectList)

        viewModel.focus = .project
        viewModel.projectTextChanged("self")
        check("typing filters the list", viewModel.matches.contains { $0.name == "Self Test" })
        check("typing opens the dropdown", viewModel.showsProjectList)
        // The dropdown belongs to the field it filters: it opens directly under the project
        // field and overlaps the amount, rather than floating a field and a caption away.
        check("dropdown hangs off the project field", panel.presentation.listTop > 60,
              "\(panel.presentation.listTop)")
        check("dropdown starts above the amount field it covers",
              panel.presentation.listTop < 120, "\(panel.presentation.listTop)")
        check("panel is tall enough for an open dropdown",
              panel.presentation.requiredHeight >= panel.presentation.listTop + panel.presentation.dropdownHeight)

        // ↩ with the list open belongs to the list (R-11): it takes the highlighted row and
        // closes it, rather than committing the popup past a list still being read.
        let highlightedName = viewModel.highlightedRow?.name ?? ""
        check("↩ with the dropdown open is consumed by the dropdown", viewModel.acceptHighlightedRow())
        check("…which closes the list rather than the popup",
              !viewModel.showsProjectList && panel.isVisible)
        check("…and does not commit", model.engine.pendingSeconds == 0)
        check("…puts the highlighted row in the field", viewModel.fieldText == highlightedName,
              "\(viewModel.fieldText) vs \(highlightedName)")
        check("…and clears the filter, so reopening shows every project",
              viewModel.query.isEmpty && viewModel.matches.count >= (try? model.store.projects().count) ?? 0)
        check("↩ with no dropdown open is left to the popup", !viewModel.acceptHighlightedRow())

        viewModel.closeProjectList()
        check("dropdown closes without closing the popup", !viewModel.showsProjectList && panel.isVisible)

        viewModel.toggleProjectList()
        check("the chevron reopens the dropdown", viewModel.showsProjectList)
        viewModel.selectRow(0)
        check("picking a row closes the dropdown", !viewModel.showsProjectList)
        check("picking a row does not commit", panel.isVisible && model.engine.pendingSeconds == 0)
        check("picking a row fills the field", !viewModel.fieldText.isEmpty)

        viewModel.projectTextChanged("self")
        viewModel.focus = .time
        check("leaving the project field closes the dropdown", !viewModel.showsProjectList)

        // The first ↩ in the time field takes the time: typing "90m" and pressing once used to
        // save an amount the user had never seen rendered.
        viewModel.timeTextChanged("90m")
        check("↩ in the time field is consumed by the field", viewModel.acceptTimeEntry())
        check("…and normalises what was typed", viewModel.timeText == "1:30:00", viewModel.timeText)
        check("…without committing", panel.isVisible)
        check("a second ↩ is left to the popup", !viewModel.acceptTimeEntry())
        check("editing again puts the two steps back", {
            viewModel.timeTextChanged("45m")
            return viewModel.acceptTimeEntry() && viewModel.timeText == "0:45:00"
        }(), viewModel.timeText)
        check("an unparsable amount is reported rather than committed", {
            viewModel.timeTextChanged("nonsense")
            return viewModel.acceptTimeEntry() && viewModel.timeFieldInvalid
        }())
        check("leaving the field puts the two steps back", {
            viewModel.timeTextChanged("0:30:00")
            _ = viewModel.acceptTimeEntry()
            viewModel.focus = .project
            viewModel.focus = .time
            return !viewModel.isTimeAccepted
        }())
        viewModel.timeTextChanged("")
        viewModel.focus = .project
        check("create row comes first for an unknown name", {
            viewModel.projectTextChanged("brand new thing")
            if case .create(let name) = viewModel.matches.first { return name == "brand new thing" }
            return false
        }())

        // Commit flow (§6.5).
        viewModel.projectTextChanged("Self Test")
        viewModel.timeTextChanged("1h30")
        viewModel.commit()
        let today = model.today
        let stored = (try? model.store.seconds(project: project?.id ?? UUID(), day: today)) ?? 0
        check("commit added the parsed time", stored == 5400, "\(stored)")
        check("commit started tracking", model.engine.status.isTracking)
        check("commit started the dismiss animation", !panel.presentation.isAppeared)

        // Pending, discard and totals.
        model.engine.tick()
        viewModel.prepareForShow()
        check("time field is pre-filled from the bucket", viewModel.timeText.hasPrefix("0:00"), viewModel.timeText)
        viewModel.discard()
        check("discard leaves the total alone",
              ((try? model.store.seconds(project: project!.id, day: today)) ?? 0) == 5400)

        viewModel.saveTotal(projectID: project!.id, text: "+15m")
        check("relative edit adjusts the total",
              ((try? model.store.seconds(project: project!.id, day: today)) ?? 0) == 6300,
              "\((try? model.store.seconds(project: project!.id, day: today)) ?? 0)")
        viewModel.saveTotal(projectID: project!.id, text: "2h")
        check("absolute edit sets the total",
              ((try? model.store.seconds(project: project!.id, day: today)) ?? 0) == 7200)

        // Today list and reports.
        check("today list has the project", viewModel.todayRows.contains { $0.project.id == project!.id })
        let report = try? model.reportBuilder.report(for: .day(today))
        check("day report matches", report?.total == 7200, "\(report?.total ?? -1)")
        let month = try? model.reportBuilder.report(for: .month(year: today.year, month: today.month))
        check("month report includes the day", (month?.total ?? 0) >= 7200)

        // Export.
        let csv = try? model.exporter.csv(scope: .month(year: today.year, month: today.month))
        check("CSV export has a header", csv?.contains("Date,Self Test") == true)
        check("CSV export has the day row", csv?.contains(today.isoString + ",2:00:00") == true)

        // Windows.
        check("panel positions under the status item",
              panelFrame(panel).maxY <= (NSScreen.main?.frame.maxY ?? 0))

        // The dismiss is animated; give it a run loop turn before checking the window is gone.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            check("panel is ordered out once the dismiss finishes", !panel.isVisible)
            FileHandle.standardError.write(Data("self-test: \(failures == 0 ? "PASS" : "FAIL (\(failures))")\n".utf8))
            exit(failures == 0 ? 0 : 1)
        }
    }

    private static func panelFrame(_ panel: CheckInPanelController) -> NSRect {
        NSApp.windows.first { $0 is CheckInPanel }?.frame ?? .zero
    }

    private static func check(_ name: String, _ condition: Bool, _ detail: String = "") {
        let mark = condition ? "ok  " : "FAIL"
        if !condition { failures += 1 }
        let suffix = detail.isEmpty ? "" : " (\(detail))"
        FileHandle.standardError.write(Data("\(mark) \(name)\(suffix)\n".utf8))
    }
}

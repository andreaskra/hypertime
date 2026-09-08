import AppKit
import HypertimeCore

/// `--self-test`: headless smoke test of the AppKit layer (status item, panel, commit flow,
/// reports, export). Complements `swift test`, which covers HypertimeCore only.
@MainActor
enum SelfTest {
    private nonisolated(unsafe) static var failures = 0

    static func run(model: AppModel, statusItem: StatusItemController, panel: CheckInPanelController) {
        let viewModel = panel.viewModel

        // The Phase 3 budget is the whole launch, but the pre-main share only exists when the
        // app was launched rather than run directly, so it is asserted only when it is real.
        let now = Date()
        let setUp = now.timeIntervalSince(AppDelegate.mainDate) * 1000
        // Generous on purpose: this runs straight after a build as often as not, and a bound
        // set close to the typical figure fails on a busy machine rather than on a regression.
        // The number to watch is the one logged on a real launch; this catches the cliff.
        check("app set-up to the status item is under 500 ms", setUp < 500, String(format: "%.0f ms", setUp))
        if let launched = AppDelegate.launchDate {
            let total = now.timeIntervalSince(launched) * 1000
            check("launch to the status item is under 300 ms", total < 300,
                  String(format: "%.0f ms total, %.0f ms before main()", total, total - setUp))
        } else {
            note("launch budget not measured: run from a bundle launch to check the 300 ms figure")
        }
        check("status item button exists", statusItem.button != nil)
        check("status item has a template image", statusItem.button?.image?.isTemplate == true)
        check("menu bar glyphs are 18×18 templates", [MenuBarGlyph.State.idle, .tracking, .paused].allSatisfy {
            let image = MenuBarGlyph.image($0)
            return image.isTemplate && image.size == NSSize(width: 18, height: 18)
        })
        checkAppIcon()
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
        // With nowhere in the menu bar to hang off — not yet placed, or pushed into the overflow
        // — the panel belongs in the top right, never in a corner of the desktop.
        let realAnchor = panel.anchorProvider
        panel.anchorProvider = { nil }
        panel.show(mode: .passive)
        if let screen = NSScreen.main {
            let fallback = panelFrame(panel)
            check("without an anchor the panel falls back to the top right",
                  fallback.maxY > screen.visibleFrame.midY && fallback.midX > screen.visibleFrame.midX,
                  String(format: "origin %.0f, %.0f", fallback.minX, fallback.minY))
        }
        panel.anchorProvider = realAnchor
        panel.show(mode: .passive)

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
        // The write happens immediately; only the display is held, so the amount flips to zero
        // and the project's total jumps together at the bottom of the bounce.
        check("commit holds the display until the bounce says so",
              panel.presentation.isAppeared && viewModel.isCommitting)
        check("…with the amount still reading what was entered", viewModel.timeText == "1h30", viewModel.timeText)
        viewModel.revealCommittedTotals()
        check("the bounce cue flips the amount to zero", viewModel.timeText.hasPrefix("0:00"), viewModel.timeText)
        check("…and the project's total has caught up",
              viewModel.todayRows.first { $0.project.id == project?.id }?.seconds == 5400,
              "\(viewModel.todayRows.first { $0.project.id == project?.id }?.seconds ?? -1)")

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

        // The header control has to work from all three states. Idle is where the popup opens
        // after a launch or a quit, and it used to show a disabled pause icon — no way back into
        // tracking except committing an amount.
        let today2 = model.today
        model.engine.stop()
        viewModel.prepareForShow()
        check("idle offers an enabled play button",
              !viewModel.isTracking && !viewModel.isPaused && viewModel.canToggleTracking)
        let beforeStart = (try? model.store.seconds(project: project!.id, day: today2)) ?? 0
        viewModel.toggleTracking()
        check("play from idle starts tracking", model.engine.status.isTracking)
        check("…without attributing any time",
              ((try? model.store.seconds(project: project!.id, day: today2)) ?? 0) == beforeStart)

        model.pause(.m15)
        viewModel.prepareForShow()
        check("paused offers a play button", viewModel.isPaused && viewModel.canToggleTracking)
        viewModel.toggleTracking()
        check("play from paused resumes", model.engine.status.isTracking)

        model.engine.stop()
        viewModel.prepareForShow()
        viewModel.projectTextChanged("")
        check("idle with no project named has nothing to start", !viewModel.canToggleTracking)

        // Tracking picks itself back up on the next launch, on the project it was last on, and
        // none of the time the app was closed is counted.
        let resumeProject = try? model.store.findOrCreateProject(named: "Self Test")
        model.engine.commit(projectID: resumeProject!.id, seconds: 0)
        model.engine.stop()
        let banked = (try? model.store.seconds(project: resumeProject!.id, day: model.today)) ?? 0

        let relaunched = TrackingEngine(store: model.store, clock: model.clock, settings: model.settings)
        relaunched.restore()
        check("a relaunch picks tracking back up", relaunched.status.isTracking)
        check("…on the project it was last on", relaunched.currentProjectID == resumeProject?.id)
        check("…counting none of the time the app was closed", relaunched.pendingSeconds == 0)
        check("…and banking nothing extra",
              ((try? model.store.seconds(project: resumeProject!.id, day: model.today)) ?? 0) == banked)

        model.settings.startTrackingOnLaunch = false
        let waiting = TrackingEngine(store: model.store, clock: model.clock, settings: model.settings)
        waiting.restore()
        check("with the setting off a relaunch waits instead", waiting.status == .idle)
        check("…but still remembers the project", waiting.currentProjectID == resumeProject?.id)
        model.settings.startTrackingOnLaunch = true

        // The confirm bounce plus the dismiss is 480 ms; give it room before checking the
        // window is gone. If this ever needs raising, the animation has outgrown its budget.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            check("panel is ordered out once the dismiss finishes", !panel.isVisible)
            // The menu bar only places the status item once launching is over, which is exactly
            // why the popup used to land in a corner. Everything below needs a placed item.
            waitForStatusItem(statusItem, panel, attempt: 0)
        }
    }

    private static func waitForStatusItem(_ statusItem: StatusItemController,
                                          _ panel: CheckInPanelController,
                                          attempt: Int) {
        guard statusItem.screenFrame == nil, attempt < 40 else {
            checkPlacement(statusItem, panel)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            waitForStatusItem(statusItem, panel, attempt: attempt + 1)
        }
    }

    /// The popup hangs off the status item, so it has to be *under* it and nowhere else.
    private static func checkPlacement(_ statusItem: StatusItemController, _ panel: CheckInPanelController) {
        check("status item takes its place in the menu bar", statusItem.screenFrame != nil)

        panel.show(mode: .passive)
        let frame = panelFrame(panel)
        if let anchor = statusItem.screenFrame, let screen = NSScreen.main {
            let clampedToEdge = frame.maxX >= screen.visibleFrame.maxX - 8.5
            check("panel is centred under the status item",
                  abs(frame.midX - anchor.midX) < 1 || clampedToEdge,
                  String(format: "panel %.0f vs item %.0f", frame.midX, anchor.midX))
            check("panel hangs 6 pt below the menu bar",
                  abs(frame.maxY - (screen.visibleFrame.maxY - 6)) < 1,
                  String(format: "top %.0f, menu bar bottom %.0f", frame.maxY, screen.visibleFrame.maxY))
        }

        measureConfirmAnimation(panel)
    }

    /// Confirm bounce plus dismiss, measured end to end with a free run loop. The design budget
    /// is 500 ms; the bound is looser so machine load cannot fail it, but the figure is printed.
    private static func measureConfirmAnimation(_ panel: CheckInPanelController) {
        let viewModel = panel.viewModel
        viewModel.projectTextChanged("Self Test")
        viewModel.timeTextChanged("5m")
        let started = Date()
        viewModel.commit()
        pollUntilHidden(panel, startedAt: started, attempt: 0)
    }

    private static func pollUntilHidden(_ panel: CheckInPanelController, startedAt: Date, attempt: Int) {
        guard panel.isVisible, attempt < 100 else {
            let elapsed = Date().timeIntervalSince(startedAt) * 1000
            // The upper bound is the design budget with slack for machine load; the lower one
            // catches the bounce being skipped entirely, which is how this first went wrong.
            check("confirm animation closes the popup inside its budget", elapsed < 700,
                  String(format: "%.0f ms, budget 500 ms", elapsed))
            check("confirm animation actually plays its phases", elapsed > 300,
                  String(format: "%.0f ms, three phases are 360 ms", elapsed))
            check("the popup did close", !panel.isVisible)
            FileHandle.standardError.write(Data("self-test: \(failures == 0 ? "PASS" : "FAIL (\(failures))")\n".utf8))
            exit(failures == 0 ? 0 : 1)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            pollUntilHidden(panel, startedAt: startedAt, attempt: attempt + 1)
        }
    }

    /// The Dock icon: present in the bundle, and actually masked to the macOS icon shape rather
    /// than the full-bleed square the handoff PNGs are authored as.
    private static func checkAppIcon() {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: url) else {
            check("bundle contains AppIcon.icns", false)
            return
        }
        check("bundle contains AppIcon.icns", true)

        let target = NSSize(width: 512, height: 512)
        guard let rep = icon.representations.first(where: { $0.pixelsWide == 512 }) as? NSBitmapImageRep
                ?? icon.bestRepresentation(for: NSRect(origin: .zero, size: target), context: nil, hints: nil)
                    .flatMap({ $0 as? NSBitmapImageRep }) else {
            check("app icon has a 512 px rendition", false)
            return
        }
        check("app icon has a 512 px rendition", true)

        let corner = rep.colorAt(x: 2, y: 2)?.alphaComponent ?? 1
        let centre = rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)?.alphaComponent ?? 0
        check("app icon is masked, not a full-bleed square", corner < 0.05, String(format: "corner alpha %.2f", corner))
        check("app icon is opaque in the middle", centre > 0.95, String(format: "centre alpha %.2f", centre))

        // What the Dock and Finder actually draw comes from LaunchServices, not from the file:
        // a stale registration keeps handing out the generic icon however good the bundle is.
        let served = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        let ours = centreColour(of: icon)
        let system = centreColour(of: served)
        let matches = ours.map { mine in system.map { abs(mine.0 - $0.0) < 0.08 && abs(mine.1 - $0.1) < 0.08
                                                      && abs(mine.2 - $0.2) < 0.08 } ?? false } ?? false
        check("LaunchServices serves our icon, not the generic one", matches,
              "bundle \(describe(ours)) vs system \(describe(system))")
    }

    /// Centre pixel of an icon at 128 pt — our artwork has an accent-blue dot there, the generic
    /// document icon is near-white, so the two are trivially distinguishable.
    private static func centreColour(of image: NSImage) -> (CGFloat, CGFloat, CGFloat)? {
        let size = NSSize(width: 128, height: 128)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 128,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        guard let colour = rep.colorAt(x: 64, y: 64)?.usingColorSpace(.deviceRGB) else { return nil }
        return (colour.redComponent, colour.greenComponent, colour.blueComponent)
    }

    private static func describe(_ colour: (CGFloat, CGFloat, CGFloat)?) -> String {
        guard let colour else { return "none" }
        return String(format: "rgb(%.2f, %.2f, %.2f)", colour.0, colour.1, colour.2)
    }

    private static func panelFrame(_ panel: CheckInPanelController) -> NSRect {
        NSApp.windows.first { $0 is CheckInPanel }?.frame ?? .zero
    }

    private static func note(_ text: String) {
        FileHandle.standardError.write(Data("--   \(text)\n".utf8))
    }

    private static func check(_ name: String, _ condition: Bool, _ detail: String = "") {
        let mark = condition ? "ok  " : "FAIL"
        if !condition { failures += 1 }
        let suffix = detail.isEmpty ? "" : " (\(detail))"
        FileHandle.standardError.write(Data("\(mark) \(name)\(suffix)\n".utf8))
    }
}

import AppKit
import HypertimeCore

/// `--self-test`: headless smoke test of the AppKit layer (status item, panel, commit flow,
/// reports, export). Complements `swift test`, which covers HypertimeCore only.
@MainActor
enum SelfTest {
    private nonisolated(unsafe) static var failures = 0

    static func run(model: AppModel,
                    statusItem: StatusItemController,
                    panel: CheckInPanelController,
                    settingsWindow: SettingsWindowController) {
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
        checkSettingsWindow(settingsWindow)
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
        checkLiveFieldIsLeftAlone(panel, model)
        checkProjectCanBeChanged(panel, model)
        checkNewTaskSurvivesAClick(panel)

        // Opening by hand while another app holds the keyboard: losing key status in the first
        // moments must make the panel insist, not dismiss itself.
        panel.show(mode: .focused)
        panel.windowDidResignKey(Notification(name: Notification.Name("self-test")))
        check("a just-opened popup does not dismiss when key status is contested", panel.isVisible)
        panel.hide()

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
        // "Did not commit" means nothing was filed, not that the clock stopped.
        let bankedBefore = (try? model.store.seconds(project: project!.id, day: model.today)) ?? 0
        check("↩ with the dropdown open is consumed by the dropdown", viewModel.acceptHighlightedRow())
        check("…which closes the list rather than the popup",
              !viewModel.showsProjectList && panel.isVisible)
        check("…and does not commit",
              ((try? model.store.seconds(project: project!.id, day: model.today)) ?? 0) == bankedBefore)
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
        check("picking a row does not commit",
              panel.isVisible
              && ((try? model.store.seconds(project: project!.id, day: model.today)) ?? 0) == bankedBefore)
        check("picking a row fills the field", !viewModel.fieldText.isEmpty)

        viewModel.projectTextChanged("self")
        viewModel.focus = .time
        check("leaving the project field closes the dropdown", !viewModel.showsProjectList)

        // The first ↩ in the time field takes the time: typing "90m" and pressing once used to
        // save an amount the user had never seen rendered.
        // Taking the keyboard stops the counter: text that rewrites itself cannot be edited.
        viewModel.prepareForShow()
        check("the amount runs live until the field is touched", !viewModel.isEditingTime)
        viewModel.beginEditingTime()
        check("focusing the amount field stops the counter", viewModel.isEditingTime)
        let frozen = viewModel.timeText
        viewModel.refreshTime()
        check("…and a refresh no longer rewrites it", viewModel.timeText == frozen, viewModel.timeText)
        viewModel.timeTextChanged("")
        viewModel.focus = .project
        check("leaving an empty amount hands it back to the counter", !viewModel.isEditingTime)
        viewModel.focus = .time
        viewModel.timeTextChanged("42m")
        viewModel.focus = .project
        check("leaving an edited amount keeps what was typed",
              viewModel.isEditingTime && viewModel.timeText == "42m", viewModel.timeText)
        viewModel.focus = .time

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
        check("day report matches", (report?.total ?? 0) >= 7200, "\(report?.total ?? -1)")
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

        // Reports: the stats describe the range on screen, and a sliding window steps a day at
        // a time so any arbitrary stretch can be reached.
        let reports = ReportsViewModel(model: model)
        reports.kind = .week
        let alignedRange = reports.period.range(calendar: model.clock.calendar, weekStart: model.settings.weekStart)
        check("a calendar week covers seven days", reports.calendarDays == 7, "\(reports.calendarDays)")
        check("averages are offered for a range longer than a day", reports.showsAverages)
        check("the average per day divides the total by the range",
              reports.averagePerDay == reports.total / 7, "\(reports.averagePerDay)")
        check("the average per tracked day only counts days with time",
              reports.trackedDays <= reports.calendarDays,
              "\(reports.trackedDays) of \(reports.calendarDays)")

        reports.isSliding = true
        let slid = reports.period.range(calendar: model.clock.calendar, weekStart: model.settings.weekStart)
        check("sliding keeps the width", reports.calendarDays == 7)
        reports.go(-1)
        let stepped = reports.period.range(calendar: model.clock.calendar, weekStart: model.settings.weekStart)
        check("…and steps one day, not one week",
              stepped.lowerBound == model.day(slid.lowerBound, offsetBy: -1),
              "\(slid.lowerBound) -> \(stepped.lowerBound)")
        check("…so it leaves the calendar week behind",
              stepped.lowerBound != alignedRange.lowerBound)
        check("…and still reports seven days", reports.calendarDays == 7)
        reports.isSliding = false
        check("snapping back lands on a calendar week", reports.calendarDays == 7)

        reports.kind = .day
        check("a single day offers no averages", !reports.showsAverages)

        // Idle: the system reading must be a real number, and the engine must act on it.
        let idle = AppModel.systemIdleSeconds()
        check("system idle time is readable without a permission prompt", idle >= 0, "\(idle)s")
        model.settings.idleTimeoutMinutes = 5
        model.engine.commit(projectID: project!.id, seconds: 0)
        model.engine.checkIdle(systemIdleSeconds: 299)
        check("below the threshold tracking carries on", model.engine.status.isTracking)
        model.engine.checkIdle(systemIdleSeconds: 600)
        check("an untouched Mac pauses tracking", model.engine.status.isPaused)
        model.engine.checkIdle(systemIdleSeconds: 0)
        check("touching it again resumes", model.engine.status.isTracking)
        model.settings.idleTimeoutMinutes = 0        // a headless run is idle by definition

        // Tasks: created under the current project, click to run, checkmark to finish.
        viewModel.projectTextChanged("Self Test")
        viewModel.addTask()
        viewModel.newTaskTitle = "Write the spec"
        viewModel.commitNewTask()
        check("the + button creates a task", viewModel.tasks.contains { $0.title == "Write the spec" })
        guard let task = viewModel.tasks.first(where: { $0.title == "Write the spec" }) else {
            check("task available", false)
            return
        }
        check("…under the project the popup is showing", task.projectID == project?.id)

        viewModel.startTask(task)
        check("the start button hands it the clock", viewModel.isRunning(task))
        check("…and a running task cannot be deleted", !viewModel.canDelete(task))
        check("…and the bucket stops accruing", model.engine.activeTaskID == task.id)
        let bucketBefore = model.engine.pendingSeconds
        model.engine.tick()
        check("…leaving the pending bucket alone", model.engine.pendingSeconds == bucketBefore)

        viewModel.stopTask(task)
        check("the stop button pauses it", !viewModel.isRunning(task) && model.engine.activeTaskID == nil)
        check("…a stopped task can be deleted", viewModel.canDelete(task))
        try? model.store.addTaskSeconds(task: task.id, project: task.projectID, day: model.today, 60)
        check("…and reads as resumable once it has time on it", viewModel.hasStarted(task))
        viewModel.startTask(task)
        check("…and resumes from where it was", viewModel.isRunning(task))
        viewModel.stopTask(task)

        viewModel.setTimer(task, seconds: 1500)
        check("a timer can be set from the slider",
              model.task(task.id)?.timerSeconds == 1500, "\(model.task(task.id)?.timerSeconds ?? -1)")
        check("…and shows as remaining", viewModel.remainingText(for: model.task(task.id)!) != nil)
        // A timer is a nudge: taking it away must not touch a second of tracked time (T-05).
        let trackedBeforeClear = model.engine.liveTaskSeconds(task.id)
        let projectBeforeClear = (try? model.store.seconds(project: task.projectID, day: model.today)) ?? -1
        viewModel.clearTimer(model.task(task.id)!)
        check("…and can be cleared", model.task(task.id)?.timerSeconds == nil)
        check("…without changing the time the task has tracked",
              model.engine.liveTaskSeconds(task.id) == trackedBeforeClear,
              "\(trackedBeforeClear) s before, \(model.engine.liveTaskSeconds(task.id)) s after")
        check("…or the project's day total",
              (try? model.store.seconds(project: task.projectID, day: model.today)) == projectBeforeClear)
        checkTimerSlider()

        viewModel.finishTask(task)
        check("finishing animates before it commits", viewModel.completingTaskID == task.id)
        viewModel.commitFinish()
        check("…then the task leaves the list", !viewModel.tasks.contains { $0.id == task.id })
        check("…and is marked complete", model.task(task.id)?.isComplete == true)

        // ↩ on a pending task never throws the title away: it either files, or the row stays
        // with the text still in it. Losing what somebody typed is never an outcome.
        viewModel.addTask()
        viewModel.newTaskTitle = "Needs a home"
        viewModel.projectTextChanged("")              // no project named at all
        let filedIt = viewModel.commitNewTask()
        check("↩ on a pending task never loses the title",
              filedIt ? viewModel.tasks.contains { $0.title == "Needs a home" }
                      : viewModel.newTaskTitle == "Needs a home",
              filedIt ? "filed it" : "kept the row")
        check("…and an unfiled row says why", filedIt || viewModel.newTaskError != nil)
        check("…while an empty field with no project still finds one", filedIt)
        if let filed = viewModel.tasks.first(where: { $0.title == "Needs a home" }) {
            viewModel.deleteTask(filed)
            viewModel.commitDelete()
        }

        viewModel.addTask()
        viewModel.newTaskTitle = "Doomed"
        viewModel.commitNewTask()
        if let doomed = viewModel.tasks.first(where: { $0.title == "Doomed" }) {
            viewModel.deleteTask(doomed)
            check("deleting animates before it commits", viewModel.deletingTaskID == doomed.id)
            viewModel.commitDelete()
            check("…then the task is gone", model.task(doomed.id) == nil)
        }

        // The day list steps back and forward, and edits land on the day being shown.
        let yesterday = model.day(model.today, offsetBy: -1)
        viewModel.prepareForShow()
        check("the list starts on today", viewModel.isShowingToday && viewModel.dayLabel == "TODAY")
        viewModel.stepDay(-1)
        check("stepping back leaves today", !viewModel.isShowingToday)
        check("…and the label names the day", viewModel.visibleDay == yesterday && viewModel.dayLabel != "TODAY",
              viewModel.dayLabel)
        let todayBefore = (try? model.store.seconds(project: project!.id, day: model.today)) ?? 0
        viewModel.saveTotal(projectID: project!.id, text: "3h")
        check("an edit lands on the day being shown",
              ((try? model.store.seconds(project: project!.id, day: yesterday)) ?? 0) == 10800)
        check("…and leaves today alone",
              ((try? model.store.seconds(project: project!.id, day: model.today)) ?? 0) == todayBefore)
        check("the calendar marks a day that has time",
              viewModel.markedDays(in: yesterday).contains(yesterday))
        check("the future is out of reach", !viewModel.canStepForward == false || viewModel.visibleDay < model.today)
        viewModel.goToToday()
        check("the calendar button comes home", viewModel.isShowingToday)
        check("…and forward stops there", !viewModel.canStepForward)
        viewModel.stepDay(1)
        check("…so stepping forward from today does nothing", viewModel.isShowingToday)
        viewModel.showDay(model.day(model.today, offsetBy: 3))
        check("…and a future date cannot be jumped to", viewModel.isShowingToday)

        // The day you were last looking at survives closing and reopening by hand, but a
        // scheduled nudge always comes back to today.
        viewModel.stepDay(-1)
        viewModel.prepareForShow(keepingDay: true)
        check("reopening by hand keeps the day", !viewModel.isShowingToday)
        viewModel.prepareForShow(keepingDay: false)
        check("a nudge comes back to today", viewModel.isShowingToday)

        // A focused field is never rewritten underneath the caret.
        viewModel.focus = .time
        viewModel.isEditingTime = false
        let typed = "0:07"
        viewModel.timeText = typed
        viewModel.refreshTime()
        check("a focused amount field is left alone even unedited", viewModel.timeText == typed,
              viewModel.timeText)
        viewModel.focus = .none
        check("a month grid is whole weeks",
              viewModel.monthGrid(for: model.today).allSatisfy { $0.count == 7 })

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
            waitForStatusItem(statusItem, panel, model, attempt: 0)
        }
    }

    private static func waitForStatusItem(_ statusItem: StatusItemController,
                                          _ panel: CheckInPanelController,
                                          _ model: AppModel,
                                          attempt: Int) {
        guard statusItem.screenFrame == nil, attempt < 40 else {
            checkPlacement(statusItem, panel, model)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            waitForStatusItem(statusItem, panel, model, attempt: attempt + 1)
        }
    }

    /// The popup hangs off the status item, so it has to be *under* it and nowhere else.
    private static func checkPlacement(_ statusItem: StatusItemController, _ panel: CheckInPanelController, _ model: AppModel) {
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

    /// Drives the real `NSTextField` the way a click does, then lets the clock run: the amount
    /// must not be rewritten, re-selected, or have the caret taken away from it.
    private static func checkLiveFieldIsLeftAlone(_ panel: CheckInPanelController, _ model: AppModel) {
        panel.show(mode: .focused)
        let viewModel = panel.viewModel

        // The counter has to actually be running, or this proves nothing.
        model.settings.idleTimeoutMinutes = 0
        if let project = try? model.store.projects().first {
            model.engine.commit(projectID: project.id, seconds: 0)
        }
        waitASecond()
        model.engine.tick()
        viewModel.prepareForShow(keepingDay: false)
        check("the amount is live before the field is touched", model.engine.pendingSeconds > 0,
              "\(model.engine.pendingSeconds)s pending")

        guard let window = NSApp.windows.first(where: { $0 is CheckInPanel }),
              let field = amountField(in: window.contentView) else {
            check("found the amount field in the panel", false)
            return
        }
        check("found the amount field in the panel", true)

        // Exactly what a click does: hand the field the keyboard and let AppKit tell the app.
        window.makeFirstResponder(field)
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        check("taking the keyboard tells the view model to stop the counter",
              viewModel.isEditingTime && viewModel.focus == .time,
              "editing=\(viewModel.isEditingTime) focus=\(viewModel.focus)")
        field.currentEditor()?.selectedRange = NSRange(location: 2, length: 0)   // caret, no selection
        let before = field.stringValue

        let pendingBefore = model.engine.pendingSeconds
        for _ in 0..<2 {
            waitASecond()
            model.engine.tick()
            viewModel.tick()
        }
        check("the clock really moved underneath it", model.engine.pendingSeconds > pendingBefore,
              "\(pendingBefore) -> \(model.engine.pendingSeconds)")

        check("the focused amount keeps its text", field.stringValue == before,
              "\(before) -> \(field.stringValue)")
        check("…and the view model stops feeding it", viewModel.timeText == before, viewModel.timeText)
        let selection = field.currentEditor()?.selectedRange ?? NSRange(location: 0, length: 0)
        check("…and keeps the caret where it was put", selection.length == 0,
              "selected \(selection.length) characters")
        check("…and still holds the keyboard",
              window.firstResponder === field.currentEditor())
        panel.hide()
    }

    /// `RunLoop.run(before:)` returns as soon as any source fires, so one call is not a wait.
    /// Picking a project has to reach the real field, and committing has to switch tracking to
    /// it. The field holds the caret the whole time, which is what broke this.
    private static func checkProjectCanBeChanged(_ panel: CheckInPanelController, _ model: AppModel) {
        panel.show(mode: .focused)
        let viewModel = panel.viewModel
        model.settings.idleTimeoutMinutes = 0

        guard let other = try? model.store.findOrCreateProject(named: "Somewhere Else"),
              let window = NSApp.windows.first(where: { $0 is CheckInPanel }),
              let field = projectField(in: window.contentView) else {
            check("found the project field", false)
            return
        }
        viewModel.prepareForShow(keepingDay: false)
        window.makeFirstResponder(field)
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))

        // Open the list and walk to another project, exactly as ↓ does.
        viewModel.openProjectList()
        var guard_ = 0
        while viewModel.highlightedRow?.name != other.name, guard_ < 40 {
            viewModel.moveSelection(by: 1)
            guard_ += 1
        }
        check("the list can reach another project", viewModel.highlightedRow?.name == other.name,
              viewModel.highlightedRow?.name ?? "none")

        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        check("arrowing shows the project in the field, caret or not",
              field.stringValue == other.name, "field says \(field.stringValue)")

        viewModel.commit()
        check("…and confirming switches tracking to it",
              model.currentProject?.name == other.name, model.currentProject?.name ?? "none")
        panel.hide()
    }

    private static func projectField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, (field.font?.pointSize ?? 0) <= 20,
           field.placeholderAttributedString?.string == "Project name" { return field }
        for subview in view.subviews {
            if let found = projectField(in: subview) { return found }
        }
        return nil
    }

    /// Clicking into the new-task row must not dismiss it. A text field resigns first responder
    /// to its own field editor the moment it is focused, which once read as "the user left".
    private static func checkNewTaskSurvivesAClick(_ panel: CheckInPanelController) {
        panel.show(mode: .focused)
        let viewModel = panel.viewModel
        viewModel.addTask()
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))

        guard let window = NSApp.windows.first(where: { $0 is CheckInPanel }),
              let field = field(in: window.contentView, placeholder: "What needs doing?") else {
            check("the new-task row appears", false)
            return
        }
        check("the new-task row appears", viewModel.isAddingTask)

        window.makeFirstResponder(field)
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        check("clicking into it does not dismiss it", viewModel.isAddingTask)
        check("…and it still holds the keyboard", window.firstResponder === field.currentEditor())

        viewModel.newTaskTitle = "Typed into it"
        viewModel.commitNewTask()
        check("…and a title can be typed and kept",
              viewModel.tasks.contains { $0.title == "Typed into it" })
        if let created = viewModel.tasks.first(where: { $0.title == "Typed into it" }) {
            viewModel.deleteTask(created)
            viewModel.commitDelete()
        }
        panel.hide()
    }

    private static func field(in view: NSView?, placeholder: String) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField,
           field.placeholderAttributedString?.string == placeholder { return field }
        for subview in view.subviews {
            if let found = field(in: subview, placeholder: placeholder) { return found }
        }
        return nil
    }

    private static func waitASecond() {
        let deadline = Date().addingTimeInterval(1.1)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: deadline)
        }
    }

    /// The amount field is the one wearing the big rounded face.
    private static func amountField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, (field.font?.pointSize ?? 0) > 20 { return field }
        for subview in view.subviews {
            if let found = amountField(in: subview) { return found }
        }
        return nil
    }

    /// Settings has to be closeable: it once drew its content through the titlebar, which left
    /// the traffic lights buried under the form.
    private static func checkSettingsWindow(_ settings: SettingsWindowController) {
        settings.show()
        guard let window = settings.window else {
            check("settings window opens", false)
            return
        }
        check("settings window opens", window.isVisible)
        check("settings window has a close button",
              window.styleMask.contains(.closable) && window.standardWindowButton(.closeButton) != nil)
        check("settings content stays below the titlebar", !window.styleMask.contains(.fullSizeContentView))
        window.performClose(nil)
        check("settings window closes", !window.isVisible)
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
        // The Dock draws the running app's tile from applicationIconImage, which the app points
        // at its own bundle precisely so a stale Dock cache cannot outvote the build.
        let tile = NSApp.applicationIconImage.flatMap(centreColour)
        let tileMatches = ours.map { mine in tile.map { abs(mine.0 - $0.0) < 0.08 && abs(mine.1 - $0.1) < 0.08
                                                        && abs(mine.2 - $0.2) < 0.08 } ?? false } ?? false
        check("the Dock tile is set from the bundle we are running", tileMatches,
              "tile \(describe(tile))")

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

    /// The timer slider, driven through the real AppKit view the way a mouse drives it.
    /// The ladder has its own tests in core; what is checked here is the plumbing — hovering,
    /// the press, the wheel's direction and the release — which is where this kind of control
    /// actually breaks.
    private static func checkTimerSlider() {
        let width = Tokens.Size.taskMenuWidth - 2 * Tokens.Space.s2
        let middle = NSPoint(x: width / 2, y: Tokens.Slider.bandHeight / 2)
        let view = SliderInteraction.TrackingView(
            frame: NSRect(x: 0, y: 0, width: width, height: Tokens.Slider.bandHeight))
        var pressed: CGFloat?
        var dragged: CGFloat?
        var releases = 0
        var steps = 0
        var hovering = false
        view.onHover = { hovering = $0 }
        view.onPress = { x, _ in pressed = x }
        view.onDrag = { dragged = $0 }
        view.onRelease = { releases += 1 }
        view.onScroll = { steps += $0 }

        // Reported: the knob slid under the pointer. Hovering is a cursor state, nothing more.
        view.mouseEntered(with: mouseEvent(.mouseMoved, at: middle))
        view.mouseMoved(with: mouseEvent(.mouseMoved, at: NSPoint(x: width * 0.8, y: middle.y)))
        check("hovering the slider moves nothing", pressed == nil && dragged == nil && releases == 0)
        check("…though the knob lights up under the cursor", hovering)
        view.mouseExited(with: mouseEvent(.mouseMoved, at: NSPoint(x: -4, y: middle.y)))
        check("…and settles again when the cursor leaves", !hovering)

        /// One click on the track, and the length it lands on.
        func slot(at x: CGFloat) -> Seconds {
            pressed = nil
            view.mouseDown(with: mouseEvent(.leftMouseDown, at: NSPoint(x: x, y: middle.y)))
            view.mouseUp(with: mouseEvent(.leftMouseUp, at: NSPoint(x: x, y: middle.y)))
            guard let pressed else { return -1 }
            return TimerLadder.seconds(at: TimerLadder.index(
                atFraction: TimerSlider.fraction(forX: pressed, width: width)))
        }

        // The knob lands under the cursor at both ends, not a knob radius short of them.
        check("the slider's left end is one minute", slot(at: 0) == 60, "\(slot(at: 0)) s")
        check("…and its right end is eight hours", slot(at: width) == 8 * 3600, "\(slot(at: width)) s")
        let radius = Tokens.Slider.knob / 2
        let step = (width - Tokens.Slider.knob) / CGFloat(TimerLadder.slots.count - 1)
        let hourFraction = TimerLadder.fraction(ofIndex: TimerLadder.index(nearest: 3600))
        check("…and the hour lands where the scale says it does",
              slot(at: radius + CGFloat(hourFraction) * (width - Tokens.Slider.knob)) == 3600)
        check("…roughly two thirds along", hourFraction > 0.6 && hourFraction < 0.72,
              String(format: "%.2f", hourFraction))
        // The whole point of the ladder: the same scrap of travel is worth a minute down at
        // the short end and an hour up at the top.
        let shortEnd = radius + 3 * step
        let longEnd = radius + CGFloat(TimerLadder.slots.count - 3) * step
        check("…where one slot of travel is a minute at the short end",
              slot(at: shortEnd + step) - slot(at: shortEnd) == 60,
              "\(slot(at: shortEnd)) s then \(slot(at: shortEnd + step)) s")
        check("…and an hour at the long end",
              slot(at: longEnd + step) - slot(at: longEnd) == 3600,
              "\(slot(at: longEnd)) s then \(slot(at: longEnd + step)) s")

        // A knob is wider than a slot, so the click that confirms a scrolled length has to
        // keep it rather than re-read it from the cursor.
        let knobX = radius + 10 * step
        check("a press on the knob keeps its value",
              TimerSlider.isOnKnob(pressX: knobX + radius - 1, knobX: knobX))
        check("…while a press on bare track takes the cursor's",
              !TimerSlider.isOnKnob(pressX: knobX + Tokens.Slider.knob, knobX: knobX))

        // Reported the other way round at first: a click had to be able to accept what the
        // wheel had just chosen, wherever the cursor happened to be sitting.
        var keptValue: Bool?
        view.onPress = { _, keeps in keptValue = keeps }
        if let up = wheelEvent(1) { view.scrollWheel(with: up) }
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: NSPoint(x: 4, y: middle.y)))
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: NSPoint(x: 4, y: middle.y)))
        check("a click straight after a scroll takes the scrolled length", keptValue == true)
        if let up = wheelEvent(1) { view.scrollWheel(with: up) }
        view.mouseMoved(with: mouseEvent(.mouseMoved, at: NSPoint(x: width * 0.3, y: middle.y)))
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: NSPoint(x: width * 0.3, y: middle.y)))
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: NSPoint(x: width * 0.3, y: middle.y)))
        check("…but moving the cursor first means the spot you clicked", keptValue == false)
        view.onPress = { x, _ in pressed = x }
        steps = 0
        releases = 0

        releases = 0
        dragged = nil
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: middle))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: NSPoint(x: width * 0.9, y: middle.y)))
        check("a drag moves the knob", dragged != nil)
        check("…without setting anything until it is let go", releases == 0)
        view.mouseExited(with: mouseEvent(.mouseMoved, at: NSPoint(x: -4, y: middle.y)))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: NSPoint(x: width * 0.95, y: middle.y)))
        check("…and a drag off the edge is still a drag", dragged == width * 0.95)
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: NSPoint(x: width * 0.95, y: middle.y)))
        check("releasing sets the timer", releases == 1)

        if let up = wheelEvent(1), let down = wheelEvent(-1) {
            view.scrollWheel(with: up)
            check("the wheel lengthens the timer scrolling up", steps == 1, "\(steps)")
            view.scrollWheel(with: down)
            view.scrollWheel(with: down)
            check("…and shortens it scrolling down", steps == -1, "\(steps)")
            check("…without setting anything on its own", releases == 1)
        } else {
            note("scroll wheel not measured: synthetic wheel events unavailable")
        }
    }

    private static func mouseEvent(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                           windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    private static func wheelEvent(_ lines: Int32) -> NSEvent? {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line,
                                  wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0) else { return nil }
        return NSEvent(cgEvent: event)
    }

    private static func check(_ name: String, _ condition: Bool, _ detail: String = "") {
        let mark = condition ? "ok  " : "FAIL"
        if !condition { failures += 1 }
        let suffix = detail.isEmpty ? "" : " (\(detail))"
        FileHandle.standardError.write(Data("\(mark) \(name)\(suffix)\n".utf8))
    }
}

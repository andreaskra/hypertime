import Foundation
import HypertimeCore
import Observation

/// One bar in the chart: a bucket of time split into per-project segments.
struct ChartBucket: Identifiable {
    let id: String
    let label: String
    let day: LocalDate?                      // nil for the day view's per-project bars
    let segments: [ChartSegment]
    var total: Seconds { segments.reduce(0) { $0 + $1.seconds } }
}

struct ChartSegment: Identifiable {
    let id: UUID
    let name: String
    let slot: Int
    let seconds: Seconds
}

@MainActor
@Observable
final class ReportsViewModel {
    private let model: AppModel

    /// Day · Week · Month · Year are zoom presets on one continuous axis, not four separate
    /// views. Pinching between them is the same movement by hand.
    var kind: PeriodKind = .day {
        didSet {
            guard kind != oldValue else { return }
            setZoom(days: Double(Period.spanLength(for: kind)))
        }
    }

    /// Rebuilds the period for the current kind and alignment, keeping the day in view.
    private func rebuildPeriod() {
        if isSliding {
            let length = Period.spanLength(for: kind)
            // The window ends on the day being looked at, so stepping back walks into the past.
            let end = min(anchor, model.today)
            period = .span(start: model.day(end, offsetBy: -(length - 1)), days: length)
        } else {
            period = Period.containing(anchor, kind: kind, calendar: calendar, weekStart: weekStart)
        }
        reload()
    }
    private(set) var period: Period
    private(set) var report: Report?
    private(set) var anchor: LocalDate
    var errorMessage: String?
    var newProjectName = ""

    /// Calendar periods snap to weeks and months; a sliding window keeps the same width and
    /// steps a day at a time, so any arbitrary stretch can be looked at.
    var isSliding = false {
        didSet {
            guard isSliding != oldValue else { return }
            if isSliding { rebuildWindow() } else { rebuildPeriod() }
        }
    }

    // MARK: - The continuous window (scroll and zoom)

    /// How many days are on screen. Fractional, because zooming is continuous: pinching
    /// should not jump between a week and a month with nothing in between.
    private(set) var visibleDays: Double = 7

    /// How far the right-hand edge sits in the past, in days. Fractional for the same reason
    /// panning is: a window that can only move a whole day at a time is not scrolling, it is
    /// paging, and at week width a day is a seventh of the screen.
    private(set) var windowEnd: Double = 0

    /// The part of a day the window is offset by, which the chart translates itself by so the
    /// bars slide under the cursor rather than snapping.
    var subDayOffset: Double { windowEnd - windowEnd.rounded(.down) }

    static let minimumVisibleDays: Double = 1
    static let maximumVisibleDays: Double = 730

    /// Two-finger scroll. Positive moves into the past.
    func pan(byDays delta: Double) {
        guard delta != 0 else { return }
        setWindow(end: windowEnd + delta, days: visibleDays)
    }

    /// Pinch. `focus` is where the cursor sits across the plot, 0 at the left edge and 1 at
    /// the right, so the day under the fingers stays under the fingers.
    func zoom(by factor: Double, focus: Double) {
        guard factor > 0, factor != 1 else { return }
        let days = (visibleDays / factor).clamped(to: Self.minimumVisibleDays...Self.maximumVisibleDays)
        guard days != visibleDays else { return }
        // Days from the right edge to the cursor stay put across the change of scale.
        let fromRight = (1 - focus) * visibleDays
        let newFromRight = (1 - focus) * days
        setWindow(end: windowEnd + (newFromRight - fromRight), days: days)
    }

    func setZoom(days: Double) {
        setWindow(end: windowEnd, days: days.clamped(to: Self.minimumVisibleDays...Self.maximumVisibleDays))
    }

    private func setWindow(end: Double, days: Double) {
        // Nothing is tracked in the future, so the window stops with today at its right edge.
        let clampedEnd = max(end, 0)
        let changed = clampedEnd != windowEnd || days != visibleDays
        windowEnd = clampedEnd
        visibleDays = days
        guard changed else { return }
        rebuildWindow()
    }

    private func rebuildWindow() {
        let whole = max(Int(visibleDays.rounded()), 1)
        let endOffset = Int(windowEnd.rounded(.down))
        let end = model.day(model.today, offsetBy: -endOffset)
        anchor = end
        // Exactly the days on screen, and no more: the window is also what the totals, the
        // averages, the table and the export all report, so a day added for the chart's
        // convenience would be a day added to the arithmetic.
        period = .span(start: model.day(end, offsetBy: -(whole - 1)), days: whole)
        reload()
    }

    enum Presentation: String, CaseIterable { case chart, table }
    var presentation: Presentation = .chart
    /// Projects the user has unticked. Hiding never re-assigns colours to the survivors.
    var hiddenProjects: Set<UUID> = []
    /// Colour slots, assigned from the *unfiltered* report in a fixed order.
    private(set) var seriesOrder: [UUID] = []

    init(model: AppModel) {
        self.model = model
        let today = model.today
        anchor = today
        period = .day(today)
        visibleDays = Double(Period.spanLength(for: kind))
        rebuildWindow()
    }

    private var calendar: Calendar { model.clock.calendar }
    private var weekStart: Weekday { model.settings.weekStart }

    var title: String { period.title(calendar: calendar, weekStart: weekStart) }
    var days: [LocalDate] { period.days(calendar: calendar, weekStart: weekStart) }
    var isToday: Bool { period.contains(model.today, calendar: calendar, weekStart: weekStart) }
    var todayDate: LocalDate { model.today }

    /// Months of a year period, for the year breakdown.
    var months: [Period] { period.months(calendar: calendar, weekStart: weekStart) }

    func reload() {
        do {
            report = try model.reportBuilder.report(for: period)
            // Slots come from the unfiltered ranking, so unticking a project never repaints
            // the ones that remain.
            seriesOrder = (report?.rows ?? []).map(\.project.id)
            hiddenProjects = hiddenProjects.intersection(seriesOrder)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The arrows page by a whole window, or step a day at a time while the window is set to
    /// slide (R-18). Scrolling is for anything finer than either.
    func go(_ delta: Int) {
        pan(byDays: Double(-delta) * (isSliding ? 1 : visibleDays))
    }

    func goToToday() {
        setWindow(end: 0, days: visibleDays)
        rebuildWindow()
    }

    /// True when the window's right edge is on today, which is what the Today button undoes.
    var isAtToday: Bool { windowEnd < 0.5 }

    func showDay(_ day: LocalDate) {
        show(.day, anchoredAt: day)
    }

    /// Drilling down from a grid cell: month cells open the day, year cells open the month.
    func show(_ kind: PeriodKind, anchoredAt day: LocalDate) {
        anchor = day
        if self.kind == kind {
            rebuildPeriod()
        } else {
            self.kind = kind                              // didSet rebuilds the period and reloads
        }
    }

    /// Busiest day in the period, for the month view's intensity cells.
    var busiestDaySeconds: Seconds {
        report?.perDayTotal.values.max() ?? 0
    }

    func isToday(_ day: LocalDate) -> Bool { day == model.today }

    // MARK: - Editing

    func text(_ seconds: Seconds) -> String {
        model.formatter.string(seconds, style: model.settings.timeDisplayStyle)
    }

    func liveSeconds(project: UUID, day: LocalDate) -> Seconds {
        model.liveSeconds(project: project, day: day)
    }

    @discardableResult
    func saveTotal(project: UUID, day: LocalDate, text: String) -> Bool {
        guard model.editTotal(project: project, day: day, text: text) else {
            errorMessage = "Could not read “\(text)”. Try 1:30, 90m or +15m."
            return false
        }
        errorMessage = nil
        reload()
        return true
    }

    func addProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            _ = try model.store.findOrCreateProject(named: name)
            newProjectName = ""
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rename(_ project: Project, to name: String) {
        do {
            try model.store.renameProject(id: project.id, to: name)
            reload()
        } catch StoreError.duplicateName(let clash) {
            errorMessage = "A project named “\(clash)” already exists."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setArchived(_ project: Project, _ archived: Bool) {
        try? model.store.setArchived(id: project.id, archived)
        reload()
    }

    func delete(_ project: Project) {
        model.engine.projectDeleted(project.id)
        try? model.store.deleteProject(id: project.id)
        reload()
    }

    var isEditable: Bool { kind == .day || kind == .week }

    // MARK: - Stats for the range on screen

    var total: Seconds { report?.total ?? 0 }
    var calendarDays: Int { max(report?.days.count ?? 0, 1) }
    var trackedDays: Int { (report?.perDayTotal.values.filter { $0 > 0 }.count) ?? 0 }
    /// Spread across every day in the range, worked or not.
    var averagePerDay: Seconds { total / calendarDays }
    /// Spread across the days that actually have time on them.
    var averagePerTrackedDay: Seconds { trackedDays > 0 ? total / trackedDays : 0 }
    var showsAverages: Bool { (report?.days.count ?? 0) > 1 }

    // MARK: - Chart

    /// Slot for a project, or `Series.maxSlots` for everything past the eighth ("Other").
    ///
    /// The slot is the project's own, fixed when it was created (TLD-07), not its rank in
    /// whatever period happens to be on screen. A colour that changes between a week and a
    /// month is not a code for anything, and it cannot be shared with the popup's timeline.
    func slot(for project: UUID) -> Int {
        model.colorSlot(for: project)
    }

    func isVisible(_ project: UUID) -> Bool { !hiddenProjects.contains(project) }

    func toggle(_ project: UUID) {
        if hiddenProjects.contains(project) {
            hiddenProjects.remove(project)
        } else {
            hiddenProjects.insert(project)
        }
    }

    /// Clicking a project in the chart or legend shows only that one.
    func isolate(_ project: UUID) {
        hiddenProjects = Set(seriesOrder).subtracting([project])
    }

    func selectAll() { hiddenProjects.removeAll() }

    var hasHiddenProjects: Bool { !hiddenProjects.isEmpty }

    var legendRows: [ReportRow] { report?.rows ?? [] }

    /// How wide one bar is in days, chosen so a bar never gets too thin to see. A year of
    /// single days would be 365 slivers; a week of months would be one bar.
    enum Grain { case project, day, week, month }

    var grain: Grain {
        if visibleDays <= 1.5 { return .project }
        if visibleDays <= 70 { return .day }
        if visibleDays <= 400 { return .week }
        return .month
    }

    /// Bars for the window. The day view shows one bar per project; wider windows bucket by
    /// day, week or month and stack the projects inside each bar.
    var chartBuckets: [ChartBucket] {
        guard let report else { return [] }
        let rows = report.rows.filter { isVisible($0.project.id) }

        func segments(_ seconds: (ReportRow) -> Seconds) -> [ChartSegment] {
            rows.compactMap { row in
                let value = seconds(row)
                guard value > 0 else { return nil }
                return ChartSegment(id: row.project.id, name: row.project.name,
                                    slot: slot(for: row.project.id), seconds: value)
            }
        }

        switch grain {
        case .project:
            return rows.filter { $0.seconds > 0 }.map { row in
                ChartBucket(id: row.project.id.uuidString,
                            label: row.project.name,
                            day: nil,
                            segments: [ChartSegment(id: row.project.id, name: row.project.name,
                                                    slot: slot(for: row.project.id), seconds: row.seconds)])
            }
        case .day:
            return report.days.map { day in
                ChartBucket(id: day.isoString,
                            label: visibleDays <= 10 ? shortDayLabel(day) : String(day.day),
                            day: day,
                            segments: segments { $0.seconds(on: day) })
            }
        case .week, .month:
            // Group the window's days into runs, so one bar covers a week or a month.
            var groups: [(key: String, label: String, days: [LocalDate])] = []
            for day in report.days {
                let key: String
                let label: String
                if grain == .week {
                    let week = Period.containing(day, kind: .week, calendar: calendar, weekStart: weekStart)
                    key = week.range(calendar: calendar, weekStart: weekStart).lowerBound.isoString
                    label = String(day.day)
                } else {
                    key = "\(day.year)-\(day.month)"
                    label = monthInitial(Period.month(year: day.year, month: day.month))
                }
                if groups.last?.key == key {
                    groups[groups.count - 1].days.append(day)
                } else {
                    groups.append((key, label, [day]))
                }
            }
            return groups.map { group in
                ChartBucket(id: group.key,
                            label: group.label,
                            day: group.days.first,
                            segments: segments { row in group.days.reduce(0) { $0 + row.seconds(on: $1) } })
            }
        }
    }

    var chartMaximum: Seconds { max(chartBuckets.map(\.total).max() ?? 0, 1) }

    private func shortDayLabel(_ day: LocalDate) -> String {
        Period.day(day).shortTitle(calendar: calendar, weekStart: weekStart)
    }

    private func monthInitial(_ month: Period) -> String {
        guard case .month(_, let index) = month else { return "" }
        return String((DateFormatter().shortMonthSymbols?[index - 1] ?? "").prefix(1))
    }
}

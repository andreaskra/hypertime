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

    var kind: PeriodKind = .day {
        didSet { period = Period.containing(anchor, kind: kind, calendar: calendar, weekStart: weekStart); reload() }
    }
    private(set) var period: Period
    private(set) var report: Report?
    private(set) var anchor: LocalDate
    var errorMessage: String?
    var newProjectName = ""

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
        reload()
    }

    private var calendar: Calendar { model.clock.calendar }
    private var weekStart: Weekday { model.settings.weekStart }

    var title: String { period.title(calendar: calendar, weekStart: weekStart) }
    var days: [LocalDate] { period.days(calendar: calendar, weekStart: weekStart) }
    var isToday: Bool { period.contains(model.today, calendar: calendar, weekStart: weekStart) }
    var todayDate: LocalDate { model.today }

    /// Months of a year period, for the year breakdown.
    var months: [Period] {
        guard case .year(let year) = period else { return [] }
        return (1...12).map { .month(year: year, month: $0) }
    }

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

    func go(_ delta: Int) {
        period = period.shifted(by: delta, calendar: calendar, weekStart: weekStart)
        anchor = period.range(calendar: calendar, weekStart: weekStart).lowerBound
        reload()
    }

    func goToToday() {
        anchor = model.today
        period = Period.containing(anchor, kind: kind, calendar: calendar, weekStart: weekStart)
        reload()
    }

    func showDay(_ day: LocalDate) {
        show(.day, anchoredAt: day)
    }

    /// Drilling down from a grid cell: month cells open the day, year cells open the month.
    func show(_ kind: PeriodKind, anchoredAt day: LocalDate) {
        anchor = day
        if self.kind == kind {
            period = Period.containing(day, kind: kind, calendar: calendar, weekStart: weekStart)
            reload()
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

    // MARK: - Chart

    /// Slot for a project, or `Series.maxSlots` for everything past the eighth ("Other").
    func slot(for project: UUID) -> Int {
        guard let index = seriesOrder.firstIndex(of: project) else { return Tokens.Series.maxSlots }
        return index < Tokens.Series.maxSlots ? index : Tokens.Series.maxSlots
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

    /// Bars for the current period. Day shows one bar per project; the longer periods bucket by
    /// day (or month, for a year) and stack the projects inside each bar.
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

        switch kind {
        case .day:
            return rows.filter { $0.seconds > 0 }.map { row in
                ChartBucket(id: row.project.id.uuidString,
                            label: row.project.name,
                            day: nil,
                            segments: [ChartSegment(id: row.project.id, name: row.project.name,
                                                    slot: slot(for: row.project.id), seconds: row.seconds)])
            }
        case .week, .month:
            return report.days.map { day in
                ChartBucket(id: day.isoString,
                            label: kind == .week ? shortDayLabel(day) : String(day.day),
                            day: day,
                            segments: segments { $0.seconds(on: day) })
            }
        case .year:
            return months.map { month in
                let range = month.range(calendar: calendar, weekStart: weekStart)
                return ChartBucket(id: "\(month)",
                                   label: monthInitial(month),
                                   day: range.lowerBound,
                                   segments: segments { row in
                                       row.perDay.reduce(0) { $0 + (range.contains($1.key) ? $1.value : 0) }
                                   })
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

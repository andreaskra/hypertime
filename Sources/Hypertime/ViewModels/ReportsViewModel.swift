import Foundation
import HypertimeCore
import Observation

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
        if model.engine.currentProjectID == project.id { model.engine.stop() }
        try? model.store.deleteProject(id: project.id)
        reload()
    }

    var isEditable: Bool { kind == .day || kind == .week }
}

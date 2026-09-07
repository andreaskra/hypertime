import Foundation
import HypertimeCore
import Observation

/// Which control should own the keyboard (§6.4).
enum CheckInFocus: Hashable {
    case project
    case time
    case total(UUID)
    case none
}

/// One row of the project dropdown. The synthetic `create` row is first when the typed name
/// does not exist yet (R-06).
enum ProjectMatchRow: Identifiable, Hashable {
    case create(String)
    case project(Project, matchedIndices: [Int])

    var id: String {
        switch self {
        case .create(let name): return "create:" + name
        case .project(let project, _): return project.id.uuidString
        }
    }

    var name: String {
        switch self {
        case .create(let name): return name
        case .project(let project, _): return project.name
        }
    }
}

@MainActor
@Observable
final class CheckInViewModel {
    private let model: AppModel

    // Project field
    var fieldText = ""
    /// What the user actually typed; drives filtering while the field may show a highlighted name.
    var query = ""
    var matches: [ProjectMatchRow] = []
    var highlighted = 0

    // Time field
    var timeText = ""
    var isEditingTime = false
    var timeFieldInvalid = false

    // Today list
    var todayRows: [ReportRow] = []
    var invalidTotalRow: UUID?

    // Chrome
    var focus: CheckInFocus = .none
    var statusLine = ""
    var todayTotalText = ""
    var isPaused = false
    var isTracking = false

    /// Set by the panel controller.
    var onCommitted: (() -> Void)?
    var onDiscarded: (() -> Void)?
    var onClose: (() -> Void)?
    var onContentSizeChanged: (() -> Void)?
    var onPauseRequested: (() -> Void)?

    init(model: AppModel) {
        self.model = model
    }

    /// The dropdown is open exactly while the project field owns the keyboard (R-07).
    var showsProjectList: Bool { focus == .project && !matches.isEmpty }

    var timeStyle: TimeStyle { model.settings.timeDisplayStyle }
    var currentProjectID: UUID? { model.engine.currentProjectID }
    var pendingSeconds: Seconds { model.engine.pendingSeconds }

    // MARK: - Refresh

    /// Called every time the popup is about to be shown.
    func prepareForShow() {
        let current = model.currentProject
        query = ""
        fieldText = current?.name ?? ""
        isEditingTime = false
        timeFieldInvalid = false
        invalidTotalRow = nil
        refreshMatches(preselect: current?.id)
        refreshTime()
        refreshRows()
        focus = .none
    }

    /// One-second refresh while the popup is visible.
    func tick() {
        refreshTime()
        refreshStatus()
        refreshTotalsOnly()
    }

    func refreshTime() {
        guard !isEditingTime else { return }
        // Idle: no bucket to offer, so the field starts empty (§6.4).
        guard let pending = model.engine.pending else {
            timeText = ""
            return
        }
        timeText = model.formatter.string(pending.seconds, style: .clock)
    }

    func refreshStatus() {
        statusLine = model.statusSummary()
        todayTotalText = model.formatter.string(model.todayTotal(), style: timeStyle)
        isPaused = model.engine.status.isPaused
        isTracking = model.engine.status.isTracking
    }

    func refreshRows() {
        let before = todayRows.count
        todayRows = model.todayRows()
        refreshStatus()
        if todayRows.count != before { onContentSizeChanged?() }
    }

    /// Updates the live totals without rebuilding the row set (keeps editing stable).
    private func refreshTotalsOnly() {
        let fresh = model.todayRows()
        if fresh.count != todayRows.count || zip(fresh, todayRows).contains(where: { $0.project.id != $1.project.id }) {
            todayRows = fresh
            onContentSizeChanged?()
        } else {
            todayRows = fresh
        }
    }

    func refreshMatches(preselect: UUID? = nil) {
        let projects = model.projects()
        let ranked = FuzzyMatcher.rank(query, in: projects, key: \.name, recency: \.lastUsedAt)
        var rows: [ProjectMatchRow] = ranked.map { .project($0.item, matchedIndices: $0.matchedIndices) }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, FuzzyMatcher.exactMatch(trimmed, in: projects, key: \.name) == nil {
            rows.insert(.create(trimmed), at: 0)
        }
        matches = rows

        if let preselect, let index = rows.firstIndex(where: {
            if case .project(let p, _) = $0 { return p.id == preselect }
            return false
        }) {
            highlighted = index
        } else {
            highlighted = 0
        }
    }

    // MARK: - Project field

    func projectTextChanged(_ text: String) {
        fieldText = text
        query = text
        refreshMatches()
    }

    /// ↑/↓ move the selection and mirror the highlighted name into the field (combobox semantics).
    func moveSelection(by delta: Int) {
        guard !matches.isEmpty else { return }
        let count = matches.count
        highlighted = ((highlighted + delta) % count + count) % count
        fieldText = matches[highlighted].name
    }

    var highlightedRow: ProjectMatchRow? {
        matches.indices.contains(highlighted) ? matches[highlighted] : nil
    }

    /// The name a commit would use: the field text, which arrow keys keep in sync with the list.
    var effectiveName: String {
        fieldText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func selectRow(_ index: Int) {
        guard matches.indices.contains(index) else { return }
        highlighted = index
        fieldText = matches[index].name
    }

    // MARK: - Time field

    func timeTextChanged(_ text: String) {
        timeText = text
        timeFieldInvalid = false
        // Clearing the field hands the display back to the live counter (§6.4).
        isEditingTime = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !isEditingTime { refreshTime() }
    }

    /// ↑/↓ in the time field: ±1 min, ±5 min with Shift, ±1 h with Option.
    func adjustTime(by direction: Int, step: Seconds) {
        let current = (try? model.parser.parse(timeText)).map(\.seconds) ?? model.engine.pendingSeconds
        let updated = min(max(current + direction * step, 0), 86_400)
        isEditingTime = true
        timeText = model.formatter.string(updated, style: .clock)
        timeFieldInvalid = false
    }

    // MARK: - Commands

    func commit() {
        let name = effectiveName
        guard !name.isEmpty else {
            focus = .project
            return
        }
        guard (try? model.parser.parseAbsolute(timeText)) != nil else {
            timeFieldInvalid = true
            focus = .time
            return
        }
        guard model.commit(name: name, timeText: timeText) else {
            timeFieldInvalid = true
            return
        }
        isEditingTime = false
        onCommitted?()
    }

    func discard() {
        model.engine.discardPending()
        isEditingTime = false
        refreshTime()
        onDiscarded?()
    }

    func close() {
        onClose?()
    }

    func requestPause() {
        onPauseRequested?()
    }

    func resume() {
        model.engine.resume()
        refreshStatus()
    }

    /// Saves an edited total from the today list (R-17). Returns false when the text is unparsable.
    @discardableResult
    func saveTotal(projectID: UUID, text: String) -> Bool {
        guard model.editTotal(project: projectID, day: model.today, text: text) else {
            invalidTotalRow = projectID
            return false
        }
        invalidTotalRow = nil
        isEditingTime = false
        refreshTime()
        refreshRows()
        return true
    }

    func totalText(for row: ReportRow) -> String {
        model.formatter.string(row.seconds, style: timeStyle)
    }

    func isCurrent(_ row: ReportRow) -> Bool {
        row.project.id == model.engine.currentProjectID
    }

    // MARK: - Focus movement (§6.4)

    func focusNext(from current: CheckInFocus) {
        switch current {
        case .project:
            focus = .time
        case .time:
            focus = todayRows.first.map { .total($0.project.id) } ?? .none
        case .total(let id):
            if let index = todayRows.firstIndex(where: { $0.project.id == id }), index + 1 < todayRows.count {
                focus = .total(todayRows[index + 1].project.id)
            } else {
                focus = .none
            }
        case .none:
            focus = .project
        }
    }

    func focusPrevious(from current: CheckInFocus) {
        switch current {
        case .project:
            focus = .none
        case .time:
            focus = .project
        case .total(let id):
            if let index = todayRows.firstIndex(where: { $0.project.id == id }), index > 0 {
                focus = .total(todayRows[index - 1].project.id)
            } else {
                focus = .time
            }
        case .none:
            focus = .project
        }
    }
}

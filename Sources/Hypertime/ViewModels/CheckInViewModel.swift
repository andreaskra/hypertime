import Foundation
import HypertimeCore
import Observation

/// Which control should own the keyboard (§6.4).
enum CheckInFocus: Hashable {
    case project
    case time
    case total(UUID)
    /// The Confirm button ends the Tab order (§6.4, design handoff "Focus & keyboard").
    case confirm
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
    /// The dropdown is a transient state, not "the project field has focus": it opens when the
    /// user types, arrows into it or clicks the chevron, and closes on pick, Esc, Tab or commit.
    var isProjectListOpen = false

    // Time field
    var timeText = ""
    var isEditingTime = false
    /// Bumped whenever the amount is replaced on purpose, so the field knows to take it even
    /// while it holds the caret.
    private(set) var timeTextRevision = 0
    var timeFieldInvalid = false
    /// Whether ↩ has already taken what is in the time field. The first ↩ normalises the entry
    /// ("90m" → "1:30:00") and stops there; only a second one commits the popup, so a typo is
    /// visible as a number before it becomes a saved entry. Reset by anything that changes the
    /// value, and by leaving the field.
    var isTimeAccepted = false

    // Day list — "today" by default, but it steps back and forward (R-17/R-18 in the popup).
    var visibleDay: LocalDate = LocalDate(year: 1970, month: 1, day: 1)
    private var hasVisibleDay = false
    var todayRows: [ReportRow] = []
    var invalidTotalRow: UUID?

    // Tasks (Phase 4)
    var tasks: [TaskItem] = []
    var isAddingTask = false
    var newTaskTitle = ""
    /// Rows mid-animation: completing slides out, deleting shrinks away.
    var completingTaskID: UUID?
    var deletingTaskID: UUID?
    /// The task whose timer just reached zero, which the popup asks about (T-12).
    var expiredTaskID: UUID?

    // Chrome
    var focus: CheckInFocus = .none {
        didSet {
            if focus != .project { isProjectListOpen = false }
            // Leaving the field forgets that ↩ had taken its value: coming back should show the
            // same two steps as arriving the first time, not commit on the first press.
            if focus != .time {
                isTimeAccepted = false
                // An empty field means "no opinion": hand it back to the live counter once the
                // user has moved on. A field with something in it keeps what they typed.
                if timeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    isEditingTime = false
                    refreshTime()
                }
            }
        }
    }
    var statusLine = ""
    /// Total for the day on screen, not for today — the list steps back.
    var todayTotalText: String { model.display(todayRows.reduce(0) { $0 + $1.seconds }) }
    var isPaused = false
    var isTracking = false

    /// True from the moment a commit is written until the confirm animation says the numbers may
    /// catch up. The write is immediate; only the display is held, so nothing is at risk if the
    /// animation is cut short.
    private(set) var isCommitting = false

    /// Set by the panel controller.
    var onCommitted: (() -> Void)?
    var onDiscarded: (() -> Void)?
    var onClose: (() -> Void)?
    var onContentSizeChanged: (() -> Void)?
    var onPauseRequested: (() -> Void)?
    var onMenuRequested: (() -> Void)?
    var onDayPickerRequested: (() -> Void)?
    /// The panel owns animation timing; it calls `commitFinish`/`commitDelete` when the row has
    /// finished playing out.
    var onTaskCompleting: (() -> Void)?
    var onTaskDeleting: (() -> Void)?

    init(model: AppModel) {
        self.model = model
    }

    /// The dropdown is visible while it is open and the project field owns the keyboard (R-07).
    var showsProjectList: Bool { isProjectListOpen && focus == .project && !matches.isEmpty }

    var timeStyle: TimeStyle { model.settings.timeDisplayStyle }

    /// The project time is currently accruing to — not what the field says.
    var currentProjectName: String? { model.currentProject?.name }
    var currentProjectID: UUID? { model.engine.currentProjectID }
    var pendingSeconds: Seconds { model.engine.pendingSeconds }

    // MARK: - Refresh

    /// Called every time the popup is about to be shown.
    /// `keepingDay` is true when the user opened the popup themselves: it stays on whatever day
    /// they were last looking at. A scheduled nudge always comes back to today.
    func prepareForShow(keepingDay: Bool = false) {
        isCommitting = false
        if !keepingDay || !hasVisibleDay { visibleDay = model.today }
        hasVisibleDay = true
        // R-05: the most recently used project is preselected, even on a fresh launch.
        let current = model.currentProject ?? model.projects().first
        query = ""
        fieldText = current?.name ?? ""
        isEditingTime = false
        timeFieldInvalid = false
        invalidTotalRow = nil
        isProjectListOpen = false
        refreshMatches(preselect: current?.id)
        refreshTime()
        refreshTasks()
        refreshRows()
        focus = .none
    }

    /// One-second refresh while the popup is visible.
    func tick() {
        refreshTime()
        refreshStatus()
        refreshTotalsOnly()
        if tasks.contains(where: { isRunning($0) }) { breakdown = model.taskBreakdown(for: visibleDay) }
    }

    /// Replaces the amount on purpose — the field will take it even mid-edit.
    func pushTimeText(_ text: String) {
        timeText = text
        timeTextRevision += 1
    }

    func refreshTime() {
        // A field with the keyboard never has its text replaced underneath the caret.
        guard !isCommitting, !isEditingTime, focus != .time else { return }
        // Idle: no bucket to offer, so the field starts empty (§6.4).
        guard let pending = model.engine.pending else {
            pushTimeText("")
            return
        }
        pushTimeText(model.formatter.string(pending.seconds, style: .clock))
    }

    func refreshStatus() {
        guard !isCommitting else { return }
        statusLine = model.statusSummary()
        isPaused = model.engine.status.isPaused
        isTracking = model.engine.status.isTracking
    }

    /// True while the list shows today; only then does it carry live pending time.
    var isShowingToday: Bool { visibleDay == model.today }

    /// "TODAY", or the date when stepped back. The artboard's label, with the count appended by
    /// the view when the list scrolls.
    var dayLabel: String {
        isShowingToday ? "TODAY" : model.dayLabel(visibleDay).uppercased()
    }

    /// Tomorrow has nothing in it and nothing can be tracked there, so forward stops at today.
    var canStepForward: Bool { visibleDay < model.today }

    func stepDay(_ delta: Int) {
        let target = model.day(visibleDay, offsetBy: delta)
        guard target <= model.today else { return }
        visibleDay = target
        refreshRows()
    }

    func showDay(_ day: LocalDate) {
        guard day <= model.today else { return }
        visibleDay = day
        refreshRows()
    }

    func isFuture(_ day: LocalDate) -> Bool { day > model.today }

    func goToToday() {
        showDay(model.today)
    }

    /// Days in the visible day's month that have time, for the calendar's dots.
    func markedDays(in month: LocalDate) -> Set<LocalDate> {
        model.daysWithTime(inMonthOf: month)
    }

    func monthGrid(for month: LocalDate) -> [[LocalDate?]] { model.monthGrid(for: month) }
    func monthTitle(_ month: LocalDate) -> String { model.monthTitle(month) }
    var weekdayInitials: [String] { model.weekdayInitials }
    var todayDate: LocalDate { model.today }
    func month(_ day: LocalDate, offsetBy delta: Int) -> LocalDate {
        // Stepping months from the 1st avoids landing short in February.
        model.day(LocalDate(year: day.year, month: day.month, day: 1), offsetBy: delta > 0 ? 32 : -1)
    }

    // MARK: - Tasks

    var activeTaskID: UUID? { model.engine.activeTaskID }

    func refreshTasks() {
        tasks = model.openTasks()
    }

    var expiredTask: TaskItem? { expiredTaskID.flatMap(model.task) }

    func isRunning(_ task: TaskItem) -> Bool { task.id == model.engine.activeTaskID }

    /// Clicking a task starts it; clicking the running one pauses it (T-03).
    func toggleTask(_ task: TaskItem) {
        if isRunning(task) {
            model.engine.stopTask()
        } else {
            model.engine.startTask(task)
        }
        refreshAfterTaskChange()
    }

    func elapsedText(for task: TaskItem) -> String {
        model.display(model.engine.liveTaskSeconds(task.id))
    }

    /// Remaining time on a timed task; negative once it has overshot.
    func remaining(for task: TaskItem) -> Seconds? { model.engine.taskRemaining(task) }

    func remainingText(for task: TaskItem) -> String? {
        guard let left = remaining(for: task) else { return nil }
        return (left < 0 ? "+" : "") + model.formatter.string(abs(left), style: .clock)
    }

    func addTask() {
        isAddingTask = true
        newTaskTitle = ""
    }

    func commitNewTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            isAddingTask = false
            return
        }
        // The + button opens the task under the project the popup is showing.
        model.createTask(title: title, projectName: effectiveName)
        newTaskTitle = ""
        isAddingTask = false
        refreshAfterTaskChange()
    }

    func cancelNewTask() {
        isAddingTask = false
        newTaskTitle = ""
    }

    func finishTask(_ task: TaskItem) {
        guard completingTaskID == nil else { return }
        completingTaskID = task.id
        if task.id == expiredTaskID { expiredTaskID = nil }
        onTaskCompleting?()
    }

    /// Called when the completion animation has played out.
    func commitFinish() {
        guard let id = completingTaskID else { return }
        completingTaskID = nil
        model.engine.finishTask(id)
        refreshAfterTaskChange()
    }

    func deleteTask(_ task: TaskItem) {
        guard deletingTaskID == nil else { return }
        deletingTaskID = task.id
        if task.id == expiredTaskID { expiredTaskID = nil }
        onTaskDeleting?()
    }

    func commitDelete() {
        guard let id = deletingTaskID else { return }
        deletingTaskID = nil
        model.engine.taskDeleted(id)
        try? model.store.deleteTask(id: id)
        refreshAfterTaskChange()
    }

    func setTimer(_ task: TaskItem, text: String) {
        guard let parsed = try? model.parser.parseAbsolute(text), parsed > 0 else { return }
        try? model.store.setTaskTimer(id: task.id, seconds: parsed)
        refreshAfterTaskChange()
    }

    func clearTimer(_ task: TaskItem) {
        try? model.store.setTaskTimer(id: task.id, seconds: nil)
        refreshAfterTaskChange()
    }

    /// "Keep working" on an expired timer: the task runs on, untimed (T-12).
    func keepWorking() {
        if let task = expiredTask { clearTimer(task) }
        expiredTaskID = nil
    }

    func move(_ task: TaskItem, to project: Project) {
        try? model.store.updateTask(id: task.id, projectID: project.id)
        refreshAfterTaskChange()
    }

    func rename(_ task: TaskItem, to title: String) {
        try? model.store.updateTask(id: task.id, title: title)
        refreshAfterTaskChange()
    }

    var allProjects: [Project] { model.projects() }

    private func refreshAfterTaskChange() {
        refreshTasks()
        refreshRows()
        refreshStatus()
        refreshTime()
    }

    /// Tasks with time on the visible day, indented under their project.
    func taskRows(under project: UUID) -> [(task: TaskItem, seconds: Seconds)] {
        breakdown[project] ?? []
    }

    private var breakdown: [UUID: [(task: TaskItem, seconds: Seconds)]] = [:]

    func refreshRows() {
        guard !isCommitting else { return }
        let before = todayRows.count
        todayRows = model.rows(for: visibleDay)
        breakdown = model.taskBreakdown(for: visibleDay)
        refreshStatus()
        if todayRows.count != before { onContentSizeChanged?() }
    }

    /// Updates the live totals without rebuilding the row set (keeps editing stable).
    private func refreshTotalsOnly() {
        guard !isCommitting else { return }
        let fresh = model.rows(for: visibleDay)
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
            // Last, under a separator: ↩ should land on the best match, not quietly make a
            // fourth project called "de" (artboard A-popup dropdown).
            rows.append(.create(trimmed))
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
        isProjectListOpen = true
    }

    func openProjectList() {
        guard !matches.isEmpty else { return }
        isProjectListOpen = true
    }

    func closeProjectList() {
        isProjectListOpen = false
    }

    func toggleProjectList() {
        if isProjectListOpen {
            closeProjectList()
        } else {
            // Reopening after a pick shows every project again, with the picked one highlighted.
            query = ""
            refreshMatches(preselect: model.currentProject.map(\.id))
            if let index = matches.firstIndex(where: { $0.name == fieldText }) { highlighted = index }
            isProjectListOpen = true
        }
    }

    /// ↑/↓ move the selection and mirror the highlighted name into the field (combobox semantics).
    /// The first press only opens the dropdown, so nothing changes under the user unseen.
    func moveSelection(by delta: Int) {
        guard !matches.isEmpty else { return }
        guard isProjectListOpen else {
            openProjectList()
            return
        }
        let count = matches.count
        highlighted = ((highlighted + delta) % count + count) % count
        fieldText = matches[highlighted].name
    }

    var highlightedRow: ProjectMatchRow? {
        matches.indices.contains(highlighted) ? matches[highlighted] : nil
    }

    /// ↩ with the dropdown open belongs to the dropdown: it takes the highlighted row and closes
    /// the list, exactly as clicking it does, rather than committing the popup past a list the
    /// user is still reading. Returns true when the press was consumed; with no list open the
    /// caller commits as before.
    func acceptHighlightedRow() -> Bool {
        guard showsProjectList, matches.indices.contains(highlighted) else { return false }
        selectRow(highlighted)
        return true
    }

    /// The name a commit would use: the field text, which arrow keys keep in sync with the list.
    var effectiveName: String {
        fieldText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Picking a row fills the field and closes the dropdown — committing stays an explicit ↩.
    func selectRow(_ index: Int) {
        guard matches.indices.contains(index) else { return }
        let row = matches[index]
        fieldText = row.name
        // Drop the filter so reopening the list shows everything, with this project highlighted.
        query = ""
        if case .project(let project, _) = row {
            refreshMatches(preselect: project.id)
        } else {
            refreshMatches()
        }
        isProjectListOpen = false
        focus = .project
    }

    // MARK: - Time field

    func timeTextChanged(_ text: String) {
        timeText = text
        timeFieldInvalid = false
        isTimeAccepted = false
        isEditingTime = true
    }

    /// The counter stops the moment the field takes the keyboard, not on the first keystroke:
    /// text that rewrites itself every second cannot be edited, only retyped.
    func beginEditingTime() {
        focus = .time
        isEditingTime = true
    }

    /// ↑/↓ in the time field: ±1 min, ±5 min with Shift, ±1 h with Option.
    func adjustTime(by direction: Int, step: Seconds) {
        let current = (try? model.parser.parse(timeText)).map(\.seconds) ?? model.engine.pendingSeconds
        let updated = min(max(current + direction * step, 0), 86_400)
        isEditingTime = true
        pushTimeText(model.formatter.string(updated, style: .clock))
        timeFieldInvalid = false
        isTimeAccepted = false
    }

    /// The first ↩ in the time field takes the time, not the popup. Typing "90m" and pressing
    /// once used to save an amount the user had never seen rendered; now the first press
    /// normalises it to "1:30:00" on screen and the second commits. Returns true when the press
    /// was consumed here.
    func acceptTimeEntry() -> Bool {
        guard !isTimeAccepted else { return false }
        guard let seconds = try? model.parser.parseAbsolute(timeText) else {
            // A press that reports an error is still a press this field handled: falling through
            // to commit() would show the same complaint twice over.
            timeFieldInvalid = true
            return true
        }
        pushTimeText(model.formatter.string(seconds, style: .clock))
        isEditingTime = true
        isTimeAccepted = true
        return true
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
        guard !isCommitting else { return }                  // a second ↩ mid-animation
        guard model.commit(name: name, timeText: timeText) else {
            timeFieldInvalid = true
            return
        }
        // Written already; the panel now runs the confirm bounce and calls back below.
        isCommitting = true
        isProjectListOpen = false
        onCommitted?()
    }

    /// Called by the confirm animation at the point the numbers should change: the amount drops
    /// to zero and the committed project's total jumps, in the same frame.
    func revealCommittedTotals() {
        isCommitting = false
        isEditingTime = false
        isTimeAccepted = false
        refreshTime()
        refreshRows()
        refreshStatus()
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

    func requestMenu() {
        onMenuRequested?()
    }

    func requestDayPicker() {
        onDayPickerRequested?()
    }

    /// The header control: pause while tracking, resume while paused, start when idle. Idle is
    /// the state the popup opens in after a launch or a quit, so it needs a way back in that is
    /// not "confirm some amount of time".
    func toggleTracking() {
        if isPaused {
            resume()
        } else if isTracking {
            requestPause()
        } else {
            guard model.startTracking(name: effectiveName) else {
                focus = .project
                return
            }
            refreshStatus()
            refreshRows()
            refreshTime()
        }
    }

    /// Nothing to start when no project is named and none is current.
    var canToggleTracking: Bool {
        isTracking || isPaused || !effectiveName.isEmpty
    }

    var trackingToggleHelp: String {
        if isPaused { return "Resume tracking" }
        if isTracking { return "Pause tracking" }
        let name = effectiveName
        return name.isEmpty ? "Start tracking" : "Start tracking \(name)"
    }

    func resume() {
        model.engine.resume()
        refreshStatus()
    }

    /// Saves an edited total from the today list (R-17). Returns false when the text is unparsable.
    @discardableResult
    func saveTotal(projectID: UUID, text: String) -> Bool {
        guard model.editTotal(project: projectID, day: visibleDay, text: text) else {
            invalidTotalRow = projectID
            return false
        }
        invalidTotalRow = nil
        isEditingTime = false
        refreshTime()
        refreshRows()
        return true
    }

    func display(_ seconds: Seconds) -> String { model.display(seconds) }

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
            focus = todayRows.first.map { .total($0.project.id) } ?? .confirm
        case .total(let id):
            if let index = todayRows.firstIndex(where: { $0.project.id == id }), index + 1 < todayRows.count {
                focus = .total(todayRows[index + 1].project.id)
            } else {
                focus = .confirm
            }
        case .confirm, .none:
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
        case .confirm:
            focus = todayRows.last.map { .total($0.project.id) } ?? .time
        case .none:
            focus = .project
        }
    }
}

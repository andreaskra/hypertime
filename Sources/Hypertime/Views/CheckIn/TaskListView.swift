import AppKit
import SwiftUI
import HypertimeCore

/// The todo list above the day breakdown. Clicking a task hands it the clock; the checkmark
/// finishes it; the ⋯ menu carries everything else (T-02 … T-06).
struct TaskListView: View {
    @Bindable var viewModel: CheckInViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s1) {
            header
            if let task = viewModel.expiredTask {
                TimerExpiredBanner(viewModel: viewModel, task: task)
            }
            ForEach(viewModel.tasks) { task in
                TaskRowView(viewModel: viewModel, task: task)
            }
            if viewModel.isAddingTask {
                NewTaskField(viewModel: viewModel)
            }
        }
        .animation(Tokens.Motion.taskAppear.animation(reduceMotion: reduceMotion), value: viewModel.tasks)
        .animation(Tokens.Motion.taskAppear.animation(reduceMotion: reduceMotion), value: viewModel.isAddingTask)
    }

    private var header: some View {
        HStack(spacing: Tokens.Space.s1) {
            Text("TASKS")
                .font(Tokens.Typography.caption)
                .tracking(0.5)
                .foregroundStyle(Tokens.Palette.textTertiary.color)
            Spacer()
            Button { viewModel.addTask() } label: {
                Image(systemName: Tokens.Icons.addProject)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Tokens.Palette.accent)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New task under \(viewModel.effectiveName)")
        }
        .padding(.horizontal, Tokens.Space.rowInset)
    }
}

// MARK: - Row

private struct TaskRowView: View {
    @Bindable var viewModel: CheckInViewModel
    let task: TaskItem

    @State private var isHovering = false
    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isRunning: Bool { viewModel.isRunning(task) }
    private var isCompleting: Bool { viewModel.completingTaskID == task.id }
    private var isDeleting: Bool { viewModel.deletingTaskID == task.id }

    var body: some View {
        HStack(spacing: Tokens.Space.s2) {
            Button { viewModel.finishTask(task) } label: {
                Image(systemName: isCompleting ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(isCompleting ? Tokens.Palette.success.color
                                     : (isRunning ? Tokens.Palette.accent : Tokens.Palette.textTertiary.color))
            }
            .buttonStyle(.plain)
            .help("Finish \(task.title)")

            Button { viewModel.toggleTask(task) } label: {
                HStack(spacing: Tokens.Space.s2) {
                    Text(task.title)
                        .font(isRunning ? Tokens.Typography.listRowCurrent : Tokens.Typography.listRow)
                        .foregroundStyle(isCompleting
                                         ? Tokens.Palette.textTertiary.color
                                         : Tokens.Palette.textPrimary.color)
                        .strikethrough(isCompleting, color: Tokens.Palette.textTertiary.color)
                        .lineLimit(1)
                    Spacer(minLength: Tokens.Space.s2)
                    trailing
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isRunning ? "Pause \(task.title)" : "Start \(task.title)")

            TaskMenu(viewModel: viewModel, task: task)
                .opacity(isHovering || isRunning ? 1 : 0.35)
        }
        .padding(.horizontal, Tokens.Space.rowInset)
        .frame(height: Tokens.Size.listRowHeight)
        .background {
            RoundedRectangle(cornerRadius: Tokens.Radius.row, style: .continuous)
                .fill(isRunning ? Tokens.Palette.accent.opacity(0.12)
                      : (isHovering ? Tokens.Palette.rowHover.color : .clear))
        }
        .onHover { isHovering = $0 }
        // Appear with a pop; complete by sliding off to the left; delete by shrinking away.
        .scaleEffect(scale, anchor: .leading)
        .offset(x: isCompleting ? -Tokens.Size.popupWidth : 0)
        .opacity(isDeleting ? 0 : (isCompleting ? 0.4 : 1))
        .frame(height: isDeleting ? 0 : Tokens.Size.listRowHeight)
        .clipped()
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            withAnimation(Tokens.Motion.taskAppear.animation(reduceMotion: reduceMotion)) { }
        }
        .animation(Tokens.Motion.taskComplete.animation(reduceMotion: reduceMotion), value: isCompleting)
        .animation(Tokens.Motion.taskDelete.animation(reduceMotion: reduceMotion), value: isDeleting)
    }

    private var scale: CGFloat {
        if isDeleting { return 0.6 }
        return 1
    }

    @ViewBuilder
    private var trailing: some View {
        if let remaining = viewModel.remainingText(for: task) {
            Text(remaining)
                .font(Tokens.Typography.timeCell)
                .foregroundStyle((viewModel.remaining(for: task) ?? 0) < 0
                                 ? Tokens.Palette.invalid.color
                                 : (isRunning ? Tokens.Palette.accent : Tokens.Palette.rowTime.color))
        } else {
            Text(viewModel.elapsedText(for: task))
                .font(Tokens.Typography.timeCell)
                .foregroundStyle(isRunning ? Tokens.Palette.accent : Tokens.Palette.rowTime.color)
        }
    }
}

// MARK: - ⋯ menu

private struct TaskMenu: View {
    @Bindable var viewModel: CheckInViewModel
    let task: TaskItem

    var body: some View {
        Menu {
            Button(viewModel.isRunning(task) ? "Pause" : "Start") { viewModel.toggleTask(task) }
            Button("Finish") { viewModel.finishTask(task) }
            Divider()
            Menu("Timer") {
                ForEach([15, 25, 45, 60], id: \.self) { minutes in
                    Button("\(minutes) minutes") { viewModel.setTimer(task, text: "\(minutes)m") }
                }
                if task.timerSeconds != nil {
                    Divider()
                    Button("Clear timer") { viewModel.clearTimer(task) }
                }
            }
            Menu("Move to project") {
                ForEach(viewModel.allProjects) { project in
                    Button(project.name) { viewModel.move(task, to: project) }
                }
            }
            Divider()
            Button("Delete", role: .destructive) { viewModel.deleteTask(task) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Tokens.Palette.textSecondary.color)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 18)
    }
}

// MARK: - New task

private struct NewTaskField: View {
    @Bindable var viewModel: CheckInViewModel

    var body: some View {
        HStack(spacing: Tokens.Space.s2) {
            Image(systemName: "circle")
                .font(.system(size: 13))
                .foregroundStyle(Tokens.Palette.textTertiary.color)
            EditableField(
                text: viewModel.newTaskTitle,
                placeholder: "What needs doing?",
                font: Tokens.Typography.listRow,
                isFocused: true,
                onText: { viewModel.newTaskTitle = $0 },
                onCommand: { selector, _ in
                    switch selector {
                    case .insertNewline: viewModel.commitNewTask(); return true
                    case .cancelOperation: viewModel.cancelNewTask(); return true
                    default: return false
                    }
                },
                onEndEditing: { viewModel.commitNewTask() }
            )
        }
        .padding(.horizontal, Tokens.Space.rowInset)
        .frame(height: Tokens.Size.listRowHeight)
        .background {
            RoundedRectangle(cornerRadius: Tokens.Radius.row, style: .continuous)
                .fill(Tokens.Palette.fieldBackground.color)
        }
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }
}

// MARK: - Timer expiry (T-12)

private struct TimerExpiredBanner: View {
    @Bindable var viewModel: CheckInViewModel
    let task: TaskItem

    var body: some View {
        HStack(spacing: Tokens.Space.s2) {
            Image(systemName: "timer")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Tokens.Palette.accent)
            Text("“\(task.title)” is up")
                .font(Tokens.Typography.body)
                .foregroundStyle(Tokens.Palette.textPrimary.color)
                .lineLimit(1)
            Spacer(minLength: Tokens.Space.s2)
            Button("Keep working") { viewModel.keepWorking() }
                .hypertimeButton(.secondary)
            Button("Finish") { viewModel.finishTask(task) }
                .hypertimeButton(.primary)
        }
        .padding(.horizontal, Tokens.Space.rowInset)
        .padding(.vertical, Tokens.Space.s1)
        .background {
            RoundedRectangle(cornerRadius: Tokens.Radius.row, style: .continuous)
                .fill(Tokens.Palette.accent.opacity(0.14))
        }
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }
}

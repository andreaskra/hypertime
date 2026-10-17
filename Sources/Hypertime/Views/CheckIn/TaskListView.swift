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
            if viewModel.tasks.isEmpty && !viewModel.isAddingTask {
                Button { viewModel.addTask() } label: {
                    Text("Add a task to time a single piece of work")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(Tokens.Palette.textTertiary.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Tokens.Space.rowInset)
                        .frame(height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
            HoverButton(help: "New task under \(viewModel.effectiveName)",
                        tint: Tokens.Palette.accent) {
                viewModel.addTask()
            } label: {
                Image(systemName: Tokens.Icons.addProject)
                    .font(.system(size: 10, weight: .bold))
            }
        }
        .padding(.horizontal, Tokens.Space.rowInset)
    }
}

// MARK: - Row

private struct TaskRowView: View {
    @Bindable var viewModel: CheckInViewModel
    let task: TaskItem

    @State private var isHovering = false
    @State private var menuAnchor: CGRect = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isRunning: Bool { viewModel.isRunning(task) }
    private var isCompleting: Bool { viewModel.completingTaskID == task.id }
    private var isDeleting: Bool { viewModel.deletingTaskID == task.id }

    var body: some View {
        HStack(spacing: Tokens.Space.s2) {
            Text(task.title)
                .font(isRunning ? Tokens.Typography.listRowCurrent : Tokens.Typography.listRow)
                .foregroundStyle(isCompleting
                                 ? Tokens.Palette.textTertiary.color
                                 : Tokens.Palette.textPrimary.color)
                .strikethrough(isCompleting, color: Tokens.Palette.textTertiary.color)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: Tokens.Space.s2)
            trailing
            actions
        }
        .padding(.leading, Tokens.Space.rowInset)
        .padding(.trailing, Tokens.Space.s1)
        .frame(height: Tokens.Size.listRowHeight)
        .background {
            RoundedRectangle(cornerRadius: Tokens.Radius.row, style: .continuous)
                .fill(isRunning ? Tokens.Palette.accent.opacity(0.12)
                      : (isHovering ? Tokens.Palette.rowHover.color : .clear))
        }
        .onHover { isHovering = $0 }
        // Appear with a pop; complete by sliding off to the left; delete by shrinking away.
        .scaleEffect(isDeleting ? 0.6 : 1, anchor: .leading)
        .offset(x: isCompleting ? -Tokens.Size.popupWidth : 0)
        .opacity(isDeleting ? 0 : (isCompleting ? 0.4 : 1))
        .frame(height: isDeleting ? 0 : Tokens.Size.listRowHeight)
        .clipped()
        .animation(Tokens.Motion.taskComplete.animation(reduceMotion: reduceMotion), value: isCompleting)
        .animation(Tokens.Motion.taskDelete.animation(reduceMotion: reduceMotion), value: isDeleting)
    }

    /// Time sits in secondary ink: it is reference, not the point of the row.
    @ViewBuilder
    private var trailing: some View {
        if let remaining = viewModel.remainingText(for: task) {
            Text(remaining)
                .font(Tokens.Typography.timeCell)
                .foregroundStyle((viewModel.remaining(for: task) ?? 0) < 0
                                 ? Tokens.Palette.invalid.color
                                 : Tokens.Palette.textSecondary.color)
        } else {
            Text(viewModel.elapsedText(for: task))
                .font(Tokens.Typography.timeCell)
                .foregroundStyle(Tokens.Palette.textSecondary.color)
        }
    }

    /// Start · Stop · Resume on the left of the pair, then finish, then the menu. Exactly the
    /// actions the task's state allows, never a control that does nothing.
    private var actions: some View {
        HStack(spacing: 2) {
            if isRunning {
                TaskActionButton(symbol: Tokens.Icons.pause, help: "Stop \(task.title)",
                                 tint: Tokens.Palette.accent, filled: true) {
                    viewModel.stopTask(task)
                }
            } else {
                TaskActionButton(symbol: Tokens.Icons.resume,
                                 help: (viewModel.hasStarted(task) ? "Resume " : "Start ") + task.title,
                                 tint: Tokens.Palette.accent) {
                    viewModel.startTask(task)
                }
            }

            TaskActionButton(symbol: "checkmark", help: "Finish \(task.title)",
                             tint: Tokens.Palette.success.color) {
                viewModel.finishTask(task)
            }

            TaskActionButton(symbol: "ellipsis", help: "More") {
                viewModel.requestTaskMenu(task, anchor: menuAnchor)
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("panel")) } action: {
                menuAnchor = $0
            }
        }
        .opacity(isHovering || isRunning ? 1 : 0.55)
    }
}

/// A small square action in the app's button language: tinted glyph, hover fill, optional
/// filled treatment for the one action that is "currently true".
private struct TaskActionButton: View {
    let symbol: String
    let help: String
    var tint: Color?
    var filled = false
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(filled
                                 ? Tokens.Palette.onAccent.color
                                 : (tint ?? Tokens.Palette.textSecondary.color))
                .frame(width: 22, height: 20)
                .background {
                    RoundedRectangle(cornerRadius: Tokens.Radius.cell, style: .continuous)
                        .fill(filled
                              ? (tint ?? Tokens.Palette.accent)
                              : (isHovering ? (tint ?? Tokens.Palette.textSecondary.color).opacity(0.16)
                                 : Color.clear))
                }
                .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.cell, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovering = $0 }
    }
}

// MARK: - New task

private struct NewTaskField: View {
    @Bindable var viewModel: CheckInViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: Tokens.Space.s2) {
            Image(systemName: "circle")
                .font(.system(size: 13))
                .foregroundStyle(Tokens.Palette.textTertiary.color)
            EditableField(
                text: viewModel.newTaskTitle,
                placeholder: "What needs doing?",
                font: Tokens.Typography.listRow,
                isFocused: viewModel.focus == .newTask,
                onText: { viewModel.newTaskTitle = $0 },
                onCommand: { selector, _ in
                    switch selector {
                    case .insertNewline: viewModel.commitNewTask(); return true
                    case .cancelOperation: viewModel.cancelNewTask(); return true
                    default: return false
                    }
                },
                onEndEditing: { viewModel.commitNewTaskIfTyped() }
            )
        }
            .padding(.horizontal, Tokens.Space.rowInset)
            .frame(height: Tokens.Size.listRowHeight)
            .background {
                RoundedRectangle(cornerRadius: Tokens.Radius.row, style: .continuous)
                    .fill(Tokens.Palette.fieldBackground.color)
            }

            if let error = viewModel.newTaskError {
                Text(error)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Palette.invalid.color)
                    .padding(.horizontal, Tokens.Space.rowInset)
            }
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

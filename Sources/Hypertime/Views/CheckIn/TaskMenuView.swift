import SwiftUI
import HypertimeCore

/// The ⋯ menu for a task, in the app's own styling rather than a system menu. Pages rather than
/// submenus: one popover that walks in and back out again.
struct TaskMenuView: View {
    enum Page {
        case root, timer, move, rename
    }

    @Bindable var viewModel: CheckInViewModel
    let task: TaskItem
    var onClose: () -> Void

    @State private var page: Page
    @State private var title: String = ""

    init(viewModel: CheckInViewModel, task: TaskItem, startOn: Page = .root, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.task = task
        self.onClose = onClose
        _page = State(initialValue: startOn)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s1) {
            switch page {
            case .root: root
            case .timer: timer
            case .move: move
            case .rename: rename
            }
        }
        .padding(Tokens.Space.s2)
        .frame(width: Tokens.Size.taskMenuWidth)
        .onAppear { title = task.title }
    }

    // MARK: - Pages

    private var root: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s1) {
            MenuRow(title: "Rename…", symbol: "pencil") { page = .rename }
            MenuRow(title: task.timerSeconds == nil ? "Set a timer…" : "Change timer…",
                    symbol: "timer",
                    hint: task.timerSeconds.map { TimerLadder.label($0) }) { page = .timer }
            MenuRow(title: "Move to project…", symbol: "folder") { page = .move }
            Hairline().padding(.vertical, 2)
            MenuRow(title: "Delete", symbol: "trash", isDestructive: true,
                    enabled: viewModel.canDelete(task),
                    hint: viewModel.canDelete(task) ? nil : "Stop it first") {
                viewModel.deleteTask(task)
                onClose()
            }
        }
    }

    /// A slider rather than a list of four lengths: the four were a guess at which ones
    /// matter, and anything else meant giving up on the menu entirely.
    private var timer: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            MenuHeader(title: "Timer") { page = .root }
            TimerSlider(current: task.timerSeconds) { seconds in
                viewModel.setTimer(task, seconds: seconds)
                onClose()
            }
            if task.timerSeconds != nil {
                Hairline()
                MenuRow(title: "Clear the timer", symbol: "xmark", hint: "time stays") {
                    viewModel.clearTimer(task)
                    onClose()
                }
            }
        }
    }

    private var move: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s1) {
            MenuHeader(title: "Move to") { page = .root }
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                    ForEach(viewModel.allProjects) { project in
                        MenuRow(title: project.name,
                                symbol: project.id == task.projectID ? "checkmark" : "folder") {
                            viewModel.move(task, to: project)
                            onClose()
                        }
                    }
                }
            }
            .frame(maxHeight: 180)
        }
    }

    private var rename: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            MenuHeader(title: "Rename") { page = .root }
            EditableField(
                text: title,
                font: Tokens.Typography.body,
                isFocused: true,
                selectAllOnFocus: true,
                onText: { title = $0 },
                onCommand: { selector, _ in
                    switch selector {
                    case .insertNewline: commitRename(); return true
                    case .cancelOperation: onClose(); return true
                    default: return false
                    }
                }
            )
            .frame(height: Tokens.Size.fieldHeight - 4)
            .padding(.horizontal, Tokens.Space.s2)
            .background {
                RoundedRectangle(cornerRadius: Tokens.Radius.field, style: .continuous)
                    .fill(Tokens.Palette.fieldBackground.color)
            }
            HStack {
                Spacer()
                Button("Save") { commitRename() }
                    .hypertimeButton(.primary)
            }
        }
    }

    private func commitRename() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.rename(task, to: trimmed)
        onClose()
    }
}

// MARK: - Pieces

private struct MenuHeader: View {
    let title: String
    var back: () -> Void

    var body: some View {
        HStack(spacing: Tokens.Space.s1) {
            HoverButton(help: "Back", tint: Tokens.Palette.textSecondary.color, action: back) {
                Image(systemName: Tokens.Icons.navBack)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(title.uppercased())
                .font(Tokens.Typography.caption)
                .tracking(0.5)
                .foregroundStyle(Tokens.Palette.textTertiary.color)
            Spacer(minLength: 0)
        }
        .padding(.bottom, 2)
    }
}

private struct MenuRow: View {
    let title: String
    let symbol: String
    var isDestructive = false
    var enabled = true
    var hint: String?
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Tokens.Space.s2) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 14)
                Text(title)
                    .font(Tokens.Typography.body)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let hint {
                    Text(hint)
                        .font(Tokens.Typography.keyboardHint)
                        .foregroundStyle(Tokens.Palette.textTertiary.color)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(isDestructive
                             ? Tokens.Palette.destructive.color
                             : Tokens.Palette.textPrimary.color)
            .opacity(enabled ? 1 : 0.4)
            .padding(.horizontal, Tokens.Space.s2)
            .frame(height: Tokens.Size.listRowHeight)
            .background {
                RoundedRectangle(cornerRadius: Tokens.Radius.row, style: .continuous)
                    .fill(isHovering && enabled ? Tokens.Palette.rowHover.color : .clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { isHovering = $0 && enabled }
    }
}

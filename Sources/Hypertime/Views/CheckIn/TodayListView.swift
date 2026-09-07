import AppKit
import SwiftUI
import HypertimeCore

/// Every project with time today and its editable total (R-02, R-17).
struct TodayListView: View {
    @Bindable var viewModel: CheckInViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(viewModel.todayTotalText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if viewModel.todayRows.isEmpty {
                Text("Nothing tracked yet today.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(viewModel.todayRows) { row in
                            TodayRowView(viewModel: viewModel, row: row)
                        }
                    }
                }
                .frame(maxHeight: CGFloat(min(viewModel.todayRows.count, 6)) * 26)
            }
        }
    }
}

private struct TodayRowView: View {
    @Bindable var viewModel: CheckInViewModel
    let row: ReportRow

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(viewModel.isCurrent(row) ? Color.accentColor : Color.clear)
                .frame(width: 6, height: 6)
            Text(row.project.name)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            TotalField(viewModel: viewModel, row: row)
        }
        .frame(height: 24)
    }
}

/// Editable per-project total. Enter saves and keeps the popup open; blur saves; Esc reverts.
struct TotalField: View {
    @Bindable var viewModel: CheckInViewModel
    let row: ReportRow

    @State private var text: String = ""
    @State private var isEditing = false

    var body: some View {
        EditableField(
            text: isEditing ? text : viewModel.totalText(for: row),
            isInvalid: viewModel.invalidTotalRow == row.project.id,
            monospacedDigits: true,
            alignment: .right,
            isFocused: viewModel.focus == .total(row.project.id),
            selectAllOnFocus: true,
            onText: { text = $0; isEditing = true },
            onCommand: handle,
            onBeginEditing: {
                text = viewModel.totalText(for: row)
                isEditing = true
                viewModel.focus = .total(row.project.id)
            },
            onEndEditing: {
                if isEditing { save() }
                isEditing = false
            }
        )
        .frame(width: 84, height: 20)
    }

    private func handle(_ selector: Selector, _ modifiers: NSEvent.ModifierFlags) -> Bool {
        switch selector {
        case .insertNewline:
            save()
            isEditing = false
            return true
        case .cancelOperation:
            isEditing = false
            text = viewModel.totalText(for: row)
            viewModel.close()
            return true
        case .insertTab:
            if isEditing { save() }
            isEditing = false
            viewModel.focusNext(from: .total(row.project.id))
            return true
        case .insertBacktab:
            if isEditing { save() }
            isEditing = false
            viewModel.focusPrevious(from: .total(row.project.id))
            return true
        default:
            return false
        }
    }

    private func save() {
        guard !text.isEmpty else { return }
        viewModel.saveTotal(projectID: row.project.id, text: text)
    }
}

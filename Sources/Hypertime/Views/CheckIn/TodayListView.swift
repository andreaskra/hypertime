import AppKit
import SwiftUI
import HypertimeCore

/// Every project with time today and its editable total (R-02, R-17).
/// Six rows visible, then it scrolls with edge fades and a 3 pt overlay indicator.
struct TodayListView: View {
    @Bindable var viewModel: CheckInViewModel

    @State private var scrollOffset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0

    private var visibleHeight: CGFloat {
        CGFloat(min(max(viewModel.todayRows.count, 1), Tokens.Size.todayListMaxVisibleRows)) * Tokens.Size.listRowHeight
    }

    private func dayStep(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Tokens.Palette.textTertiary.color)
                .frame(width: 16, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s1) {
            HStack(spacing: 2) {
                dayStep(Tokens.Icons.navBack, "Previous day") { viewModel.stepDay(-1) }
                Button { viewModel.requestDayPicker() } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(viewModel.isShowingToday
                                         ? Tokens.Palette.textTertiary.color
                                         : Tokens.Palette.accent)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Jump to a date")
                dayStep(Tokens.Icons.navForward, "Next day") { viewModel.stepDay(1) }

                // Once the list scrolls, the label says how much is out of sight (artboard
                // "TODAY · 9 PROJECTS").
                Text(viewModel.todayRows.count > Tokens.Size.todayListMaxVisibleRows
                     ? "\(viewModel.dayLabel) · \(viewModel.todayRows.count) PROJECTS"
                     : viewModel.dayLabel)
                    .font(Tokens.Typography.caption)
                    .tracking(0.5)
                    .foregroundStyle(viewModel.isShowingToday
                                     ? Tokens.Palette.textTertiary.color
                                     : Tokens.Palette.accent)
                    .padding(.leading, Tokens.Space.s1)
                Spacer(minLength: Tokens.Space.s2)
                Text(viewModel.todayTotalText)
                    .font(Tokens.Typography.timeCell)
                    .foregroundStyle(Tokens.Palette.textSecondary.color)
            }
            .padding(.leading, Tokens.Space.s1)
            .padding(.trailing, Tokens.Space.rowInset)
            .padding(.bottom, Tokens.Space.s1)

            if viewModel.todayRows.isEmpty {
                Text(viewModel.isShowingToday ? "Nothing tracked yet today." : "Nothing tracked on this day.")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Palette.textTertiary.color)
                    .frame(height: Tokens.Size.listRowHeight, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(viewModel.todayRows) { row in
                            TodayRowView(viewModel: viewModel, row: row)
                        }
                    }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("todayScroll")) } action: { rect in
                        scrollOffset = -rect.minY
                        contentHeight = rect.height
                    }
                }
                .coordinateSpace(.named("todayScroll"))
                .scrollIndicators(.hidden)
                .frame(height: visibleHeight)
                .edgeFade(top: scrollOffset > 1, bottom: scrollOffset + visibleHeight < contentHeight - 1)
                .overlay {
                    ThinScrollIndicator(contentHeight: contentHeight, visibleHeight: visibleHeight, offset: scrollOffset)
                }
            }
        }
    }
}

private struct TodayRowView: View {
    @Bindable var viewModel: CheckInViewModel
    let row: ReportRow

    @State private var isHovering = false

    private var isFocused: Bool { viewModel.focus == .total(row.project.id) }

    var body: some View {
        HStack(spacing: Tokens.Space.s2) {
            Circle()
                .fill(indicatorColor)
                .frame(width: Tokens.Size.indicatorDot, height: Tokens.Size.indicatorDot)
            Text(row.project.name)
                .font(viewModel.isCurrent(row) ? Tokens.Typography.listRowCurrent : Tokens.Typography.listRow)
                .foregroundStyle(Tokens.Palette.textPrimary.color)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: Tokens.Space.s2)
            TotalField(viewModel: viewModel, row: row)
        }
        .padding(.horizontal, Tokens.Space.rowInset)
        .frame(height: Tokens.Size.listRowHeight)
        .background {
            RoundedRectangle(cornerRadius: Tokens.Radius.row, style: .continuous)
                .fill(isHovering ? Tokens.Palette.rowHover.color : .clear)
        }
        .focusRing(isFocused, radius: Tokens.Radius.row, width: Tokens.Focus.rowRingWidth, border: false)
        .onHover { isHovering = $0 }
    }

    /// Only the project time is accruing to carries a live indicator.
    private var indicatorColor: Color {
        guard viewModel.isCurrent(row) else { return .clear }
        if viewModel.isPaused { return Tokens.Palette.pausedIndicator.color }
        if viewModel.isTracking { return Tokens.Palette.trackingIndicator.color }
        return Tokens.Palette.idleIndicator.color
    }
}

/// Editable per-project total. Enter saves and keeps the popup open; blur saves; Esc reverts.
struct TotalField: View {
    @Bindable var viewModel: CheckInViewModel
    let row: ReportRow

    @State private var text: String = ""
    @State private var isEditing = false

    private var isInvalid: Bool { viewModel.invalidTotalRow == row.project.id }

    var body: some View {
        EditableField(
            text: isEditing ? text : viewModel.totalText(for: row),
            font: Tokens.Typography.timeCell,
            textColor: Tokens.Palette.rowTime.nsColor,
            isInvalid: isInvalid,
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
        .frame(width: 78, height: 20)
        .padding(.horizontal, Tokens.Space.s1)
        .background {
            RoundedRectangle(cornerRadius: Tokens.Radius.cell, style: .continuous)
                .fill(isInvalid ? Tokens.Palette.invalidFieldBackground.color
                      : (isEditing ? Tokens.Palette.fieldBackground.color : .clear))
        }
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

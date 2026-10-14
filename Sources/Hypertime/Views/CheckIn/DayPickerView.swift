import SwiftUI
import HypertimeCore

/// Jump to any day. Days with tracked time carry an accent dot, so the month reads as a record
/// of what was worked before you pick anything.
struct DayPickerView: View {
    @Bindable var viewModel: CheckInViewModel
    var onPick: (LocalDate) -> Void

    @State private var month: LocalDate = LocalDate(year: 1970, month: 1, day: 1)
    @Environment(\.colorScheme) private var scheme

    private let cell: CGFloat = 30

    var body: some View {
        VStack(spacing: Tokens.Space.s2) {
            header
            weekdays
            grid
        }
        .padding(Tokens.Space.s3)
        .frame(width: 7 * cell + 2 * Tokens.Space.s3)
        .onAppear { month = viewModel.visibleDay }
    }

    private var header: some View {
        HStack(spacing: Tokens.Space.s1) {
            stepper(Tokens.Icons.navBack) { month = viewModel.month(month, offsetBy: -1) }
            Spacer(minLength: 0)
            Text(viewModel.monthTitle(month))
                .font(Tokens.Typography.heading)
                .foregroundStyle(Tokens.Palette.textPrimary.color)
            Spacer(minLength: 0)
            stepper(Tokens.Icons.navForward) { month = viewModel.month(month, offsetBy: 1) }
        }
    }

    private func stepper(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Tokens.Palette.textSecondary.color)
                .frame(width: Tokens.Size.iconButton, height: Tokens.Size.iconButton)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var weekdays: some View {
        HStack(spacing: 0) {
            ForEach(Array(viewModel.weekdayInitials.enumerated()), id: \.offset) { _, initial in
                Text(initial)
                    .font(Tokens.Typography.keyboardHint)
                    .foregroundStyle(Tokens.Palette.textTertiary.color)
                    .frame(width: cell)
            }
        }
    }

    private var grid: some View {
        let marked = viewModel.markedDays(in: month)
        return VStack(spacing: 2) {
            ForEach(Array(viewModel.monthGrid(for: month).enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day {
                            dayCell(day, hasTime: marked.contains(day))
                        } else {
                            Color.clear.frame(width: cell, height: cell)
                        }
                    }
                }
            }
        }
    }

    private func dayCell(_ day: LocalDate, hasTime: Bool) -> some View {
        let isSelected = day == viewModel.visibleDay
        let isToday = day == viewModel.todayDate
        return Button {
            onPick(day)
        } label: {
            VStack(spacing: 1) {
                Text(String(day.day))
                    .font(Tokens.Typography.timeCell)
                    .foregroundStyle(isSelected
                                     ? Tokens.Palette.onAccent.color
                                     : Tokens.Palette.textPrimary.color)
                Circle()
                    .fill(hasTime
                          ? (isSelected ? Tokens.Palette.onAccent.color : Tokens.Palette.accent)
                          : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(width: cell, height: cell)
            .background {
                RoundedRectangle(cornerRadius: Tokens.Radius.cell, style: .continuous)
                    .fill(isSelected ? Tokens.Palette.accent : Color.clear)
                    .overlay {
                        if isToday, !isSelected {
                            RoundedRectangle(cornerRadius: Tokens.Radius.cell, style: .continuous)
                                .strokeBorder(Tokens.Palette.accent, lineWidth: 1)
                        }
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.cell, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

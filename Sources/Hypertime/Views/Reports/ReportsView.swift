import SwiftUI
import HypertimeCore

/// Day / Week / Month / Year reports with editable totals (R-17, R-18, §6.10), styled from the
/// Phase 2 handoff: 52 pt toolbar, window material, today column tint, month intensity cells.
struct ReportsView: View {
    @Bindable var viewModel: ReportsViewModel
    var onExport: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let nameColumn: CGFloat = 160
    private let totalColumn: CGFloat = 82

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            Hairline()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .animation(Tokens.Motion.listOpen.animation(reduceMotion: reduceMotion),
                           value: viewModel.presentation)
                .animation(Tokens.Motion.listOpen.animation(reduceMotion: reduceMotion),
                           value: viewModel.title)
            Hairline()
            footer
        }
        .background { GlassBackground(style: Tokens.Materials.window, cornerRadius: 0) }
        .frame(minWidth: 620, minHeight: 420)
    }

    // MARK: - Chrome

    private var toolbar: some View {
        HStack(spacing: Tokens.Space.s3) {
            Picker("", selection: $viewModel.kind) {
                Text("Day").tag(PeriodKind.day)
                Text("Week").tag(PeriodKind.week)
                Text("Month").tag(PeriodKind.month)
                Text("Year").tag(PeriodKind.year)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)

            HStack(spacing: Tokens.Space.s1) {
                Button { viewModel.go(-1) } label: { Image(systemName: Tokens.Icons.navBack) }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Button("Today") { viewModel.goToToday() }
                    .keyboardShortcut("t", modifiers: .command)
                    .fixedSize()
                Button { viewModel.go(1) } label: { Image(systemName: Tokens.Icons.navForward) }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Text(viewModel.title)
                .font(Tokens.Typography.periodTitle)
                .foregroundStyle(Tokens.Palette.textPrimary.color)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)

            Spacer(minLength: Tokens.Space.s2)

            HoverButton(help: viewModel.isSliding
                        ? "Snap to calendar weeks and months"
                        : "Slide the window a day at a time",
                        tint: viewModel.isSliding ? Tokens.Palette.accent : nil) {
                viewModel.isSliding.toggle()
            } label: {
                Image(systemName: viewModel.isSliding ? "arrow.left.and.right" : "calendar")
                    .font(.system(size: 11, weight: .medium))
            }

            Picker("", selection: $viewModel.presentation) {
                Image(systemName: "chart.bar").tag(ReportsViewModel.Presentation.chart)
                Image(systemName: "tablecells").tag(ReportsViewModel.Presentation.table)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 76)
            .help("Chart or table")

            Button {
                onExport()
            } label: {
                Label("Export…", systemImage: Tokens.Icons.export)
            }
            .hypertimeButton(.secondary)
        }
        .padding(.leading, Tokens.Size.trafficLightInset)
        .padding(.trailing, Tokens.Space.s4)
        .frame(height: Tokens.Size.toolbarHeight)
        .background { periodShortcuts }
    }

    /// ⌘1–4 switch the period kind.
    private var periodShortcuts: some View {
        Group {
            Button("") { viewModel.kind = .day }.keyboardShortcut("1", modifiers: .command)
            Button("") { viewModel.kind = .week }.keyboardShortcut("2", modifiers: .command)
            Button("") { viewModel.kind = .month }.keyboardShortcut("3", modifiers: .command)
            Button("") { viewModel.kind = .year }.keyboardShortcut("4", modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }

    private var footer: some View {
        HStack {
            Text(footerHint)
                .font(Tokens.Typography.caption)
                .foregroundStyle(viewModel.errorMessage == nil
                                 ? Tokens.Palette.textTertiary.color
                                 : Tokens.Palette.invalid.color)
            Spacer()
            if viewModel.showsAverages {
                stat("Per day", viewModel.averagePerDay)
                stat("Per tracked day", viewModel.averagePerTrackedDay,
                     detail: "\(viewModel.trackedDays) of \(viewModel.calendarDays)")
            }
            stat("Total", viewModel.total, emphasised: true)
        }
        .padding(.horizontal, Tokens.Space.s4)
        .frame(height: 36)
    }

    /// A labelled number in the footer. The averages only make sense over more than one day.
    private func stat(_ label: String, _ seconds: Seconds,
                      detail: String? = nil, emphasised: Bool = false) -> some View {
        HStack(spacing: Tokens.Space.s1) {
            Text(label)
                .font(Tokens.Typography.caption)
                .foregroundStyle(Tokens.Palette.textSecondary.color)
            Text(viewModel.text(seconds))
                .font(emphasised
                      ? Tokens.Typography.timeCell.font.weight(.semibold)
                      : Tokens.Typography.timeCell.font)
                .foregroundStyle(Tokens.Palette.textPrimary.color)
            if let detail {
                Text(detail)
                    .font(Tokens.Typography.keyboardHint)
                    .foregroundStyle(Tokens.Palette.textTertiary.color)
            }
        }
        .padding(.leading, Tokens.Space.s3)
    }

    private var footerHint: String {
        if let message = viewModel.errorMessage { return message }
        if viewModel.presentation == .chart {
            return "Tick to hide a project · click one to show it alone."
        }
        switch viewModel.kind {
        case .day, .week: return "Edit a total to set it, or type +15m / −30m to adjust it."
        case .month: return "Click a day to open it."
        case .year: return "Click a month to open it."
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.presentation {
        case .chart: ActivityChartView(viewModel: viewModel)
        case .table: table
        }
    }

    @ViewBuilder
    private var table: some View {
        switch viewModel.kind {
        case .day: dayView
        case .week: weekView
        case .month: monthView
        case .year: yearView
        }
    }

    private var dayOfPeriod: LocalDate {
        if case .day(let day) = viewModel.period { return day }
        return viewModel.todayDate
    }

    /// The same shape as the popup's today list, for any day.
    private var dayView: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(viewModel.report?.rows ?? []) { row in
                    HStack(spacing: Tokens.Space.s2) {
                        Text(row.project.name)
                            .font(Tokens.Typography.listRow)
                            .foregroundStyle(Tokens.Palette.textPrimary.color)
                            .lineLimit(1)
                        Spacer(minLength: Tokens.Space.s3)
                        InlineTotalField(text: viewModel.text(row.seconds)) { text in
                            viewModel.saveTotal(project: row.project.id, day: dayOfPeriod, text: text)
                        }
                    }
                    .padding(.horizontal, Tokens.Space.s2)
                    .frame(height: Tokens.Size.listRowHeight)
                    .contextMenu { projectMenu(row.project) }
                }

                HStack(spacing: Tokens.Space.s2) {
                    Image(systemName: Tokens.Icons.addProject)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Tokens.Palette.textTertiary.color)
                    TextField("Add project…", text: $viewModel.newProjectName)
                        .textFieldStyle(.plain)
                        .font(Tokens.Typography.listRow)
                        .onSubmit { viewModel.addProject() }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Tokens.Space.s2)
                .frame(height: Tokens.Size.listRowHeight)
            }
            .padding(Tokens.Space.s4)
            .frame(maxWidth: 420, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Week

    private var weekView: some View {
        let days = viewModel.days
        return ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .trailing, horizontalSpacing: 0, verticalSpacing: 2) {
                GridRow {
                    Text("Project")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(Tokens.Palette.textTertiary.color)
                        .frame(width: nameColumn, alignment: .leading)
                    ForEach(days, id: \.self) { day in
                        Button {
                            viewModel.showDay(day)
                        } label: {
                            Text(dayLabel(day))
                                .font(Tokens.Typography.caption)
                                .foregroundStyle(viewModel.isToday(day)
                                                 ? Tokens.Palette.accent
                                                 : Tokens.Palette.textTertiary.color)
                                .frame(width: weekCell)
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Total")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(Tokens.Palette.textTertiary.color)
                        .frame(width: totalColumn, alignment: .trailing)
                }
                .padding(.bottom, Tokens.Space.s1)

                ForEach(viewModel.report?.rows ?? []) { row in
                    GridRow {
                        Text(row.project.name)
                            .font(Tokens.Typography.listRow)
                            .foregroundStyle(Tokens.Palette.textPrimary.color)
                            .lineLimit(1)
                            .frame(width: nameColumn, alignment: .leading)
                            .contextMenu { projectMenu(row.project) }
                        ForEach(viewModel.days, id: \.self) { day in
                            InlineTotalField(text: viewModel.text(row.seconds(on: day)),
                                             width: weekCell - 8,
                                             alignment: .right) { text in
                                viewModel.saveTotal(project: row.project.id, day: day, text: text)
                            }
                            .frame(width: weekCell)
                            .background {
                                if viewModel.isToday(day) {
                                    Rectangle().fill(Tokens.Palette.todayColumn(scheme))
                                }
                            }
                        }
                        Text(viewModel.text(row.seconds))
                            .font(Tokens.Typography.timeCell.font.weight(.semibold))
                            .foregroundStyle(Tokens.Palette.textPrimary.color)
                            .frame(width: totalColumn, alignment: .trailing)
                    }
                }

                GridRow {
                    Text("Total")
                        .font(Tokens.Typography.caption.font.weight(.semibold))
                        .foregroundStyle(Tokens.Palette.textSecondary.color)
                        .frame(width: nameColumn, alignment: .leading)
                    ForEach(days, id: \.self) { day in
                        Text(viewModel.text(viewModel.report?.total(on: day) ?? 0))
                            .font(Tokens.Typography.timeCell)
                            .foregroundStyle(Tokens.Palette.textSecondary.color)
                            .frame(width: weekCell, alignment: .trailing)
                    }
                    Text(viewModel.text(viewModel.report?.total ?? 0))
                        .font(Tokens.Typography.timeCell.font.weight(.semibold))
                        .foregroundStyle(Tokens.Palette.textPrimary.color)
                        .frame(width: totalColumn, alignment: .trailing)
                }
                .padding(.top, Tokens.Space.s1)
            }
            .padding(Tokens.Space.s4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var weekCell: CGFloat { 68 }

    private func dayLabel(_ day: LocalDate) -> String {
        Period.day(day).shortTitle(calendar: .autoupdatingCurrent, weekStart: .monday)
    }

    // MARK: - Month

    /// Intensity cells: one square per day, opacity scaled by that day's share of the busiest day.
    private var monthView: some View {
        let days = viewModel.days
        let busiest = max(viewModel.busiestDaySeconds, 1)
        return ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .trailing, horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow {
                    Text("Project")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(Tokens.Palette.textTertiary.color)
                        .frame(width: nameColumn, alignment: .leading)
                    ForEach(days, id: \.self) { day in
                        Text(String(day.day))
                            .font(Tokens.Typography.keyboardHint)
                            .foregroundStyle(viewModel.isToday(day) ? Tokens.Palette.accent : Tokens.Palette.textTertiary.color)
                            .frame(width: monthCell)
                    }
                    Text("Total")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(Tokens.Palette.textTertiary.color)
                        .frame(width: totalColumn, alignment: .trailing)
                }

                ForEach(viewModel.report?.rows ?? []) { row in
                    GridRow {
                        Text(row.project.name)
                            .font(Tokens.Typography.listRow)
                            .foregroundStyle(Tokens.Palette.textPrimary.color)
                            .lineLimit(1)
                            .frame(width: nameColumn, alignment: .leading)
                            .contextMenu { projectMenu(row.project) }
                        ForEach(days, id: \.self) { day in
                            intensityCell(seconds: row.seconds(on: day), busiest: busiest, day: day)
                        }
                        Text(viewModel.text(row.seconds))
                            .font(Tokens.Typography.timeCell.font.weight(.semibold))
                            .foregroundStyle(Tokens.Palette.textPrimary.color)
                            .frame(width: totalColumn, alignment: .trailing)
                    }
                }
            }
            .padding(Tokens.Space.s4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var monthCell: CGFloat { 18 }

    private func intensityCell(seconds: Seconds, busiest: Seconds, day: LocalDate) -> some View {
        Button {
            viewModel.showDay(day)
        } label: {
            RoundedRectangle(cornerRadius: Tokens.Radius.cell - 2, style: .continuous)
                .fill(seconds == 0
                      ? Tokens.Palette.rowHover.color
                      : Tokens.Palette.accent.opacity(0.2 + 0.8 * min(Double(seconds) / Double(busiest), 1)))
                .frame(width: monthCell, height: 18)
                .overlay {
                    if viewModel.isToday(day) {
                        RoundedRectangle(cornerRadius: Tokens.Radius.cell - 2, style: .continuous)
                            .strokeBorder(Tokens.Palette.accent, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(seconds == 0 ? day.isoString : "\(day.isoString) · \(viewModel.text(seconds))")
    }

    // MARK: - Year

    private var yearView: some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .trailing, horizontalSpacing: Tokens.Space.s1, verticalSpacing: 2) {
                GridRow {
                    Text("Project")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(Tokens.Palette.textTertiary.color)
                        .frame(width: nameColumn, alignment: .leading)
                    ForEach(viewModel.months, id: \.self) { month in
                        Text(monthLabel(month))
                            .font(Tokens.Typography.caption)
                            .foregroundStyle(Tokens.Palette.textTertiary.color)
                            .frame(width: yearCell)
                    }
                    Text("Total")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(Tokens.Palette.textTertiary.color)
                        .frame(width: totalColumn, alignment: .trailing)
                }

                ForEach(viewModel.report?.rows ?? []) { row in
                    GridRow {
                        Text(row.project.name)
                            .font(Tokens.Typography.listRow)
                            .foregroundStyle(Tokens.Palette.textPrimary.color)
                            .lineLimit(1)
                            .frame(width: nameColumn, alignment: .leading)
                            .contextMenu { projectMenu(row.project) }
                        ForEach(viewModel.months, id: \.self) { month in
                            let seconds = monthSeconds(row: row, month: month)
                            Button {
                                viewModel.show(.month, anchoredAt: monthStart(month))
                            } label: {
                                Text(viewModel.text(seconds))
                                    .font(Tokens.Typography.timeCell)
                                    .foregroundStyle(seconds == 0
                                                     ? Tokens.Palette.textTertiary.color
                                                     : Tokens.Palette.textPrimary.color)
                                    .frame(width: yearCell, alignment: .trailing)
                            }
                            .buttonStyle(.plain)
                        }
                        Text(viewModel.text(row.seconds))
                            .font(Tokens.Typography.timeCell.font.weight(.semibold))
                            .foregroundStyle(Tokens.Palette.textPrimary.color)
                            .frame(width: totalColumn, alignment: .trailing)
                    }
                }
            }
            .padding(Tokens.Space.s4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var yearCell: CGFloat { 62 }

    private func monthLabel(_ period: Period) -> String {
        guard case .month(_, let month) = period else { return "" }
        return DateFormatter().shortMonthSymbols?[month - 1] ?? String(month)
    }

    private func monthStart(_ period: Period) -> LocalDate {
        period.range(calendar: .autoupdatingCurrent, weekStart: .monday).lowerBound
    }

    private func monthSeconds(row: ReportRow, month: Period) -> Seconds {
        let range = month.range(calendar: .autoupdatingCurrent, weekStart: .monday)
        return row.perDay.reduce(0) { $0 + (range.contains($1.key) ? $1.value : 0) }
    }

    // MARK: - Project management

    @ViewBuilder
    private func projectMenu(_ project: Project) -> some View {
        Button("Rename…") { RenamePrompt.show(project: project, viewModel: viewModel) }
        Button(project.isArchived ? "Unarchive" : "Archive") {
            viewModel.setArchived(project, !project.isArchived)
        }
        Divider()
        Button("Delete…", role: .destructive) { DeletePrompt.show(project: project, viewModel: viewModel) }
    }
}

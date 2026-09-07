import SwiftUI
import HypertimeCore

/// Day / Week / Month / Year reports with editable totals (R-17, R-18, §6.10).
struct ReportsView: View {
    @Bindable var viewModel: ReportsViewModel
    var onExport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            footer
        }
        .frame(minWidth: 620, minHeight: 420)
    }

    // MARK: - Chrome

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $viewModel.kind) {
                Text("Day").tag(PeriodKind.day)
                Text("Week").tag(PeriodKind.week)
                Text("Month").tag(PeriodKind.month)
                Text("Year").tag(PeriodKind.year)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)

            HStack(spacing: 4) {
                Button { viewModel.go(-1) } label: { Image(systemName: "chevron.left") }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Button("Today") { viewModel.goToToday() }
                    .keyboardShortcut("t", modifiers: .command)
                Button { viewModel.go(1) } label: { Image(systemName: "chevron.right") }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
            }

            Text(viewModel.title)
                .font(.headline)
                .lineLimit(1)

            Spacer()
            Button("Export…", action: onExport)
        }
        .padding(10)
        .background(alignment: .center) { periodShortcuts }
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
            if let message = viewModel.errorMessage {
                Text(message).foregroundStyle(.red).font(.callout)
            } else if viewModel.kind == .day || viewModel.kind == .week {
                Text("Edit a total to set it, or type +15m / -30m to adjust it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Total \(viewModel.text(viewModel.report?.total ?? 0))")
                .font(.callout.monospacedDigit().bold())
        }
        .padding(10)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.kind {
        case .day: dayView
        case .week: gridView(columns: viewModel.days.map { ($0.isoString, columnTitle($0), .day($0)) })
        case .month: gridView(columns: viewModel.days.map { (String($0.day), String($0.day), .day($0)) })
        case .year: yearView
        }
    }

    private func columnTitle(_ day: LocalDate) -> String {
        Period.day(day).shortTitle(calendar: .autoupdatingCurrent, weekStart: .monday)
    }

    private var dayView: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(viewModel.report?.rows ?? []) { row in
                    HStack {
                        Text(row.project.name)
                            .lineLimit(1)
                        Spacer(minLength: 12)
                        InlineTotalField(text: viewModel.text(row.seconds)) { text in
                            viewModel.saveTotal(project: row.project.id, day: dayOfPeriod, text: text)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .contextMenu { projectMenu(row.project) }
                }

                HStack {
                    TextField("Add project…", text: $viewModel.newProjectName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { viewModel.addProject() }
                    Button("Add") { viewModel.addProject() }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            .padding(.vertical, 8)
        }
    }

    private var dayOfPeriod: LocalDate {
        if case .day(let day) = viewModel.period { return day }
        return viewModel.todayDate
    }

    /// Week and Month: projects × days. Week cells are editable, Month cells open the day.
    private func gridView(columns: [(String, String, Period)]) -> some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 4) {
                GridRow {
                    Text("Project").frame(width: 160, alignment: .leading)
                    ForEach(columns, id: \.0) { column in
                        Button(column.1) {
                            if case .day(let day) = column.2 { viewModel.showDay(day) }
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                        .frame(width: cellWidth)
                    }
                    Text("Total").frame(width: 80)
                }
                Divider().gridCellUnsizedAxes(.horizontal)

                ForEach(viewModel.report?.rows ?? []) { row in
                    GridRow {
                        Text(row.project.name)
                            .lineLimit(1)
                            .frame(width: 160, alignment: .leading)
                            .contextMenu { projectMenu(row.project) }
                        ForEach(columns, id: \.0) { column in
                            cell(row: row, column: column)
                        }
                        Text(viewModel.text(row.seconds))
                            .font(.body.monospacedDigit().bold())
                            .frame(width: 80, alignment: .trailing)
                    }
                }

                Divider().gridCellUnsizedAxes(.horizontal)
                GridRow {
                    Text("Total").frame(width: 160, alignment: .leading).bold()
                    ForEach(columns, id: \.0) { column in
                        Text(viewModel.text(total(for: column.2)))
                            .font(.caption.monospacedDigit())
                            .frame(width: cellWidth, alignment: .trailing)
                    }
                    Text(viewModel.text(viewModel.report?.total ?? 0))
                        .font(.body.monospacedDigit().bold())
                        .frame(width: 80, alignment: .trailing)
                }
            }
            .padding(12)
        }
    }

    private var cellWidth: CGFloat { viewModel.kind == .week ? 84 : 60 }

    @ViewBuilder
    private func cell(row: ReportRow, column: (String, String, Period)) -> some View {
        if case .day(let day) = column.2 {
            if viewModel.kind == .week {
                InlineTotalField(text: viewModel.text(row.seconds(on: day)), width: cellWidth) { text in
                    viewModel.saveTotal(project: row.project.id, day: day, text: text)
                }
            } else {
                Button(viewModel.text(row.seconds(on: day))) { viewModel.showDay(day) }
                    .buttonStyle(.plain)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(row.seconds(on: day) == 0 ? .tertiary : .primary)
                    .frame(width: cellWidth, alignment: .trailing)
            }
        }
    }

    private var yearView: some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 4) {
                GridRow {
                    Text("Project").frame(width: 160, alignment: .leading)
                    ForEach(viewModel.months, id: \.self) { month in
                        Text(monthLabel(month)).font(.caption).frame(width: 64)
                    }
                    Text("Total").frame(width: 80)
                }
                Divider().gridCellUnsizedAxes(.horizontal)

                ForEach(viewModel.report?.rows ?? []) { row in
                    GridRow {
                        Text(row.project.name)
                            .lineLimit(1)
                            .frame(width: 160, alignment: .leading)
                            .contextMenu { projectMenu(row.project) }
                        ForEach(viewModel.months, id: \.self) { month in
                            let seconds = monthSeconds(row: row, month: month)
                            Button(viewModel.text(seconds)) {
                                viewModel.showDay(month.range(calendar: .autoupdatingCurrent, weekStart: .monday).lowerBound)
                            }
                            .buttonStyle(.plain)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(seconds == 0 ? .tertiary : .primary)
                            .frame(width: 64, alignment: .trailing)
                        }
                        Text(viewModel.text(row.seconds))
                            .font(.body.monospacedDigit().bold())
                            .frame(width: 80, alignment: .trailing)
                    }
                }
            }
            .padding(12)
        }
    }

    private func monthLabel(_ period: Period) -> String {
        guard case .month(_, let month) = period else { return "" }
        return DateFormatter().shortMonthSymbols?[month - 1] ?? String(month)
    }

    private func monthSeconds(row: ReportRow, month: Period) -> Seconds {
        let range = month.range(calendar: .autoupdatingCurrent, weekStart: .monday)
        return row.perDay.reduce(0) { $0 + (range.contains($1.key) ? $1.value : 0) }
    }

    private func total(for period: Period) -> Seconds {
        guard case .day(let day) = period else { return 0 }
        return viewModel.report?.total(on: day) ?? 0
    }

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

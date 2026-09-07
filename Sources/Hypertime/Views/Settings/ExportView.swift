import SwiftUI
import HypertimeCore

@MainActor
@Observable
final class ExportViewModel {
    enum ScopeKind: String, CaseIterable { case month, year, range }

    var scopeKind: ScopeKind = .month
    var from: Date
    var to: Date
    var delimiterIsSemicolon: Bool
    var cellStyle: TimeStyle
    var includeTotals: Bool
    var message: String?

    private let model: AppModel

    init(model: AppModel, initialPeriod: Period?) {
        self.model = model
        let calendar = model.clock.calendar
        let range = (initialPeriod ?? .month(year: model.today.year, month: model.today.month))
            .range(calendar: calendar, weekStart: model.settings.weekStart)
        from = range.lowerBound.startOfDay(calendar: calendar)
        to = range.upperBound.startOfDay(calendar: calendar)
        delimiterIsSemicolon = model.settings.csvDelimiter == ";"
        cellStyle = model.settings.csvCellStyle
        includeTotals = model.settings.csvIncludeTotals
        if let initialPeriod {
            switch initialPeriod {
            case .year: scopeKind = .year
            case .month: scopeKind = .month
            default: scopeKind = .range
            }
        }
    }

    var scope: ExportScope {
        let calendar = model.clock.calendar
        switch scopeKind {
        case .month:
            let day = LocalDate(from, calendar: calendar)
            return .month(year: day.year, month: day.month)
        case .year:
            return .year(LocalDate(from, calendar: calendar).year)
        case .range:
            let lower = LocalDate(from, calendar: calendar)
            let upper = LocalDate(to, calendar: calendar)
            return .range(min(lower, upper)...max(lower, upper))
        }
    }

    var options: CSVOptions {
        CSVOptions(delimiter: delimiterIsSemicolon ? ";" : ",",
                   cellStyle: cellStyle,
                   includeTotals: includeTotals,
                   decimalSeparator: delimiterIsSemicolon ? "," : ".")
    }

    var suggestedFilename: String { CSVExporter.suggestedFilename(scope: scope) }

    func csv() throws -> String { try model.exporter.csv(scope: scope, options: options) }
}

/// Export options sheet (R-19, §6.11).
struct ExportView: View {
    @Bindable var viewModel: ExportViewModel
    var onExport: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export CSV").font(.headline)

            Picker("Scope", selection: $viewModel.scopeKind) {
                Text("Month").tag(ExportViewModel.ScopeKind.month)
                Text("Year").tag(ExportViewModel.ScopeKind.year)
                Text("Date range").tag(ExportViewModel.ScopeKind.range)
            }
            .pickerStyle(.segmented)

            switch viewModel.scopeKind {
            case .month, .year:
                DatePicker("Inside", selection: $viewModel.from, displayedComponents: .date)
            case .range:
                DatePicker("From", selection: $viewModel.from, displayedComponents: .date)
                DatePicker("To", selection: $viewModel.to, displayedComponents: .date)
            }

            Divider()

            Toggle("Semicolon delimiter", isOn: $viewModel.delimiterIsSemicolon)
            Picker("Cells", selection: $viewModel.cellStyle) {
                Text("1:30:15").tag(TimeStyle.clock)
                Text("1:30").tag(TimeStyle.clockNoSeconds)
                Text("1.50 (decimal hours)").tag(TimeStyle.decimalHours)
            }
            Toggle("Include totals", isOn: $viewModel.includeTotals)

            if let message = viewModel.message {
                Text(message).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Text(viewModel.suggestedFilename).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Export…", action: onExport).keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 380)
    }
}

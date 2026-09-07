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

    /// Header plus the first data row, so the delimiter and cell format are visible before saving.
    var previewLines: [String] {
        guard let csv = try? csv() else { return [] }
        return csv
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .components(separatedBy: "\r\n")
            .prefix(2)
            .map { String($0.prefix(120)) }
    }
}

/// A-export: export options on the sheet material, with a CSV preview line (R-19, §6.11).
struct ExportView: View {
    @Bindable var viewModel: ExportViewModel
    var onExport: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            Text("Export CSV")
                .font(Tokens.Typography.periodTitle)
                .foregroundStyle(Tokens.Palette.textPrimary.color)

            Picker("", selection: $viewModel.scopeKind) {
                Text("Month").tag(ExportViewModel.ScopeKind.month)
                Text("Year").tag(ExportViewModel.ScopeKind.year)
                Text("Date range").tag(ExportViewModel.ScopeKind.range)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                switch viewModel.scopeKind {
                case .month, .year:
                    DatePicker("Inside", selection: $viewModel.from, displayedComponents: .date)
                case .range:
                    DatePicker("From", selection: $viewModel.from, displayedComponents: .date)
                    DatePicker("To", selection: $viewModel.to, displayedComponents: .date)
                }
            }
            .font(Tokens.Typography.body)

            Hairline()

            Toggle("Semicolon delimiter", isOn: $viewModel.delimiterIsSemicolon)
            Picker("Cells", selection: $viewModel.cellStyle) {
                Text("1:30:15").tag(TimeStyle.clock)
                Text("1:30").tag(TimeStyle.clockNoSeconds)
                Text("1.50 (decimal hours)").tag(TimeStyle.decimalHours)
            }
            Toggle("Include totals", isOn: $viewModel.includeTotals)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(viewModel.previewLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(Tokens.Typography.keyboardHint.font.monospaced())
                        .foregroundStyle(Tokens.Palette.textTertiary.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Tokens.Space.s2)
            .background {
                RoundedRectangle(cornerRadius: Tokens.Radius.cell, style: .continuous)
                    .fill(Tokens.Palette.rowHover.color)
            }

            if let message = viewModel.message {
                Text(message)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Palette.invalid.color)
            }

            HStack {
                Text(viewModel.suggestedFilename)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Palette.textTertiary.color)
                Spacer()
                Button("Cancel", action: onCancel)
                    .hypertimeButton(.secondary)
                    .keyboardShortcut(.cancelAction)
                Button("Export…", action: onExport)
                    .hypertimeButton(.primary)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Tokens.Space.s4)
        .frame(width: 400)
        .background { GlassBackground(style: Tokens.Materials.sheet, cornerRadius: 0) }
    }
}

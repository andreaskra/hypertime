import Foundation

public struct CSVOptions: Sendable, Equatable {
    public var delimiter: Character
    public var cellStyle: TimeStyle
    public var includeBOM: Bool
    public var includeTotals: Bool
    public var decimalSeparator: String

    public init(delimiter: Character = ",",
                cellStyle: TimeStyle = .clock,
                includeBOM: Bool = true,
                includeTotals: Bool = true,
                decimalSeparator: String = ".") {
        self.delimiter = delimiter
        self.cellStyle = cellStyle
        self.includeBOM = includeBOM
        self.includeTotals = includeTotals
        self.decimalSeparator = decimalSeparator
    }
}

public enum ExportScope: Sendable, Equatable {
    case month(year: Int, month: Int)
    case year(Int)
    case range(ClosedRange<LocalDate>)

    public func dateRange(calendar: Calendar) -> ClosedRange<LocalDate> {
        switch self {
        case .month(let year, let month):
            return Period.month(year: year, month: month).range(calendar: calendar, weekStart: .monday)
        case .year(let year):
            return Period.year(year).range(calendar: calendar, weekStart: .monday)
        case .range(let range):
            return range
        }
    }
}

/// Date-rows × project-columns matrix export (§5.8, D-12).
public struct CSVExporter: Sendable {
    private let store: Store
    private let clock: Clock
    private let formatter = TimeFormatter()

    public init(store: Store, clock: Clock) {
        self.store = store
        self.clock = clock
    }

    public func csv(scope: ExportScope, options: CSVOptions = CSVOptions()) throws -> String {
        let calendar = clock.calendar
        let range = scope.dateRange(calendar: calendar)
        let days = LocalDate.days(in: range, calendar: calendar)
        let projects = try store.projectsWithEntries(in: range)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        var byDay: [LocalDate: [UUID: Seconds]] = [:]
        for entry in try store.entries(in: range) where entry.seconds > 0 {
            byDay[entry.day, default: [:]][entry.projectID, default: 0] += entry.seconds
        }

        var lines: [String] = []

        var header = ["Date"] + projects.map(\.name)
        if options.includeTotals { header.append("Total") }
        lines.append(row(header, options))

        var columnTotals = [Seconds](repeating: 0, count: projects.count)
        var grandTotal = 0

        for day in days {
            var fields = [day.isoString]
            var dayTotal = 0
            for (index, project) in projects.enumerated() {
                let seconds = byDay[day]?[project.id] ?? 0
                dayTotal += seconds
                columnTotals[index] += seconds
                fields.append(cell(seconds, options))
            }
            if options.includeTotals { fields.append(cell(dayTotal, options)) }
            grandTotal += dayTotal
            lines.append(row(fields, options))
        }

        if options.includeTotals {
            var fields = ["Total"] + columnTotals.map { cell($0, options) }
            fields.append(cell(grandTotal, options))
            lines.append(row(fields, options))
        }

        let body = lines.joined(separator: "\r\n") + "\r\n"
        return options.includeBOM ? "\u{FEFF}" + body : body
    }

    public func data(scope: ExportScope, options: CSVOptions = CSVOptions()) throws -> Data {
        Data(try csv(scope: scope, options: options).utf8)
    }

    public static func suggestedFilename(scope: ExportScope) -> String {
        switch scope {
        case .month(let year, let month):
            return String(format: "Hypertime-%04d-%02d.csv", year, month)
        case .year(let year):
            return String(format: "Hypertime-%04d.csv", year)
        case .range(let range):
            return "Hypertime-\(range.lowerBound.isoString)_\(range.upperBound.isoString).csv"
        }
    }

    // MARK: - Formatting

    private func cell(_ seconds: Seconds, _ options: CSVOptions) -> String {
        formatter.string(seconds, style: options.cellStyle, decimalSeparator: options.decimalSeparator)
    }

    private func row(_ fields: [String], _ options: CSVOptions) -> String {
        fields.map { escape($0, options.delimiter) }.joined(separator: String(options.delimiter))
    }

    /// RFC 4180 quoting.
    private func escape(_ field: String, _ delimiter: Character) -> String {
        let needsQuotes = field.contains(delimiter) || field.contains("\"") || field.contains("\n") || field.contains("\r")
        guard needsQuotes else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

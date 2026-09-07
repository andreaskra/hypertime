import Foundation

public enum TimeStyle: String, CaseIterable, Codable, Sendable {
    case clock           // 1:30:15
    case clockNoSeconds  // 1:30
    case units           // 1h 30m
    case decimalHours    // 1.50
}

public struct TimeFormatter: Sendable {
    public init() {}

    public func string(_ seconds: Seconds, style: TimeStyle, decimalSeparator: String = ".") -> String {
        let negative = seconds < 0
        let total = abs(seconds)
        let body: String

        switch style {
        case .clock:
            let (h, m, s) = Self.split(total)
            body = "\(h):" + Self.pad(m) + ":" + Self.pad(s)

        case .clockNoSeconds:
            let (h, m, _) = Self.split(total)
            body = "\(h):" + Self.pad(m)

        case .units:
            let (h, m, s) = Self.split(total)
            var parts: [String] = []
            if h > 0 { parts.append("\(h)h") }
            if m > 0 { parts.append("\(m)m") }
            if s > 0 { parts.append("\(s)s") }
            body = parts.isEmpty ? "0m" : parts.joined(separator: " ")

        case .decimalHours:
            let hours = Double(total) / 3600
            body = String(format: "%.2f", hours).replacingOccurrences(of: ".", with: decimalSeparator)
        }

        return negative ? "-" + body : body
    }

    /// Compact form for the menu bar / status line: `1:30:15`.
    public func elapsed(_ seconds: Seconds) -> String { string(seconds, style: .clock) }

    private static func split(_ total: Seconds) -> (Int, Int, Int) {
        (total / 3600, (total % 3600) / 60, total % 60)
    }

    private static func pad(_ value: Int) -> String {
        value < 10 ? "0\(value)" : String(value)
    }
}

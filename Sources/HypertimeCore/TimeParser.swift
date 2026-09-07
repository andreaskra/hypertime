import Foundation

public enum ParsedTime: Equatable, Sendable {
    case absolute(Seconds)
    case relative(Seconds)

    public var seconds: Seconds {
        switch self {
        case .absolute(let s), .relative(let s): return s
        }
    }

    public var isRelative: Bool { if case .relative = self { return true }; return false }
}

public enum TimeParseError: Error, Equatable, Sendable {
    case empty
    case unrecognized
    case duplicateUnit
    case outOfRange
    case minutesOutOfRange
    case secondsOutOfRange
}

/// Free-text duration parser (§5.2). Hours, minutes and seconds only; never dates.
public struct TimeParser: Sendable {
    private enum Unit: Int, Comparable {
        case hours = 3, minutes = 2, seconds = 1

        var factor: Double {
            switch self {
            case .hours: return 3600
            case .minutes: return 60
            case .seconds: return 1
            }
        }

        var smaller: Unit? {
            switch self {
            case .hours: return .minutes
            case .minutes: return .seconds
            case .seconds: return nil
            }
        }

        static func < (lhs: Unit, rhs: Unit) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private static let unitWords: [String: Unit] = [
        "h": .hours, "hr": .hours, "hrs": .hours, "hour": .hours, "hours": .hours, "std": .hours,
        "stunde": .hours, "stunden": .hours,
        "m": .minutes, "min": .minutes, "mins": .minutes, "minute": .minutes, "minutes": .minutes,
        "minuten": .minutes,
        "s": .seconds, "sec": .seconds, "secs": .seconds, "second": .seconds, "seconds": .seconds,
        "sek": .seconds, "sekunden": .seconds,
    ]

    public let decimalSeparators: Set<Character>

    public init(decimalSeparators: Set<Character> = [".", ","]) {
        self.decimalSeparators = decimalSeparators
    }

    // MARK: - Parsing

    public func parse(_ text: String) throws -> ParsedTime {
        var body = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !body.isEmpty else { return .absolute(0) }

        var sign = 0
        if let first = body.first, first == "+" || first == "-" {
            sign = first == "-" ? -1 : 1
            body = body.dropFirst()
            while let f = body.first, f.isWhitespace { body = body.dropFirst() }
            guard !body.isEmpty else { throw TimeParseError.unrecognized }
        }

        let magnitude = try magnitudeSeconds(body)
        guard magnitude <= secondsPerDay else { throw TimeParseError.outOfRange }

        return sign == 0 ? .absolute(magnitude) : .relative(sign * magnitude)
    }

    /// Applies a parsed value to an existing total. Absolute sets, relative adjusts. Clamps to 0...24 h.
    public func apply(_ parsed: ParsedTime, to current: Seconds) -> Seconds {
        switch parsed {
        case .absolute(let s): return min(max(s, 0), secondsPerDay)
        case .relative(let d): return min(max(current + d, 0), secondsPerDay)
        }
    }

    /// Convenience: parse and require an absolute value (used by the popup's "time to add" field).
    public func parseAbsolute(_ text: String) throws -> Seconds {
        let parsed = try parse(text)
        guard case .absolute(let s) = parsed else { throw TimeParseError.unrecognized }
        return s
    }

    // MARK: - Grammar

    private func magnitudeSeconds(_ body: Substring) throws -> Seconds {
        if body.contains(":") { return try colonForm(body) }
        return try unitForm(body)
    }

    /// `H:MM` and `H:MM:SS`.
    private func colonForm(_ body: Substring) throws -> Seconds {
        let parts = body.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { throw TimeParseError.unrecognized }

        var values: [Int] = []
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.allSatisfy({ $0.isASCII && $0.isNumber }), let v = Int(trimmed) else {
                throw TimeParseError.unrecognized
            }
            values.append(v)
        }

        let hours = values[0]
        let minutes = values[1]
        let seconds = values.count == 3 ? values[2] : 0

        guard minutes <= 59 else { throw TimeParseError.minutesOutOfRange }
        guard seconds <= 59 else { throw TimeParseError.secondsOutOfRange }
        guard hours <= 24 else { throw TimeParseError.outOfRange }

        return hours * 3600 + minutes * 60 + seconds
    }

    /// Unit groups (`1h 30m`), trailing bare numbers (`1h30`) and the bare-number rule (D-10).
    private func unitForm(_ body: Substring) throws -> Seconds {
        var tokens: [(value: Double, unit: Unit?)] = []
        var index = body.startIndex

        func skipWhitespace() {
            while index < body.endIndex, body[index].isWhitespace { index = body.index(after: index) }
        }

        while true {
            skipWhitespace()
            guard index < body.endIndex else { break }

            // Number
            var digits = ""
            var sawSeparator = false
            while index < body.endIndex {
                let c = body[index]
                if c.isASCII && c.isNumber {
                    digits.append(c)
                } else if decimalSeparators.contains(c), !sawSeparator {
                    sawSeparator = true
                    digits.append(".")
                } else {
                    break
                }
                index = body.index(after: index)
            }
            guard digits.contains(where: { $0.isNumber }), let value = Double(digits) else {
                throw TimeParseError.unrecognized
            }

            // Unit word
            skipWhitespace()
            var word = ""
            while index < body.endIndex, body[index].isLetter {
                word.append(body[index])
                index = body.index(after: index)
            }

            if word.isEmpty {
                tokens.append((value, nil))
            } else {
                guard let unit = Self.unitWords[word.lowercased()] else { throw TimeParseError.unrecognized }
                tokens.append((value, unit))
            }
        }

        guard !tokens.isEmpty else { throw TimeParseError.unrecognized }

        // Bare number on its own: integer → minutes, decimal → hours (D-10).
        if tokens.count == 1, tokens[0].unit == nil {
            let v = tokens[0].value
            let isInteger = v == v.rounded()
            return Self.round(isInteger ? v * 60 : v * 3600)
        }

        var total: Double = 0
        var used: Set<Unit> = []
        var previous: Unit?

        for (offset, token) in tokens.enumerated() {
            let unit: Unit
            if let u = token.unit {
                unit = u
            } else {
                // Only a single trailing bare number is allowed, taking the next smaller unit.
                guard offset == tokens.count - 1, let prev = previous, let smaller = prev.smaller else {
                    throw TimeParseError.unrecognized
                }
                unit = smaller
            }
            guard used.insert(unit).inserted else { throw TimeParseError.duplicateUnit }
            total += token.value * unit.factor
            previous = unit
        }

        return Self.round(total)
    }

    private static func round(_ value: Double) -> Seconds {
        guard value.isFinite else { return Int.max }
        let clamped = min(value.rounded(), Double(Int.max / 2))
        return Int(clamped)
    }
}

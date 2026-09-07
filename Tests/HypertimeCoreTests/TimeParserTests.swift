import Testing
@testable import HypertimeCore

private let parser = TimeParser()

@Suite("TimeParser — §5.2 table")
struct TimeParserTableTests {

    @Test("absolute forms", arguments: [
        ("1:30", 5400), ("1:30:15", 5415), ("0:05", 300), ("1:5", 3900),
        ("1h", 3600), ("1h 30m", 5400), ("1h30", 5400), ("1h30m15s", 5415),
        ("90m", 5400), ("90 min", 5400), ("90 minutes", 5400),
        ("1.5h", 5400), ("1,5h", 5400), ("1.5 hours", 5400), (".5h", 1800),
        ("5400s", 5400), ("90", 5400), ("1.5", 5400),
        ("2 hours 5 minutes 3 seconds", 7503), ("30m 1h", 5400), ("1 Std 30 Min", 5400),
        ("", 0), ("   ", 0), ("24h", 86400), ("2.5m", 150), ("0", 0), ("0:00:00", 0),
        ("1H30M", 5400), ("  1h  30m  ", 5400), ("1hour30minutes", 5400), ("1h30m15", 5415),
    ])
    func absolute(input: String, expected: Seconds) throws {
        #expect(try parser.parse(input) == .absolute(expected), "input: \(input)")
    }

    @Test("errors", arguments: [
        ("1:75", TimeParseError.minutesOutOfRange),
        ("1:30:75", TimeParseError.secondsOutOfRange),
        ("25h", TimeParseError.outOfRange),
        ("1500m", TimeParseError.outOfRange),
        ("25:00", TimeParseError.outOfRange),
        ("1h 1h", TimeParseError.duplicateUnit),
        ("30m 30m", TimeParseError.duplicateUnit),
        ("abc", TimeParseError.unrecognized),
        ("1x", TimeParseError.unrecognized),
        ("1::2", TimeParseError.unrecognized),
        ("1:2:3:4", TimeParseError.unrecognized),
        ("h", TimeParseError.unrecognized),
        ("+", TimeParseError.unrecognized),
        ("1h 30", TimeParseError.unrecognized),   // bare number is fine…
    ])
    func errors(input: String, expected: TimeParseError) {
        // "1h 30" is legal (trailing bare number → minutes); handled separately below.
        if input == "1h 30" {
            #expect((try? parser.parse(input)) == .absolute(5400))
            return
        }
        #expect(throws: expected) { try parser.parse(input) }
    }

    @Test("relative forms")
    func relative() throws {
        #expect(try parser.parse("+15m") == .relative(900))
        #expect(try parser.parse("-1:00") == .relative(-3600))
        #expect(try parser.parse("+ 15 min") == .relative(900))
        #expect(try parser.parse("-30") == .relative(-1800))
        #expect(try parser.parse("+1.5h") == .relative(5400))
    }

    @Test("apply clamps to 0…24 h")
    func apply() {
        #expect(parser.apply(.relative(-3600), to: 1800) == 0)
        #expect(parser.apply(.relative(900), to: 1800) == 2700)
        #expect(parser.apply(.absolute(7200), to: 1800) == 7200)
        #expect(parser.apply(.absolute(999_999), to: 0) == 86400)
        #expect(parser.apply(.relative(86400), to: 3600) == 86400)
    }

    @Test("bare number rule (D-10)")
    func bareNumbers() throws {
        #expect(try parser.parse("1") == .absolute(60))
        #expect(try parser.parse("60") == .absolute(3600))
        #expect(try parser.parse("0.5") == .absolute(1800))
        #expect(try parser.parse("0,25") == .absolute(900))
    }

    @Test("trailing bare number takes the next smaller unit")
    func trailingBare() throws {
        #expect(try parser.parse("1h30") == .absolute(5400))
        #expect(try parser.parse("1h30m15") == .absolute(5415))
        #expect(try parser.parse("2m30") == .absolute(150))
        #expect(throws: TimeParseError.unrecognized) { try parser.parse("30s15") }
        #expect(throws: TimeParseError.unrecognized) { try parser.parse("30 1h") }
    }

    @Test("parseAbsolute rejects relative input")
    func absoluteOnly() {
        #expect(throws: TimeParseError.unrecognized) { try parser.parseAbsolute("+5m") }
        #expect((try? parser.parseAbsolute("5m")) == 300)
    }
}

@Suite("TimeFormatter")
struct TimeFormatterTests {
    let f = TimeFormatter()

    @Test("clock never pads hours")
    func clock() {
        #expect(f.string(300, style: .clock) == "0:05:00")
        #expect(f.string(43200, style: .clock) == "12:00:00")
        #expect(f.string(5415, style: .clock) == "1:30:15")
        #expect(f.string(0, style: .clock) == "0:00:00")
        #expect(f.string(-90, style: .clock) == "-0:01:30")
    }

    @Test("other styles")
    func styles() {
        #expect(f.string(5415, style: .clockNoSeconds) == "1:30")
        #expect(f.string(5415, style: .units) == "1h 30m 15s")
        #expect(f.string(5400, style: .units) == "1h 30m")
        #expect(f.string(3600, style: .units) == "1h")
        #expect(f.string(0, style: .units) == "0m")
        #expect(f.string(5400, style: .decimalHours) == "1.50")
        #expect(f.string(5400, style: .decimalHours, decimalSeparator: ",") == "1,50")
    }

    @Test("round trip parse(format(x)) == x")
    func roundTrip() throws {
        for style in [TimeStyle.clock, .units] {
            for seconds in stride(from: 0, through: 86400, by: 617) {
                let text = f.string(seconds, style: style)
                #expect(try parser.parse(text) == .absolute(seconds), "\(style) \(text)")
            }
        }
        for minutes in stride(from: 0, through: 1440, by: 7) {
            let text = f.string(minutes * 60, style: .clockNoSeconds)
            #expect(try parser.parse(text) == .absolute(minutes * 60), "\(text)")
        }
    }
}

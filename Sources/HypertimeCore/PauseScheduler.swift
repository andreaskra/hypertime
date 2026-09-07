import Foundation

public enum PausePreset: String, CaseIterable, Sendable {
    case m15, m30, h1, h2, untilMorning, custom

    public var duration: Seconds? {
        switch self {
        case .m15: return 15 * 60
        case .m30: return 30 * 60
        case .h1: return 3600
        case .h2: return 7200
        case .untilMorning, .custom: return nil
        }
    }

    public func title(morningHour: Int) -> String {
        switch self {
        case .m15: return "15 minutes"
        case .m30: return "30 minutes"
        case .h1: return "1 hour"
        case .h2: return "2 hours"
        case .untilMorning: return String(format: "Until %02d:00", morningHour)
        case .custom: return "Custom…"
        }
    }
}

public struct PauseScheduler: Sendable {
    public init() {}

    public func until(_ preset: PausePreset,
                      customDuration: Seconds? = nil,
                      now: Date,
                      calendar: Calendar,
                      morningHour: Int = 7) -> Date {
        switch preset {
        case .untilMorning:
            return nextMorning(after: now, calendar: calendar, hour: morningHour)
        case .custom:
            return now.addingTimeInterval(TimeInterval(max(customDuration ?? 0, 0)))
        default:
            return now.addingTimeInterval(TimeInterval(preset.duration ?? 0))
        }
    }

    /// The next occurrence of `hour`:00 local time, strictly after `now`.
    public func nextMorning(after now: Date, calendar: Calendar, hour: Int) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        comps.hour = hour
        comps.minute = 0
        comps.second = 0
        if let today = calendar.date(from: comps), today > now { return today }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400)
        var next = calendar.dateComponents([.year, .month, .day], from: tomorrow)
        next.hour = hour
        next.minute = 0
        next.second = 0
        return calendar.date(from: next) ?? now.addingTimeInterval(86_400)
    }
}

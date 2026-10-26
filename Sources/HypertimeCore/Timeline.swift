import Foundation

/// What the app was doing during a stretch of time (TL-01). This is a record of the engine's
/// own behaviour, not of what was finally confirmed — which is the point: the strip exists so
/// you can check whether the app noticed you had walked away.
public enum SliceKind: String, CaseIterable, Codable, Sendable {
    case tracked
    case idle
    case paused
}

/// Seconds of one kind inside one bracket. A bracket where the project changed halfway, or
/// where tracking gave way to idle, has more than one of these.
public struct Slice: Hashable, Sendable {
    public var bucketStart: Date
    public var kind: SliceKind
    public var projectID: UUID?
    public var seconds: Seconds

    public init(bucketStart: Date, kind: SliceKind, projectID: UUID?, seconds: Seconds) {
        self.bucketStart = bucketStart
        self.kind = kind
        self.projectID = projectID
        self.seconds = seconds
    }
}

/// One mark on the strip: what it is, and everything that happened inside it.
public struct TimelineBucket: Identifiable, Hashable, Sendable {
    public var start: Date
    /// Ordered by seconds, largest first — the first entry is what colours the mark.
    public var parts: [Slice]

    public var id: Date { start }

    public var isEmpty: Bool { parts.isEmpty }
    public var dominant: Slice? { parts.first }
    public var seconds: Seconds { parts.reduce(0) { $0 + $1.seconds } }
    public var isMixed: Bool { parts.count > 1 }
}

/// Turns slices into the row of marks the strip draws (TL-01 … TL-04).
public enum Timeline {

    /// Ten minutes (TLD-03). The coarsest bracket at which one default idle timeout fills a
    /// whole mark, which is the question the strip exists to answer. Anything coarser loses a
    /// single idle stretch inside a tracked one and answers a question nobody asked.
    public static let grain: TimeInterval = 600

    /// How far back the strip reaches.
    public static let window: TimeInterval = 24 * 3600

    public static var bucketCount: Int { Int(window / grain) }

    /// Start of the bracket a moment falls in.
    public static func bucketStart(for date: Date, grain: TimeInterval = grain) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / grain).rounded(.down) * grain)
    }

    /// The marks for the window ending at `now`, oldest first. Always exactly `bucketCount`
    /// of them: a bracket nothing is known about is empty rather than absent, because the
    /// strip's whole job is to be a proportional picture of the last day.
    public static func buckets(from slices: [Slice], now: Date,
                               grain: TimeInterval = grain,
                               window: TimeInterval = window) -> [TimelineBucket] {
        let count = Int(window / grain)
        let newest = bucketStart(for: now, grain: grain)
        let oldest = newest.addingTimeInterval(-grain * Double(count - 1))

        var byBucket: [Date: [Slice]] = [:]
        for slice in slices where slice.seconds > 0 {
            let start = bucketStart(for: slice.bucketStart, grain: grain)
            guard start >= oldest, start <= newest else { continue }
            byBucket[start, default: []].append(slice)
        }

        return (0..<count).map { index in
            let start = oldest.addingTimeInterval(grain * Double(index))
            return TimelineBucket(start: start, parts: rank(byBucket[start] ?? []))
        }
    }

    /// Dominant first (TLD-05). Ties go to whatever ran latest in the bracket, so a long
    /// stretch at an even split does not flicker between two colours mark by mark (TLA-03).
    private static func rank(_ parts: [Slice]) -> [Slice] {
        var merged: [Slice] = []
        for part in parts {
            if let index = merged.firstIndex(where: { $0.kind == part.kind && $0.projectID == part.projectID }) {
                merged[index].seconds += part.seconds
            } else {
                merged.append(part)
            }
        }
        return merged.enumerated()
            .sorted { a, b in
                if a.element.seconds != b.element.seconds { return a.element.seconds > b.element.seconds }
                return a.offset > b.offset
            }
            .map(\.element)
    }
}

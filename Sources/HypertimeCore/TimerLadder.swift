import Foundation

/// The set of timer lengths the slider can land on (T-10).
///
/// A linear 1 minute … 8 hour slider would spend four fifths of its travel on lengths nobody
/// sets. The ladder is dense where the choices matter — every minute up to a quarter of an
/// hour, then five-minute steps to the hour — and opens out afterwards, so the whole range
/// still fits in one short sweep and every slot is a round number someone would actually say
/// out loud.
public enum TimerLadder {

    /// One step per slot, coarsening as the lengths grow.
    private static let bands: [(upTo: Seconds, step: Seconds)] = [
        (900, 60),        // 1 … 15 minutes, by the minute
        (3600, 300),      // 20 … 60 minutes, by five
        (7200, 900),      // 1¼ … 2 hours, by the quarter
        (14_400, 1800),   // 2½ … 4 hours, by the half
        (28_800, 3600),   // 5 … 8 hours, by the hour
    ]

    /// Every length the slider can produce, ascending. 1 minute to 8 hours in 36 slots.
    public static let slots: [Seconds] = {
        var values: [Seconds] = []
        var lower: Seconds = 0
        for band in bands {
            var value = lower + band.step
            while value <= band.upTo {
                values.append(value)
                value += band.step
            }
            lower = band.upTo
        }
        return values
    }()

    public static var shortest: Seconds { slots.first ?? 60 }
    public static var longest: Seconds { slots.last ?? 28_800 }

    /// The length at `index`, clamped to the ladder.
    public static func seconds(at index: Int) -> Seconds {
        slots[min(max(index, 0), slots.count - 1)]
    }

    /// The slot nearest a length in seconds — how an existing timer finds its place on the
    /// slider, whatever set it.
    public static func index(nearest seconds: Seconds) -> Int {
        var best = 0
        var bestDistance = Int.max
        for (index, value) in slots.enumerated() {
            let distance = abs(value - seconds)
            if distance < bestDistance {
                best = index
                bestDistance = distance
            }
        }
        return best
    }

    /// Slot for a position along the track, 0 at the left end and 1 at the right.
    public static func index(atFraction fraction: Double) -> Int {
        let scaled = (fraction * Double(slots.count - 1)).rounded()
        return min(max(Int(scaled), 0), slots.count - 1)
    }

    /// Where a slot sits along the track, 0 … 1. Slots are evenly spaced: the non-linearity is
    /// in what they are worth, which is the whole point.
    public static func fraction(ofIndex index: Int) -> Double {
        guard slots.count > 1 else { return 0 }
        return Double(min(max(index, 0), slots.count - 1)) / Double(slots.count - 1)
    }

    /// Spoken form for the readout: "25 min", "1h 30m", "8h".
    public static func label(_ seconds: Seconds, formatter: TimeFormatter = TimeFormatter()) -> String {
        seconds < 3600 ? "\(seconds / 60) min" : formatter.string(seconds, style: .units)
    }
}

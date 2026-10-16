import Foundation
import Testing
@testable import HypertimeCore

@Suite("TimerLadder")
struct TimerLadderTests {

    @Test("the ladder spans one minute to eight hours and only ever climbs")
    func span() {
        #expect(TimerLadder.shortest == 60)
        #expect(TimerLadder.longest == 8 * 3600)
        #expect(TimerLadder.slots == TimerLadder.slots.sorted())
        #expect(Set(TimerLadder.slots).count == TimerLadder.slots.count)
    }

    @Test("resolution is fine where it matters and coarse where it does not")
    func resolution() {
        let slots = TimerLadder.slots
        // Every minute up to a quarter of an hour.
        #expect(Array(slots.prefix(15)) == Array(stride(from: 60, through: 900, by: 60)))
        // Half the ladder is spent on the first hour.
        let withinTheHour = slots.filter { $0 <= 3600 }.count
        #expect(withinTheHour * 2 >= slots.count)
        // …and the whole thing still fits in a short sweep.
        #expect(slots.count <= 40)
        // Every slot is a length someone would say out loud: a whole number of minutes, and
        // past the hour a whole quarter of one.
        #expect(slots.allSatisfy { $0 % 60 == 0 })
        #expect(slots.filter { $0 > 3600 }.allSatisfy { $0 % 900 == 0 })
    }

    @Test("an existing timer finds the nearest slot, whatever set it")
    func nearest() {
        #expect(TimerLadder.seconds(at: TimerLadder.index(nearest: 1500)) == 1500)   // 25m, exact
        #expect(TimerLadder.seconds(at: TimerLadder.index(nearest: 1510)) == 1500)   // rounds back
        #expect(TimerLadder.seconds(at: TimerLadder.index(nearest: 7)) == 60)        // below the floor
        #expect(TimerLadder.seconds(at: TimerLadder.index(nearest: 99_999)) == 8 * 3600)
    }

    @Test("positions along the track map back to the slot they came from")
    func positions() {
        for index in TimerLadder.slots.indices {
            #expect(TimerLadder.index(atFraction: TimerLadder.fraction(ofIndex: index)) == index)
        }
        #expect(TimerLadder.index(atFraction: -1) == 0)
        #expect(TimerLadder.index(atFraction: 2) == TimerLadder.slots.count - 1)
        #expect(TimerLadder.seconds(at: -5) == TimerLadder.shortest)
        #expect(TimerLadder.seconds(at: 9999) == TimerLadder.longest)
    }

    @Test("the readout names the length the way a person would")
    func labels() {
        #expect(TimerLadder.label(60) == "1 min")
        #expect(TimerLadder.label(1500) == "25 min")
        #expect(TimerLadder.label(3600) == "1h")
        #expect(TimerLadder.label(5400) == "1h 30m")
        #expect(TimerLadder.label(8 * 3600) == "8h")
    }
}

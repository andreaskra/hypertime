import Foundation
import HypertimeCore

/// `--seed-demo`: plausible data in a separate database, for screenshots and design QA.
enum DemoData {
    static let projectNames = ["Hypertime", "Client · Müller", "Admin", "Design System", "Sales calls", "Learning"]

    static func seed(store: Store, clock: Clock) throws {
        guard try store.projects(includeArchived: true).isEmpty else { return }

        var generator = SeededGenerator(seed: 20260907)
        let projects = try projectNames.map { try store.findOrCreateProject(named: $0) }
        let today = LocalDate(clock.now(), calendar: clock.calendar)

        for offset in stride(from: -89, through: 0, by: 1) {
            let day = today.adding(days: offset, calendar: clock.calendar)
            let weekday = clock.calendar.component(.weekday, from: day.startOfDay(calendar: clock.calendar))
            let isWeekend = weekday == 1 || weekday == 7
            if isWeekend && Int.random(in: 0...3, using: &generator) != 0 { continue }

            let count = Int.random(in: 1...3, using: &generator)
            for project in projects.shuffled(using: &generator).prefix(count) {
                let minutes = Int.random(in: 20...260, using: &generator)
                try store.setSeconds(project: project.id, day: day, minutes * 60)
            }
        }

        for project in projects {
            try store.touchProject(id: project.id)
        }
    }
}

/// Deterministic RNG so the demo database looks the same every time.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

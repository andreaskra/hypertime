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

        try seedTimeline(store: store, clock: clock, projects: projects, generator: &generator)
    }

    /// A day's worth of brackets for the strip: stretches of work on one project at a time,
    /// broken by the idle gaps the strip exists to show, and nothing at all overnight.
    private static func seedTimeline(store: Store, clock: Clock, projects: [Project],
                                     generator: inout SeededGenerator) throws {
        let now = clock.now()
        var cursor = Timeline.bucketStart(for: now.addingTimeInterval(-Timeline.window))
        var project = projects[0]

        while cursor < now {
            let hour = clock.calendar.component(.hour, from: cursor)
            // Asleep: the app was not running, so nothing is known rather than nothing happened.
            guard hour >= 8, hour < 21 else {
                cursor = cursor.addingTimeInterval(Timeline.grain)
                continue
            }
            switch Int.random(in: 0...9, using: &generator) {
            case 0...5:
                try store.addSlice(bucketStart: cursor, kind: .tracked, project: project.id,
                                   Int(Timeline.grain))
            case 6...7:
                try store.addSlice(bucketStart: cursor, kind: .idle, project: nil, Int(Timeline.grain))
            case 8:
                // A bracket where the work changed hands halfway.
                let next = projects.randomElement(using: &generator) ?? project
                try store.addSlice(bucketStart: cursor, kind: .tracked, project: project.id, 380)
                try store.addSlice(bucketStart: cursor, kind: .tracked, project: next.id, 220)
                project = next
            default:
                try store.addSlice(bucketStart: cursor, kind: .paused, project: nil, Int(Timeline.grain))
            }
            if Int.random(in: 0...6, using: &generator) == 0 {
                project = projects.randomElement(using: &generator) ?? project
            }
            cursor = cursor.addingTimeInterval(Timeline.grain)
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

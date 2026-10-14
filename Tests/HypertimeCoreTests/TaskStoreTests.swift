import Foundation
import Testing
@testable import HypertimeCore

private func d(_ iso: String) -> LocalDate { LocalDate.parse(iso)! }

@Suite("Store — tasks")
struct TaskStoreTests {
    let clock = TestClock()
    let store: Store
    let project: Project

    init() throws {
        clock.set(year: 2026, month: 10, day: 14, hour: 9)
        store = try Store.inMemory(clock: clock)
        project = try store.findOrCreateProject(named: "Hypertime")
    }

    @Test("create, list and complete")
    func lifecycle() throws {
        let a = try store.createTask(projectID: project.id, title: "  Write the spec  ")
        #expect(a.title == "Write the spec")                       // trimmed
        let b = try store.createTask(projectID: project.id, title: "Ship it")
        #expect(try store.tasks().map(\.title) == ["Write the spec", "Ship it"])   // creation order

        try store.completeTask(id: a.id)
        #expect(try store.tasks().map(\.title) == ["Ship it"])      // open only
        #expect(try store.tasks(includeCompleted: true).count == 2)
        #expect(try store.task(id: a.id)?.isComplete == true)

        try store.reopenTask(id: a.id)
        #expect(try store.tasks().count == 2)
        #expect(throws: StoreError.emptyName) { try store.createTask(projectID: project.id, title: "  ") }
    }

    @Test("task time is booked to the project as well, never on top of it")
    func subdivision() throws {
        let task = try store.createTask(projectID: project.id, title: "Deep work")
        try store.addTaskSeconds(task: task.id, project: project.id, day: d("2026-10-14"), 1800)
        try store.addTaskSeconds(task: task.id, project: project.id, day: d("2026-10-14"), 900)

        #expect(try store.taskSeconds(task: task.id, day: d("2026-10-14")) == 2700)
        #expect(try store.seconds(project: project.id, day: d("2026-10-14")) == 2700)

        // Untasked time on the same project adds on top of the task's.
        _ = try store.addSeconds(project: project.id, day: d("2026-10-14"), 300)
        #expect(try store.seconds(project: project.id, day: d("2026-10-14")) == 3000)
        #expect(try store.taskSeconds(task: task.id, day: d("2026-10-14")) == 2700)
        #expect(try store.taskSeconds(task: task.id, day: d("2026-10-14"))
                <= store.seconds(project: project.id, day: d("2026-10-14")))
    }

    @Test("a task accumulates across days")
    func acrossDays() throws {
        let task = try store.createTask(projectID: project.id, title: "Long one")
        try store.addTaskSeconds(task: task.id, project: project.id, day: d("2026-10-13"), 600)
        try store.addTaskSeconds(task: task.id, project: project.id, day: d("2026-10-14"), 1200)
        #expect(try store.taskSeconds(task: task.id) == 1800)
        #expect(try store.taskSeconds(task: task.id, day: d("2026-10-13")) == 600)
        #expect(try store.taskTotals(in: d("2026-10-14")...d("2026-10-14"))[task.id] == 1200)
    }

    @Test("deleting a task keeps the time on its project")
    func deleteKeepsProjectTime() throws {
        let task = try store.createTask(projectID: project.id, title: "Doomed")
        try store.addTaskSeconds(task: task.id, project: project.id, day: d("2026-10-14"), 900)
        try store.deleteTask(id: task.id)

        #expect(try store.tasks(includeCompleted: true).isEmpty)
        #expect(try store.taskSeconds(task: task.id) == 0)
        #expect(try store.seconds(project: project.id, day: d("2026-10-14")) == 900)
    }

    @Test("deleting a project takes its tasks with it")
    func projectCascade() throws {
        let task = try store.createTask(projectID: project.id, title: "Goes too")
        try store.addTaskSeconds(task: task.id, project: project.id, day: d("2026-10-14"), 60)
        try store.deleteProject(id: project.id)
        #expect(try store.tasks(includeCompleted: true).isEmpty)
        #expect(try store.taskSeconds(task: task.id) == 0)
    }

    @Test("timer and reassignment")
    func timerAndMove() throws {
        let other = try store.findOrCreateProject(named: "Admin")
        let task = try store.createTask(projectID: project.id, title: "Timed", timerSeconds: 1500)
        #expect(try store.task(id: task.id)?.timerSeconds == 1500)
        try store.setTaskTimer(id: task.id, seconds: nil)
        #expect(try store.task(id: task.id)?.timerSeconds == nil)

        try store.updateTask(id: task.id, projectID: other.id)
        #expect(try store.task(id: task.id)?.projectID == other.id)
        #expect(try store.tasks(project: other.id).count == 1)

        try store.updateTask(id: task.id, title: "Renamed")
        #expect(try store.task(id: task.id)?.title == "Renamed")
    }

    @Test("over-long titles are capped")
    func longTitle() throws {
        let task = try store.createTask(projectID: project.id, title: String(repeating: "x", count: 500))
        #expect(task.title.count == maxTaskTitleLength)
    }
}

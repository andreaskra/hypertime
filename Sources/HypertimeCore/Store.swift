import Foundation
import GRDB

public enum StoreError: Error, Equatable, Sendable {
    case emptyName
    case duplicateName(String)
    case notFound
}

/// Longest project name we store. Anything longer is truncated on the way in, so a stray paste
/// can not produce a name that breaks layout or queries (Phase 3).
public let maxProjectNameLength = 200

public enum StoreChange: String, Sendable, Hashable, CaseIterable {
    case projects
    case entries
    case engineState
}

/// Engine state persisted across launches and crashes (§5.5).
public struct PersistedEngineState: Equatable, Sendable {
    public enum Kind: String, Sendable { case idle, tracking, paused }

    public var kind: Kind
    public var currentProjectID: UUID?
    public var trackingSince: Date?
    public var pausedUntil: Date?
    public var pauseReason: PauseReason?
    public var lastTickAt: Date?
    public var pendingProjectID: UUID?
    public var pendingSeconds: Seconds?
    public var pendingSince: Date?
    public var lastCheckInAt: Date?
    public var lastCommitAt: Date?

    public init(kind: Kind = .idle,
                currentProjectID: UUID? = nil,
                trackingSince: Date? = nil,
                pausedUntil: Date? = nil,
                pauseReason: PauseReason? = nil,
                lastTickAt: Date? = nil,
                pendingProjectID: UUID? = nil,
                pendingSeconds: Seconds? = nil,
                pendingSince: Date? = nil,
                lastCheckInAt: Date? = nil,
                lastCommitAt: Date? = nil) {
        self.kind = kind
        self.currentProjectID = currentProjectID
        self.trackingSince = trackingSince
        self.pausedUntil = pausedUntil
        self.pauseReason = pauseReason
        self.lastTickAt = lastTickAt
        self.pendingProjectID = pendingProjectID
        self.pendingSeconds = pendingSeconds
        self.pendingSince = pendingSince
        self.lastCheckInAt = lastCheckInAt
        self.lastCommitAt = lastCommitAt
    }
}

public struct ChangeLogEntry: Equatable, Sendable {
    public let id: Int64
    public let at: Date
    public let kind: String
    public let payload: String
}

/// All persistence goes through `Store`. Methods are synchronous and safe to call from the
/// main actor; GRDB serialises access internally.
public final class Store: @unchecked Sendable {
    private let dbQueue: DatabaseQueue
    private let clock: Clock
    private let observers = Broadcaster<StoreChange>()

    public let path: String

    /// Set when the database on disk could not be opened and was moved aside; holds the path of
    /// the quarantined copy so the user can be told where their old data went.
    public private(set) var recoveredFromCorruption: String?

    // MARK: - Lifecycle

    public init(path: String, clock: Clock, recoverFromCorruption: Bool = true) throws {
        self.path = path
        self.clock = clock
        if path != ":memory:" {
            let directory = (path as NSString).deletingLastPathComponent
            if !directory.isEmpty {
                try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            }
        }
        var config = Configuration()
        config.foreignKeysEnabled = true

        do {
            self.dbQueue = try Self.open(path: path, config: config)
        } catch {
            // A missing file is created by GRDB; getting here means it exists and is unusable.
            guard recoverFromCorruption, path != ":memory:" else { throw error }
            self.recoveredFromCorruption = Self.quarantine(path: path, clock: clock)
            self.dbQueue = try Self.open(path: path, config: config)
        }
        try pruneChangeLog()
    }

    private static func open(path: String, config: Configuration) throws -> DatabaseQueue {
        let queue = try DatabaseQueue(path: path, configuration: config)
        try migrator.migrate(queue)
        // Migrations succeed on a file that is only partly readable; force a real read too.
        try queue.read { db in _ = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM project") }
        return queue
    }

    /// Moves an unusable database (and its sidecar files) aside. Returns the new path.
    private static func quarantine(path: String, clock: Clock) -> String? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.timeZone = clock.timeZone
        let stamp = formatter.string(from: clock.now())
        let base = (path as NSString).deletingPathExtension
        let ext = (path as NSString).pathExtension
        let target = "\(base)-corrupt-\(stamp)" + (ext.isEmpty ? "" : ".\(ext)")

        let manager = FileManager.default
        do {
            try? manager.removeItem(atPath: target)
            try manager.moveItem(atPath: path, toPath: target)
        } catch {
            return nil
        }
        for suffix in ["-wal", "-shm"] {
            try? manager.removeItem(atPath: path + suffix)
        }
        return target
    }

    public static func inMemory(clock: Clock) throws -> Store {
        try Store(path: ":memory:", clock: clock)
    }

    /// Default on-disk location: `~/Library/Application Support/Hypertime/hypertime.sqlite`.
    public static func defaultPath(filename: String = "hypertime.sqlite") -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Hypertime", isDirectory: true)
            .appendingPathComponent(filename).path
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE project (
                  id            TEXT PRIMARY KEY,
                  name          TEXT NOT NULL UNIQUE COLLATE NOCASE,
                  created_at    REAL NOT NULL,
                  last_used_at  REAL,
                  archived      INTEGER NOT NULL DEFAULT 0
                );
                CREATE TABLE day_entry (
                  project_id    TEXT NOT NULL REFERENCES project(id) ON DELETE CASCADE,
                  day           TEXT NOT NULL,
                  seconds       INTEGER NOT NULL DEFAULT 0 CHECK (seconds >= 0 AND seconds <= 86400),
                  updated_at    REAL NOT NULL,
                  PRIMARY KEY (project_id, day)
                );
                CREATE INDEX day_entry_day ON day_entry(day);
                CREATE TABLE app_state (
                  key           TEXT PRIMARY KEY,
                  value         TEXT
                );
                CREATE TABLE change_log (
                  id            INTEGER PRIMARY KEY AUTOINCREMENT,
                  at            REAL NOT NULL,
                  kind          TEXT NOT NULL,
                  payload       TEXT NOT NULL
                );
                """)
        }
        return migrator
    }

    // MARK: - Projects

    public func projects(includeArchived: Bool = false) throws -> [Project] {
        try dbQueue.read { db in
            let sql = """
                SELECT * FROM project
                \(includeArchived ? "" : "WHERE archived = 0")
                ORDER BY last_used_at IS NULL, last_used_at DESC, name COLLATE NOCASE ASC
                """
            return try Row.fetchAll(db, sql: sql).map(Self.project)
        }
    }

    public func project(id: UUID) throws -> Project? {
        try dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM project WHERE id = ?", arguments: [id.uuidString])
                .map(Self.project)
        }
    }

    /// Trims and caps a name the way `findOrCreateProject` stores it.
    public static func normalise(name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxProjectNameLength else { return trimmed }
        return String(trimmed.prefix(maxProjectNameLength))
    }

    public func project(named name: String) throws -> Project? {
        let trimmed = Self.normalise(name: name)
        guard !trimmed.isEmpty else { return nil }
        if let found = try dbQueue.read({ db in
            try Row.fetchOne(db, sql: "SELECT * FROM project WHERE name = ? COLLATE NOCASE", arguments: [trimmed])
                .map(Self.project)
        }) {
            return found
        }
        // SQLite's NOCASE only folds ASCII; fall back to a Unicode-aware comparison.
        let needle = trimmed.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
        return try projects(includeArchived: true).first {
            $0.name.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil) == needle
        }
    }

    @discardableResult
    public func findOrCreateProject(named name: String) throws -> Project {
        let trimmed = Self.normalise(name: name)
        guard !trimmed.isEmpty else { throw StoreError.emptyName }
        if let existing = try project(named: trimmed) { return existing }

        let project = Project(name: trimmed, createdAt: clock.now())
        try write(.projects) { db in
            do {
                try db.execute(sql: "INSERT INTO project (id, name, created_at, last_used_at, archived) VALUES (?, ?, ?, NULL, 0)",
                               arguments: [project.id.uuidString, project.name, project.createdAt.timeIntervalSince1970])
            } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
                throw StoreError.duplicateName(trimmed)
            }
            try self.log(db, kind: "project.create", payload: ["id": project.id.uuidString, "name": project.name])
        }
        return project
    }

    public func renameProject(id: UUID, to name: String) throws {
        let trimmed = Self.normalise(name: name)
        guard !trimmed.isEmpty else { throw StoreError.emptyName }
        if let clash = try project(named: trimmed), clash.id != id { throw StoreError.duplicateName(trimmed) }
        try write(.projects) { db in
            do {
                try db.execute(sql: "UPDATE project SET name = ? WHERE id = ?", arguments: [trimmed, id.uuidString])
            } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
                throw StoreError.duplicateName(trimmed)
            }
            try self.log(db, kind: "project.rename", payload: ["id": id.uuidString, "name": trimmed])
        }
    }

    public func setArchived(id: UUID, _ archived: Bool) throws {
        try write(.projects) { db in
            try db.execute(sql: "UPDATE project SET archived = ? WHERE id = ?", arguments: [archived ? 1 : 0, id.uuidString])
            try self.log(db, kind: "project.archive", payload: ["id": id.uuidString, "archived": archived ? "1" : "0"])
        }
    }

    public func deleteProject(id: UUID) throws {
        try write([.projects, .entries]) { db in
            try db.execute(sql: "DELETE FROM project WHERE id = ?", arguments: [id.uuidString])
            try self.log(db, kind: "project.delete", payload: ["id": id.uuidString])
        }
    }

    public func touchProject(id: UUID) throws {
        let now = clock.now().timeIntervalSince1970
        try write(.projects) { db in
            try db.execute(sql: "UPDATE project SET last_used_at = ? WHERE id = ?", arguments: [now, id.uuidString])
        }
    }

    // MARK: - Entries

    public func seconds(project: UUID, day: LocalDate) throws -> Seconds {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT seconds FROM day_entry WHERE project_id = ? AND day = ?",
                             arguments: [project.uuidString, day.isoString]) ?? 0
        }
    }

    public func setSeconds(project: UUID, day: LocalDate, _ seconds: Seconds) throws {
        let clamped = min(max(seconds, 0), secondsPerDay)
        let now = clock.now().timeIntervalSince1970
        try write(.entries) { db in
            try db.execute(sql: """
                INSERT INTO day_entry (project_id, day, seconds, updated_at) VALUES (?, ?, ?, ?)
                ON CONFLICT(project_id, day) DO UPDATE SET seconds = excluded.seconds, updated_at = excluded.updated_at
                """, arguments: [project.uuidString, day.isoString, clamped, now])
            try self.log(db, kind: "entry.set", payload: ["project": project.uuidString, "day": day.isoString, "seconds": String(clamped)])
        }
    }

    /// Adds `delta` to the stored value, clamping the result to 0…24 h. Returns the new total.
    @discardableResult
    public func addSeconds(project: UUID, day: LocalDate, _ delta: Seconds) throws -> Seconds {
        guard delta != 0 else { return try seconds(project: project, day: day) }
        let now = clock.now().timeIntervalSince1970
        var result = 0
        try write(.entries) { db in
            let current = try Int.fetchOne(db, sql: "SELECT seconds FROM day_entry WHERE project_id = ? AND day = ?",
                                           arguments: [project.uuidString, day.isoString]) ?? 0
            let clamped = min(max(current + delta, 0), secondsPerDay)
            try db.execute(sql: """
                INSERT INTO day_entry (project_id, day, seconds, updated_at) VALUES (?, ?, ?, ?)
                ON CONFLICT(project_id, day) DO UPDATE SET seconds = excluded.seconds, updated_at = excluded.updated_at
                """, arguments: [project.uuidString, day.isoString, clamped, now])
            try self.log(db, kind: "entry.add", payload: ["project": project.uuidString, "day": day.isoString,
                                                          "delta": String(delta), "seconds": String(clamped)])
            result = clamped
        }
        return result
    }

    public func entries(in range: ClosedRange<LocalDate>) throws -> [DayEntry] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT project_id, day, seconds FROM day_entry WHERE day >= ? AND day <= ? ORDER BY day",
                             arguments: [range.lowerBound.isoString, range.upperBound.isoString])
                .compactMap { row -> DayEntry? in
                    guard let id = UUID(uuidString: row["project_id"]),
                          let day = LocalDate.parse(row["day"]) else { return nil }
                    return DayEntry(projectID: id, day: day, seconds: row["seconds"])
                }
        }
    }

    public func projectsWithEntries(in range: ClosedRange<LocalDate>) throws -> [Project] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT p.* FROM project p
                WHERE EXISTS (SELECT 1 FROM day_entry e WHERE e.project_id = p.id AND e.day >= ? AND e.day <= ? AND e.seconds > 0)
                ORDER BY p.name COLLATE NOCASE ASC
                """, arguments: [range.lowerBound.isoString, range.upperBound.isoString]).map(Self.project)
        }
    }

    public func totalSeconds(in range: ClosedRange<LocalDate>) throws -> Seconds {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COALESCE(SUM(seconds), 0) FROM day_entry WHERE day >= ? AND day <= ?",
                             arguments: [range.lowerBound.isoString, range.upperBound.isoString]) ?? 0
        }
    }

    // MARK: - Engine state

    public func loadEngineState() throws -> PersistedEngineState? {
        let values = try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT key, value FROM app_state")
                .reduce(into: [String: String]()) { dict, row in
                    if let value: String = row["value"] { dict[row["key"]] = value }
                }
        }
        guard let kindRaw = values["status"], let kind = PersistedEngineState.Kind(rawValue: kindRaw) else { return nil }

        func date(_ key: String) -> Date? { values[key].flatMap(Double.init).map(Date.init(timeIntervalSince1970:)) }
        func uuid(_ key: String) -> UUID? { values[key].flatMap(UUID.init(uuidString:)) }

        return PersistedEngineState(
            kind: kind,
            currentProjectID: uuid("current_project_id"),
            trackingSince: date("tracking_since"),
            pausedUntil: date("paused_until"),
            pauseReason: values["pause_reason"].flatMap(PauseReason.init(rawValue:)),
            lastTickAt: date("last_tick_at"),
            pendingProjectID: uuid("pending_project_id"),
            pendingSeconds: values["pending_seconds"].flatMap(Int.init),
            pendingSince: date("pending_since"),
            lastCheckInAt: date("last_check_in_at"),
            lastCommitAt: date("last_commit_at")
        )
    }

    public func saveEngineState(_ state: PersistedEngineState?) throws {
        try write(.engineState) { db in
            try db.execute(sql: "DELETE FROM app_state")
            guard let state else { return }
            var values: [String: String] = ["status": state.kind.rawValue]
            func put(_ key: String, _ value: String?) { if let value { values[key] = value } }
            put("current_project_id", state.currentProjectID?.uuidString)
            put("tracking_since", state.trackingSince.map { String($0.timeIntervalSince1970) })
            put("paused_until", state.pausedUntil.map { String($0.timeIntervalSince1970) })
            put("pause_reason", state.pauseReason?.rawValue)
            put("last_tick_at", state.lastTickAt.map { String($0.timeIntervalSince1970) })
            put("pending_project_id", state.pendingProjectID?.uuidString)
            put("pending_seconds", state.pendingSeconds.map(String.init))
            put("pending_since", state.pendingSince.map { String($0.timeIntervalSince1970) })
            put("last_check_in_at", state.lastCheckInAt.map { String($0.timeIntervalSince1970) })
            put("last_commit_at", state.lastCommitAt.map { String($0.timeIntervalSince1970) })
            for (key, value) in values {
                try db.execute(sql: "INSERT INTO app_state (key, value) VALUES (?, ?)", arguments: [key, value])
            }
        }
    }

    // MARK: - Change log

    public func changeLog(limit: Int = 100) throws -> [ChangeLogEntry] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM change_log ORDER BY id DESC LIMIT ?", arguments: [limit])
                .map { ChangeLogEntry(id: $0["id"], at: Date(timeIntervalSince1970: $0["at"]), kind: $0["kind"], payload: $0["payload"]) }
        }
    }

    /// Drops change-log rows older than 90 days (run on launch).
    public func pruneChangeLog(olderThan days: Int = 90) throws {
        let cutoff = clock.now().addingTimeInterval(-Double(days) * 86_400).timeIntervalSince1970
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM change_log WHERE at < ?", arguments: [cutoff])
        }
    }

    private func log(_ db: Database, kind: String, payload: [String: String]) throws {
        let json = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
        try db.execute(sql: "INSERT INTO change_log (at, kind, payload) VALUES (?, ?, ?)",
                       arguments: [clock.now().timeIntervalSince1970, kind, String(decoding: json, as: UTF8.self)])
    }

    // MARK: - Observation

    /// A stream of write notifications. Each call returns an independent stream.
    public var changes: AsyncStream<StoreChange> { observers.stream }

    private func write(_ change: StoreChange, _ body: @escaping (Database) throws -> Void) throws {
        try write([change], body)
    }

    private func write(_ changes: [StoreChange], _ body: @escaping (Database) throws -> Void) throws {
        try dbQueue.write(body)
        for change in changes { observers.send(change) }
    }

    // MARK: - Row mapping

    private static func project(_ row: Row) -> Project {
        Project(
            id: UUID(uuidString: row["id"]) ?? UUID(),
            name: row["name"],
            createdAt: Date(timeIntervalSince1970: row["created_at"]),
            lastUsedAt: (row["last_used_at"] as Double?).map(Date.init(timeIntervalSince1970:)),
            isArchived: (row["archived"] as Int) != 0
        )
    }
}

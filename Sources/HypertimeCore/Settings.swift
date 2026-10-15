import Foundation

/// Typed wrapper over `UserDefaults` (§5.9). Every setter publishes the changed key on `didChange`.
public final class Settings: @unchecked Sendable {
    public enum Key: String, CaseIterable, Sendable {
        case checkInIntervalMinutes
        case startTrackingOnLaunch
        case launchAtLogin
        case showInDockAndCmdTab
        case showElapsedInMenuBar
        case weekStart
        case timeDisplayStyle
        case pauseOnSleepAndLock
        case idleTimeoutMinutes
        case morningHour
        case maxGapSeconds
        case csvDelimiter
        case csvCellStyle
        case csvIncludeTotals
        case flushIntervalSeconds
        case passivePopupAutoHideSeconds
    }

    public static let checkInIntervalChoices = [0, 15, 30, 45, 60, 90, 120]

    private let defaults: UserDefaults
    private let broadcaster = Broadcaster<Key>()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.checkInIntervalMinutes.rawValue: 30,
            Key.startTrackingOnLaunch.rawValue: true,
            Key.launchAtLogin.rawValue: true,
            Key.showInDockAndCmdTab.rawValue: true,
            Key.showElapsedInMenuBar.rawValue: false,
            Key.weekStart.rawValue: Weekday.monday.rawValue,
            Key.timeDisplayStyle.rawValue: TimeStyle.clock.rawValue,
            Key.pauseOnSleepAndLock.rawValue: true,
            Key.idleTimeoutMinutes.rawValue: 10,
            Key.morningHour.rawValue: 7,
            Key.maxGapSeconds.rawValue: 120,
            Key.csvDelimiter.rawValue: ",",
            Key.csvCellStyle.rawValue: TimeStyle.clock.rawValue,
            Key.csvIncludeTotals.rawValue: true,
            Key.flushIntervalSeconds.rawValue: 15,
            Key.passivePopupAutoHideSeconds.rawValue: 20,
        ])
    }

    /// Isolated instance for tests and `--seed-demo`.
    public static func ephemeral(name: String = UUID().uuidString) -> Settings {
        let defaults = UserDefaults(suiteName: "com.hypertime.app.test." + name) ?? .standard
        defaults.removePersistentDomain(forName: "com.hypertime.app.test." + name)
        return Settings(defaults: defaults)
    }

    public var didChange: AsyncStream<Key> { broadcaster.stream }

    // MARK: - Values

    public var checkInIntervalMinutes: Int {
        get { defaults.integer(forKey: Key.checkInIntervalMinutes.rawValue) }
        set { set(newValue, .checkInIntervalMinutes) }
    }

    /// Check-in interval in seconds; `nil` when check-ins are off.
    public var checkInInterval: TimeInterval? {
        let minutes = checkInIntervalMinutes
        return minutes > 0 ? TimeInterval(minutes) * 60 : nil
    }

    /// Pick tracking back up on the last project as soon as the app starts (supersedes A-03).
    public var startTrackingOnLaunch: Bool {
        get { defaults.bool(forKey: Key.startTrackingOnLaunch.rawValue) }
        set { set(newValue, .startTrackingOnLaunch) }
    }

    public var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin.rawValue) }
        set { set(newValue, .launchAtLogin) }
    }

    public var showInDockAndCmdTab: Bool {
        get { defaults.bool(forKey: Key.showInDockAndCmdTab.rawValue) }
        set { set(newValue, .showInDockAndCmdTab) }
    }

    public var showElapsedInMenuBar: Bool {
        get { defaults.bool(forKey: Key.showElapsedInMenuBar.rawValue) }
        set { set(newValue, .showElapsedInMenuBar) }
    }

    public var weekStart: Weekday {
        get { Weekday(rawValue: defaults.string(forKey: Key.weekStart.rawValue) ?? "") ?? .monday }
        set { set(newValue.rawValue, .weekStart) }
    }

    public var timeDisplayStyle: TimeStyle {
        get { TimeStyle(rawValue: defaults.string(forKey: Key.timeDisplayStyle.rawValue) ?? "") ?? .clock }
        set { set(newValue.rawValue, .timeDisplayStyle) }
    }

    public var pauseOnSleepAndLock: Bool {
        get { defaults.bool(forKey: Key.pauseOnSleepAndLock.rawValue) }
        set { set(newValue, .pauseOnSleepAndLock) }
    }

    /// Stop tracking after this long without a keystroke or a mouse move; 0 turns it off.
    public var idleTimeoutMinutes: Int {
        get { defaults.integer(forKey: Key.idleTimeoutMinutes.rawValue) }
        set { set(max(newValue, 0), .idleTimeoutMinutes) }
    }

    public var idleTimeout: Seconds? {
        let minutes = idleTimeoutMinutes
        return minutes > 0 ? minutes * 60 : nil
    }

    public static let idleTimeoutChoices = [0, 5, 10, 15, 30, 60]

    public var morningHour: Int {
        get { defaults.integer(forKey: Key.morningHour.rawValue) }
        set { set(min(max(newValue, 0), 23), .morningHour) }
    }

    public var maxGapSeconds: Int {
        get { defaults.integer(forKey: Key.maxGapSeconds.rawValue) }
        set { set(max(newValue, 2), .maxGapSeconds) }
    }

    public var csvDelimiter: Character {
        get { defaults.string(forKey: Key.csvDelimiter.rawValue)?.first ?? "," }
        set { set(String(newValue), .csvDelimiter) }
    }

    public var csvCellStyle: TimeStyle {
        get { TimeStyle(rawValue: defaults.string(forKey: Key.csvCellStyle.rawValue) ?? "") ?? .clock }
        set { set(newValue.rawValue, .csvCellStyle) }
    }

    public var csvIncludeTotals: Bool {
        get { defaults.bool(forKey: Key.csvIncludeTotals.rawValue) }
        set { set(newValue, .csvIncludeTotals) }
    }

    public var flushIntervalSeconds: Int {
        get { max(defaults.integer(forKey: Key.flushIntervalSeconds.rawValue), 1) }
        set { set(max(newValue, 1), .flushIntervalSeconds) }
    }

    public var passivePopupAutoHideSeconds: Int {
        get { defaults.integer(forKey: Key.passivePopupAutoHideSeconds.rawValue) }
        set { set(max(newValue, 0), .passivePopupAutoHideSeconds) }
    }

    public var csvOptions: CSVOptions {
        CSVOptions(delimiter: csvDelimiter, cellStyle: csvCellStyle, includeTotals: csvIncludeTotals)
    }

    private func set(_ value: Any, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
        broadcaster.send(key)
    }
}

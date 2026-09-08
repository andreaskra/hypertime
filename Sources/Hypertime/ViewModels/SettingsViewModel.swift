import Foundation
import HypertimeCore
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    private let model: AppModel

    var checkInIntervalMinutes: Int { didSet { settings.checkInIntervalMinutes = checkInIntervalMinutes } }
    var startTrackingOnLaunch: Bool { didSet { settings.startTrackingOnLaunch = startTrackingOnLaunch } }
    var pauseOnSleepAndLock: Bool { didSet { settings.pauseOnSleepAndLock = pauseOnSleepAndLock } }
    var morningHour: Int { didSet { settings.morningHour = morningHour } }
    var passiveAutoHide: Int { didSet { settings.passivePopupAutoHideSeconds = passiveAutoHide } }
    var timeDisplayStyle: TimeStyle { didSet { settings.timeDisplayStyle = timeDisplayStyle; onAppearanceChanged?() } }
    var showElapsedInMenuBar: Bool { didSet { settings.showElapsedInMenuBar = showElapsedInMenuBar; onAppearanceChanged?() } }
    var weekStart: Weekday { didSet { settings.weekStart = weekStart; onAppearanceChanged?() } }
    var showInDockAndCmdTab: Bool { didSet { settings.showInDockAndCmdTab = showInDockAndCmdTab; onActivationPolicyChanged?() } }
    var launchAtLogin: Bool { didSet { if launchAtLogin != LoginItemController.isEnabled { LoginItemController.setEnabled(launchAtLogin, settings: settings) } } }
    var csvDelimiterIsSemicolon: Bool { didSet { settings.csvDelimiter = csvDelimiterIsSemicolon ? ";" : "," } }
    var csvCellStyle: TimeStyle { didSet { settings.csvCellStyle = csvCellStyle } }
    var csvIncludeTotals: Bool { didSet { settings.csvIncludeTotals = csvIncludeTotals } }

    var onActivationPolicyChanged: (() -> Void)?
    var onAppearanceChanged: (() -> Void)?

    private var settings: Settings { model.settings }

    var loginItemNeedsApproval: Bool { LoginItemController.requiresApproval }
    var isInApplicationsFolder: Bool { LoginItemController.isInApplicationsFolder }
    var databasePath: String { model.store.path }
    /// Non-nil when this launch had to replace an unreadable database.
    var recoveredDatabasePath: String? { model.store.recoveredFromCorruption }

    init(model: AppModel) {
        self.model = model
        let settings = model.settings
        checkInIntervalMinutes = settings.checkInIntervalMinutes
        startTrackingOnLaunch = settings.startTrackingOnLaunch
        pauseOnSleepAndLock = settings.pauseOnSleepAndLock
        morningHour = settings.morningHour
        passiveAutoHide = settings.passivePopupAutoHideSeconds
        timeDisplayStyle = settings.timeDisplayStyle
        showElapsedInMenuBar = settings.showElapsedInMenuBar
        weekStart = settings.weekStart
        showInDockAndCmdTab = settings.showInDockAndCmdTab
        launchAtLogin = LoginItemController.isEnabled
        csvDelimiterIsSemicolon = settings.csvDelimiter == ";"
        csvCellStyle = settings.csvCellStyle
        csvIncludeTotals = settings.csvIncludeTotals
    }
}

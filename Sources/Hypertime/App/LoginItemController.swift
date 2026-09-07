import AppKit
import HypertimeCore
import ServiceManagement

/// Login item registration (R-16, §6.9). Only reliable when the app runs from /Applications.
@MainActor
enum LoginItemController {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool, settings: Settings) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            settings.launchAtLogin = enabled
        } catch {
            Log.app.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
            settings.launchAtLogin = isEnabled
        }
    }

    /// Applies the stored preference on launch, without fighting a user decision in System Settings.
    static func synchronise(settings: Settings) {
        let status = SMAppService.mainApp.status
        switch status {
        case .enabled:
            settings.launchAtLogin = true
        case .notRegistered where settings.launchAtLogin && isInApplicationsFolder:
            setEnabled(true, settings: settings)
        case .notRegistered where settings.launchAtLogin:
            Log.app.notice("Not registering the login item: the app is not in /Applications")
        case .requiresApproval:
            Log.app.notice("Login item needs approval in System Settings › General › Login Items")
        default:
            break
        }
    }

    static var isInApplicationsFolder: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications")
    }
}

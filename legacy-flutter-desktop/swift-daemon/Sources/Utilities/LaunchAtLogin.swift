import Foundation
import ServiceManagement

/// Login item management via SMAppService (macOS 13+).
enum LaunchAtLogin {
    static func setEnabled(_ enabled: Bool) {
        let service = SMAppService.mainApp

        do {
            if enabled {
                try service.register()
                ClawLogger.info("Registered as login item")
            } else {
                try service.unregister()
                ClawLogger.info("Unregistered as login item")
            }
        } catch {
            ClawLogger.error("Failed to \(enabled ? "register" : "unregister") login item: \(error)")
        }
    }

    static var isEnabled: Bool {
        return SMAppService.mainApp.status == .enabled
    }
}

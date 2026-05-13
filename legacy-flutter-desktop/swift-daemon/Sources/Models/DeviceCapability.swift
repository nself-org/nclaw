import AppKit
import Foundation

/// Capability report sent to the nself-claw server on WebSocket connect.
/// Server expects (ws.rs):
/// {"type":"capabilities","device_id":"<uuid>","actions":["file_op","shell"],"platform":"macos","version":"1.0"}
struct DeviceCapability: Codable {
    let type: String
    let device_id: String
    let actions: [String]
    let platform: String
    let version: String

    static func current() -> DeviceCapability {
        // T-1413: include "browser" capability only when user has enabled it
        var actions = ["file_op", "shell", "clipboard", "screenshot", "context_watch", "terminal", "audio", "sandbox_fs"]
        if UserDefaults.standard.bool(forKey: "NClaw_BrowserEnabled") {
            actions.append("browser")
        }
        return DeviceCapability(
            type: "capabilities",
            device_id: persistentDeviceId(),
            actions: actions,
            platform: "macos",
            version: "1.0"
        )
    }

    /// T-1413: Request user consent to enable Chrome browser automation.
    /// Shows a native alert. If approved, launches Chrome with CDP and stores consent.
    @MainActor
    static func requestBrowserConsent(completion: @escaping (Bool) -> Void) {
        // Only prompt once — if already answered, return stored value
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "NClaw_BrowserEnabled") != nil {
            completion(defaults.bool(forKey: "NClaw_BrowserEnabled"))
            return
        }

        let alert = NSAlert()
        alert.messageText = "Enable Browser Automation?"
        alert.informativeText = """
        nClaw wants to control your Chrome browser to help with web tasks.

        This will relaunch Chrome with remote debugging enabled on localhost:9222 (accessible to apps on this machine only).

        You can disable this at any time in nClaw settings.
        """
        alert.addButton(withTitle: "Enable")
        alert.addButton(withTitle: "Not Now")
        alert.alertStyle = .informational

        let response = alert.runModal()
        let enabled = response == .alertFirstButtonReturn

        defaults.set(enabled, forKey: "NClaw_BrowserEnabled")

        if enabled {
            // Relaunch Chrome with CDP port
            let chromePath = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
            if FileManager.default.fileExists(atPath: chromePath) {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: chromePath)
                task.arguments = ["--remote-debugging-port=9222"]
                try? task.run()
            }
        }

        completion(enabled)
    }

    /// Returns a stable UUID for this device, persisted in UserDefaults.
    private static func persistentDeviceId() -> String {
        let key = "nclawDeviceId"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let new = UUID().uuidString.lowercased()
        UserDefaults.standard.set(new, forKey: key)
        return new
    }
}

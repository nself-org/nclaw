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
        return DeviceCapability(
            type: "capabilities",
            device_id: persistentDeviceId(),
            // T-1351: added context_watch (editor file), terminal (shell buffer)
            actions: ["file_op", "shell", "clipboard", "screenshot", "context_watch", "terminal"],
            platform: "macos",
            version: "1.0"
        )
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

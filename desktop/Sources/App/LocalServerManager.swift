import SwiftUI

/// Manages the local HTTP server lifecycle.
/// Observable so the UI can show running state.
///
/// Port 7432 is the canonical companion daemon port (T-1351).
/// The previous default (7710) is retained as a fallback for user overrides.
@MainActor
final class LocalServerManager: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var port: Int = 7432

    private var server: LocalHTTPServer?

    /// The device token is stored in Keychain and sent as X-Device-Token on all requests.
    /// Generated on first pair, persisted across restarts.
    var deviceToken: String? {
        KeychainHelper.load(key: "nclaw-device-token")
    }

    init() {
        let savedPort = UserDefaults.standard.integer(forKey: "httpPort")
        // Default to 7432 (T-1351 canonical port); respect user override if set
        self.port = savedPort > 0 ? savedPort : 7432
        startServer()
    }

    func startServer() {
        guard !isRunning else { return }

        let token = KeychainHelper.load(key: "nclaw-http-token")
        let httpServer = LocalHTTPServer(port: UInt16(port), token: token)

        do {
            try httpServer.start()
            self.server = httpServer
            self.isRunning = true
        } catch {
            ClawLogger.error("Failed to start HTTP server: \(error)")
            self.isRunning = false
        }
    }

    func stopServer() {
        server?.stop()
        server = nil
        isRunning = false
    }

    func restart() {
        stopServer()
        let savedPort = UserDefaults.standard.integer(forKey: "httpPort")
        self.port = savedPort > 0 ? savedPort : 7432
        startServer()
    }

    /// Store the device token received during pairing.
    func saveDeviceToken(_ token: String) {
        _ = KeychainHelper.save(key: "nclaw-device-token", value: token)
    }
}

import Foundation
import NClaw
#if canImport(UIKit)
import UIKit
#endif

final class ClawClient: NSObject, URLSessionWebSocketDelegate {
    private static let serverURLKey = "nclaw_server_url"
    private static let apiKeyKey = "nclaw_api_key"
    private static let keychainService = "org.nself.nclaw"

    static var serverURL: String {
        get { UserDefaults.standard.string(forKey: serverURLKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: serverURLKey) }
    }

    /// API key stored in iOS Keychain for security (not UserDefaults).
    static var apiKey: String {
        get {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: apiKeyKey,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            guard status == errSecSuccess, let data = result as? Data,
                  let key = String(data: data, encoding: .utf8) else {
                // Fallback to UserDefaults for migration from old storage
                return UserDefaults.standard.string(forKey: apiKeyKey) ?? ""
            }
            return key
        }
        set {
            // Delete existing entry first
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: apiKeyKey
            ]
            SecItemDelete(deleteQuery as CFDictionary)

            guard !newValue.isEmpty, let data = newValue.data(using: .utf8) else { return }
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: apiKeyKey,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
            ]
            SecItemAdd(addQuery as CFDictionary, nil)

            // Also keep in UserDefaults for backwards compat
            UserDefaults.standard.set(newValue, forKey: apiKeyKey)
        }
    }
    
    private var clawInstance: NClaw?
    private var lastURL: String = ""
    private var lastKey: String = ""
    private var webSocketTask: URLSessionWebSocketTask?

    // Default device ID (in a real app, store this in Keychain after pairing)
    private var deviceId = UUID().uuidString

    // T-2178: Sensor streaming state
    private var sensorStreamingTimer: Timer?
    private var sensorStreamingEnabled = false

    override init() {
        super.init()
    }

    func connectWebSocketIfNeeded() {
        let baseURL = ClawClient.serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !baseURL.isEmpty, let url = URL(string: "\(baseURL)/claw/ws?device_id=\(deviceId)&last_seq=0") else { return }
        
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        var request = URLRequest(url: url)
        request.setValue(ClawClient.apiKey, forHTTPHeaderField: "Authorization")
        
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        receiveMessage()
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .failure(let error):
                print("WebSocket error: \(error)")
            case .success(let message):
                switch message {
                case .string(let text):
                    print("WebSocket received: \(text)")
                case .data(let data):
                    print("WebSocket received data: \(data)")
                @unknown default:
                    break
                }
                self?.receiveMessage()
            }
        }
    }

    func registerCapabilities() {
        let payload: [String: Any] = [
            "type": "capabilities",
            "device_id": deviceId,
            "actions": ["clipboard_read", "clipboard_write", "location", "sensor_streaming"],
            "platform": "ios",
            "version": "1.0"
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let jsonString = String(data: data, encoding: .utf8) {
            let message = URLSessionWebSocketTask.Message.string(jsonString)
            webSocketTask?.send(message) { error in
                if let error = error {
                    print("Failed to send capabilities: \(error)")
                }
            }
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("WebSocket connected")
        registerCapabilities()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("WebSocket disconnected")
    }

    func sendMessage(_ text: String) async throws -> String {
        let currentURL = ClawClient.serverURL
        let currentKey = ClawClient.apiKey
        
        let baseURL = currentURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !baseURL.isEmpty else {
            throw ClawError.invalidURL
        }
        
        if clawInstance == nil || lastURL != baseURL || lastKey != currentKey {
            clawInstance?.disconnect()
            clawInstance = try NClaw(serverURL: baseURL, apiKey: currentKey)
            lastURL = baseURL
            lastKey = currentKey
            connectWebSocketIfNeeded()
        }
        
        guard let claw = clawInstance else {
            throw ClawError.connectionFailed
        }
        
        do {
            return try await claw.sendMessage(text)
        } catch let error as NClawError {
            throw error
        } catch {
            throw ClawError.serverError(statusCode: 500, message: error.localizedDescription)
        }
    }

    // =========================================================================
    // T-2178: Sensor streaming scaffold
    // =========================================================================

    /// Start streaming mobile sensor data to the server.
    /// Reports battery level, GPS coordinates, and activity detection
    /// at the configured interval. Data is sent as interactions with
    /// channel="mobile_sensor" to np_claw_interactions.
    ///
    /// - Parameter interval: Reporting interval in seconds (default 60).
    func startSensorStreaming(interval: TimeInterval = 60.0) {
        guard !sensorStreamingEnabled else { return }
        sensorStreamingEnabled = true

        sensorStreamingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.sendSensorReport()
        }
        // Fire immediately on start
        sendSensorReport()
        print("Sensor streaming started (interval=\(interval)s)")
    }

    /// Stop sensor streaming.
    func stopSensorStreaming() {
        sensorStreamingEnabled = false
        sensorStreamingTimer?.invalidate()
        sensorStreamingTimer = nil
        print("Sensor streaming stopped")
    }

    /// Collect current sensor data and send as a WebSocket message.
    /// Uses channel="mobile_sensor" for server-side routing to
    /// np_claw_interactions table.
    private func sendSensorReport() {
        guard let ws = webSocketTask else { return }

        var sensorData: [String: Any] = [
            "type": "sensor_report",
            "channel": "mobile_sensor",
            "device_id": deviceId,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ]

        // Battery level
        sensorData["battery"] = collectBatteryData()

        // GPS location (last known)
        sensorData["location"] = collectLocationData()

        // Activity detection
        sensorData["activity"] = collectActivityData()

        if let data = try? JSONSerialization.data(withJSONObject: sensorData),
           let jsonString = String(data: data, encoding: .utf8) {
            let message = URLSessionWebSocketTask.Message.string(jsonString)
            ws.send(message) { error in
                if let error = error {
                    print("Failed to send sensor report: \(error)")
                }
            }
        }
    }

    /// Collect battery level and charging state.
    /// Uses UIDevice battery monitoring (must be enabled).
    private func collectBatteryData() -> [String: Any] {
        #if canImport(UIKit)
        let device = UIDevice.current
        let wasMonitoring = device.isBatteryMonitoringEnabled
        device.isBatteryMonitoringEnabled = true

        let level = Int(device.batteryLevel * 100)
        let charging = device.batteryState == .charging || device.batteryState == .full

        if !wasMonitoring {
            device.isBatteryMonitoringEnabled = false
        }

        return [
            "level": level >= 0 ? level : -1,
            "charging": charging
        ]
        #else
        // macOS: battery info via IOKit (scaffold only)
        return [
            "level": -1,
            "charging": false,
            "note": "macOS battery monitoring not yet implemented"
        ]
        #endif
    }

    /// Collect last known GPS coordinates.
    /// Returns empty coordinates if location permission is not granted.
    /// The caller (ViewController) is responsible for requesting
    /// location permission via CLLocationManager.
    private func collectLocationData() -> [String: Any] {
        // CLLocationManager requires the calling code to have requested
        // authorization. This scaffold returns a placeholder; the UI
        // layer should pass location updates to this client.
        return [
            "available": false,
            "reason": "location_delegate_not_connected",
            "note": "Connect CLLocationManager delegate to provide live GPS"
        ]
    }

    /// Collect user activity detection state.
    /// Scaffold: returns "unknown" until CMMotionActivityManager is integrated.
    /// Requires CoreMotion framework and NSMotionUsageDescription in Info.plist.
    private func collectActivityData() -> [String: Any] {
        return [
            "type": "unknown",
            "confidence": 0,
            "note": "CMMotionActivityManager integration pending"
        ]
    }

    /// Disconnect and clean up all resources including sensor streaming.
    func disconnect() {
        stopSensorStreaming()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        clawInstance?.disconnect()
        clawInstance = nil
    }
}

enum ClawError: LocalizedError {
    case invalidURL
    case connectionFailed
    case serverError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL. Check your settings."
        case .connectionFailed:
            return "Failed to initialize the FFI connection."
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        }
    }
}

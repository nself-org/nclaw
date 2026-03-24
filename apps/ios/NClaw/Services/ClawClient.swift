import Foundation
import AuthenticationServices
import NClaw
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif

// MARK: - T-2738: OAuth PKCE Auth + ClawClient

final class ClawClient: NSObject, URLSessionWebSocketDelegate {
    private static let serverURLKey = "nclaw_server_url"
    private static let keychainService = "org.nself.nclaw"
    private static let accessTokenKey = "nclaw_access_token"
    private static let refreshTokenKey = "nclaw_refresh_token"

    // Legacy API key — kept for migration; new installs use OAuth tokens.
    private static let apiKeyKey = "nclaw_api_key"

    static var serverURL: String {
        get { UserDefaults.standard.string(forKey: serverURLKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: serverURLKey) }
    }

    /// Auth base URL derived from the server URL (e.g. https://api.example.com → auth lives there).
    /// Override with AUTH_URL UserDefault if auth endpoint differs from the API.
    static var authURL: String {
        if let override_ = UserDefaults.standard.string(forKey: "nclaw_auth_url"), !override_.isEmpty {
            return override_.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    // MARK: - Keychain helpers (generic)

    private static func keychainSave(key: String, value: String) {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func keychainLoad(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func keychainDelete(key: String) {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)
    }

    // MARK: - Token storage

    static var accessToken: String? {
        get { keychainLoad(key: accessTokenKey) }
        set {
            if let v = newValue { keychainSave(key: accessTokenKey, value: v) }
            else { keychainDelete(key: accessTokenKey) }
        }
    }

    static var refreshToken: String? {
        get { keychainLoad(key: refreshTokenKey) }
        set {
            if let v = newValue { keychainSave(key: refreshTokenKey, value: v) }
            else { keychainDelete(key: refreshTokenKey) }
        }
    }

    /// Legacy API key for backward compatibility. New installs use OAuth tokens.
    static var apiKey: String {
        get { keychainLoad(key: apiKeyKey) ?? UserDefaults.standard.string(forKey: apiKeyKey) ?? "" }
        set {
            keychainSave(key: apiKeyKey, value: newValue)
            UserDefaults.standard.set(newValue, forKey: apiKeyKey)
        }
    }

    /// Returns true if the user has a valid access token or legacy API key.
    static var isAuthenticated: Bool {
        (accessToken != nil && !(accessToken?.isEmpty ?? true)) || !apiKey.isEmpty
    }

    /// The Bearer token to use for API requests. Prefers OAuth access token over legacy API key.
    static var bearerToken: String {
        if let token = accessToken, !token.isEmpty { return token }
        return apiKey
    }

    // MARK: - PKCE helpers

    private var codeVerifier: String?

    /// Generate a cryptographic code verifier (43-128 URL-safe characters).
    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Derive S256 code challenge from the verifier.
    private func codeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - OAuth PKCE flow (T-2738)

    /// Start the OAuth PKCE authorization flow via ASWebAuthenticationSession.
    /// Presents the system browser auth sheet, then exchanges the code for tokens.
    @MainActor
    func authenticate(from anchor: ASPresentationAnchor? = nil) async throws {
        let verifier = generateCodeVerifier()
        self.codeVerifier = verifier
        let challenge = codeChallenge(from: verifier)

        let baseAuth = ClawClient.authURL
        let redirectURI = "nclaw://callback"
        let encodedRedirect = redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectURI

        guard let authorizationURL = URL(string:
            "\(baseAuth)/signin?redirect_uri=\(encodedRedirect)&code_challenge=\(challenge)&code_challenge_method=S256"
        ) else {
            throw ClawError.invalidURL
        }

        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: authorizationURL,
                callbackURLScheme: "nclaw"
            ) { url, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let url = url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: ClawError.connectionFailed)
                }
            }
            session.prefersEphemeralWebBrowserSession = false
            if let anchor = anchor {
                session.presentationContextProvider = PresentationContextProvider(anchor: anchor)
            }
            session.start()
        }

        // Extract the authorization code from the callback URL
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else {
            throw ClawError.serverError(statusCode: 400, message: "No authorization code in callback URL")
        }

        // Exchange the code for tokens
        try await exchangeCodeForTokens(code: code, verifier: verifier)
    }

    /// Exchange the authorization code for access + refresh tokens.
    private func exchangeCodeForTokens(code: String, verifier: String) async throws {
        let tokenURL = "\(ClawClient.authURL)/token"
        guard let url = URL(string: tokenURL) else { throw ClawError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": "nclaw://callback"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClawError.connectionFailed
        }

        guard httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Token exchange failed"
            throw ClawError.serverError(statusCode: httpResponse.statusCode, message: message)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClawError.serverError(statusCode: 500, message: "Invalid token response")
        }

        guard let accessToken = json["access_token"] as? String, !accessToken.isEmpty else {
            throw ClawError.serverError(statusCode: 500, message: "No access_token in response")
        }

        ClawClient.accessToken = accessToken
        if let refreshToken = json["refresh_token"] as? String, !refreshToken.isEmpty {
            ClawClient.refreshToken = refreshToken
        }
    }

    /// Attempt to refresh the access token using the stored refresh token.
    /// Returns true if refresh succeeded, false if re-authentication is needed.
    func refreshAccessToken() async -> Bool {
        guard let refreshToken = ClawClient.refreshToken, !refreshToken.isEmpty else {
            return false
        }

        let tokenURL = "\(ClawClient.authURL)/token"
        guard let url = URL(string: tokenURL) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccessToken = json["access_token"] as? String, !newAccessToken.isEmpty else {
            // Refresh failed — clear tokens so user must re-authenticate
            ClawClient.accessToken = nil
            ClawClient.refreshToken = nil
            return false
        }

        ClawClient.accessToken = newAccessToken
        if let newRefreshToken = json["refresh_token"] as? String, !newRefreshToken.isEmpty {
            ClawClient.refreshToken = newRefreshToken
        }
        return true
    }

    /// Clear all stored credentials (logout).
    static func logout() {
        accessToken = nil
        refreshToken = nil
        apiKey = ""
        keychainDelete(key: accessTokenKey)
        keychainDelete(key: refreshTokenKey)
        keychainDelete(key: apiKeyKey)
    }

    // MARK: - Instance state

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
        request.setValue("Bearer \(ClawClient.bearerToken)", forHTTPHeaderField: "Authorization")

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
        let currentToken = ClawClient.bearerToken

        let baseURL = currentURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !baseURL.isEmpty else {
            throw ClawError.invalidURL
        }

        if clawInstance == nil || lastURL != baseURL || lastKey != currentToken {
            clawInstance?.disconnect()
            clawInstance = try NClaw(serverURL: baseURL, apiKey: currentToken)
            lastURL = baseURL
            lastKey = currentToken
            connectWebSocketIfNeeded()
        }

        guard let claw = clawInstance else {
            throw ClawError.connectionFailed
        }

        do {
            return try await claw.sendMessage(text)
        } catch let error as NClawError {
            // T-2738: On 401, attempt token refresh then retry once
            if case .serverError(let code, _) = ClawError.from(error), code == 401 {
                let refreshed = await refreshAccessToken()
                if refreshed {
                    // Reconnect with new token
                    clawInstance?.disconnect()
                    let newToken = ClawClient.bearerToken
                    clawInstance = try NClaw(serverURL: baseURL, apiKey: newToken)
                    lastKey = newToken
                    connectWebSocketIfNeeded()
                    return try await clawInstance!.sendMessage(text)
                }
            }
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

// MARK: - ASWebAuthenticationSession presentation context

private final class PresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    let anchor: ASPresentationAnchor

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return anchor
    }
}

// MARK: - Error types

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

    /// Map from NClawError to ClawError (best effort).
    static func from(_ error: NClawError) -> ClawError {
        return .serverError(statusCode: 500, message: error.localizedDescription)
    }
}

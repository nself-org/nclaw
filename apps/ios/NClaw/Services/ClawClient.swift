import Foundation
import NClaw

final class ClawClient: NSObject, URLSessionWebSocketDelegate {
    private static let serverURLKey = "nclaw_server_url"
    private static let apiKeyKey = "nclaw_api_key"

    static var serverURL: String {
        get { UserDefaults.standard.string(forKey: serverURLKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: serverURLKey) }
    }

    static var apiKey: String {
        get { UserDefaults.standard.string(forKey: apiKeyKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: apiKeyKey) }
    }
    
    private var clawInstance: NClaw?
    private var lastURL: String = ""
    private var lastKey: String = ""
    private var webSocketTask: URLSessionWebSocketTask?
    
    // Default device ID (in a real app, store this in Keychain after pairing)
    private var deviceId = UUID().uuidString

    override init() {
        super.init()
    }

    func connectWebSocketIfNeeded() {
        let baseURL = ClawClient.serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !baseURL.isEmpty, let url = URL(string: "\(baseURL)/claw/ws?user_id=ios_user&last_seq=0") else { return }
        
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
            "actions": ["clipboard_read", "clipboard_write", "location"],
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

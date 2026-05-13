import Network
import Foundation

/// WebSocket client to the nself-claw server.
/// Uses NWConnection + NWProtocolWebSocket (Network.framework) with explicit
/// HTTP/1.1 ALPN to avoid the HTTP/2 WebSocket (RFC 8441) path that
/// URLSessionWebSocketTask attempts — Cloudflare returns 301 for that path.
final class ClawWebSocket {
    private var connection: NWConnection?
    private var reconnector: Reconnect?
    private let urlString: String
    private let onStateChange: (ConnectionState) -> Void
    private let onAction: (Action) -> Void
    private let connectionQueue = DispatchQueue(label: "org.nself.nclaw.ws", qos: .utility)

    init(url: String, onStateChange: @escaping (ConnectionState) -> Void, onAction: @escaping (Action) -> Void) {
        self.urlString = url
        self.onStateChange = onStateChange
        self.onAction = onAction
        self.reconnector = Reconnect { [weak self] in self?.attemptConnect() }
    }

    func connect() {
        attemptConnect()
    }

    func disconnect() {
        reconnector?.stop()
        connection?.cancel()
        connection = nil
        onStateChange(.disconnected)
    }

    func send(_ message: some Encodable) {
        guard let data = try? JSONEncoder().encode(message) else {
            ClawLogger.error("Failed to encode WebSocket message")
            return
        }
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        let ctx = NWConnection.ContentContext(identifier: "ws-text", metadata: [meta])
        connection?.send(content: data, contentContext: ctx, isComplete: true, completion: .idempotent)
    }

    /// Send a plain [String: String] dictionary as a JSON WebSocket message.
    func sendDict(_ dict: [String: String]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else {
            ClawLogger.error("Failed to encode WebSocket dict message")
            return
        }
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        let ctx = NWConnection.ContentContext(identifier: "ws-text", metadata: [meta])
        connection?.send(content: data, contentContext: ctx, isComplete: true, completion: .idempotent)
    }

    // MARK: - Private

    private func attemptConnect() {
        fputs("[nClaw] attemptConnect (NW): \(urlString)\n", stderr)
        guard let url = URL(string: urlString) else {
            fputs("[nClaw] invalid URL\n", stderr)
            ClawLogger.error("Invalid WebSocket URL: \(urlString)")
            return
        }

        onStateChange(.connecting)

        // TLS with explicit http/1.1 ALPN — prevents HTTP/2 negotiation.
        // Cloudflare returns 301 when URLSessionWebSocketTask tries RFC 8441
        // WebSocket-over-HTTP/2. Forcing http/1.1 in ALPN guarantees the
        // standard HTTP/1.1 Upgrade handshake that CF proxies correctly.
        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_add_tls_application_protocol(
            tlsOptions.securityProtocolOptions, "http/1.1"
        )

        let parameters = NWParameters(tls: tlsOptions)

        // WebSocket protocol framing
        let wsOptions = NWProtocolWebSocket.Options(.version13)
        wsOptions.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        // NWEndpoint.url carries the full path + query into the WS handshake
        let conn = NWConnection(to: NWEndpoint.url(url), using: parameters)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            fputs("[nClaw] NW state: \(state)\n", stderr)
            switch state {
            case .ready:
                ClawLogger.info("WebSocket connected")
                self.reconnector?.reset()
                self.onStateChange(.connected)
                let caps = DeviceCapability.current()
                self.send(caps)
                self.receiveMessage()
            case .failed(let error):
                fputs("[nClaw] NW failed: \(error)\n", stderr)
                ClawLogger.error("WebSocket connection failed: \(error)")
                self.connection?.cancel()
                self.connection = nil
                self.onStateChange(.disconnected)
                self.reconnector?.scheduleRetry()
            case .cancelled:
                self.onStateChange(.disconnected)
            default:
                break
            }
        }

        conn.start(queue: connectionQueue)
    }

    private func receiveMessage() {
        connection?.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }

            if let error {
                fputs("[nClaw] NW receive error: \(error)\n", stderr)
                ClawLogger.error("WebSocket receive error: \(error)")
                self.connection?.cancel()
                self.connection = nil
                self.onStateChange(.disconnected)
                self.reconnector?.scheduleRetry()
                return
            }

            if let data, !data.isEmpty {
                self.handleData(data)
            }

            self.receiveMessage() // Continue listening
        }
    }

    private func handleData(_ data: Data) {
        let raw = String(data: data.prefix(500), encoding: .utf8) ?? "<binary>"
        fputs("[nClaw] raw msg: \(raw)\n", stderr)
        do {
            let msg = try JSONDecoder().decode(ServerMessage.self, from: data)
            fputs("[nClaw] server msg type=\(msg.type) payload=\(msg.payload != nil ? "present" : "nil")\n", stderr)
            if msg.type == "action" {
                if let action = msg.payload?.action {
                    fputs("[nClaw] dispatching action \(action.id) type=\(action.action_type)\n", stderr)
                    onAction(action)
                } else {
                    fputs("[nClaw] action msg has nil payload.action — decode failed\n", stderr)
                }
            }
        } catch {
            fputs("[nClaw] failed to decode server msg: \(raw)\nError: \(error)\n", stderr)
            ClawLogger.error("Failed to decode server message: \(error)")
        }
    }
}

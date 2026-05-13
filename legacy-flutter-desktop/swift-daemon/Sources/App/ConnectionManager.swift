import SwiftUI
import Combine

enum ConnectionState: String {
    case disconnected
    case connecting
    case connected

    var displayName: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        }
    }
}

@MainActor
final class ConnectionManager: ObservableObject {
    @Published var state: ConnectionState = .disconnected
    @Published var config: ServerConfig
    /// T-1352: The path of the file currently being watched. Shown in claw-web chat header.
    @Published var watchingFile: String? = nil

    private var webSocket: ClawWebSocket?
    private var actionHandler: ActionHandler?
    // T-1352: Active file watcher
    private let fileWatcher = ActiveFileWatcher()
    // T-1354: Clipboard change watcher
    private let clipboardWatcher = ClipboardWatcher()
    // T-2726: Ambient OS context streamer
    private let ambientContext = AmbientContextService()

    var statusColor: Color {
        switch state {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .red
        }
    }

    var statusIcon: String {
        switch state {
        case .connected: return "brain.head.profile"
        case .connecting: return "brain.head.profile"
        case .disconnected: return "brain.head.profile"
        }
    }

    init() {
        let savedURL = UserDefaults.standard.string(forKey: "serverURL") ?? "wss://api.nself.org/claw/ws"
        let savedPort = UserDefaults.standard.integer(forKey: "httpPort")
        self.config = ServerConfig(
            serverURL: savedURL,
            port: savedPort > 0 ? savedPort : 7710
        )
        fputs("[nClaw] init: url=\(savedURL)\n", stderr)
        // Auto-connect on startup. Use detached task to avoid @MainActor deadlock
        // during init, then dispatch back to main after the run loop is active.
        Task.detached { [weak self] in
            fputs("[nClaw] task.detached: sleeping 1s\n", stderr)
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s — let NSApp finish launching
            fputs("[nClaw] task.detached: calling connect\n", stderr)
            await MainActor.run { self?.connect() }
        }
    }

    func connect() {
        fputs("[nClaw] connect() called, state=\(state.rawValue)\n", stderr)
        guard state == .disconnected else { return }
        state = .connecting

        let handler = ActionHandler()
        self.actionHandler = handler

        let ws = ClawWebSocket(
            url: config.serverURL,
            onStateChange: { [weak self] newState in
                Task { @MainActor in
                    self?.state = newState
                    if newState == .connected {
                        self?.startWatchers()
                    } else if newState == .disconnected {
                        self?.stopWatchers()
                    }
                }
            },
            onAction: { [weak self] action in
                Task { @MainActor in
                    self?.actionHandler?.handle(action)
                }
            }
        )
        self.webSocket = ws
        ws.connect()
    }

    func disconnect() {
        stopWatchers()
        webSocket?.disconnect()
        webSocket = nil
        actionHandler = nil
        state = .disconnected
    }

    // MARK: - Watchers (T-1352, T-1354)

    private func startWatchers() {
        // T-1352: Active file context watcher
        fileWatcher.start { [weak self] msg in
            Task { @MainActor in
                self?.watchingFile = msg.file
                self?.webSocket?.send(msg)
            }
        }

        // T-1354: Clipboard watcher
        clipboardWatcher.start { [weak self] event in
            Task { @MainActor in
                let msg: [String: String] = [
                    "type": "clipboard_update",
                    "content_type": event.contentType,
                    "preview": event.preview
                ]
                self?.webSocket?.sendDict(msg)
            }
        }

        // T-2726: Ambient OS context streamer (active app + window + clipboard preview)
        ambientContext.start { [weak self] msg in
            Task { @MainActor in
                self?.webSocket?.send(msg)
            }
        }
    }

    private func stopWatchers() {
        fileWatcher.stop()
        clipboardWatcher.stop()
        ambientContext.stop()
        watchingFile = nil
    }

    /// Called after onboarding completes. Reloads the saved server URL
    /// from UserDefaults and opens a fresh WebSocket connection.
    func reconnectWithSavedCredentials() {
        disconnect()
        let savedURL = UserDefaults.standard.string(forKey: "serverURL") ?? config.serverURL
        config = ServerConfig(serverURL: savedURL, port: config.port)
        connect()
    }
}

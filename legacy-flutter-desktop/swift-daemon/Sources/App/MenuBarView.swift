import SwiftUI

struct MenuBarView: View {
    @ObservedObject var connectionManager: ConnectionManager
    @ObservedObject var serverManager: LocalServerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("\u{0273}Claw")
                    .font(.headline)
                Spacer()
                statusBadge
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Divider()

            // Connection status
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text("Server: \(connectionManager.config.serverURL)")
                        .font(.caption)
                        .lineLimit(1)
                } icon: {
                    Circle()
                        .fill(connectionManager.statusColor)
                        .frame(width: 8, height: 8)
                }

                Label {
                    Text("Local HTTP: \(serverManager.isRunning ? "Active" : "Stopped") on :\(serverManager.port)")
                        .font(.caption)
                } icon: {
                    Circle()
                        .fill(serverManager.isRunning ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 12)

            Divider()

            // Actions
            VStack(alignment: .leading, spacing: 2) {
                if connectionManager.state == .disconnected {
                    Button("Connect") {
                        connectionManager.connect()
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                } else if connectionManager.state == .connected {
                    Button("Disconnect") {
                        connectionManager.disconnect()
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }

                Button("Settings...") {
                    openSettings()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .keyboardShortcut(",", modifiers: .command)
            }

            Divider()

            Button("Quit \u{0273}Claw") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.bottom, 8)
        .frame(width: 280)
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(connectionManager.statusColor)
                .frame(width: 8, height: 8)
            Text(connectionManager.state.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func openSettings() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

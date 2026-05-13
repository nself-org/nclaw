import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var connectionManager: ConnectionManager
    @ObservedObject var serverManager: LocalServerManager

    @AppStorage("serverURL") private var serverURL: String = "wss://api.nself.org/claw/ws"
    @AppStorage("httpPort") private var httpPort: Int = 7710
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true
    @AppStorage("sandboxPaths") private var sandboxPathsRaw: String = ""

    @State private var editingToken: String = ""
    @State private var tokenSaveStatus: String?
    @State private var showDisconnectConfirm: Bool = false

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            serverTab
                .tabItem {
                    Label("Server", systemImage: "network")
                }

            securityTab
                .tabItem {
                    Label("Security", systemImage: "lock.shield")
                }
        }
        .frame(width: 480, height: 360)
        .onAppear {
            loadToken()
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        LaunchAtLogin.setEnabled(newValue)
                    }

                Toggle("Show notifications", isOn: $notificationsEnabled)
            }

            Section("Local HTTP Server") {
                HStack {
                    Text("Port:")
                    TextField("Port", value: $httpPort, format: .number)
                        .frame(width: 80)
                    Text("(requires restart)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Server Tab

    private var serverTab: some View {
        Form {
            Section("nClaw Server") {
                TextField("WebSocket URL", text: $serverURL)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Text("Status:")
                    Circle()
                        .fill(connectionManager.statusColor)
                        .frame(width: 8, height: 8)
                    Text(connectionManager.state.displayName)
                }

                HStack {
                    Button("Connect") {
                        connectionManager.config = ServerConfig(
                            serverURL: serverURL,
                            port: httpPort
                        )
                        connectionManager.connect()
                    }
                    .disabled(connectionManager.state == .connected)

                    Button("Disconnect") {
                        connectionManager.disconnect()
                    }
                    .disabled(connectionManager.state == .disconnected)
                }
            }

            Section("Authentication") {
                SecureField("JWT Token", text: $editingToken)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Save to Keychain") {
                        saveToken()
                    }

                    if let status = tokenSaveStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Security Tab

    private var securityTab: some View {
        Form {
            Section("Authentication") {
                HStack {
                    Text("Token:")
                        .foregroundStyle(.secondary)
                    Text(maskedToken)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Button(role: .destructive) {
                    showDisconnectConfirm = true
                } label: {
                    Label("Disconnect & unpair", systemImage: "eject.circle")
                }
                .confirmationDialog(
                    "Disconnect and unpair this device?",
                    isPresented: $showDisconnectConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Disconnect & unpair", role: .destructive) {
                        unpair()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will remove your saved credentials. You will need to pair again to reconnect.")
                }
            }

            Section("File Access Sandbox") {
                Text("Allowed directories (one per line):")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $sandboxPathsRaw)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 100)
                    .border(Color.secondary.opacity(0.3))

                Text("File operations are restricted to these paths. Leave empty to use ~/Documents only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Shell Execution") {
                Text("Shell commands from the server always require explicit user approval via a system dialog before execution.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var maskedToken: String {
        let token = KeychainHelper.load(key: "nclaw-jwt-token") ?? ""
        if token.isEmpty { return "(no token stored)" }
        let prefix = String(token.prefix(20))
        return prefix + "..."
    }

    private func unpair() {
        connectionManager.disconnect()
        _ = KeychainHelper.delete(key: "nclaw-jwt-token")
        UserDefaults.standard.removeObject(forKey: "serverURL")
        editingToken = ""

        // Open the onboarding window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            openOnboarding()
        }
    }

    private func openOnboarding() {
        // Close the settings window first
        NSApplication.shared.windows
            .first { $0.title.lowercased().contains("settings") || $0.title.lowercased().contains("preferences") }?
            .close()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 440),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Setup \u{0273}Claw"
        window.center()
        window.isReleasedWhenClosed = false

        let contentView = OnboardingView {
            window.close()
            connectionManager.reconnectWithSavedCredentials()
        }
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Helpers

    private func loadToken() {
        if let token = KeychainHelper.load(key: "nclaw-jwt-token") {
            editingToken = token
        }
    }

    private func saveToken() {
        let success = KeychainHelper.save(key: "nclaw-jwt-token", value: editingToken)
        tokenSaveStatus = success ? "Saved" : "Failed"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            tokenSaveStatus = nil
        }
    }
}

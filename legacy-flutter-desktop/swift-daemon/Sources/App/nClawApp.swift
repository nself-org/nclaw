import SwiftUI
import AuthenticationServices

@main
struct nClawApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var connectionManager = ConnectionManager()
    @StateObject private var serverManager = LocalServerManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                connectionManager: connectionManager,
                serverManager: serverManager
            )
            .task { connectionManager.connect() }
        } label: {
            Image(systemName: connectionManager.statusIcon)
                .symbolRenderingMode(.palette)
                .foregroundStyle(connectionManager.statusColor)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                connectionManager: connectionManager,
                serverManager: serverManager
            )
        }

        // Onboarding window — shown on first launch when no JWT is found.
        // Displayed as a floating panel via openWindow(id:) from AppDelegate.
        WindowGroup("Setup \u{0273}Claw", id: "onboarding") {
            OnboardingView {
                // Dismiss the onboarding window and reconnect with the new credentials.
                NSApplication.shared.windows
                    .first { $0.title.hasPrefix("Setup") }?
                    .close()
                connectionManager.reconnectWithSavedCredentials()
            }
            .frame(width: 460, height: 460)
            // T-1371: Also reconnect when credentials arrive via nclaw:// URL scheme.
            .onReceive(NotificationCenter.default.publisher(for: .nClawCredentialsUpdated)) { _ in
                connectionManager.reconnectWithSavedCredentials()
            }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ClawLogger.info("nClaw daemon started")

        // Register the nclaw:// custom URL scheme handler (T-1371).
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        // Show onboarding if no JWT exists in Keychain.
        if KeychainHelper.load(key: "nclaw-jwt-token") == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.openOnboardingWindow()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClawLogger.info("nClaw daemon shutting down")
    }

    // MARK: - nclaw:// URL scheme handler (T-1371)

    /// Handles nclaw://auth?token={jwt} callbacks from ASWebAuthenticationSession.
    ///
    /// Extracts the JWT, stores it in Keychain as NClaw_JWT, then closes any open
    /// onboarding window and reconnects with the new credentials.
    @objc private func handleGetURLEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent _: NSAppleEventDescriptor
    ) {
        guard
            let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
            let url = URL(string: urlString),
            url.scheme == "nclaw",
            url.host == "auth",
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
            !token.isEmpty
        else {
            ClawLogger.error("nclaw:// callback received but token missing or URL malformed")
            return
        }

        ClawLogger.info("nclaw:// auth callback received — storing JWT")
        _ = KeychainHelper.save(key: "NClaw_JWT", value: token)
        // Also store under the legacy key so ConnectionManager picks it up.
        _ = KeychainHelper.save(key: "nclaw-jwt-token", value: token)

        DispatchQueue.main.async {
            // Close any open onboarding window.
            NSApplication.shared.windows
                .first { $0.title.hasPrefix("Setup") }?
                .close()

            // Reconnect with the new token.
            // Post a notification that ConnectionManager observes.
            NotificationCenter.default.post(name: .nClawCredentialsUpdated, object: nil)
        }
    }

    // MARK: - Private

    private func openOnboardingWindow() {
        // Find the onboarding WindowGroup by its title prefix and bring it forward,
        // or open a fresh one if none exists yet.
        if let existing = NSApplication.shared.windows.first(where: { $0.title.hasPrefix("Setup") }) {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Trigger the WindowGroup by sending the openWindow action via the environment.
        // For menu bar apps, the cleanest path is to post the built-in openWindow
        // notification that SwiftUI's WindowGroup listens to.
        if #available(macOS 13.0, *) {
            NSApp.sendAction(#selector(NSDocument.makeWindowControllers), to: nil, from: nil)
        }

        // Fallback: create an NSWindow hosting the OnboardingView directly.
        let onboardingWindow = OnboardingWindowController()
        onboardingWindow.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Onboarding Window Controller

/// Fallback NSWindowController that hosts OnboardingView when the SwiftUI
/// WindowGroup approach fails (e.g., during first launch on macOS 13).
final class OnboardingWindowController: NSWindowController {
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 440),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Setup \u{0273}Claw"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)

        let contentView = OnboardingView {
            window.close()
        }
        window.contentView = NSHostingView(rootView: contentView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not used")
    }
}

// MARK: - Notification Names (T-1371)

extension Notification.Name {
    /// Posted by AppDelegate when a new JWT arrives via the nclaw:// URL scheme.
    static let nClawCredentialsUpdated = Notification.Name("nClawCredentialsUpdated")
}

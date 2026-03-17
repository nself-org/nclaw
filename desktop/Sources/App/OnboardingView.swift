import SwiftUI
import AuthenticationServices

// MARK: - Onboarding View

struct OnboardingView: View {
    var onComplete: () -> Void

    // Tab selection
    @State private var selectedTab: OnboardingTab = .pairWithCode

    // Pair-with-code state
    @State private var serverURL: String = ""
    @State private var pairCode: String = ""
    @State private var pairEmail: String = ""
    @State private var pairPassword: String = ""
    @State private var pairState: PairFlowState = .enterCode
    @State private var pairError: String?
    @State private var isPairing: Bool = false

    // Direct sign-in state
    @State private var directServerURL: String = ""
    @State private var directEmail: String = ""
    @State private var directPassword: String = ""
    @State private var directError: String?
    @State private var isSigningIn: Bool = false

    // Passkey sign-in state
    @State private var passkeyServerURL: String = ""
    @State private var passkeyError: String?
    @State private var isPasskeyAuthenticating: Bool = false

    private let accent = Color(red: 0.388, green: 0.4, blue: 0.945)

    // MARK: - Tab + Flow state

    enum OnboardingTab: String, CaseIterable {
        case pairWithCode = "Pair with Code"
        case signInDirectly = "Sign In Directly"
        case signInWithPasskey = "Sign In with Passkey"
    }

    enum PairFlowState {
        case enterCode
        case enterCredentials
        case done
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection

            Divider()

            // Tab selector — all three options at the same level
            Picker("", selection: $selectedTab) {
                ForEach(OnboardingTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedTab {
                    case .pairWithCode:
                        pairWithCodeSection
                    case .signInDirectly:
                        directSignInSection
                    case .signInWithPasskey:
                        passkeySignInSection
                    }
                }
                .padding(20)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(width: 460, height: 460)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "brain.head.profile")
                .font(.title2)
                .foregroundStyle(accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("\u{0266}Claw Setup")
                    .font(.headline)
                Text("Connect to your nSelf server")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Pair with Code Section

    private var pairWithCodeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Pair with code", systemImage: "qrcode")
                .font(.subheadline.weight(.semibold))

            Text("Run `nself claw pair` on your server to get a 6-character code.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                TextField("Server URL  (e.g. https://api.myserver.com)", text: $serverURL)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: serverURL) { _ in pairError = nil }

                TextField("Pair code  (e.g. ABCDEF)", text: $pairCode)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: pairCode) { _ in pairError = nil }
                    .onSubmit { if pairState == .enterCode { redeemCode() } }

                if pairState == .enterCredentials {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Server found. Sign in to complete pairing.")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .padding(.top, 4)

                        TextField("Email", text: $pairEmail)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: pairEmail) { _ in pairError = nil }

                        SecureField("Password", text: $pairPassword)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: pairPassword) { _ in pairError = nil }
                            .onSubmit { signInAfterPair() }
                    }
                }

                if let error = pairError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack {
                    switch pairState {
                    case .enterCode:
                        Button(action: redeemCode) {
                            HStack(spacing: 6) {
                                if isPairing {
                                    ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                                }
                                Text("Connect with code")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                        .disabled(serverURL.trimmingCharacters(in: .whitespaces).isEmpty
                            || pairCode.trimmingCharacters(in: .whitespaces).isEmpty
                            || isPairing)

                    case .enterCredentials:
                        Button(action: signInAfterPair) {
                            HStack(spacing: 6) {
                                if isPairing {
                                    ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                                }
                                Text("Sign in")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                        .disabled(pairEmail.trimmingCharacters(in: .whitespaces).isEmpty
                            || pairPassword.isEmpty
                            || isPairing)

                        Button("Back") {
                            pairState = .enterCode
                            pairError = nil
                        }
                        .buttonStyle(.bordered)

                    case .done:
                        EmptyView()
                    }
                }
            }
        }
    }

    // MARK: - Direct Sign-In Section

    private var directSignInSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Sign in with email & password", systemImage: "envelope")
                .font(.subheadline.weight(.semibold))

            Text("Use this if your server is already configured and you just need to authenticate.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                TextField("Server URL  (e.g. https://api.myserver.com)", text: $directServerURL)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: directServerURL) { _ in directError = nil }

                TextField("Email", text: $directEmail)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: directEmail) { _ in directError = nil }

                SecureField("Password", text: $directPassword)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: directPassword) { _ in directError = nil }
                    .onSubmit { directSignIn() }

                if let error = directError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button(action: directSignIn) {
                    HStack(spacing: 6) {
                        if isSigningIn {
                            ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                        }
                        Text("Sign in")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(directServerURL.trimmingCharacters(in: .whitespaces).isEmpty
                    || directEmail.trimmingCharacters(in: .whitespaces).isEmpty
                    || directPassword.isEmpty
                    || isSigningIn)
            }
        }
    }

    // MARK: - Passkey Sign-In Section (T-1371)

    private var passkeySignInSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Sign in with Passkey", systemImage: "person.badge.key")
                .font(.subheadline.weight(.semibold))

            Text("Opens your browser for passkey authentication. After signing in, the app pairs automatically via the nclaw:// URL scheme.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                TextField("Server URL  (e.g. https://claw.myserver.com)", text: $passkeyServerURL)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: passkeyServerURL) { _ in passkeyError = nil }

                if let error = passkeyError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button(action: startPasskeyAuth) {
                    HStack(spacing: 6) {
                        if isPasskeyAuthenticating {
                            ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                        }
                        Image(systemName: "globe")
                        Text("Open Browser to Sign In")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(passkeyServerURL.trimmingCharacters(in: .whitespaces).isEmpty
                    || isPasskeyAuthenticating)
            }

            Text("After authenticating, the browser will redirect back to the app automatically.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Actions

    private func redeemCode() {
        let trimmedURL = serverURL.trimmingCharacters(in: .whitespaces)
        let trimmedCode = pairCode.trimmingCharacters(in: .whitespaces)

        guard validateURL(trimmedURL) else {
            pairError = "Invalid URL. Include scheme and host (e.g. https://api.myserver.com)."
            return
        }
        guard !trimmedCode.isEmpty else {
            pairError = "Enter the 6-character code from `nself claw pair`."
            return
        }

        isPairing = true
        pairError = nil

        Task {
            do {
                try await PairingAPI.redeemCode(serverURL: trimmedURL, code: trimmedCode.uppercased())
                await MainActor.run {
                    pairState = .enterCredentials
                    isPairing = false
                }
            } catch let error as PairingError {
                await MainActor.run {
                    pairError = error.userMessage
                    isPairing = false
                }
            } catch {
                await MainActor.run {
                    pairError = "Network error: \(error.localizedDescription)"
                    isPairing = false
                }
            }
        }
    }

    private func signInAfterPair() {
        let trimmedURL = serverURL.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = pairEmail.trimmingCharacters(in: .whitespaces)

        guard !trimmedEmail.isEmpty, !pairPassword.isEmpty else {
            pairError = "Email and password are required."
            return
        }

        isPairing = true
        pairError = nil

        Task {
            do {
                let token = try await PairingAPI.signIn(
                    serverURL: trimmedURL,
                    email: trimmedEmail,
                    password: pairPassword
                )
                await MainActor.run {
                    completeSetup(serverURL: trimmedURL, token: token)
                }
            } catch let error as PairingError {
                await MainActor.run {
                    pairError = error.userMessage
                    isPairing = false
                }
            } catch {
                await MainActor.run {
                    pairError = "Network error: \(error.localizedDescription)"
                    isPairing = false
                }
            }
        }
    }

    private func directSignIn() {
        let trimmedURL = directServerURL.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = directEmail.trimmingCharacters(in: .whitespaces)

        guard validateURL(trimmedURL) else {
            directError = "Invalid URL. Include scheme and host (e.g. https://api.myserver.com)."
            return
        }
        guard !trimmedEmail.isEmpty, !directPassword.isEmpty else {
            directError = "Email and password are required."
            return
        }

        isSigningIn = true
        directError = nil

        Task {
            do {
                let token = try await PairingAPI.signIn(
                    serverURL: trimmedURL,
                    email: trimmedEmail,
                    password: directPassword
                )
                await MainActor.run {
                    completeSetup(serverURL: trimmedURL, token: token)
                }
            } catch let error as PairingError {
                await MainActor.run {
                    directError = error.userMessage
                    isSigningIn = false
                }
            } catch {
                await MainActor.run {
                    directError = "Network error: \(error.localizedDescription)"
                    isSigningIn = false
                }
            }
        }
    }

    // MARK: - Passkey auth via ASWebAuthenticationSession (T-1371)

    private func startPasskeyAuth() {
        let trimmedURL = passkeyServerURL.trimmingCharacters(in: .whitespaces)

        guard validateURL(trimmedURL) else {
            passkeyError = "Invalid URL. Include scheme and host (e.g. https://claw.myserver.com)."
            return
        }

        var base = trimmedURL
        if base.hasSuffix("/") { base = String(base.dropLast()) }

        guard let loginURL = URL(string: base + "/login") else {
            passkeyError = "Could not construct login URL."
            return
        }

        isPasskeyAuthenticating = true
        passkeyError = nil

        let session = ASWebAuthenticationSession(
            url: loginURL,
            callbackURLScheme: "nclaw"
        ) { callbackURL, error in
            DispatchQueue.main.async {
                self.isPasskeyAuthenticating = false

                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    self.passkeyError = "Sign-in cancelled."
                    return
                }

                guard let callback = callbackURL,
                      let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
                      let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
                      !token.isEmpty
                else {
                    self.passkeyError = "Authentication failed or token missing in callback."
                    return
                }

                self.completeSetup(serverURL: trimmedURL, token: token)
            }
        }

        // macOS 10.15+: presentationContextProvider must be set.
        // Use a helper that satisfies the protocol without requiring a window reference here.
        session.presentationContextProvider = PasskeyPresentationContext()
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }

    private func completeSetup(serverURL: String, token: String) {
        // Derive WebSocket URL from HTTP server URL
        // e.g. https://api.myserver.com -> wss://api.myserver.com/claw/ws
        //      http://192.168.1.x:3721  -> ws://192.168.1.x:3721/claw/ws
        let wsURL = httpToWebSocketURL(serverURL)

        UserDefaults.standard.set(wsURL, forKey: "serverURL")
        _ = KeychainHelper.save(key: "nclaw-jwt-token", value: token)

        isPairing = false
        isSigningIn = false
        pairState = .done

        onComplete()
    }

    // MARK: - Helpers

    private func validateURL(_ raw: String) -> Bool {
        guard let url = URL(string: raw),
              url.scheme != nil,
              url.host != nil else { return false }
        return true
    }

    /// Converts an HTTP/HTTPS server base URL to the matching WebSocket URL.
    private func httpToWebSocketURL(_ raw: String) -> String {
        var result = raw
        if result.hasPrefix("https://") {
            result = "wss://" + result.dropFirst("https://".count)
        } else if result.hasPrefix("http://") {
            result = "ws://" + result.dropFirst("http://".count)
        }
        // Strip trailing slash before appending path
        if result.hasSuffix("/") {
            result = String(result.dropLast())
        }
        return result + "/claw/ws"
    }
}

// MARK: - Pairing API

enum PairingError: Error {
    case invalidURL
    case wrongCode
    case expiredCode
    case wrongCredentials
    case serverError(Int)
    case decodingError
    case unknown(String)

    var userMessage: String {
        switch self {
        case .invalidURL: return "Invalid server URL."
        case .wrongCode: return "Invalid or already-used code. Run `nself claw pair` again."
        case .expiredCode: return "Code expired. Run `nself claw pair` again to get a new one."
        case .wrongCredentials: return "Wrong email or password."
        case .serverError(let code): return "Server error (\(code)). Check server logs."
        case .decodingError: return "Unexpected server response format."
        case .unknown(let msg): return msg
        }
    }
}

enum PairingAPI {
    // MARK: Redeem pair code

    static func redeemCode(serverURL: String, code: String) async throws {
        let url = try buildURL(serverURL, path: "/claw/devices/pair/redeem")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body = ["code": code]
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PairingError.unknown("No HTTP response") }

        switch http.statusCode {
        case 200, 201:
            return // success — user_id not needed locally
        case 400, 404, 422:
            throw PairingError.wrongCode
        case 410:
            throw PairingError.expiredCode
        default:
            throw PairingError.serverError(http.statusCode)
        }
    }

    // MARK: Sign in (with fallback)

    /// Attempts the new claw auth endpoint first, falls back to nHost email/password.
    static func signIn(serverURL: String, email: String, password: String) async throws -> String {
        // Try new claw auth endpoint first
        if let token = try? await signInClawAuth(serverURL: serverURL, email: email, password: password) {
            return token
        }
        // Fall back to nHost email/password
        return try await signInNHost(serverURL: serverURL, email: email, password: password)
    }

    // MARK: Private

    private static func signInClawAuth(serverURL: String, email: String, password: String) async throws -> String {
        let url = try buildURL(serverURL, path: "/auth/password")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body = ["email": email, "password": password]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PairingError.unknown("No HTTP response") }

        switch http.statusCode {
        case 200, 201:
            struct ClawAuthResponse: Decodable {
                let ok: Bool?
                let token: String?
            }
            if let decoded = try? JSONDecoder().decode(ClawAuthResponse.self, from: data),
               let token = decoded.token {
                return token
            }
            throw PairingError.decodingError

        case 401, 403:
            throw PairingError.wrongCredentials

        case 404:
            // Endpoint doesn't exist on this server — signal caller to try fallback
            throw PairingError.serverError(404)

        default:
            throw PairingError.serverError(http.statusCode)
        }
    }

    private static func signInNHost(serverURL: String, email: String, password: String) async throws -> String {
        let url = try buildURL(serverURL, path: "/v1/signin/email-password")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body = ["email": email, "password": password]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PairingError.unknown("No HTTP response") }

        switch http.statusCode {
        case 200, 201:
            struct NHostResponse: Decodable {
                struct Session: Decodable {
                    let accessToken: String
                }
                let session: Session?
            }
            if let decoded = try? JSONDecoder().decode(NHostResponse.self, from: data),
               let token = decoded.session?.accessToken {
                return token
            }
            throw PairingError.decodingError

        case 401, 403:
            throw PairingError.wrongCredentials

        default:
            throw PairingError.serverError(http.statusCode)
        }
    }

    private static func buildURL(_ serverURL: String, path: String) throws -> URL {
        var base = serverURL
        if base.hasSuffix("/") { base = String(base.dropLast()) }
        guard let url = URL(string: base + path) else { throw PairingError.invalidURL }
        return url
    }
}

// MARK: - Passkey Presentation Context (T-1371)

/// Satisfies ASWebAuthenticationPresentationContextProviding for menu-bar apps
/// that may not have a key window at the moment the session starts.
final class PasskeyPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Use the key window if available; otherwise use any visible window.
        return NSApplication.shared.keyWindow
            ?? NSApplication.shared.windows.first(where: { $0.isVisible })
            ?? ASPresentationAnchor()
    }
}

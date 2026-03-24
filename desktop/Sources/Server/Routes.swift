import Foundation

/// Route handler for the local HTTP server.
/// Maps paths to service methods and endpoint handlers.
final class RouteHandler {
    private let fileEndpoints = FileEndpoints()
    private let shellEndpoints = ShellEndpoints()
    private let clipboardService = ClipboardService()
    private let screenshotService = ScreenshotService()
    private let browserService = BrowserService()
    // T-1351: Daemon capability routes
    private let editorContextService = EditorContextService()
    private let terminalBufferService = TerminalBufferService()
    // T-2727: Audio capture + transcription
    private let audioEndpoints = AudioEndpoints()
    // T-2729: Sandbox filesystem access for AI tools
    private let sandboxFSEndpoints = SandboxFSEndpoints()

    func handle(_ request: HTTPRequest) -> HTTPResponse {
        // T-2729: Sandbox FS routes use query params, so match on path prefix.
        let basePath = request.path.components(separatedBy: "?").first ?? request.path

        switch (request.method, basePath) {

        // Health check
        case ("GET", "/health"):
            return handleHealth()

        // Capabilities report
        case ("GET", "/capabilities"):
            return handleCapabilities()

        // File operations
        case ("POST", "/files/read"):
            return fileEndpoints.handleRead(request)
        case ("POST", "/files/write"):
            return fileEndpoints.handleWrite(request)
        case ("POST", "/files/list"):
            return fileEndpoints.handleList(request)
        case ("POST", "/files/delete"):
            return fileEndpoints.handleDelete(request)
        case ("POST", "/files/mkdir"):
            return fileEndpoints.handleMkdir(request)

        // Shell execution
        case ("POST", "/shell/execute"):
            return shellEndpoints.handleExecute(request)
        case (_, "/shell/allowlist"):
            return shellEndpoints.handleAllowlist(request)

        // Legacy shell endpoint (redirects to new)
        case ("POST", "/shell/exec"):
            return shellEndpoints.handleExecute(request)

        // Clipboard — T-1351 canonical paths (also keeping legacy /clipboard/read + /clipboard/write)
        case ("GET", "/clipboard"):
            return clipboardService.handleRead()
        case ("POST", "/clipboard"):
            return clipboardService.handleWriteText(request)
        case ("GET", "/clipboard/read"):
            return clipboardService.handleRead()
        case ("POST", "/clipboard/write"):
            return clipboardService.handleWrite(request)

        // Screenshot — T-1351 canonical path (also keeping legacy /screenshot)
        case ("GET", "/screen"):
            return screenshotService.handleCapture(request)
        case ("POST", "/screenshot"):
            return screenshotService.handleCapture(request)

        // T-1351: Editor context (active file via Accessibility API)
        case ("GET", "/context"):
            return editorContextService.handleGetContext(request)

        // T-1351: Terminal buffer
        case ("GET", "/terminal"):
            return terminalBufferService.handleGetTerminal(request)

        // Browser automation (CDP) — T-1412/T-1413
        // Unified action endpoint (used by nClaw browser_ tools)
        case ("GET", "/browser/tabs"):
            guard isBrowserEnabled() else { return .error("Browser automation not enabled", status: 403) }
            return BrowserEndpoints.handleTabs(request, service: browserService)
        case ("POST", "/browser/action"):
            guard isBrowserEnabled() else { return .error("Browser automation not enabled", status: 403) }
            return BrowserEndpoints.handleAction(request, service: browserService)
        case ("GET", "/browser/cookies"):
            guard isBrowserEnabled() else { return .error("Browser automation not enabled", status: 403) }
            return BrowserEndpoints.handleCookies(request, service: browserService)
        case ("POST", "/browser/extract"):
            guard isBrowserEnabled() else { return .error("Browser automation not enabled", status: 403) }
            return BrowserEndpoints.handleExtract(request, service: browserService)
        // Legacy browser routes (kept for backwards compat)
        case ("POST", "/browser/open"):
            guard isBrowserEnabled() else { return .error("Browser automation not enabled", status: 403) }
            return BrowserEndpoints.handleOpen(request, service: browserService)
        case ("POST", "/browser/screenshot"):
            guard isBrowserEnabled() else { return .error("Browser automation not enabled", status: 403) }
            return BrowserEndpoints.handleScreenshot(request, service: browserService)
        case ("POST", "/browser/execute"):
            guard isBrowserEnabled() else { return .error("Browser automation not enabled", status: 403) }
            return BrowserEndpoints.handleExecute(request, service: browserService)
        case ("POST", "/browser/fill"):
            guard isBrowserEnabled() else { return .error("Browser automation not enabled", status: 403) }
            return BrowserEndpoints.handleFill(request, service: browserService)
        case ("POST", "/browser/click"):
            guard isBrowserEnabled() else { return .error("Browser automation not enabled", status: 403) }
            return BrowserEndpoints.handleClick(request, service: browserService)
        case ("POST", "/browser/wait"):
            guard isBrowserEnabled() else { return .error("Browser automation not enabled", status: 403) }
            return BrowserEndpoints.handleWait(request, service: browserService)

        // T-2727: Audio capture + Whisper transcription
        case ("POST", "/companion/audio/start"):
            return audioEndpoints.handleStartRecording(request)
        case ("POST", "/companion/audio/stop"):
            return audioEndpoints.handleStopRecording(request)
        case ("POST", "/companion/audio/transcribe"):
            return audioEndpoints.handleTranscribe(request)

        // T-2729: Sandbox filesystem access for AI tools
        case ("GET", "/companion/fs/list"):
            return sandboxFSEndpoints.handleList(request)
        case ("GET", "/companion/fs/read"):
            return sandboxFSEndpoints.handleRead(request)
        case ("GET", "/companion/fs/search"):
            return sandboxFSEndpoints.handleSearch(request)
        case ("GET", "/companion/fs/roots"):
            return sandboxFSEndpoints.handleRoots(request)
        case ("POST", "/companion/fs/grant"):
            return sandboxFSEndpoints.handleGrant(request)

        // Catch-all
        case (_, _) where request.method != "GET" && request.method != "POST" && request.method != "DELETE":
            return .error("Method not allowed", status: 405)
        default:
            return .error("Not found", status: 404)
        }
    }

    // MARK: - Built-in Routes

    private func handleHealth() -> HTTPResponse {
        let health: [String: String] = [
            "status": "ok",
            "version": "0.1.0",
            "daemon": "nclaw-desktop"
        ]
        return .json(health)
    }

    private func handleCapabilities() -> HTTPResponse {
        let caps = DeviceCapability.current()
        return .json(caps)
    }

    /// T-1413: Check if browser automation has been enabled by the user.
    private func isBrowserEnabled() -> Bool {
        return UserDefaults.standard.bool(forKey: "NClaw_BrowserEnabled")
    }
}

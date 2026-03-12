import Foundation

/// Route handler for the local HTTP server.
/// Maps paths to service methods and endpoint handlers.
final class RouteHandler {
    private let fileEndpoints = FileEndpoints()
    private let shellEndpoints = ShellEndpoints()
    private let clipboardService = ClipboardService()
    private let screenshotService = ScreenshotService()
    private let browserService = BrowserService()

    func handle(_ request: HTTPRequest) -> HTTPResponse {
        switch (request.method, request.path) {

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

        // Clipboard
        case ("GET", "/clipboard/read"):
            return clipboardService.handleRead()
        case ("POST", "/clipboard/write"):
            return clipboardService.handleWrite(request)

        // Screenshot
        case ("POST", "/screenshot"):
            return screenshotService.handleCapture(request)

        // Browser automation (CDP)
        case ("POST", "/browser/open"):
            return BrowserEndpoints.handleOpen(request, service: browserService)
        case ("POST", "/browser/screenshot"):
            return BrowserEndpoints.handleScreenshot(request, service: browserService)
        case ("POST", "/browser/execute"):
            return BrowserEndpoints.handleExecute(request, service: browserService)
        case ("POST", "/browser/fill"):
            return BrowserEndpoints.handleFill(request, service: browserService)
        case ("POST", "/browser/click"):
            return BrowserEndpoints.handleClick(request, service: browserService)
        case ("POST", "/browser/wait"):
            return BrowserEndpoints.handleWait(request, service: browserService)

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
}

import Foundation

/// Processes incoming action dispatches from the nself-claw server.
/// Server sends action_type values: "file_op", "shell", "clipboard", "screenshot", "browser"
@MainActor
final class ActionHandler {
    private let fileService = FileService()
    private let shellService = ShellService()
    private let clipboardService = ClipboardService()
    private let screenshotService = ScreenshotService()
    private let browserService = BrowserService()

    func handle(_ action: Action) {
        ClawLogger.info("Handling action: \(action.action_type) (id: \(action.id))")
        fputs("[nClaw] action: \(action.action_type) id=\(action.id)\n", stderr)

        switch action.action_type {
        case "file_op":
            handleFileOp(action)
        case "shell":
            handleShell(action)
        case "clipboard":
            handleClipboard(action)
        case "screenshot":
            handleScreenshot(action)
        case "browser":
            ClawLogger.info("Browser actions not yet implemented")
        default:
            ClawLogger.error("Unknown action type: \(action.action_type)")
        }
    }

    // MARK: - File Operations

    private func handleFileOp(_ action: Action) {
        guard let path = action.param("path") else {
            ClawLogger.error("file_op missing 'path' param (id: \(action.id))")
            return
        }
        // Distinguish operation by presence of params:
        // companion.file_write → {path, content}
        // companion.file_read  → {path}
        // companion.file_list  → {path, recursive?}
        if let content = action.param("content") {
            let result = fileService.writeFile(path: path, content: content)
            fputs("[nClaw] file_op write \(path): \(result)\n", stderr)
            logResult(action: action, result: result)
        } else if action.params?.keys.contains("recursive") == true {
            let result = fileService.listDirectory(path: path)
            logResult(action: action, result: result)
        } else {
            let result = fileService.readFile(path: path)
            logResult(action: action, result: result)
        }
    }

    // MARK: - Shell

    /// Regex matching legacy shell commands that are really file writes:
    /// `mkdir -p /path && printf "content" > /path/file.md`
    /// These should have been sent as file_op actions. Convert silently.
    private static let shellFileWritePattern = try! NSRegularExpression(
        pattern: #"^mkdir\s+-p\s+(\S+)\s+&&\s+printf\s+"(.+)"\s+>\s+(\S+)$"#,
        options: [.dotMatchesLineSeparators]
    )

    private func handleShell(_ action: Action) {
        guard let command = action.param("command") else {
            ClawLogger.error("shell action missing 'command' param")
            return
        }

        // Convert legacy shell file-write commands to silent file_op.
        // The server historically sent `mkdir -p ... && printf ... > file.md`
        // as shell actions, which prompted the user for every single write.
        // Detect this pattern and route through FileService instead.
        if let (path, content) = Self.extractFileWrite(from: command) {
            fputs("[nClaw] shell->file_op upgrade: \(path)\n", stderr)
            ClawLogger.info("Upgrading shell file-write to file_op: \(path)")
            let result = fileService.writeFile(path: path, content: content)
            fputs("[nClaw] file_op write \(path): \(result)\n", stderr)
            logResult(action: action, result: result)
            return
        }

        let workingDir = action.param("cwd")
        shellService.executeWithApproval(command: command, workingDirectory: workingDir) { result in
            switch result {
            case .success(let output):
                ClawLogger.info("Shell action \(action.id) completed: \(output.prefix(200))")
            case .failure(let error):
                ClawLogger.error("Shell action \(action.id) failed: \(error)")
            }
        }
    }

    /// Extract path and content from a legacy shell file-write command.
    /// Returns nil if the command doesn't match the pattern.
    private static func extractFileWrite(from command: String) -> (path: String, content: String)? {
        let range = NSRange(command.startIndex..., in: command)
        guard let match = shellFileWritePattern.firstMatch(in: command, range: range) else {
            return nil
        }

        guard let pathRange = Range(match.range(at: 3), in: command) else {
            return nil
        }
        let path = String(command[pathRange])

        guard let contentRange = Range(match.range(at: 2), in: command) else {
            return nil
        }
        // Unescape printf content: \\n -> newline, \\\\ -> backslash
        let raw = String(command[contentRange])
        let content = raw
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\\\", with: "\\")
            .replacingOccurrences(of: "\\\"", with: "\"")

        // Sandbox check: only allow writes within home directory
        let home = NSHomeDirectory()
        let resolved = (path as NSString).expandingTildeInPath
        guard resolved.hasPrefix(home) else {
            ClawLogger.error("shell->file_op blocked: path outside home: \(path)")
            return nil
        }

        return (path: resolved, content: content)
    }

    // MARK: - Clipboard

    private func handleClipboard(_ action: Action) {
        if let content = action.param("content") {
            let result = clipboardService.write(content)
            logResult(action: action, result: result)
        } else {
            let result = clipboardService.read()
            logResult(action: action, result: result)
        }
    }

    // MARK: - Screenshot

    private func handleScreenshot(_ action: Action) {
        Task {
            let result = await screenshotService.capture()
            switch result {
            case .success(let base64):
                ClawLogger.info("Screenshot action \(action.id) completed (\(base64.count) chars)")
            case .failure(let error):
                ClawLogger.error("Screenshot action \(action.id) failed: \(error)")
            }
        }
    }

    private func logResult(action: Action, result: Result<String, ServiceError>) {
        switch result {
        case .success(let output):
            ClawLogger.info("Action \(action.id) (\(action.action_type)) completed")
            ClawLogger.debug("Output: \(output.prefix(500))")
        case .failure(let error):
            ClawLogger.error("Action \(action.id) (\(action.action_type)) failed: \(error)")
        }
    }
}

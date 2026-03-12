import Foundation
import AppKit

/// HTTP endpoint handlers for shell command execution.
/// Commands matching the allowlist run without user approval.
/// All other commands trigger a native dialog for explicit user consent.
final class ShellEndpoints {

    /// Default auto-approved command prefixes (safe read-only commands).
    private static let defaultAllowlist: [String] = [
        "git status",
        "ls",
        "cat",
        "pwd",
        "which",
        "echo",
        "date",
        "whoami"
    ]

    private static let allowlistKey = "shellAllowlist"
    private static let defaultTimeout: TimeInterval = 30
    private static let maxTimeout: TimeInterval = 300

    // MARK: - POST /shell/execute

    /// Execute a shell command with optional working directory and timeout.
    /// Auto-approved commands bypass the user dialog.
    ///
    /// Request: { "command": "...", "workingDirectory": "...", "timeout": 30 }
    /// Response: { "stdout": "...", "stderr": "...", "exitCode": 0, "timedOut": false }
    func handleExecute(_ request: HTTPRequest) -> HTTPResponse {
        struct Params: Decodable {
            let command: String
            let workingDirectory: String?
            let timeout: Double?
        }
        guard let params = request.jsonBody(as: Params.self) else {
            return .error("Missing 'command' in request body")
        }

        let command = params.command.trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty else {
            return .error("Command cannot be empty")
        }

        let timeout = min(
            params.timeout ?? ShellEndpoints.defaultTimeout,
            ShellEndpoints.maxTimeout
        )

        // Check allowlist for auto-approval
        let allowed = isAllowed(command)

        if !allowed {
            // Synchronous user approval on the main thread
            var approved = false
            let semaphore = DispatchSemaphore(value: 0)

            DispatchQueue.main.async {
                approved = self.showApprovalDialog(
                    command: command,
                    workingDirectory: params.workingDirectory
                )
                semaphore.signal()
            }

            semaphore.wait()

            if !approved {
                ClawLogger.info("[shell/execute] DENIED by user: \(command)")
                return .error("User denied the operation", status: 403)
            }
        }

        // Execute the command
        let result = execute(
            command: command,
            workingDirectory: params.workingDirectory,
            timeout: timeout
        )

        ClawLogger.info("[shell/execute] \(allowed ? "auto" : "approved"): \(command) -> exit \(result.exitCode)")
        return .json(result)
    }

    // MARK: - /shell/allowlist (GET, POST, DELETE)

    /// Manage the command allowlist.
    /// GET:    Returns { "allowlist": ["git status", "ls", ...] }
    /// POST:   Adds a pattern. Body: { "pattern": "npm test" }
    /// DELETE: Removes a pattern. Body: { "pattern": "npm test" }
    func handleAllowlist(_ request: HTTPRequest) -> HTTPResponse {
        switch request.method {
        case "GET":
            return handleAllowlistGet()
        case "POST":
            return handleAllowlistAdd(request)
        case "DELETE":
            return handleAllowlistRemove(request)
        default:
            return .error("Method not allowed", status: 405)
        }
    }

    // MARK: - Allowlist Storage

    private func currentAllowlist() -> [String] {
        if let stored = UserDefaults.standard.array(forKey: ShellEndpoints.allowlistKey) as? [String] {
            return stored
        }
        // First access: seed with defaults and persist
        UserDefaults.standard.set(ShellEndpoints.defaultAllowlist, forKey: ShellEndpoints.allowlistKey)
        return ShellEndpoints.defaultAllowlist
    }

    private func saveAllowlist(_ list: [String]) {
        UserDefaults.standard.set(list, forKey: ShellEndpoints.allowlistKey)
    }

    private func isAllowed(_ command: String) -> Bool {
        let list = currentAllowlist()
        for prefix in list {
            if command == prefix || command.hasPrefix(prefix + " ") {
                return true
            }
        }
        return false
    }

    // MARK: - Allowlist Handlers

    private func handleAllowlistGet() -> HTTPResponse {
        let list = currentAllowlist()
        return .json(AllowlistResponse(allowlist: list))
    }

    private func handleAllowlistAdd(_ request: HTTPRequest) -> HTTPResponse {
        struct Params: Decodable { let pattern: String }
        guard let params = request.jsonBody(as: Params.self) else {
            return .error("Missing 'pattern' in request body")
        }

        let pattern = params.pattern.trimmingCharacters(in: .whitespaces)
        guard !pattern.isEmpty else {
            return .error("Pattern cannot be empty")
        }

        var list = currentAllowlist()
        if !list.contains(pattern) {
            list.append(pattern)
            saveAllowlist(list)
            ClawLogger.info("[shell/allowlist] Added: \(pattern)")
        }

        return .json(AllowlistResponse(allowlist: list))
    }

    private func handleAllowlistRemove(_ request: HTTPRequest) -> HTTPResponse {
        struct Params: Decodable { let pattern: String }
        guard let params = request.jsonBody(as: Params.self) else {
            return .error("Missing 'pattern' in request body")
        }

        let pattern = params.pattern.trimmingCharacters(in: .whitespaces)
        var list = currentAllowlist()
        list.removeAll { $0 == pattern }
        saveAllowlist(list)

        ClawLogger.info("[shell/allowlist] Removed: \(pattern)")
        return .json(AllowlistResponse(allowlist: list))
    }

    // MARK: - Approval Dialog

    private func showApprovalDialog(command: String, workingDirectory: String?) -> Bool {
        let alert = NSAlert()
        alert.messageText = "\u{0266}Claw: Shell Command Request"
        alert.informativeText = "The nClaw server is requesting to execute:\n\n\(command)"
        if let cwd = workingDirectory {
            alert.informativeText += "\n\nWorking directory: \(cwd)"
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Deny")

        let response = alert.runModal()
        return response == .alertFirstButtonReturn
    }

    // MARK: - Command Execution

    private func execute(command: String, workingDirectory: String?, timeout: TimeInterval) -> ExecResponse {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        if let cwd = workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        do {
            try process.run()
        } catch {
            return ExecResponse(
                stdout: "",
                stderr: "Failed to launch: \(error.localizedDescription)",
                exitCode: -1,
                timedOut: false
            )
        }

        // Wait with timeout
        var timedOut = false
        let deadline = DispatchTime.now() + timeout
        let waitGroup = DispatchGroup()
        waitGroup.enter()

        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            waitGroup.leave()
        }

        let waitResult = waitGroup.wait(timeout: deadline)
        if waitResult == .timedOut {
            timedOut = true
            process.terminate()
            // Give a moment for cleanup, then force-kill if still running
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdoutStr = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""

        return ExecResponse(
            stdout: stdoutStr,
            stderr: stderrStr,
            exitCode: Int(process.terminationStatus),
            timedOut: timedOut
        )
    }
}

// MARK: - Response Types

private struct ExecResponse: Encodable {
    let stdout: String
    let stderr: String
    let exitCode: Int
    let timedOut: Bool
}

private struct AllowlistResponse: Encodable {
    let allowlist: [String]
}

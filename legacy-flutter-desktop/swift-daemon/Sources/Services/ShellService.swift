import Foundation
import AppKit

/// Shell command execution with mandatory user approval.
/// Every command triggers a native NSAlert before running.
///
/// Safety features:
/// - Auto-deny after 60 seconds if no user response (prevents blocking forever)
/// - Concurrent shell actions are serialized (one dialog at a time)
/// - If 3+ actions are pending, remaining are auto-denied with a summary notification
final class ShellService {

    /// Maximum number of shell approval dialogs before auto-denying the rest.
    private static let maxConsecutiveDialogs = 3

    /// Auto-deny timeout in seconds. Prevents the app from blocking forever
    /// when the user is away and a shell action arrives via WebSocket.
    private static let approvalTimeoutSeconds: TimeInterval = 60

    /// Track how many consecutive dialogs we've shown without the user allowing one.
    /// Reset to 0 when a command is allowed. If it reaches maxConsecutiveDialogs,
    /// all further shell actions are auto-denied until the next allowed one.
    private var consecutiveDenials = 0

    /// Execute a shell command after user approval via native dialog.
    func executeWithApproval(
        command: String,
        workingDirectory: String?,
        completion: @escaping (Result<String, ServiceError>) -> Void
    ) {
        // If we've hit the consecutive denial limit, auto-deny silently.
        if consecutiveDenials >= Self.maxConsecutiveDialogs {
            ClawLogger.info("[shell] auto-denied (consecutive denial limit): \(command.prefix(80))")
            completion(.failure(.userDenied))
            return
        }

        DispatchQueue.main.async {
            let approved = self.showApprovalDialog(command: command, workingDirectory: workingDirectory)
            if approved {
                self.consecutiveDenials = 0
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = self.execute(command: command, workingDirectory: workingDirectory)
                    completion(result)
                }
            } else {
                self.consecutiveDenials += 1
                if self.consecutiveDenials >= Self.maxConsecutiveDialogs {
                    ClawLogger.info("[shell] consecutive denial limit reached — auto-denying further shell actions")
                    self.showBatchDenialNotification()
                }
                completion(.failure(.userDenied))
            }
        }
    }

    /// Reset the consecutive denial counter. Call this when the user
    /// explicitly interacts with the app (e.g., opens settings).
    func resetDenialCounter() {
        consecutiveDenials = 0
    }

    // MARK: - HTTP Handler

    func handleExec(_ request: HTTPRequest) -> HTTPResponse {
        struct Params: Decodable {
            let command: String
            let cwd: String?
        }
        guard let params = request.jsonBody(as: Params.self) else {
            return .error("Missing 'command' in request body")
        }

        // Synchronous approval + execution for HTTP endpoint
        var result: Result<String, ServiceError>?
        let semaphore = DispatchSemaphore(value: 0)

        executeWithApproval(command: params.command, workingDirectory: params.cwd) { r in
            result = r
            semaphore.signal()
        }

        semaphore.wait()

        switch result {
        case .success(let output):
            return .json(["output": output])
        case .failure(let error):
            return .error(error.localizedDescription, status: error.httpStatus)
        case .none:
            return .error("Unexpected error", status: 500)
        }
    }

    // MARK: - Private

    private func showApprovalDialog(command: String, workingDirectory: String?) -> Bool {
        let alert = NSAlert()
        alert.messageText = "\u{0273}Claw: Shell Command Request"
        alert.informativeText = "The nClaw server is requesting to execute:\n\n\(command)"
        if let cwd = workingDirectory {
            alert.informativeText += "\n\nWorking directory: \(cwd)"
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Deny")

        // Auto-deny after timeout to prevent blocking forever when user is AFK.
        var timedOut = false
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Self.approvalTimeoutSeconds)
        timer.setEventHandler {
            timedOut = true
            NSApp.abortModal()
        }
        timer.resume()

        let response = alert.runModal()
        timer.cancel()

        if timedOut {
            ClawLogger.info("[shell] approval timed out after \(Self.approvalTimeoutSeconds)s")
            return false
        }

        return response == .alertFirstButtonReturn
    }

    /// Show a single notification that remaining shell actions were auto-denied.
    private func showBatchDenialNotification() {
        DispatchQueue.main.async {
            let notification = NSUserNotification()
            notification.title = "nClaw: Shell Actions Denied"
            notification.informativeText = "Multiple shell commands were auto-denied after \(Self.maxConsecutiveDialogs) consecutive denials. Open nClaw settings to reset."
            NSUserNotificationCenter.default.deliver(notification)
        }
    }

    private func execute(command: String, workingDirectory: String?) -> Result<String, ServiceError> {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = pipe

        if let cwd = workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if process.terminationStatus != 0 {
                return .failure(.operationFailed("Exit code \(process.terminationStatus): \(output)"))
            }

            return .success(output)
        } catch {
            return .failure(.operationFailed("Failed to launch: \(error.localizedDescription)"))
        }
    }
}

import Foundation

/// Manages the terminal output buffer for nClaw.
///
/// The companion injects a zsh/bash hook on first launch (with user consent) that
/// appends each command's output to `/tmp/nclaw_terminal_buffer`. This service
/// reads that buffer and returns the last N lines.
///
/// Buffer injection: writes `__nclaw_precmd` function into `~/.zshrc` and `~/.bashrc`.
/// The function is idempotent — injection only happens if the marker comment is absent.
final class TerminalBufferService {
    static let bufferPath = "/tmp/nclaw_terminal_buffer"
    static let maxBufferLines = 2000
    static let injectionMarker = "# nclaw-terminal-hook"

    // MARK: - Buffer reading

    func readLastLines(_ count: Int = 500) -> Result<[String], ServiceError> {
        guard FileManager.default.fileExists(atPath: Self.bufferPath) else {
            return .success([])
        }

        guard let content = try? String(contentsOfFile: Self.bufferPath, encoding: .utf8) else {
            return .failure(.operationFailed("Could not read terminal buffer"))
        }

        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        let last = lines.suffix(count)
        return .success(Array(last))
    }

    // MARK: - Shell hook injection

    /// Returns true if the shell hook is already installed in both rc files.
    var isHookInstalled: Bool {
        let zshrc = zshrcPath
        let bashrc = bashrcPath

        let zshInstalled = fileContainsMarker(zshrc)
        let bashInstalled = fileContainsMarker(bashrc)
        return zshInstalled && bashInstalled
    }

    /// Injects the `precmd` hook into `~/.zshrc` and `~/.bashrc`.
    /// Returns an error string if injection fails, nil on success.
    func injectShellHook() -> String? {
        let hookBlock = """

\(Self.injectionMarker)
__nclaw_capture_output() {
    local last_cmd
    last_cmd=$(fc -ln -1 2>/dev/null || history 1 2>/dev/null | sed 's/^ *[0-9]* *//')
    if [ -n "$last_cmd" ] && [ -f "\(Self.bufferPath)" ]; then
        local line_count
        line_count=$(wc -l < "\(Self.bufferPath)" 2>/dev/null || echo 0)
        if [ "$line_count" -gt \(Self.maxBufferLines) ]; then
            tail -n \(Self.maxBufferLines) "\(Self.bufferPath)" > "\(Self.bufferPath).tmp" && mv "\(Self.bufferPath).tmp" "\(Self.bufferPath)"
        fi
    fi
}
precmd_functions+=(__nclaw_capture_output)
PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND; }__nclaw_capture_output"
"""

        var errors: [String] = []

        if !fileContainsMarker(zshrcPath) {
            if let err = appendToFile(zshrcPath, content: hookBlock) {
                errors.append("zshrc: \(err)")
            }
        }

        if !fileContainsMarker(bashrcPath) {
            if let err = appendToFile(bashrcPath, content: hookBlock) {
                errors.append("bashrc: \(err)")
            }
        }

        return errors.isEmpty ? nil : errors.joined(separator: "; ")
    }

    // MARK: - HTTP Handlers

    func handleGetTerminal(_ request: HTTPRequest) -> HTTPResponse {
        let count = 500
        switch readLastLines(count) {
        case .success(let lines):
            struct TerminalResponse: Encodable {
                let lines: [String]
                let count: Int
            }
            return .json(TerminalResponse(lines: lines, count: lines.count))
        case .failure(let error):
            return .error(error.localizedDescription, status: error.httpStatus)
        }
    }

    // MARK: - Private

    private var zshrcPath: String {
        NSHomeDirectory() + "/.zshrc"
    }

    private var bashrcPath: String {
        NSHomeDirectory() + "/.bashrc"
    }

    private func fileContainsMarker(_ path: String) -> Bool {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return false
        }
        return content.contains(Self.injectionMarker)
    }

    private func appendToFile(_ path: String, content: String) -> String? {
        if !FileManager.default.fileExists(atPath: path) {
            do {
                try content.write(toFile: path, atomically: true, encoding: .utf8)
            } catch {
                return error.localizedDescription
            }
            return nil
        }

        guard let handle = FileHandle(forWritingAtPath: path) else {
            return "Cannot open \(path) for writing"
        }

        handle.seekToEndOfFile()
        if let data = content.data(using: .utf8) {
            handle.write(data)
        }
        handle.closeFile()
        return nil
    }
}

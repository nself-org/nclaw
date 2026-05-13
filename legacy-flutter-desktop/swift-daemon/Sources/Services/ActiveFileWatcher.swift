import Foundation
import AppKit

/// Watches for active editor file changes using the macOS Accessibility API and sends
/// `context_update` WebSocket messages to the nClaw server (T-1352).
///
/// Polls the frontmost application's AXDocument every 3 seconds. If the active file
/// path changes, fires the onChange callback so ConnectionManager can send a WS message.
final class ActiveFileWatcher {
    private var timer: DispatchSourceTimer?
    private var lastFilePath: String?
    private let queue = DispatchQueue(label: "org.nself.nclaw.file-watcher", qos: .background)
    private let editorService = EditorContextService()
    private var onChange: ((ContextUpdateMessage) -> Void)?

    /// T-1352 WS message format: {"type": "context_update", "file": "/path/to/file.rs", "language": "rust"}
    struct ContextUpdateMessage: Encodable {
        let type: String = "context_update"
        let file: String
        let language: String?
    }

    func start(onChange: @escaping (ContextUpdateMessage) -> Void) {
        self.onChange = onChange

        let src = DispatchSource.makeTimerSource(queue: queue)
        src.schedule(deadline: .now() + 1, repeating: 3)
        src.setEventHandler { [weak self] in
            self?.checkForFileChange()
        }
        src.resume()
        self.timer = src
        ClawLogger.info("Active file watcher started")
    }

    func stop() {
        timer?.cancel()
        timer = nil
        onChange = nil
        lastFilePath = nil
        ClawLogger.info("Active file watcher stopped")
    }

    var currentFilePath: String? { lastFilePath }

    // MARK: - Private

    private func checkForFileChange() {
        guard let path = editorService.detectActiveFilePath() else {
            if lastFilePath != nil {
                lastFilePath = nil
            }
            return
        }

        guard path != lastFilePath else { return }
        lastFilePath = path

        let language = inferLanguage(from: path)
        let msg = ContextUpdateMessage(file: path, language: language)
        onChange?(msg)
        ClawLogger.info("Active file changed: \(path)")
    }

    private func inferLanguage(from path: String) -> String? {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        switch ext {
        case "rs": return "rust"
        case "swift": return "swift"
        case "ts", "tsx": return "typescript"
        case "js", "jsx": return "javascript"
        case "py": return "python"
        case "go": return "go"
        case "kt": return "kotlin"
        case "java": return "java"
        case "rb": return "ruby"
        case "sh", "bash", "zsh": return "shell"
        case "svelte": return "svelte"
        case "vue": return "vue"
        case "dart": return "dart"
        case "c", "h": return "c"
        case "cpp", "cc", "cxx", "hpp": return "cpp"
        default: return ext.isEmpty ? nil : ext
        }
    }
}

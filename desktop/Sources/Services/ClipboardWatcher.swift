import Foundation
import AppKit

/// Monitors the system pasteboard for changes and sends `clipboard_update` WebSocket
/// messages to the nClaw server (T-1354).
///
/// Uses NSPasteboard's `changeCount` property — polling every 2 seconds on a
/// background DispatchSource timer. This is the standard approach on macOS since
/// there is no push notification for clipboard changes.
final class ClipboardWatcher {
    private var timer: DispatchSourceTimer?
    private var lastChangeCount: Int = -1
    private let queue = DispatchQueue(label: "org.nself.nclaw.clipboard-watcher", qos: .background)
    private var onClipboardChange: ((ClipboardEvent) -> Void)?

    struct ClipboardEvent {
        let contentType: String
        let preview: String
    }

    func start(onChange: @escaping (ClipboardEvent) -> Void) {
        self.onClipboardChange = onChange
        self.lastChangeCount = NSPasteboard.general.changeCount

        let src = DispatchSource.makeTimerSource(queue: queue)
        src.schedule(deadline: .now() + 2, repeating: 2)
        src.setEventHandler { [weak self] in
            self?.checkForChange()
        }
        src.resume()
        self.timer = src
        ClawLogger.info("Clipboard watcher started")
    }

    func stop() {
        timer?.cancel()
        timer = nil
        onClipboardChange = nil
        ClawLogger.info("Clipboard watcher stopped")
    }

    // MARK: - Private

    private func checkForChange() {
        let pb = NSPasteboard.general
        let currentCount = pb.changeCount
        guard currentCount != lastChangeCount else { return }

        lastChangeCount = currentCount

        let text = pb.string(forType: .string) ?? ""
        guard !text.isEmpty else { return }

        let event = ClipboardEvent(
            contentType: classifyClipboardContent(text),
            preview: String(text.prefix(100))
        )

        onClipboardChange?(event)
    }

    /// Classify clipboard content for annotation.
    private func classifyClipboardContent(_ text: String) -> String {
        // Stack trace heuristic: contains "at " lines or error traces
        if text.contains("\tat ") || text.contains("Error: ") || text.contains("Exception in thread") ||
           text.contains("Traceback (most recent call last)") || text.contains("at (") {
            return "stack_trace"
        }

        // URL heuristic
        if text.hasPrefix("http://") || text.hasPrefix("https://") || text.hasPrefix("ftp://") {
            return "url"
        }

        // Code heuristic: contains braces, semicolons, function/def/fn keywords
        let codeSignals = ["func ", "fn ", "def ", "class ", "import ", "const ", "let ", "var ",
                           "return ", "if (", "for (", "while (", "=>", "->"]
        let codeMatches = codeSignals.filter { text.contains($0) }.count
        if codeMatches >= 2 || text.contains("{") && text.contains("}") && text.contains("\n") {
            return "code"
        }

        return "text"
    }
}

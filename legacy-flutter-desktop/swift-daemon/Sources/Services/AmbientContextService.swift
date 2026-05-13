import Foundation
import AppKit

/// Streams ambient OS context (active app, window title, clipboard preview) to the
/// nClaw server over WebSocket every 2 seconds (T-2726).
///
/// Packages the data as a JSON message with type "ambient_context" so the server can
/// store it per-session and optionally inject it into the prompt pipeline.
final class AmbientContextService {
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "org.nself.nclaw.ambient-context", qos: .background)
    private var onChange: ((AmbientContextMessage) -> Void)?
    private var lastChangeCount: Int = -1
    private var lastAppName: String?
    private var lastWindowTitle: String?

    struct AmbientContextMessage: Encodable {
        let type: String = "ambient_context"
        let active_app: String
        let active_window: String
        let clipboard_preview: String
        let timestamp: String
    }

    func start(onChange: @escaping (AmbientContextMessage) -> Void) {
        self.onChange = onChange
        self.lastChangeCount = NSPasteboard.general.changeCount

        let src = DispatchSource.makeTimerSource(queue: queue)
        src.schedule(deadline: .now() + 2, repeating: 2)
        src.setEventHandler { [weak self] in
            self?.poll()
        }
        src.resume()
        self.timer = src
        ClawLogger.info("Ambient context service started")
    }

    func stop() {
        timer?.cancel()
        timer = nil
        onChange = nil
        lastAppName = nil
        lastWindowTitle = nil
        ClawLogger.info("Ambient context service stopped")
    }

    // MARK: - Private

    private func poll() {
        let app = NSWorkspace.shared.frontmostApplication
        let appName = app?.localizedName ?? "unknown"
        let windowTitle = activeWindowTitle(pid: app?.processIdentifier) ?? ""

        // Detect clipboard changes
        let currentCount = NSPasteboard.general.changeCount
        let clipboardChanged = currentCount != lastChangeCount
        if clipboardChanged {
            lastChangeCount = currentCount
        }

        // Only emit when something changed: app, window, or clipboard
        let appChanged = appName != lastAppName
        let windowChanged = windowTitle != lastWindowTitle
        guard appChanged || windowChanged || clipboardChanged else { return }

        lastAppName = appName
        lastWindowTitle = windowTitle

        let clipboardText = NSPasteboard.general.string(forType: .string) ?? ""
        let preview = String(clipboardText.prefix(200))

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let msg = AmbientContextMessage(
            active_app: appName,
            active_window: windowTitle,
            clipboard_preview: preview,
            timestamp: formatter.string(from: Date())
        )

        onChange?(msg)
    }

    /// Read the title of the frontmost window via Accessibility API.
    private func activeWindowTitle(pid: pid_t?) -> String? {
        guard let pid = pid else { return nil }
        let axApp = AXUIElementCreateApplication(pid)

        var windowValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowValue)
        guard result == .success, let window = windowValue else { return nil }

        var titleValue: AnyObject?
        let titleResult = AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &titleValue)
        guard titleResult == .success, let title = titleValue as? String else { return nil }

        return title
    }
}

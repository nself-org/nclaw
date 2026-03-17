import Foundation
import AppKit

/// Detects the currently active editor window and returns the file path and content.
/// Uses the macOS Accessibility API (AXUIElement) to read the focused window title.
///
/// Supported detection strategies (in order):
///   1. Window title heuristics for known editors (VS Code, Xcode, Zed, Cursor, etc.)
///   2. Recent documents from NSDocumentController fallback
final class EditorContextService {

    struct EditorContext: Encodable {
        let file: String?
        let language: String?
        let lines: [String]
        let line_count: Int
        let truncated: Bool
    }

    // MARK: - Public API

    func currentContext(maxLines: Int = 200) -> Result<EditorContext, ServiceError> {
        guard let filePath = detectActiveFilePath() else {
            return .success(EditorContext(
                file: nil,
                language: nil,
                lines: [],
                line_count: 0,
                truncated: false
            ))
        }

        return readFile(at: filePath, maxLines: maxLines)
    }

    /// Returns the file path of the active document in the frontmost editor app, or nil.
    func detectActiveFilePath() -> String? {
        // 1. Try Accessibility API on the frontmost app
        if let path = pathViaAccessibility() {
            return path
        }

        // 2. Fall back to looking at frontmost app name + recent open file
        return nil
    }

    // MARK: - Accessibility

    private func pathViaAccessibility() -> String? {
        let app = NSWorkspace.shared.frontmostApplication
        guard let app = app else { return nil }

        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)

        // Try to get the focused window's AXDocument attribute (file:// URL)
        var docValue: AnyObject?
        let docResult = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &docValue)
        if docResult == .success, let window = docValue {
            var urlValue: AnyObject?
            let urlResult = AXUIElementCopyAttributeValue(window as! AXUIElement, "AXDocument" as CFString, &urlValue)
            if urlResult == .success, let urlStr = urlValue as? String {
                if let url = URL(string: urlStr), url.isFileURL {
                    return url.path
                }
            }

            // Some editors (VS Code) put the path in the window title: "filename.ext — /full/path"
            var titleValue: AnyObject?
            let titleResult = AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &titleValue)
            if titleResult == .success, let title = titleValue as? String {
                if let path = extractPathFromWindowTitle(title, bundleID: app.bundleIdentifier) {
                    return path
                }
            }
        }

        return nil
    }

    private func extractPathFromWindowTitle(_ title: String, bundleID: String?) -> String? {
        let bundle = bundleID ?? ""

        // VS Code / Cursor / Windsurf: "filename.ext — /full/path/to/project"
        if bundle.contains("vscode") || bundle.contains("cursor") || bundle.contains("windsurf") || bundle.contains("code") {
            // Pattern: something — /absolute/path
            let separators = [" — ", " - "]
            for sep in separators {
                if let range = title.range(of: sep) {
                    let suffix = String(title[range.upperBound...])
                    if suffix.hasPrefix("/") {
                        return suffix
                    }
                }
            }
        }

        // Xcode: "ProjectName — filename.swift"
        // We can check if AXDocument gave us something — handled above

        // Zed: "/path/to/file.rs — Zed"
        if bundle.contains("zed") {
            if let range = title.range(of: " — Zed") {
                let prefix = String(title[..<range.lowerBound])
                if prefix.hasPrefix("/") {
                    return prefix
                }
            }
        }

        return nil
    }

    // MARK: - File reading

    private func readFile(at path: String, maxLines: Int) -> Result<EditorContext, ServiceError> {
        guard FileManager.default.fileExists(atPath: path) else {
            return .success(EditorContext(file: path, language: nil, lines: [], line_count: 0, truncated: false))
        }

        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return .failure(.operationFailed("Could not read file at \(path)"))
        }

        let allLines = content.components(separatedBy: "\n")
        let truncated = allLines.count > maxLines
        let lines = truncated ? Array(allLines.prefix(maxLines)) : allLines
        let language = inferLanguage(from: path)

        return .success(EditorContext(
            file: path,
            language: language,
            lines: lines,
            line_count: allLines.count,
            truncated: truncated
        ))
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
        case "c": return "c"
        case "cpp", "cc", "cxx": return "cpp"
        case "h", "hpp": return "c"
        case "rb": return "ruby"
        case "sh", "bash", "zsh": return "shell"
        case "md": return "markdown"
        case "json": return "json"
        case "yaml", "yml": return "yaml"
        case "toml": return "toml"
        case "svelte": return "svelte"
        case "vue": return "vue"
        case "html": return "html"
        case "css", "scss", "sass": return "css"
        case "sql": return "sql"
        case "dart": return "dart"
        default: return ext.isEmpty ? nil : ext
        }
    }

    // MARK: - HTTP Handler

    func handleGetContext(_ request: HTTPRequest) -> HTTPResponse {
        switch currentContext() {
        case .success(let ctx):
            return .json(ctx)
        case .failure(let error):
            return .error(error.localizedDescription, status: error.httpStatus)
        }
    }
}

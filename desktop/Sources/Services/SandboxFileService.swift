import AppKit
import Foundation

/// T-2729: Permission-gated filesystem access for AI tool use.
///
/// Provides safe, read-only-by-default access to user files within approved
/// root directories (~/Desktop, ~/Downloads, ~/Documents). On first access
/// to any root, shows an NSOpenPanel asking the user to grant access.
///
/// Permissions and write-enable flags are persisted in UserDefaults.
final class SandboxFileService {
    private let fileManager = FileManager.default

    /// Default root paths the AI can access (subject to user approval).
    static let defaultRoots: [String] = [
        "~/Desktop",
        "~/Downloads",
        "~/Documents",
    ]

    /// UserDefaults key for granted root paths.
    private static let grantedKey = "NClaw_FS_GrantedRoots"
    /// UserDefaults key for per-path write enable flags.
    private static let writeEnabledKey = "NClaw_FS_WriteEnabled"

    // MARK: - Permission Management

    /// Returns the set of root paths the user has approved.
    var grantedRoots: [String] {
        UserDefaults.standard.stringArray(forKey: Self.grantedKey) ?? []
    }

    /// Whether a specific root has write access enabled.
    func isWriteEnabled(for root: String) -> Bool {
        let dict = UserDefaults.standard.dictionary(forKey: Self.writeEnabledKey) as? [String: Bool] ?? [:]
        let resolved = (root as NSString).expandingTildeInPath
        return dict[resolved] ?? false
    }

    /// Set write enable for a root path.
    func setWriteEnabled(_ enabled: Bool, for root: String) {
        var dict = UserDefaults.standard.dictionary(forKey: Self.writeEnabledKey) as? [String: Bool] ?? [:]
        let resolved = (root as NSString).expandingTildeInPath
        dict[resolved] = enabled
        UserDefaults.standard.set(dict, forKey: Self.writeEnabledKey)
    }

    /// Request user approval for a root path via NSOpenPanel.
    /// Must be called on the main thread. Returns true if the user approved.
    @MainActor
    func requestAccess(to root: String) -> Bool {
        let resolved = (root as NSString).expandingTildeInPath

        // Already granted?
        if grantedRoots.contains(resolved) { return true }

        let panel = NSOpenPanel()
        panel.title = "Grant nClaw Access"
        panel.message = "nClaw AI assistant wants to access files in \(root). Select the folder to grant read access."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: resolved)
        panel.prompt = "Grant Access"

        let response = panel.runModal()
        guard response == .OK, let selectedURL = panel.url else {
            ClawLogger.info("[sandbox-fs] User denied access to \(root)")
            return false
        }

        // Verify the selected path matches the requested root.
        let selectedPath = selectedURL.path
        let standardizedSelected = (selectedPath as NSString).standardizingPath
        let standardizedRoot = (resolved as NSString).standardizingPath

        if standardizedSelected != standardizedRoot {
            ClawLogger.warning("[sandbox-fs] User selected \(selectedPath) instead of \(resolved)")
            // Accept whatever they selected as long as it's a real directory.
        }

        // Store the granted path.
        var granted = grantedRoots
        let pathToStore = standardizedSelected
        if !granted.contains(pathToStore) {
            granted.append(pathToStore)
            UserDefaults.standard.set(granted, forKey: Self.grantedKey)
        }

        ClawLogger.info("[sandbox-fs] Access granted to \(pathToStore)")
        return true
    }

    // MARK: - Path Validation

    /// Validate that a path is within a granted root. Returns the resolved path or nil.
    func validatePath(_ path: String) -> String? {
        let resolved = (path as NSString).expandingTildeInPath
        let standardized = (resolved as NSString).standardizingPath

        // Prevent path traversal.
        if standardized.contains("/../") || standardized.hasSuffix("/..") {
            return nil
        }

        for root in grantedRoots {
            if standardized.hasPrefix(root) {
                return standardized
            }
        }

        return nil
    }

    // MARK: - File Operations

    /// List files in a directory within an approved root.
    /// Returns an array of file entry dictionaries.
    func listFiles(path: String) -> Result<[[String: Any]], SandboxFSError> {
        guard let resolved = validatePath(path) else {
            return .failure(.accessDenied(path))
        }

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: resolved, isDirectory: &isDir), isDir.boolValue else {
            return .failure(.notFound(resolved))
        }

        do {
            let items = try fileManager.contentsOfDirectory(atPath: resolved)
            let formatter = ISO8601DateFormatter()
            var entries: [[String: Any]] = []

            for item in items {
                let fullPath = (resolved as NSString).appendingPathComponent(item)
                let attrs = try fileManager.attributesOfItem(atPath: fullPath)
                let fileType = attrs[.type] as? FileAttributeType
                let size = (attrs[.size] as? UInt64) ?? 0
                let modified = (attrs[.modificationDate] as? Date) ?? Date()

                let typeName: String
                if fileType == .typeDirectory {
                    typeName = "directory"
                } else if fileType == .typeSymbolicLink {
                    typeName = "symlink"
                } else {
                    typeName = "file"
                }

                entries.append([
                    "name": item,
                    "type": typeName,
                    "size": Int(size),
                    "modified": formatter.string(from: modified),
                    "path": fullPath,
                ])
            }

            return .success(entries)
        } catch {
            return .failure(.operationFailed(error.localizedDescription))
        }
    }

    /// Read a file within an approved root.
    /// Returns text content for text files, base64 for binary files.
    func readFile(path: String) -> Result<[String: Any], SandboxFSError> {
        guard let resolved = validatePath(path) else {
            return .failure(.accessDenied(path))
        }

        guard fileManager.fileExists(atPath: resolved) else {
            return .failure(.notFound(resolved))
        }

        // Max 10MB.
        do {
            let attrs = try fileManager.attributesOfItem(atPath: resolved)
            let fileSize = (attrs[.size] as? UInt64) ?? 0
            if fileSize > 10 * 1024 * 1024 {
                return .failure(.tooLarge(resolved, fileSize))
            }

            let data = try Data(contentsOf: URL(fileURLWithPath: resolved))

            // Try text first.
            if let text = String(data: data, encoding: .utf8) {
                return .success([
                    "content": text,
                    "encoding": "utf-8",
                    "size": Int(fileSize),
                    "path": resolved,
                ])
            }

            // Fall back to base64 for binary.
            return .success([
                "content": data.base64EncodedString(),
                "encoding": "base64",
                "size": Int(fileSize),
                "path": resolved,
            ])
        } catch {
            return .failure(.operationFailed(error.localizedDescription))
        }
    }

    /// Search for files matching a query string within an approved root.
    /// Performs a case-insensitive name match.
    func searchFiles(query: String, path: String, maxResults: Int = 50) -> Result<[[String: Any]], SandboxFSError> {
        guard let resolved = validatePath(path) else {
            return .failure(.accessDenied(path))
        }

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: resolved, isDirectory: &isDir), isDir.boolValue else {
            return .failure(.notFound(resolved))
        }

        let lowerQuery = query.lowercased()
        var results: [[String: Any]] = []
        let formatter = ISO8601DateFormatter()

        // Recursive enumeration.
        guard let enumerator = fileManager.enumerator(atPath: resolved) else {
            return .failure(.operationFailed("Failed to enumerate \(resolved)"))
        }

        while let relativePath = enumerator.nextObject() as? String {
            if results.count >= maxResults { break }

            let filename = (relativePath as NSString).lastPathComponent
            if filename.lowercased().contains(lowerQuery) {
                let fullPath = (resolved as NSString).appendingPathComponent(relativePath)
                if let attrs = try? fileManager.attributesOfItem(atPath: fullPath) {
                    let fileType = attrs[.type] as? FileAttributeType
                    let size = (attrs[.size] as? UInt64) ?? 0
                    let modified = (attrs[.modificationDate] as? Date) ?? Date()

                    results.append([
                        "name": filename,
                        "path": fullPath,
                        "relativePath": relativePath,
                        "type": fileType == .typeDirectory ? "directory" : "file",
                        "size": Int(size),
                        "modified": formatter.string(from: modified),
                    ])
                }
            }
        }

        return .success(results)
    }
}

// MARK: - Errors

enum SandboxFSError: Error, LocalizedError {
    case accessDenied(String)
    case notFound(String)
    case tooLarge(String, UInt64)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied(let path):
            return "Access denied: \(path) is not within an approved directory"
        case .notFound(let path):
            return "Not found: \(path)"
        case .tooLarge(let path, let size):
            return "File too large: \(path) (\(size) bytes, max 10MB)"
        case .operationFailed(let reason):
            return "Operation failed: \(reason)"
        }
    }

    var httpStatus: Int {
        switch self {
        case .accessDenied: return 403
        case .notFound: return 404
        case .tooLarge: return 413
        case .operationFailed: return 500
        }
    }
}

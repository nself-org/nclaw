import Foundation

/// HTTP endpoint handlers for file operations.
/// Delegates to FileService for sandbox-enforced I/O, then formats
/// rich JSON responses per the daemon API contract.
final class FileEndpoints {
    private let fileService = FileService()
    private let fileManager = FileManager.default

    // MARK: - POST /files/read

    /// Read file contents (max 10 MB).
    /// Request: { "path": "/abs/path" }
    /// Response: { "content": string, "size": number, "modified": string }
    func handleRead(_ request: HTTPRequest) -> HTTPResponse {
        struct Params: Decodable { let path: String }
        guard let params = request.jsonBody(as: Params.self) else {
            return .error("Missing 'path' in request body")
        }

        let maxSize: UInt64 = 10 * 1024 * 1024 // 10 MB

        // Validate sandbox first
        guard let resolved = fileService.resolvedPath(params.path) else {
            return .error("Path is outside the allowed sandbox: \(params.path)", status: 403)
        }

        guard fileManager.fileExists(atPath: resolved) else {
            return .error("File not found: \(resolved)", status: 404)
        }

        // Check file size before reading
        do {
            let attrs = try fileManager.attributesOfItem(atPath: resolved)
            let fileSize = (attrs[.size] as? UInt64) ?? 0
            if fileSize > maxSize {
                return .error("File exceeds 10 MB limit (\(fileSize) bytes)", status: 413)
            }

            let modified = (attrs[.modificationDate] as? Date) ?? Date()
            let content = try String(contentsOfFile: resolved, encoding: .utf8)

            let response = ReadResponse(
                content: content,
                size: Int(fileSize),
                modified: ISO8601DateFormatter().string(from: modified)
            )

            ClawLogger.info("[files/read] \(resolved) (\(fileSize) bytes)")
            return .json(response)
        } catch {
            return .error("Read failed: \(error.localizedDescription)", status: 500)
        }
    }

    // MARK: - POST /files/write

    /// Write content to a file (creates parent dirs as needed).
    /// Request: { "path": "/abs/path", "content": "..." }
    /// Response: { "success": true }
    func handleWrite(_ request: HTTPRequest) -> HTTPResponse {
        struct Params: Decodable { let path: String; let content: String }
        guard let params = request.jsonBody(as: Params.self) else {
            return .error("Missing 'path' and 'content' in request body")
        }

        switch fileService.writeFile(path: params.path, content: params.content) {
        case .success:
            ClawLogger.info("[files/write] \(params.path) (\(params.content.count) chars)")
            return .json(SuccessResponse(success: true))
        case .failure(let error):
            return .error(error.localizedDescription, status: error.httpStatus)
        }
    }

    // MARK: - POST /files/list

    /// List directory contents with metadata.
    /// Request: { "path": "/abs/path" }
    /// Response: { "entries": [{ "name", "type", "size", "modified" }] }
    func handleList(_ request: HTTPRequest) -> HTTPResponse {
        struct Params: Decodable { let path: String }
        guard let params = request.jsonBody(as: Params.self) else {
            return .error("Missing 'path' in request body")
        }

        guard let resolved = fileService.resolvedPath(params.path) else {
            return .error("Path is outside the allowed sandbox: \(params.path)", status: 403)
        }

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: resolved, isDirectory: &isDir), isDir.boolValue else {
            return .error("Directory not found: \(resolved)", status: 404)
        }

        do {
            let items = try fileManager.contentsOfDirectory(atPath: resolved)
            let formatter = ISO8601DateFormatter()
            var entries: [DirectoryEntry] = []

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

                entries.append(DirectoryEntry(
                    name: item,
                    type: typeName,
                    size: Int(size),
                    modified: formatter.string(from: modified)
                ))
            }

            ClawLogger.info("[files/list] \(resolved) (\(entries.count) entries)")
            return .json(ListResponse(entries: entries))
        } catch {
            return .error("List failed: \(error.localizedDescription)", status: 500)
        }
    }

    // MARK: - POST /files/delete

    /// Delete a file or directory.
    /// Request: { "path": "/abs/path" }
    /// Response: { "success": true }
    func handleDelete(_ request: HTTPRequest) -> HTTPResponse {
        struct Params: Decodable { let path: String }
        guard let params = request.jsonBody(as: Params.self) else {
            return .error("Missing 'path' in request body")
        }

        switch fileService.deleteFile(path: params.path) {
        case .success:
            ClawLogger.info("[files/delete] \(params.path)")
            return .json(SuccessResponse(success: true))
        case .failure(let error):
            return .error(error.localizedDescription, status: error.httpStatus)
        }
    }

    // MARK: - POST /files/mkdir

    /// Create a directory (optionally recursive).
    /// Request: { "path": "/abs/path", "recursive": true }
    /// Response: { "success": true }
    func handleMkdir(_ request: HTTPRequest) -> HTTPResponse {
        struct Params: Decodable {
            let path: String
            let recursive: Bool?
        }
        guard let params = request.jsonBody(as: Params.self) else {
            return .error("Missing 'path' in request body")
        }

        let useRecursive = params.recursive ?? true

        guard let resolved = fileService.resolvedPath(params.path) else {
            return .error("Path is outside the allowed sandbox: \(params.path)", status: 403)
        }

        do {
            try fileManager.createDirectory(
                atPath: resolved,
                withIntermediateDirectories: useRecursive
            )
            ClawLogger.info("[files/mkdir] \(resolved) (recursive: \(useRecursive))")
            return .json(SuccessResponse(success: true))
        } catch {
            return .error("Mkdir failed: \(error.localizedDescription)", status: 500)
        }
    }
}

// MARK: - Response Types

private struct ReadResponse: Encodable {
    let content: String
    let size: Int
    let modified: String
}

private struct ListResponse: Encodable {
    let entries: [DirectoryEntry]
}

private struct DirectoryEntry: Encodable {
    let name: String
    let type: String
    let size: Int
    let modified: String
}

private struct SuccessResponse: Encodable {
    let success: Bool
}

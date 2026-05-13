import Foundation

/// File operations with sandbox enforcement.
/// All paths must resolve within user-configured allowed directories.
final class FileService {
    private let fileManager = FileManager.default

    /// Allowed directories — defaults to the user's home directory.
    /// Override via UserDefaults key "sandboxPaths" (string array).
    private var allowedPaths: [String] {
        if let arr = UserDefaults.standard.stringArray(forKey: "sandboxPaths"), !arr.isEmpty {
            return arr
        }
        return [NSHomeDirectory()]
    }

    // MARK: - Sandbox Validation

    /// Resolve and validate a path against the sandbox.
    /// Returns the standardized absolute path if within allowed directories, nil otherwise.
    func resolvedPath(_ path: String) -> String? {
        switch validatePath(path) {
        case .success(let resolved): return resolved
        case .failure: return nil
        }
    }

    private func validatePath(_ path: String) -> Result<String, ServiceError> {
        let resolved = (path as NSString).expandingTildeInPath
        let standardized = (resolved as NSString).standardizingPath

        for allowed in allowedPaths {
            let allowedResolved = (allowed as NSString).expandingTildeInPath
            let allowedStandard = (allowedResolved as NSString).standardizingPath
            if standardized.hasPrefix(allowedStandard) {
                return .success(standardized)
            }
        }

        return .failure(.pathOutsideSandbox(path))
    }

    // MARK: - Operations

    func readFile(path: String) -> Result<String, ServiceError> {
        switch validatePath(path) {
        case .failure(let error):
            return .failure(error)
        case .success(let resolved):
            guard fileManager.fileExists(atPath: resolved) else {
                return .failure(.fileNotFound(resolved))
            }
            do {
                let content = try String(contentsOfFile: resolved, encoding: .utf8)
                return .success(content)
            } catch {
                return .failure(.operationFailed("Read failed: \(error.localizedDescription)"))
            }
        }
    }

    func writeFile(path: String, content: String) -> Result<String, ServiceError> {
        switch validatePath(path) {
        case .failure(let error):
            return .failure(error)
        case .success(let resolved):
            do {
                // Create parent directories if needed
                let dir = (resolved as NSString).deletingLastPathComponent
                try fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true)
                try content.write(toFile: resolved, atomically: true, encoding: .utf8)
                return .success("Written \(content.count) characters to \(resolved)")
            } catch {
                return .failure(.operationFailed("Write failed: \(error.localizedDescription)"))
            }
        }
    }

    func listDirectory(path: String) -> Result<String, ServiceError> {
        switch validatePath(path) {
        case .failure(let error):
            return .failure(error)
        case .success(let resolved):
            do {
                let items = try fileManager.contentsOfDirectory(atPath: resolved)
                let json = try JSONEncoder().encode(items)
                return .success(String(data: json, encoding: .utf8) ?? "[]")
            } catch {
                return .failure(.operationFailed("List failed: \(error.localizedDescription)"))
            }
        }
    }

    func deleteFile(path: String) -> Result<String, ServiceError> {
        switch validatePath(path) {
        case .failure(let error):
            return .failure(error)
        case .success(let resolved):
            guard fileManager.fileExists(atPath: resolved) else {
                return .failure(.fileNotFound(resolved))
            }
            do {
                try fileManager.removeItem(atPath: resolved)
                return .success("Deleted \(resolved)")
            } catch {
                return .failure(.operationFailed("Delete failed: \(error.localizedDescription)"))
            }
        }
    }

    func makeDirectory(path: String) -> Result<String, ServiceError> {
        switch validatePath(path) {
        case .failure(let error):
            return .failure(error)
        case .success(let resolved):
            do {
                try fileManager.createDirectory(atPath: resolved, withIntermediateDirectories: true)
                return .success("Created directory \(resolved)")
            } catch {
                return .failure(.operationFailed("Mkdir failed: \(error.localizedDescription)"))
            }
        }
    }

    // MARK: - HTTP Handlers

    func handleRead(_ request: HTTPRequest) -> HTTPResponse {
        struct Params: Decodable { let path: String }
        guard let params = request.jsonBody(as: Params.self) else {
            return .error("Missing 'path' in request body")
        }
        switch readFile(path: params.path) {
        case .success(let content):
            return .json(["content": content])
        case .failure(let error):
            return .error(error.localizedDescription, status: error.httpStatus)
        }
    }

    func handleWrite(_ request: HTTPRequest) -> HTTPResponse {
        struct Params: Decodable { let path: String; let content: String }
        guard let params = request.jsonBody(as: Params.self) else {
            return .error("Missing 'path' and 'content' in request body")
        }
        switch writeFile(path: params.path, content: params.content) {
        case .success(let msg):
            return .json(["message": msg])
        case .failure(let error):
            return .error(error.localizedDescription, status: error.httpStatus)
        }
    }

    func handleList(_ request: HTTPRequest) -> HTTPResponse {
        struct Params: Decodable { let path: String }
        guard let params = request.jsonBody(as: Params.self) else {
            return .error("Missing 'path' in request body")
        }
        switch listDirectory(path: params.path) {
        case .success(let json):
            // Already JSON array string, wrap it
            return HTTPResponse(status: 200, body: json.data(using: .utf8))
        case .failure(let error):
            return .error(error.localizedDescription, status: error.httpStatus)
        }
    }

    func handleDelete(_ request: HTTPRequest) -> HTTPResponse {
        struct Params: Decodable { let path: String }
        guard let params = request.jsonBody(as: Params.self) else {
            return .error("Missing 'path' in request body")
        }
        switch deleteFile(path: params.path) {
        case .success(let msg):
            return .json(["message": msg])
        case .failure(let error):
            return .error(error.localizedDescription, status: error.httpStatus)
        }
    }

    func handleMkdir(_ request: HTTPRequest) -> HTTPResponse {
        struct Params: Decodable { let path: String }
        guard let params = request.jsonBody(as: Params.self) else {
            return .error("Missing 'path' in request body")
        }
        switch makeDirectory(path: params.path) {
        case .success(let msg):
            return .json(["message": msg])
        case .failure(let error):
            return .error(error.localizedDescription, status: error.httpStatus)
        }
    }
}

// MARK: - ServiceError HTTP Status

extension ServiceError {
    var httpStatus: Int {
        switch self {
        case .pathOutsideSandbox: return 403
        case .fileNotFound: return 404
        case .permissionDenied: return 403
        case .operationFailed: return 500
        case .userDenied: return 403
        case .notImplemented: return 501
        }
    }
}

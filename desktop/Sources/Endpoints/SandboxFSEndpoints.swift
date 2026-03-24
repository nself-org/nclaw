import Foundation

/// T-2729: HTTP endpoints for permission-gated filesystem access.
///
/// These endpoints expose the SandboxFileService via the companion's
/// local HTTP server for use as AI tools.
///
/// Routes:
///   GET /companion/fs/list?path=~/Downloads     → JSON array of file entries
///   GET /companion/fs/read?path=~/Downloads/x   → file content (text or base64)
///   GET /companion/fs/search?query=invoice&path= → matching file paths
///   GET /companion/fs/roots                      → granted root paths + write flags
///   POST /companion/fs/grant                     → request access to a new root
final class SandboxFSEndpoints {
    private let fsService = SandboxFileService()

    // MARK: - GET /companion/fs/list

    /// List files in a directory. Path must be within an approved root.
    /// Query: ?path=~/Downloads
    /// Response: { "entries": [{ "name", "type", "size", "modified", "path" }] }
    func handleList(_ request: HTTPRequest) -> HTTPResponse {
        guard let path = extractQueryParam(from: request.path, key: "path") else {
            return .error("Missing 'path' query parameter")
        }

        switch fsService.listFiles(path: path) {
        case .success(let entries):
            let data = try? JSONSerialization.data(withJSONObject: ["entries": entries])
            ClawLogger.info("[fs/list] \(path) → \(entries.count) entries")
            return HTTPResponse(status: 200, body: data)
        case .failure(let error):
            return .error(error.localizedDescription, status: error.httpStatus)
        }
    }

    // MARK: - GET /companion/fs/read

    /// Read a file. Returns text (UTF-8) or base64 for binary.
    /// Query: ?path=~/Downloads/invoice.pdf
    /// Response: { "content": "...", "encoding": "utf-8"|"base64", "size": N, "path": "..." }
    func handleRead(_ request: HTTPRequest) -> HTTPResponse {
        guard let path = extractQueryParam(from: request.path, key: "path") else {
            return .error("Missing 'path' query parameter")
        }

        switch fsService.readFile(path: path) {
        case .success(let result):
            let data = try? JSONSerialization.data(withJSONObject: result)
            let size = result["size"] as? Int ?? 0
            ClawLogger.info("[fs/read] \(path) (\(size) bytes)")
            return HTTPResponse(status: 200, body: data)
        case .failure(let error):
            return .error(error.localizedDescription, status: error.httpStatus)
        }
    }

    // MARK: - GET /companion/fs/search

    /// Search for files by name within an approved directory.
    /// Query: ?query=invoice&path=~/Documents
    /// Response: { "results": [{ "name", "path", "relativePath", "type", "size", "modified" }] }
    func handleSearch(_ request: HTTPRequest) -> HTTPResponse {
        guard let query = extractQueryParam(from: request.path, key: "query") else {
            return .error("Missing 'query' query parameter")
        }
        guard let path = extractQueryParam(from: request.path, key: "path") else {
            return .error("Missing 'path' query parameter")
        }

        switch fsService.searchFiles(query: query, path: path) {
        case .success(let results):
            let data = try? JSONSerialization.data(withJSONObject: ["results": results])
            ClawLogger.info("[fs/search] q='\(query)' in \(path) → \(results.count) results")
            return HTTPResponse(status: 200, body: data)
        case .failure(let error):
            return .error(error.localizedDescription, status: error.httpStatus)
        }
    }

    // MARK: - GET /companion/fs/roots

    /// List granted root paths and their write-enable status.
    /// Response: { "roots": [{ "path": "...", "writeEnabled": false }] }
    func handleRoots(_ request: HTTPRequest) -> HTTPResponse {
        let roots = fsService.grantedRoots.map { root -> [String: Any] in
            [
                "path": root,
                "writeEnabled": fsService.isWriteEnabled(for: root),
            ]
        }
        let defaultRoots = SandboxFileService.defaultRoots.map { root -> [String: Any] in
            let resolved = (root as NSString).expandingTildeInPath
            let granted = fsService.grantedRoots.contains(resolved)
            return [
                "path": root,
                "resolved": resolved,
                "granted": granted,
                "writeEnabled": granted ? fsService.isWriteEnabled(for: resolved) : false,
            ]
        }
        let data = try? JSONSerialization.data(withJSONObject: [
            "granted": roots,
            "available": defaultRoots,
        ])
        return HTTPResponse(status: 200, body: data)
    }

    // MARK: - POST /companion/fs/grant

    /// Request user permission to access a root directory.
    /// Request body: { "path": "~/Downloads" }
    /// Response: { "granted": true }
    func handleGrant(_ request: HTTPRequest) -> HTTPResponse {
        struct Params: Decodable { let path: String }
        guard let params = request.jsonBody(as: Params.self) else {
            return .error("Missing 'path' in request body")
        }

        // NSOpenPanel must run on main thread.
        var granted = false
        DispatchQueue.main.sync {
            granted = fsService.requestAccess(to: params.path)
        }

        let data = try? JSONSerialization.data(withJSONObject: ["granted": granted])
        return HTTPResponse(status: granted ? 200 : 403, body: data)
    }

    // MARK: - Helpers

    /// Extract a query parameter from the request path.
    /// "/companion/fs/list?path=~/Downloads&limit=10" → "~/Downloads" for key "path"
    private func extractQueryParam(from path: String, key: String) -> String? {
        guard let queryStart = path.firstIndex(of: "?") else { return nil }
        let queryString = String(path[path.index(after: queryStart)...])
        let pairs = queryString.components(separatedBy: "&")
        for pair in pairs {
            let parts = pair.components(separatedBy: "=")
            if parts.count == 2 && parts[0] == key {
                return parts[1].removingPercentEncoding ?? parts[1]
            }
        }
        return nil
    }
}

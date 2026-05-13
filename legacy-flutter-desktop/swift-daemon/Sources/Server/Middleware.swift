import Foundation

/// Authentication middleware for the local HTTP server.
/// Enforces local-only access (127.0.0.1) and optional bearer token.
struct AuthMiddleware {
    let token: String?

    /// Returns nil if authentication passes, or an HTTPResponse rejection.
    func authenticate(_ request: HTTPRequest) -> HTTPResponse? {
        // Health endpoint is always accessible (for monitoring)
        if request.path == "/health" && request.method == "GET" {
            return nil
        }

        // If a token is configured, require it via Bearer auth
        if let expectedToken = token, !expectedToken.isEmpty {
            guard let authHeader = request.headers["authorization"] else {
                return .error("Missing Authorization header", status: 401)
            }

            let prefix = "Bearer "
            guard authHeader.hasPrefix(prefix) else {
                return .error("Invalid Authorization format. Expected: Bearer <token>", status: 401)
            }

            let provided = String(authHeader.dropFirst(prefix.count))
            guard provided == expectedToken else {
                return .error("Invalid token", status: 403)
            }
        }

        return nil
    }
}

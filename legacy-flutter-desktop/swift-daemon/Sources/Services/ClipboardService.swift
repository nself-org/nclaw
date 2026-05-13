import Foundation
import AppKit

/// Clipboard read/write via NSPasteboard.
final class ClipboardService {

    func read() -> Result<String, ServiceError> {
        guard let content = NSPasteboard.general.string(forType: .string) else {
            return .success("") // Empty clipboard is not an error
        }
        return .success(content)
    }

    func write(_ content: String) -> Result<String, ServiceError> {
        NSPasteboard.general.clearContents()
        let success = NSPasteboard.general.setString(content, forType: .string)
        if success {
            return .success("Clipboard updated (\(content.count) characters)")
        } else {
            return .failure(.operationFailed("Failed to write to clipboard"))
        }
    }

    // MARK: - HTTP Handlers

    func handleRead() -> HTTPResponse {
        switch read() {
        case .success(let content):
            return .json(["content": content])
        case .failure(let error):
            return .error(error.localizedDescription, status: error.httpStatus)
        }
    }

    func handleWrite(_ request: HTTPRequest) -> HTTPResponse {
        struct Params: Decodable { let content: String }
        guard let params = request.jsonBody(as: Params.self) else {
            return .error("Missing 'content' in request body")
        }
        switch write(params.content) {
        case .success(let msg):
            return .json(["message": msg])
        case .failure(let error):
            return .error(error.localizedDescription, status: error.httpStatus)
        }
    }

    /// T-1351: POST /clipboard — body: {"text": "..."}
    func handleWriteText(_ request: HTTPRequest) -> HTTPResponse {
        struct Params: Decodable { let text: String }
        guard let params = request.jsonBody(as: Params.self) else {
            return .error("Missing 'text' in request body")
        }
        switch write(params.text) {
        case .success(let msg):
            return .json(["message": msg])
        case .failure(let error):
            return .error(error.localizedDescription, status: error.httpStatus)
        }
    }
}

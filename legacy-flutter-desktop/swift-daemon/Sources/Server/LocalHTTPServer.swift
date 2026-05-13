import Foundation
import Network

/// Minimal HTTP server using Network.framework (NWListener).
/// Binds to 127.0.0.1 only. Parses simple JSON POST requests.
final class LocalHTTPServer {
    private var listener: NWListener?
    private let port: UInt16
    private let router: RouteHandler
    private let authMiddleware: AuthMiddleware
    private let queue = DispatchQueue(label: "org.nself.nclaw.httpserver", qos: .userInitiated)

    var isRunning: Bool { listener != nil }

    init(port: UInt16 = 7710, token: String? = nil) {
        self.port = port
        self.router = RouteHandler()
        self.authMiddleware = AuthMiddleware(token: token)
    }

    func start() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: port)!
        )

        let nwListener = try NWListener(using: params)
        nwListener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ClawLogger.info("HTTP server listening on 127.0.0.1:\(self.port)")
            case .failed(let error):
                ClawLogger.error("HTTP server failed: \(error)")
            default:
                break
            }
        }

        nwListener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        nwListener.start(queue: queue)
        self.listener = nwListener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        ClawLogger.info("HTTP server stopped")
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHTTPRequest(connection: connection)
    }

    private func receiveHTTPRequest(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                ClawLogger.error("Connection receive error: \(error)")
                connection.cancel()
                return
            }

            guard let data = content else {
                if isComplete { connection.cancel() }
                return
            }

            let request = self.parseHTTPRequest(data)
            self.processRequest(request, connection: connection)
        }
    }

    private func parseHTTPRequest(_ data: Data) -> HTTPRequest {
        guard let raw = String(data: data, encoding: .utf8) else {
            return HTTPRequest(method: "GET", path: "/", headers: [:], body: nil)
        }

        let lines = raw.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return HTTPRequest(method: "GET", path: "/", headers: [:], body: nil)
        }

        let parts = requestLine.components(separatedBy: " ")
        let method = parts.count > 0 ? parts[0] : "GET"
        let path = parts.count > 1 ? parts[1] : "/"

        var headers: [String: String] = [:]
        var bodyStartIndex: Int?

        for (index, line) in lines.dropFirst().enumerated() {
            if line.isEmpty {
                bodyStartIndex = index + 2 // +1 for dropFirst, +1 for next line
                break
            }
            let headerParts = line.split(separator: ":", maxSplits: 1)
            if headerParts.count == 2 {
                let key = headerParts[0].trimmingCharacters(in: .whitespaces).lowercased()
                let value = headerParts[1].trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        var body: Data?
        if let startIdx = bodyStartIndex, startIdx < lines.count {
            let bodyString = lines[startIdx...].joined(separator: "\r\n")
            body = bodyString.data(using: .utf8)
        }

        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }

    private func processRequest(_ request: HTTPRequest, connection: NWConnection) {
        // Auth check
        if let rejection = authMiddleware.authenticate(request) {
            sendResponse(rejection, connection: connection)
            return
        }

        let response = router.handle(request)
        sendResponse(response, connection: connection)
    }

    private func sendResponse(_ response: HTTPResponse, connection: NWConnection) {
        let statusText: String
        switch response.status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 401: statusText = "Unauthorized"
        case 403: statusText = "Forbidden"
        case 404: statusText = "Not Found"
        case 405: statusText = "Method Not Allowed"
        case 500: statusText = "Internal Server Error"
        default: statusText = "Unknown"
        }

        let body = response.body ?? Data()
        var header = "HTTP/1.1 \(response.status) \(statusText)\r\n"
        header += "Content-Type: application/json\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Connection: close\r\n"
        header += "\r\n"

        var responseData = header.data(using: .utf8) ?? Data()
        responseData.append(body)

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

// MARK: - HTTP Types

struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data?

    func jsonBody<T: Decodable>(as type: T.Type) -> T? {
        guard let body = body else { return nil }
        return try? JSONDecoder().decode(type, from: body)
    }
}

struct HTTPResponse {
    let status: Int
    let body: Data?

    static func json(_ value: some Encodable, status: Int = 200) -> HTTPResponse {
        let data = try? JSONEncoder().encode(value)
        return HTTPResponse(status: status, body: data)
    }

    static func error(_ message: String, status: Int = 400) -> HTTPResponse {
        let body: [String: String] = ["error": message]
        let data = try? JSONEncoder().encode(body)
        return HTTPResponse(status: status, body: data)
    }
}

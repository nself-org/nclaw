import Foundation

/// HTTP endpoint handlers for browser automation via Chrome DevTools Protocol.
/// Delegates to BrowserService for all CDP communication.
enum BrowserEndpoints {

    // MARK: - POST /browser/open

    struct OpenRequest: Decodable {
        let url: String
    }

    struct OpenResponse: Encodable {
        let success: Bool
        let tabId: String?
    }

    static func handleOpen(_ request: HTTPRequest, service: BrowserService) -> HTTPResponse {
        guard let params = request.jsonBody(as: OpenRequest.self) else {
            return .error("Missing 'url' in request body")
        }

        guard let _ = URL(string: params.url) else {
            return .error("Invalid URL: \(params.url)")
        }

        ClawLogger.info("Browser open: \(params.url)")

        switch service.navigateToURL(params.url) {
        case .success(let tabId):
            return .json(OpenResponse(success: true, tabId: tabId))
        case .failure(let error):
            return .error(error.localizedDescription, status: error.httpStatus)
        }
    }

    // MARK: - POST /browser/screenshot

    struct ScreenshotRequest: Decodable {
        let tabId: String?
    }

    struct ScreenshotResponse: Encodable {
        let image: String
    }

    static func handleScreenshot(_ request: HTTPRequest, service: BrowserService) -> HTTPResponse {
        let params = request.jsonBody(as: ScreenshotRequest.self)
        let tabId = params?.tabId

        ClawLogger.info("Browser screenshot (tab: \(tabId ?? "active"))")

        switch service.captureScreenshot(tabId: tabId) {
        case .success(let base64):
            return .json(ScreenshotResponse(image: base64))
        case .failure(let error):
            return .error(error.localizedDescription, status: error.httpStatus)
        }
    }

    // MARK: - POST /browser/execute

    struct ExecuteRequest: Decodable {
        let expression: String
        let tabId: String?
    }

    struct ExecuteResponse: Encodable {
        let result: JSONValue
        let exceptionDetails: String?
    }

    static func handleExecute(_ request: HTTPRequest, service: BrowserService) -> HTTPResponse {
        guard let params = request.jsonBody(as: ExecuteRequest.self) else {
            return .error("Missing 'expression' in request body")
        }

        ClawLogger.info("Browser execute: \(String(params.expression.prefix(100)))")

        switch service.executeScript(expression: params.expression, tabId: params.tabId) {
        case .success(let cdpResult):
            let evalResult = cdpResult["result"] as? [String: Any] ?? [:]
            let value = evalResult["value"]
            let exceptionDetails = cdpResult["exceptionDetails"] as? [String: Any]
            let exceptionText = exceptionDetails?["text"] as? String

            return .json(ExecuteResponse(
                result: JSONValue(value),
                exceptionDetails: exceptionText
            ))
        case .failure(let error):
            return .error(error.localizedDescription, status: error.httpStatus)
        }
    }

    // MARK: - GET /browser/tabs

    static func handleTabs(_ request: HTTPRequest, service: BrowserService) -> HTTPResponse {
        switch service.listTabs() {
        case .success(let tabs):
            let simplified = tabs.filter { ($0["type"] as? String) == "page" }
                .map { tab -> [String: Any] in
                    var out: [String: Any] = [:]
                    if let id = tab["id"] { out["id"] = id }
                    if let title = tab["title"] { out["title"] = title }
                    if let url = tab["url"] { out["url"] = url }
                    return out
                }
            struct TabsResponse: Encodable {
                let tabs: [JSONValue]
            }
            return .json(TabsResponse(tabs: simplified.map { JSONValue($0) }))
        case .failure(let error):
            return .error(error.localizedDescription, status: error.httpStatus)
        }
    }

    // MARK: - GET /browser/cookies

    static func handleCookies(_ request: HTTPRequest, service: BrowserService) -> HTTPResponse {
        let params = request.jsonBody(as: ScreenshotRequest.self)
        switch service.getCookies(tabId: params?.tabId) {
        case .success(let cookies):
            struct CookiesResponse: Encodable {
                let cookies: [JSONValue]
            }
            return .json(CookiesResponse(cookies: cookies.map { JSONValue($0) }))
        case .failure(let error):
            return .error(error.localizedDescription, status: error.httpStatus)
        }
    }

    // MARK: - POST /browser/extract

    struct ExtractRequest: Decodable {
        let selector: String?
        let tabId: String?
    }

    static func handleExtract(_ request: HTTPRequest, service: BrowserService) -> HTTPResponse {
        let params = request.jsonBody(as: ExtractRequest.self)
        switch service.extractContent(selector: params?.selector, tabId: params?.tabId) {
        case .success(let elements):
            struct ElementsResponse: Encodable {
                let elements: [JSONValue]
            }
            return .json(ElementsResponse(elements: elements.map { JSONValue($0) }))
        case .failure(let error):
            return .error(error.localizedDescription, status: error.httpStatus)
        }
    }

    // MARK: - POST /browser/action (unified dispatcher)

    struct ActionRequest: Decodable {
        let action: String
        let url: String?
        let selector: String?
        let value: String?
        let expression: String?
        let tabId: String?
        let timeout: Double?
    }

    static func handleAction(_ request: HTTPRequest, service: BrowserService) -> HTTPResponse {
        guard let params = request.jsonBody(as: ActionRequest.self) else {
            return .error("Missing 'action' in request body")
        }

        switch params.action {
        case "navigate":
            guard let urlStr = params.url else { return .error("Missing 'url'") }
            switch service.navigateToURL(urlStr) {
            case .success(let tabId):
                return .json(OpenResponse(success: true, tabId: tabId))
            case .failure(let e):
                return .error(e.localizedDescription, status: e.httpStatus)
            }
        case "click":
            guard let sel = params.selector else { return .error("Missing 'selector'") }
            switch service.clickElement(selector: sel, tabId: params.tabId) {
            case .success:
                return .json(SuccessResponse(success: true))
            case .failure(let e):
                return .error(e.localizedDescription, status: e.httpStatus)
            }
        case "type":
            guard let sel = params.selector, let val = params.value else {
                return .error("Missing 'selector' or 'value'")
            }
            switch service.fillField(selector: sel, value: val, tabId: params.tabId) {
            case .success:
                return .json(SuccessResponse(success: true))
            case .failure(let e):
                return .error(e.localizedDescription, status: e.httpStatus)
            }
        case "extract":
            switch service.extractContent(selector: params.selector, tabId: params.tabId) {
            case .success(let elements):
                struct ElementsResponse: Encodable {
                    let elements: [JSONValue]
                }
                return .json(ElementsResponse(elements: elements.map { JSONValue($0) }))
            case .failure(let e):
                return .error(e.localizedDescription, status: e.httpStatus)
            }
        case "screenshot":
            switch service.captureScreenshot(tabId: params.tabId) {
            case .success(let data):
                return .json(["image": data])
            case .failure(let e):
                return .error(e.localizedDescription, status: e.httpStatus)
            }
        case "wait_for":
            let timeout = params.timeout ?? 10.0
            switch service.waitFor(selector: params.selector, url: params.url, timeout: timeout) {
            case .success(let found):
                return .json(["found": found])
            case .failure(let e):
                return .error(e.localizedDescription, status: e.httpStatus)
            }
        case "evaluate":
            guard let expr = params.expression else { return .error("Missing 'expression'") }
            switch service.executeScript(expression: expr, tabId: params.tabId) {
            case .success(let result):
                let evalResult = result["result"] as? [String: Any] ?? [:]
                let value = evalResult["value"]
                let exceptionDetails = (result["exceptionDetails"] as? [String: Any])?["text"] as? String
                return .json(ExecuteResponse(result: JSONValue(value), exceptionDetails: exceptionDetails))
            case .failure(let e):
                return .error(e.localizedDescription, status: e.httpStatus)
            }
        case "get_cookies":
            switch service.getCookies(tabId: params.tabId) {
            case .success(let cookies):
                struct CookiesResponse: Encodable {
                    let cookies: [JSONValue]
                }
                return .json(CookiesResponse(cookies: cookies.map { JSONValue($0) }))
            case .failure(let e):
                return .error(e.localizedDescription, status: e.httpStatus)
            }
        default:
            return .error("Unknown action '\(params.action)'", status: 400)
        }
    }

    // MARK: - POST /browser/fill

    struct FillRequest: Decodable {
        let selector: String
        let value: String
        let tabId: String?
    }

    struct SuccessResponse: Encodable {
        let success: Bool
    }

    static func handleFill(_ request: HTTPRequest, service: BrowserService) -> HTTPResponse {
        guard let params = request.jsonBody(as: FillRequest.self) else {
            return .error("Missing 'selector' and 'value' in request body")
        }

        ClawLogger.info("Browser fill: \(params.selector)")

        switch service.fillField(selector: params.selector, value: params.value, tabId: params.tabId) {
        case .success:
            return .json(SuccessResponse(success: true))
        case .failure(let error):
            return .error(error.localizedDescription, status: error.httpStatus)
        }
    }

    // MARK: - POST /browser/click

    struct ClickRequest: Decodable {
        let selector: String
        let tabId: String?
    }

    static func handleClick(_ request: HTTPRequest, service: BrowserService) -> HTTPResponse {
        guard let params = request.jsonBody(as: ClickRequest.self) else {
            return .error("Missing 'selector' in request body")
        }

        ClawLogger.info("Browser click: \(params.selector)")

        switch service.clickElement(selector: params.selector, tabId: params.tabId) {
        case .success:
            return .json(SuccessResponse(success: true))
        case .failure(let error):
            return .error(error.localizedDescription, status: error.httpStatus)
        }
    }

    // MARK: - POST /browser/wait

    struct WaitRequest: Decodable {
        let selector: String?
        let url: String?
        let timeout: Double?
    }

    struct WaitResponse: Encodable {
        let found: Bool
    }

    static func handleWait(_ request: HTTPRequest, service: BrowserService) -> HTTPResponse {
        guard let params = request.jsonBody(as: WaitRequest.self) else {
            return .error("Missing request body")
        }

        guard params.selector != nil || params.url != nil else {
            return .error("At least one of 'selector' or 'url' must be provided")
        }

        let timeout = params.timeout ?? 10.0
        ClawLogger.info("Browser wait: selector=\(params.selector ?? "nil") url=\(params.url ?? "nil") timeout=\(timeout)s")

        switch service.waitFor(selector: params.selector, url: params.url, timeout: timeout) {
        case .success(let found):
            return .json(WaitResponse(found: found))
        case .failure(let error):
            return .error(error.localizedDescription, status: error.httpStatus)
        }
    }
}

// MARK: - JSONValue

/// Type-erased JSON value for encoding arbitrary CDP results.
struct JSONValue: Encodable {
    private let value: Any?

    init(_ value: Any?) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case nil:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { JSONValue($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { JSONValue($0) })
        default:
            try container.encode(String(describing: value))
        }
    }
}

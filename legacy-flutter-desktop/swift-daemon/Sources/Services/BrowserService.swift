import Foundation

/// Chrome DevTools Protocol client.
/// Connects to Chrome's debug port via WebSocket to control browser tabs.
final class BrowserService {

    private let chromePath = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    private let cdpPort: UInt16 = 9222
    private var messageId: Int = 0

    // MARK: - Chrome Process Management

    /// Ensure Chrome is running with remote debugging enabled.
    /// Returns true if Chrome is ready for CDP connections.
    func ensureChromeRunning() -> Result<Bool, ServiceError> {
        if isCDPAvailable() {
            return .success(true)
        }

        guard FileManager.default.fileExists(atPath: chromePath) else {
            return .failure(.operationFailed("Chrome not found at \(chromePath)"))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: chromePath)
        process.arguments = ["--remote-debugging-port=\(cdpPort)"]

        do {
            try process.run()
        } catch {
            return .failure(.operationFailed("Failed to launch Chrome: \(error.localizedDescription)"))
        }

        // Wait up to 5 seconds for CDP to become available
        for _ in 0..<50 {
            Thread.sleep(forTimeInterval: 0.1)
            if isCDPAvailable() {
                return .success(true)
            }
        }

        return .failure(.operationFailed("Chrome launched but CDP port \(cdpPort) not responding"))
    }

    /// Check if CDP is responding on localhost:9222
    private func isCDPAvailable() -> Bool {
        guard let url = URL(string: "http://localhost:\(cdpPort)/json/version") else { return false }
        let semaphore = DispatchSemaphore(value: 0)
        var available = false

        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0

        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, data != nil {
                available = true
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        return available
    }

    // MARK: - Tab Discovery

    /// Fetch the list of debuggable tabs from Chrome CDP.
    func listTabs() -> Result<[[String: Any]], ServiceError> {
        guard let url = URL(string: "http://localhost:\(cdpPort)/json") else {
            return .failure(.operationFailed("Invalid CDP URL"))
        }

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<[[String: Any]], ServiceError> = .failure(.operationFailed("Timeout"))

        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            if let error = error {
                result = .failure(.operationFailed("CDP list tabs failed: \(error.localizedDescription)"))
            } else if let data = data {
                do {
                    if let tabs = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                        result = .success(tabs)
                    } else {
                        result = .failure(.operationFailed("Unexpected CDP response format"))
                    }
                } catch {
                    result = .failure(.operationFailed("Failed to parse CDP response: \(error.localizedDescription)"))
                }
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        return result
    }

    /// Find the WebSocket debug URL for a specific tab, or the first page tab.
    func findTabWebSocketURL(tabId: String?) -> Result<(String, String), ServiceError> {
        switch listTabs() {
        case .failure(let error):
            return .failure(error)
        case .success(let tabs):
            let pageTabs = tabs.filter { ($0["type"] as? String) == "page" }

            guard !pageTabs.isEmpty else {
                return .failure(.operationFailed("No page tabs found in Chrome"))
            }

            let tab: [String: Any]
            if let targetId = tabId {
                guard let found = pageTabs.first(where: { ($0["id"] as? String) == targetId }) else {
                    return .failure(.operationFailed("Tab \(targetId) not found"))
                }
                tab = found
            } else {
                tab = pageTabs[0]
            }

            guard let wsURL = tab["webSocketDebuggerUrl"] as? String,
                  let id = tab["id"] as? String else {
                return .failure(.operationFailed("Tab missing webSocketDebuggerUrl"))
            }

            return .success((wsURL, id))
        }
    }

    // MARK: - CDP Command Execution

    /// Send a CDP command via WebSocket and return the result.
    /// Uses URLSessionWebSocketTask for the connection.
    func sendCDPCommand(
        webSocketURL: String,
        method: String,
        params: [String: Any] = [:]
    ) -> Result<[String: Any], ServiceError> {
        guard let url = URL(string: webSocketURL) else {
            return .failure(.operationFailed("Invalid WebSocket URL: \(webSocketURL)"))
        }

        let session = URLSession(configuration: .default)
        let wsTask = session.webSocketTask(with: url)
        wsTask.resume()

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<[String: Any], ServiceError> = .failure(.operationFailed("Timeout"))

        messageId += 1
        let currentId = messageId

        let command: [String: Any] = [
            "id": currentId,
            "method": method,
            "params": params
        ]

        do {
            let commandData = try JSONSerialization.data(withJSONObject: command)
            let commandString = String(data: commandData, encoding: .utf8) ?? "{}"

            wsTask.send(.string(commandString)) { sendError in
                if let sendError = sendError {
                    result = .failure(.operationFailed("WebSocket send failed: \(sendError.localizedDescription)"))
                    semaphore.signal()
                    return
                }

                self.receiveCDPResponse(wsTask: wsTask, expectedId: currentId, semaphore: semaphore, result: &result)
            }
        } catch {
            wsTask.cancel(with: .goingAway, reason: nil)
            return .failure(.operationFailed("Failed to serialize CDP command: \(error.localizedDescription)"))
        }

        let timeout = semaphore.wait(timeout: .now() + 30)
        wsTask.cancel(with: .goingAway, reason: nil)

        if timeout == .timedOut {
            return .failure(.operationFailed("CDP command timed out after 30s"))
        }

        return result
    }

    private func receiveCDPResponse(
        wsTask: URLSessionWebSocketTask,
        expectedId: Int,
        semaphore: DispatchSemaphore,
        result: inout Result<[String: Any], ServiceError>
    ) {
        // Use a local mutable reference via a class wrapper
        let wrapper = ResultWrapper()

        func receive() {
            wsTask.receive { completion in
                switch completion {
                case .failure(let error):
                    wrapper.result = .failure(.operationFailed("WebSocket receive failed: \(error.localizedDescription)"))
                    semaphore.signal()
                case .success(let message):
                    switch message {
                    case .string(let text):
                        guard let data = text.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            // Not JSON, keep listening
                            receive()
                            return
                        }

                        // Check if this is our response (matching id)
                        if let id = json["id"] as? Int, id == expectedId {
                            if let error = json["error"] as? [String: Any],
                               let errorMessage = error["message"] as? String {
                                wrapper.result = .failure(.operationFailed("CDP error: \(errorMessage)"))
                            } else {
                                let responseResult = json["result"] as? [String: Any] ?? [:]
                                wrapper.result = .success(responseResult)
                            }
                            semaphore.signal()
                        } else {
                            // Event or different message, keep listening
                            receive()
                        }
                    case .data:
                        // Binary message, ignore and keep listening
                        receive()
                    @unknown default:
                        receive()
                    }
                }
            }
        }

        receive()

        // After semaphore signals, copy wrapper result back
        // (handled by the caller reading wrapper.result instead)
        result = wrapper.result
    }

    // MARK: - High-Level Operations

    /// Navigate to a URL. Opens a new tab if needed.
    func navigateToURL(_ urlString: String) -> Result<String, ServiceError> {
        switch ensureChromeRunning() {
        case .failure(let error):
            return .failure(error)
        case .success:
            break
        }

        // Create a new tab via CDP HTTP endpoint
        guard let encodedURL = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let newTabURL = URL(string: "http://localhost:\(cdpPort)/json/new?\(encodedURL)") else {
            return .failure(.operationFailed("Invalid URL"))
        }

        let semaphore = DispatchSemaphore(value: 0)
        var tabId: String?
        var error: ServiceError?

        var request = URLRequest(url: newTabURL)
        request.httpMethod = "PUT"

        let task = URLSession.shared.dataTask(with: request) { data, _, err in
            if let err = err {
                error = .operationFailed("Failed to open tab: \(err.localizedDescription)")
            } else if let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let id = json["id"] as? String {
                tabId = id
            } else {
                error = .operationFailed("Unexpected response when creating tab")
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        if let error = error {
            return .failure(error)
        }
        guard let id = tabId else {
            return .failure(.operationFailed("No tab ID in response"))
        }

        return .success(id)
    }

    /// Capture a screenshot of a tab via CDP Page.captureScreenshot.
    func captureScreenshot(tabId: String?) -> Result<String, ServiceError> {
        switch findTabWebSocketURL(tabId: tabId) {
        case .failure(let error):
            return .failure(error)
        case .success(let (wsURL, _)):
            switch sendCDPCommand(webSocketURL: wsURL, method: "Page.captureScreenshot", params: ["format": "png"]) {
            case .failure(let error):
                return .failure(error)
            case .success(let result):
                guard let data = result["data"] as? String else {
                    return .failure(.operationFailed("No screenshot data in CDP response"))
                }
                return .success(data)
            }
        }
    }

    /// Execute JavaScript in page context via CDP Runtime.evaluate.
    func executeScript(expression: String, tabId: String?) -> Result<[String: Any], ServiceError> {
        switch findTabWebSocketURL(tabId: tabId) {
        case .failure(let error):
            return .failure(error)
        case .success(let (wsURL, _)):
            let params: [String: Any] = [
                "expression": expression,
                "returnByValue": true,
                "awaitPromise": true
            ]
            return sendCDPCommand(webSocketURL: wsURL, method: "Runtime.evaluate", params: params)
        }
    }

    /// Fill a form field by CSS selector.
    func fillField(selector: String, value: String, tabId: String?) -> Result<Bool, ServiceError> {
        let escapedSelector = selector.replacingOccurrences(of: "'", with: "\\'")
        let escapedValue = value.replacingOccurrences(of: "'", with: "\\'")

        let script = """
        (() => {
            const el = document.querySelector('\(escapedSelector)');
            if (!el) return { success: false, error: 'Element not found' };
            el.focus();
            el.value = '\(escapedValue)';
            el.dispatchEvent(new Event('input', { bubbles: true }));
            el.dispatchEvent(new Event('change', { bubbles: true }));
            return { success: true };
        })()
        """

        switch executeScript(expression: script, tabId: tabId) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            if let evalResult = result["result"] as? [String: Any],
               let value = evalResult["value"] as? [String: Any],
               let success = value["success"] as? Bool {
                if success {
                    return .success(true)
                } else {
                    let msg = value["error"] as? String ?? "Unknown error"
                    return .failure(.operationFailed(msg))
                }
            }
            return .success(true)
        }
    }

    /// Click an element by CSS selector.
    func clickElement(selector: String, tabId: String?) -> Result<Bool, ServiceError> {
        let escapedSelector = selector.replacingOccurrences(of: "'", with: "\\'")

        let script = """
        (() => {
            const el = document.querySelector('\(escapedSelector)');
            if (!el) return { success: false, error: 'Element not found' };
            el.click();
            return { success: true };
        })()
        """

        switch executeScript(expression: script, tabId: tabId) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            if let evalResult = result["result"] as? [String: Any],
               let value = evalResult["value"] as? [String: Any],
               let success = value["success"] as? Bool {
                if success {
                    return .success(true)
                } else {
                    let msg = value["error"] as? String ?? "Unknown error"
                    return .failure(.operationFailed(msg))
                }
            }
            return .success(true)
        }
    }

    /// Extract text content or attribute from elements matching a CSS selector.
    func extractContent(selector: String?, tabId: String?) -> Result<[[String: Any]], ServiceError> {
        let sel = selector ?? "body"
        let escapedSelector = sel.replacingOccurrences(of: "'", with: "\\'")

        let script = """
        (() => {
            const els = Array.from(document.querySelectorAll('\(escapedSelector)'));
            return els.slice(0, 50).map(el => ({
                tag: el.tagName.toLowerCase(),
                text: el.innerText ? el.innerText.trim().substring(0, 2000) : '',
                html: el.innerHTML ? el.innerHTML.substring(0, 2000) : '',
                href: el.href || null,
                src: el.src || null
            }));
        })()
        """

        switch executeScript(expression: script, tabId: tabId) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            if let evalResult = result["result"] as? [String: Any],
               let value = evalResult["value"] as? [[String: Any]] {
                return .success(value)
            }
            return .success([])
        }
    }

    /// Get cookies for the current page via Network.getCookies.
    func getCookies(tabId: String?) -> Result<[[String: Any]], ServiceError> {
        switch findTabWebSocketURL(tabId: tabId) {
        case .failure(let error):
            return .failure(error)
        case .success(let (wsURL, _)):
            switch sendCDPCommand(webSocketURL: wsURL, method: "Network.getCookies") {
            case .failure(let error):
                return .failure(error)
            case .success(let result):
                let cookies = result["cookies"] as? [[String: Any]] ?? []
                // Strip secure values — return name, domain, path, expires only
                let safe = cookies.map { cookie -> [String: Any] in
                    var out: [String: Any] = [
                        "name": cookie["name"] ?? "",
                        "domain": cookie["domain"] ?? "",
                        "path": cookie["path"] ?? "/"
                    ]
                    if let expires = cookie["expires"] { out["expires"] = expires }
                    if let httpOnly = cookie["httpOnly"] { out["httpOnly"] = httpOnly }
                    if let secure = cookie["secure"] { out["secure"] = secure }
                    return out
                }
                return .success(safe)
            }
        }
    }

    /// Wait for an element or URL with timeout.
    func waitFor(selector: String?, url: String?, timeout: TimeInterval) -> Result<Bool, ServiceError> {
        // Need a tab to poll against
        switch findTabWebSocketURL(tabId: nil) {
        case .failure(let error):
            return .failure(error)
        case .success(let (wsURL, _)):
            let deadline = Date().addingTimeInterval(timeout)
            let pollInterval: TimeInterval = 0.25

            while Date() < deadline {
                if let sel = selector {
                    let escapedSelector = sel.replacingOccurrences(of: "'", with: "\\'")
                    let checkScript = "document.querySelector('\(escapedSelector)') !== null"
                    let params: [String: Any] = [
                        "expression": checkScript,
                        "returnByValue": true
                    ]
                    if case .success(let result) = sendCDPCommand(webSocketURL: wsURL, method: "Runtime.evaluate", params: params),
                       let evalResult = result["result"] as? [String: Any],
                       let value = evalResult["value"] as? Bool,
                       value {
                        return .success(true)
                    }
                }

                if let targetURL = url {
                    let checkScript = "window.location.href"
                    let params: [String: Any] = [
                        "expression": checkScript,
                        "returnByValue": true
                    ]
                    if case .success(let result) = sendCDPCommand(webSocketURL: wsURL, method: "Runtime.evaluate", params: params),
                       let evalResult = result["result"] as? [String: Any],
                       let currentURL = evalResult["value"] as? String,
                       currentURL.contains(targetURL) {
                        return .success(true)
                    }
                }

                Thread.sleep(forTimeInterval: pollInterval)
            }

            return .success(false)
        }
    }
}

// MARK: - Helper

/// Thread-safe wrapper for passing Result through closures.
private class ResultWrapper {
    var result: Result<[String: Any], ServiceError> = .failure(.operationFailed("No response"))
}

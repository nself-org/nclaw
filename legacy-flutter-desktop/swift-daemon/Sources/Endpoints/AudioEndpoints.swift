import Foundation

/// T-2727: HTTP endpoint handlers for audio capture and transcription.
///
/// Provides local recording control and sends audio to the claw server
/// for Whisper transcription via POST /claw/audio/transcribe.
final class AudioEndpoints {
    private let audioCaptureService = AudioCaptureService()

    // MARK: - POST /companion/audio/start

    /// Start microphone recording.
    /// Response: { "status": "recording" }
    func handleStartRecording(_ request: HTTPRequest) -> HTTPResponse {
        do {
            try audioCaptureService.startRecording()
            return .json(["status": "recording"])
        } catch {
            return .error("Failed to start recording: \(error.localizedDescription)", status: 500)
        }
    }

    // MARK: - POST /companion/audio/stop

    /// Stop microphone recording and return the local file path.
    /// Response: { "status": "stopped", "file": "/tmp/nclaw-audio-xxxx.wav" }
    func handleStopRecording(_ request: HTTPRequest) -> HTTPResponse {
        guard let url = audioCaptureService.stopRecording() else {
            return .error("No recording in progress", status: 400)
        }
        return .json(["status": "stopped", "file": url.path])
    }

    // MARK: - POST /companion/audio/transcribe

    /// Stop recording (if active), read the audio file, and send it to the
    /// claw server for Whisper transcription. Returns the transcript text.
    ///
    /// Request body (optional): { "server_url": "https://...", "token": "jwt..." }
    /// If omitted, uses the stored server URL and token from UserDefaults/Keychain.
    ///
    /// Response: { "text": "transcribed text here" }
    func handleTranscribe(_ request: HTTPRequest) -> HTTPResponse {
        // Stop recording if still active.
        let audioURL: URL
        if audioCaptureService.isRecording {
            guard let url = audioCaptureService.stopRecording() else {
                return .error("Failed to stop recording", status: 500)
            }
            audioURL = url
        } else {
            // Check for a file path in the request body.
            struct Params: Decodable { let file: String? }
            guard let params = request.jsonBody(as: Params.self),
                  let filePath = params.file else {
                return .error("No recording active and no 'file' provided", status: 400)
            }
            audioURL = URL(fileURLWithPath: filePath)
        }

        // Read audio file bytes.
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            return .error("Audio file not found: \(audioURL.path)", status: 404)
        }

        guard let audioData = try? Data(contentsOf: audioURL) else {
            return .error("Failed to read audio file", status: 500)
        }

        // Build multipart form request to claw server.
        let serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        let token = KeychainHelper.load(key: "nclaw-jwt-token") ?? ""

        guard !serverURL.isEmpty else {
            return .error("No server URL configured", status: 400)
        }

        // Parse server URL to build transcribe endpoint.
        // serverURL is typically a WSS URL like wss://api.example.com/claw/ws
        // We need to derive the HTTP base: https://api.example.com
        let httpBase = deriveHTTPBase(from: serverURL)
        let transcribeURL = "\(httpBase)/claw/audio/transcribe"

        // Synchronous HTTP call (acceptable for companion daemon context).
        let result = sendMultipartAudio(
            url: transcribeURL,
            audioData: audioData,
            filename: audioURL.lastPathComponent,
            token: token
        )

        // Clean up temp file.
        try? FileManager.default.removeItem(at: audioURL)

        switch result {
        case .success(let transcript):
            ClawLogger.info("[audio] Transcription complete: \(transcript.prefix(80))...")
            return .json(["text": transcript])
        case .failure(let error):
            return .error("Transcription failed: \(error.localizedDescription)", status: 502)
        }
    }

    // MARK: - Helpers

    /// Derive HTTP(S) base URL from a WebSocket URL.
    /// "wss://api.example.com/claw/ws" → "https://api.example.com"
    /// "ws://localhost:3710/claw/ws" → "http://localhost:3710"
    private func deriveHTTPBase(from wsURL: String) -> String {
        var url = wsURL
        // Strip path component.
        if let range = url.range(of: "/claw/") {
            url = String(url[url.startIndex..<range.lowerBound])
        }
        // Convert scheme.
        if url.hasPrefix("wss://") {
            url = "https://" + url.dropFirst(6)
        } else if url.hasPrefix("ws://") {
            url = "http://" + url.dropFirst(5)
        }
        // If it already starts with http, return as-is.
        if !url.hasPrefix("http") {
            url = "https://" + url
        }
        return url
    }

    /// Send audio data as multipart/form-data to the transcribe endpoint.
    private func sendMultipartAudio(
        url: String,
        audioData: Data,
        filename: String,
        token: String
    ) -> Result<String, Error> {
        guard let requestURL = URL(string: url) else {
            return .failure(AudioTranscribeError.invalidURL)
        }

        let boundary = "NClaw-\(UUID().uuidString)"
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 30

        // Build multipart body.
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        // Synchronous send via semaphore.
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<String, Error> = .failure(AudioTranscribeError.timeout)

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }

            if let error = error {
                result = .failure(error)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                result = .failure(AudioTranscribeError.serverError(statusCode, body))
                return
            }

            guard let data = data else {
                result = .failure(AudioTranscribeError.noData)
                return
            }

            // Parse { "text": "..." } response.
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let text = json["text"] as? String {
                    result = .success(text)
                } else {
                    result = .failure(AudioTranscribeError.invalidResponse)
                }
            } catch {
                result = .failure(error)
            }
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 30)

        return result
    }
}

// MARK: - Errors

enum AudioTranscribeError: Error, LocalizedError {
    case invalidURL
    case timeout
    case noData
    case invalidResponse
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid transcribe URL"
        case .timeout: return "Request timed out"
        case .noData: return "No data in response"
        case .invalidResponse: return "Invalid response format"
        case .serverError(let code, let body): return "Server returned \(code): \(body)"
        }
    }
}

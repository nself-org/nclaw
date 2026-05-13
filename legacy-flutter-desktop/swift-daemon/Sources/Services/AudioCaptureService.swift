import AVFoundation
import Foundation

/// T-2727: Microphone audio capture for voice input.
///
/// Records audio from the default input device to a temporary WAV file.
/// Max recording duration: 60 seconds (auto-stops).
///
/// Usage:
/// ```swift
/// let audio = AudioCaptureService()
/// try audio.startRecording()
/// // ... user speaks ...
/// let url = try audio.stopRecording()
/// // url points to a temporary .wav file
/// ```
final class AudioCaptureService {
    private var audioEngine: AVAudioEngine?
    private var outputFile: AVAudioFile?
    private var tempURL: URL?
    private var recordingTimer: Timer?

    /// Whether audio is currently being captured.
    private(set) var isRecording = false

    /// Maximum recording duration in seconds.
    static let maxDuration: TimeInterval = 60

    // MARK: - Public API

    /// Start recording microphone audio.
    ///
    /// Throws if the audio engine cannot be started or the mic is unavailable.
    func startRecording() throws {
        guard !isRecording else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Create temp file for WAV output.
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "nclaw-audio-\(UUID().uuidString.prefix(8)).wav"
        let url = tempDir.appendingPathComponent(filename)

        // WAV output settings: 16kHz mono 16-bit (Whisper-friendly).
        let wavSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        let file = try AVAudioFile(forWriting: url, settings: wavSettings)

        // Convert from input format → WAV format.
        guard let converter = AVAudioConverter(from: inputFormat, to: file.processingFormat) else {
            throw AudioCaptureError.converterFailed
        }

        let bufferCapacity: AVAudioFrameCount = 4096

        inputNode.installTap(onBus: 0, bufferSize: bufferCapacity, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self, self.isRecording else { return }

            let ratio = file.processingFormat.sampleRate / inputFormat.sampleRate
            let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1

            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: outputCapacity
            ) else { return }

            var error: NSError?
            converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if error == nil && outputBuffer.frameLength > 0 {
                do {
                    try file.write(from: outputBuffer)
                } catch {
                    ClawLogger.error("[audio] Write error: \(error)")
                }
            }
        }

        try engine.start()

        self.audioEngine = engine
        self.outputFile = file
        self.tempURL = url
        self.isRecording = true

        // Auto-stop after max duration.
        DispatchQueue.main.async { [weak self] in
            self?.recordingTimer = Timer.scheduledTimer(withTimeInterval: Self.maxDuration, repeats: false) { _ in
                self?.forceStop()
            }
        }

        ClawLogger.info("[audio] Recording started → \(url.lastPathComponent)")
    }

    /// Stop recording and return the URL of the recorded WAV file.
    ///
    /// Returns `nil` if no recording was active.
    @discardableResult
    func stopRecording() -> URL? {
        guard isRecording else { return nil }

        recordingTimer?.invalidate()
        recordingTimer = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        outputFile = nil
        isRecording = false

        let url = tempURL
        tempURL = nil

        if let url = url {
            ClawLogger.info("[audio] Recording stopped → \(url.lastPathComponent)")
        }

        return url
    }

    /// Clean up any temporary audio files.
    func cleanupTempFiles() {
        let tempDir = FileManager.default.temporaryDirectory
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(atPath: tempDir.path) {
            for file in files where file.hasPrefix("nclaw-audio-") && file.hasSuffix(".wav") {
                try? fm.removeItem(at: tempDir.appendingPathComponent(file))
            }
        }
    }

    // MARK: - Private

    private func forceStop() {
        if isRecording {
            ClawLogger.warning("[audio] Max duration reached, auto-stopping")
            _ = stopRecording()
        }
    }
}

// MARK: - Error

enum AudioCaptureError: Error, LocalizedError {
    case converterFailed
    case notRecording

    var errorDescription: String? {
        switch self {
        case .converterFailed:
            return "Failed to create audio format converter"
        case .notRecording:
            return "No recording in progress"
        }
    }
}

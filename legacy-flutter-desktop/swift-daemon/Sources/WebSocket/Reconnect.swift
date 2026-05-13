import Foundation

/// Exponential backoff reconnection manager.
final class Reconnect {
    private let onRetry: () -> Void
    private var retryCount: Int = 0
    private var timer: DispatchSourceTimer?
    private var stopped: Bool = false

    /// Base delay in seconds. Doubles on each retry up to maxDelay.
    private let baseDelay: TimeInterval = 1.0
    private let maxDelay: TimeInterval = 60.0
    private let maxRetries: Int = 50

    init(onRetry: @escaping () -> Void) {
        self.onRetry = onRetry
    }

    func scheduleRetry() {
        guard !stopped else { return }
        guard retryCount < maxRetries else {
            ClawLogger.error("Max reconnection attempts (\(maxRetries)) reached")
            return
        }

        let delay = min(baseDelay * pow(2.0, Double(retryCount)), maxDelay)
        // Add jitter: +/- 25%
        let jitter = delay * Double.random(in: -0.25...0.25)
        let actualDelay = delay + jitter

        retryCount += 1
        ClawLogger.info("Reconnecting in \(String(format: "%.1f", actualDelay))s (attempt \(retryCount))")

        let source = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        source.schedule(deadline: .now() + actualDelay)
        source.setEventHandler { [weak self] in
            self?.onRetry()
        }
        source.resume()
        self.timer = source
    }

    func reset() {
        retryCount = 0
        timer?.cancel()
        timer = nil
    }

    func stop() {
        stopped = true
        timer?.cancel()
        timer = nil
    }
}

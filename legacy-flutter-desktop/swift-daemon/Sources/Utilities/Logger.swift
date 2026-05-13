import Foundation
import os

/// Unified logging via os.Logger.
enum ClawLogger {
    private static let logger = os.Logger(subsystem: "org.nself.nclaw", category: "daemon")

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    static func warning(_ message: String) {
        logger.warning("\(message, privacy: .public)")
    }
}

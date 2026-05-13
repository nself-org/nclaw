import Foundation
import ScreenCaptureKit
import CoreGraphics
import AppKit

/// Screen capture via ScreenCaptureKit.
/// Uses SCScreenshotManager on macOS 14+, falls back to CGWindowListCreateImage on macOS 13.
final class ScreenshotService {

    func capture() async -> Result<String, ServiceError> {
        if #available(macOS 14.0, *) {
            return await captureModern()
        } else {
            return captureLegacy()
        }
    }

    @available(macOS 14.0, *)
    private func captureModern() async -> Result<String, ServiceError> {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else {
                return .failure(.operationFailed("No display found"))
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width * 2  // Retina
            config.height = display.height * 2
            config.showsCursor = false

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )

            let rep = NSBitmapImageRep(cgImage: image)
            guard let pngData = rep.representation(using: .png, properties: [:]) else {
                return .failure(.operationFailed("Failed to encode PNG"))
            }

            let base64 = pngData.base64EncodedString()
            return .success(base64)
        } catch {
            return .failure(.operationFailed("Screenshot failed: \(error.localizedDescription)"))
        }
    }

    private func captureLegacy() -> Result<String, ServiceError> {
        guard let cgImage = CGWindowListCreateImage(
            CGRect.infinite,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else {
            return .failure(.operationFailed("CGWindowListCreateImage failed"))
        }

        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            return .failure(.operationFailed("Failed to encode PNG"))
        }

        let base64 = pngData.base64EncodedString()
        return .success(base64)
    }

    // MARK: - HTTP Handler

    func handleCapture(_ request: HTTPRequest) -> HTTPResponse {
        var result: Result<String, ServiceError>?
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            result = await capture()
            semaphore.signal()
        }

        semaphore.wait()

        switch result {
        case .success(let base64):
            return .json(["image": base64, "format": "png", "encoding": "base64"])
        case .failure(let error):
            return .error(error.localizedDescription, status: error.httpStatus)
        case .none:
            return .error("Unexpected error", status: 500)
        }
    }
}

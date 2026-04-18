// S22-T03: APNs Notification Service Extension.
//
// Runs in a separate process when an APNs payload arrives with
// `mutable-content: 1`. Gives us up to 30 seconds to mutate the
// notification before it is shown — for example:
//   - decrypt the payload body (for E2E memory extractions)
//   - download and attach media (images) referenced in `data.media_url`
//   - rewrite the title / body based on user locale / server content
//
// The extension is wired into the iOS target by a separate Xcode target
// called "NotificationService" whose Info.plist declares
// `NSExtensionPointIdentifier = com.apple.usernotifications.service`.
// See docs/SIGNING.md for the target setup checklist.

import UserNotifications

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttemptContent =
            (request.content.mutableCopy() as? UNMutableNotificationContent)

        guard let bestAttemptContent = bestAttemptContent else {
            contentHandler(request.content)
            return
        }

        // 1. Thread grouping: group by topic/memory so banners collapse.
        if let threadId = request.content.userInfo["thread_id"] as? String {
            bestAttemptContent.threadIdentifier = threadId
        }

        // 2. Rich media: attach an image if the payload carries media_url.
        if let urlString = request.content.userInfo["media_url"] as? String,
           let url = URL(string: urlString) {
            downloadAttachment(from: url) { attachment in
                if let attachment = attachment {
                    bestAttemptContent.attachments = [attachment]
                }
                contentHandler(bestAttemptContent)
            }
            return
        }

        contentHandler(bestAttemptContent)
    }

    override func serviceExtensionTimeWillExpire() {
        // Best-effort: deliver whatever we have if the 30s budget expires.
        if let contentHandler = contentHandler,
           let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

    /// Download an image into the extension's tmp dir and wrap it as a
    /// UNNotificationAttachment. Returns nil on any failure — the banner is
    /// then shown without the image rather than failing the delivery.
    private func downloadAttachment(
        from url: URL,
        completion: @escaping (UNNotificationAttachment?) -> Void
    ) {
        let task = URLSession.shared.downloadTask(with: url) { tmpUrl, _, _ in
            guard let tmpUrl = tmpUrl else {
                completion(nil)
                return
            }
            let fileManager = FileManager.default
            let tmpDir = fileManager.temporaryDirectory
            let suffix = url.pathExtension.isEmpty ? "img" : url.pathExtension
            let dest = tmpDir.appendingPathComponent("\(UUID().uuidString).\(suffix)")
            do {
                try fileManager.moveItem(at: tmpUrl, to: dest)
                let attachment = try UNNotificationAttachment(
                    identifier: "media", url: dest, options: nil)
                completion(attachment)
            } catch {
                completion(nil)
            }
        }
        task.resume()
    }
}

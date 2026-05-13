/// E-26-05a: iOS Share Extension.
///
/// Accepts shared content from other apps and bridges to Flutter
/// via App Groups shared UserDefaults. The Flutter app reads the
/// shared data on launch/resume and opens the ShareComposerScreen.
import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers

class ShareViewController: SLComposeServiceViewController {

    private let appGroupId = "group.com.nself.claw"

    override func isContentValid() -> Bool {
        return true
    }

    override func didSelectPost() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        let group = DispatchGroup()

        for attachment in attachments {
            if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                group.enter()
                attachment.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] data, _ in
                    if let url = data as? URL {
                        self?.saveSharedContent(
                            content: url.absoluteString,
                            title: self?.contentText,
                            mimeType: "text/uri-list"
                        )
                    }
                    group.leave()
                }
            } else if attachment.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                group.enter()
                attachment.loadItem(forTypeIdentifier: UTType.text.identifier) { [weak self] data, _ in
                    if let text = data as? String {
                        self?.saveSharedContent(
                            content: text,
                            title: self?.contentText,
                            mimeType: "text/plain"
                        )
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func saveSharedContent(content: String, title: String?, mimeType: String) {
        let defaults = UserDefaults(suiteName: appGroupId)
        let payload: [String: Any] = [
            "content": content,
            "title": title ?? "",
            "mime_type": mimeType,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        defaults?.set(payload, forKey: "nclaw_shared_content")
        defaults?.synchronize()
    }

    override func configurationItems() -> [Any]! {
        return []
    }
}

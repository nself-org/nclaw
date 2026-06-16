/**
 * iOS Share Extension — Receives shared content from system share sheet.
 *
 * Purpose: Handle NSExtensionContext input items (text, URL, image),
 * extract data, and write to App Group UserDefaults for main app to consume.
 *
 * Constraints: Extension runs in separate process; must use App Groups to share data.
 */

import Foundation
import Social
import UIKit

class ShareViewController: SLComposeServiceViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationController?.navigationBar.tintColor = UIColor(red: 0.106, green: 0.106, blue: 0.180, alpha: 1.0) // #1a1a2e
    }

    override func isContentValid() -> Bool {
        return !self.contentText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    override func didSelectPost() {
        // Extract shared content
        var sharedText = self.contentText ?? ""
        var sharedTitle: String?
        var sharedUrl: String?
        var sharedImage: String?
        var sharedMimeType: String?

        // Check NSExtensionContext for attached items
        if let extensionContext = self.extensionContext {
            for item in extensionContext.inputItems {
                if let itemProvider = item as? NSExtensionItem {
                    // Extract text/URL
                    if let typeIdentifier = kUTTypeURL as String? {
                        if itemProvider.hasItemConformingToTypeIdentifier(typeIdentifier) {
                            itemProvider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { (item, error) in
                                if let url = item as? NSURL {
                                    sharedUrl = url.absoluteString
                                }
                            }
                        }
                    }

                    // Extract plain text
                    if let typeIdentifier = kUTTypePlainText as String? {
                        if itemProvider.hasItemConformingToTypeIdentifier(typeIdentifier) {
                            itemProvider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { (item, error) in
                                if let text = item as? String, !text.isEmpty {
                                    sharedText = text
                                }
                            }
                        }
                    }

                    // Extract image
                    if let typeIdentifier = kUTTypeImage as String? {
                        if itemProvider.hasItemConformingToTypeIdentifier(typeIdentifier) {
                            itemProvider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { (item, error) in
                                if let image = item as? UIImage {
                                    if let imageData = image.jpegData(compressionQuality: 0.8) {
                                        let filename = "shared_\(Date().timeIntervalSince1970).jpg"
                                        if let groupContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.org.nself.nclaw.share") {
                                            let fileUrl = groupContainer.appendingPathComponent(filename)
                                            try? imageData.write(to: fileUrl)
                                            sharedImage = fileUrl.absoluteString
                                            sharedMimeType = "image/jpeg"
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Write shared content to App Group UserDefaults
        if let userDefaults = UserDefaults(suiteName: "group.org.nself.nclaw.share") {
            let payload: [String: Any] = [
                "type": sharedImage != nil ? "image" : (sharedUrl != nil ? "url" : "text"),
                "text": sharedText,
                "url": sharedUrl ?? "",
                "title": sharedTitle ?? "",
                "imageUri": sharedImage ?? "",
                "mimeType": sharedMimeType ?? ""
            ]

            if let jsonData = try? JSONSerialization.data(withJSONObject: payload),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                userDefaults.set(jsonString, forKey: "NCLAW_SHARED_CONTENT")
                userDefaults.synchronize()
            }
        }

        // Open main app with deep link
        let deepLinkUrl = URL(string: "nclaw://share")!
        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                application.open(deepLinkUrl, options: [:], completionHandler: nil)
                break
            }
            responder = responder?.next
        }

        self.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
    }

    override func configurationItems() -> [Any]! {
        // To add configuration options via table cells at the bottom of the sheet, return an array of SLComposeSheetConfigurationItem here.
        return []
    }
}

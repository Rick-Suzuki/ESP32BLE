import SwiftUI
import UIKit

extension SettingsScreen {
    var availableImageURLs: [URL] {
        let directoryURL: URL
        if let existingDocumentURL = documentFiles.first {
            directoryURL = existingDocumentURL.deletingLastPathComponent()
        } else if let fallbackDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            directoryURL = fallbackDirectoryURL
        } else {
            return []
        }

        let supportedExtensions = Set(["png", "jpg", "jpeg", "heic", "heif", "gif", "bmp", "tiff", "webp"])

        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                return values?.isRegularFile == true && supportedExtensions.contains(url.pathExtension.lowercased())
            }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    var maximumSelectableImageIndex: Int {
        availableImageURLs.count
    }

    var previewImage: UIImage? {
        guard selectedImageIndex > 0 else { return nil }
        let imageIndex = selectedImageIndex - 1
        guard availableImageURLs.indices.contains(imageIndex) else { return nil }
        return UIImage(contentsOfFile: availableImageURLs[imageIndex].path)
    }

    var truncatedImageDisplayName: String {
        if selectedImageIndex == 0 {
            return "black bg"
        }

        let imageIndex = selectedImageIndex - 1
        guard availableImageURLs.indices.contains(imageIndex) else { return "no image" }

        let name = availableImageURLs[imageIndex].lastPathComponent
        let maxCharacterCount = 20
        if name.count <= maxCharacterCount {
            return name
        }

        return String(name.prefix(maxCharacterCount)) + "..."
    }
}

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

    var selectedImagePosition: Int? {
        if !selectedImageName.isEmpty,
           let imageIndex = availableImageURLs.firstIndex(where: { $0.lastPathComponent == selectedImageName }) {
            return imageIndex + 1
        }

        guard selectedImageIndex > 0 else { return nil }
        let imageIndex = selectedImageIndex - 1
        guard availableImageURLs.indices.contains(imageIndex) else { return nil }
        return imageIndex + 1
    }

    var selectedImageURL: URL? {
        guard let selectedImagePosition else { return nil }
        let imageIndex = selectedImagePosition - 1
        return availableImageURLs[imageIndex]
    }

    var truncatedImageDisplayName: String {
        guard let selectedImagePosition else {
            return "black bg"
        }

        let imageIndex = selectedImagePosition - 1
        let name = availableImageURLs[imageIndex].lastPathComponent
        let maxCharacterCount = 20
        if name.count <= maxCharacterCount {
            return name
        }

        return String(name.prefix(maxCharacterCount)) + "..."
    }

    func persistSelectedImage(_ imageURL: URL?) {
        selectedImageName = imageURL?.lastPathComponent ?? ""
        if let imageURL,
           let imageIndex = availableImageURLs.firstIndex(where: { $0.lastPathComponent == imageURL.lastPathComponent }) {
            selectedImageIndex = imageIndex + 1
        } else {
            selectedImageIndex = 0
        }
    }
}

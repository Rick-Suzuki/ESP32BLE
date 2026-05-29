import SwiftUI
import UIKit

extension SettingsScreen {
    var availableImageURLs: [URL] {
        guard let directoryURL = currentDocumentsDirectoryURL else {
            return []
        }

        let supportedExtensions = Set(["png", "jpg", "jpeg", "heic", "heif", "gif", "bmp", "tiff", "webp"])

        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [URLResourceKey.isRegularFileKey],
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

    var selectedImageURL: URL? {
        if !selectedImagePath.isEmpty,
           let imageURL = availableImageURLs.first(where: { $0.path == selectedImagePath }) {
            return imageURL
        }

        if !selectedImageName.isEmpty,
           let imageURL = availableImageURLs.first(where: {
               $0.lastPathComponent.caseInsensitiveCompare(selectedImageName) == .orderedSame
           }) {
            return imageURL
        }

        guard selectedImageIndex > 0 else { return nil }
        let imageIndex = selectedImageIndex - 1
        guard availableImageURLs.indices.contains(imageIndex) else { return nil }
        return availableImageURLs[imageIndex]
    }

    var selectedImagePosition: Int? {
        guard let selectedImageURL,
              let imageIndex = availableImageURLs.firstIndex(where: { $0.path == selectedImageURL.path }) else {
            return nil
        }

        return imageIndex + 1
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
        selectedImagePath = imageURL?.path ?? ""
        selectedImageName = imageURL?.lastPathComponent ?? ""
        if let imageURL,
           let imageIndex = availableImageURLs.firstIndex(where: { $0.path == imageURL.path }) {
            selectedImageIndex = imageIndex + 1
        } else {
            selectedImageIndex = 0
        }
    }
}

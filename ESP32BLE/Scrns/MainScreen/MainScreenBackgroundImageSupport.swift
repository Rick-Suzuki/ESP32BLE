import SwiftUI
import UIKit

extension MainScreen {
    var availableBackgroundImageURLs: [URL] {
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

    var mainBackgroundImage: UIImage? {
        guard selectedBackgroundImageIndex > 0 else { return nil }
        let imageIndex = selectedBackgroundImageIndex - 1
        guard availableBackgroundImageURLs.indices.contains(imageIndex) else { return nil }
        return UIImage(contentsOfFile: availableBackgroundImageURLs[imageIndex].path)
    }

    @ViewBuilder
    var mainBackgroundView: some View {
        ZStack {
            Color.black

            if let mainBackgroundImage {
                Image(uiImage: mainBackgroundImage)
                    .resizable()
                    .scaledToFill()
                    .opacity(backgroundImageOpacity)
                    .ignoresSafeArea()
            }
        }
        .ignoresSafeArea()
    }
}

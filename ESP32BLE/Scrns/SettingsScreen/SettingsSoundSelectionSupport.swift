import SwiftUI

extension SettingsScreen {
    var availableSoundURLs: [URL] {
        let directoryURL: URL
        if let existingDocumentURL = documentFiles.first {
            directoryURL = existingDocumentURL.deletingLastPathComponent()
        } else if let fallbackDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            directoryURL = fallbackDirectoryURL
        } else {
            return []
        }

        let supportedExtensions = supportedImportedSoundExtensions

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

    var selectedSoundURL: URL? {
        if !selectedSoundPath.isEmpty,
           let soundURL = availableSoundURLs.first(where: { $0.path == selectedSoundPath }) {
            return soundURL
        }

        if !selectedSoundName.isEmpty,
           let soundURL = availableSoundURLs.first(where: {
               $0.lastPathComponent.caseInsensitiveCompare(selectedSoundName) == .orderedSame
           }) {
            return soundURL
        }

        return nil
    }

    func persistSelectedSound(_ soundURL: URL?) {
        selectedSoundPath = soundURL?.path ?? ""
        selectedSoundName = soundURL?.lastPathComponent ?? ""
    }
}

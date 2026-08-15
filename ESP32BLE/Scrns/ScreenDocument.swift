import Foundation

let screenDocumentFileExtension = "screen"
let legacyScreenDocumentFileExtension = "txt"

func isScreenDocumentURL(_ url: URL) -> Bool {
    isScreenDocumentFileExtension(url.pathExtension)
}

func isScreenDocumentFileName(_ fileName: String) -> Bool {
    isScreenDocumentFileExtension(URL(fileURLWithPath: fileName).pathExtension)
}

func isScreenDocumentFileExtension(_ fileExtension: String) -> Bool {
    let normalizedExtension = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalizedExtension == screenDocumentFileExtension
}

func screenDocumentFileName(forBaseName baseName: String) -> String {
    let trimmedBaseName = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedBaseName = trimmedBaseName.isEmpty ? "Screen" : trimmedBaseName
    return "\(resolvedBaseName).\(screenDocumentFileExtension)"
}

func screenDocumentBaseKey(for fileName: String) -> String {
    URL(fileURLWithPath: fileName)
        .deletingPathExtension()
        .lastPathComponent
        .lowercased()
}

func preferredScreenDocumentURLs(from urls: [URL]) -> [URL] {
    urls
        .filter(isScreenDocumentURL)
        .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
}

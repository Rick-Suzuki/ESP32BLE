import SwiftUI

private let maxFunctionKeyCount = 100
private let defaultNamedFunctionKeyCount = 20

struct FunctionKeyEntry {
    let rawLine: String
    let sendTexts: [String]
    let alternateDisplayText: String?

    var primaryDisplayText: String {
        sendTexts.joined(separator: ":")
    }

    var displayUsesAlternateText: Bool {
        alternateDisplayText != nil
    }
}

struct ContentView: View {
    @StateObject private var ble = BLEKeyboardManager()
    @State private var functionKeys = ContentView.makeDefaultFunctionKeys()
    @State private var documentFiles: [URL] = []
    @State private var selectedDocumentName = "fnkeys.txt"

    var body: some View {
        NavigationStack {
            MainScreen(
                ble: ble,
                functionKeys: functionKeys,
                documentFiles: documentFiles,
                selectedDocumentName: selectedDocumentName,
                selectedDocumentDisplayName: displayName(for: selectedDocumentName),
                currentFileNumber: currentFileNumber,
                totalFileCount: documentFiles.count,
                refreshDocumentFiles: refreshDocumentFiles,
                loadFunctionKeys: selectDocument,
                renameDocument: renameSelectedDocument,
                deleteDocument: deleteDocument,
                duplicateDocument: duplicateDocument,
                canDeleteDocuments: documentFiles.count > 1,
                selectPreviousDocument: selectPreviousDocument,
                selectNextDocument: selectNextDocument
            )
        }
        .task {
            ensureDefaultFunctionKeysFile()
            refreshDocumentFiles()
            selectInitialDocument()
        }
    }

    private func defaultFunctionKeyTitles() -> [String] {
        (1...defaultNamedFunctionKeyCount).map { "F\($0)" }
    }

    private static func makeDefaultFunctionKeys() -> [FunctionKeyEntry] {
        let namedEntries = (1...defaultNamedFunctionKeyCount).map { index in
            FunctionKeyEntry(rawLine: "F\(index)", sendTexts: ["F\(index)"], alternateDisplayText: nil)
        }
        let emptyEntries = Array(
            repeating: FunctionKeyEntry(rawLine: "", sendTexts: [], alternateDisplayText: nil),
            count: maxFunctionKeyCount - defaultNamedFunctionKeyCount
        )

        return namedEntries + emptyEntries
    }

    private func defaultFunctionKeys() -> [FunctionKeyEntry] {
        Self.makeDefaultFunctionKeys()
    }

    private func documentsDirectoryURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    private func ensureDefaultFunctionKeysFile() {
        guard let documentsDirectoryURL = documentsDirectoryURL() else {
            functionKeys = defaultFunctionKeys()
            return
        }

        let fileURL = documentsDirectoryURL.appendingPathComponent("fnkeys.txt")

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let defaultContents = defaultFunctionKeyTitles().joined(separator: "\n")

            do {
                try defaultContents.write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                functionKeys = defaultFunctionKeys()
                return
            }
        }

        refreshDocumentFiles()
        selectInitialDocument()
    }

    private func refreshDocumentFiles() {
        guard let documentsDirectoryURL = documentsDirectoryURL() else {
            documentFiles = []
            return
        }

        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: documentsDirectoryURL,
                includingPropertiesForKeys: [URLResourceKey.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            documentFiles = urls
                .filter { url in
                    let values = try? url.resourceValues(forKeys: [URLResourceKey.isRegularFileKey])
                    return values?.isRegularFile == true
                }
                .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
        } catch {
            documentFiles = []
        }
    }

    private func selectInitialDocument() {
        guard let firstFileURL = documentFiles.first else {
            functionKeys = defaultFunctionKeys()
            selectedDocumentName = "fnkeys.txt"
            return
        }

        loadFunctionKeys(from: firstFileURL)
    }

    private func loadFunctionKeys(from fileURL: URL) {
        do {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            let loadedTitles = contents.components(separatedBy: .newlines)
            functionKeys = normalizedFunctionKeys(from: loadedTitles)
            selectedDocumentName = fileURL.lastPathComponent
        } catch {
            functionKeys = Array(repeating: FunctionKeyEntry(rawLine: "", sendTexts: [], alternateDisplayText: nil), count: maxFunctionKeyCount)
        }
    }

    private func normalizedFunctionKeys(from loadedTitles: [String]) -> [FunctionKeyEntry] {
        let filteredTitles = loadedTitles.compactMap { line -> String? in
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("//") else {
                return nil
            }

            return trimmedLine
        }
        let firstHundred = Array(filteredTitles.prefix(maxFunctionKeyCount))

        return (0..<maxFunctionKeyCount).map { index in
            guard index < firstHundred.count else {
                return FunctionKeyEntry(rawLine: "", sendTexts: [], alternateDisplayText: nil)
            }

            return functionKeyEntry(from: firstHundred[index])
        }
    }

    private func functionKeyEntry(from line: String) -> FunctionKeyEntry {
        let components = line.components(separatedBy: "::")

        guard components.count >= 2 else {
            return FunctionKeyEntry(rawLine: line, sendTexts: [line], alternateDisplayText: nil)
        }

        let leftText = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let rightText = components.dropFirst().joined(separator: "::").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !leftText.isEmpty, !rightText.isEmpty else {
            return FunctionKeyEntry(rawLine: line, sendTexts: [line], alternateDisplayText: nil)
        }

        let sendTexts = leftText
            .components(separatedBy: ":")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !sendTexts.isEmpty else {
            return FunctionKeyEntry(rawLine: line, sendTexts: [line], alternateDisplayText: nil)
        }

        return FunctionKeyEntry(rawLine: line, sendTexts: sendTexts, alternateDisplayText: rightText)
    }

    private func selectDocument(_ fileURL: URL) {
        loadFunctionKeys(from: fileURL)
        refreshDocumentFiles()
    }

    private func displayName(for fileName: String) -> String {
        URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
    }

    private var currentFileNumber: Int {
        guard let index = documentFiles.firstIndex(where: { $0.lastPathComponent == selectedDocumentName }) else {
            return 1
        }

        return index + 1
    }

    private func renameSelectedDocument(to proposedName: String) -> String? {
        let trimmedName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            return "Filename can't be blank."
        }

        let targetFileName = "\(trimmedName).txt"

        if targetFileName.caseInsensitiveCompare(selectedDocumentName) == .orderedSame {
            return nil
        }

        guard let documentsDirectoryURL = documentsDirectoryURL() else {
            return "Couldn't access the documents folder."
        }

        if documentFiles.contains(where: { $0.lastPathComponent.caseInsensitiveCompare(targetFileName) == .orderedSame }) {
            return "A file with that name already exists."
        }

        let sourceURL = documentsDirectoryURL.appendingPathComponent(selectedDocumentName)
        let targetURL = documentsDirectoryURL.appendingPathComponent(targetFileName)

        do {
            try FileManager.default.moveItem(at: sourceURL, to: targetURL)
            loadFunctionKeys(from: targetURL)
            refreshDocumentFiles()
            return nil
        } catch {
            return "Couldn't rename the file."
        }
    }

    private func deleteDocument(_ fileURL: URL) {
        guard documentFiles.count > 1 else {
            return
        }

        let fallbackFileURL: URL?

        if selectedDocumentName == fileURL.lastPathComponent,
           let currentIndex = documentFiles.firstIndex(where: { $0.lastPathComponent == fileURL.lastPathComponent }) {
            let remainingFiles = documentFiles.enumerated()
                .filter { $0.offset != currentIndex }
                .map(\.element)

            if currentIndex > 0 {
                fallbackFileURL = remainingFiles[currentIndex - 1]
            } else {
                fallbackFileURL = remainingFiles.first
            }
        } else {
            fallbackFileURL = nil
        }

        do {
            try FileManager.default.removeItem(at: fileURL)
            refreshDocumentFiles()

            if let fallbackFileURL {
                loadFunctionKeys(from: fallbackFileURL)
            }
        } catch {
            refreshDocumentFiles()
        }
    }

    private func duplicateDocument(_ fileURL: URL) {
        let directoryURL = fileURL.deletingLastPathComponent()
        let fileExtension = fileURL.pathExtension
        let baseName = fileURL.deletingPathExtension().lastPathComponent

        var index = 1
        var targetURL: URL

        repeat {
            let candidateName = "\(baseName)_\(index)"
            targetURL = directoryURL.appendingPathComponent(candidateName).appendingPathExtension(fileExtension)
            index += 1
        } while FileManager.default.fileExists(atPath: targetURL.path)

        do {
            try FileManager.default.copyItem(at: fileURL, to: targetURL)
            refreshDocumentFiles()
            loadFunctionKeys(from: targetURL)
        } catch {
            refreshDocumentFiles()
        }
    }

    private func selectPreviousDocument() {
        guard let currentIndex = documentFiles.firstIndex(where: { $0.lastPathComponent == selectedDocumentName }),
              currentIndex > 0 else {
            return
        }

        loadFunctionKeys(from: documentFiles[currentIndex - 1])
    }

    private func selectNextDocument() {
        guard let currentIndex = documentFiles.firstIndex(where: { $0.lastPathComponent == selectedDocumentName }),
              currentIndex < documentFiles.count - 1 else {
            return
        }

        loadFunctionKeys(from: documentFiles[currentIndex + 1])
    }
}

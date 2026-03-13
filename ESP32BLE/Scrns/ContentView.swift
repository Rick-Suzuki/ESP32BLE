import SwiftUI

struct FunctionKeyEntry {
    let rawLine: String
    let sendText: String
    let alternateDisplayText: String?

    var displayUsesAlternateText: Bool {
        alternateDisplayText != nil
    }
}

struct ContentView: View {
    @StateObject private var ble = BLEKeyboardManager()
    @State private var functionKeys = (1...20).map {
        FunctionKeyEntry(rawLine: "F\($0)", sendText: "F\($0)", alternateDisplayText: nil)
    }
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
                refreshDocumentFiles: refreshDocumentFiles,
                loadFunctionKeys: selectDocument,
                renameDocument: renameSelectedDocument,
                deleteDocument: deleteDocument,
                duplicateDocument: duplicateDocument,
                canDeleteDocuments: documentFiles.count > 1
            )
        }
        .task {
            ensureDefaultFunctionKeysFile()
            refreshDocumentFiles()
            selectInitialDocument()
        }
    }

    private func defaultFunctionKeyTitles() -> [String] {
        (1...20).map { "F\($0)" }
    }

    private func defaultFunctionKeys() -> [FunctionKeyEntry] {
        defaultFunctionKeyTitles().map { title in
            FunctionKeyEntry(rawLine: title, sendText: title, alternateDisplayText: nil)
        }
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
            functionKeys = Array(repeating: FunctionKeyEntry(rawLine: "", sendText: "", alternateDisplayText: nil), count: 20)
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
        let firstTwenty = Array(filteredTitles.prefix(20))

        return (0..<20).map { index in
            guard index < firstTwenty.count else {
                return FunctionKeyEntry(rawLine: "", sendText: "", alternateDisplayText: nil)
            }

            return functionKeyEntry(from: firstTwenty[index])
        }
    }

    private func functionKeyEntry(from line: String) -> FunctionKeyEntry {
        let components = line.components(separatedBy: "::")

        guard components.count >= 2 else {
            return FunctionKeyEntry(rawLine: line, sendText: line, alternateDisplayText: nil)
        }

        let leftText = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let rightText = components.dropFirst().joined(separator: "::").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !leftText.isEmpty, !rightText.isEmpty else {
            return FunctionKeyEntry(rawLine: line, sendText: line, alternateDisplayText: nil)
        }

        return FunctionKeyEntry(rawLine: line, sendText: leftText, alternateDisplayText: rightText)
    }

    private func selectDocument(_ fileURL: URL) {
        loadFunctionKeys(from: fileURL)
        refreshDocumentFiles()
    }

    private func displayName(for fileName: String) -> String {
        URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
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
}

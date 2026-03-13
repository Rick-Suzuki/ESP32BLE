import SwiftUI

struct ContentView: View {
    @StateObject private var ble = BLEKeyboardManager()
    @State private var functionKeyTitles = (1...20).map { "F\($0)" }
    @State private var documentFiles: [URL] = []
    @State private var selectedDocumentName = "fnkeys.txt"

    var body: some View {
        NavigationStack {
            MainScreen(
                ble: ble,
                functionKeyTitles: functionKeyTitles,
                documentFiles: documentFiles,
                selectedDocumentName: selectedDocumentName,
                selectedDocumentDisplayName: displayName(for: selectedDocumentName),
                refreshDocumentFiles: refreshDocumentFiles,
                loadFunctionKeys: selectDocument,
                renameDocument: renameSelectedDocument
            )
        }
        .task {
            ensureDefaultFunctionKeysFile()
            refreshDocumentFiles()
        }
    }

    private func defaultFunctionKeyTitles() -> [String] {
        (1...20).map { "F\($0)" }
    }

    private func documentsDirectoryURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    private func ensureDefaultFunctionKeysFile() {
        guard let documentsDirectoryURL = documentsDirectoryURL() else {
            functionKeyTitles = defaultFunctionKeyTitles()
            return
        }

        let fileURL = documentsDirectoryURL.appendingPathComponent("fnkeys.txt")

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let defaultContents = defaultFunctionKeyTitles().joined(separator: "\n")

            do {
                try defaultContents.write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                functionKeyTitles = defaultFunctionKeyTitles()
                return
            }
        }

        loadFunctionKeys(from: fileURL)
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

    private func loadFunctionKeys(from fileURL: URL) {
        do {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            let loadedTitles = contents.components(separatedBy: .newlines)
            functionKeyTitles = normalizedFunctionKeyTitles(from: loadedTitles)
            selectedDocumentName = fileURL.lastPathComponent
        } catch {
            functionKeyTitles = Array(repeating: "", count: 20)
        }
    }

    private func normalizedFunctionKeyTitles(from loadedTitles: [String]) -> [String] {
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
                return ""
            }

            return firstTwenty[index]
        }
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
}

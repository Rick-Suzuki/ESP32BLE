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
                refreshDocumentFiles: refreshDocumentFiles,
                loadFunctionKeys: selectDocument
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
        let firstTwenty = Array(loadedTitles.prefix(20))

        return (0..<20).map { index in
            guard index < firstTwenty.count else {
                return ""
            }

            return firstTwenty[index].trimmingCharacters(in: .newlines)
        }
    }

    private func selectDocument(_ fileURL: URL) {
        loadFunctionKeys(from: fileURL)
        refreshDocumentFiles()
    }
}

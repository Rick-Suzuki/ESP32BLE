
import SwiftUI
import AudioToolbox

private let maxFunctionKeyCount = 100
private let defaultNamedFunctionKeyCount = 20

enum ButtonClickFeedback {
    static let preferenceKey = "isButtonClickEnabled"
    private static let soundID: SystemSoundID = 1104

    static func playIfEnabled() {
        let isEnabled = UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true
        guard isEnabled else { return }
        AudioServicesPlaySystemSound(soundID)
    }
}

struct FunctionKeyEntry {
    let rawLine: String
    let sendTexts: [String]
    let alternateDisplayText: String?
    let buttonColorCode: String?
    let isBlankPlaceholder: Bool

    var primaryDisplayText: String {
        sendTexts.joined(separator: ":")
    }

    var displayUsesAlternateText: Bool {
        alternateDisplayText != nil
    }
}

struct ContentView: View {
    private let defaultDocumentFontSize: Double = 20
    @AppStorage("selectedBackgroundImageIndex") private var selectedBackgroundImageIndex = 0
    @AppStorage("selectedBackgroundImageName") private var selectedBackgroundImageName = ""
    @AppStorage("backgroundImageOpacity") private var backgroundImageOpacity = 0.5
    @StateObject private var ble = BLEKeyboardManager()
    @State private var functionKeys = ContentView.makeDefaultFunctionKeys()
    @State private var functionKeySlotLines = ContentView.defaultFunctionKeyTitles()
    @State private var loadedFunctionKeySlotCount = defaultNamedFunctionKeyCount
    @State private var documentFiles: [URL] = []
    @State private var backgroundImageFiles: [URL] = []
    @State private var loadedBackgroundImage: UIImage?
    @State private var documentNavigationHistory: [String] = []
    @AppStorage("selectedDocumentName") private var selectedDocumentName = "fnkeys.txt"
    @AppStorage("documentFontSizesData") private var documentFontSizesData = ""
    @State private var settingsBLEText = ""
    @State private var isKeyboardScreenPresented = false
    @State private var isSettingsScreenPresented = true

    var body: some View {
        NavigationStack {
            ZStack {
                GeometryReader { geometry in
                    let containerWidth = geometry.size.width.isFinite ? max(0, geometry.size.width) : 0
                    let containerHeight = geometry.size.height.isFinite ? max(0, geometry.size.height) : 0

                    ZStack {
                        KeyboardScreen(ble: ble, isPresented: isKeyboardScreenPresented) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isKeyboardScreenPresented = false
                            }
                        }
                        .frame(width: containerWidth, height: containerHeight)
                        .offset(x: isKeyboardScreenPresented ? 0 : -containerWidth)

                        MainScreen(
                            ble: ble,
                            functionKeys: functionKeys,
                            documentFiles: documentFiles,
                            selectedDocumentName: selectedDocumentName,
                            selectedDocumentDisplayName: displayName(for: selectedDocumentName),
                            boxFontSize: fontSize(for: selectedDocumentName),
                            currentFileNumber: currentFileNumber,
                            totalFileCount: documentFiles.count,
                            definedFunctionKeyCount: loadedFunctionKeySlotCount,
                            refreshDocumentFiles: refreshDocumentFiles,
                            loadFunctionKeys: selectDocument,
                            saveSelectedDocumentAndReload: saveSelectedDocumentAndReload,
                            renameDocument: renameSelectedDocument,
                            deleteDocument: deleteDocument,
                            duplicateDocument: duplicateDocument,
                            canDeleteDocuments: documentFiles.count > 1,
                            selectPreviousDocument: selectPreviousDocument,
                            selectNextDocument: selectNextDocument,
                            goBackToPreviousDocument: goBackToPreviousDocument,
                            canGoBackToPreviousDocument: canGoBackToPreviousDocument,
                            selectDocumentNamedFromGrid: selectDocumentNamedFromGrid,
                            resizeVisibleBoxCount: resizeSelectedDocumentSlotCount,
                            moveFunctionKeySlot: moveSelectedDocumentSlot,
                            updateFunctionKeySlot: updateSelectedDocumentSlot,
                            updateDocumentFontSize: updateDocumentFontSize,
                            openKeyboardScreen: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    isKeyboardScreenPresented = true
                                }
                            },
                            settingsBLEText: $settingsBLEText
                        )
                        .frame(width: containerWidth, height: containerHeight)
                        .offset(x: isKeyboardScreenPresented ? containerWidth : 0)
                    }
                    .frame(width: containerWidth, height: containerHeight)
                    .clipped()
                }
            }
            .background {
                mainScreenBackgroundView
            }
            .toolbarVisibility(isKeyboardScreenPresented ? .hidden : .visible, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(isPresented: $isSettingsScreenPresented) {
                SettingsScreen(
                    ble: ble,
                    documentFiles: documentFiles,
                    selectedDocumentName: selectedDocumentName,
                    refreshDocumentFiles: refreshDocumentFiles,
                    loadFunctionKeys: selectDocument,
                    saveSelectedDocumentAndReload: saveSelectedDocumentAndReload,
                    renameDocument: renameSelectedDocument,
                    deleteDocument: deleteDocument,
                    duplicateDocument: duplicateDocument,
                    canDeleteDocuments: documentFiles.count > 1,
                    bleTextToSend: $settingsBLEText
                )
            }
        }
        .task {
            ensureDefaultFunctionKeysFile()
            refreshDocumentFiles()
            refreshBackgroundImageFiles()
            selectInitialDocument()
            reloadBackgroundImage()
        }
        .onChange(of: selectedBackgroundImageIndex) {
            reloadBackgroundImage()
        }
        .onChange(of: selectedBackgroundImageName) {
            reloadBackgroundImage()
        }
    }

    private static func defaultFunctionKeyTitles() -> [String] {
        (1...defaultNamedFunctionKeyCount).map { "F\($0)" }
    }

    private static func makeDefaultFunctionKeys() -> [FunctionKeyEntry] {
        let namedEntries = (1...defaultNamedFunctionKeyCount).map { index in
            FunctionKeyEntry(rawLine: "F\(index)", sendTexts: ["F\(index)"], alternateDisplayText: nil, buttonColorCode: nil, isBlankPlaceholder: false)
        }
        let emptyEntries = Array(
            repeating: FunctionKeyEntry(rawLine: "", sendTexts: [], alternateDisplayText: nil, buttonColorCode: nil, isBlankPlaceholder: false),
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
            loadedFunctionKeySlotCount = defaultNamedFunctionKeyCount
            return
        }

        let fileURL = documentsDirectoryURL.appendingPathComponent("fnkeys.txt")

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let defaultContents = Self.defaultFunctionKeyTitles().joined(separator: "\n")

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
                    return values?.isRegularFile == true && url.pathExtension.lowercased() == "txt"
                }
                .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
        } catch {
            documentFiles = []
        }
    }

    private func refreshBackgroundImageFiles() {
        guard let documentsDirectoryURL = documentsDirectoryURL() else {
            backgroundImageFiles = []
            loadedBackgroundImage = nil
            return
        }

        let supportedExtensions = Set(["png", "jpg", "jpeg", "heic", "heif", "gif", "bmp", "tiff", "webp"])
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: documentsDirectoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        backgroundImageFiles = urls
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                return values?.isRegularFile == true && supportedExtensions.contains(url.pathExtension.lowercased())
            }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func reloadBackgroundImage() {
        if !selectedBackgroundImageName.isEmpty,
           let namedImageURL = backgroundImageFiles.first(where: { $0.lastPathComponent == selectedBackgroundImageName }) {
            loadedBackgroundImage = UIImage(contentsOfFile: namedImageURL.path)
            if let namedImageIndex = backgroundImageFiles.firstIndex(where: { $0.lastPathComponent == selectedBackgroundImageName }) {
                selectedBackgroundImageIndex = namedImageIndex + 1
            }
            return
        }

        guard selectedBackgroundImageIndex > 0 else {
            loadedBackgroundImage = nil
            return
        }

        let imageIndex = selectedBackgroundImageIndex - 1
        guard backgroundImageFiles.indices.contains(imageIndex) else {
            loadedBackgroundImage = nil
            return
        }

        let resolvedImageURL = backgroundImageFiles[imageIndex]
        selectedBackgroundImageName = resolvedImageURL.lastPathComponent
        loadedBackgroundImage = UIImage(contentsOfFile: resolvedImageURL.path)
    }

    private func selectInitialDocument() {
        guard !documentFiles.isEmpty else {
            functionKeys = defaultFunctionKeys()
            selectedDocumentName = "fnkeys.txt"
            loadedFunctionKeySlotCount = defaultNamedFunctionKeyCount
            return
        }

        if let savedFileURL = documentFiles.first(where: { $0.lastPathComponent == selectedDocumentName }) {
            loadFunctionKeys(from: savedFileURL)
            return
        }

        loadFunctionKeys(from: documentFiles[0])
    }

    private func loadFunctionKeys(from fileURL: URL) {
        do {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            let loadedTitles = normalizedSlotLines(from: contents)
            applySlotLines(loadedTitles)
            selectedDocumentName = fileURL.lastPathComponent
        } catch {
            functionKeySlotLines = []
            functionKeys = Array(repeating: FunctionKeyEntry(rawLine: "", sendTexts: [], alternateDisplayText: nil, buttonColorCode: nil, isBlankPlaceholder: false), count: maxFunctionKeyCount)
            loadedFunctionKeySlotCount = 0
        }
    }

    private func normalizedSlotLines(from contents: String) -> [String] {
        contents
            .components(separatedBy: CharacterSet.newlines.union(.init(charactersIn: "\t")))
            .compactMap { line -> String? in
                let normalizedLine = line.replacingOccurrences(of: "\r", with: "")
                let trimmedLine = normalizedLine.trimmingCharacters(in: .whitespacesAndNewlines)

                guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("//") else {
                    return nil
                }

                return normalizedLine
            }
    }

    private func applySlotLines(_ slotLines: [String]) {
        functionKeySlotLines = Array(slotLines.prefix(maxFunctionKeyCount))
        let parsedFunctionKeys = normalizedFunctionKeys(from: functionKeySlotLines)
        functionKeys = parsedFunctionKeys.entries
        loadedFunctionKeySlotCount = parsedFunctionKeys.definedSlotCount
    }

    private func normalizedFunctionKeys(from loadedTitles: [String]) -> (entries: [FunctionKeyEntry], definedSlotCount: Int) {
        let firstHundred = Array(loadedTitles.prefix(maxFunctionKeyCount))

        let entries = (0..<maxFunctionKeyCount).map { index in
            guard index < firstHundred.count else {
                return FunctionKeyEntry(rawLine: "", sendTexts: [], alternateDisplayText: nil, buttonColorCode: nil, isBlankPlaceholder: false)
            }

            return functionKeyEntry(from: firstHundred[index])
        }

        return (entries, firstHundred.count)
    }

    private func selectedDocumentURL() -> URL? {
        if let matchingURL = documentFiles.first(where: { $0.lastPathComponent == selectedDocumentName }) {
            return matchingURL
        }

        return documentsDirectoryURL()?.appendingPathComponent(selectedDocumentName)
    }

    private func persistSlotLines(_ slotLines: [String]) {
        guard let selectedDocumentURL = selectedDocumentURL() else {
            applySlotLines(slotLines)
            return
        }

        let normalizedLines = Array(slotLines.prefix(maxFunctionKeyCount))
        let contents = normalizedLines.joined(separator: "\n")

        do {
            try contents.write(to: selectedDocumentURL, atomically: true, encoding: .utf8)
            applySlotLines(normalizedLines)
        } catch {
            loadFunctionKeys(from: selectedDocumentURL)
        }
    }

    private func saveSelectedDocumentAndReload(_ text: String) {
        guard let selectedDocumentURL = selectedDocumentURL() else { return }

        do {
            try text.write(to: selectedDocumentURL, atomically: true, encoding: .utf8)
            let loadedTitles = normalizedSlotLines(from: text)
            applySlotLines(loadedTitles)
        } catch {
            loadFunctionKeys(from: selectedDocumentURL)
        }
    }

    private func fontSize(for fileName: String) -> Double {
        loadDocumentFontSizes()[fileName] ?? defaultDocumentFontSize
    }

    private func updateDocumentFontSize(_ newFontSize: Double) {
        var updatedFontSizes = loadDocumentFontSizes()
        updatedFontSizes[selectedDocumentName] = newFontSize
        saveDocumentFontSizes(updatedFontSizes)
    }

    private func loadDocumentFontSizes() -> [String: Double] {
        guard let data = documentFontSizesData.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: Double].self, from: data) else {
            return [:]
        }

        return decoded
    }

    private func saveDocumentFontSizes(_ fontSizes: [String: Double]) {
        guard let data = try? JSONEncoder().encode(fontSizes),
              let encoded = String(data: data, encoding: .utf8) else {
            return
        }

        documentFontSizesData = encoded
    }

    @discardableResult
    private func resizeSelectedDocumentSlotCount(to newCount: Int) -> Bool {
        let boundedCount = min(max(newCount, 1), maxFunctionKeyCount)
        let currentCount = functionKeySlotLines.count

        guard boundedCount != currentCount else {
            return true
        }

        let currentLines = Array(functionKeySlotLines.prefix(currentCount))

        guard let resizedLines = resizedSlotLines(
            from: currentLines,
            oldCount: currentCount,
            to: boundedCount
        ) else {
            print("Can't shrink grid because trailing buttons contain text.")
            return false
        }

        persistSlotLines(resizedLines)
        return true
    }

    private func resizedSlotLines(from slotLines: [String], oldCount: Int, to newCount: Int) -> [String]? {
        let oldGrid = functionKeyGridDimensions(for: oldCount)
        let newGrid = functionKeyGridDimensions(for: newCount)
        var remappedLines = Array(repeating: "_", count: newCount)

        for index in 0..<oldCount {
            let line = index < slotLines.count ? slotLines[index] : "_"
            let row = index / oldGrid.columns
            let column = index % oldGrid.columns

            guard row < newGrid.rows, column < newGrid.columns else {
                if isBlankPlaceholderLine(line) {
                    continue
                }
                return nil
            }

            let newIndex = row * newGrid.columns + column
            guard newIndex < newCount else {
                if isBlankPlaceholderLine(line) {
                    continue
                }
                return nil
            }

            remappedLines[newIndex] = line
        }

        return remappedLines
    }

    @discardableResult
    private func moveSelectedDocumentSlot(from sourceIndex: Int, to targetIndex: Int) -> Bool {
        guard sourceIndex != targetIndex,
              functionKeySlotLines.indices.contains(sourceIndex),
              targetIndex >= 0,
              targetIndex < maxFunctionKeyCount else {
            return false
        }

        var updatedLines = functionKeySlotLines

        if targetIndex >= updatedLines.count {
            updatedLines += Array(repeating: "_", count: targetIndex - updatedLines.count + 1)
        }

        let sourceLine = updatedLines[sourceIndex]
        let targetLine = updatedLines[targetIndex]

        guard !isBlankPlaceholderLine(sourceLine) else {
            return false
        }

        updatedLines[targetIndex] = sourceLine
        updatedLines[sourceIndex] = targetLine
        persistSlotLines(updatedLines)
        return true
    }

    @discardableResult
    private func updateSelectedDocumentSlot(at index: Int, with line: String) -> Bool {
        guard index >= 0, index < maxFunctionKeyCount else {
            return false
        }

        var updatedLines = functionKeySlotLines
        let normalizedLine = line.replacingOccurrences(of: "\r", with: "")
        let persistedLine = normalizedLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "_" : normalizedLine

        if index >= updatedLines.count {
            updatedLines += Array(repeating: "_", count: index - updatedLines.count + 1)
        }

        updatedLines[index] = persistedLine
        persistSlotLines(updatedLines)
        return true
    }

    private func isBlankPlaceholderLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines) == "_"
    }

    private func functionKeyEntry(from line: String) -> FunctionKeyEntry {
        if line == "_" || line.isEmpty {
            return FunctionKeyEntry(rawLine: "", sendTexts: [], alternateDisplayText: nil, buttonColorCode: nil, isBlankPlaceholder: true)
        }

        let components = line.components(separatedBy: "::")

        guard components.count >= 2 else {
            return FunctionKeyEntry(rawLine: line, sendTexts: [line], alternateDisplayText: nil, buttonColorCode: nil, isBlankPlaceholder: false)
        }

        let leftText = components[0]
        let rightText = components.dropFirst().joined(separator: "::").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !rightText.isEmpty else {
            return FunctionKeyEntry(rawLine: line, sendTexts: [line], alternateDisplayText: nil, buttonColorCode: nil, isBlankPlaceholder: false)
        }

        let sendTexts = parsedSendTexts(from: leftText)
        let parsedRightText = parsedRightTextAndColor(from: rightText)
        return FunctionKeyEntry(
            rawLine: line,
            sendTexts: sendTexts,
            alternateDisplayText: parsedRightText.text,
            buttonColorCode: parsedRightText.colorCode,
            isBlankPlaceholder: false
        )
    }

    private func parsedSendTexts(from leftText: String) -> [String] {
        leftText
            .components(separatedBy: ":")
            .compactMap { component in
                if !component.isEmpty,
                   component.allSatisfy({ $0.isWhitespace && !$0.isNewline }) {
                    return " "
                }

                let trimmedComponent = component.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmedComponent.isEmpty ? nil : trimmedComponent
            }
    }

    private func parsedRightTextAndColor(from rightText: String) -> (text: String, colorCode: String?) {
        let components = rightText.components(separatedBy: ":")

        if let firstComponent = components.first,
           firstComponent.count == 1,
           let manualColorCode = firstComponent.lowercased().first,
           "lwbgorpucya".contains(manualColorCode) {
            let remainingText = components.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
            return (remainingText.isEmpty ? rightText : remainingText, String(manualColorCode))
        }

        let firstWord = rightText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .first?
            .lowercased() ?? ""

		// MARK: - BM:🟥 btns keywords
        if ["delete", "del", "rem", "remove", "clr", "clear", "erase", "destroy"].contains(firstWord) {
            return (rightText, "dest")
        }

        if ["save", "start", "run", "apply", "ok", "confirm", "enable", "disable"].contains(firstWord) {
            return (rightText, "pos")
        }

        if ["rst", "reset", "reload", "restart", "warning", "warn"].contains(firstWord) {
            return (rightText, "warning")
        }

        if ["open", "close", "cls", "edit"].contains(firstWord) {
            return (rightText, "actions")
        }

        if ["settings", "options", "details", "info"].contains(firstWord) {
            return (rightText, "info")
        }

        return (rightText, nil)
    }

    private func selectDocument(_ fileURL: URL) {
        loadFunctionKeys(from: fileURL)
        refreshDocumentFiles()
    }

    private func selectDocument(_ fileURL: URL, recordHistory: Bool) {
        if recordHistory {
            recordDocumentHistory(beforeSwitchingTo: fileURL.lastPathComponent)
        }
        loadFunctionKeys(from: fileURL)
        refreshDocumentFiles()
    }

    private func recordDocumentHistory(beforeSwitchingTo targetDocumentName: String) {
        guard !selectedDocumentName.isEmpty,
              selectedDocumentName != targetDocumentName else {
            return
        }

        if documentNavigationHistory.last != selectedDocumentName {
            documentNavigationHistory.append(selectedDocumentName)
        }
    }

    private func canonicalDocumentFileName(from rawName: String) -> String {
        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedName.isEmpty else { return trimmedName }
        return trimmedName.lowercased().hasSuffix(".txt") ? trimmedName : "\(trimmedName).txt"
    }

    @discardableResult
    private func selectDocumentNamedFromGrid(_ rawName: String) -> Bool {
        let targetFileName = canonicalDocumentFileName(from: rawName)
        guard !targetFileName.isEmpty,
              let fileURL = documentFiles.first(where: {
                  $0.lastPathComponent.caseInsensitiveCompare(targetFileName) == .orderedSame
              }) else {
            return false
        }

        selectDocument(fileURL, recordHistory: true)
        return true
    }

    private func displayName(for fileName: String) -> String {
        URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
    }

    @ViewBuilder
    private var mainScreenBackgroundView: some View {
        ZStack {
            Color.black

            if let loadedBackgroundImage, !isKeyboardScreenPresented, !isSettingsScreenPresented {
                Image(uiImage: loadedBackgroundImage)
                    .resizable()
                    .scaledToFill()
                    .opacity(backgroundImageOpacity)
            }
        }
        .ignoresSafeArea()
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
            return "a file with that name already exists."
        }

        let sourceURL = documentsDirectoryURL.appendingPathComponent(selectedDocumentName)
        let targetURL = documentsDirectoryURL.appendingPathComponent(targetFileName)

        do {
            var updatedFontSizes = loadDocumentFontSizes()
            if let existingFontSize = updatedFontSizes.removeValue(forKey: selectedDocumentName) {
                updatedFontSizes[targetFileName] = existingFontSize
                saveDocumentFontSizes(updatedFontSizes)
            }
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
            var updatedFontSizes = loadDocumentFontSizes()
            updatedFontSizes.removeValue(forKey: fileURL.lastPathComponent)
            saveDocumentFontSizes(updatedFontSizes)
            refreshDocumentFiles()

            if let fallbackFileURL {
                documentNavigationHistory.removeAll { $0 == fileURL.lastPathComponent }
                selectDocument(fallbackFileURL)
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
            var updatedFontSizes = loadDocumentFontSizes()
            updatedFontSizes[targetURL.lastPathComponent] = defaultDocumentFontSize
            saveDocumentFontSizes(updatedFontSizes)
            refreshDocumentFiles()
            selectDocument(targetURL)
        } catch {
            refreshDocumentFiles()
        }
    }

    private func selectPreviousDocument() {
        guard let currentIndex = documentFiles.firstIndex(where: { $0.lastPathComponent == selectedDocumentName }),
              currentIndex > 0 else {
            return
        }

        selectDocument(documentFiles[currentIndex - 1], recordHistory: true)
    }

    private func selectNextDocument() {
        guard let currentIndex = documentFiles.firstIndex(where: { $0.lastPathComponent == selectedDocumentName }),
              currentIndex < documentFiles.count - 1 else {
            return
        }

        selectDocument(documentFiles[currentIndex + 1], recordHistory: true)
    }

    private var canGoBackToPreviousDocument: Bool {
        documentNavigationHistory.contains { previousName in
            previousName != selectedDocumentName &&
            documentFiles.contains(where: { $0.lastPathComponent == previousName })
        }
    }

    private func goBackToPreviousDocument() {
        while let previousName = documentNavigationHistory.popLast() {
            guard previousName != selectedDocumentName,
                  let fileURL = documentFiles.first(where: { $0.lastPathComponent == previousName }) else {
                continue
            }

            selectDocument(fileURL)
            return
        }
    }
}

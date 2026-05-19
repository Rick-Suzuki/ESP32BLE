
import SwiftUI
import AudioToolbox
import UIKit
import ImageIO

let maxGridDimension = 20
let maxFunctionKeyCount = maxGridDimension * maxGridDimension
private let defaultNamedFunctionKeyCount = 20
let hiddenButtonMetadataToken = "@@hidden"
let wideButtonContinuationToken = "@@wide"
let blockButtonContinuationToken = "@@block"

// True on iPad, false on iPhone.
var isPad: Bool {
    UIDevice.current.userInterfaceIdiom == .pad
}

private enum AppRuntimeFlags {
    static var orientationState = false
}

// True when horizontal, false when vertical.
var orientationState: Bool {
    AppRuntimeFlags.orientationState
}

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
    let isHiddenInNormalMode: Bool

    var primaryDisplayText: String {
        sendTexts.joined(separator: ":")
    }

    var displayUsesAlternateText: Bool {
        alternateDisplayText != nil
    }
}

private let compactDisplayModifierTokens: [(symbol: Character, code: String)] = [
    ("⌃", "ct"),
    ("⌥", "op"),
    ("⇧", "sh"),
    ("⌘", "cm")
]

func parsedActionTokens(from text: String) -> [String] {
    text
        .components(separatedBy: ":")
        .flatMap { component -> [String] in
            if !component.isEmpty,
               component.allSatisfy({ $0.isWhitespace && !$0.isNewline }) {
                return [" "]
            }

            let trimmedComponent = component.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedComponent.isEmpty else {
                return []
            }

            if trimmedComponent.caseInsensitiveCompare("sp") == .orderedSame {
                return [" "]
            }

            return expandedCompactDisplayModifierToken(trimmedComponent) ?? [trimmedComponent]
        }
}

private func expandedCompactDisplayModifierToken(_ token: String) -> [String]? {
    let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedToken.isEmpty else {
        return nil
    }

    var remainingToken = trimmedToken[...]
    var activeModifierCodes = Set<String>()

    while let firstCharacter = remainingToken.first,
          let matchingModifier = compactDisplayModifierTokens.first(where: { $0.symbol == firstCharacter }) {
        activeModifierCodes.insert(matchingModifier.code)
        remainingToken.removeFirst()
    }

    guard !activeModifierCodes.isEmpty else {
        return nil
    }

    var expandedTokens = compactDisplayModifierTokens
        .compactMap { activeModifierCodes.contains($0.code) ? $0.code : nil }

    let remainingComponent = String(remainingToken).trimmingCharacters(in: .whitespacesAndNewlines)
    if !remainingComponent.isEmpty {
        expandedTokens.append(remainingComponent)
    }

    return expandedTokens
}

private struct StoredGridDimensions: Codable {
    let columns: Int
    let rows: Int
}

func downsampledUIImage(at url: URL, maxPixelDimension: CGFloat) -> UIImage? {
    guard maxPixelDimension > 0 else {
        return UIImage(contentsOfFile: url.path)
    }

    let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, imageSourceOptions) else {
        return nil
    }

    let downsampleOptions = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: false,
        kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelDimension.rounded(.up))
    ] as CFDictionary

    guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
        return nil
    }

    return UIImage(cgImage: downsampledImage)
}

private enum ContentViewLaunchDestination: Hashable {
    case settings
}

struct ContentView: View {
	//
	//-----------------------------------------------------------------------------------------------
	// MARK: - BM:🔆 EMOJI LIST
	//
	// normal emoji map
	static let emojiSpeechConfigFilename = "emoji_speech_map.cfg"
	
	// default (start) emoji
	static let defaultEmojiSpeechConfigContents = """

	# Emoji Speech Map
	# ----------------
	# Edit this file to control how Text To Speech speaks emoji on the main screen.
	#
	# Emoji override format:
	# <emoji> = words to speak
	#
	# Examples:
	# ⏯ = play pause media
	# ⏩ = fast forward
	#
	# Suffix format:
	# suffix = word
	#
	# If an emoji has no explicit override, the app can look at its Unicode name.
	# If that generated name ends with one of the suffixes below, the suffix is
	# removed and the shorter phrase is spoken. Otherwise the emoji is spoken as-is.
	#

	⏯️ = play pause 
	⏸️ = pause
	⏹️ = stop
	⏺️ = record
	⏭️ = next track
	⏮️ = previous track
	◀️ = left
	▶️ = right
	⬅️ = left
	➡️ = right
	⏩ = fast forward
	⏪ = fast rewind
	🔼 = up
	🔽 = down
	⏏️ = eject
	🔀 = shuffle
	🔁 = repeat
	🔂 = repeat single
	"""
	//
	//-----------------------------------------------------------------------------------------------
	//
    private let defaultDocumentFontSize: Double = 20
    @AppStorage("selectedBackgroundImageIndex") private var selectedBackgroundImageIndex = 0
    @AppStorage("selectedBackgroundImageName") private var selectedBackgroundImageName = ""
    @AppStorage("selectedBackgroundImagePath") private var selectedBackgroundImagePath = ""
    @AppStorage("documentBackgroundImageNamesData") private var documentBackgroundImageNamesData = ""
    @AppStorage("documentBackgroundImagePathsData") private var documentBackgroundImagePathsData = ""
    @AppStorage("documentBackgroundImageOpacitiesData") private var documentBackgroundImageOpacitiesData = ""
    @AppStorage("documentGridDimensionsData") private var documentGridDimensionsData = ""
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
    @State private var rootNavigationPath = NavigationPath()
    @State private var isKeyboardScreenPresented = false
    @State private var isSettingsScreenPresented = true
    @State private var didPresentInitialSettingsScreen = false
    @State private var hasLoggedDeviceType = false
    @State private var lastLoggedOrientationState: Bool?

    var body: some View {
        NavigationStack(path: $rootNavigationPath) {
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
                            boxFontSize: Binding(
                                get: {
                                    fontSize(for: selectedDocumentName)
                                },
                                set: { newFontSize in
                                    updateDocumentFontSize(newFontSize)
                                }
                            ),
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
                            previousDocumentDisplayName: previousDocumentDisplayName,
                            adjacentPreviousDocumentDisplayName: adjacentPreviousDocumentDisplayName,
                            adjacentNextDocumentDisplayName: adjacentNextDocumentDisplayName,
                            selectDocumentNamedFromGrid: selectDocumentNamedFromGrid,
                            resizeVisibleBoxCount: resizeSelectedDocumentGrid,
                            moveFunctionKeySlot: moveSelectedDocumentSlot,
                            duplicateFunctionKeySlot: duplicateSelectedDocumentSlot,
                            updateFunctionKeySlot: updateSelectedDocumentSlot,
                            loadGridDimensions: loadStoredGridDimensions,
                            saveGridDimensions: { documentName, gridDimensions in
                                saveGridDimensions(gridDimensions, for: documentName)
                            },
                            openKeyboardScreen: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    isKeyboardScreenPresented = true
                                }
                            },
                            openSettingsScreen: {
                                showSettingsScreen()
                            },
                            isSettingsScreenPresented: isSettingsScreenPresented,
                            settingsBLEText: $settingsBLEText
                        )
                        .frame(width: containerWidth, height: containerHeight)
                        .offset(x: isKeyboardScreenPresented ? containerWidth : 0)
                    }
                    .frame(width: containerWidth, height: containerHeight)
                    .clipped()
                    .onAppear {
                        logDeviceTypeIfNeeded()
                    }
                }
            }
            .background { 
                mainScreenBackgroundView
            }
            .compatibleNavigationBarVisibility(isKeyboardScreenPresented ? .hidden : .visible)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(for: ContentViewLaunchDestination.self) { destination in
                switch destination {
                case .settings:
                    launchedSettingsScreen
                }
            }
        }
        .onAppear {
            presentInitialSettingsScreenIfNeeded()
        }
        .task {
            ensureDefaultFunctionKeysFile()
            ensureDefaultEmojiSpeechConfigFile()
            refreshDocumentFiles()
            refreshBackgroundImageFiles()
            selectInitialDocument()
            updateLoadedBackgroundImageForVisibleScreen()
            logDeviceTypeIfNeeded()
            refreshOrientationState()
            logOrientationStateIfNeeded()
        }
        .task {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            defer {
                UIDevice.current.endGeneratingDeviceOrientationNotifications()
            }

            for await _ in NotificationCenter.default.notifications(named: UIDevice.orientationDidChangeNotification) {
                refreshOrientationState()
                logOrientationStateIfNeeded()
            }
        }
        .onChange(of: selectedBackgroundImageIndex) {
            refreshBackgroundImageFiles()
            updateLoadedBackgroundImageForVisibleScreen()
        }
        .onChange(of: selectedBackgroundImagePath) {
            refreshBackgroundImageFiles()
            updateLoadedBackgroundImageForVisibleScreen()
        }
        .onChange(of: selectedBackgroundImageName) {
            refreshBackgroundImageFiles()
            saveBackgroundImageSelection(for: selectedDocumentName)
            updateLoadedBackgroundImageForVisibleScreen()
        }
        .onChange(of: isSettingsScreenPresented) {
            updateLoadedBackgroundImageForVisibleScreen()
        }
        .onChange(of: backgroundImageOpacity) {
            saveBackgroundImageOpacity(for: selectedDocumentName)
        }
    }

    private func logDeviceTypeIfNeeded() {
        guard !hasLoggedDeviceType else { return }
        hasLoggedDeviceType = true
        print("isPad:", isPad ? "iPad" : "iPhone")
    }

    private func refreshOrientationState() {
        if let activeScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) {
            let interfaceOrientation = activeScene.effectiveGeometry.interfaceOrientation
            if interfaceOrientation.isLandscape {
                AppRuntimeFlags.orientationState = true
                return
            }
            if interfaceOrientation.isPortrait {
                AppRuntimeFlags.orientationState = false
                return
            }

            if let keyWindow = activeScene.keyWindow {
                AppRuntimeFlags.orientationState = keyWindow.bounds.width > keyWindow.bounds.height
                return
            }
        }

        let deviceOrientation = UIDevice.current.orientation
        if deviceOrientation.isLandscape {
            AppRuntimeFlags.orientationState = true
            return
        }
        if deviceOrientation.isPortrait {
            AppRuntimeFlags.orientationState = false
            return
        }

        AppRuntimeFlags.orientationState = isPad
    }

    private func logOrientationStateIfNeeded() {
        let currentOrientationState = orientationState
        guard lastLoggedOrientationState != currentOrientationState else { return }
        lastLoggedOrientationState = currentOrientationState
		print("orientationState:", currentOrientationState ? "horizontal" : "vertical")
    }

    private static func defaultFunctionKeyTitles() -> [String] {
        (1...defaultNamedFunctionKeyCount).map { "F\($0)" }
    }

    private static func makeDefaultFunctionKeys() -> [FunctionKeyEntry] {
        let namedEntries = (1...defaultNamedFunctionKeyCount).map { index in
            FunctionKeyEntry(rawLine: "F\(index)", sendTexts: ["F\(index)"], alternateDisplayText: nil, buttonColorCode: nil, isBlankPlaceholder: false, isHiddenInNormalMode: false)
        }
        let emptyEntries = Array(
            repeating: FunctionKeyEntry(rawLine: "", sendTexts: [], alternateDisplayText: nil, buttonColorCode: nil, isBlankPlaceholder: false, isHiddenInNormalMode: false),
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

    private func ensureDefaultEmojiSpeechConfigFile() {
        guard let documentsDirectoryURL = documentsDirectoryURL() else {
            return
        }

        let fileURL = documentsDirectoryURL.appendingPathComponent(Self.emojiSpeechConfigFilename)

        guard db_overwriteConfigFile || !FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        try? Self.defaultEmojiSpeechConfigContents.write(to: fileURL, atomically: true, encoding: .utf8)
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
        let maxPixelDimension = max(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * UIScreen.main.scale

        if !selectedBackgroundImagePath.isEmpty {
            let pathImageURL = URL(fileURLWithPath: selectedBackgroundImagePath)
            if FileManager.default.fileExists(atPath: pathImageURL.path),
               let pathImage = downsampledUIImage(at: pathImageURL, maxPixelDimension: maxPixelDimension) {
                loadedBackgroundImage = pathImage
                selectedBackgroundImageName = pathImageURL.lastPathComponent
                if let pathImageIndex = backgroundImageFiles.firstIndex(where: { $0.path == pathImageURL.path }) {
                    selectedBackgroundImageIndex = pathImageIndex + 1
                }
                return
            }
        }

        if !selectedBackgroundImageName.isEmpty,
           let namedImageURL = backgroundImageFiles.first(where: { $0.lastPathComponent == selectedBackgroundImageName }) {
            loadedBackgroundImage = downsampledUIImage(at: namedImageURL, maxPixelDimension: maxPixelDimension)
            selectedBackgroundImagePath = namedImageURL.path
            if let namedImageIndex = backgroundImageFiles.firstIndex(where: { $0.lastPathComponent == selectedBackgroundImageName }) {
                selectedBackgroundImageIndex = namedImageIndex + 1
            }
            return
        }

        guard selectedBackgroundImageIndex > 0 else {
            selectedBackgroundImagePath = ""
            selectedBackgroundImageName = ""
            loadedBackgroundImage = nil
            return
        }

        let imageIndex = selectedBackgroundImageIndex - 1
        guard backgroundImageFiles.indices.contains(imageIndex) else {
            loadedBackgroundImage = nil
            return
        }

        let resolvedImageURL = backgroundImageFiles[imageIndex]
        selectedBackgroundImagePath = resolvedImageURL.path
        selectedBackgroundImageName = resolvedImageURL.lastPathComponent
        loadedBackgroundImage = downsampledUIImage(at: resolvedImageURL, maxPixelDimension: maxPixelDimension)
    }

    private func updateLoadedBackgroundImageForVisibleScreen() {
        if isSettingsScreenPresented {
            loadedBackgroundImage = nil
        } else {
            reloadBackgroundImage()
        }
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
            restoreBackgroundImageSelection(for: selectedDocumentName)
        } catch {
            functionKeySlotLines = []
            functionKeys = Array(repeating: FunctionKeyEntry(rawLine: "", sendTexts: [], alternateDisplayText: nil, buttonColorCode: nil, isBlankPlaceholder: false, isHiddenInNormalMode: false), count: maxFunctionKeyCount)
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
                return FunctionKeyEntry(rawLine: "", sendTexts: [], alternateDisplayText: nil, buttonColorCode: nil, isBlankPlaceholder: false, isHiddenInNormalMode: false)
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

    private func loadDocumentBackgroundImageNames() -> [String: String] {
        guard let data = documentBackgroundImageNamesData.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }

        return decoded
    }

    private func saveDocumentBackgroundImageNames(_ mappings: [String: String]) {
        guard let data = try? JSONEncoder().encode(mappings),
              let encoded = String(data: data, encoding: .utf8) else {
            return
        }

        documentBackgroundImageNamesData = encoded
    }

    private func loadDocumentBackgroundImagePaths() -> [String: String] {
        guard let data = documentBackgroundImagePathsData.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }

        return decoded
    }

    private func saveDocumentBackgroundImagePaths(_ mappings: [String: String]) {
        guard let data = try? JSONEncoder().encode(mappings),
              let encoded = String(data: data, encoding: .utf8) else {
            return
        }

        documentBackgroundImagePathsData = encoded
    }

    private func loadDocumentBackgroundImageOpacities() -> [String: Double] {
        guard let data = documentBackgroundImageOpacitiesData.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: Double].self, from: data) else {
            return [:]
        }

        return decoded
    }

    private func saveDocumentBackgroundImageOpacities(_ mappings: [String: Double]) {
        guard let data = try? JSONEncoder().encode(mappings),
              let encoded = String(data: data, encoding: .utf8) else {
            return
        }

        documentBackgroundImageOpacitiesData = encoded
    }

    private func loadDocumentGridDimensions() -> [String: StoredGridDimensions] {
        guard let data = documentGridDimensionsData.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: StoredGridDimensions].self, from: data) else {
            return [:]
        }

        return decoded
    }

    private func saveDocumentGridDimensions(_ mappings: [String: StoredGridDimensions]) {
        guard let data = try? JSONEncoder().encode(mappings),
              let encoded = String(data: data, encoding: .utf8) else {
            return
        }

        documentGridDimensionsData = encoded
    }

    private func loadStoredGridDimensions(for documentName: String, requiredBoxCount: Int) -> GridDimensions {
        let trimmedDocumentName = documentName.trimmingCharacters(in: .whitespacesAndNewlines)
        let minimumRequiredCount = max(requiredBoxCount, 1)

        guard !trimmedDocumentName.isEmpty else {
            return functionKeyGridDimensions(for: minimumRequiredCount)
        }

        let mappings = loadDocumentGridDimensions()
        if let storedDimensions = mappings[trimmedDocumentName] {
            let sanitizedColumns = max(storedDimensions.columns, 1)
            let sanitizedRows = max(storedDimensions.rows, 1)
            if sanitizedColumns * sanitizedRows >= minimumRequiredCount,
               sanitizedColumns * sanitizedRows <= maxFunctionKeyCount {
                return (columns: sanitizedColumns, rows: sanitizedRows)
            }
        }

        return functionKeyGridDimensions(for: minimumRequiredCount)
    }

    private func saveGridDimensions(_ gridDimensions: GridDimensions, for documentName: String) {
        let trimmedDocumentName = documentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDocumentName.isEmpty else {
            return
        }

        var mappings = loadDocumentGridDimensions()
        mappings[trimmedDocumentName] = StoredGridDimensions(
            columns: max(gridDimensions.columns, 1),
            rows: max(gridDimensions.rows, 1)
        )
        saveDocumentGridDimensions(mappings)
    }

    private func saveBackgroundImageOpacity(for documentName: String) {
        let trimmedDocumentName = documentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDocumentName.isEmpty else {
            return
        }

        var opacityMappings = loadDocumentBackgroundImageOpacities()
        opacityMappings[trimmedDocumentName] = backgroundImageOpacity
        saveDocumentBackgroundImageOpacities(opacityMappings)
    }

    private func restoreBackgroundImageOpacity(for documentName: String) {
        let trimmedDocumentName = documentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDocumentName.isEmpty else {
            backgroundImageOpacity = 0.5
            return
        }

        let opacityMappings = loadDocumentBackgroundImageOpacities()
        backgroundImageOpacity = opacityMappings[trimmedDocumentName] ?? 0.5
    }

    private func saveBackgroundImageSelection(for documentName: String) {
        let trimmedDocumentName = documentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDocumentName.isEmpty else {
            return
        }

        var nameMappings = loadDocumentBackgroundImageNames()
        var pathMappings = loadDocumentBackgroundImagePaths()
        if selectedBackgroundImageName.isEmpty {
            nameMappings.removeValue(forKey: trimmedDocumentName)
            pathMappings.removeValue(forKey: trimmedDocumentName)
        } else {
            nameMappings[trimmedDocumentName] = selectedBackgroundImageName
            if !selectedBackgroundImagePath.isEmpty {
                pathMappings[trimmedDocumentName] = selectedBackgroundImagePath
            } else {
                pathMappings.removeValue(forKey: trimmedDocumentName)
            }
        }
        saveDocumentBackgroundImageNames(nameMappings)
        saveDocumentBackgroundImagePaths(pathMappings)
    }

    private func restoreBackgroundImageSelection(for documentName: String) {
        let trimmedDocumentName = documentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDocumentName.isEmpty else {
            selectedBackgroundImageIndex = 0
            selectedBackgroundImagePath = ""
            selectedBackgroundImageName = ""
            backgroundImageOpacity = 0.5
            loadedBackgroundImage = nil
            return
        }

        restoreBackgroundImageOpacity(for: trimmedDocumentName)

        let nameMappings = loadDocumentBackgroundImageNames()
        let pathMappings = loadDocumentBackgroundImagePaths()
        let savedImagePath = pathMappings[trimmedDocumentName] ?? ""
        let savedImageName = nameMappings[trimmedDocumentName] ?? ""

        if !savedImagePath.isEmpty,
           let pathImageURL = backgroundImageFiles.first(where: { $0.path == savedImagePath }) {
            selectedBackgroundImagePath = pathImageURL.path
            selectedBackgroundImageName = pathImageURL.lastPathComponent
            selectedBackgroundImageIndex = (backgroundImageFiles.firstIndex(where: { $0.path == pathImageURL.path }) ?? -1) + 1
            reloadBackgroundImage()
            return
        }

        guard !savedImageName.isEmpty,
              let nameImageURL = backgroundImageFiles.first(where: { $0.lastPathComponent == savedImageName }) else {
            selectedBackgroundImageIndex = 0
            selectedBackgroundImagePath = ""
            selectedBackgroundImageName = ""
            loadedBackgroundImage = nil
            return
        }

        selectedBackgroundImagePath = nameImageURL.path
        selectedBackgroundImageName = nameImageURL.lastPathComponent
        if let imageIndex = backgroundImageFiles.firstIndex(where: { $0.path == nameImageURL.path }) {
            selectedBackgroundImageIndex = imageIndex + 1
        }
        reloadBackgroundImage()
    }

    @discardableResult
    private func resizeSelectedDocumentGrid(from oldDimensions: GridDimensions, to newDimensions: GridDimensions) -> Bool {
        let sanitizedOldDimensions = (
            columns: max(oldDimensions.columns, 1),
            rows: max(oldDimensions.rows, 1)
        )
        let sanitizedNewDimensions = (
            columns: max(newDimensions.columns, 1),
            rows: max(newDimensions.rows, 1)
        )
        let boundedCount = min(
            max(sanitizedNewDimensions.columns * sanitizedNewDimensions.rows, 1),
            maxFunctionKeyCount
        )
        let currentCount = sanitizedOldDimensions.columns * sanitizedOldDimensions.rows

        guard boundedCount == sanitizedNewDimensions.columns * sanitizedNewDimensions.rows else {
            return false
        }

        guard boundedCount != currentCount else {
            return true
        }

        let currentLines = Array(functionKeySlotLines.prefix(currentCount))

        guard let resizedLines = resizedSlotLines(
            from: currentLines,
            oldGrid: sanitizedOldDimensions,
            newGrid: sanitizedNewDimensions
        ) else {
            print("Can't resize grid because occupied buttons would fall outside the new dimensions.")
            return false
        }

        persistSlotLines(resizedLines)
        return true
    }

    private func resizedSlotLines(from slotLines: [String], oldGrid: GridDimensions, newGrid: GridDimensions) -> [String]? {
        let oldCount = oldGrid.columns * oldGrid.rows
        let newCount = newGrid.columns * newGrid.rows
        var remappedLines = Array(repeating: "_", count: newCount)
        let occupiedSlots: [(line: String, row: Int, column: Int)] = (0..<oldCount).compactMap { index in
            let line = index < slotLines.count ? slotLines[index] : "_"
            guard !isEmptyGridSlotLine(line) else {
                return nil
            }

            return (
                line: line,
                row: index / oldGrid.columns,
                column: index % oldGrid.columns
            )
        }

        guard !occupiedSlots.isEmpty else {
            return remappedLines
        }

        let minimumRow = occupiedSlots.map(\.row).min() ?? 0
        let maximumRow = occupiedSlots.map(\.row).max() ?? 0
        let minimumColumn = occupiedSlots.map(\.column).min() ?? 0
        let maximumColumn = occupiedSlots.map(\.column).max() ?? 0
        let occupiedHeight = maximumRow - minimumRow + 1
        let occupiedWidth = maximumColumn - minimumColumn + 1

        guard occupiedHeight <= newGrid.rows, occupiedWidth <= newGrid.columns else {
            return nil
        }

        let upwardShift = max(0, maximumRow - (newGrid.rows - 1))
        let leftwardShift = max(0, maximumColumn - (newGrid.columns - 1))

        for occupiedSlot in occupiedSlots {
            let newRow = occupiedSlot.row - upwardShift
            let newColumn = occupiedSlot.column - leftwardShift

            guard newRow >= 0,
                  newColumn >= 0,
                  newRow < newGrid.rows,
                  newColumn < newGrid.columns else {
                return nil
            }

            let newIndex = newRow * newGrid.columns + newColumn
            guard newIndex < newCount else {
                return nil
            }

            remappedLines[newIndex] = occupiedSlot.line
        }

        return remappedLines
    }

    @discardableResult
    private func moveSelectedDocumentSlot(from sourceIndex: Int, to targetIndex: Int, span: Int) -> Bool {
        guard sourceIndex != targetIndex,
              functionKeySlotLines.indices.contains(sourceIndex),
              targetIndex >= 0,
              targetIndex < maxFunctionKeyCount else {
            return false
        }

        let boundedSpan = max(1, min(span, 5))
        var updatedLines = functionKeySlotLines
        let gridDimensions = loadStoredGridDimensions(for: selectedDocumentName, requiredBoxCount: max(loadedFunctionKeySlotCount, 1))
        let sourceShape = buttonShape(startingAt: sourceIndex, in: updatedLines, gridDimensions: gridDimensions)
        let moveShape = boundedSpan >= 4 ? sourceShape : ButtonStorageShape(width: max(1, min(boundedSpan, 3)), height: 1)
        let targetIndexes = buttonIndexes(startingAt: targetIndex, shape: moveShape, gridDimensions: gridDimensions)
        let sourceIndexList = buttonIndexes(startingAt: sourceIndex, shape: moveShape, gridDimensions: gridDimensions)
        let sourceIndexes = Set(sourceIndexList)
        let targetIndexSet = Set(targetIndexes)
        let sourceOnlyIndexes = Set(sourceIndexList.filter { !targetIndexSet.contains($0) })
        let displacedMoveOffset = displacedMoveOffset(from: sourceIndex, to: targetIndex, shape: moveShape, gridDimensions: gridDimensions)
        var checkedTargetIndexes = Set<Int>()
        var targetOccupants: [MovedTargetOccupant] = []

        if let maximumTargetIndex = targetIndexes.max(), maximumTargetIndex >= updatedLines.count {
            updatedLines += Array(repeating: "_", count: maximumTargetIndex - updatedLines.count + 1)
        }

        let sourceLine = updatedLines[sourceIndex]

        guard !isBlankPlaceholderLine(sourceLine),
              !isButtonContinuationLine(sourceLine) else {
            return false
        }

        for sourceSlotIndex in sourceIndexes {
            guard sourceSlotIndex < updatedLines.count else {
                return false
            }

            if sourceSlotIndex == sourceIndex {
                guard !isBlankPlaceholderLine(updatedLines[sourceSlotIndex]),
                      !isButtonContinuationLine(updatedLines[sourceSlotIndex]) else {
                    return false
                }
            } else {
                guard isButtonContinuationLine(updatedLines[sourceSlotIndex]) else {
                    return false
                }
            }
        }

        for targetSlotIndex in targetIndexes {
            if checkedTargetIndexes.contains(targetSlotIndex) {
                continue
            }

            guard targetSlotIndex < updatedLines.count else {
                return false
            }

            if sourceIndexes.contains(targetSlotIndex) {
                continue
            }

            let targetLine = updatedLines[targetSlotIndex]
            if isBlankPlaceholderLine(targetLine) {
                continue
            }

            guard !isButtonContinuationLine(targetLine) else {
                return false
            }

            let targetShape = buttonShape(startingAt: targetSlotIndex, in: updatedLines, gridDimensions: gridDimensions)
            let occupiedIndexes = Set(buttonIndexes(startingAt: targetSlotIndex, shape: targetShape, gridDimensions: gridDimensions))
            guard occupiedIndexes.isSubset(of: targetIndexSet) else {
                return false
            }

            checkedTargetIndexes.formUnion(occupiedIndexes)
            targetOccupants.append(MovedTargetOccupant(index: targetSlotIndex, line: targetLine, shape: targetShape))
        }

        guard let targetPlacements = displacedTargetOccupantPlacements(
            targetOccupants,
            into: sourceOnlyIndexes,
            moveOffset: displacedMoveOffset,
            gridDimensions: gridDimensions
        ) else {
            return false
        }

        for sourceSlotIndex in sourceIndexes {
            updatedLines[sourceSlotIndex] = "_"
        }

        updatedLines[targetIndex] = sourceLine
        for continuation in continuationAssignments(startingAt: targetIndex, shape: moveShape) {
            updatedLines[continuation.index] = continuation.token
        }

        for placement in targetPlacements {
            updatedLines[placement.index] = placement.occupant.line
            for continuation in continuationAssignments(startingAt: placement.index, shape: placement.occupant.shape) {
                updatedLines[continuation.index] = continuation.token
            }
        }

        persistSlotLines(updatedLines)
        return true
    }

    private struct ButtonStorageShape {
        let width: Int
        let height: Int
    }

    private struct MovedTargetOccupant {
        let index: Int
        let line: String
        let shape: ButtonStorageShape
    }

    private func displacedMoveOffset(
        from sourceIndex: Int,
        to targetIndex: Int,
        shape: ButtonStorageShape,
        gridDimensions: GridDimensions
    ) -> Int {
        let columns = max(gridDimensions.columns, 1)
        let sourceRow = sourceIndex / columns
        let targetRow = targetIndex / columns

        if sourceRow == targetRow {
            return targetIndex > sourceIndex ? -shape.width : shape.width
        }

        return targetIndex > sourceIndex ? -(shape.height * columns) : (shape.height * columns)
    }

    private func displacedTargetOccupantPlacements(
        _ occupants: [MovedTargetOccupant],
        into availableIndexes: Set<Int>,
        moveOffset: Int,
        gridDimensions: GridDimensions
    ) -> [(occupant: MovedTargetOccupant, index: Int)]? {
        var placements: [(occupant: MovedTargetOccupant, index: Int)] = []
        var occupiedDestinationIndexes = Set<Int>()

        for occupant in occupants {
            let destinationIndex = occupant.index + moveOffset
            let columns = max(gridDimensions.columns, 1)
            let destinationColumn = destinationIndex % columns
            let destinationIndexes = Set(buttonIndexes(startingAt: destinationIndex, shape: occupant.shape, gridDimensions: gridDimensions))
            guard destinationIndex >= 0,
                  destinationColumn + occupant.shape.width <= columns,
                  (destinationIndex / columns) + occupant.shape.height <= gridDimensions.rows,
                  !destinationIndexes.isEmpty,
                  destinationIndexes.isSubset(of: availableIndexes),
                  destinationIndexes.isDisjoint(with: occupiedDestinationIndexes) else {
                return nil
            }

            occupiedDestinationIndexes.formUnion(destinationIndexes)
            placements.append((occupant, destinationIndex))
        }

        return placements
    }

    private func buttonShape(startingAt index: Int, in lines: [String], gridDimensions: GridDimensions) -> ButtonStorageShape {
        let columns = max(gridDimensions.columns, 1)
        let hasRight = lines.indices.contains(index + 1) && isWideButtonContinuationLine(lines[index + 1])
        let hasBelow = lines.indices.contains(index + columns) && isBlockButtonContinuationLine(lines[index + columns])
        let hasBelowRight = lines.indices.contains(index + columns + 1) && isBlockButtonContinuationLine(lines[index + columns + 1])
        let hasSecondRight = lines.indices.contains(index + 2) && isWideButtonContinuationLine(lines[index + 2])
        let hasThreeByThreeBlock = (1...2).allSatisfy { rowOffset in
            (0...2).allSatisfy { columnOffset in
                let blockIndex = index + (rowOffset * columns) + columnOffset
                return lines.indices.contains(blockIndex) && isBlockButtonContinuationLine(lines[blockIndex])
            }
        }

        if hasRight && hasSecondRight && hasThreeByThreeBlock {
            return ButtonStorageShape(width: 3, height: 3)
        }

        if hasRight && hasBelow && hasBelowRight {
            return ButtonStorageShape(width: 2, height: 2)
        }

        if hasRight {
            return ButtonStorageShape(width: hasSecondRight ? 3 : 2, height: 1)
        }

        return ButtonStorageShape(width: 1, height: 1)
    }

    private func buttonIndexes(startingAt index: Int, shape: ButtonStorageShape, gridDimensions: GridDimensions) -> [Int] {
        let columns = max(gridDimensions.columns, 1)
        var indexes: [Int] = []

        for rowOffset in 0..<shape.height {
            for columnOffset in 0..<shape.width {
                indexes.append(index + (rowOffset * columns) + columnOffset)
            }
        }

        return indexes
    }

    private func continuationAssignments(startingAt index: Int, shape: ButtonStorageShape) -> [(index: Int, token: String)] {
        let columns = max(loadStoredGridDimensions(for: selectedDocumentName, requiredBoxCount: max(loadedFunctionKeySlotCount, 1)).columns, 1)
        var assignments: [(index: Int, token: String)] = []

        for rowOffset in 0..<shape.height {
            for columnOffset in 0..<shape.width {
                guard rowOffset != 0 || columnOffset != 0 else {
                    continue
                }

                let token = rowOffset == 0 ? wideButtonContinuationToken : blockButtonContinuationToken
                assignments.append((index + (rowOffset * columns) + columnOffset, token))
            }
        }

        return assignments
    }

    @discardableResult
    private func duplicateSelectedDocumentSlot(from sourceIndex: Int, to targetIndex: Int) -> Bool {
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

        guard !isBlankPlaceholderLine(sourceLine),
              !isWideButtonContinuationLine(sourceLine),
              isBlankPlaceholderLine(targetLine) else {
            return false
        }

        updatedLines[targetIndex] = sourceLine
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

    private func isWideButtonContinuationLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines) == wideButtonContinuationToken
    }

    private func isBlockButtonContinuationLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines) == blockButtonContinuationToken
    }

    private func isButtonContinuationLine(_ line: String) -> Bool {
        isWideButtonContinuationLine(line) || isBlockButtonContinuationLine(line)
    }

    private func isEmptyGridSlotLine(_ line: String) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedLine.isEmpty || trimmedLine == "_"
    }

    private func functionKeyEntry(from line: String) -> FunctionKeyEntry {
        if isWideButtonContinuationLine(line) {
            return FunctionKeyEntry(rawLine: wideButtonContinuationToken, sendTexts: [], alternateDisplayText: nil, buttonColorCode: nil, isBlankPlaceholder: true, isHiddenInNormalMode: false)
        }

        if isBlockButtonContinuationLine(line) {
            return FunctionKeyEntry(rawLine: blockButtonContinuationToken, sendTexts: [], alternateDisplayText: nil, buttonColorCode: nil, isBlankPlaceholder: true, isHiddenInNormalMode: false)
        }

        if line == "_" || line.isEmpty {
            return FunctionKeyEntry(rawLine: "", sendTexts: [], alternateDisplayText: nil, buttonColorCode: nil, isBlankPlaceholder: true, isHiddenInNormalMode: false)
        }

        let components = line.components(separatedBy: "::")

        guard components.count >= 2 else {
            return FunctionKeyEntry(rawLine: line, sendTexts: [line], alternateDisplayText: nil, buttonColorCode: nil, isBlankPlaceholder: false, isHiddenInNormalMode: false)
        }

        let leftText = components[0]
        let rightSideComponents = components.dropFirst().filter { $0 != hiddenButtonMetadataToken }
        let isHiddenInNormalMode = components.dropFirst().contains(hiddenButtonMetadataToken)
        let rightText = rightSideComponents.joined(separator: "::").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !rightText.isEmpty else {
            return FunctionKeyEntry(
                rawLine: line,
                sendTexts: parsedSendTexts(from: leftText),
                alternateDisplayText: nil,
                buttonColorCode: nil,
                isBlankPlaceholder: false,
                isHiddenInNormalMode: isHiddenInNormalMode
            )
        }

        let sendTexts = parsedSendTexts(from: leftText)
        let parsedRightText = parsedRightTextAndColor(from: rightText)
        let usesLegacyVisibilitySymbol = parsedRightText.text == "eye" || parsedRightText.text == "eye.slash"
        return FunctionKeyEntry(
            rawLine: line,
            sendTexts: sendTexts,
            alternateDisplayText: usesLegacyVisibilitySymbol ? nil : parsedRightText.text,
            buttonColorCode: parsedRightText.colorCode,
            isBlankPlaceholder: false,
            isHiddenInNormalMode: isHiddenInNormalMode || parsedRightText.text == "eye.slash"
        )
    }

    private func parsedSendTexts(from leftText: String) -> [String] {
        let trimmedLeftText = leftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let loweredLeftText = trimmedLeftText.lowercased()

        if loweredLeftText.hasPrefix("http:") ||
            loweredLeftText.hasPrefix("https:") {
            return trimmedLeftText.isEmpty ? [] : [trimmedLeftText]
        }

        if isBareWidgetCommandText(loweredLeftText) {
            return parsedWidgetSendTexts(from: trimmedLeftText)
        }

        return parsedActionTokens(from: leftText)
    }

    private func isBareWidgetCommandText(_ loweredText: String) -> Bool {
        let widgetCommands = [
            "add", "minus", "power", "rnd", "random", "clock", "date",
            "dow", "sec", "min", "hour", "day", "month", "year", "timer",
            "stop", "stopwatch", "amb", "ambient"
        ]

        return widgetCommands.contains { command in
            loweredText == command || loweredText.hasPrefix("\(command) ")
        }
    }

    private func parsedWidgetSendTexts(from text: String) -> [String] {
        guard !text.isEmpty else {
            return []
        }

        var components: [String] = []
        var currentComponent = ""
        let characters = Array(text)
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character == ":", index + 1 < characters.count, characters[index + 1].isWhitespace {
                let trimmedComponent = currentComponent.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedComponent.isEmpty {
                    components.append(trimmedComponent)
                }
                currentComponent = ""
                index += 1

                while index < characters.count, characters[index].isWhitespace {
                    index += 1
                }
                continue
            }

            currentComponent.append(character)
            index += 1
        }

        let trimmedComponent = currentComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedComponent.isEmpty {
            components.append(trimmedComponent)
        }

        return components
    }

    private func parsedRightTextAndColor(from rightText: String) -> (text: String, colorCode: String?) {
        let components = rightText.components(separatedBy: ":")

        if let firstComponent = components.first,
           firstComponent.count == 1,
           let manualColorCode = firstComponent.lowercased().first,
           "lwbgorpucya12345".contains(manualColorCode) {
            let remainingText = components.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
            return (remainingText.isEmpty ? rightText : remainingText, String(manualColorCode))
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
        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
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
    private var launchedSettingsScreen: some View {
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
        .onAppear {
            isSettingsScreenPresented = true
        }
        .onDisappear {
            isSettingsScreenPresented = false
        }
    }

    private func presentInitialSettingsScreenIfNeeded() {
        guard isSettingsScreenPresented, !didPresentInitialSettingsScreen else {
            return
        }

        didPresentInitialSettingsScreen = true
        rootNavigationPath.append(ContentViewLaunchDestination.settings)
    }

    private func showSettingsScreen() {
        guard !isSettingsScreenPresented else {
            return
        }

        rootNavigationPath.append(ContentViewLaunchDestination.settings)
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
            var updatedGridDimensions = loadDocumentGridDimensions()
            if let existingGridDimensions = updatedGridDimensions.removeValue(forKey: selectedDocumentName) {
                updatedGridDimensions[targetFileName] = existingGridDimensions
                saveDocumentGridDimensions(updatedGridDimensions)
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
            var updatedGridDimensions = loadDocumentGridDimensions()
            updatedGridDimensions.removeValue(forKey: fileURL.lastPathComponent)
            saveDocumentGridDimensions(updatedGridDimensions)
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
            var updatedGridDimensions = loadDocumentGridDimensions()
            if let existingGridDimensions = updatedGridDimensions[fileURL.lastPathComponent] {
                updatedGridDimensions[targetURL.lastPathComponent] = existingGridDimensions
                saveDocumentGridDimensions(updatedGridDimensions)
            }
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

    private var adjacentPreviousDocumentDisplayName: String? {
        guard let currentIndex = documentFiles.firstIndex(where: { $0.lastPathComponent == selectedDocumentName }),
              currentIndex > 0 else {
            return nil
        }

        return displayName(for: documentFiles[currentIndex - 1].lastPathComponent)
    }

    private var adjacentNextDocumentDisplayName: String? {
        guard let currentIndex = documentFiles.firstIndex(where: { $0.lastPathComponent == selectedDocumentName }),
              currentIndex < documentFiles.count - 1 else {
            return nil
        }

        return displayName(for: documentFiles[currentIndex + 1].lastPathComponent)
    }

    private var previousDocumentDisplayName: String? {
        for previousName in documentNavigationHistory.reversed() {
            guard previousName != selectedDocumentName,
                  documentFiles.contains(where: { $0.lastPathComponent == previousName }) else {
                continue
            }

            return displayName(for: previousName)
        }

        return nil
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

extension View {
    @ViewBuilder
    func compatibleNavigationBarVisibility(_ visibility: Visibility) -> some View {
        if #available(iOS 18.0, *) {
            toolbarVisibility(visibility, for: .navigationBar)
        } else {
            toolbar(visibility, for: .navigationBar)
        }
    }
}

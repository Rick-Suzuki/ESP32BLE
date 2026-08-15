//
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

private let maxDocumentNavigationHistoryCount = 50

private enum AppRuntimeFlags {
    static var orientationState = false
}

private struct DocumentBackgroundImageConfig: Codable {
    var imageNames: [String: String] = [:]
    var imagePaths: [String: String] = [:]
    var opacities: [String: Double] = [:]

    var isEmpty: Bool {
        imageNames.isEmpty && imagePaths.isEmpty && opacities.isEmpty
    }
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

struct ContentView: View {
	//
	//-----------------------------------------------------------------------------------------------
	// MARK: - BM:🔆 EMOJI LIST-not used
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
    @AppStorage("mainGridBackgroundOpacity") private var mainGridBackgroundOpacity = 1.0
    @StateObject private var ble = BLEKeyboardManager()
    @State private var functionKeys = ContentView.makeDefaultFunctionKeys()
    @State private var functionKeySlotLines = ContentView.defaultFunctionKeyTitles()
    @State private var loadedFunctionKeySlotCount = defaultNamedFunctionKeyCount
    @State private var loadedScreenConfig: ScreenConfig?
    @State private var documentFiles: [URL] = []
    @State private var backgroundImageFiles: [URL] = []
    @State private var loadedBackgroundImage: UIImage?
    @State private var isRestoringBackgroundImageSelection = false
    @State private var documentNavigationHistory: [String] = []
    @State private var documentForwardNavigationHistory: [String] = []
    @AppStorage("selectedDocumentName") private var selectedDocumentName = screenDocumentFileName(forBaseName: "fnkeys")
    @AppStorage("documentFontSizesData") private var documentFontSizesData = ""
    @State private var documentFontSizeRefreshToken = 0
    @State private var settingsBLEText = ""
    @State private var isKeyboardScreenPresented = false
    @State private var isSettingsScreenPresented = true
    @State private var didPresentInitialSettingsScreen = false
    @State private var hasLoggedDeviceType = false
    @State private var lastLoggedOrientationState: Bool?
    @AppStorage("settingsStatusBarVisible") private var isStatusBarVisible = true

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                let containerWidth = geometry.size.width.isFinite ? max(0, geometry.size.width) : 0
                let containerHeight = geometry.size.height.isFinite ? max(0, geometry.size.height) : 0

                ZStack {
                    KeyboardScreen(ble: ble, isPresented: isKeyboardScreenPresented) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            db("STATE ContentView.KeyboardScreen.returnToMain current isKeyboardScreenPresented=\(isKeyboardScreenPresented) new=false thread=\(Thread.isMainThread ? "main" : "background")")
                            isKeyboardScreenPresented = false
                        }
                    }
                    .frame(width: containerWidth, height: containerHeight)
                    .offset(x: isKeyboardScreenPresented ? 0 : -containerWidth)
                    .onAppear {
                        db("DESTINATION KeyboardScreen.onAppear current isKeyboardScreenPresented=\(isKeyboardScreenPresented) new=visible thread=\(Thread.isMainThread ? "main" : "background")")
                    }
                    .onDisappear {
                        db("DESTINATION KeyboardScreen.onDisappear current isKeyboardScreenPresented=\(isKeyboardScreenPresented) new=hidden thread=\(Thread.isMainThread ? "main" : "background")")
                    }

                    let _ = documentFontSizeRefreshToken

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
                        mainGridBackgroundOpacity: Binding(
                            get: {
                                buttonsBackgroundOpacity(for: selectedDocumentName)
                            },
                            set: { newOpacity in
                                updateButtonsBackgroundOpacity(newOpacity)
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
                        goForwardToNextDocument: goForwardToNextDocument,
                        canGoBackToPreviousDocument: canGoBackToPreviousDocument,
                        previousDocumentDisplayName: previousDocumentDisplayName,
                        adjacentPreviousDocumentDisplayName: adjacentPreviousDocumentDisplayName,
                        adjacentNextDocumentDisplayName: adjacentNextDocumentDisplayName,
                        selectDocumentNamedFromGrid: selectDocumentNamedFromGrid,
                        resizeVisibleBoxCount: resizeSelectedDocumentGrid,
                        moveFunctionKeySlot: { sourceIndex, targetIndex, span, gridDimensions in
                            moveSelectedDocumentSlot(
                                from: sourceIndex,
                                to: targetIndex,
                                span: span,
                                gridDimensions: gridDimensions
                            )
                        },
                        duplicateFunctionKeySlot: duplicateSelectedDocumentSlot,
                        updateFunctionKeySlot: updateSelectedDocumentSlot,
                        loadGridDimensions: loadStoredGridDimensions,
                        saveGridDimensions: { documentName, gridDimensions in
                            saveGridDimensions(gridDimensions, for: documentName)
                        },
                        openKeyboardScreen: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                db("STATE ContentView.openKeyboardScreen current isKeyboardScreenPresented=\(isKeyboardScreenPresented) new=true thread=\(Thread.isMainThread ? "main" : "background")")
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
                    .ignoresSafeArea(.keyboard)
                    .offset(x: isKeyboardScreenPresented ? containerWidth : 0)
                    .onAppear {
                        db("DESTINATION MainScreen.onAppear current isKeyboardScreenPresented=\(isKeyboardScreenPresented) isSettingsScreenPresented=\(isSettingsScreenPresented) new=visible thread=\(Thread.isMainThread ? "main" : "background")")
                    }
                    .onDisappear {
                        db("DESTINATION MainScreen.onDisappear current isKeyboardScreenPresented=\(isKeyboardScreenPresented) isSettingsScreenPresented=\(isSettingsScreenPresented) new=hidden thread=\(Thread.isMainThread ? "main" : "background")")
                    }

                    if isSettingsScreenPresented {
                        launchedSettingsScreen
                            .frame(width: containerWidth, height: containerHeight)
                            .transition(.move(edge: .trailing))
                    }
                }
                .frame(width: containerWidth, height: containerHeight)
                .clipped()
                .ignoresSafeArea(.keyboard)
                .onAppear {
                    logDeviceTypeIfNeeded()
                }
            }
            .ignoresSafeArea(.keyboard)
        }
        .ignoresSafeArea(.keyboard)
        .background { 
            mainScreenBackgroundView
        }
        .id(isStatusBarVisible)
        .ignoresSafeArea(.keyboard)
        .statusBarHidden(!isStatusBarVisible)
        .onAppear {
            presentInitialSettingsScreenIfNeeded()
        }
        .task {
            ensureDefaultFunctionKeysFile()
            ensureDefaultEmojiSpeechConfigFile()
            refreshDocumentFiles()
            refreshBackgroundImageFiles()
            synchronizeDocumentBackgroundConfigFile()
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
            if !isRestoringBackgroundImageSelection {
                saveBackgroundImageSelection(for: selectedDocumentName)
            }
            updateLoadedBackgroundImageForVisibleScreen()
        }
        .onChange(of: isSettingsScreenPresented) {
            db("STATE ContentView.onChange isSettingsScreenPresented current=\(isSettingsScreenPresented) new=backgroundRefresh thread=\(Thread.isMainThread ? "main" : "background")")
            updateLoadedBackgroundImageForVisibleScreen()
        }
        .onChange(of: isKeyboardScreenPresented) { oldValue, newValue in
            db("STATE ContentView.onChange isKeyboardScreenPresented current=\(oldValue) new=\(newValue) thread=\(Thread.isMainThread ? "main" : "background")")
        }
        .onChange(of: selectedDocumentName) { oldValue, newValue in
            db("STATE ContentView.onChange selectedDocumentName current=\(oldValue) new=\(newValue) thread=\(Thread.isMainThread ? "main" : "background")")
        }
        .onChange(of: backgroundImageOpacity) {
            if !isRestoringBackgroundImageSelection {
                saveBackgroundImageOpacity(for: selectedDocumentName)
            }
        }
    }

    private func logDeviceTypeIfNeeded() {
        guard !hasLoggedDeviceType else { return }
        hasLoggedDeviceType = true
        db("isPad: %@", isPad ? "iPad" : "iPhone")
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
		db("orientationState: %@", currentOrientationState ? "horizontal" : "vertical")
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

        let fileURL = documentsDirectoryURL.appendingPathComponent(screenDocumentFileName(forBaseName: "fnkeys"))
        let legacyFileURL = documentsDirectoryURL.appendingPathComponent("fnkeys.\(legacyScreenDocumentFileExtension)")

        if !FileManager.default.fileExists(atPath: fileURL.path),
           !FileManager.default.fileExists(atPath: legacyFileURL.path) {
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
            db("STATE ContentView.refreshDocumentFiles current documentFiles.count=\(documentFiles.count) new=0 thread=\(Thread.isMainThread ? "main" : "background")")
            documentFiles = []
            return
        }

        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: documentsDirectoryURL,
                includingPropertiesForKeys: [URLResourceKey.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            let updatedDocumentFiles = preferredScreenDocumentURLs(
                from: urls.filter { url in
                    let values = try? url.resourceValues(forKeys: [URLResourceKey.isRegularFileKey])
                    return values?.isRegularFile == true
                }
            )
            ensureScreenConfigFilesFromAppStorageFallback(for: updatedDocumentFiles)
            db("STATE ContentView.refreshDocumentFiles current documentFiles.count=\(documentFiles.count) new=\(updatedDocumentFiles.count) thread=\(Thread.isMainThread ? "main" : "background")")
            documentFiles = updatedDocumentFiles
        } catch {
            db("STATE ContentView.refreshDocumentFiles current documentFiles.count=\(documentFiles.count) new=0 error=\(error.localizedDescription) thread=\(Thread.isMainThread ? "main" : "background")")
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
            selectedDocumentName = screenDocumentFileName(forBaseName: "fnkeys")
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
        db("ENTER ContentView.loadFunctionKeys current selectedDocumentName=\(selectedDocumentName) new=\(fileURL.lastPathComponent) thread=\(Thread.isMainThread ? "main" : "background")")
        do {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            let loadedTitles = normalizedSlotLines(from: contents)
            loadedScreenConfig = loadScreenConfigForDocument(
                fileURL,
                requiredBoxCount: min(max(loadedTitles.count, 1), maxFunctionKeyCount)
            )
            applySlotLines(loadedTitles)
            db("STATE ContentView.loadFunctionKeys current selectedDocumentName=\(selectedDocumentName) new=\(fileURL.lastPathComponent) thread=\(Thread.isMainThread ? "main" : "background")")
            selectedDocumentName = fileURL.lastPathComponent
            restoreBackgroundImageSelection(for: selectedDocumentName)
            db("EXIT ContentView.loadFunctionKeys current selectedDocumentName=\(selectedDocumentName) new=\(fileURL.lastPathComponent) thread=\(Thread.isMainThread ? "main" : "background")")
        } catch {
            loadedScreenConfig = nil
            db("STATE ContentView.loadFunctionKeys error current functionKeySlotLines.count=\(functionKeySlotLines.count) new=0 thread=\(Thread.isMainThread ? "main" : "background")")
            functionKeySlotLines = []
            db("STATE ContentView.loadFunctionKeys error current functionKeys.count=\(functionKeys.count) new=\(maxFunctionKeyCount) thread=\(Thread.isMainThread ? "main" : "background")")
            functionKeys = Array(repeating: FunctionKeyEntry(rawLine: "", sendTexts: [], alternateDisplayText: nil, buttonColorCode: nil, isBlankPlaceholder: false, isHiddenInNormalMode: false), count: maxFunctionKeyCount)
            db("STATE ContentView.loadFunctionKeys error current loadedFunctionKeySlotCount=\(loadedFunctionKeySlotCount) new=0 thread=\(Thread.isMainThread ? "main" : "background")")
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

    private func escapedSlotLineForPersistence(_ line: String) -> String {
        line
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    private func applySlotLines(_ slotLines: [String]) {
        db("STATE ContentView.applySlotLines current functionKeySlotLines.count=\(functionKeySlotLines.count) new=\(min(slotLines.count, maxFunctionKeyCount)) thread=\(Thread.isMainThread ? "main" : "background")")
        functionKeySlotLines = Array(slotLines.prefix(maxFunctionKeyCount))
        let parsedFunctionKeys = normalizedFunctionKeys(from: functionKeySlotLines)
        db("STATE ContentView.applySlotLines current functionKeys.count=\(functionKeys.count) new=\(parsedFunctionKeys.entries.count) thread=\(Thread.isMainThread ? "main" : "background")")
        functionKeys = parsedFunctionKeys.entries
        db("STATE ContentView.applySlotLines current loadedFunctionKeySlotCount=\(loadedFunctionKeySlotCount) new=\(parsedFunctionKeys.definedSlotCount) thread=\(Thread.isMainThread ? "main" : "background")")
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
        documentURL(forDocumentName: selectedDocumentName)
    }

    private func documentURL(forDocumentName documentName: String) -> URL? {
        if let matchingURL = documentFiles.first(where: { $0.lastPathComponent == documentName }) {
            return matchingURL
        }

        if isScreenDocumentFileName(documentName),
           let matchingURL = documentFiles.first(where: {
               screenDocumentBaseKey(for: $0.lastPathComponent) == screenDocumentBaseKey(for: documentName)
           }) {
            return matchingURL
        }

        return documentsDirectoryURL()?.appendingPathComponent(documentName)
    }

    private func persistSlotLines(_ slotLines: [String]) {
        db("ENTER ContentView.persistSlotLines count=\(slotLines.count)")
        guard let selectedDocumentURL = selectedDocumentURL() else {
            db("ENTER ContentView.persistSlotLines applySlotLines no selectedDocumentURL")
            applySlotLines(slotLines)
            db("EXIT ContentView.persistSlotLines no selectedDocumentURL")
            return
        }

        let normalizedLines = Array(slotLines.prefix(maxFunctionKeyCount))
            .map(escapedSlotLineForPersistence)
        let contents = normalizedLines.joined(separator: "\n")

        do {
            db("ENTER ContentView.persistSlotLines write url=\(selectedDocumentURL.lastPathComponent) bytes=\(contents.utf8.count)")
            try contents.write(to: selectedDocumentURL, atomically: true, encoding: .utf8)
            db("EXIT ContentView.persistSlotLines write")
            db("ENTER ContentView.persistSlotLines applySlotLines")
            applySlotLines(normalizedLines)
            db("EXIT ContentView.persistSlotLines")
        } catch {
            db("ENTER ContentView.persistSlotLines loadFunctionKeys after write failure error=\(error.localizedDescription)")
            loadFunctionKeys(from: selectedDocumentURL)
            db("EXIT ContentView.persistSlotLines error")
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
        if fileName == selectedDocumentName,
           let config = loadedScreenConfig {
            return config.fontSize
        }

        return loadDocumentFontSizes()[fileName] ?? defaultDocumentFontSize
    }

    private func updateDocumentFontSize(_ newFontSize: Double) {
        var updatedFontSizes = loadDocumentFontSizes()
        updatedFontSizes[selectedDocumentName] = newFontSize
        saveDocumentFontSizes(updatedFontSizes)

        if let selectedDocumentURL = selectedDocumentURL() {
            var updatedConfig = loadedScreenConfig ?? screenConfigFromAppStorageFallback(
                for: selectedDocumentName,
                requiredBoxCount: requiredBoxCountForDocumentURL(selectedDocumentURL)
            )
            updatedConfig.fontSize = newFontSize
            loadedScreenConfig = updatedConfig
            _ = saveScreenConfig(updatedConfig, for: selectedDocumentURL)
        } else if var updatedConfig = loadedScreenConfig {
            updatedConfig.fontSize = newFontSize
            loadedScreenConfig = updatedConfig
        }

        documentFontSizeRefreshToken += 1
    }

    private func buttonsBackgroundOpacity(for fileName: String) -> Double {
        if fileName == selectedDocumentName,
           let configOpacity = loadedScreenConfig?.buttonsBackgroundOpacity {
            return configOpacity
        }

        return mainGridBackgroundOpacity
    }

    private func updateButtonsBackgroundOpacity(_ newOpacity: Double) {
        let sanitizedOpacity = min(max(newOpacity, 0), 1)
        mainGridBackgroundOpacity = sanitizedOpacity

        updateScreenConfig(for: selectedDocumentName) { config in
            config.buttonsBackgroundOpacity = sanitizedOpacity
        }
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

    private func loadScreenConfigForDocument(_ documentURL: URL, requiredBoxCount: Int) -> ScreenConfig {
        if let config = loadScreenConfig(for: documentURL) {
            return config
        }

        return screenConfigFromAppStorageFallback(
            for: documentURL.lastPathComponent,
            requiredBoxCount: requiredBoxCount
        )
    }

    private func ensureScreenConfigFilesFromAppStorageFallback(for documentURLs: [URL]) {
        for documentURL in documentURLs where loadScreenConfig(for: documentURL) == nil {
            let requiredBoxCount = requiredBoxCountForDocumentURL(documentURL)
            let config = screenConfigFromAppStorageFallback(
                for: documentURL.lastPathComponent,
                requiredBoxCount: requiredBoxCount
            )
            _ = saveScreenConfig(config, for: documentURL)
        }
    }

    private func requiredBoxCountForDocumentURL(_ documentURL: URL) -> Int {
        guard let contents = try? String(contentsOf: documentURL, encoding: .utf8) else {
            return 1
        }

        return min(max(normalizedSlotLines(from: contents).count, 1), maxFunctionKeyCount)
    }

    private func screenConfigFromAppStorageFallback(for documentName: String, requiredBoxCount: Int) -> ScreenConfig {
        let fallbackConfig = defaultScreenConfig(for: documentName, requiredBoxCount: requiredBoxCount)
        let trimmedDocumentName = documentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDocumentName.isEmpty else {
            return fallbackConfig
        }

        let fontSize = loadDocumentFontSizes()[trimmedDocumentName] ?? fallbackConfig.fontSize
        let gridDimensions = appStorageGridDimensions(for: trimmedDocumentName, requiredBoxCount: requiredBoxCount)
        let backgroundImageName = fallbackBackgroundImageName(for: trimmedDocumentName)
        let backgroundOpacity = fallbackBackgroundImageOpacity(
            for: trimmedDocumentName,
            defaultOpacity: fallbackConfig.backgroundOpacity
        )
        let buttonsBackgroundOpacity = min(max(mainGridBackgroundOpacity, 0), 1)

        return ScreenConfig(
            schemaVersion: fallbackConfig.schemaVersion,
            fontSize: fontSize,
            grid: ScreenConfig.Grid(rows: gridDimensions.rows, columns: gridDimensions.columns),
            backgroundImageName: backgroundImageName,
            backgroundOpacity: backgroundOpacity,
            buttonsBackgroundOpacity: buttonsBackgroundOpacity
        )
    }

    private func fallbackBackgroundImageName(for documentName: String) -> String? {
        if let imageName = documentBackgroundConfigImageName(for: documentName) {
            return imageName
        }

        return appStorageBackgroundImageName(for: documentName)
    }

    private func documentBackgroundConfigImageName(for documentName: String) -> String? {
        guard let config = loadDocumentBackgroundImageConfigFile() else {
            return nil
        }

        if let imageName = config.imageNames[documentName], !imageName.isEmpty {
            return URL(fileURLWithPath: imageName).lastPathComponent
        }

        guard let imagePath = config.imagePaths[documentName], !imagePath.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: imagePath).lastPathComponent
    }

    private func fallbackBackgroundImageOpacity(for documentName: String, defaultOpacity: Double) -> Double {
        if let opacity = loadDocumentBackgroundImageConfigFile()?.opacities[documentName] {
            return min(max(opacity, 0), 1)
        }

        let appStorageOpacity = loadDocumentBackgroundImageOpacities()[documentName] ?? defaultOpacity
        return min(max(appStorageOpacity, 0), 1)
    }

    private func appStorageBackgroundImageName(for documentName: String) -> String? {
        let nameMappings = loadDocumentBackgroundImageNames()
        if let imageName = nameMappings[documentName], !imageName.isEmpty {
            return URL(fileURLWithPath: imageName).lastPathComponent
        }

        let pathMappings = loadDocumentBackgroundImagePaths()
        guard let imagePath = pathMappings[documentName], !imagePath.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: imagePath).lastPathComponent
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

    private var documentBackgroundImageConfigURL: URL? {
        documentsDirectoryURL()?.appendingPathComponent("document-backgrounds.json")
    }

    private var legacyDocumentBackgroundImageConfigURL: URL? {
        documentsDirectoryURL()?.appendingPathComponent(".document-backgrounds.json")
    }

    private func loadDocumentBackgroundImageConfigFile() -> DocumentBackgroundImageConfig? {
        let candidateURLs = [
            documentBackgroundImageConfigURL,
            legacyDocumentBackgroundImageConfigURL
        ].compactMap { $0 }

        guard let configURL = candidateURLs.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let data = try? Data(contentsOf: configURL) else {
            return nil
        }

        guard !data.isEmpty else {
            return DocumentBackgroundImageConfig()
        }

        return try? JSONDecoder().decode(DocumentBackgroundImageConfig.self, from: data)
    }

    private var visibleDocumentBackgroundImageConfigIsEmpty: Bool {
        guard let configURL = documentBackgroundImageConfigURL,
              FileManager.default.fileExists(atPath: configURL.path),
              let data = try? Data(contentsOf: configURL) else {
            return true
        }

        guard !data.isEmpty else {
            return true
        }

        return (try? JSONDecoder().decode(DocumentBackgroundImageConfig.self, from: data).isEmpty) ?? true
    }

    private func saveDocumentBackgroundImageConfigFile(_ config: DocumentBackgroundImageConfig) {
        guard let configURL = documentBackgroundImageConfigURL else {
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else {
            return
        }

        try? data.write(to: configURL, options: [.atomic])
    }

    private var hasDocumentBackgroundMappingsInAppStorage: Bool {
        !loadDocumentBackgroundImageNames().isEmpty ||
        !loadDocumentBackgroundImagePaths().isEmpty ||
        !loadDocumentBackgroundImageOpacities().isEmpty
    }

    private func documentBackgroundImageConfigFromAppStorage() -> DocumentBackgroundImageConfig {
        DocumentBackgroundImageConfig(
            imageNames: loadDocumentBackgroundImageNames(),
            imagePaths: loadDocumentBackgroundImagePaths(),
            opacities: loadDocumentBackgroundImageOpacities()
        )
    }

    private func writeDocumentBackgroundImageConfigFileFromAppStorage() {
        saveDocumentBackgroundImageConfigFile(documentBackgroundImageConfigFromAppStorage())
    }

    private func synchronizeDocumentBackgroundConfigFile() {
        let storedConfig = loadDocumentBackgroundImageConfigFile()

        // A non-empty document-backgrounds.json is the portable source of truth.
        // This lets copied config files replace stale AppStorage values on another iPad.
        if let storedConfig, !storedConfig.isEmpty {
            saveDocumentBackgroundImageNames(storedConfig.imageNames)
            saveDocumentBackgroundImagePaths(storedConfig.imagePaths)
            saveDocumentBackgroundImageOpacities(storedConfig.opacities)

            if visibleDocumentBackgroundImageConfigIsEmpty {
                saveDocumentBackgroundImageConfigFile(storedConfig)
            }
            return
        }

        if hasDocumentBackgroundMappingsInAppStorage, visibleDocumentBackgroundImageConfigIsEmpty {
            writeDocumentBackgroundImageConfigFileFromAppStorage()
        }
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

        if trimmedDocumentName == selectedDocumentName,
           let config = loadedScreenConfig {
            let sanitizedColumns = max(config.grid.columns, 1)
            let sanitizedRows = max(config.grid.rows, 1)
            if sanitizedColumns * sanitizedRows >= minimumRequiredCount,
               sanitizedColumns * sanitizedRows <= maxFunctionKeyCount {
                return (columns: sanitizedColumns, rows: sanitizedRows)
            }
        }

        return appStorageGridDimensions(for: trimmedDocumentName, requiredBoxCount: minimumRequiredCount)
    }

    private func appStorageGridDimensions(for documentName: String, requiredBoxCount: Int) -> GridDimensions {
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

        let sanitizedGridDimensions = (
            columns: max(gridDimensions.columns, 1),
            rows: max(gridDimensions.rows, 1)
        )

        var mappings = loadDocumentGridDimensions()
        mappings[trimmedDocumentName] = StoredGridDimensions(
            columns: sanitizedGridDimensions.columns,
            rows: sanitizedGridDimensions.rows
        )
        saveDocumentGridDimensions(mappings)

        guard let documentURL = documentURL(forDocumentName: trimmedDocumentName) else {
            return
        }

        var updatedConfig: ScreenConfig
        if trimmedDocumentName == selectedDocumentName,
           let config = loadedScreenConfig {
            updatedConfig = config
        } else if let config = loadScreenConfig(for: documentURL) {
            updatedConfig = config
        } else {
            updatedConfig = screenConfigFromAppStorageFallback(
                for: trimmedDocumentName,
                requiredBoxCount: sanitizedGridDimensions.columns * sanitizedGridDimensions.rows
            )
        }

        updatedConfig.grid = ScreenConfig.Grid(
            rows: sanitizedGridDimensions.rows,
            columns: sanitizedGridDimensions.columns
        )

        if trimmedDocumentName == selectedDocumentName {
            loadedScreenConfig = updatedConfig
        }

        _ = saveScreenConfig(updatedConfig, for: documentURL)
    }

    private func updateScreenConfig(for documentName: String, mutate: (inout ScreenConfig) -> Void) {
        let trimmedDocumentName = documentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDocumentName.isEmpty,
              let documentURL = documentURL(forDocumentName: trimmedDocumentName) else {
            return
        }

        var updatedConfig: ScreenConfig
        if trimmedDocumentName == selectedDocumentName,
           let config = loadedScreenConfig {
            updatedConfig = config
        } else if let config = loadScreenConfig(for: documentURL) {
            updatedConfig = config
        } else {
            updatedConfig = screenConfigFromAppStorageFallback(
                for: trimmedDocumentName,
                requiredBoxCount: requiredBoxCountForDocumentURL(documentURL)
            )
        }

        mutate(&updatedConfig)

        if trimmedDocumentName == selectedDocumentName {
            loadedScreenConfig = updatedConfig
        }

        _ = saveScreenConfig(updatedConfig, for: documentURL)
    }

    private func saveBackgroundImageOpacity(for documentName: String) {
        let trimmedDocumentName = documentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDocumentName.isEmpty else {
            return
        }

        let sanitizedOpacity = min(max(backgroundImageOpacity, 0), 1)
        var opacityMappings = loadDocumentBackgroundImageOpacities()
        opacityMappings[trimmedDocumentName] = sanitizedOpacity
        saveDocumentBackgroundImageOpacities(opacityMappings)
        writeDocumentBackgroundImageConfigFileFromAppStorage()

        updateScreenConfig(for: trimmedDocumentName) { config in
            config.backgroundOpacity = sanitizedOpacity
        }
    }

    private func restoreBackgroundImageOpacity(for documentName: String) {
        let trimmedDocumentName = documentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDocumentName.isEmpty else {
            backgroundImageOpacity = 0.5
            return
        }

        if trimmedDocumentName == selectedDocumentName,
           let config = loadedScreenConfig {
            backgroundImageOpacity = config.backgroundOpacity
            return
        }

        if let documentURL = documentURL(forDocumentName: trimmedDocumentName),
           let config = loadScreenConfig(for: documentURL) {
            backgroundImageOpacity = config.backgroundOpacity
            return
        }

        backgroundImageOpacity = fallbackBackgroundImageOpacity(for: trimmedDocumentName, defaultOpacity: 0.5)
    }

    private func saveBackgroundImageSelection(for documentName: String) {
        let trimmedDocumentName = documentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDocumentName.isEmpty else {
            return
        }

        var nameMappings = loadDocumentBackgroundImageNames()
        var pathMappings = loadDocumentBackgroundImagePaths()
        let portableImageName = selectedBackgroundImageName.isEmpty
            ? nil
            : URL(fileURLWithPath: selectedBackgroundImageName).lastPathComponent

        if let portableImageName {
            nameMappings[trimmedDocumentName] = portableImageName
            if !selectedBackgroundImagePath.isEmpty {
                pathMappings[trimmedDocumentName] = selectedBackgroundImagePath
            } else {
                pathMappings.removeValue(forKey: trimmedDocumentName)
            }
        } else {
            nameMappings.removeValue(forKey: trimmedDocumentName)
            pathMappings.removeValue(forKey: trimmedDocumentName)
        }
        saveDocumentBackgroundImageNames(nameMappings)
        saveDocumentBackgroundImagePaths(pathMappings)
        writeDocumentBackgroundImageConfigFileFromAppStorage()

        updateScreenConfig(for: trimmedDocumentName) { config in
            config.backgroundImageName = portableImageName
        }
    }

    private func restoreBackgroundImageSelection(for documentName: String) {
        let trimmedDocumentName = documentName.trimmingCharacters(in: .whitespacesAndNewlines)
        isRestoringBackgroundImageSelection = true
        DispatchQueue.main.async {
            isRestoringBackgroundImageSelection = false
        }

        guard !trimmedDocumentName.isEmpty else {
            selectedBackgroundImageIndex = 0
            selectedBackgroundImagePath = ""
            selectedBackgroundImageName = ""
            backgroundImageOpacity = 0.5
            loadedBackgroundImage = nil
            return
        }

        restoreBackgroundImageOpacity(for: trimmedDocumentName)

        let savedImageName: String
        let savedImagePath: String
        if trimmedDocumentName == selectedDocumentName,
           let config = loadedScreenConfig {
            savedImageName = config.backgroundImageName ?? ""
            savedImagePath = ""
        } else if let documentURL = documentURL(forDocumentName: trimmedDocumentName),
                  let config = loadScreenConfig(for: documentURL) {
            savedImageName = config.backgroundImageName ?? ""
            savedImagePath = ""
        } else {
            let documentBackgroundConfig = loadDocumentBackgroundImageConfigFile()
            let nameMappings = loadDocumentBackgroundImageNames()
            let pathMappings = loadDocumentBackgroundImagePaths()
            savedImagePath = documentBackgroundConfig?.imagePaths[trimmedDocumentName] ?? pathMappings[trimmedDocumentName] ?? ""
            savedImageName = documentBackgroundConfig?.imageNames[trimmedDocumentName] ?? nameMappings[trimmedDocumentName] ?? ""
        }

        if !savedImagePath.isEmpty,
           let pathImageURL = backgroundImageFiles.first(where: { $0.path == savedImagePath }) {
            selectedBackgroundImagePath = pathImageURL.path
            selectedBackgroundImageName = pathImageURL.lastPathComponent
            selectedBackgroundImageIndex = (backgroundImageFiles.firstIndex(where: { $0.path == pathImageURL.path }) ?? -1) + 1
            reloadBackgroundImage()
            return
        }

        guard !savedImageName.isEmpty,
              let nameImageURL = backgroundImageFiles.first(where: { $0.lastPathComponent == URL(fileURLWithPath: savedImageName).lastPathComponent }) else {
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
            db("Can't resize grid because occupied buttons would fall outside the new dimensions.")
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
    private func moveSelectedDocumentSlot(
        from sourceIndex: Int,
        to targetIndex: Int,
        span: Int,
        gridDimensions: GridDimensions
    ) -> Bool {
        guard sourceIndex != targetIndex,
              functionKeySlotLines.indices.contains(sourceIndex),
              targetIndex >= 0,
              targetIndex < maxFunctionKeyCount else {
            return false
        }

        var updatedLines = functionKeySlotLines
        // The drag target was calculated from the grid currently on screen. Reusing those
        // dimensions here keeps large-tile movement from being planned against stale saved
        // dimensions after a document resize or repair.
        let moveGridDimensions = (
            columns: max(gridDimensions.columns, 1),
            rows: max(gridDimensions.rows, 1)
        )
        let gridCellCount = moveGridDimensions.columns * moveGridDimensions.rows
        let requiredLineCount = max(gridCellCount, targetIndex + 1, sourceIndex + 1)

        if requiredLineCount > updatedLines.count {
            updatedLines += Array(repeating: "_", count: requiredLineCount - updatedLines.count)
        }

        guard let movePlan = resolvedTileMovePlan(
            sourceIndex: sourceIndex,
            targetIndex: targetIndex,
            lines: updatedLines,
            gridDimensions: moveGridDimensions
        ) else {
            return false
        }

        // Clear both the old footprints and the new footprints before writing anchors and
        // continuation markers. Without clearing the destination cells, stale wide/block
        // markers can survive and later make blank-looking cells behave as blocked cells.
        let oldIndexes = movePlan.flatMap { placement in
            buttonIndexes(startingAt: placement.tile.anchor, shape: placement.tile.shape, gridDimensions: moveGridDimensions)
        }
        let newIndexes = movePlan.flatMap { placement in
            buttonIndexes(startingAt: placement.anchor, shape: placement.tile.shape, gridDimensions: moveGridDimensions)
        }
        let affectedIndexes = Set(oldIndexes + newIndexes)

        for index in affectedIndexes where index < updatedLines.count {
            updatedLines[index] = "_"
        }

        for placement in movePlan {
            let targetIndexes = buttonIndexes(startingAt: placement.anchor, shape: placement.tile.shape, gridDimensions: moveGridDimensions)
            if let maximumTargetIndex = targetIndexes.max(), maximumTargetIndex >= updatedLines.count {
                updatedLines += Array(repeating: "_", count: maximumTargetIndex - updatedLines.count + 1)
            }

            updatedLines[placement.anchor] = placement.tile.line
            for continuation in continuationAssignments(
                startingAt: placement.anchor,
                shape: placement.tile.shape,
                gridDimensions: moveGridDimensions
            ) {
                updatedLines[continuation.index] = continuation.token
            }
        }

        persistSlotLines(updatedLines)
        return true
    }

    private struct StoredTileMove {
        let tile: StoredGridTile
        let anchor: Int
    }

    private struct StoredGridTile {
        let anchor: Int
        let line: String
        let shape: ButtonStorageShape

        var area: Int {
            shape.width * shape.height
        }
    }

    private struct ButtonStorageShape: Equatable {
        let width: Int
        let height: Int
    }

    private func resolvedTileMovePlan(
        sourceIndex: Int,
        targetIndex: Int,
        lines: [String],
        gridDimensions: GridDimensions
    ) -> [StoredTileMove]? {
        let tiles = storedGridTiles(in: lines, gridDimensions: gridDimensions)
        let tilesByAnchor = Dictionary(uniqueKeysWithValues: tiles.map { ($0.anchor, $0) })
        let occupancy = tileOccupancy(for: tiles, gridDimensions: gridDimensions)

        guard let sourceTile = tilesByAnchor[sourceIndex] else {
            return nil
        }

        let columns = max(gridDimensions.columns, 1)
        let sourceRow = sourceIndex / columns
        let sourceColumn = sourceIndex % columns
        let targetRow = targetIndex / columns
        let targetColumn = targetIndex % columns
        let rowDelta = targetRow - sourceRow
        let columnDelta = targetColumn - sourceColumn
        let rowStep = rowDelta == 0 ? 0 : (rowDelta > 0 ? 1 : -1)
        let columnStep = columnDelta == 0 ? 0 : (columnDelta > 0 ? 1 : -1)

        guard rowStep != 0 || columnStep != 0 else {
            return nil
        }

        guard rowStep == 0 || columnStep == 0 else {
            return nil
        }

        guard shapeFits(sourceTile.shape, startingAt: targetIndex, gridDimensions: gridDimensions) else {
            return nil
        }

        let destinationIndexes = Set(buttonIndexes(startingAt: targetIndex, shape: sourceTile.shape, gridDimensions: gridDimensions))
        let blockingAnchors = Set(destinationIndexes.compactMap { occupancy[$0] }.filter { $0 != sourceIndex })

        guard !blockingAnchors.isEmpty else {
            return [StoredTileMove(tile: sourceTile, anchor: targetIndex)]
        }

        if let localSlideMoves = directionalLocalSlideMoves(
            from: sourceTile,
            targetIndex: targetIndex,
            rowStep: rowStep,
            columnStep: columnStep,
            occupancy: occupancy,
            tilesByAnchor: tilesByAnchor,
            gridDimensions: gridDimensions
        ) {
            return localSlideMoves
        }

        if let crossingMoves = crossingPushMoves(
            from: sourceTile,
            blockingAnchors: blockingAnchors,
            rowStep: rowStep,
            columnStep: columnStep,
            occupancy: occupancy,
            tilesByAnchor: tilesByAnchor,
            gridDimensions: gridDimensions
        ) {
            return crossingMoves
        }

        if let edgePushMoves = edgePushMoves(
            from: sourceTile,
            targetIndex: targetIndex,
            blockingAnchors: blockingAnchors,
            rowStep: rowStep,
            columnStep: columnStep,
            occupancy: occupancy,
            tilesByAnchor: tilesByAnchor,
            gridDimensions: gridDimensions
        ) {
            return edgePushMoves
        }

        if let groupSwapMoves = directionalGroupSwapMoves(
            from: sourceTile,
            rowStep: rowStep,
            columnStep: columnStep,
            occupancy: occupancy,
            tilesByAnchor: tilesByAnchor,
            gridDimensions: gridDimensions
        ) {
            return groupSwapMoves
        }

        if let footprintSwapMoves = directionalFootprintGroupSwapMoves(
            from: sourceTile,
            rowStep: rowStep,
            columnStep: columnStep,
            occupancy: occupancy,
            tilesByAnchor: tilesByAnchor,
            gridDimensions: gridDimensions
        ) {
            return footprintSwapMoves
        }

        if let swapMoves = directionalCompatibleSwapMoves(
            from: sourceTile,
            rowStep: rowStep,
            columnStep: columnStep,
            tilesByAnchor: tilesByAnchor,
            occupancy: occupancy,
            gridDimensions: gridDimensions
        ) {
            return swapMoves
        }

        if blockingAnchors.count == 1,
           let blockingAnchor = blockingAnchors.first,
           let blockingTile = tilesByAnchor[blockingAnchor],
           blockingTile.shape == sourceTile.shape {
            return [
                StoredTileMove(tile: sourceTile, anchor: blockingTile.anchor),
                StoredTileMove(tile: blockingTile, anchor: sourceIndex)
            ]
        }

        // The named movement helpers above are intentionally exhaustive. If a
        // blocked move reaches this point, allowing a generic fallback would let
        // tiles jump through islands or move more than one logical step.
        return nil
    }

    private func directionalLocalSlideMoves(
        from sourceTile: StoredGridTile,
        targetIndex: Int,
        rowStep: Int,
        columnStep: Int,
        occupancy: [Int: Int],
        tilesByAnchor: [Int: StoredGridTile],
        gridDimensions: GridDimensions
    ) -> [StoredTileMove]? {
        // Local slide rule:
        // - the dragged tile moves exactly one cell in the drag direction
        // - only tiles on the newly-entered edge are displaced
        // - those displaced tiles move into the edge strip just vacated
        //
        // This is what lets a 3x3 tile move right one cell while the small
        // tiles on its right edge move into the 3x3 tile's old left edge.
        let sourceIndexes = Set(buttonIndexes(
            startingAt: sourceTile.anchor,
            shape: sourceTile.shape,
            gridDimensions: gridDimensions
        ))
        let destinationIndexes = Set(buttonIndexes(
            startingAt: targetIndex,
            shape: sourceTile.shape,
            gridDimensions: gridDimensions
        ))
        let enteringIndexes = destinationIndexes.subtracting(sourceIndexes)
        let enteringBlockers = Set(enteringIndexes.compactMap { occupancy[$0] }.filter { $0 != sourceTile.anchor })

        guard !enteringBlockers.isEmpty else {
            return nil
        }

        let columns = max(gridDimensions.columns, 1)
        let columnShift = columnStep == 0 ? 0 : -columnStep * sourceTile.shape.width
        let rowShift = rowStep == 0 ? 0 : -rowStep * sourceTile.shape.height
        var displacedMoves: [StoredTileMove] = []

        for blockingAnchor in enteringBlockers {
            guard let blockingTile = tilesByAnchor[blockingAnchor],
                  blockingTile.area < sourceTile.area else {
                return nil
            }

            let blockingIndexes = Set(buttonIndexes(
                startingAt: blockingTile.anchor,
                shape: blockingTile.shape,
                gridDimensions: gridDimensions
            ))

            // The whole blocking tile must sit on the entered strip. If only
            // part of a tile is on that edge, moving it would drag an island
            // from outside the affected lane and create hard-to-predict jumps.
            guard blockingIndexes.isSubset(of: enteringIndexes) else {
                return nil
            }

            let newRow = (blockingTile.anchor / columns) + rowShift
            let newColumn = (blockingTile.anchor % columns) + columnShift

            guard newRow >= 0, newColumn >= 0 else {
                return nil
            }

            let newAnchor = (newRow * columns) + newColumn

            guard shapeFits(blockingTile.shape, startingAt: newAnchor, gridDimensions: gridDimensions) else {
                return nil
            }

            displacedMoves.append(StoredTileMove(tile: blockingTile, anchor: newAnchor))
        }

        let plannedMoves = [StoredTileMove(tile: sourceTile, anchor: targetIndex)] + displacedMoves
        return movePlanFits(plannedMoves, occupancy: occupancy, gridDimensions: gridDimensions) ? plannedMoves : nil
    }

    private func edgePushMoves(
        from sourceTile: StoredGridTile,
        targetIndex: Int,
        blockingAnchors: Set<Int>,
        rowStep: Int,
        columnStep: Int,
        occupancy: [Int: Int],
        tilesByAnchor: [Int: StoredGridTile],
        gridDimensions: GridDimensions
    ) -> [StoredTileMove]? {
        guard blockingAnchors.count == 1,
              let blockingAnchor = blockingAnchors.first,
              let blockingTile = tilesByAnchor[blockingAnchor],
              sourceTile.area > blockingTile.area else {
            return nil
        }

        let columns = max(gridDimensions.columns, 1)
        let sourceRow = sourceTile.anchor / columns
        let sourceColumn = sourceTile.anchor % columns
        let blockingRow = blockingTile.anchor / columns
        let blockingColumn = blockingTile.anchor % columns
        let sourceRowRange = sourceRow..<(sourceRow + sourceTile.shape.height)
        let sourceColumnRange = sourceColumn..<(sourceColumn + sourceTile.shape.width)
        let blockingRowRange = blockingRow..<(blockingRow + blockingTile.shape.height)
        let blockingColumnRange = blockingColumn..<(blockingColumn + blockingTile.shape.width)

        let blockingNewAnchor: Int

        if columnStep != 0, rowStep == 0 {
            guard sourceRowRange.overlaps(blockingRowRange) else {
                return nil
            }

            let blockingNewColumn = blockingColumn - columnStep
            guard blockingNewColumn >= 0 else {
                return nil
            }

            blockingNewAnchor = blockingRow * columns + blockingNewColumn
        } else if rowStep != 0, columnStep == 0 {
            guard sourceColumnRange.overlaps(blockingColumnRange) else {
                return nil
            }

            let blockingNewRow = blockingRow - rowStep
            guard blockingNewRow >= 0 else {
                return nil
            }

            blockingNewAnchor = blockingNewRow * columns + blockingColumn
        } else {
            return nil
        }

        let moves = [
            StoredTileMove(tile: sourceTile, anchor: targetIndex),
            StoredTileMove(tile: blockingTile, anchor: blockingNewAnchor)
        ]

        return movePlanFits(moves, occupancy: occupancy, gridDimensions: gridDimensions) ? moves : nil
    }

    private func crossingPushMoves(
        from sourceTile: StoredGridTile,
        blockingAnchors: Set<Int>,
        rowStep: Int,
        columnStep: Int,
        occupancy: [Int: Int],
        tilesByAnchor: [Int: StoredGridTile],
        gridDimensions: GridDimensions
    ) -> [StoredTileMove]? {
        guard blockingAnchors.count == 1,
              let blockingAnchor = blockingAnchors.first,
              let blockingTile = tilesByAnchor[blockingAnchor],
              blockingTile.area > sourceTile.area else {
            return nil
        }

        let columns = max(gridDimensions.columns, 1)
        let sourceRow = sourceTile.anchor / columns
        let sourceColumn = sourceTile.anchor % columns
        let blockingRow = blockingTile.anchor / columns
        let blockingColumn = blockingTile.anchor % columns
        let sourceRowRange = sourceRow..<(sourceRow + sourceTile.shape.height)
        let sourceColumnRange = sourceColumn..<(sourceColumn + sourceTile.shape.width)
        let blockingRowRange = blockingRow..<(blockingRow + blockingTile.shape.height)
        let blockingColumnRange = blockingColumn..<(blockingColumn + blockingTile.shape.width)

        let sourceNewAnchor: Int
        let blockingNewAnchor: Int

        if columnStep != 0, rowStep == 0 {
            guard sourceRowRange.overlaps(blockingRowRange) else {
                return nil
            }

            let blockingNewColumn = blockingColumn - (columnStep * sourceTile.shape.width)
            let sourceNewColumn = columnStep > 0
                ? blockingNewColumn + blockingTile.shape.width
                : blockingNewColumn - sourceTile.shape.width

            guard blockingNewColumn >= 0, sourceNewColumn >= 0 else {
                return nil
            }

            blockingNewAnchor = blockingRow * columns + blockingNewColumn
            sourceNewAnchor = sourceRow * columns + sourceNewColumn
        } else if rowStep != 0, columnStep == 0 {
            guard sourceColumnRange.overlaps(blockingColumnRange) else {
                return nil
            }

            let blockingNewRow = blockingRow - (rowStep * sourceTile.shape.height)
            let sourceNewRow = rowStep > 0
                ? blockingNewRow + blockingTile.shape.height
                : blockingNewRow - sourceTile.shape.height

            guard blockingNewRow >= 0, sourceNewRow >= 0 else {
                return nil
            }

            blockingNewAnchor = blockingNewRow * columns + blockingColumn
            sourceNewAnchor = sourceNewRow * columns + sourceColumn
        } else {
            return nil
        }

        let moves = [
            StoredTileMove(tile: sourceTile, anchor: sourceNewAnchor),
            StoredTileMove(tile: blockingTile, anchor: blockingNewAnchor)
        ]

        return movePlanFits(moves, occupancy: occupancy, gridDimensions: gridDimensions) ? moves : nil
    }

    private func directionalGroupSwapMoves(
        from sourceTile: StoredGridTile,
        rowStep: Int,
        columnStep: Int,
        occupancy: [Int: Int],
        tilesByAnchor: [Int: StoredGridTile],
        gridDimensions: GridDimensions
    ) -> [StoredTileMove]? {
        let columns = max(gridDimensions.columns, 1)
        let sourceRow = sourceTile.anchor / columns
        let sourceColumn = sourceTile.anchor % columns

        if columnStep != 0, rowStep == 0 {
            let targetColumn = sourceColumn + columnStep
            guard targetColumn >= 0, targetColumn + sourceTile.shape.width <= columns else {
                return nil
            }

            return groupSwapMoves(
                sourceTile: sourceTile,
                targetAnchor: (sourceRow * columns) + targetColumn,
                occupancy: occupancy,
                tilesByAnchor: tilesByAnchor,
                gridDimensions: gridDimensions
            )
        }

        if rowStep != 0, columnStep == 0 {
            let targetRow = sourceRow + rowStep
            guard targetRow >= 0, targetRow + sourceTile.shape.height <= gridDimensions.rows else {
                return nil
            }

            return groupSwapMoves(
                sourceTile: sourceTile,
                targetAnchor: (targetRow * columns) + sourceColumn,
                occupancy: occupancy,
                tilesByAnchor: tilesByAnchor,
                gridDimensions: gridDimensions
            )
        }

        return nil
    }

    private func directionalFootprintGroupSwapMoves(
        from sourceTile: StoredGridTile,
        rowStep: Int,
        columnStep: Int,
        occupancy: [Int: Int],
        tilesByAnchor: [Int: StoredGridTile],
        gridDimensions: GridDimensions
    ) -> [StoredTileMove]? {
        let columns = max(gridDimensions.columns, 1)
        let sourceRow = sourceTile.anchor / columns
        let sourceColumn = sourceTile.anchor % columns

        // Footprint swaps handle a large tile exchanging places with a same-sized
        // rectangular group of smaller tiles. Example: a 2x2 tile can move left into
        // two stacked 2-wide tiles, while those two tiles move into the 2x2's old space.
        //
        // This is deliberately different from a one-cell slide. The target rectangle starts
        // one full source-width/height away, so the exchanged footprints do not overlap.
        if columnStep != 0, rowStep == 0 {
            let targetColumn = sourceColumn + (columnStep * sourceTile.shape.width)
            guard targetColumn >= 0, targetColumn + sourceTile.shape.width <= columns else {
                return nil
            }

            return groupSwapMoves(
                sourceTile: sourceTile,
                targetAnchor: (sourceRow * columns) + targetColumn,
                occupancy: occupancy,
                tilesByAnchor: tilesByAnchor,
                gridDimensions: gridDimensions
            )
        }

        if rowStep != 0, columnStep == 0 {
            let targetRow = sourceRow + (rowStep * sourceTile.shape.height)
            guard targetRow >= 0, targetRow + sourceTile.shape.height <= gridDimensions.rows else {
                return nil
            }

            return groupSwapMoves(
                sourceTile: sourceTile,
                targetAnchor: (targetRow * columns) + sourceColumn,
                occupancy: occupancy,
                tilesByAnchor: tilesByAnchor,
                gridDimensions: gridDimensions
            )
        }

        return nil
    }

    private func groupSwapMoves(
        sourceTile: StoredGridTile,
        targetAnchor: Int,
        occupancy: [Int: Int],
        tilesByAnchor: [Int: StoredGridTile],
        gridDimensions: GridDimensions
    ) -> [StoredTileMove]? {
        guard shapeFits(sourceTile.shape, startingAt: targetAnchor, gridDimensions: gridDimensions) else {
            return nil
        }

        let targetIndexes = Set(buttonIndexes(startingAt: targetAnchor, shape: sourceTile.shape, gridDimensions: gridDimensions))
        let blockingAnchors = Set(targetIndexes.compactMap { occupancy[$0] }.filter { $0 != sourceTile.anchor })

        guard !blockingAnchors.isEmpty else {
            return nil
        }

        let targetRow = targetAnchor / max(gridDimensions.columns, 1)
        let targetColumn = targetAnchor % max(gridDimensions.columns, 1)
        var moves = [StoredTileMove(tile: sourceTile, anchor: targetAnchor)]

        for anchor in blockingAnchors {
            guard let tile = tilesByAnchor[anchor] else {
                return nil
            }

            let tileIndexes = Set(buttonIndexes(startingAt: tile.anchor, shape: tile.shape, gridDimensions: gridDimensions))
            guard tileIndexes.isSubset(of: targetIndexes) else {
                return nil
            }

            let relativeRow = (tile.anchor / max(gridDimensions.columns, 1)) - targetRow
            let relativeColumn = (tile.anchor % max(gridDimensions.columns, 1)) - targetColumn
            let newAnchor = sourceTile.anchor + (relativeRow * max(gridDimensions.columns, 1)) + relativeColumn
            moves.append(StoredTileMove(tile: tile, anchor: newAnchor))
        }

        return movePlanFits(moves, occupancy: occupancy, gridDimensions: gridDimensions) ? moves : nil
    }

    private func directionalCompatibleSwapMoves(
        from sourceTile: StoredGridTile,
        rowStep: Int,
        columnStep: Int,
        tilesByAnchor: [Int: StoredGridTile],
        occupancy: [Int: Int],
        gridDimensions: GridDimensions
    ) -> [StoredTileMove]? {
        let columns = max(gridDimensions.columns, 1)
        let sourceRow = sourceTile.anchor / columns
        let sourceColumn = sourceTile.anchor % columns

        if columnStep != 0, rowStep == 0 {
            let scanRow = sourceRow
            var scanColumn = columnStep > 0 ? sourceColumn + sourceTile.shape.width : sourceColumn - 1

            while scanColumn >= 0, scanColumn < columns {
                let index = (scanRow * columns) + scanColumn
                if let anchor = occupancy[index], anchor != sourceTile.anchor {
                    guard let tile = tilesByAnchor[anchor],
                          tile.shape.height == sourceTile.shape.height,
                          tile.anchor / columns == sourceRow,
                          let moves = horizontalCompatibleSwapMoves(
                            sourceTile,
                            tile,
                            occupancy: occupancy,
                            gridDimensions: gridDimensions
                          ) else {
                        return nil
                    }

                    return moves
                }

                scanColumn += columnStep
            }

            return nil
        }

        if rowStep != 0, columnStep == 0 {
            let scanColumn = sourceColumn
            var scanRow = rowStep > 0 ? sourceRow + sourceTile.shape.height : sourceRow - 1

            while scanRow >= 0, scanRow < gridDimensions.rows {
                let index = (scanRow * columns) + scanColumn
                if let anchor = occupancy[index], anchor != sourceTile.anchor {
                    guard let tile = tilesByAnchor[anchor],
                          tile.shape.width == sourceTile.shape.width,
                          tile.anchor % columns == sourceColumn,
                          let moves = verticalCompatibleSwapMoves(
                            sourceTile,
                            tile,
                            occupancy: occupancy,
                            gridDimensions: gridDimensions
                          ) else {
                        return nil
                    }

                    return moves
                }

                scanRow += rowStep
            }
        }

        return nil
    }

    private func horizontalCompatibleSwapMoves(
        _ sourceTile: StoredGridTile,
        _ targetTile: StoredGridTile,
        occupancy: [Int: Int],
        gridDimensions: GridDimensions
    ) -> [StoredTileMove]? {
        let columns = max(gridDimensions.columns, 1)
        let sourceColumn = sourceTile.anchor % columns
        let targetColumn = targetTile.anchor % columns
        let leftAnchor = min(sourceTile.anchor, targetTile.anchor)
        let sourceIsLeft = sourceColumn < targetColumn
        let sourceAnchor = sourceIsLeft ? leftAnchor + targetTile.shape.width : leftAnchor
        let targetAnchor = sourceIsLeft ? leftAnchor : leftAnchor + sourceTile.shape.width
        let moves = [
            StoredTileMove(tile: sourceTile, anchor: sourceAnchor),
            StoredTileMove(tile: targetTile, anchor: targetAnchor)
        ]

        return movePlanFits(moves, occupancy: occupancy, gridDimensions: gridDimensions) ? moves : nil
    }

    private func verticalCompatibleSwapMoves(
        _ sourceTile: StoredGridTile,
        _ targetTile: StoredGridTile,
        occupancy: [Int: Int],
        gridDimensions: GridDimensions
    ) -> [StoredTileMove]? {
        let columns = max(gridDimensions.columns, 1)
        let sourceRow = sourceTile.anchor / columns
        let targetRow = targetTile.anchor / columns
        let topAnchor = min(sourceTile.anchor, targetTile.anchor)
        let sourceIsTop = sourceRow < targetRow
        let sourceAnchor = sourceIsTop ? topAnchor + (targetTile.shape.height * columns) : topAnchor
        let targetAnchor = sourceIsTop ? topAnchor : topAnchor + (sourceTile.shape.height * columns)
        let moves = [
            StoredTileMove(tile: sourceTile, anchor: sourceAnchor),
            StoredTileMove(tile: targetTile, anchor: targetAnchor)
        ]

        return movePlanFits(moves, occupancy: occupancy, gridDimensions: gridDimensions) ? moves : nil
    }

    private func movePlanFits(
        _ moves: [StoredTileMove],
        occupancy: [Int: Int],
        gridDimensions: GridDimensions
    ) -> Bool {
        let movingAnchors = Set(moves.map(\.tile.anchor))
        var plannedOccupancy = Set<Int>()

        for move in moves {
            guard shapeFits(move.tile.shape, startingAt: move.anchor, gridDimensions: gridDimensions) else {
                return false
            }

            for index in buttonIndexes(startingAt: move.anchor, shape: move.tile.shape, gridDimensions: gridDimensions) {
                if let anchor = occupancy[index], !movingAnchors.contains(anchor) {
                    return false
                }

                guard plannedOccupancy.insert(index).inserted else {
                    return false
                }
            }
        }

        return true
    }

    private func storedGridTiles(in lines: [String], gridDimensions: GridDimensions) -> [StoredGridTile] {
        let gridCellCount = gridDimensions.columns * gridDimensions.rows
        var claimedIndexes = Set<Int>()
        var tiles: [StoredGridTile] = []

        for index in 0..<gridCellCount {
            guard lines.indices.contains(index),
                  !claimedIndexes.contains(index),
                  !isBlankPlaceholderLine(lines[index]),
                  !isButtonContinuationLine(lines[index]) else {
                continue
            }

            let shape = buttonShape(startingAt: index, in: lines, gridDimensions: gridDimensions, claimedIndexes: claimedIndexes)
            let tileIndexes = buttonIndexes(startingAt: index, shape: shape, gridDimensions: gridDimensions)
            claimedIndexes.formUnion(tileIndexes)
            tiles.append(StoredGridTile(anchor: index, line: lines[index], shape: shape))
        }

        return tiles
    }

    private func tileOccupancy(for tiles: [StoredGridTile], gridDimensions: GridDimensions) -> [Int: Int] {
        var occupancy: [Int: Int] = [:]

        for tile in tiles {
            for index in buttonIndexes(startingAt: tile.anchor, shape: tile.shape, gridDimensions: gridDimensions) {
                occupancy[index] = tile.anchor
            }
        }

        return occupancy
    }

    private func shapeFits(_ shape: ButtonStorageShape, startingAt index: Int, gridDimensions: GridDimensions) -> Bool {
        let columns = max(gridDimensions.columns, 1)
        let row = index / columns
        let column = index % columns

        return index >= 0 &&
            column + shape.width <= columns &&
            row + shape.height <= gridDimensions.rows
    }

    private func buttonShape(
        startingAt index: Int,
        in lines: [String],
        gridDimensions: GridDimensions,
        claimedIndexes: Set<Int>
    ) -> ButtonStorageShape {
        let columns = max(gridDimensions.columns, 1)
        let column = index % columns
        let rightIndex = index + 1
        let secondRightIndex = index + 2
        let belowIndex = index + columns
        let belowRightIndex = index + columns + 1
        let hasRight = column + 1 < columns &&
            lines.indices.contains(rightIndex) &&
            !claimedIndexes.contains(rightIndex) &&
            isWideButtonContinuationLine(lines[rightIndex])
        let hasSecondRight = column + 2 < columns &&
            lines.indices.contains(secondRightIndex) &&
            !claimedIndexes.contains(secondRightIndex) &&
            isWideButtonContinuationLine(lines[secondRightIndex])
        let hasBelow = lines.indices.contains(belowIndex) &&
            !claimedIndexes.contains(belowIndex) &&
            isBlockButtonContinuationLine(lines[belowIndex])
        let hasBelowRight = column + 1 < columns &&
            lines.indices.contains(belowRightIndex) &&
            !claimedIndexes.contains(belowRightIndex) &&
            isBlockButtonContinuationLine(lines[belowRightIndex])
        let hasThreeByThreeBlock = (1...2).allSatisfy { rowOffset in
            (0...2).allSatisfy { columnOffset in
                let blockIndex = index + (rowOffset * columns) + columnOffset
                return column + columnOffset < columns &&
                    lines.indices.contains(blockIndex) &&
                    !claimedIndexes.contains(blockIndex) &&
                    isBlockButtonContinuationLine(lines[blockIndex])
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

    private func continuationAssignments(
        startingAt index: Int,
        shape: ButtonStorageShape,
        gridDimensions: GridDimensions
    ) -> [(index: Int, token: String)] {
        let columns = max(gridDimensions.columns, 1)
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
        db("updateFunctionKeySlot index=\(index)")
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

        if components.count > 1,
           let firstComponent = components.first,
           isHexColorPrefix(firstComponent) {
            let remainingText = components.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
            let colorCode = firstComponent.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return (remainingText, colorCode)
        }

        return (rightText, nil)
    }

    private func isHexColorPrefix(_ text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.count == 6 else {
            return false
        }

        let hexDigits = "0123456789abcdefABCDEF"
        return trimmedText.allSatisfy { hexDigits.contains($0) }
    }

    private func selectDocument(_ fileURL: URL) {
        db("ENTER ContentView.selectDocument current selectedDocumentName=\(selectedDocumentName) new=\(fileURL.lastPathComponent) recordHistory=false thread=\(Thread.isMainThread ? "main" : "background")")
        loadFunctionKeys(from: fileURL)
        refreshDocumentFiles()
        db("EXIT ContentView.selectDocument current selectedDocumentName=\(selectedDocumentName) new=\(fileURL.lastPathComponent) recordHistory=false thread=\(Thread.isMainThread ? "main" : "background")")
    }

    private func selectDocument(_ fileURL: URL, recordHistory: Bool) {
        db("ENTER ContentView.selectDocument current selectedDocumentName=\(selectedDocumentName) new=\(fileURL.lastPathComponent) recordHistory=\(recordHistory) thread=\(Thread.isMainThread ? "main" : "background")")
        if recordHistory {
            recordDocumentHistory(beforeSwitchingTo: fileURL.lastPathComponent)
        }
        loadFunctionKeys(from: fileURL)
        refreshDocumentFiles()
        db("EXIT ContentView.selectDocument current selectedDocumentName=\(selectedDocumentName) new=\(fileURL.lastPathComponent) recordHistory=\(recordHistory) thread=\(Thread.isMainThread ? "main" : "background")")
    }

    private func recordDocumentHistory(beforeSwitchingTo targetDocumentName: String) {
        db("ENTER ContentView.recordDocumentHistory current selectedDocumentName=\(selectedDocumentName) new=\(targetDocumentName) thread=\(Thread.isMainThread ? "main" : "background")")
        printDocumentNavigationStacks("record requested -> \(targetDocumentName)")
        guard !selectedDocumentName.isEmpty,
              selectedDocumentName != targetDocumentName else {
            db("EXIT ContentView.recordDocumentHistory skipped current documentNavigationHistory=\(documentNavigationHistory) new=no change thread=\(Thread.isMainThread ? "main" : "background")")
            printDocumentNavigationStacks("record skipped")
            return
        }

        let currentDocumentNavigationHistory = documentNavigationHistory
        db("STATE ContentView.recordDocumentHistory current documentNavigationHistory=\(currentDocumentNavigationHistory) new=append \(selectedDocumentName) thread=\(Thread.isMainThread ? "main" : "background")")
        documentNavigationHistory = appendingDocumentHistoryName(
            selectedDocumentName,
            to: documentNavigationHistory
        )
        db("STATE ContentView.recordDocumentHistory current documentNavigationHistory=\(currentDocumentNavigationHistory) new=\(documentNavigationHistory) thread=\(Thread.isMainThread ? "main" : "background")")
        printDocumentNavigationStacks("record stored -> \(targetDocumentName)")
        db("EXIT ContentView.recordDocumentHistory current selectedDocumentName=\(selectedDocumentName) new=\(targetDocumentName) thread=\(Thread.isMainThread ? "main" : "background")")
    }

    private func printDocumentNavigationStacks(_ label: String) {
        db("Doc nav \(label). current: [\(selectedDocumentName)] back: \(documentNavigationHistory) forw: \(documentForwardNavigationHistory)")
    }

    private func appendingDocumentHistoryName(_ documentName: String, to history: [String]) -> [String] {
        guard history.last != documentName else {
            return history
        }

        var updatedHistory = history
        updatedHistory.append(documentName)
        if updatedHistory.count > maxDocumentNavigationHistoryCount {
            updatedHistory.removeFirst(updatedHistory.count - maxDocumentNavigationHistoryCount)
        }
        return updatedHistory
    }

    private func canonicalDocumentFileName(from rawName: String) -> String {
        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return trimmedName }
        let pathExtension = URL(fileURLWithPath: trimmedName).pathExtension.lowercased()
        if pathExtension == screenDocumentFileExtension || pathExtension == legacyScreenDocumentFileExtension {
            return trimmedName
        }

        return "\(trimmedName).\(legacyScreenDocumentFileExtension)"
    }

    @discardableResult
    private func selectDocumentNamedFromGrid(_ rawName: String) -> Bool {
        let targetFileName = canonicalDocumentFileName(from: rawName)
        db("ENTER ContentView.selectDocumentNamedFromGrid rawName=\(rawName) current selectedDocumentName=\(selectedDocumentName) new=\(targetFileName) documentFiles.count=\(documentFiles.count) thread=\(Thread.isMainThread ? "main" : "background")")
        guard !targetFileName.isEmpty else {
            db("EXIT ContentView.selectDocumentNamedFromGrid failed rawName=\(rawName) current selectedDocumentName=\(selectedDocumentName) new=\(targetFileName) thread=\(Thread.isMainThread ? "main" : "background")")
            return false
        }

        let exactFileURL = documentFiles.first(where: {
            $0.lastPathComponent.caseInsensitiveCompare(targetFileName) == .orderedSame
        })
        let fallbackScreenURL: URL?
        if exactFileURL == nil,
           URL(fileURLWithPath: targetFileName).pathExtension.lowercased() == legacyScreenDocumentFileExtension {
            fallbackScreenURL = documentFiles.first(where: {
                $0.pathExtension.lowercased() == screenDocumentFileExtension &&
                    screenDocumentBaseKey(for: $0.lastPathComponent) == screenDocumentBaseKey(for: targetFileName)
            })
        } else {
            fallbackScreenURL = nil
        }

        let fileURL = exactFileURL ?? fallbackScreenURL

        guard let fileURL else {
            db("EXIT ContentView.selectDocumentNamedFromGrid failed rawName=\(rawName) current selectedDocumentName=\(selectedDocumentName) new=\(targetFileName) thread=\(Thread.isMainThread ? "main" : "background")")
            return false
        }

        if exactFileURL == nil,
           let fallbackScreenURL {
            db("SCREEN_NAV_RESOLVE requested=\(targetFileName) resolved=\(fallbackScreenURL.lastPathComponent)")
        }

        selectDocument(fileURL, recordHistory: true)
        db("EXIT ContentView.selectDocumentNamedFromGrid succeeded rawName=\(rawName) current selectedDocumentName=\(selectedDocumentName) new=\(targetFileName) thread=\(Thread.isMainThread ? "main" : "background")")
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
            bleTextToSend: $settingsBLEText,
            returnToMain: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    db("STATE ContentView.SettingsScreen.returnToMain current isSettingsScreenPresented=\(isSettingsScreenPresented) new=false thread=\(Thread.isMainThread ? "main" : "background")")
                    isSettingsScreenPresented = false
                }
            }
        )
        .onAppear {
            db("DESTINATION SettingsScreen.onAppear current isSettingsScreenPresented=\(isSettingsScreenPresented) new=true thread=\(Thread.isMainThread ? "main" : "background")")
            db("STATE ContentView.launchedSettingsScreen.onAppear current isSettingsScreenPresented=\(isSettingsScreenPresented) new=true thread=\(Thread.isMainThread ? "main" : "background")")
            isSettingsScreenPresented = true
        }
        .onDisappear {
            db("DESTINATION SettingsScreen.onDisappear current isSettingsScreenPresented=\(isSettingsScreenPresented) new=false thread=\(Thread.isMainThread ? "main" : "background")")
            db("STATE ContentView.launchedSettingsScreen.onDisappear current isSettingsScreenPresented=\(isSettingsScreenPresented) new=false thread=\(Thread.isMainThread ? "main" : "background")")
            isSettingsScreenPresented = false
        }
    }

    private func presentInitialSettingsScreenIfNeeded() {
        db("ENTER ContentView.presentInitialSettingsScreenIfNeeded current isSettingsScreenPresented=\(isSettingsScreenPresented) didPresentInitialSettingsScreen=\(didPresentInitialSettingsScreen) new=initialSettingsCheck thread=\(Thread.isMainThread ? "main" : "background")")
        guard isSettingsScreenPresented, !didPresentInitialSettingsScreen else {
            db("EXIT ContentView.presentInitialSettingsScreenIfNeeded skipped current isSettingsScreenPresented=\(isSettingsScreenPresented) didPresentInitialSettingsScreen=\(didPresentInitialSettingsScreen) new=no change thread=\(Thread.isMainThread ? "main" : "background")")
            return
        }

        db("STATE ContentView.presentInitialSettingsScreenIfNeeded current didPresentInitialSettingsScreen=\(didPresentInitialSettingsScreen) new=true thread=\(Thread.isMainThread ? "main" : "background")")
        didPresentInitialSettingsScreen = true
        db("STATE ContentView.presentInitialSettingsScreenIfNeeded current isSettingsScreenPresented=\(isSettingsScreenPresented) new=true thread=\(Thread.isMainThread ? "main" : "background")")
        isSettingsScreenPresented = true
        db("EXIT ContentView.presentInitialSettingsScreenIfNeeded current isSettingsScreenPresented=\(isSettingsScreenPresented) didPresentInitialSettingsScreen=\(didPresentInitialSettingsScreen) new=initialSettingsPresented thread=\(Thread.isMainThread ? "main" : "background")")
    }

    private func showSettingsScreen() {
        db("ENTER ContentView.showSettingsScreen current isSettingsScreenPresented=\(isSettingsScreenPresented) new=true thread=\(Thread.isMainThread ? "main" : "background")")
        guard !isSettingsScreenPresented else {
            db("EXIT ContentView.showSettingsScreen skipped current isSettingsScreenPresented=\(isSettingsScreenPresented) new=no change thread=\(Thread.isMainThread ? "main" : "background")")
            return
        }

        withAnimation(.easeInOut(duration: 0.25)) {
            db("STATE ContentView.showSettingsScreen current isSettingsScreenPresented=\(isSettingsScreenPresented) new=true thread=\(Thread.isMainThread ? "main" : "background")")
            isSettingsScreenPresented = true
        }
        db("EXIT ContentView.showSettingsScreen current isSettingsScreenPresented=\(isSettingsScreenPresented) new=true thread=\(Thread.isMainThread ? "main" : "background")")
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

    @discardableResult
    private func moveDocumentConfigIfPresent(from sourceDocumentURL: URL, to targetDocumentURL: URL) throws -> Bool {
        let fileManager = FileManager.default
        let sourceConfigURL = configURL(forDocumentURL: sourceDocumentURL)
        guard fileManager.fileExists(atPath: sourceConfigURL.path) else {
            return false
        }

        let targetConfigURL = configURL(forDocumentURL: targetDocumentURL)
        guard sourceConfigURL.path != targetConfigURL.path else {
            return true
        }

        if fileManager.fileExists(atPath: targetConfigURL.path) {
            try fileManager.removeItem(at: targetConfigURL)
        }

        try fileManager.moveItem(at: sourceConfigURL, to: targetConfigURL)
        return true
    }

    private func deleteDocumentConfigIfPresent(for documentURL: URL) throws {
        let configFileURL = configURL(forDocumentURL: documentURL)
        guard FileManager.default.fileExists(atPath: configFileURL.path) else {
            return
        }

        try FileManager.default.removeItem(at: configFileURL)
    }

    private func copyDocumentConfigOrCreateDefault(from sourceDocumentURL: URL, to targetDocumentURL: URL) throws {
        let fileManager = FileManager.default
        let sourceConfigURL = configURL(forDocumentURL: sourceDocumentURL)
        let targetConfigURL = configURL(forDocumentURL: targetDocumentURL)

        if fileManager.fileExists(atPath: targetConfigURL.path) {
            try fileManager.removeItem(at: targetConfigURL)
        }

        if fileManager.fileExists(atPath: sourceConfigURL.path) {
            try fileManager.copyItem(at: sourceConfigURL, to: targetConfigURL)
            return
        }

        let requiredBoxCount = requiredBoxCountForDocumentURL(targetDocumentURL)
        let config = screenConfigFromAppStorageFallback(
            for: targetDocumentURL.lastPathComponent,
            requiredBoxCount: requiredBoxCount
        )
        _ = saveScreenConfig(config, for: targetDocumentURL)
    }

    private func renameSelectedDocument(to proposedName: String) -> String? {
        let trimmedName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            return "Filename can't be blank."
        }

        let targetFileName = screenDocumentFileName(forBaseName: trimmedName)

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
            let didMoveConfig = try moveDocumentConfigIfPresent(from: sourceURL, to: targetURL)
            do {
                try FileManager.default.moveItem(at: sourceURL, to: targetURL)
            } catch {
                if didMoveConfig {
                    _ = try? moveDocumentConfigIfPresent(from: targetURL, to: sourceURL)
                }
                throw error
            }
            loadFunctionKeys(from: targetURL)
            refreshDocumentFiles()
            db("STATE ContentView.renameSelectedDocument succeeded current selectedDocumentName=\(sourceURL.lastPathComponent) new=\(targetURL.lastPathComponent) thread=\(Thread.isMainThread ? "main" : "background")")
            return nil
        } catch {
            db("ERROR ContentView.renameSelectedDocument failed current selectedDocumentName=\(selectedDocumentName) new=\(targetFileName) error=\(String(describing: error)) thread=\(Thread.isMainThread ? "main" : "background")")
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
            try deleteDocumentConfigIfPresent(for: fileURL)
            var updatedFontSizes = loadDocumentFontSizes()
            updatedFontSizes.removeValue(forKey: fileURL.lastPathComponent)
            saveDocumentFontSizes(updatedFontSizes)
            var updatedGridDimensions = loadDocumentGridDimensions()
            updatedGridDimensions.removeValue(forKey: fileURL.lastPathComponent)
            saveDocumentGridDimensions(updatedGridDimensions)
            refreshDocumentFiles()

            if let fallbackFileURL {
                documentNavigationHistory.removeAll { $0 == fileURL.lastPathComponent }
                documentForwardNavigationHistory.removeAll { $0 == fileURL.lastPathComponent }
                selectDocument(fallbackFileURL)
            }
        } catch {
            refreshDocumentFiles()
        }
    }

    private func duplicateDocument(_ fileURL: URL) {
        let directoryURL = fileURL.deletingLastPathComponent()
        let fileExtension = screenDocumentFileExtension
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
            try copyDocumentConfigOrCreateDefault(from: fileURL, to: targetURL)
            refreshDocumentFiles()
            selectDocument(targetURL)
        } catch {
            refreshDocumentFiles()
        }
    }

    private func selectPreviousDocument() {
        db("ENTER ContentView.selectPreviousDocument current selectedDocumentName=\(selectedDocumentName) currentFileNumber=\(currentFileNumber) new=previousDocument thread=\(Thread.isMainThread ? "main" : "background")")
        guard let currentIndex = documentFiles.firstIndex(where: { $0.lastPathComponent == selectedDocumentName }),
              currentIndex > 0 else {
            db("EXIT ContentView.selectPreviousDocument skipped current selectedDocumentName=\(selectedDocumentName) currentFileNumber=\(currentFileNumber) new=no change thread=\(Thread.isMainThread ? "main" : "background")")
            return
        }

        selectDocument(documentFiles[currentIndex - 1], recordHistory: true)
        db("EXIT ContentView.selectPreviousDocument current selectedDocumentName=\(selectedDocumentName) currentFileNumber=\(currentFileNumber) new=previousDocument complete thread=\(Thread.isMainThread ? "main" : "background")")
    }

    private func selectNextDocument() {
        db("ENTER ContentView.selectNextDocument current selectedDocumentName=\(selectedDocumentName) currentFileNumber=\(currentFileNumber) new=nextDocument thread=\(Thread.isMainThread ? "main" : "background")")
        guard let currentIndex = documentFiles.firstIndex(where: { $0.lastPathComponent == selectedDocumentName }),
              currentIndex < documentFiles.count - 1 else {
            db("EXIT ContentView.selectNextDocument skipped current selectedDocumentName=\(selectedDocumentName) currentFileNumber=\(currentFileNumber) new=no change thread=\(Thread.isMainThread ? "main" : "background")")
            return
        }

        selectDocument(documentFiles[currentIndex + 1], recordHistory: true)
        db("EXIT ContentView.selectNextDocument current selectedDocumentName=\(selectedDocumentName) currentFileNumber=\(currentFileNumber) new=nextDocument complete thread=\(Thread.isMainThread ? "main" : "background")")
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
        db("ENTER ContentView.goBackToPreviousDocument current selectedDocumentName=\(selectedDocumentName) documentNavigationHistory=\(documentNavigationHistory) documentForwardNavigationHistory=\(documentForwardNavigationHistory) new=previousHistory thread=\(Thread.isMainThread ? "main" : "background")")
        printDocumentNavigationStacks("back requested")
        while let previousName = documentNavigationHistory.popLast() {
            db("STATE ContentView.goBackToPreviousDocument current documentNavigationHistory=popLast new=\(documentNavigationHistory) thread=\(Thread.isMainThread ? "main" : "background")")
            guard previousName != selectedDocumentName,
                  let fileURL = documentFiles.first(where: { $0.lastPathComponent == previousName }) else {
                db("Doc nav back skipped: [\(previousName)]")
                continue
            }

            if !selectedDocumentName.isEmpty {
                let currentDocumentForwardNavigationHistory = documentForwardNavigationHistory
                db("STATE ContentView.goBackToPreviousDocument current documentForwardNavigationHistory=\(currentDocumentForwardNavigationHistory) new=append \(selectedDocumentName) thread=\(Thread.isMainThread ? "main" : "background")")
                documentForwardNavigationHistory = appendingDocumentHistoryName(
                    selectedDocumentName,
                    to: documentForwardNavigationHistory
                )
                db("STATE ContentView.goBackToPreviousDocument current documentForwardNavigationHistory=\(currentDocumentForwardNavigationHistory) new=\(documentForwardNavigationHistory) thread=\(Thread.isMainThread ? "main" : "background")")
            }
            printDocumentNavigationStacks("back selecting -> \(previousName)")
            selectDocument(fileURL)
            printDocumentNavigationStacks("back finished")
            db("EXIT ContentView.goBackToPreviousDocument current selectedDocumentName=\(selectedDocumentName) new=\(previousName) thread=\(Thread.isMainThread ? "main" : "background")")
            return
        }
        printDocumentNavigationStacks("back no target")
        db("EXIT ContentView.goBackToPreviousDocument noTarget current selectedDocumentName=\(selectedDocumentName) new=no change thread=\(Thread.isMainThread ? "main" : "background")")
    }

    private func goForwardToNextDocument() {
        db("ENTER ContentView.goForwardToNextDocument current selectedDocumentName=\(selectedDocumentName) documentNavigationHistory=\(documentNavigationHistory) documentForwardNavigationHistory=\(documentForwardNavigationHistory) new=forwardHistory thread=\(Thread.isMainThread ? "main" : "background")")
        printDocumentNavigationStacks("forw requested")
        while let nextName = documentForwardNavigationHistory.popLast() {
            db("STATE ContentView.goForwardToNextDocument current documentForwardNavigationHistory=popLast new=\(documentForwardNavigationHistory) thread=\(Thread.isMainThread ? "main" : "background")")
            guard nextName != selectedDocumentName,
                  let fileURL = documentFiles.first(where: { $0.lastPathComponent == nextName }) else {
                db("Doc nav forw skipped: [\(nextName)]")
                continue
            }

            if !selectedDocumentName.isEmpty {
                let currentDocumentNavigationHistory = documentNavigationHistory
                db("STATE ContentView.goForwardToNextDocument current documentNavigationHistory=\(currentDocumentNavigationHistory) new=append \(selectedDocumentName) thread=\(Thread.isMainThread ? "main" : "background")")
                documentNavigationHistory = appendingDocumentHistoryName(
                    selectedDocumentName,
                    to: documentNavigationHistory
                )
                db("STATE ContentView.goForwardToNextDocument current documentNavigationHistory=\(currentDocumentNavigationHistory) new=\(documentNavigationHistory) thread=\(Thread.isMainThread ? "main" : "background")")
            }
            printDocumentNavigationStacks("forw selecting -> \(nextName)")
            selectDocument(fileURL)
            printDocumentNavigationStacks("forw finished")
            db("EXIT ContentView.goForwardToNextDocument current selectedDocumentName=\(selectedDocumentName) new=\(nextName) thread=\(Thread.isMainThread ? "main" : "background")")
            return
        }

        if let (nextName, fileURL) = nextDocumentFromNavigationHistory() {
            printDocumentNavigationStacks("forw selecting from history -> \(nextName)")
            selectDocument(fileURL)
            printDocumentNavigationStacks("forw history finished")
            db("EXIT ContentView.goForwardToNextDocument history current selectedDocumentName=\(selectedDocumentName) new=\(nextName) thread=\(Thread.isMainThread ? "main" : "background")")
            return
        }

        printDocumentNavigationStacks("forw no target")
        db("EXIT ContentView.goForwardToNextDocument noTarget current selectedDocumentName=\(selectedDocumentName) new=no change thread=\(Thread.isMainThread ? "main" : "background")")
    }

    private func nextDocumentFromNavigationHistory() -> (name: String, fileURL: URL)? {
        guard !selectedDocumentName.isEmpty else {
            return nil
        }

        for currentIndex in documentNavigationHistory.indices.reversed()
            where documentNavigationHistory[currentIndex] == selectedDocumentName {
            var nextIndex = documentNavigationHistory.index(after: currentIndex)
            while nextIndex < documentNavigationHistory.endIndex {
                let nextName = documentNavigationHistory[nextIndex]
                guard nextName != selectedDocumentName,
                      let fileURL = documentFiles.first(where: { $0.lastPathComponent == nextName }) else {
                    db("Doc nav forw history skipped: [\(nextName)]")
                    nextIndex = documentNavigationHistory.index(after: nextIndex)
                    continue
                }

                return (nextName, fileURL)
            }
        }

        return nil
    }
}

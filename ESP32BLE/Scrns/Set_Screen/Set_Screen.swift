import SwiftUI
import UIKit
import AVFoundation
import UniformTypeIdentifiers

struct SettingsScreen: View {
    private enum SettingsListMode: String {
        case files
        case text
        case images
        case sounds
        case pdfs
        case templates
        case all

        static let visibleMenuModes: [SettingsListMode] = [
            .files,
            .templates,
            .text,
            .images,
            .sounds,
            .pdfs
        ]

        var selectorTitle: String {
            switch self {
            case .files:
                return "screens"
            case .text:
                return "text"
            case .images:
                return "images"
            case .sounds:
                return "sounds"
            case .pdfs:
                return "PDFs"
            case .templates:
                return "plates"
            case .all:
                return "all Ffles"
            }
        }

        var menuItemTitle: String {
            switch self {
            case .templates:
                return "templates"
            default:
                return selectorTitle
            }
        }

        var selectedButtonTitle: String {
            guard !isPad else { return selectorTitle }

            switch self {
            case .files:
                return "scrns"
            case .images:
                return "imgs"
            case .sounds:
                return "snds"
            default:
                return selectorTitle
            }
        }

        mutating func toggle(developerMode: Bool) {
            switch self {
            case .files:
                self = .text
            case .text:
                self = .images
            case .images:
                self = .sounds
            case .sounds:
                self = .pdfs
            case .pdfs:
                self = .templates
            case .templates:
                self = developerMode ? .all : .files
            case .all:
                self = .files
            }
        }
    }

    private enum ImportedContentKind {
        case document
        case config
        case text
        case image
        case sound
        case pdf
        case templateDocument
        case templateConfiguration
    }

    private enum SettingsImportMode {
        case screen
        case allFiles
    }

    private enum ImportConflictResolution {
        case replace
        case keepBoth
    }

    private enum RestoreConflictResolution {
        case replaceAll
        case skipAll
    }

    private enum DocumentSaveResult {
        case unchanged
        case saved
        case reloadedFromDisk
        case conflict
        case missing
        case failed

        var allowsDocumentTransition: Bool {
            switch self {
            case .unchanged, .saved, .reloadedFromDisk, .missing:
                return true
            case .conflict, .failed:
                return false
            }
        }
    }

    private enum RestoreArchiveValidationError: LocalizedError {
        case invalidBackupArchive
        case invalidArchivePath(String)
        case unsupportedArchiveEntry(String)
        case duplicateDestinationFilename(String)
        case invalidScreenConfiguration(String)
        case orphanedTemplateConfiguration(String)

        var errorDescription: String? {
            switch self {
            case .invalidBackupArchive:
                return "Invalid backup archive."
            case .invalidArchivePath(let fileName):
                return "Invalid backup archive path: \(fileName)."
            case .unsupportedArchiveEntry(let fileName):
                return "Unsupported file in backup: \(fileName)."
            case .duplicateDestinationFilename(let fileName):
                return "Duplicate filenames in backup: \(fileName)."
            case .invalidScreenConfiguration(let fileName):
                return "Invalid screen configuration in backup: \(fileName)."
            case .orphanedTemplateConfiguration(let fileName):
                return "Template configuration has no matching template in backup: \(fileName)."
            }
        }
    }

    private struct PendingImportConflict {
        let sourceURL: URL
        let targetURL: URL
        let fileName: String
        let contentKind: ImportedContentKind
    }

    private struct PendingImportSession {
        let directoryURL: URL
        var importListMode: SettingsListMode?
        var importMode: SettingsImportMode
        var remainingURLs: [URL]
        var processedItemCount = 0
        var selectedConfigURLsByName: [String: URL]
        var temporaryImportDirectoryURLs: [URL] = []
        var skipFileNameKeys: Set<String> = []
        var existingFileNames: Set<String>
        var existingTextNames: Set<String>
        var existingConfigNames: Set<String>
        var existingImageNames: Set<String>
        var existingSoundNames: Set<String>
        var existingPDFNames: Set<String>
        var templateRestorePairs: [TemplateArchiveRestorePair] = []
        var skipTemplatePairKeys: Set<String> = []
        var templateRestoreAttempted = false
        var firstImportedDocumentURL: URL?
        var firstImportedTextURL: URL?
        var firstImportedImageURL: URL?
        var firstImportedSoundURL: URL?
        var firstImportedPDFURL: URL?
        var applyToAllResolution: ImportConflictResolution?
        var importedAnything = false
        var importedFileCount = 0
        var replacedFileCount = 0
        var failedFileCount = 0
    }

    private struct ScreenPackageImport {
        let documentURL: URL
        let configURL: URL?
        let temporaryDirectoryURL: URL
    }

    private struct FullArchiveImport {
        let fileURLs: [URL]
        let configURLsByName: [String: URL]
        let templatePairs: [TemplateArchiveRestorePair]
        let temporaryDirectoryURL: URL
    }

    private struct TemplateArchiveRestorePair {
        let templateFileName: String
        let templateData: Data
        let configurationData: Data?

        var templateKey: String {
            templateFileNameCollisionKey(templateFileName)
        }

        var configurationKey: String {
            templateFileNameCollisionKey(
                templateConfigFileName(forTemplateDocumentName: templateFileName)
            )
        }
    }

    private struct PendingFullRestore {
        var session: PendingImportSession
        let skipFileNameKeys: Set<String>
        let skipTemplatePairKeys: Set<String>
    }

    private struct FullRestorePreflight {
        var session: PendingImportSession
        let conflictFileNameKeys: Set<String>
        let skipFileNameKeys: Set<String>
        let skipTemplatePairKeys: Set<String>
    }

    private struct FullArchiveEntryPlan {
        let entry: SettingsArchiveFileDocument.ArchiveEntry
        let folderName: String
        let fileName: String
        let contentKind: ImportedContentKind
        let fileNameKey: String
    }

    private struct FullArchiveEntryClassification {
        let fileURLs: [URL]
        let configURLsByName: [String: URL]
        let templatePairs: [TemplateArchiveRestorePair]
    }

    private struct SettingsStoredGridDimensions: Codable {
        let columns: Int
        let rows: Int
    }

    private struct SettingsButtonStorageShape {
        let width: Int
        let height: Int
    }

    private struct PendingTemplateApplication {
        let templateURL: URL
        let templateName: String
        let targetName: String
    }

    private enum TemplateDescriptionState {
        case description(String)
        case noDescription
        case unavailable

        var displayText: String {
            switch self {
            case .description(let description):
                return description
            case .noDescription:
                return "No description"
            case .unavailable:
                return "Description unavailable"
            }
        }
    }

    private let ttsControlColor = Color(red: 0.0, green: 0.2, blue: 0.45)
    private let defaultTextToSpeechRate = Double(AVSpeechUtteranceDefaultSpeechRate)
    private let minimumTextToSpeechPercentage = 40.0
    private let maximumTextToSpeechPercentage = 140.0
    private let textToSpeechPercentageStep = 5.0
    private let maximumSpeechRecognitionAutoOffMinutes = 31
    
	
	// MARK: - BM:🐞 DEBUG: Set false before release
	// DEBUG ONLY
    // Set false before release to hide internal files such as Screen.config.json.
    private let developerMode = true
	
	
    @AppStorage("speechRecognitionAutoOffMinutes") private var speechRecognitionAutoOffMinutes = 5
    @AppStorage("sendControlABeforeText") var sendControlABeforeText = false
    @AppStorage("keyboardTimingOnMs") private var keyboardTimingOnMs = 0.0
    @AppStorage("keyboardTimingOffMs") private var keyboardTimingOffMs = 0.0
    @AppStorage("keepScreenAwake") private var keepScreenAwake = false
    private let timingLabelWidth = 90.0
    @ObservedObject var ble: BLEKeyboardManager
    @ObservedObject var macConnection: MacConnectionManager
    @Binding var outputModeRawValue: String
    let documentFiles: [URL]
    let documentDirectorySnapshot: [URL]
    let selectedDocumentName: String
    let refreshDocumentFiles: () -> Void
    let refreshDocumentFilesAfterDeletingAllData: () -> Void
    let loadFunctionKeys: (URL) -> Void
    let createTemplate: (String, String?, String) throws -> TemplateCreationResult
    let applyTemplate: (URL, String) throws -> TemplateApplicationResult
    let saveSelectedDocumentAndReload: (String) -> Void
    let renameDocument: (String) -> String?
    let deleteDocument: (URL) -> Void
    let duplicateDocument: (URL) -> Void
    let canDeleteDocuments: Bool
    let isSettingsScreenPresented: Bool
    @Binding var bleTextToSend: String
    let returnToMain: () -> Void
    @State private var documentEditorText = ""
    @State private var documentEditorFontSize: CGFloat = 18
    @State private var isLoadingDocumentText = false
    @State private var isDocumentEditorFocused = false
    @State private var speechSynthesizer = AVSpeechSynthesizer()
    @State private var soundPreviewPlayer: AVAudioPlayer?
    @State private var loadedDocumentName = ""
    @State private var loadedDocumentURL: URL?
    @State private var savedDocumentEditorText = ""
    @State private var documentSaveAlertTitle = ""
    @State private var documentSaveAlertMessage = ""
    @State private var isDocumentSaveAlertPresented = false
    @State private var blockedDocumentSaveResult: DocumentSaveResult?
    @AppStorage("settingsBluetoothMonitorMode") private var isBluetoothMonitorMode = false
    @State private var isEditingDocumentName = false
    @State private var documentNameDraft = ""
    @State private var renameAlertMessage: String?
    @State private var repairAlertMessage: String?
    @State private var isDeleteAllDataConfirmationPresented = false
    @State private var isRestoreAllFilesConfirmationPresented = false
    @AppStorage("settingsListMode") private var listModeRawValue = SettingsListMode.files.rawValue
    @State private var isIPhoneSettingsCategoryPopoverPresented = false
    @State private var isIPhoneSettingsImportPopoverPresented = false
    @State private var isIPhoneSettingsExportPopoverPresented = false
    @AppStorage("settingsFilesScrollPositionID") private var fileScrollPositionIDStorage = ""
    @AppStorage("settingsTextScrollPositionID") private var textScrollPositionIDStorage = ""
    @AppStorage("settingsImagesScrollPositionID") private var imageScrollPositionIDStorage = ""
    @AppStorage("settingsSoundsScrollPositionID") private var soundScrollPositionIDStorage = ""
    @AppStorage("settingsPDFsScrollPositionID") private var pdfScrollPositionIDStorage = ""
    @AppStorage("settingsTemplatesScrollPositionID") private var templateScrollPositionIDStorage = ""
    @AppStorage("settingsAllScrollPositionID") private var allScrollPositionIDStorage = ""
    @State private var pendingImportListMode: SettingsListMode?
    @State private var pendingImportMode: SettingsImportMode?
    @State private var activeImportMode: SettingsImportMode?
    @State private var pendingImportSession: PendingImportSession?
    @State private var pendingImportConflict: PendingImportConflict?
    @State private var pendingFullRestore: PendingFullRestore?
    @State private var importConflictApplyToAll = false
    @State private var importRefreshID = UUID()
    @State private var isExportingArchive = false
    @State private var exportArchiveDocument: SettingsArchiveFileDocument?
    @State private var singleFileExportURL: URL?
    @State private var singleFileExportTemporaryURL: URL?
    @State private var availableSpeechVoices: [SpeechVoiceOption] = []
    @AppStorage("selectedTextToSpeechVoiceIdentifier") private var selectedTextToSpeechVoiceIdentifier = ""
    @AppStorage("textToSpeechRate") private var textToSpeechRate = Double(AVSpeechUtteranceDefaultSpeechRate)
    @AppStorage("backgroundImageOpacity") private var opacitySliderValue = 0.5
    @AppStorage("selectedBackgroundImageIndex") var selectedImageIndex = 0
    @AppStorage("selectedBackgroundImageName") var selectedImageName = ""
    @AppStorage("selectedBackgroundImagePath") var selectedImagePath = ""
    @AppStorage("selectedSoundName") var selectedSoundName = ""
    @AppStorage("selectedSoundPath") var selectedSoundPath = ""
    @AppStorage("selectedPDFName") var selectedPDFName = ""
    @AppStorage("selectedPDFPath") var selectedPDFPath = ""
    @AppStorage("documentGridDimensionsData") private var documentGridDimensionsData = ""
    @AppStorage(ButtonClickFeedback.preferenceKey) private var isButtonClickEnabled = true
    @AppStorage("settingsStatusBarVisible") private var isStatusBarVisible = true
    @FocusState var focusedField: SettingsFocusField?
    @FocusState private var isDocumentNameFieldFocused: Bool
    @State private var isCancellingDocumentNameFromOutsideTap = false
    @State private var previewImageURL: URL?
    @State private var backgroundChangeFeedbackID = UUID()
    @State private var selectedTextFileName = ""
    @State private var templateURLs: [URL] = []
    @State private var selectedTemplateURL: URL?
    @State private var templateDescriptionState: TemplateDescriptionState?
    @State private var pendingTemplateApplication: PendingTemplateApplication?
    @State private var isTemplateApplicationAlertPresented = false
    @State private var isSaveAsTemplateAlertPresented = false
    @State private var saveAsTemplateSourceName: String?
    @State private var templateNameDraft = ""
    @State private var templateDescriptionDraft = ""
    @State private var settingsFeedbackMessage: String?
    @State private var settingsFeedbackTask: Task<Void, Never>?
    @State private var isHelpPresented = false

    var body: some View {
        configuredSettingsScreen
            .onAppear {
                restorePreviewFromAppliedBackground()
            }
            .onChange(of: selectedDocumentName) {
                previewImageURL = nil
            }
            .onChange(of: documentDirectorySnapshot) {
                if let previewImageURL,
                   !availableImageURLs.contains(previewImageURL) {
                    self.previewImageURL = nil
                }
            }
    }

	// MARK: - BM:⬇️⬆️ SETTINGS - Top Toolbar
    private var settingsScreenBase: some View {
        GeometryReader { screenGeometry in
            VStack(spacing: 0) {
                settingsTopToolbar(availableWidth: screenGeometry.size.width)

                GeometryReader { geometry in
                    if isPad {
                        HStack(alignment: .top, spacing: 0) {
                            VStack(spacing: 0) {
                                editableDocumentSection

                                if !isDocumentEditorFocused {
                                    combinedBottomPanelSection
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                            documentTableSection
                                .frame(width: documentTableWidth(for: geometry.size.width))
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                        .overlay(alignment: .bottomLeading) {
                            SettingsHelpButton {
                                isHelpPresented = true
                            }
                            .padding()
                        }
                    } else {
                        iPhoneSettingsBody(availableWidth: geometry.size.width)
                    }
                }
            }
            .frame(width: screenGeometry.size.width, height: screenGeometry.size.height)
        }
    }

    private func iPhoneSettingsBody(availableWidth: CGFloat) -> some View {
        let tableWidth = iPhoneDocumentTableWidth(for: availableWidth)

        return HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    availableDevicesContent
                        .frame(width: 230, alignment: .topLeading)

                    keyboardSettingsContent
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .padding(.vertical, 8)

            documentTableSection
                .frame(width: tableWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
        .overlay {
            Rectangle()
                .stroke(Color.white, lineWidth: 1)
        }
        .clipShape(.rect(cornerRadius: 0))
    }

    private func settingsTopToolbar(availableWidth: CGFloat) -> some View {
			//
			//----------------------------------------
			// back to main
		//
				HStack(spacing: 8) {
					SettingsToolbarButton(title: "main", backgroundColor: Color.gray.opacity(0.45), minWidth: isPad ? 92 : 70, isEnabled: true) {
				saveAndReturnToMain()
			}
				//
			//----------------------------------------
			// tts voice
			//
				textToSpeechVoiceMenu
			//
			//----------------------------------------
			// tts slider
			//
				textToSpeechRateControl
			//
				//----------------------------------------
				// title text
				//
				if isPad {
					Spacer()
				}
						settingsTitleControl(availableWidth: availableWidth)
							.padding(.horizontal, 12)

				if isPad {
					Spacer()
				}
			//
			//----------------------------------------
			// import btn
			//
                    if isPad {
                        settingsImportNativeMenu
                    } else {
                        settingsIPhoneImportButton
                    }

				if isPad {
					Spacer()
						.frame(width:10)
				}
			//
			//----------------------------------------
			// export btn/menu
			//
                    settingsExportControl
			
			Spacer()
			//
			//----------------------------------------
			// show type of table
			//
						settingsTableSelector
			//----------------------------------------
			// new file
			//
						SettingsToolbarButton(title: "new", backgroundColor: Color.green.opacity(0.5), minWidth: isPad ? 64.4 : 52, isEnabled: listMode == .files) {
					createNewDocument()
			}
			}
			.padding(.horizontal, 8)
			.padding(.vertical, 6)
		}

    private var configuredSettingsScreen: some View {
        settingsScreenBase
        .background {
            Color.black
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    handleSettingsBackgroundTap()
                }
        }
        .sheet(
            isPresented: Binding(
                get: { singleFileExportURL != nil },
                set: { isPresented in
                    guard !isPresented else { return }
                    cleanupSingleFileExportTemporaryURLIfNeeded()
                    singleFileExportURL = nil
                }
            )
        ) {
            if let exportURL = singleFileExportURL {
                SettingsSingleFileExportPicker(url: exportURL) {
                    cleanupSingleFileExportTemporaryURLIfNeeded()
                    singleFileExportURL = nil
                }
                .onAppear {
                }
                .onDisappear {
                }
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { !isPad && isHelpPresented },
                set: { isPresented in
                    if !isPresented {
                        isHelpPresented = false
                    }
                }
            )
        ) {
            ESPHelpView {
                isHelpPresented = false
            }
        }
        .sheet(
            isPresented: Binding(
                get: { isPad && isHelpPresented },
                set: { isPresented in
                    if !isPresented {
                        isHelpPresented = false
                    }
                }
            )
        ) {
            ESPHelpView {
                isHelpPresented = false
            }
            .presentationDetents([.large])
        }
        .onChange(of: ble.isConnected) {
            if ble.isConnected {
                sendKeyboardTimingCommand()
            }
        }
        .task {
            normalizeVisibleListMode()
            loadSelectedDocumentText()
            refreshTemplateFiles()
        }
        .task {
            await observeSettingsKeyboardHide()
        }
        .onChange(of: documentFiles.map(\.path)) {
            if saveCurrentDocumentText().allowsDocumentTransition {
                loadSelectedDocumentText()
            }
        }
        .onChange(of: selectedDocumentName) {
            if saveCurrentDocumentText().allowsDocumentTransition {
                loadSelectedDocumentText()
            }
            cancelNameEditing()
        }
        .onChange(of: listModeRawValue) {
            if listMode != .templates {
                clearTemplateSelection()
            }
            if saveCurrentDocumentText().allowsDocumentTransition {
                loadSelectedDocumentText()
            }
        }
        .onChange(of: documentEditorText) {
            guard !isLoadingDocumentText else { return }
            saveCurrentDocumentText()
        }
        .onChange(of: isDocumentNameFieldFocused) {
            guard isEditingDocumentName, !isDocumentNameFieldFocused else { return }
            if isCancellingDocumentNameFromOutsideTap {
                cancelNameEditing()
            }
        }
        .onChange(of: settingsModeEditResetKey) {
            cancelNameEditing()
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
            documentNameDraft = currentTitleDisplayName
            loadSpeechVoicesIfNeeded()
        }
        .onChange(of: keepScreenAwake) {
            UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
        }
        .task(id: isEditingDocumentName) {
            guard isEditingDocumentName else { return }
            isDocumentNameFieldFocused = true
        }
        .modifier(SettingsRenameAlertModifier(
            message: $renameAlertMessage,
            isPresented: renameAlertIsPresented
        ))
        .alert(documentSaveAlertTitle, isPresented: $isDocumentSaveAlertPresented) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(documentSaveAlertMessage)
        }
        .modifier(DeleteAllDataConfirmationModifier(
            isPresented: $isDeleteAllDataConfirmationPresented,
            deleteAllData: deleteAllData
        ))
        .overlay {
            repairDocumentAlertOverlay
        }
        .confirmationDialog(
            importConflictDialogTitle,
            isPresented: importConflictIsPresented,
            titleVisibility: .visible
        ) {
            Button("Replace Existing") {
                resolvePendingImportConflictByReplacing()
            }
            Button("Skip This File") {
                resolvePendingImportConflictBySkipping()
            }
            Button("Stop Import", role: .destructive) {
                cancelPendingImportSession()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(pendingImportConflict?.fileName ?? "")
        }
        .alert(
            "Restore Conflicts Found",
            isPresented: restoreConflictDialogIsPresented
        ) {
            Button("Replace All") {
                resolvePendingFullRestore(.replaceAll)
            }
            Button("Skip All") {
                resolvePendingFullRestore(.skipAll)
            }
            Button("Cancel", role: .cancel) {
                cancelPendingFullRestore()
            }
        } message: {
            Text("Some filenames already exist. Choose how to handle them.")
        }
        .fileImporter(
            isPresented: isImporting,
            allowedContentTypes: activeImportContentTypes,
            allowsMultipleSelection: allowsMultipleImportSelection
        ) { result in
            let importMode = activeImportMode
            pendingImportListMode = nil
            pendingImportMode = nil
            activeImportMode = nil
            handleImportedSelection(result, importMode: importMode)
        }
        .background {
            archiveExportPresenter
        }
        .onDisappear {
            settingsFeedbackTask?.cancel()
        }
    }

    private var archiveExportPresenter: some View {
        Color.clear
            .fileExporter(
                isPresented: $isExportingArchive,
                document: exportArchiveDocument,
                contentType: archiveExportType,
                defaultFilename: archiveExportDefaultFilename()
            ) { result in
                switch result {
                case .success:
                    showSettingsFeedback("Backup Complete")
                case .failure(let error):
                    renameAlertMessage = error.localizedDescription
                }
                exportArchiveDocument = nil
            }
            .fileDialogBrowserOptions(.displayFileExtensions)
    }

    private var listMode: SettingsListMode {
        get {
            let storedListMode = SettingsListMode(rawValue: listModeRawValue) ?? .files
            if storedListMode == .all {
                return .files
            }

            return storedListMode
        }
        nonmutating set {
            if newValue == .all {
                listModeRawValue = SettingsListMode.files.rawValue
            } else {
                listModeRawValue = newValue.rawValue
            }
        }
    }

    // MARK: - BM:🅱️ IPHONE FILE CATEGORY FONT SIZE — Change 13 to adjust the Settings file-category selector label on iPhone; iPad appearance is unchanged.
    private var settingsTableSelectorFont: Font {
        isPad ? .body : .system(size: 13)
    }

    // MARK: - BM:🅱️ IPHONE SETTINGS MENU ITEM FONT SIZE
    // Change 13 to adjust the opened file-category
    // menu text on iPhone.
    // iPad continues using its native menu.
    private var iphoneSettingsMenuItemFont: Font {
        .system(size: 13)
    }

    // MARK: - BM:🅱️ IPHONE SETTINGS MENU ROW HEIGHT
    // Change 36 to adjust the minimum height of
    // the opened iPhone category-menu rows.
    private var iphoneSettingsMenuRowMinimumHeight: CGFloat {
        36
    }

    private var settingsTableSelector: some View {
        Group {
            if isPad {
                settingsTableSelectorNativeMenu
            } else {
                Button {
                    isIPhoneSettingsCategoryPopoverPresented = true
                } label: {
                    settingsTableSelectorLabel
                }
                .buttonStyle(.plain)
                .accessibilityLabel("File category: \(listMode.selectedButtonTitle)")
                .popover(isPresented: $isIPhoneSettingsCategoryPopoverPresented) {
                    iphoneSettingsCategoryPopover
                        .presentationCompactAdaptation(.popover)
                }
            }
        }
    }

    private var settingsTableSelectorNativeMenu: some View {
        Menu {
            ForEach(SettingsListMode.visibleMenuModes, id: \.rawValue) { mode in
                Button {
                    selectSettingsListMode(mode)
                } label: {
                    if listMode == mode {
                        Label(mode.menuItemTitle, systemImage: "checkmark")
                    } else {
                        Text(mode.menuItemTitle)
                    }
                }
            }
        } label: {
            settingsTableSelectorLabel
        }
    }

    private var settingsTableSelectorLabel: some View {
        HStack(spacing: 3) {
            Text(listMode.selectedButtonTitle)
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.caption2)
        }
        .font(settingsTableSelectorFont)
        .foregroundStyle(.white)
        .padding(.horizontal, isPad ? 6 : 4)
        .frame(width: isPad ? 110 : 74)
        .frame(minHeight: 36)
        .background(Color.gray.opacity(0.45))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
        }
        .clipShape(.rect(cornerRadius: 12))
        .contentShape(.rect)
    }

    private var iphoneSettingsCategoryPopover: some View {
        VStack(spacing: 0) {
            ForEach(SettingsListMode.visibleMenuModes, id: \.rawValue) { mode in
                Button {
                    isIPhoneSettingsCategoryPopoverPresented = false
                    selectSettingsListMode(mode)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .opacity(listMode == mode ? 1 : 0)
                            .frame(width: 14, alignment: .leading)

                        Text(mode.menuItemTitle)
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }
                    .font(iphoneSettingsMenuItemFont)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, minHeight: iphoneSettingsMenuRowMinimumHeight, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.menuItemTitle)
                .accessibilityValue(listMode == mode ? "Selected" : "")
            }
        }
        .frame(minWidth: 150)
        .padding(.vertical, 4)
        .background(.regularMaterial)
    }

    private var settingsImportNativeMenu: some View {
        Menu {
            Button("Import Screen(s)") {
                beginScreenImport()
            }
            Button("Restore Full Backup") {
                beginFullBackupRestore()
            }
        } label: {
            settingsImportTriggerLabel
        }
        .contentShape(.rect)
        .accessibilityLabel("Import from iCloud")
    }

    private var settingsIPhoneImportButton: some View {
        Button {
            isIPhoneSettingsImportPopoverPresented = true
        } label: {
            settingsImportTriggerLabel
        }
        .buttonStyle(.plain)
        .contentShape(.rect)
        .accessibilityLabel("Import from iCloud")
        .popover(isPresented: $isIPhoneSettingsImportPopoverPresented) {
            iphoneSettingsImportPopover
                .presentationCompactAdaptation(.popover)
        }
    }

    private var settingsImportTriggerLabel: some View {
        Image(systemName: "square.and.arrow.down")
            .font(.title)
            .foregroundStyle(.white)
    }

    private var iphoneSettingsImportPopover: some View {
        VStack(spacing: 0) {
            iphoneSettingsMenuActionRow(title: "Import Screen(s)") {
                isIPhoneSettingsImportPopoverPresented = false
                beginScreenImport()
            }
            iphoneSettingsMenuActionRow(title: "Restore Full Backup") {
                isIPhoneSettingsImportPopoverPresented = false
                beginFullBackupRestore()
            }
        }
        .frame(minWidth: 180)
        .padding(.vertical, 4)
        .background(.regularMaterial)
    }

    private func iphoneSettingsMenuActionRow(
        title: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .lineLimit(1)
                .font(iphoneSettingsMenuItemFont)
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: iphoneSettingsMenuRowMinimumHeight, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(title)
    }

    private var settingsExportControl: some View {
        Group {
            if isPad {
                settingsExportNativeMenu
            } else {
                settingsIPhoneExportButton
            }
        }
        .alert("Save as Template", isPresented: $isSaveAsTemplateAlertPresented) {
            TextField("Template name", text: $templateNameDraft)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            TextField("Description (optional)", text: $templateDescriptionDraft)
            Button("Cancel", role: .cancel) {
                cancelSaveAsTemplate()
            }
            Button("Save") {
                saveAsTemplate()
            }
        } message: {
            Text("Save the current screen's contents and settings as a reusable template.")
        }
    }

    private var settingsExportNativeMenu: some View {
        Menu {
            Button("Export 1 Screen") {
                beginSingleScreenExport()
            }
            .disabled(!canExportActiveScreen)
            Button("Save as Template") {
                beginTemplateSave()
            }
            .disabled(!canSaveCurrentScreenAsTemplate)
            Button("Create Full Backup") {
                beginFullArchiveExport()
            }
            .disabled(!hasArchiveExportContent)
        } label: {
            settingsExportTriggerLabel
        }
        .contentShape(.rect)
        .accessibilityLabel("Export to iCloud")
        .disabled(!canUseExportMenu)
        .opacity(canUseExportMenu ? 1 : 0.45)
    }

    private var settingsIPhoneExportButton: some View {
        Button {
            isIPhoneSettingsExportPopoverPresented = true
        } label: {
            settingsExportTriggerLabel
        }
        .buttonStyle(.plain)
        .contentShape(.rect)
        .accessibilityLabel("Export to iCloud")
        .disabled(!canUseExportMenu)
        .opacity(canUseExportMenu ? 1 : 0.45)
        .popover(isPresented: $isIPhoneSettingsExportPopoverPresented) {
            iphoneSettingsExportPopover
                .presentationCompactAdaptation(.popover)
        }
    }

    private var settingsExportTriggerLabel: some View {
        Image(systemName: "square.and.arrow.up")
            .font(.title)
            .foregroundStyle(.white)
    }

    private var iphoneSettingsExportPopover: some View {
        VStack(spacing: 0) {
            iphoneSettingsMenuActionRow(
                title: "Export 1 Screen",
                isEnabled: canExportActiveScreen
            ) {
                isIPhoneSettingsExportPopoverPresented = false
                beginSingleScreenExport()
            }
            iphoneSettingsMenuActionRow(
                title: "Save as Template",
                isEnabled: canSaveCurrentScreenAsTemplate
            ) {
                isIPhoneSettingsExportPopoverPresented = false
                beginTemplateSave()
            }
            iphoneSettingsMenuActionRow(
                title: "Create Full Backup",
                isEnabled: hasArchiveExportContent
            ) {
                isIPhoneSettingsExportPopoverPresented = false
                beginFullArchiveExport()
            }
        }
        .frame(minWidth: 180)
        .padding(.vertical, 4)
        .background(.regularMaterial)
    }

    private func selectSettingsListMode(_ mode: SettingsListMode) {
        ButtonClickFeedback.playIfEnabled()
        listMode = mode
    }

    private func beginScreenImport() {
        ButtonClickFeedback.playIfEnabled()
        importConflictApplyToAll = false
        activeImportMode = .screen
        pendingImportMode = .screen
    }

    private func beginFullBackupRestore() {
        ButtonClickFeedback.playIfEnabled()
        beginRestoreAllFiles()
    }

    private func beginSingleScreenExport() {
        ButtonClickFeedback.playIfEnabled()
        prepareSingleFileExport()
    }

    private func beginTemplateSave() {
        ButtonClickFeedback.playIfEnabled()
        beginSaveAsTemplate()
    }

    private func beginFullArchiveExport() {
        ButtonClickFeedback.playIfEnabled()
        prepareArchiveExport()
    }

    private func normalizeVisibleListMode() {
        guard SettingsListMode(rawValue: listModeRawValue) == .all else { return }
        listModeRawValue = SettingsListMode.files.rawValue
    }

    private func nextListMode(from mode: SettingsListMode) -> SettingsListMode {
        var nextMode = mode
        nextMode.toggle(developerMode: developerMode)
        return nextMode
    }

    private var fileScrollPositionID: Binding<String?> {
        Binding(
            get: { fileScrollPositionIDStorage.isEmpty ? nil : fileScrollPositionIDStorage },
            set: { fileScrollPositionIDStorage = $0 ?? "" }
        )
    }

    private var textScrollPositionID: Binding<String?> {
        Binding(
            get: { textScrollPositionIDStorage.isEmpty ? nil : textScrollPositionIDStorage },
            set: { textScrollPositionIDStorage = $0 ?? "" }
        )
    }

    private var imageScrollPositionID: Binding<String?> {
        Binding(
            get: { imageScrollPositionIDStorage.isEmpty ? nil : imageScrollPositionIDStorage },
            set: { imageScrollPositionIDStorage = $0 ?? "" }
        )
    }

    private var soundScrollPositionID: Binding<String?> {
        Binding(
            get: { soundScrollPositionIDStorage.isEmpty ? nil : soundScrollPositionIDStorage },
            set: { soundScrollPositionIDStorage = $0 ?? "" }
        )
    }

    private var pdfScrollPositionID: Binding<String?> {
        Binding(
            get: { pdfScrollPositionIDStorage.isEmpty ? nil : pdfScrollPositionIDStorage },
            set: { pdfScrollPositionIDStorage = $0 ?? "" }
        )
    }

    private var allScrollPositionID: Binding<String?> {
        Binding(
            get: { allScrollPositionIDStorage.isEmpty ? nil : allScrollPositionIDStorage },
            set: { allScrollPositionIDStorage = $0 ?? "" }
        )
    }

    private var templateScrollPositionID: Binding<String?> {
        Binding(
            get: { templateScrollPositionIDStorage.isEmpty ? nil : templateScrollPositionIDStorage },
            set: { templateScrollPositionIDStorage = $0 ?? "" }
        )
    }

    private var settingsModeEditResetKey: String {
        "\(listModeRawValue)|\(selectedTextFileName)|\(selectedImagePath)|\(selectedSoundPath)|\(selectedPDFPath)"
    }

    private var canExportActiveScreen: Bool {
        canSaveCurrentScreenAsTemplate
    }

    private var canSaveCurrentScreenAsTemplate: Bool {
        guard let selectedDocumentFileURL else { return false }
        return selectedDocumentFileURL.lastPathComponent == selectedDocumentName &&
            isScreenDocumentURL(selectedDocumentFileURL)
    }

    private var canUseExportMenu: Bool {
        canExportActiveScreen || canSaveCurrentScreenAsTemplate || hasArchiveExportContent
    }

    private var isImporting: Binding<Bool> {
        Binding(
            get: { pendingImportMode != nil },
            set: { isPresented in
                if !isPresented {
                    pendingImportListMode = nil
                    pendingImportMode = nil
                }
            }
        )
    }

    private var allowsMultipleImportSelection: Bool {
        pendingImportMode != .allFiles
    }

    private var restoreConflictDialogIsPresented: Binding<Bool> {
        Binding(
            get: { pendingFullRestore != nil },
            set: { isPresented in
                if !isPresented {
                    cancelPendingFullRestore()
                }
            }
        )
    }

    private func beginRestoreAllFiles() {
        importConflictApplyToAll = false
        activeImportMode = .allFiles
        pendingImportMode = .allFiles
    }

    private var importConflictIsPresented: Binding<Bool> {
        Binding(
            get: { pendingImportConflict != nil },
            set: { isPresented in
                if !isPresented {
                    pendingImportConflict = nil
                }
            }
        )
    }

    private var activeImportContentTypes: [UTType] {
        switch pendingImportMode {
        case .screen:
            return [screenDocumentImportType, zipImportType]
        case .allFiles:
            return [zipImportType]
        case nil:
            return [.data]
        }
    }

    private var importConflictDialogTitle: String {
        guard pendingImportSession?.importMode == .allFiles,
              let fileName = pendingImportConflict?.fileName else {
            return "a file with that name already exists."
        }

        return "An item named \(fileName) already exists."
    }

    private func documentTableWidth(for availableWidth: CGFloat) -> CGFloat {
        let safeWidth = availableWidth.isFinite ? max(0, availableWidth) : 0
        let widthRatio = safeWidth > 900 ? 0.184 : 0.16
        let maximumWidth: CGFloat = safeWidth > 900 ? 260 : 220
        return min(max(safeWidth * widthRatio, 140), maximumWidth)
    }

    private func iPhoneDocumentTableWidth(for availableWidth: CGFloat) -> CGFloat {
        let safeWidth = availableWidth.isFinite ? max(0, availableWidth) : 0
        return min(max(safeWidth * 0.2, 170), 190)
    }

    @ViewBuilder
    private var editableDocumentSection: some View {
        if isBluetoothMonitorMode {
            SettingsBluetoothMonitorView(monitorText: ble.bluetoothMonitorText)
        } else {
            SettingsEditorSectionView(
                text: $documentEditorText,
                fontSize: $documentEditorFontSize,
                isFocused: $isDocumentEditorFocused,
                savedText: savedDocumentEditorText,
                onUndo: { documentEditorText = savedDocumentEditorText }
            )
        }
    }

    @ViewBuilder
    private var repairDocumentAlertOverlay: some View {
        if let repairAlertMessage {
            GeometryReader { proxy in
                ZStack {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        VStack(spacing: 8) {
                            Text("repair document")
                                .font(.title2.bold())
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)

                            Text(repairAlertMessage)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.green)
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)
                        }

                        Button {
                            self.repairAlertMessage = nil
                        } label: {
                            Text("OK")
                                .font(.headline.bold())
                                .foregroundStyle(.green)
                                .frame(width: 100)
                                .padding(.vertical, 11)
                                .padding(.horizontal, 50)
                                .background(Color.green.opacity(0.2), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
					.frame(width: 300, height:140)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                }
            }
        }
    }

    @ViewBuilder
    private func settingsTitleControl(availableWidth: CGFloat) -> some View {
		let titleWidth = settingsTitleWidth(for: availableWidth)
		// MARK: - BM:🔠🔢 Settings: Top title
        Group {
            if isEditingDocumentName {
                TextField("", text: $documentNameDraft)
                    .textFieldStyle(.roundedBorder)
                    //.font(.headline)
                    .foregroundStyle(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.center)
                    .frame(width: titleWidth, height: 36)
                    .focused($isDocumentNameFieldFocused)
                    .onSubmit {
                        commitNameEdit()
                    }
				} else {
					if #available(iOS 18, *) {
						Button {
							guard canEditCurrentTitle else { return }
							ButtonClickFeedback.playIfEnabled()
							documentNameDraft = currentTitleDisplayName
							isEditingDocumentName = true
						} label: {
							Text(currentTitleDisplayName)
								.lineLimit(1)
								.minimumScaleFactor(0.7)
								.frame(maxWidth: .infinity)
						}
						.disabled(!canEditCurrentTitle)
						//.font(.headline)
						.foregroundStyle(canEditCurrentTitle ? .white : Color(white: 0.8))
						.frame(width: titleWidth, height: 36)
						.background(Color.gray.opacity(0.45))
						.overlay {
							RoundedRectangle(cornerRadius: 12)
								.stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
						}
						.clipShape(.rect(cornerRadius: 12))
						.contentShape(.rect)
					} else {
						SettingsUIKitVisualButton(
							title: currentTitleDisplayName,
							backgroundColor: Color.gray.opacity(0.45),
							width: titleWidth,
							height: 36,
							isEnabled: canEditCurrentTitle,
							fontStyle: .headline,
							titleColor: canEditCurrentTitle ? .white : UIColor(white: 0.8, alpha: 1),
							adjustsFontSizeToFitWidth: true,
							contentInsets: .zero
						) {
							guard canEditCurrentTitle else { return }
							ButtonClickFeedback.playIfEnabled()
							documentNameDraft = currentTitleDisplayName
							isEditingDocumentName = true
						}
					}
	            }
        }
    }

    private func settingsTitleWidth(for availableWidth: CGFloat) -> CGFloat {
        let safeWidth = availableWidth.isFinite ? max(0, availableWidth) : 0
        let preferredWidth = safeWidth * 0.22

        if isPad {
            return min(max(preferredWidth, 300), 500)
        }

        return 140
    }

    private var textToSpeechVoiceMenu: some View {
        Menu {
            ForEach(availableSpeechVoices, id: \.identifier) { voice in
                Button {
                    ButtonClickFeedback.playIfEnabled()
                    selectedTextToSpeechVoiceIdentifier = voice.identifier
                    availableSpeechVoices = orderedSpeechVoices(availableSpeechVoices, selectedIdentifier: voice.identifier)
                    previewSpeechVoice(voice)
                } label: {
                    if voice.identifier == resolvedTextToSpeechVoiceIdentifier {
                        Label(voice.menuTitle, systemImage: "checkmark")
                    } else {
                        Text(voice.menuTitle)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.headline)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(minWidth: 60, minHeight: 36)
            .background(ttsControlColor)
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(ttsControlColor, lineWidth: 1.5)
            }
            .clipShape(.rect(cornerRadius: 12))
            .contentShape(.rect)
        }
        .accessibilityLabel("Text to speech voice")
        .accessibilityValue(selectedSpeechVoiceDisplayName)
    }

    private var textToSpeechRateControl: some View {
        VStack(alignment: .leading, spacing: -2) {
            Text("spd:\(textToSpeechRateLabel)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
                .offset(y: 1.5)

            Slider(
                value: speechRatePercentageBinding,
                in: minimumTextToSpeechPercentage...maximumTextToSpeechPercentage,
                step: textToSpeechPercentageStep,
                onEditingChanged: { isEditing in
                    guard !isEditing else { return }
                    previewCurrentSpeechVoice()
                }
            )
            .tint(ttsControlColor)
            .frame(width: 110)
        }
        .padding(.leading, 4)
    }

    private var availableDevicesContent: some View {
        SettingsBottomControlsSection(
            ble: ble,
            macConnection: macConnection,
            outputModeRawValue: $outputModeRawValue,
            keepScreenAwake: $keepScreenAwake,
            isButtonClickEnabled: $isButtonClickEnabled,
            isBluetoothMonitorMode: $isBluetoothMonitorMode,
            isStatusBarVisible: $isStatusBarVisible,
            opacitySliderValue: $opacitySliderValue,
            imageControlButtons: AnyView(imageControlButtons),
            presentDeleteAllDataConfirmation: presentDeleteAllDataConfirmation,
            presentHelp: {
                isHelpPresented = true
            }
        )
    }

    private var imagePreviewSection: some View {
        SettingsImagePreviewPanel(
            imageURL: previewImageURL,
            opacitySliderValue: opacitySliderValue
        )
        .contentShape(.rect)
        .onTapGesture {
            applySettingsBackground(previewImageURL)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Background preview")
        .accessibilityHint("Applies the displayed background")
        .accessibilityAction {
            applySettingsBackground(previewImageURL)
        }
    }

    private var pdfPreviewSection: some View {
        SettingsPDFPreviewPanel(pdfURL: selectedPDFURL)
    }

    private var imageControlButtons: some View {
        SettingsImageControlsSection(
            canGoPrevious: canPreviewPreviousImage,
            canGoNext: canPreviewNextImage,
            onReset: {
                selectPreviewImage(nil)
            },
            onRandom: {
                let previewChoices: [URL?] = [nil] + availableImageURLs
                let candidateURLs = previewChoices.filter { imageURL in
                    imageURL?.path != previewImageURL?.path
                }
                selectPreviewImage(candidateURLs.randomElement() ?? previewImageURL)
            },
            onPrevious: {
                guard let previewImagePosition else { return }
                if previewImagePosition == 1 {
                    selectPreviewImage(nil)
                } else {
                    selectPreviewImage(availableImageURLs[previewImagePosition - 2])
                }
            },
            onNext: {
                guard !availableImageURLs.isEmpty else { return }
                let nextIndex = previewImagePosition ?? 0
                guard availableImageURLs.indices.contains(nextIndex) else { return }
                selectPreviewImage(availableImageURLs[nextIndex])
            }
        )
    }

    private var previewImagePosition: Int? {
        guard let previewImageURL,
              let imageIndex = availableImageURLs.firstIndex(where: { $0.path == previewImageURL.path }) else {
            return nil
        }

        return imageIndex + 1
    }

    private var canPreviewPreviousImage: Bool {
        previewImagePosition != nil
    }

    private var canPreviewNextImage: Bool {
        guard !availableImageURLs.isEmpty else { return false }
        guard let previewImagePosition else { return true }
        return previewImagePosition < availableImageURLs.count
    }

    private func selectPreviewImage(_ imageURL: URL?) {
        previewImageURL = imageURL
        imageScrollPositionIDStorage = imageURL?.path ?? ""
    }

    private func restorePreviewFromAppliedBackground() {
        selectPreviewImage(selectedImageURL)
    }

    private func settingsBluePlaceholderButton(_ title: String) -> some View {
        Button(title) { }
            .simultaneousGesture(TapGesture().onEnded { ButtonClickFeedback.playIfEnabled() })
            .buttonStyle(.plain)
            .font(.headline)
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.blue)
            .clipShape(.rect(cornerRadius: 18))
    }

    private var simplifiedConnectionStatus: String {
        if ble.isConnected {
            return "connected"
        }

        let status = ble.connectionText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if status.hasPrefix("connecting") || status.contains("discovering") {
            return "connecting..."
        }

        return "disconnected"
    }

    private var keyboardSettingsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            customKeyboardTimingSection
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var combinedBottomPanelSection: some View {
		VStack(spacing:0) {
			HStack(alignment: .top, spacing: 20) {
				availableDevicesContent
					.frame(maxWidth: .infinity, alignment: .topLeading)

				keyboardSettingsContent
					.frame(maxWidth: .infinity, alignment: .topLeading)
			}
			
                if isPad {
                    Spacer()
                        HStack(alignment: .top, spacing: 20) {
                            Spacer()
                            Button {
                                ButtonClickFeedback.playIfEnabled()
                                presentDeleteAllDataConfirmation()
                            } label: {
                                Text("delete all data")
                                    .frame(width: 150, height:60)
                                .padding(.all,5)
                                .foregroundColor(Color.white)
                                .background(Color.red.opacity(0.5))
                                .cornerRadius(5)
                                .overlay(
                                    RoundedRectangle(cornerRadius:5)
                                        .stroke(Color.white, lineWidth:1)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
			}
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding()
        .background(Color.black)
        .overlay {
            Rectangle()
                .stroke(Color.white, lineWidth: 1)
        }
        .clipShape(.rect(cornerRadius: 0))
    }

    private var documentTableSection: some View {
        SettingsDocumentTableSection(
            listMode: settingsDocumentTableListMode,
            documentFiles: availableDocumentURLs,
            loadedDocumentURL: selectedDocumentFileURL,
            textURLs: availableTextURLs,
            selectedTextFileName: selectedTextFileName,
            imageURLs: availableImageURLs,
            previewedImageURL: previewImageURL,
            appliedImageURL: selectedImageURL,
            backgroundChangeFeedbackID: backgroundChangeFeedbackID,
            soundURLs: availableSoundURLs,
            selectedSoundURL: selectedSoundURL,
            pdfURLs: availablePDFURLs,
            selectedPDFURL: selectedPDFURL,
            templateURLs: templateURLs,
            selectedTemplateURL: selectedTemplateURL,
            templateDescription: templateDescriptionState?.displayText,
            allFileURLs: availableAllFileURLs,
            fileScrollPositionID: fileScrollPositionID,
            textScrollPositionID: textScrollPositionID,
            imageScrollPositionID: imageScrollPositionID,
            soundScrollPositionID: soundScrollPositionID,
            pdfScrollPositionID: pdfScrollPositionID,
            templateScrollPositionID: templateScrollPositionID,
            allScrollPositionID: allScrollPositionID,
            refreshFiles: refreshSettingsFileCollections,
            canDeleteDocuments: canDeleteDocuments,
            imagePreviewSection: settingsTablePreviewSection,
            loadFunctionKeys: handleSettingsDocumentSelection,
            isLoadedDocument: { selectedDocumentFileURL?.path == $0.path },
            loadTextFile: loadTextFile,
            deleteDocument: deleteDocument,
            duplicateDocument: duplicateDocument,
            deleteTextFile: deleteTextFile,
            previewImage: { previewImageURL = $0 },
            previewBlackImage: { selectPreviewImage(nil) },
            applyImageBackground: applySettingsBackground,
            deleteImage: deleteImage,
            selectSound: selectSound,
            deleteSound: deleteSound,
            selectPDF: selectPDF,
            deletePDF: deletePDF,
            deleteAllFile: deleteAllFile,
            selectTemplate: selectTemplateForDescription,
            applyTemplate: prepareTemplateApplication,
            deleteTemplate: deleteTemplate,
            showsOuterBorder: isPad
        )
        .id(importRefreshID)
        .overlay(alignment: .top) {
            if let settingsFeedbackMessage {
                Text(settingsFeedbackMessage)
                    .font(.subheadline)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 6)
                    .background(
                        Color.black.opacity(0.9),
                        in: .rect(cornerRadius: 10)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.white, lineWidth: 1)
                    }
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
        }
        .alert(
            "Apply Template?",
            isPresented: $isTemplateApplicationAlertPresented
        ) {
            Button("Cancel", role: .cancel) {
                pendingTemplateApplication = nil
            }
            Button("Apply", role: .destructive) {
                applyPendingTemplate()
            }
        } message: {
            Text(templateApplicationMessage)
        }
    }

    private var templateApplicationMessage: String {
        guard let pendingTemplateApplication else { return "" }

        var lines = [
            "Template: \(pendingTemplateApplication.templateName)",
            "Target: \(pendingTemplateApplication.targetName)"
        ]
        lines.append("This will replace the target screen's buttons and configuration.")
        return lines.joined(separator: "\n\n")
    }

    private func selectTemplateForDescription(_ templateURL: URL) {
        selectedTemplateURL = templateURL

        do {
            let configuration = try loadTemplateConfiguration(for: templateURL)
            let description = configuration.description?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let description, !description.isEmpty {
                templateDescriptionState = .description(description)
            } else {
                templateDescriptionState = .noDescription
            }
        } catch {
            templateDescriptionState = .unavailable
        }
    }

    private func clearTemplateSelection() {
        selectedTemplateURL = nil
        templateDescriptionState = nil
    }

    private func deleteTemplate(_ templateURL: URL) {
        do {
            try deleteTemplateDocument(at: templateURL)
            refreshTemplateFiles()
        } catch {
            refreshTemplateFiles()
            let title: String
            if case .rollbackFailed = error as? TemplateDeletionError {
                title = "Critical Template Deletion Error"
            } else {
                title = "Template Could Not Be Deleted"
            }
            presentDocumentSaveAlert(title: title, message: error.localizedDescription)
        }
    }

    private func prepareTemplateApplication(_ templateURL: URL) {
        do {
            let values = try templateURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                throw TemplateConfigurationError.templateDocumentNotFound(templateURL)
            }
            _ = try loadTemplateConfiguration(for: templateURL)
            guard let targetURL = selectedDocumentFileURL,
                  targetURL.lastPathComponent == selectedDocumentName,
                  isScreenDocumentURL(targetURL),
                  FileManager.default.fileExists(atPath: targetURL.path) else {
                throw TemplateApplicationError.targetNotFound(
                    selectedDocumentFileURL ?? URL(fileURLWithPath: selectedDocumentName)
                )
            }
            let targetValues = try targetURL.resourceValues(forKeys: [.isRegularFileKey])
            guard targetValues.isRegularFile == true else {
                throw TemplateApplicationError.targetIsNotRegularFile(targetURL)
            }

            let saveResult = saveCurrentDocumentText()
            switch saveResult {
            case .unchanged, .saved, .reloadedFromDisk:
                break
            case .missing:
                presentDocumentSaveAlert(for: .missing)
                return
            case .conflict, .failed:
                return
            }

            pendingTemplateApplication = PendingTemplateApplication(
                templateURL: templateURL,
                templateName: templateURL.lastPathComponent,
                targetName: selectedDocumentName
            )
            isTemplateApplicationAlertPresented = true
        } catch {
            presentDocumentSaveAlert(
                title: "Template Could Not Be Opened",
                message: error.localizedDescription
            )
        }
    }

    private func applyPendingTemplate() {
        guard let pendingApplication = pendingTemplateApplication else { return }
        pendingTemplateApplication = nil

        guard selectedDocumentName == pendingApplication.targetName else {
            presentDocumentSaveAlert(
                title: "Template Could Not Be Applied",
                message: TemplateApplicationError.targetSelectionChanged(
                    expected: pendingApplication.targetName,
                    actual: selectedDocumentName
                ).localizedDescription
            )
            return
        }

        do {
            _ = try applyTemplate(
                pendingApplication.templateURL,
                pendingApplication.targetName
            )
            loadSelectedDocumentText()
            showSettingsFeedback("Template applied")
        } catch {
            let title: String
            if case .rollbackFailed = error as? TemplateApplicationError {
                title = "Critical Template Error"
            } else {
                title = "Template Could Not Be Applied"
            }
            presentDocumentSaveAlert(title: title, message: error.localizedDescription)
        }
    }

    private func showSettingsFeedback(_ message: String) {
        settingsFeedbackTask?.cancel()
        settingsFeedbackMessage = message
        settingsFeedbackTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            settingsFeedbackMessage = nil
        }
    }

    private func handleSettingsDocumentSelection(_ fileURL: URL) {
        loadFunctionKeys(fileURL)
    }

    private var settingsDocumentTableListMode: SettingsDocumentTableSection.ListMode {
        switch listMode {
        case .files:
            return .files
        case .text:
            return .text
        case .images:
            return .images
        case .sounds:
            return .sounds
        case .pdfs:
            return .pdfs
        case .templates:
            return .templates
        case .all:
            return .all
        }
    }

    private var settingsTablePreviewSection: AnyView {
        if listMode == .images {
            return AnyView(imagePreviewSection)
        }

        if listMode == .pdfs {
            return AnyView(pdfPreviewSection)
        }

        return AnyView(EmptyView())
    }

    private var customKeyboardTimingSection: some View {
        SettingsKeyboardTimingSection(
            timingLabelWidth: timingLabelWidth,
            keyboardTimingOnMs: $keyboardTimingOnMs,
            keyboardTimingOffMs: $keyboardTimingOffMs,
            speechRecognitionAutoOffMinutes: $speechRecognitionAutoOffMinutes,
            opacitySliderValue: $opacitySliderValue,
            imageControlButtons: AnyView(imageControlButtons),
            isEnabled: isCustomKeyboardTimingEnabled,
            onSetAndTest: {
                sendKeyboardTimingCommand()
                ble.sendString("Hello World! Let's go. (test) 1!2\"3#4$5%6&7'8(9)")
            }
        )
    }

    private var isCustomKeyboardTimingEnabled: Bool {
        OutputMode(persistedValue: outputModeRawValue) != .mac
    }

    private func presentDeleteAllDataConfirmation() {
        isDeleteAllDataConfirmationPresented = true
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(alignment: .sliderTrackCenter, spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(width: timingLabelWidth, alignment: .trailing)
                .alignmentGuide(.sliderTrackCenter) { dimensions in
                    dimensions[VerticalAlignment.center]
                }

            Button {
                ButtonClickFeedback.playIfEnabled()
                value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1)
            } label: {
                Image(systemName: "triangle.fill")
						.font(.system(size: 26))
						.rotationEffect(.degrees(-90))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .disabled(value.wrappedValue <= range.lowerBound)
            .alignmentGuide(.sliderTrackCenter) { dimensions in
                dimensions[VerticalAlignment.center]
            }

            VStack(spacing: -10) {
                Text("\(Int(value.wrappedValue)) ms")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)

                Slider(value: value, in: range, step: 10)
                    .tint(.white)
                    .alignmentGuide(.sliderTrackCenter) { dimensions in
                        dimensions[VerticalAlignment.center]
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)

            Button {
                ButtonClickFeedback.playIfEnabled()
                value.wrappedValue = min(range.upperBound, value.wrappedValue + 1)
            } label: {
                Image(systemName: "triangle.fill")
						.font(.system(size: 26))
						.rotationEffect(.degrees(90))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .disabled(value.wrappedValue >= range.upperBound)
            .alignmentGuide(.sliderTrackCenter) { dimensions in
                dimensions[VerticalAlignment.center]
            }
        }
    }

    private var speechRecognitionAutoOffRow: some View {
        HStack(alignment: .sliderTrackCenter, spacing: 4) {
            Text("rec off")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: timingLabelWidth, alignment: .trailing)
                .alignmentGuide(.sliderTrackCenter) { dimensions in
                    dimensions[VerticalAlignment.center]
                }

            Button {
                ButtonClickFeedback.playIfEnabled()
                speechRecognitionAutoOffMinutes = max(1, speechRecognitionAutoOffMinutes - 1)
            } label: {
                Image(systemName: "triangle.fill")
                    .font(.system(size: 26))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .disabled(speechRecognitionAutoOffMinutes <= 1)
            .alignmentGuide(.sliderTrackCenter) { dimensions in
                dimensions[VerticalAlignment.center]
            }

            VStack(spacing: -10) {
                Text(speechRecognitionAutoOffDisplayText)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)

                Slider(
                    value: Binding(
                        get: { Double(speechRecognitionAutoOffMinutes) },
                        set: { speechRecognitionAutoOffMinutes = Int($0.rounded()) }
                    ),
                    in: 1...Double(maximumSpeechRecognitionAutoOffMinutes),
                    step: 1
                )
                .tint(.white)
                .alignmentGuide(.sliderTrackCenter) { dimensions in
                    dimensions[VerticalAlignment.center]
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)

            Button {
                ButtonClickFeedback.playIfEnabled()
                speechRecognitionAutoOffMinutes = min(maximumSpeechRecognitionAutoOffMinutes, speechRecognitionAutoOffMinutes + 1)
            } label: {
                Image(systemName: "triangle.fill")
                    .font(.system(size: 26))
                    .rotationEffect(.degrees(90))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .disabled(speechRecognitionAutoOffMinutes >= maximumSpeechRecognitionAutoOffMinutes)
            .alignmentGuide(.sliderTrackCenter) { dimensions in
                dimensions[VerticalAlignment.center]
            }
        }
    }

    private var speechRecognitionAutoOffDisplayText: String {
        speechRecognitionAutoOffMinutes >= maximumSpeechRecognitionAutoOffMinutes
            ? "Never"
            : "\(speechRecognitionAutoOffMinutes) min"
    }

    private func documentRow(for fileURL: URL) -> some View {
        let isSelected = selectedDocumentName == fileURL.lastPathComponent

        return Button {
            ButtonClickFeedback.playIfEnabled()
            loadFunctionKeys(fileURL)
        } label: {
            HStack {
                Text(fileURL.lastPathComponent)
                    .fontWeight(isSelected ? .bold : .regular)
                    .foregroundStyle(isSelected ? Color.green : .white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(.leading, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Color.black)
            .overlay {
                Rectangle()
                    .fill(Color.gray.opacity(0.6))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                duplicateDocument(fileURL)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if canDeleteDocuments {
                Button(role: .destructive) {
                    deleteDocument(fileURL)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func loadSelectedDocumentText() {
        isLoadingDocumentText = true
        defer { isLoadingDocumentText = false }

        let fileURL = listMode == .text ? selectedTextFileURL : selectedDocumentFileURL

        guard let fileURL else {
            documentEditorText = ""
            savedDocumentEditorText = ""
            loadedDocumentName = ""
            loadedDocumentURL = nil
            blockedDocumentSaveResult = nil
            return
        }

        do {
            let loadedText = try String(contentsOf: fileURL, encoding: .utf8)
            documentEditorText = loadedText
            savedDocumentEditorText = loadedText
            loadedDocumentName = fileURL.lastPathComponent
            loadedDocumentURL = fileURL
            blockedDocumentSaveResult = nil
            documentNameDraft = currentTitleDisplayName
        } catch {
            presentDocumentSaveAlert(
                title: "File Could Not Be Opened",
                message: "The file could not be read. The current editor contents have been preserved."
            )
        }
    }

    private func loadTextFile(_ fileURL: URL) {
        selectedTextFileName = fileURL.lastPathComponent
        isLoadingDocumentText = true
        defer { isLoadingDocumentText = false }

        do {
            let loadedText = try String(contentsOf: fileURL, encoding: .utf8)
            documentEditorText = loadedText
            savedDocumentEditorText = loadedText
            loadedDocumentName = fileURL.lastPathComponent
            loadedDocumentURL = fileURL
            blockedDocumentSaveResult = nil
            documentNameDraft = currentTitleDisplayName
        } catch {
            presentDocumentSaveAlert(
                title: "File Could Not Be Opened",
                message: "The file could not be read. The current editor contents have been preserved."
            )
        }
    }

    @discardableResult
    private func saveSelectedDocumentText() -> DocumentSaveResult {
        guard let fileURL = selectedDocumentFileURL else {
            return .failed
        }

        return saveDocumentText(documentEditorText, to: fileURL)
    }

    @discardableResult
    private func saveCurrentDocumentText() -> DocumentSaveResult {
        guard !loadedDocumentName.isEmpty,
              let fileURL = fileURLForLoadedDocumentName() else {
            return .unchanged
        }

        return saveDocumentText(documentEditorText, to: fileURL)
    }

    @discardableResult
    private func saveCurrentDocumentText(_ text: String) -> DocumentSaveResult {
        guard !loadedDocumentName.isEmpty,
              let fileURL = fileURLForLoadedDocumentName() else {
            return .unchanged
        }

        return saveDocumentText(text, to: fileURL)
    }

    private func fileURLForLoadedDocumentName() -> URL? {
        guard loadedDocumentURL?.lastPathComponent == loadedDocumentName else {
            return nil
        }

        return loadedDocumentURL
    }

    private func saveAndReturnToMain(using text: String? = nil) {
        let textToSave = text ?? documentEditorText
        if let text {
            documentEditorText = text
        }

        let saveResult = saveCurrentDocumentText(textToSave)
        guard saveResult.allowsDocumentTransition else {
            return
        }

        do {
            guard try hasScreenDocumentsOnDisk() else {
                presentDocumentSaveAlert(
                    title: "No Screens Available",
                    message: "Please create a new screen or import a screen before going to Main."
                )
                return
            }
        } catch {
            presentDocumentSaveAlert(
                title: "File Could Not Be Saved",
                message: "The Documents folder could not be accessed. Please try again."
            )
            return
        }

        returnToMain()
    }

    private func hasScreenDocumentsOnDisk() throws -> Bool {
        guard let directoryURL = currentDocumentsDirectoryURL else {
            throw CocoaError(.fileReadUnknown)
        }

        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        let regularFileURLs = try fileURLs.filter { fileURL in
            try fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
        }

        return !preferredScreenDocumentURLs(from: regularFileURLs).isEmpty
    }

    private func clearLoadedDocumentAfterConfirmedDeletion() {
        let deletedDocumentName = loadedDocumentName
        let deletedDocumentDisplayName = URL(fileURLWithPath: deletedDocumentName)
            .deletingPathExtension()
            .lastPathComponent

        isLoadingDocumentText = true
        loadedDocumentName = ""
        loadedDocumentURL = nil
        blockedDocumentSaveResult = nil
        savedDocumentEditorText = ""
        documentEditorText = ""
        if documentNameDraft == deletedDocumentName || documentNameDraft == deletedDocumentDisplayName {
            documentNameDraft = ""
        }
        isLoadingDocumentText = false
    }

    private func isConfirmedMissingDocument(at fileURL: URL) throws -> Bool {
        do {
            _ = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            return false
        } catch {
            guard isConfirmedMissingDocument(
                error,
                at: fileURL,
                stage: "resource check"
            ) else {
                throw error
            }

            return true
        }
    }

    private func isConfirmedMissingDocument(
        _ error: Error,
        at fileURL: URL,
        stage: String
    ) -> Bool {
        let fileError = error as NSError
        if isMissingFileError(fileError) {
            logDocumentFileError(fileError, stage: stage, fileURL: fileURL, classification: "confirmed missing")
            return true
        }

        let parentDirectoryURL = fileURL.deletingLastPathComponent()
        guard let directoryContents = try? FileManager.default.contentsOfDirectory(
            at: parentDirectoryURL,
            includingPropertiesForKeys: nil
        ) else {
            logDocumentFileError(fileError, stage: stage, fileURL: fileURL, classification: "genuine failure")
            return false
        }

        let targetURL = fileURL.standardizedFileURL
        let documentExists = directoryContents.contains { $0.standardizedFileURL == targetURL }
        let classification = documentExists ? "genuine failure" : "confirmed missing"
        logDocumentFileError(fileError, stage: stage, fileURL: fileURL, classification: classification)
        return !documentExists
    }

    private func isMissingFileError(_ error: NSError) -> Bool {
        let missingCocoaErrorCodes = [
            CocoaError.Code.fileNoSuchFile.rawValue,
            CocoaError.Code.fileReadNoSuchFile.rawValue
        ]
        if error.domain == NSCocoaErrorDomain,
           missingCocoaErrorCodes.contains(error.code) {
            return true
        }

        if error.domain == NSPOSIXErrorDomain, error.code == ENOENT {
            return true
        }

        if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isMissingFileError(underlyingError)
        }

        return false
    }

    private func logDocumentFileError(
        _ error: NSError,
        stage: String,
        fileURL: URL,
        classification: String
    ) {
        print("🐞 [SET-001] stage=\(stage) filename=\(fileURL.lastPathComponent) domain=\(error.domain) code=\(error.code) classification=\(classification)")
    }

    private func handleConfirmedMissingDocument(_ text: String) -> DocumentSaveResult {
        guard text == savedDocumentEditorText else {
            blockedDocumentSaveResult = .missing
            presentDocumentSaveAlert(for: .missing)
            return .failed
        }

        clearLoadedDocumentAfterConfirmedDeletion()
        return .missing
    }

    private func saveDocumentText(_ text: String, to fileURL: URL) -> DocumentSaveResult {
        guard fileURL.lastPathComponent == loadedDocumentName,
              fileURL == loadedDocumentURL else {
            presentDocumentSaveAlert(
                title: "File Could Not Be Saved",
                message: "The editor baseline does not match this file. Your changes have not been saved."
            )
            return .failed
        }

        if let blockedDocumentSaveResult {
            if blockedDocumentSaveResult == .missing {
                do {
                    if try isConfirmedMissingDocument(at: fileURL) {
                        return handleConfirmedMissingDocument(text)
                    }
                    self.blockedDocumentSaveResult = nil
                } catch {
                    presentDocumentSaveAlert(for: .failed)
                    return .failed
                }
            } else {
                presentDocumentSaveAlert(for: blockedDocumentSaveResult)
                return blockedDocumentSaveResult
            }
        }

        do {
            if try isConfirmedMissingDocument(at: fileURL) {
                return handleConfirmedMissingDocument(text)
            }
        } catch {
            presentDocumentSaveAlert(for: .failed)
            return .failed
        }

        let diskText: String
        do {
            diskText = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            if isConfirmedMissingDocument(error, at: fileURL, stage: "read") {
                return handleConfirmedMissingDocument(text)
            }
            presentDocumentSaveAlert(
                title: "File Could Not Be Saved",
                message: "The file could not be read or saved. Your changes have not been saved."
            )
            return .failed
        }

        if diskText == text {
            savedDocumentEditorText = diskText
            return .unchanged
        }

        if text == savedDocumentEditorText {
            isLoadingDocumentText = true
            documentEditorText = diskText
            savedDocumentEditorText = diskText
            isLoadingDocumentText = false
            return .reloadedFromDisk
        }

        guard diskText == savedDocumentEditorText else {
            blockedDocumentSaveResult = .conflict
            presentDocumentSaveAlert(for: .conflict)
            return .conflict
        }

        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            savedDocumentEditorText = text
            loadedDocumentName = fileURL.lastPathComponent
            loadedDocumentURL = fileURL
            return .saved
        } catch {
            if isConfirmedMissingDocument(error, at: fileURL, stage: "write") {
                return handleConfirmedMissingDocument(text)
            }
            presentDocumentSaveAlert(
                title: "File Could Not Be Saved",
                message: "The file could not be read or saved. Your changes have not been saved."
            )
            return .failed
        }
    }

    private func presentDocumentSaveAlert(title: String, message: String) {
        documentSaveAlertTitle = title
        documentSaveAlertMessage = message
        isDocumentSaveAlertPresented = true
    }

    private func presentDocumentSaveAlert(for result: DocumentSaveResult) {
        switch result {
        case .conflict:
            presentDocumentSaveAlert(
                title: "File Changed Externally",
                message: "The file on disk has changed since it was opened. Your changes have not been saved."
            )
        case .missing:
            presentDocumentSaveAlert(
                title: "File Removed",
                message: "The file was removed outside ESP. Your unsaved changes have not been saved."
            )
        case .failed:
            presentDocumentSaveAlert(
                title: "File Could Not Be Saved",
                message: "The file could not be read or saved. Your changes have not been saved."
            )
        case .unchanged, .saved, .reloadedFromDisk:
            break
        }
    }

    // MARK: - BM:🅱️
    // MARK: - Legacy Screen Repair (Retained for Future Recovery)
    //
    // This repair utility was introduced during development of multi-cell
    // screen buttons to reconstruct malformed @@wide and @@block continuation
    // markers and normalize damaged .screen grid data.
    //
    // The Settings toolbar Repair button was intentionally removed before
    // public release because this operation is rarely needed and can
    // overwrite the selected screen without creating a backup or undo.
    //
    // Keep this function and its supporting helpers for possible future
    // recovery or migration work. It is intentionally not exposed in the
    // normal Settings interface.
    //
    // IMPORTANT: Do not call this automatically during app startup,
    // screen loading, import, or backup restoration. Any future user-facing
    // repair operation should provide clear confirmation and appropriate
    // protection of the original screen data.
    private func repairDocument() {
        guard listMode == .files, let fileURL = selectedDocumentFileURL else {
            repairAlertMessage = "Select a text file to repair"
            return
        }

        guard saveCurrentDocumentText().allowsDocumentTransition else {
            return
        }
        let repairedText = repairedDocumentText(from: documentEditorText, documentName: fileURL.lastPathComponent)
        let didRepair = repairedText != documentEditorText

        let saveResult = saveDocumentText(repairedText, to: fileURL)
        switch saveResult {
        case .saved, .unchanged:
            isLoadingDocumentText = true
            documentEditorText = repairedText
            savedDocumentEditorText = repairedText
            loadedDocumentName = fileURL.lastPathComponent
            loadedDocumentURL = fileURL
            isLoadingDocumentText = false
            loadFunctionKeys(fileURL)
            repairAlertMessage = didRepair ? "Document repaired" : "Document checked"
        case .reloadedFromDisk:
            repairAlertMessage = "The file changed outside ESP and was reloaded. Check it before repairing."
        case .conflict, .missing, .failed:
            break
        }
    }

    private func repairedDocumentText(from text: String, documentName: String) -> String {
        let lines = normalizedRepairLines(from: text)
        let gridDimensions = repairGridDimensions(for: documentName, requiredBoxCount: lines.count)
        var repairedLines = Array(repeating: "_", count: lines.count)
        var claimedIndexes = Set<Int>()

        for index in lines.indices {
            guard !claimedIndexes.contains(index),
                  !isRepairBlankLine(lines[index]),
                  !isRepairContinuationLine(lines[index]) else {
                continue
            }

            let shape = validRepairShape(
                startingAt: index,
                in: lines,
                gridDimensions: gridDimensions,
                claimedIndexes: claimedIndexes
            )
            let indexes = repairIndexes(startingAt: index, shape: shape, gridDimensions: gridDimensions)

            repairedLines[index] = lines[index]
            claimedIndexes.formUnion(indexes)

            for assignment in repairContinuationAssignments(
                startingAt: index,
                shape: shape,
                gridDimensions: gridDimensions
            ) where repairedLines.indices.contains(assignment.index) {
                repairedLines[assignment.index] = assignment.token
            }
        }

        return repairedLines.joined(separator: "\n")
    }

    private func normalizedRepairLines(from text: String) -> [String] {
        let normalizedText = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalizedText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        let boundedLines = Array(lines.prefix(maxFunctionKeyCount))
        return boundedLines.isEmpty ? ["_"] : boundedLines
    }

    private func repairGridDimensions(for documentName: String, requiredBoxCount: Int) -> GridDimensions {
        let minimumRequiredCount = max(requiredBoxCount, 1)
        let trimmedDocumentName = documentName.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedDocumentName.isEmpty,
           let documentURL = currentDocumentsDirectoryURL?.appendingPathComponent(trimmedDocumentName),
           let config = loadScreenConfig(for: documentURL) {
            let columns = max(config.grid.columns, 1)
            let rows = max(config.grid.rows, 1)
            if columns * rows >= minimumRequiredCount, columns * rows <= maxFunctionKeyCount {
                return (columns: columns, rows: rows)
            }
        }

        if !trimmedDocumentName.isEmpty,
           let data = documentGridDimensionsData.data(using: .utf8),
           let mappings = try? JSONDecoder().decode([String: SettingsStoredGridDimensions].self, from: data),
           let storedDimensions = mappings[trimmedDocumentName] {
            let columns = max(storedDimensions.columns, 1)
            let rows = max(storedDimensions.rows, 1)
            if columns * rows >= minimumRequiredCount, columns * rows <= maxFunctionKeyCount {
                return (columns: columns, rows: rows)
            }
        }

        return functionKeyGridDimensions(for: minimumRequiredCount)
    }

    private func validRepairShape(
        startingAt index: Int,
        in lines: [String],
        gridDimensions: GridDimensions,
        claimedIndexes: Set<Int>
    ) -> SettingsButtonStorageShape {
        let candidateShapes = [
            SettingsButtonStorageShape(width: 3, height: 3),
            SettingsButtonStorageShape(width: 3, height: 2),
            SettingsButtonStorageShape(width: 2, height: 2),
            SettingsButtonStorageShape(width: 1, height: 3),
            SettingsButtonStorageShape(width: 3, height: 1),
            SettingsButtonStorageShape(width: 1, height: 2),
            SettingsButtonStorageShape(width: 2, height: 1),
            SettingsButtonStorageShape(width: 1, height: 1)
        ]

        for shape in candidateShapes where repairShapeTokensMatch(
            startingAt: index,
            shape: shape,
            in: lines,
            gridDimensions: gridDimensions
        ) && canPlaceRepairShape(
            startingAt: index,
            shape: shape,
            lineCount: lines.count,
            gridDimensions: gridDimensions,
            claimedIndexes: claimedIndexes
        ) {
            return shape
        }

        return SettingsButtonStorageShape(width: 1, height: 1)
    }

    private func repairShapeTokensMatch(
        startingAt index: Int,
        shape: SettingsButtonStorageShape,
        in lines: [String],
        gridDimensions: GridDimensions
    ) -> Bool {
        repairContinuationAssignments(startingAt: index, shape: shape, gridDimensions: gridDimensions)
            .allSatisfy { assignment in
                lines.indices.contains(assignment.index) &&
                    lines[assignment.index].trimmingCharacters(in: .whitespacesAndNewlines) == assignment.token
            }
    }

    private func canPlaceRepairShape(
        startingAt index: Int,
        shape: SettingsButtonStorageShape,
        lineCount: Int,
        gridDimensions: GridDimensions,
        claimedIndexes: Set<Int>
    ) -> Bool {
        let columns = max(gridDimensions.columns, 1)
        let startColumn = index % columns
        let startRow = index / columns
        guard startColumn + shape.width <= columns,
              startRow + shape.height <= max(gridDimensions.rows, 1) else {
            return false
        }

        return repairIndexes(startingAt: index, shape: shape, gridDimensions: gridDimensions)
            .allSatisfy { slotIndex in
                slotIndex < lineCount && !claimedIndexes.contains(slotIndex)
            }
    }

    private func repairIndexes(
        startingAt index: Int,
        shape: SettingsButtonStorageShape,
        gridDimensions: GridDimensions
    ) -> [Int] {
        let columns = max(gridDimensions.columns, 1)
        var indexes: [Int] = []

        for rowOffset in 0..<shape.height {
            for columnOffset in 0..<shape.width {
                indexes.append(index + (rowOffset * columns) + columnOffset)
            }
        }

        return indexes
    }

    private func repairContinuationAssignments(
        startingAt index: Int,
        shape: SettingsButtonStorageShape,
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

    private func isRepairBlankLine(_ line: String) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedLine.isEmpty || trimmedLine == "_"
    }

    private func isRepairContinuationLine(_ line: String) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedLine == wideButtonContinuationToken || trimmedLine == blockButtonContinuationToken
    }

    private var selectedDocumentFileURL: URL? {
        availableDocumentURLs.first(where: { $0.lastPathComponent == selectedDocumentName })
    }

    private var selectedTextFileURL: URL? {
        guard !selectedTextFileName.isEmpty else {
            return availableTextURLs.first
        }

        return availableTextURLs.first(where: { $0.lastPathComponent == selectedTextFileName }) ?? availableTextURLs.first
    }

    private var availableDocumentURLs: [URL] {
        return preferredScreenDocumentURLs(
            from: documentDirectorySnapshot.filter { url in
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                return values?.isRegularFile == true
            }
        )
    }

    private var availableTextURLs: [URL] {
        return documentDirectorySnapshot
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                return values?.isRegularFile == true && url.pathExtension.lowercased() == legacyScreenDocumentFileExtension
            }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    private var selectedDocumentDisplayName: String {
        URL(fileURLWithPath: selectedDocumentName).deletingPathExtension().lastPathComponent
    }

    private var selectedTextDisplayName: String {
        guard let selectedTextFileURL else {
            return "text"
        }

        return selectedTextFileURL.deletingPathExtension().lastPathComponent
    }

    private var singleFileExportDisplayName: String {
        if let selectedDocumentFileURL {
            return selectedDocumentFileURL.deletingPathExtension().lastPathComponent
        }

        if !loadedDocumentName.isEmpty {
            return URL(fileURLWithPath: loadedDocumentName).deletingPathExtension().lastPathComponent
        }

        return "Document"
    }

    private var selectedImageDisplayName: String {
        guard let selectedImageURL else {
            return "black bg"
        }

        return selectedImageURL.deletingPathExtension().lastPathComponent
    }

    private var availableSoundURLs: [URL] {
        let supportedExtensions = supportedImportedSoundExtensions

        return documentDirectorySnapshot
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                return values?.isRegularFile == true && supportedExtensions.contains(url.pathExtension.lowercased())
            }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    private var availablePDFURLs: [URL] {
        return documentDirectorySnapshot
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                return values?.isRegularFile == true && url.pathExtension.lowercased() == "pdf"
            }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func refreshSettingsFileCollections() {
        refreshDocumentFiles()
        refreshTemplateFiles()
    }

    private func refreshTemplateFiles() {
        guard let documentsDirectoryURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            templateURLs = []
            clearTemplateSelection()
            return
        }

        let refreshedTemplateURLs = discoverTemplateDocumentURLs(in: documentsDirectoryURL)
        templateURLs = refreshedTemplateURLs

        guard let selectedTemplateURL else { return }
        guard refreshedTemplateURLs.contains(where: {
            $0.standardizedFileURL == selectedTemplateURL.standardizedFileURL
        }) else {
            clearTemplateSelection()
            return
        }

        selectTemplateForDescription(selectedTemplateURL)
    }

    private var availableAllFileURLs: [URL] {
        return documentDirectorySnapshot
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                return values?.isRegularFile == true &&
                    !isTemplateDocumentURL(url) &&
                    !isTemplateConfigurationURL(url) &&
                    (developerMode || !isInternalFile(url))
            }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func isInternalFile(_ url: URL) -> Bool {
        url.lastPathComponent.lowercased().hasSuffix(".config.json")
    }

    private var selectedSoundURL: URL? {
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

    private var selectedPDFURL: URL? {
        if !selectedPDFPath.isEmpty,
           let pdfURL = availablePDFURLs.first(where: { $0.path == selectedPDFPath }) {
            return pdfURL
        }

        if !selectedPDFName.isEmpty,
           let pdfURL = availablePDFURLs.first(where: {
               $0.lastPathComponent.caseInsensitiveCompare(selectedPDFName) == .orderedSame
           }) {
            return pdfURL
        }

        return nil
    }

    private func persistSelectedSound(_ soundURL: URL?) {
        selectedSoundPath = soundURL?.path ?? ""
        selectedSoundName = soundURL?.lastPathComponent ?? ""
    }

    private func persistSelectedPDF(_ pdfURL: URL?) {
        selectedPDFPath = pdfURL?.path ?? ""
        selectedPDFName = pdfURL?.lastPathComponent ?? ""
    }

    private var selectedSoundDisplayName: String {
        guard let selectedSoundURL else {
            return "sound"
        }

        return selectedSoundURL.deletingPathExtension().lastPathComponent
    }

    private var selectedPDFDisplayName: String {
        guard let selectedPDFURL else {
            return "pdf"
        }

        return selectedPDFURL.deletingPathExtension().lastPathComponent
    }

    private var currentTitleDisplayName: String {
        switch listMode {
        case .files:
            return selectedDocumentDisplayName
        case .text:
            return selectedTextDisplayName
        case .images:
            return selectedImageDisplayName
        case .sounds:
            return selectedSoundDisplayName
        case .pdfs:
            return selectedPDFDisplayName
        case .templates:
            return selectedDocumentDisplayName
        case .all:
            return "all files"
        }
    }

    private var canEditCurrentTitle: Bool {
        switch listMode {
        case .files:
            return selectedDocumentFileURL != nil
        case .text:
            return false
        case .images:
            return selectedImageURL != nil
        case .sounds:
            return selectedSoundURL != nil
        case .pdfs:
            return selectedPDFURL != nil
        case .templates:
            return false
        case .all:
            return false
        }
    }

    private var renameAlertIsPresented: Binding<Bool> {
        Binding(
            get: { renameAlertMessage != nil },
            set: { newValue in
                if !newValue {
                    renameAlertMessage = nil
                }
            }
        )
    }

    private func commitNameEdit() {
        let proposedName = documentNameDraft
        let alertMessage: String?

        switch listMode {
        case .files:
            alertMessage = renameDocument(proposedName)
        case .text:
            return
        case .images:
            alertMessage = renameSelectedImage(to: proposedName)
        case .sounds:
            alertMessage = renameSelectedSound(to: proposedName)
        case .pdfs:
            alertMessage = renameSelectedPDF(to: proposedName)
        case .templates:
            return
        case .all:
            return
        }

        if let alertMessage {
            renameAlertMessage = alertMessage
            isCancellingDocumentNameFromOutsideTap = false
            return
        }

        isCancellingDocumentNameFromOutsideTap = false
        documentNameDraft = currentTitleDisplayName
        isEditingDocumentName = false
        isDocumentNameFieldFocused = false
    }

    private func cancelNameEditing() {
        isCancellingDocumentNameFromOutsideTap = false
        documentNameDraft = currentTitleDisplayName
        isEditingDocumentName = false
        isDocumentNameFieldFocused = false
    }

    private func handleSettingsBackgroundTap() {
        if isEditingDocumentName {
            isCancellingDocumentNameFromOutsideTap = true
            isDocumentNameFieldFocused = false
        }

        focusedField = nil
        isDocumentEditorFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func handleSettingsKeyboardWillHide() {
        guard isEditingDocumentName else {
            return
        }

        guard !isCancellingDocumentNameFromOutsideTap else {
            return
        }

        commitNameEdit()
    }

    private func observeSettingsKeyboardHide() async {
        let notificationCenter = NotificationCenter.default

        for await _ in notificationCenter.notifications(named: UIResponder.keyboardWillHideNotification) {
            await MainActor.run {
                handleSettingsKeyboardWillHide()
            }
        }
    }

    private func createNewDocument() {
        saveCurrentDocumentText()

        guard let fileURL = nextAvailableNewDocumentURL() else {
            return
        }

        let newDocumentContents = Array(repeating: "_", count: 16).joined(separator: "\n")

        do {
            try newDocumentContents.write(to: fileURL, atomically: true, encoding: .utf8)
            refreshDocumentFiles()
            loadFunctionKeys(fileURL)
        } catch {
            db("Failed to create document: \(fileURL.lastPathComponent)")
        }
    }

    private func beginSaveAsTemplate() {
        guard canSaveCurrentScreenAsTemplate else {
            presentDocumentSaveAlert(
                title: "Template Could Not Be Saved",
                message: "The selected screen is not available."
            )
            return
        }

        saveAsTemplateSourceName = selectedDocumentName
        templateNameDraft = URL(fileURLWithPath: selectedDocumentName)
            .deletingPathExtension()
            .lastPathComponent
        templateDescriptionDraft = ""
        isSaveAsTemplateAlertPresented = true
    }

    private func cancelSaveAsTemplate() {
        saveAsTemplateSourceName = nil
        templateNameDraft = ""
        templateDescriptionDraft = ""
    }

    private func saveAsTemplate() {
        guard let expectedSourceName = saveAsTemplateSourceName else { return }
        let requestedName = templateNameDraft
        let requestedDescription = templateDescriptionDraft
        saveAsTemplateSourceName = nil

        guard selectedDocumentName == expectedSourceName else {
            presentDocumentSaveAlert(
                title: "Template Could Not Be Saved",
                message: TemplateCreationError.sourceSelectionChanged(
                    expected: expectedSourceName,
                    actual: selectedDocumentName
                ).localizedDescription
            )
            return
        }

        let saveResult = saveCurrentDocumentText()
        switch saveResult {
        case .unchanged, .saved, .reloadedFromDisk:
            break
        case .missing:
            presentDocumentSaveAlert(for: .missing)
            return
        case .conflict, .failed:
            return
        }

        guard let sourceURL = selectedDocumentFileURL,
              sourceURL.lastPathComponent == expectedSourceName,
              isScreenDocumentURL(sourceURL) else {
            presentDocumentSaveAlert(
                title: "Template Could Not Be Saved",
                message: "The selected screen is no longer available."
            )
            return
        }

        do {
            _ = try createTemplate(
                requestedName,
                requestedDescription,
                expectedSourceName
            )
            refreshTemplateFiles()
            showSettingsFeedback("Template saved")
            templateNameDraft = ""
            templateDescriptionDraft = ""
        } catch {
            let title: String
            if case .cleanupFailed = error as? TemplateCreationError {
                title = "Critical Template Error"
            } else {
                title = "Template Could Not Be Saved"
            }
            presentDocumentSaveAlert(title: title, message: error.localizedDescription)
        }
    }

    private func prepareSingleFileExport() {
        saveCurrentDocumentText()
        do {
            let exportURL = try makeSingleFileExportURL()
            singleFileExportURL = exportURL
        } catch {
            cleanupSingleFileExportTemporaryURLIfNeeded()
            renameAlertMessage = "Couldn't prepare the screen export."
        }
    }

    private func prepareArchiveExport() {
        saveCurrentDocumentText()

        guard hasArchiveExportContent else {
            renameAlertMessage = "There are no files to export."
            return
        }

        do {
            let archiveData = try makeFullArchiveData()
            exportArchiveDocument = SettingsArchiveFileDocument(data: archiveData)
            isExportingArchive = true
        } catch {
            renameAlertMessage = "Couldn't create Archive.zip."
        }
    }

    private func makeSingleFileExportURL() throws -> URL {
        cleanupSingleFileExportTemporaryURLIfNeeded()

        let documentFileName: String
        let documentData: Data
        let configData: Data

        if let selectedDocumentFileURL,
           isScreenDocumentURL(selectedDocumentFileURL) {
            documentFileName = selectedDocumentFileURL.lastPathComponent
            documentData = try Data(contentsOf: selectedDocumentFileURL)
            configData = try screenPackageConfigData(
                for: selectedDocumentFileURL,
                documentFileName: documentFileName
            )
        } else {
            documentFileName = screenDocumentFileName(forBaseName: singleFileExportDisplayName)
            documentData = Data(documentEditorText.utf8)
            configData = try defaultScreenPackageConfigData(
                forDocumentName: documentFileName,
                requiredBoxCount: requiredBoxCountForDocumentText(documentEditorText)
            )
        }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(singleFileExportDisplayName).zip")
        let archiveData = try SettingsArchiveFileDocument.makeArchiveData(
            with: [
                SettingsArchiveFileDocument.ArchiveEntry(
                    fileName: documentFileName,
                    data: documentData
                ),
                SettingsArchiveFileDocument.ArchiveEntry(
                    fileName: configFileName(forDocumentName: documentFileName),
                    data: configData
                )
            ]
        )

        try archiveData.write(to: temporaryURL, options: [.atomic])
        singleFileExportTemporaryURL = temporaryURL
        return temporaryURL
    }

    private func screenPackageConfigData(for documentURL: URL, documentFileName: String) throws -> Data {
        let screenConfigURL = configURL(forDocumentURL: documentURL)
        if FileManager.default.fileExists(atPath: screenConfigURL.path),
           let existingConfigData = try? Data(contentsOf: screenConfigURL),
           !existingConfigData.isEmpty,
           (try? JSONDecoder().decode(ScreenConfig.self, from: existingConfigData)) != nil {
            return existingConfigData
        }

        return try defaultScreenPackageConfigData(
            forDocumentName: documentFileName,
            requiredBoxCount: requiredBoxCountForImportedDocument(at: documentURL)
        )
    }

    private func defaultScreenPackageConfigData(forDocumentName documentFileName: String, requiredBoxCount: Int) throws -> Data {
        let config = defaultScreenConfig(for: documentFileName, requiredBoxCount: requiredBoxCount)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(config)
    }

    private func cleanupSingleFileExportTemporaryURLIfNeeded() {
        guard let singleFileExportTemporaryURL else {
            return
        }

        try? FileManager.default.removeItem(at: singleFileExportTemporaryURL)
        self.singleFileExportTemporaryURL = nil
    }

    private func applySettingsBackground(_ imageURL: URL?) {
        persistSelectedImage(imageURL)
        if imageURL == nil {
            selectPreviewImage(nil)
        } else {
            previewImageURL = imageURL
        }
        backgroundChangeFeedbackID = UUID()
    }

    private func selectSound(_ soundURL: URL) {
        persistSelectedSound(soundURL)
        playSelectedSoundPreview(from: soundURL)
    }

    private func selectPDF(_ pdfURL: URL) {
        persistSelectedPDF(pdfURL)
    }

    private func playSelectedSoundPreview(from soundURL: URL) {
        soundPreviewPlayer?.stop()
        soundPreviewPlayer = nil

        do {
            let player = try AVAudioPlayer(contentsOf: soundURL)
            player.prepareToPlay()
            player.play()
            soundPreviewPlayer = player
        } catch {
            soundPreviewPlayer = nil
        }
    }

    private func renameSelectedImage(to proposedName: String) -> String? {
        let trimmedName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            return "Filename can't be blank."
        }

        guard let sourceURL = selectedImageURL else {
            return "Select an image first."
        }

        let fileExtension = sourceURL.pathExtension
        let targetFileName = "\(trimmedName).\(fileExtension)"

        if targetFileName.caseInsensitiveCompare(sourceURL.lastPathComponent) == .orderedSame {
            return nil
        }

        let directoryURL = sourceURL.deletingLastPathComponent()

        if availableImageURLs.contains(where: { $0.lastPathComponent.caseInsensitiveCompare(targetFileName) == .orderedSame }) {
            return "a file with that name already exists."
        }

        let targetURL = directoryURL.appendingPathComponent(targetFileName)

        do {
            try FileManager.default.moveItem(at: sourceURL, to: targetURL)
            refreshDocumentFiles()
            persistSelectedImage(targetURL)
            return nil
        } catch {
            return "Couldn't rename the image."
        }
    }

    private func renameSelectedPDF(to proposedName: String) -> String? {
        let trimmedName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            return "Filename can't be blank."
        }

        guard let sourceURL = selectedPDFURL else {
            return "Select a pdf first."
        }

        let targetFileName = "\(trimmedName).pdf"
        let directoryURL = sourceURL.deletingLastPathComponent()

        if availablePDFURLs.contains(where: { $0.lastPathComponent.caseInsensitiveCompare(targetFileName) == .orderedSame }) {
            return "a file with that name already exists."
        }

        let targetURL = directoryURL.appendingPathComponent(targetFileName)

        do {
            try FileManager.default.moveItem(at: sourceURL, to: targetURL)
            refreshDocumentFiles()
            persistSelectedPDF(targetURL)
            return nil
        } catch {
            return "Couldn't rename the pdf."
        }
    }

    private func deleteImage(_ imageURL: URL) {
        let originalImageURLs = availableImageURLs
        let deletedImageIndex = originalImageURLs.firstIndex(where: { $0.path == imageURL.path })
        let predecessorURL: URL?
        if let deletedImageIndex, deletedImageIndex > 0 {
            predecessorURL = originalImageURLs[deletedImageIndex - 1]
        } else {
            predecessorURL = nil
        }
        let wasApplied = selectedImageURL?.path == imageURL.path
        let wasPreviewed = previewImageURL?.path == imageURL.path

        do {
            try FileManager.default.removeItem(at: imageURL)
        } catch {
            renameAlertMessage = "Couldn't delete the image."
            return
        }

        refreshDocumentFiles()
        let refreshedImageURLs = availableImageURLs
        let validatedPredecessorURL = predecessorURL.flatMap { predecessorURL in
            refreshedImageURLs.contains(where: { $0.path == predecessorURL.path }) ? predecessorURL : nil
        }

        if wasApplied {
            persistSelectedImage(validatedPredecessorURL)
            if let validatedPredecessorURL {
                previewImageURL = validatedPredecessorURL
            } else {
                selectPreviewImage(nil)
            }
        } else if wasPreviewed {
            if let validatedPredecessorURL {
                previewImageURL = validatedPredecessorURL
            } else {
                selectPreviewImage(nil)
            }
        }
    }

    private func renameSelectedSound(to proposedName: String) -> String? {
        let trimmedName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            return "Filename can't be blank."
        }

        guard let sourceURL = selectedSoundURL else {
            return "Select a sound first."
        }

        let fileExtension = sourceURL.pathExtension
        let targetFileName = "\(trimmedName).\(fileExtension)"

        if targetFileName.caseInsensitiveCompare(sourceURL.lastPathComponent) == .orderedSame {
            return nil
        }

        let directoryURL = sourceURL.deletingLastPathComponent()

        if availableSoundURLs.contains(where: { $0.lastPathComponent.caseInsensitiveCompare(targetFileName) == .orderedSame }) {
            return "a file with that name already exists."
        }

        let targetURL = directoryURL.appendingPathComponent(targetFileName)

        do {
            try FileManager.default.moveItem(at: sourceURL, to: targetURL)
            refreshDocumentFiles()
            persistSelectedSound(targetURL)
            return nil
        } catch {
            return "Couldn't rename the sound."
        }
    }

    private func deleteSound(_ soundURL: URL) {
        let previousSelectedSoundURL = selectedSoundURL

        do {
            try FileManager.default.removeItem(at: soundURL)
        } catch {
            renameAlertMessage = "Couldn't delete the sound."
            return
        }

        refreshDocumentFiles()
        let refreshedSoundURLs = availableSoundURLs

        if let previousSelectedSoundURL,
           previousSelectedSoundURL.lastPathComponent == soundURL.lastPathComponent {
            persistSelectedSound(refreshedSoundURLs.first)
        } else if let previousSelectedSoundURL,
                  let refreshedSoundIndex = refreshedSoundURLs.firstIndex(where: { $0.lastPathComponent == previousSelectedSoundURL.lastPathComponent }) {
            persistSelectedSound(refreshedSoundURLs[refreshedSoundIndex])
        }
    }

    private func deletePDF(_ pdfURL: URL) {
        let previousSelectedPDFURL = selectedPDFURL

        do {
            try FileManager.default.removeItem(at: pdfURL)
        } catch {
            renameAlertMessage = "Couldn't delete the pdf."
            return
        }

        refreshDocumentFiles()
        let refreshedPDFURLs = availablePDFURLs

        if let previousSelectedPDFURL,
           previousSelectedPDFURL.lastPathComponent == pdfURL.lastPathComponent {
            if let replacementURL = refreshedPDFURLs.first {
                persistSelectedPDF(replacementURL)
            } else {
                persistSelectedPDF(nil)
            }
        } else if let previousSelectedPDFURL,
                  let refreshedPDFIndex = refreshedPDFURLs.firstIndex(where: { $0.lastPathComponent == previousSelectedPDFURL.lastPathComponent }) {
            persistSelectedPDF(refreshedPDFURLs[refreshedPDFIndex])
        }
    }

    private func deleteTextFile(_ textURL: URL) {
        do {
            try FileManager.default.removeItem(at: textURL)
        } catch {
            renameAlertMessage = "Couldn't delete the text file."
            return
        }

        markImportedContentChanged()

        if selectedTextFileName == textURL.lastPathComponent {
            selectedTextFileName = availableTextURLs.first?.lastPathComponent ?? ""
        }

        if loadedDocumentName == textURL.lastPathComponent {
            loadSelectedDocumentText()
        }
    }

    private func deleteAllData() {
        guard let directoryURL = currentDocumentsDirectoryURL else {
            renameAlertMessage = "Couldn't find the Documents folder."
            db("DELETE_ALL_TRACE no_documents_directory")
            return
        }

        do {
            let allBeforeDeleteURLs = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: []
            )

            for itemURL in allBeforeDeleteURLs {
                do {
                    try FileManager.default.removeItem(at: itemURL)
                } catch {
                    db("DELETE_ALL_TRACE remove_failed item=\(itemURL.lastPathComponent) path=\(itemURL.path) error=\(error)")
                    throw error
                }
            }

            resetSettingsStateAfterDeletingAllData()
            markDeletedAllDataChanged()
        } catch {
            db("DELETE_ALL_TRACE delete_all_failed error=\(error)")
            renameAlertMessage = "Couldn't delete all data: \(error.localizedDescription)"
        }
    }

    private func resetSettingsStateAfterDeletingAllData() {
        isLoadingDocumentText = true
        documentEditorText = ""
        savedDocumentEditorText = ""
        loadedDocumentName = ""
        documentNameDraft = ""
        selectedTextFileName = ""
        isLoadingDocumentText = false

        persistSelectedImage(nil)
        persistSelectedSound(nil)
        persistSelectedPDF(nil)
        cancelNameEditing()
    }

    private func deleteAllFile(_ fileURL: URL) {
        let fileExtension = fileURL.pathExtension.lowercased()

        if isScreenDocumentURL(fileURL) {
            deleteDocument(fileURL)
            return
        }

        if supportedImportedImageExtensions.contains(fileExtension) {
            deleteImage(fileURL)
            return
        }

        if supportedImportedSoundExtensions.contains(fileExtension) {
            deleteSound(fileURL)
            return
        }

        if supportedImportedPDFExtensions.contains(fileExtension) {
            deletePDF(fileURL)
            return
        }

        if fileExtension == legacyScreenDocumentFileExtension {
            deleteTextFile(fileURL)
            return
        }

        do {
            try FileManager.default.removeItem(at: fileURL)
            markImportedContentChanged()
        } catch {
            renameAlertMessage = "Couldn't delete the file."
        }
    }

    private var plainTextImportType: UTType {
        UTType(filenameExtension: "txt") ?? .plainText
    }

    private var screenDocumentImportType: UTType {
        UTType(filenameExtension: screenDocumentFileExtension) ?? .data
    }

    private var zipImportType: UTType {
        UTType(filenameExtension: "zip") ?? .data
    }

    private var screenConfigImportType: UTType {
        UTType(filenameExtension: "json") ?? .json
    }

    private var supportedImportedImageExtensions: Set<String> {
        ["png", "jpg", "jpeg", "heic", "heif", "gif", "bmp", "tiff", "webp"]
    }

    var supportedImportedSoundExtensions: Set<String> {
        ["mp3", "wav", "m4a", "aiff", "aac", "caf"]
    }

    private var supportedImportedPDFExtensions: Set<String> {
        ["pdf"]
    }

    private func handleImportedSelection(_ result: Result<[URL], Error>, importMode: SettingsImportMode?) {
        guard case let .success(urls) = result else {
            return
        }

        guard let importMode else {
            return
        }

        guard let directoryURL = currentDocumentsDirectoryURL else {
            db("IMPORT_TRACE rejected reason=missing_documents_directory")
            return
        }

        switch importMode {
        case .screen:
            guard !screenImportSelectionContainsFullBackup(urls) else {
                renameAlertMessage = settingsFullBackupImportRejectedMessage
                return
            }

            let session = makePendingImportSession(
                directoryURL: directoryURL,
                importMode: .screen,
                remainingURLs: urls,
                selectedConfigURLsByName: selectedScreenConfigURLsByName(from: urls)
            )
            processPendingImportSession(session)
        case .allFiles:
            guard let zipURL = urls.first, urls.count == 1, zipURL.pathExtension.lowercased() == "zip" else {
                db("IMPORT_TRACE all_files_archive_validation=invalid reason=expected_single_zip")
                renameAlertMessage = "Restore Full Backup expects one ZIP file."
                return
            }

            do {
                let preflight = try makeFullRestorePreflight(from: zipURL, directoryURL: directoryURL)
                guard !preflight.conflictFileNameKeys.isEmpty else {
                    processPendingImportSession(preflight.session)
                    return
                }

                pendingFullRestore = PendingFullRestore(
                    session: preflight.session,
                    skipFileNameKeys: preflight.skipFileNameKeys,
                    skipTemplatePairKeys: preflight.skipTemplatePairKeys
                )
            } catch {
                db("IMPORT_TRACE all_files_archive_validation=invalid error=\(error.localizedDescription)")
                renameAlertMessage = error is SettingsArchiveError
                    ? settingsUnsupportedFullBackupZIPMessage
                    : "Couldn't import full backup: \(error.localizedDescription)"
            }
        }
    }

    private func makeFullRestorePreflight(from zipURL: URL, directoryURL: URL) throws -> FullRestorePreflight {
        let archiveImport = try extractFullArchiveImport(from: zipURL)
        let destinationFileNameKeys = archiveImport.fileURLs.map { $0.lastPathComponent.lowercased() }
        let existingFileNameKeys = existingDocumentDirectoryFileNameKeys(in: directoryURL)
        let conflictFileNameKeys = Set(destinationFileNameKeys.filter { existingFileNameKeys.contains($0) })
        let existingTemplateDestinationKeys = existingTemplateDestinationFileNameKeys(in: directoryURL)
        let conflictingTemplatePairs = archiveImport.templatePairs.filter {
            existingTemplateDestinationKeys.contains($0.templateKey) ||
                existingTemplateDestinationKeys.contains($0.configurationKey)
        }
        let templateConflictKeys = Set(conflictingTemplatePairs.map(\.templateKey))
        let screenConflictConfigKeys = Set(archiveImport.fileURLs.compactMap { fileURL -> String? in
            guard isScreenDocumentURL(fileURL),
                  conflictFileNameKeys.contains(fileURL.lastPathComponent.lowercased()) else {
                return nil
            }

            return configFileName(forDocumentName: fileURL.lastPathComponent).lowercased()
        })

        var session = makePendingImportSession(
            directoryURL: directoryURL,
            importMode: .allFiles,
            remainingURLs: archiveImport.fileURLs,
            selectedConfigURLsByName: archiveImport.configURLsByName
        )
        session.temporaryImportDirectoryURLs.append(archiveImport.temporaryDirectoryURL)
        session.templateRestorePairs = archiveImport.templatePairs

        return FullRestorePreflight(
            session: session,
            conflictFileNameKeys: conflictFileNameKeys.union(templateConflictKeys),
            skipFileNameKeys: conflictFileNameKeys.union(screenConflictConfigKeys),
            skipTemplatePairKeys: templateConflictKeys
        )
    }

    private func existingTemplateDestinationFileNameKeys(in directoryURL: URL) -> Set<String> {
        let fileURLs = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return Set(fileURLs.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values?.isRegularFile == true || values?.isSymbolicLink == true else { return nil }
            return templateFileNameCollisionKey(url.lastPathComponent)
        })
    }

    private func existingDocumentDirectoryFileNameKeys(in directoryURL: URL) -> Set<String> {
        let fileURLs = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return Set(fileURLs.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { return nil }
            return url.lastPathComponent.lowercased()
        })
    }

    private func resolvePendingFullRestore(_ resolution: RestoreConflictResolution) {
        guard var restore = pendingFullRestore else {
            return
        }

        pendingFullRestore = nil
        switch resolution {
        case .replaceAll:
            processPendingImportSession(restore.session)
        case .skipAll:
            restore.session.skipFileNameKeys = restore.skipFileNameKeys
            restore.session.skipTemplatePairKeys = restore.skipTemplatePairKeys
            processPendingImportSession(restore.session)
        }
    }

    private func cancelPendingFullRestore() {
        guard let restore = pendingFullRestore else {
            return
        }

        cleanupTemporaryImportDirectories(restore.session.temporaryImportDirectoryURLs)
        pendingFullRestore = nil
    }

    private func makePendingImportSession(
        directoryURL: URL,
        importMode: SettingsImportMode,
        remainingURLs: [URL],
        selectedConfigURLsByName: [String: URL]
    ) -> PendingImportSession {
        return PendingImportSession(
            directoryURL: directoryURL,
            importListMode: importMode == .screen ? .files : nil,
            importMode: importMode,
            remainingURLs: remainingURLs,
            selectedConfigURLsByName: selectedConfigURLsByName,
            existingFileNames: Set(availableDocumentURLs.map { $0.lastPathComponent.lowercased() }),
            existingTextNames: Set(availableTextURLs.map { $0.lastPathComponent.lowercased() }),
            existingConfigNames: existingConfigFileNames(),
            existingImageNames: Set(availableImageURLs.map { $0.lastPathComponent.lowercased() }),
            existingSoundNames: Set(availableSoundURLs.map { $0.lastPathComponent.lowercased() }),
            existingPDFNames: Set(availablePDFURLs.map { $0.lastPathComponent.lowercased() })
        )
    }

    private func processPendingImportSession(_ session: PendingImportSession) {
        var session = session
        processTemplateRestorePairs(session: &session)
        if session.importMode == .allFiles {
        }

        while !session.remainingURLs.isEmpty {
            let sourceURL = session.remainingURLs.removeFirst()
            session.processedItemCount += 1
            let pathExtension = sourceURL.pathExtension.lowercased()
            let targetFileName = sourceURL.lastPathComponent
            let targetFileNameKey = targetFileName.lowercased()
            let targetURL = session.directoryURL.appendingPathComponent(targetFileName)
            if session.importMode == .allFiles {
            }

            if session.importMode == .allFiles,
               session.skipFileNameKeys.contains(targetFileNameKey) {
                continue
            }

            if pathExtension == "zip" {
                guard session.importMode == .screen || session.importMode == .allFiles else {
                    continue
                }

                do {

                    if let archiveImport = try extractFullArchiveImportIfPresent(from: sourceURL) {
                        guard session.importMode != .screen else {
                            cleanupTemporaryImportDirectories(session.temporaryImportDirectoryURLs + [archiveImport.temporaryDirectoryURL])
                            renameAlertMessage = settingsFullBackupImportRejectedMessage
                            return
                        }

                        session.importMode = .allFiles
                        session.importListMode = nil
                        session.temporaryImportDirectoryURLs.append(archiveImport.temporaryDirectoryURL)
                        session.selectedConfigURLsByName.merge(archiveImport.configURLsByName) { _, newValue in newValue }
                        session.remainingURLs = archiveImport.fileURLs + session.remainingURLs
                    } else {
                        let package = try extractScreenPackageImport(from: sourceURL)
                        session.temporaryImportDirectoryURLs.append(package.temporaryDirectoryURL)
                        if let configURL = package.configURL {
                            session.selectedConfigURLsByName[configURL.lastPathComponent.lowercased()] = configURL
                        }
                        let packageFilePaths = Set([package.documentURL.path, package.configURL?.path].compactMap { $0 })
                        session.remainingURLs = [package.documentURL] + session.remainingURLs.filter { !packageFilePaths.contains($0.path) }
                    }
                } catch {
                    db("IMPORT_TRACE zip_classification=invalid_archive filename=\(targetFileName) error=\(error.localizedDescription)")
                    db("Failed to import screen package \(targetFileName): \(error.localizedDescription)")
                    if error is SettingsArchiveError {
                        renameAlertMessage = settingsUnsupportedScreenZIPMessage
                    }
                }
                continue
            }

            if isScreenConfigFileName(targetFileName) {
                guard session.importMode == .allFiles else {
                    continue
                }

                if session.existingConfigNames.contains(targetFileNameKey) ||
                    FileManager.default.fileExists(atPath: targetURL.path) {
                    if applyPendingImportConflictIfNeeded(
                        sourceURL: sourceURL,
                        targetURL: targetURL,
                        fileName: targetFileName,
                        contentKind: .config,
                        session: &session
                    ) {
                        return
                    }
                    continue
                }

                do {
                    try importValidScreenConfig(from: sourceURL, to: targetURL)
                    recordSuccessfulImport(
                        targetURL: targetURL,
                        fileNameKey: targetFileNameKey,
                        contentKind: .config,
                        session: &session
                    )
                } catch {
                    recordImportFailure(fileName: targetFileName, error: error, session: &session)
                    db("Failed to import screen config \(targetFileName): \(error.localizedDescription)")
                }
                continue
            }

            if isScreenDocumentFileExtension(pathExtension) {
                if session.existingFileNames.contains(targetFileNameKey) ||
                    FileManager.default.fileExists(atPath: targetURL.path) {
                    if applyPendingImportConflictIfNeeded(
                        sourceURL: sourceURL,
                        targetURL: targetURL,
                        fileName: targetFileName,
                        contentKind: .document,
                        session: &session
                    ) {
                        return
                    }
                    continue
                }

                do {
                    try importFileData(from: sourceURL, to: targetURL)
                    ensureImportedScreenConfig(for: targetURL, session: session, replacingDocument: false)
                    recordSuccessfulImport(
                        targetURL: targetURL,
                        fileNameKey: targetFileNameKey,
                        contentKind: .document,
                        session: &session
                    )
                } catch {
                    recordImportFailure(fileName: targetFileName, error: error, session: &session)
                    db("Failed to import text file \(targetFileName): \(error.localizedDescription)")
                }
                continue
            }

            if pathExtension == legacyScreenDocumentFileExtension {
                guard session.importMode == .allFiles else {
                    continue
                }

                if session.existingTextNames.contains(targetFileNameKey) ||
                    FileManager.default.fileExists(atPath: targetURL.path) {
                    if applyPendingImportConflictIfNeeded(
                        sourceURL: sourceURL,
                        targetURL: targetURL,
                        fileName: targetFileName,
                        contentKind: .text,
                        session: &session
                    ) {
                        return
                    }
                    continue
                }

                do {
                    try importFileData(from: sourceURL, to: targetURL)
                    recordSuccessfulImport(
                        targetURL: targetURL,
                        fileNameKey: targetFileNameKey,
                        contentKind: .text,
                        session: &session
                    )
                } catch {
                    recordImportFailure(fileName: targetFileName, error: error, session: &session)
                    db("Failed to import text file \(targetFileName): \(error.localizedDescription)")
                }
                continue
            }

            if supportedImportedImageExtensions.contains(pathExtension) {
                guard session.importMode == .allFiles else {
                    continue
                }

                if session.existingImageNames.contains(targetFileNameKey) ||
                    FileManager.default.fileExists(atPath: targetURL.path) {
                    if applyPendingImportConflictIfNeeded(
                        sourceURL: sourceURL,
                        targetURL: targetURL,
                        fileName: targetFileName,
                        contentKind: .image,
                        session: &session
                    ) {
                        return
                    }
                    continue
                }

                do {
                    try importFileData(from: sourceURL, to: targetURL)
                    recordSuccessfulImport(
                        targetURL: targetURL,
                        fileNameKey: targetFileNameKey,
                        contentKind: .image,
                        session: &session
                    )
                } catch {
                    recordImportFailure(fileName: targetFileName, error: error, session: &session)
                    db("Failed to import image \(targetFileName): \(error.localizedDescription)")
                }
                continue
            }

            if supportedImportedSoundExtensions.contains(pathExtension) {
                guard session.importMode == .allFiles else {
                    continue
                }

                if session.existingSoundNames.contains(targetFileNameKey) ||
                    FileManager.default.fileExists(atPath: targetURL.path) {
                    if applyPendingImportConflictIfNeeded(
                        sourceURL: sourceURL,
                        targetURL: targetURL,
                        fileName: targetFileName,
                        contentKind: .sound,
                        session: &session
                    ) {
                        return
                    }
                    continue
                }

                do {
                    try importFileData(from: sourceURL, to: targetURL)
                    recordSuccessfulImport(
                        targetURL: targetURL,
                        fileNameKey: targetFileNameKey,
                        contentKind: .sound,
                        session: &session
                    )
                } catch {
                    recordImportFailure(fileName: targetFileName, error: error, session: &session)
                    db("Failed to import sound \(targetFileName): \(error.localizedDescription)")
                }
                continue
            }

            if supportedImportedPDFExtensions.contains(pathExtension) {
                guard session.importMode == .allFiles else {
                    continue
                }

                if session.existingPDFNames.contains(targetFileNameKey) ||
                    FileManager.default.fileExists(atPath: targetURL.path) {
                    if applyPendingImportConflictIfNeeded(
                        sourceURL: sourceURL,
                        targetURL: targetURL,
                        fileName: targetFileName,
                        contentKind: .pdf,
                        session: &session
                    ) {
                        return
                    }
                    continue
                }

                do {
                    try importFileData(from: sourceURL, to: targetURL)
                    recordSuccessfulImport(
                        targetURL: targetURL,
                        fileNameKey: targetFileNameKey,
                        contentKind: .pdf,
                        session: &session
                    )
                } catch {
                    recordImportFailure(fileName: targetFileName, error: error, session: &session)
                    db("Failed to import pdf \(targetFileName): \(error.localizedDescription)")
                }
                continue
            }

            db("IMPORT_TRACE file_rejected filename=\(targetFileName) reason=unsupported_extension extension=\(pathExtension) mode=\(session.importMode)")
        }

        if session.importMode == .allFiles {
        }
        finishPendingImportSession(session)
    }

    private func processTemplateRestorePairs(session: inout PendingImportSession) {
        guard session.importMode == .allFiles, !session.templateRestorePairs.isEmpty else {
            return
        }

        let templatePairs = session.templateRestorePairs
        session.templateRestorePairs = []
        session.templateRestoreAttempted = true

        for pair in templatePairs {
            guard !session.skipTemplatePairKeys.contains(pair.templateKey) else {
                continue
            }

            do {
                _ = try restoreTemplateDocumentPair(
                    templateFileName: pair.templateFileName,
                    templateData: pair.templateData,
                    configurationData: pair.configurationData,
                    to: session.directoryURL
                )
                session.importedAnything = true
                session.importedFileCount += 1
            } catch {
                session.failedFileCount += 1
                renameAlertMessage = "Couldn't restore template \(pair.templateFileName): \(error.localizedDescription)"
            }
        }
    }

    private func recordSuccessfulImport(
        targetURL: URL,
        fileNameKey: String,
        contentKind: ImportedContentKind,
        session: inout PendingImportSession
    ) {
        session.importedAnything = true
        session.importedFileCount += 1
        if session.importMode == .allFiles {
        }

        switch contentKind {
        case .document:
            session.existingFileNames.insert(fileNameKey)
            if session.firstImportedDocumentURL == nil {
                session.firstImportedDocumentURL = targetURL
            }
            reloadEditorAfterSuccessfulImportIfNeeded(at: targetURL)
        case .config:
            session.existingConfigNames.insert(fileNameKey)
        case .text:
            session.existingTextNames.insert(fileNameKey)
            if session.firstImportedTextURL == nil {
                session.firstImportedTextURL = targetURL
            }
        case .image:
            session.existingImageNames.insert(fileNameKey)
            if session.firstImportedImageURL == nil {
                session.firstImportedImageURL = targetURL
            }
        case .sound:
            session.existingSoundNames.insert(fileNameKey)
            if session.firstImportedSoundURL == nil {
                session.firstImportedSoundURL = targetURL
            }
        case .pdf:
            session.existingPDFNames.insert(fileNameKey)
            if session.firstImportedPDFURL == nil {
                session.firstImportedPDFURL = targetURL
            }
        case .templateDocument, .templateConfiguration:
            break
        }
    }

    private func reloadEditorAfterSuccessfulImportIfNeeded(at targetURL: URL) {
        guard listMode == .files,
              let loadedDocumentURL,
              let selectedDocumentFileURL,
              loadedDocumentURL.standardizedFileURL == targetURL.standardizedFileURL,
              selectedDocumentFileURL.standardizedFileURL == targetURL.standardizedFileURL else {
            return
        }

        loadSelectedDocumentText()
    }

    private func recordImportFailure(fileName: String, error: Error, session: inout PendingImportSession) {
        session.failedFileCount += 1
        if session.importMode == .allFiles {
            db("IMPORT_FULL_COPY_FAILED filename=\(fileName) error=\(error.localizedDescription)")
        }
    }

    private func applyPendingImportConflictIfNeeded(
        sourceURL: URL,
        targetURL: URL,
        fileName: String,
        contentKind: ImportedContentKind,
        session: inout PendingImportSession
    ) -> Bool {
        if session.importMode == .allFiles {
            importReplacingExistingFile(
                sourceURL: sourceURL,
                targetURL: targetURL,
                fileName: fileName,
                contentKind: contentKind,
                session: &session
            )
            return false
        }

        if let resolution = session.applyToAllResolution {
            switch resolution {
            case .replace:
                if session.importMode == .allFiles {
                }
                importReplacingExistingFile(
                    sourceURL: sourceURL,
                    targetURL: targetURL,
                    fileName: fileName,
                    contentKind: contentKind,
                    session: &session
                )
            case .keepBoth:
                if session.importMode == .allFiles {
                }
                importKeepingBothFiles(
                    sourceURL: sourceURL,
                    preferredTargetURL: targetURL,
                    contentKind: contentKind,
                    session: &session
                )
            }
            return false
        }

        if session.importMode == .allFiles {
        }
        pendingImportSession = session
        pendingImportConflict = PendingImportConflict(
            sourceURL: sourceURL,
            targetURL: targetURL,
            fileName: fileName,
            contentKind: contentKind
        )
        return true
    }

    private func resolvePendingImportConflictByReplacing() {
        guard var session = pendingImportSession,
              let conflict = pendingImportConflict else {
            db("IMPORT_CONFLICT filename=nil action=replace continuing=false reason=missing_pending_conflict")
            return
        }

        pendingImportConflict = nil
        pendingImportSession = nil

        if importConflictApplyToAll, session.importMode == .allFiles {
            session.applyToAllResolution = .replace
        }

        if session.importMode == .allFiles {
        }
        importReplacingExistingFile(
            sourceURL: conflict.sourceURL,
            targetURL: conflict.targetURL,
            fileName: conflict.fileName,
            contentKind: conflict.contentKind,
            session: &session
        )
        processPendingImportSession(session)
    }

    private func resolvePendingImportConflictKeepingBoth() {
        guard var session = pendingImportSession,
              let conflict = pendingImportConflict else {
            db("IMPORT_CONFLICT filename=nil action=keepBoth continuing=false reason=missing_pending_conflict")
            return
        }

        pendingImportConflict = nil
        pendingImportSession = nil

        if importConflictApplyToAll, session.importMode == .allFiles {
            session.applyToAllResolution = .keepBoth
        }

        if session.importMode == .allFiles {
        }
        importKeepingBothFiles(
            sourceURL: conflict.sourceURL,
            preferredTargetURL: conflict.targetURL,
            contentKind: conflict.contentKind,
            session: &session
        )
        processPendingImportSession(session)
    }

    private func resolvePendingImportConflictBySkipping() {
        guard let session = pendingImportSession else {
            pendingImportConflict = nil
            return
        }

        pendingImportConflict = nil
        pendingImportSession = nil
        processPendingImportSession(session)
    }

    private func importReplacingExistingFile(
        sourceURL: URL,
        targetURL: URL,
        fileName: String,
        contentKind: ImportedContentKind,
        session: inout PendingImportSession
    ) {
        do {
            let targetExists = FileManager.default.fileExists(atPath: targetURL.path)

            if targetExists {
                switch contentKind {
                case .config:
                    try safelyReplaceExistingScreenConfig(from: sourceURL, to: targetURL)
                default:
                    try safelyReplaceExistingImportedFile(from: sourceURL, to: targetURL)
                }

                if contentKind == .document {
                    ensureImportedScreenConfig(for: targetURL, session: session, replacingDocument: true)
                }

                session.replacedFileCount += 1
                recordSuccessfulImport(
                    targetURL: targetURL,
                    fileNameKey: targetURL.lastPathComponent.lowercased(),
                    contentKind: contentKind,
                    session: &session
                )
                return
            }

            try importResolvedFile(
                from: sourceURL,
                to: targetURL,
                contentKind: contentKind,
                session: &session,
                replacingDocument: true
            )

        } catch {
            recordImportFailure(fileName: fileName, error: error, session: &session)
            renameAlertMessage = "Couldn't import \(fileName): \(error.localizedDescription)"
        }
    }

    private func importKeepingBothFiles(
        sourceURL: URL,
        preferredTargetURL: URL,
        contentKind: ImportedContentKind,
        session: inout PendingImportSession
    ) {
        let targetURL = uniqueImportTargetURL(for: preferredTargetURL, session: session)

        do {
            try importResolvedFile(
                from: sourceURL,
                to: targetURL,
                contentKind: contentKind,
                session: &session,
                replacingDocument: false
            )
        } catch {
            recordImportFailure(fileName: preferredTargetURL.lastPathComponent, error: error, session: &session)
            renameAlertMessage = "Couldn't import \(preferredTargetURL.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func importResolvedFile(
        from sourceURL: URL,
        to targetURL: URL,
        contentKind: ImportedContentKind,
        session: inout PendingImportSession,
        replacingDocument: Bool
    ) throws {
        switch contentKind {
        case .config:
            try importValidScreenConfig(from: sourceURL, to: targetURL)
        default:
            try importFileData(from: sourceURL, to: targetURL)
        }

        if contentKind == .document {
            ensureImportedScreenConfig(for: targetURL, session: session, replacingDocument: replacingDocument)
        }

        recordSuccessfulImport(
            targetURL: targetURL,
            fileNameKey: targetURL.lastPathComponent.lowercased(),
            contentKind: contentKind,
            session: &session
        )
    }

    private func cancelPendingImportSession() {
        guard let session = pendingImportSession else {
            db("IMPORT_CONFLICT filename=\(pendingImportConflict?.fileName ?? "nil") action=stop continuing=false reason=missing_pending_session")
            pendingImportConflict = nil
            return
        }

        if session.importMode == .allFiles {
        }
        pendingImportConflict = nil
        pendingImportSession = nil
        finishPendingImportSession(session)
    }

    private func finishPendingImportSession(_ session: PendingImportSession) {
        pendingImportConflict = nil
        pendingImportSession = nil
        importConflictApplyToAll = false

        cleanupTemporaryImportDirectories(session.temporaryImportDirectoryURLs)

        if session.templateRestoreAttempted {
            refreshTemplateFiles()
        }

        if session.importMode == .allFiles,
           session.failedFileCount > 0,
           renameAlertMessage == nil {
            renameAlertMessage = "Some files couldn't be restored: \(session.failedFileCount) failed."
        }

        guard session.importedAnything else { return }

        markImportedContentChanged()

        if let firstImportedDocumentURL = session.firstImportedDocumentURL {
            loadFunctionKeys(firstImportedDocumentURL)
        }

        if let firstImportedImageURL = session.firstImportedImageURL,
           session.importListMode == .images || selectedImageURL == nil {
            persistSelectedImage(firstImportedImageURL)
        }

        if let firstImportedSoundURL = session.firstImportedSoundURL,
           session.importListMode == .sounds || selectedSoundURL == nil {
            persistSelectedSound(firstImportedSoundURL)
        }

        if let firstImportedPDFURL = session.firstImportedPDFURL,
           session.importListMode == .pdfs || selectedPDFURL == nil {
            persistSelectedPDF(firstImportedPDFURL)
        }

        if session.importMode == .allFiles,
           session.failedFileCount == 0,
           session.skipFileNameKeys.isEmpty,
           session.skipTemplatePairKeys.isEmpty,
           renameAlertMessage == nil {
            showSettingsFeedback("Restore Complete")
        }
    }

    private func cleanupTemporaryImportDirectories(_ directoryURLs: [URL]) {
        for directoryURL in directoryURLs {
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }

    private func screenImportSelectionContainsFullBackup(_ urls: [URL]) -> Bool {
        for url in urls where url.pathExtension.lowercased() == "zip" {
            guard (try? isFullBackupArchive(url)) == true else {
                continue
            }

            return true
        }

        return false
    }

    private func isFullBackupArchive(_ zipURL: URL) throws -> Bool {
        let archiveData = try readImportedFileData(from: zipURL)
        let entries = try SettingsArchiveFileDocument.archiveEntries(from: archiveData)
        return fullArchiveStructure(in: entries).isFullArchive
    }

    private func selectedScreenConfigURLsByName(from urls: [URL]) -> [String: URL] {
        var configURLsByName: [String: URL] = [:]

        for url in urls {
            let fileName = url.lastPathComponent
            guard fileName.lowercased().hasSuffix(".config.json") else {
                continue
            }

            configURLsByName[fileName.lowercased()] = url
        }

        return configURLsByName
    }

    private func existingConfigFileNames() -> Set<String> {
        guard let directoryURL = currentDocumentsDirectoryURL else {
            return []
        }

        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return Set(urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true,
                  isScreenConfigFileName(url.lastPathComponent) else {
                return nil
            }

            return url.lastPathComponent.lowercased()
        })
    }

    private func extractScreenPackageImport(from zipURL: URL) throws -> ScreenPackageImport {
        let archiveData = try readImportedFileData(from: zipURL)
        let entries = try SettingsArchiveFileDocument.archiveEntries(from: archiveData)
        guard let documentEntry = entries.first(where: { entry in
            guard let fileName = sanitizedArchiveFileName(entry.fileName) else {
                return false
            }

            return isScreenDocumentFileExtension(URL(fileURLWithPath: fileName).pathExtension)
        }),
              let documentFileName = sanitizedArchiveFileName(documentEntry.fileName) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: temporaryDirectoryURL,
                withIntermediateDirectories: true
            )

            let documentURL = temporaryDirectoryURL.appendingPathComponent(documentFileName)
            try documentEntry.data.write(to: documentURL, options: [.atomic])

            let matchingConfigFileName = configFileName(forDocumentName: documentFileName)
            let matchingConfigKey = matchingConfigFileName.lowercased()
            var configURL: URL?

            if let configEntry = entries.first(where: { entry in
                sanitizedArchiveFileName(entry.fileName)?.lowercased() == matchingConfigKey
            }) {
                let extractedConfigURL = temporaryDirectoryURL.appendingPathComponent(matchingConfigFileName)
                try configEntry.data.write(to: extractedConfigURL, options: [.atomic])
                configURL = extractedConfigURL
            }

            return ScreenPackageImport(
                documentURL: documentURL,
                configURL: configURL,
                temporaryDirectoryURL: temporaryDirectoryURL
            )
        } catch {
            db("IMPORT_TRACE screen_package_extraction_failed error=\(error.localizedDescription)")
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
            throw error
        }
    }

    private func extractFullArchiveImport(from zipURL: URL) throws -> FullArchiveImport {
        guard let archiveImport = try extractFullArchiveImportIfPresent(from: zipURL) else {
            db("IMPORT_TRACE zip_classification=invalid_archive reason=missing_full_archive_structure")
            throw CocoaError(.fileReadCorruptFile)
        }

        return archiveImport
    }

    private func extractFullArchiveImportIfPresent(from zipURL: URL) throws -> FullArchiveImport? {
        let archiveData = try readImportedFileData(from: zipURL)
        let entries = try SettingsArchiveFileDocument.archiveEntries(from: archiveData)
        let archiveStructure = fullArchiveStructure(in: entries)

        guard archiveStructure.isFullArchive else {
            return nil
        }

        let temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: temporaryDirectoryURL,
                withIntermediateDirectories: true
            )

            let classification = try classifyFullArchiveEntries(entries, temporaryDirectoryURL: temporaryDirectoryURL)
            return FullArchiveImport(
                fileURLs: classification.fileURLs,
                configURLsByName: classification.configURLsByName,
                templatePairs: classification.templatePairs,
                temporaryDirectoryURL: temporaryDirectoryURL
            )
        } catch {
            db("IMPORT_TRACE full_archive_extraction_failed error=\(error.localizedDescription)")
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
            throw error
        }
    }

    private func classifyFullArchiveEntries(
        _ entries: [SettingsArchiveFileDocument.ArchiveEntry],
        temporaryDirectoryURL: URL
    ) throws -> FullArchiveEntryClassification {
        var seenFileNameKeys: Set<String> = []
        var configURLsByName: [String: URL] = [:]
        var configURLs: [URL] = []
        var screenURLs: [URL] = []
        var textURLs: [URL] = []
        var imageURLs: [URL] = []
        var soundURLs: [URL] = []
        var pdfURLs: [URL] = []
        var templateDocumentsByKey: [String: (fileName: String, data: Data)] = [:]
        var templateConfigurationsByTemplateKey: [String: Data] = [:]

        for entry in entries {
            guard entry.fileName != "Archive.json" else {
                continue
            }

            let plan = try fullArchiveEntryPlan(for: entry)
            guard !seenFileNameKeys.contains(plan.fileNameKey) else {
                throw RestoreArchiveValidationError.duplicateDestinationFilename(plan.fileName)
            }
            seenFileNameKeys.insert(plan.fileNameKey)

            switch plan.contentKind {
            case .templateDocument:
                templateDocumentsByKey[templateFileNameCollisionKey(plan.fileName)] = (
                    fileName: plan.fileName,
                    data: plan.entry.data
                )
                continue
            case .templateConfiguration:
                let templateFileName = String(plan.fileName.dropLast(".config.json".count))
                templateConfigurationsByTemplateKey[templateFileNameCollisionKey(templateFileName)] = plan.entry.data
                continue
            default:
                break
            }

            let extractedURL = temporaryDirectoryURL.appendingPathComponent(plan.fileName)
            try plan.entry.data.write(to: extractedURL, options: [.atomic])

            switch plan.contentKind {
            case .config:
                configURLsByName[plan.fileNameKey] = extractedURL
                configURLs.append(extractedURL)
            case .document:
                screenURLs.append(extractedURL)
            case .text:
                textURLs.append(extractedURL)
            case .image:
                imageURLs.append(extractedURL)
            case .sound:
                soundURLs.append(extractedURL)
            case .pdf:
                pdfURLs.append(extractedURL)
            case .templateDocument, .templateConfiguration:
                break
            }
        }

        if let orphanedConfigurationKey = templateConfigurationsByTemplateKey.keys.first(where: {
            templateDocumentsByKey[$0] == nil
        }) {
            let orphanedFileName = entries.first(where: { entry in
                guard entry.fileName.hasPrefix("templates/") else { return false }
                let fileName = String(entry.fileName.dropFirst("templates/".count))
                guard isTemplateConfigurationURL(URL(fileURLWithPath: fileName)) else { return false }
                let templateFileName = String(fileName.dropLast(".config.json".count))
                return templateFileNameCollisionKey(templateFileName) == orphanedConfigurationKey
            })?.fileName ?? orphanedConfigurationKey
            throw RestoreArchiveValidationError.orphanedTemplateConfiguration(orphanedFileName)
        }

        let templatePairs = templateDocumentsByKey
            .map { key, document in
                TemplateArchiveRestorePair(
                    templateFileName: document.fileName,
                    templateData: document.data,
                    configurationData: templateConfigurationsByTemplateKey[key]
                )
            }
            .sorted {
                $0.templateFileName.localizedCaseInsensitiveCompare($1.templateFileName) == .orderedAscending
            }

        return FullArchiveEntryClassification(
            fileURLs: configURLs + screenURLs + textURLs + imageURLs + soundURLs + pdfURLs,
            configURLsByName: configURLsByName,
            templatePairs: templatePairs
        )
    }

    private func fullArchiveEntryPlan(for entry: SettingsArchiveFileDocument.ArchiveEntry) throws -> FullArchiveEntryPlan {
        let components = entry.fileName.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard components.count == 2 else {
            throw RestoreArchiveValidationError.invalidArchivePath(entry.fileName)
        }

        let folderName = components[0]
        guard let fileName = sanitizedArchiveFileName(components[1]) else {
            throw RestoreArchiveValidationError.invalidArchivePath(entry.fileName)
        }

        if folderName == "templates" {
            guard entry.fileName == "templates/\(fileName)",
                  !entry.fileName.contains("\\") else {
                throw RestoreArchiveValidationError.invalidArchivePath(entry.fileName)
            }
        }

        let pathExtension = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        let contentKind: ImportedContentKind

        switch folderName {
        case "Configs" where isScreenConfigFileName(fileName):
            do {
                _ = try JSONDecoder().decode(ScreenConfig.self, from: entry.data)
            } catch {
                throw RestoreArchiveValidationError.invalidScreenConfiguration(fileName)
            }
            contentKind = .config
        case "Screens" where isScreenDocumentFileExtension(pathExtension):
            contentKind = .document
        case "Text" where pathExtension == legacyScreenDocumentFileExtension:
            contentKind = .text
        case "Images" where supportedImportedImageExtensions.contains(pathExtension):
            contentKind = .image
        case "Sounds" where supportedImportedSoundExtensions.contains(pathExtension):
            contentKind = .sound
        case "PDFs" where supportedImportedPDFExtensions.contains(pathExtension):
            contentKind = .pdf
        case "templates" where isValidTemplateArchiveDocumentFileName(fileName):
            contentKind = .templateDocument
        case "templates" where isValidTemplateArchiveConfigurationFileName(fileName):
            contentKind = .templateConfiguration
        default:
            throw RestoreArchiveValidationError.unsupportedArchiveEntry(entry.fileName)
        }

        let fileNameKey: String
        switch contentKind {
        case .templateDocument, .templateConfiguration:
            fileNameKey = templateFileNameCollisionKey(fileName)
        default:
            fileNameKey = fileName.lowercased()
        }

        return FullArchiveEntryPlan(
            entry: entry,
            folderName: folderName,
            fileName: fileName,
            contentKind: contentKind,
            fileNameKey: fileNameKey
        )
    }

    private func isValidTemplateArchiveDocumentFileName(_ fileName: String) -> Bool {
        guard isTemplateDocumentFileName(fileName),
              URL(fileURLWithPath: fileName).lastPathComponent == fileName else {
            return false
        }
        guard let normalizedFileName = try? normalizedTemplateDocumentFileName(from: fileName) else {
            return false
        }
        return templateFileNameCollisionKey(normalizedFileName) == templateFileNameCollisionKey(fileName)
    }

    private func isValidTemplateArchiveConfigurationFileName(_ fileName: String) -> Bool {
        guard isTemplateConfigurationURL(URL(fileURLWithPath: fileName)),
              fileName.lowercased().hasSuffix(".config.json") else {
            return false
        }
        let templateFileName = String(fileName.dropLast(".config.json".count))
        return isValidTemplateArchiveDocumentFileName(templateFileName) &&
            fileName == templateConfigFileName(forTemplateDocumentName: templateFileName)
    }

    private func fullArchiveStructure(
        in entries: [SettingsArchiveFileDocument.ArchiveEntry]
    ) -> (
        hasManifest: Bool,
        hasScreensFolder: Bool,
        hasConfigsFolder: Bool,
        hasTextFolder: Bool,
        hasImagesFolder: Bool,
        hasSoundsFolder: Bool,
        hasPDFsFolder: Bool,
        hasTemplatesFolder: Bool,
        isFullArchive: Bool
    ) {
        let hasManifest = entries.contains { $0.fileName == "Archive.json" }
        let hasScreensFolder = entries.contains { $0.fileName.hasPrefix("Screens/") }
        let hasConfigsFolder = entries.contains { $0.fileName.hasPrefix("Configs/") }
        let hasTextFolder = entries.contains { $0.fileName.hasPrefix("Text/") }
        let hasImagesFolder = entries.contains { $0.fileName.hasPrefix("Images/") }
        let hasSoundsFolder = entries.contains { $0.fileName.hasPrefix("Sounds/") }
        let hasPDFsFolder = entries.contains { $0.fileName.hasPrefix("PDFs/") }
        let hasTemplatesFolder = entries.contains { $0.fileName.hasPrefix("templates/") }
        let hasArchiveContentFolder = hasScreensFolder ||
            hasConfigsFolder ||
            hasTextFolder ||
            hasImagesFolder ||
            hasSoundsFolder ||
            hasPDFsFolder ||
            hasTemplatesFolder

        return (
            hasManifest: hasManifest,
            hasScreensFolder: hasScreensFolder,
            hasConfigsFolder: hasConfigsFolder,
            hasTextFolder: hasTextFolder,
            hasImagesFolder: hasImagesFolder,
            hasSoundsFolder: hasSoundsFolder,
            hasPDFsFolder: hasPDFsFolder,
            hasTemplatesFolder: hasTemplatesFolder,
            isFullArchive: hasManifest && hasArchiveContentFolder
        )
    }

    private func sanitizedArchiveFileName(_ fileName: String) -> String? {
        let lastPathComponent = URL(fileURLWithPath: fileName).lastPathComponent
        guard !lastPathComponent.isEmpty,
              lastPathComponent != ".",
              lastPathComponent != ".." else {
            return nil
        }

        return lastPathComponent
    }

    private func ensureImportedScreenConfig(
        for documentURL: URL,
        session: PendingImportSession,
        replacingDocument: Bool
    ) {
        let fileManager = FileManager.default
        let targetConfigURL = configURL(forDocumentURL: documentURL)
        let targetConfigKey = targetConfigURL.lastPathComponent.lowercased()

        if session.importMode == .allFiles,
           session.skipFileNameKeys.contains(targetConfigKey) {
            return
        }

        if session.importMode == .allFiles,
           replacingDocument,
           fileManager.fileExists(atPath: targetConfigURL.path),
           loadScreenConfig(for: documentURL) != nil {
            return
        }

        let matchingConfigFileName = configFileName(forDocumentName: documentURL.lastPathComponent).lowercased()

        if session.importMode == .allFiles,
           let sourceConfigURL = session.selectedConfigURLsByName[matchingConfigFileName] {
            do {
                if fileManager.fileExists(atPath: targetConfigURL.path) {
                    try safelyReplaceExistingScreenConfig(from: sourceConfigURL, to: targetConfigURL)
                } else {
                    try importValidScreenConfig(from: sourceConfigURL, to: targetConfigURL)
                }

                if loadScreenConfig(for: documentURL) != nil {
                    return
                }
            } catch {
                db("Failed to import screen config \(sourceConfigURL.lastPathComponent): \(error.localizedDescription)")
                return
            }
        }

        if session.importMode == .allFiles {
            createDefaultScreenConfigIfNeeded(for: documentURL)
            return
        }

        if fileManager.fileExists(atPath: targetConfigURL.path) {
            if replacingDocument {
                try? fileManager.removeItem(at: targetConfigURL)
            } else {
                if loadScreenConfig(for: documentURL) != nil {
                    return
                }

                try? fileManager.removeItem(at: targetConfigURL)
            }
        }

        if let sourceConfigURL = session.selectedConfigURLsByName[matchingConfigFileName] {
            do {
                if fileManager.fileExists(atPath: targetConfigURL.path) {
                    try fileManager.removeItem(at: targetConfigURL)
                }

                try importFileData(from: sourceConfigURL, to: targetConfigURL)

                if loadScreenConfig(for: documentURL) != nil {
                    return
                }

                try? fileManager.removeItem(at: targetConfigURL)
            } catch {
                db("Failed to import screen config \(sourceConfigURL.lastPathComponent): \(error.localizedDescription)")
                try? fileManager.removeItem(at: targetConfigURL)
            }
        }

        createDefaultScreenConfigIfNeeded(for: documentURL)
    }

    private func createDefaultScreenConfigIfNeeded(for documentURL: URL) {
        guard loadScreenConfig(for: documentURL) == nil else {
            return
        }

        let requiredBoxCount = requiredBoxCountForImportedDocument(at: documentURL)
        _ = ensureScreenConfigFile(for: documentURL, requiredBoxCount: requiredBoxCount)
    }

    private func importValidScreenConfig(from sourceURL: URL, to targetURL: URL) throws {
        try importFileData(from: sourceURL, to: targetURL)
        let data = try Data(contentsOf: targetURL)

        do {
            _ = try JSONDecoder().decode(ScreenConfig.self, from: data)
        } catch {
            try? FileManager.default.removeItem(at: targetURL)
            throw error
        }
    }

    private func safelyReplaceExistingScreenConfig(from sourceURL: URL, to targetURL: URL) throws {
        let configData = try readImportedFileData(from: sourceURL)
        _ = try JSONDecoder().decode(ScreenConfig.self, from: configData)
        try safelyReplaceExistingImportedFile(from: sourceURL, to: targetURL)
    }

    private func isScreenConfigFileName(_ fileName: String) -> Bool {
        fileName.lowercased().hasSuffix(".config.json")
    }

    private func uniqueImportTargetURL(for preferredTargetURL: URL, session: PendingImportSession) -> URL {
        let directoryURL = preferredTargetURL.deletingLastPathComponent()
        let fileName = preferredTargetURL.lastPathComponent
        let baseName: String
        let suffix: String

        if isScreenConfigFileName(fileName) {
            baseName = String(fileName.dropLast(".config.json".count))
            suffix = ".config.json"
        } else {
            baseName = preferredTargetURL.deletingPathExtension().lastPathComponent
            suffix = ".\(preferredTargetURL.pathExtension)"
        }

        var index = 2
        while true {
            let candidateFileName = "\(baseName) \(index)\(suffix)"
            let candidateURL = directoryURL.appendingPathComponent(candidateFileName)
            let candidateKey = candidateFileName.lowercased()

            if !FileManager.default.fileExists(atPath: candidateURL.path),
               !session.existingFileNames.contains(candidateKey),
               !session.existingTextNames.contains(candidateKey),
               !session.existingConfigNames.contains(candidateKey),
               !session.existingImageNames.contains(candidateKey),
               !session.existingSoundNames.contains(candidateKey),
               !session.existingPDFNames.contains(candidateKey) {
                return candidateURL
            }

            index += 1
        }
    }

    private func requiredBoxCountForImportedDocument(at documentURL: URL) -> Int {
        guard let contents = try? String(contentsOf: documentURL, encoding: .utf8) else {
            return 1
        }

        return requiredBoxCountForDocumentText(contents)
    }

    private func requiredBoxCountForDocumentText(_ contents: String) -> Int {
        let slotLines = contents
            .components(separatedBy: CharacterSet.newlines.union(.init(charactersIn: "\t")))
            .filter { line in
                let normalizedLine = line.replacingOccurrences(of: "\r", with: "")
                let trimmedLine = normalizedLine.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmedLine.isEmpty && !trimmedLine.hasPrefix("//")
            }

        return min(max(slotLines.count, 1), maxFunctionKeyCount)
    }

    private func handleDocumentImport(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result else {
            if case let .failure(error) = result {
                renameAlertMessage = error.localizedDescription
            }
            return
        }

        guard let directoryURL = currentDocumentsDirectoryURL else {
            renameAlertMessage = "Couldn't access the documents folder."
            return
        }

        var existingFileNames = Set(availableDocumentURLs.map { $0.lastPathComponent.lowercased() })
        var duplicateFileNames: [String] = []

        for sourceURL in urls {
            guard isScreenDocumentURL(sourceURL) else {
                renameAlertMessage = "Only screen document files can be imported."
                return
            }

            let targetFileName = sourceURL.lastPathComponent
            let targetURL = directoryURL.appendingPathComponent(targetFileName)

            if existingFileNames.contains(targetFileName.lowercased()) {
                duplicateFileNames.append(targetFileName)
                continue
            }

            do {
                try importFileData(from: sourceURL, to: targetURL)
                existingFileNames.insert(targetFileName.lowercased())
            } catch {
                renameAlertMessage = "Couldn't import the file: \(error.localizedDescription)"
                return
            }
        }

        markImportedContentChanged()

        if let firstImportedURL = urls.first(where: { !duplicateFileNames.contains($0.lastPathComponent) }) {
            loadFunctionKeys(directoryURL.appendingPathComponent(firstImportedURL.lastPathComponent))
        }

        if let duplicateFileName = duplicateFileNames.first {
            renameAlertMessage = duplicateFileNames.count == 1
                ? "a file with that name already exists."
                : "Some files were skipped because they already exist. First skipped: \(duplicateFileName)"
        }
    }

    private func handleImageImport(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result else {
            if case let .failure(error) = result {
                renameAlertMessage = error.localizedDescription
            }
            return
        }

        guard let directoryURL = currentDocumentsDirectoryURL else {
            renameAlertMessage = "Couldn't access the documents folder."
            return
        }

        var existingImageNames = Set(availableImageURLs.map { $0.lastPathComponent.lowercased() })
        var duplicateImageNames: [String] = []

        for sourceURL in urls {
            guard supportedImportedImageExtensions.contains(sourceURL.pathExtension.lowercased()) else {
                renameAlertMessage = "Only supported image files can be imported."
                return
            }

            let targetFileName = sourceURL.lastPathComponent
            let targetURL = directoryURL.appendingPathComponent(targetFileName)

            if existingImageNames.contains(targetFileName.lowercased()) {
                duplicateImageNames.append(targetFileName)
                continue
            }

            do {
                if FileManager.default.fileExists(atPath: targetURL.path) {
                    duplicateImageNames.append(targetFileName)
                    continue
                }
                try importFileData(from: sourceURL, to: targetURL)
                existingImageNames.insert(targetFileName.lowercased())
            } catch {
                renameAlertMessage = "Couldn't import the image: \(error.localizedDescription)"
                return
            }
        }

        if !availableImageURLs.isEmpty {
            let previousImageURL = selectedImageURL
            markImportedContentChanged()
            if let previousImageURL,
               let refreshedImageIndex = availableImageURLs.firstIndex(where: { $0.lastPathComponent == previousImageURL.lastPathComponent }) {
                persistSelectedImage(availableImageURLs[refreshedImageIndex])
            }
        } else {
            markImportedContentChanged()
        }

        if let duplicateImageName = duplicateImageNames.first {
            renameAlertMessage = duplicateImageNames.count == 1
                ? "a file with that name already exists."
                : "Some images were skipped because they already exist. First skipped: \(duplicateImageName)"
        }
    }

    private func handleSoundImport(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result else {
            if case let .failure(error) = result {
                renameAlertMessage = error.localizedDescription
            }
            return
        }

        guard let directoryURL = currentDocumentsDirectoryURL else {
            renameAlertMessage = "Couldn't access the documents folder."
            return
        }

        var existingSoundNames = Set(availableSoundURLs.map { $0.lastPathComponent.lowercased() })
        var duplicateSoundNames: [String] = []

        for sourceURL in urls {
            guard supportedImportedSoundExtensions.contains(sourceURL.pathExtension.lowercased()) else {
                renameAlertMessage = "Only supported sound files can be imported."
                return
            }

            let targetFileName = sourceURL.lastPathComponent
            let targetURL = directoryURL.appendingPathComponent(targetFileName)

            if existingSoundNames.contains(targetFileName.lowercased()) {
                duplicateSoundNames.append(targetFileName)
                continue
            }

            do {
                if FileManager.default.fileExists(atPath: targetURL.path) {
                    duplicateSoundNames.append(targetFileName)
                    continue
                }
                try importFileData(from: sourceURL, to: targetURL)
                existingSoundNames.insert(targetFileName.lowercased())
            } catch {
                renameAlertMessage = "Couldn't import the sound: \(error.localizedDescription)"
                return
            }
        }

        markImportedContentChanged()

        if let firstImportedURL = urls.first(where: { !duplicateSoundNames.contains($0.lastPathComponent) }) {
            persistSelectedSound(directoryURL.appendingPathComponent(firstImportedURL.lastPathComponent))
        }

        if let duplicateSoundName = duplicateSoundNames.first {
            renameAlertMessage = duplicateSoundNames.count == 1
                ? "a file with that name already exists."
                : "Some sounds were skipped because they already exist. First skipped: \(duplicateSoundName)"
        }
    }

    private func nextAvailableNewDocumentURL() -> URL? {
        guard let directoryURL = currentDocumentsDirectoryURL else {
            return nil
        }

        let fileExtension = screenDocumentFileExtension
        var candidateName = "new.\(fileExtension)"
        var suffix = 0

        while true {
            let candidateURL = directoryURL.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }

            suffix += 1
            candidateName = "new_\(suffix).\(fileExtension)"
        }
    }

    var currentDocumentsDirectoryURL: URL? {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    private func markImportedContentChanged() {
        refreshDocumentFiles()
        importRefreshID = UUID()
    }

    private func markDeletedAllDataChanged() {
        refreshDocumentFilesAfterDeletingAllData()
        importRefreshID = UUID()
    }

    private func readImportedFileData(from sourceURL: URL) throws -> Data {
        let didAccessSecurityScopedResource = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScopedResource {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let coordinator = NSFileCoordinator()
        var importedData: Data?
        var importError: Error?
        var coordinatorError: NSError?

        coordinator.coordinate(readingItemAt: sourceURL, options: [], error: &coordinatorError) { coordinatedURL in
            do {
                importedData = try Data(contentsOf: coordinatedURL)
            } catch {
                importError = error
            }
        }

        if let importError {
            throw importError
        }

        if let coordinatorError {
            throw coordinatorError
        }

        guard let importedData else {
            throw CocoaError(.fileReadUnknown)
        }

        return importedData
    }

    private func safelyReplaceExistingImportedFile(from sourceURL: URL, to targetURL: URL) throws {
        let fileManager = FileManager.default
        let replacementDirectoryURL = try fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: targetURL,
            create: true
        )
        defer {
            try? fileManager.removeItem(at: replacementDirectoryURL)
        }

        let stagedURL = replacementDirectoryURL
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(targetURL.pathExtension)

        let expectedFileSize = try stageImportedFileData(from: sourceURL, to: stagedURL)
        try verifyStagedReplacement(at: stagedURL, expectedFileSize: expectedFileSize)

        do {
            _ = try fileManager.replaceItemAt(
                targetURL,
                withItemAt: stagedURL,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
        } catch {
            let nsError = error as NSError
            if let recoveryURL = nsError.userInfo["NSFileOriginalItemLocationKey"] as? URL {
                db("IMPORT_TRACE replacement_failed original_recovery_location=\(recoveryURL.path)")
            } else if let recoveryURL = nsError.userInfo["NSFileOriginalItemLocationKey"] as? NSURL {
                db("IMPORT_TRACE replacement_failed original_recovery_location=\(recoveryURL.path ?? "")")
            }

            let destinationStillExists = fileManager.fileExists(atPath: targetURL.path)
            db("IMPORT_TRACE replacement_failed destination_exists=\(destinationStillExists) destination=\(targetURL.path) error=\(error.localizedDescription)")
            throw error
        }
    }

    private func stageImportedFileData(from sourceURL: URL, to stagedURL: URL) throws -> Int? {
        let didAccessSecurityScopedResource = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScopedResource {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let coordinator = NSFileCoordinator()
        var importError: Error?
        var coordinatorError: NSError?
        var expectedFileSize: Int?

        coordinator.coordinate(readingItemAt: sourceURL, options: [], error: &coordinatorError) { coordinatedURL in
            do {
                expectedFileSize = try? coordinatedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
                try FileManager.default.createDirectory(
                    at: stagedURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                do {
                    try FileManager.default.copyItem(at: coordinatedURL, to: stagedURL)
                } catch {
                    try? FileManager.default.removeItem(at: stagedURL)
                    let importedData = try Data(contentsOf: coordinatedURL)
                    try importedData.write(to: stagedURL, options: .atomic)
                }
            } catch {
                importError = error
            }
        }

        if let importError {
            throw importError
        }

        if let coordinatorError {
            throw coordinatorError
        }

        return expectedFileSize
    }

    private func verifyStagedReplacement(at stagedURL: URL, expectedFileSize: Int?) throws {
        let values = try stagedURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true,
              let stagedFileSize = values.fileSize else {
            throw CocoaError(.fileWriteUnknown)
        }

        if let expectedFileSize,
           stagedFileSize != expectedFileSize {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private func importFileData(from sourceURL: URL, to targetURL: URL) throws {
        let didAccessSecurityScopedResource = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScopedResource {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let coordinator = NSFileCoordinator()
        var importError: Error?
        var coordinatorError: NSError?

        coordinator.coordinate(readingItemAt: sourceURL, options: [], error: &coordinatorError) { coordinatedURL in
            do {
                try FileManager.default.createDirectory(
                    at: targetURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                let temporaryURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(targetURL.pathExtension)

                defer {
                    try? FileManager.default.removeItem(at: temporaryURL)
                }

                do {
                    try FileManager.default.copyItem(at: coordinatedURL, to: temporaryURL)
                } catch {
                    let importedData = try Data(contentsOf: coordinatedURL)
                    try importedData.write(to: temporaryURL, options: .atomic)
                }

                try FileManager.default.moveItem(at: temporaryURL, to: targetURL)
            } catch {
                db("IMPORT_TRACE copy_failure source=\(coordinatedURL.path) destination=\(targetURL.path) error=\(error.localizedDescription)")
                importError = error
            }
        }

        if let importError {
            db("IMPORT_TRACE copy_throwing source=\(sourceURL.path) destination=\(targetURL.path) error=\(importError.localizedDescription)")
            throw importError
        }

        if let coordinatorError {
            db("IMPORT_TRACE copy_coordinator_error source=\(sourceURL.path) destination=\(targetURL.path) error=\(coordinatorError.localizedDescription)")
            throw coordinatorError
        }
    }
	
    private var hasArchiveExportContent: Bool {
        !availableDocumentURLs.isEmpty ||
            !availableTextURLs.isEmpty ||
            !availableImageURLs.isEmpty ||
            !availableSoundURLs.isEmpty ||
            !availablePDFURLs.isEmpty ||
            !availableTemplateURLsForArchiveExport.isEmpty
    }

    private var availableTemplateURLsForArchiveExport: [URL] {
        guard let documentsDirectoryURL = currentDocumentsDirectoryURL else {
            return []
        }

        return discoverTemplateDocumentURLs(in: documentsDirectoryURL)
    }

    private var archiveExportType: UTType {
        UTType(filenameExtension: "zip") ?? .data
    }

    private func archiveExportDefaultFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMdd_HHmmss"
        return "ESP_\(formatter.string(from: Date())).zip"
    }

    private func makeFullArchiveData() throws -> Data {
        var entries: [SettingsArchiveFileDocument.ArchiveEntry] = [
            SettingsArchiveFileDocument.ArchiveEntry(
                fileName: "Archive.json",
                data: try archiveManifestData()
            )
        ]

        for screenURL in availableDocumentURLs {
            entries.append(
                SettingsArchiveFileDocument.ArchiveEntry(
                    fileName: "Screens/\(screenURL.lastPathComponent)",
                    data: try Data(contentsOf: screenURL)
                )
            )
            entries.append(
                SettingsArchiveFileDocument.ArchiveEntry(
                    fileName: "Configs/\(configFileName(forDocumentName: screenURL.lastPathComponent))",
                    data: try screenPackageConfigData(
                        for: screenURL,
                        documentFileName: screenURL.lastPathComponent
                    )
                )
            )
        }

        try appendArchiveEntries(
            from: availableTextURLs,
            folderName: "Text",
            to: &entries
        )
        try appendArchiveEntries(
            from: availableImageURLs,
            folderName: "Images",
            to: &entries
        )
        try appendArchiveEntries(
            from: availableSoundURLs,
            folderName: "Sounds",
            to: &entries
        )
        try appendArchiveEntries(
            from: availablePDFURLs,
            folderName: "PDFs",
            to: &entries
        )
        try appendTemplateArchiveEntries(to: &entries)

        return try SettingsArchiveFileDocument.makeArchiveData(with: entries)
    }

    private func appendTemplateArchiveEntries(
        to entries: inout [SettingsArchiveFileDocument.ArchiveEntry]
    ) throws {
        for templateURL in availableTemplateURLsForArchiveExport {
            entries.append(
                SettingsArchiveFileDocument.ArchiveEntry(
                    fileName: "templates/\(templateURL.lastPathComponent)",
                    data: try Data(contentsOf: templateURL)
                )
            )

            let configurationURL = templateConfigURL(forTemplateDocumentURL: templateURL)
            guard FileManager.default.fileExists(atPath: configurationURL.path) else {
                continue
            }

            let resourceValues = try configurationURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else {
                throw CocoaError(.fileReadUnknown)
            }

            entries.append(
                SettingsArchiveFileDocument.ArchiveEntry(
                    fileName: "templates/\(configurationURL.lastPathComponent)",
                    data: try Data(contentsOf: configurationURL)
                )
            )
        }
    }

    private func appendArchiveEntries(
        from fileURLs: [URL],
        folderName: String,
        to entries: inout [SettingsArchiveFileDocument.ArchiveEntry]
    ) throws {
        for fileURL in fileURLs {
            entries.append(
                SettingsArchiveFileDocument.ArchiveEntry(
                    fileName: "\(folderName)/\(fileURL.lastPathComponent)",
                    data: try Data(contentsOf: fileURL)
                )
            )
        }
    }

    private func archiveManifestData() throws -> Data {
        let manifest: [String: Any] = [
            "archiveFormatVersion": 1,
            "app": "ESP32BLE"
        ]
        return try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    private func sendKeyboardTimingCommand() {
        ble.sendKeyboardTiming(onMs: Int(keyboardTimingOnMs), offMs: Int(keyboardTimingOffMs))
    }

    private var resolvedTextToSpeechVoiceIdentifier: String {
        if availableSpeechVoices.contains(where: { $0.identifier == selectedTextToSpeechVoiceIdentifier }) {
            return selectedTextToSpeechVoiceIdentifier
        }

        if let defaultVoice = AVSpeechSynthesisVoice(language: Locale.current.identifier) {
            return defaultVoice.identifier
        }

        return availableSpeechVoices.first?.identifier ?? ""
    }

    private var selectedSpeechVoiceDisplayName: String {
        guard let selectedVoice = availableSpeechVoices.first(where: { $0.identifier == resolvedTextToSpeechVoiceIdentifier }) else {
            return "voice"
        }

        return selectedVoice.name
    }

    private func loadSpeechVoicesIfNeeded() {
        guard availableSpeechVoices.isEmpty else { return }

        let loadedVoices = AVSpeechSynthesisVoice.speechVoices()
            .map { voice in
                let localeName = Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language
                return SpeechVoiceOption(
                    identifier: voice.identifier,
                    localeIdentifier: voice.language,
                    languageCode: Locale(identifier: voice.language).language.languageCode?.identifier.lowercased() ?? "",
                    languageDisplayName: localeName,
                    name: voice.name,
                    menuTitle: "\(voice.name) (\(localeName))"
                )
            }

        availableSpeechVoices = orderedSpeechVoices(
            loadedVoices,
            selectedIdentifier: selectedTextToSpeechVoiceIdentifier
        )
    }

    private func orderedSpeechVoices(_ voices: [SpeechVoiceOption], selectedIdentifier: String) -> [SpeechVoiceOption] {
        let preferredVoices: [(name: String, localePrefix: String)] = [
            ("Eddy", "en-US"),
            ("Samantha", "en-US"),
            ("Daniel", "en-GB"),
            ("Shelley", "en-GB"),
            ("Karen", "en-AU"),
            ("Eddy", "ja-JP"),
            ("Kyoko", "ja-JP")
        ]

        let sortedVoices = voices.sorted { leftVoice, rightVoice in
            let leftPriority = preferredVoicePriority(for: leftVoice, preferredVoices: preferredVoices)
            let rightPriority = preferredVoicePriority(for: rightVoice, preferredVoices: preferredVoices)

            if leftPriority != rightPriority {
                return leftPriority < rightPriority
            }

            if leftPriority == preferredVoices.count {
                let languageComparison = leftVoice.languageDisplayName.localizedCaseInsensitiveCompare(rightVoice.languageDisplayName)
                if languageComparison != .orderedSame {
                    return languageComparison == .orderedAscending
                }
            }

            let nameComparison = leftVoice.name.localizedCaseInsensitiveCompare(rightVoice.name)
            if nameComparison != .orderedSame {
                return nameComparison == .orderedAscending
            }

            return leftVoice.menuTitle.localizedCaseInsensitiveCompare(rightVoice.menuTitle) == .orderedAscending
        }

        guard let selectedIndex = sortedVoices.firstIndex(where: { $0.identifier == selectedIdentifier }) else {
            return sortedVoices
        }

        var reorderedVoices = sortedVoices
        let selectedVoice = reorderedVoices.remove(at: selectedIndex)
        reorderedVoices.insert(selectedVoice, at: 0)
        return reorderedVoices
    }

    private func preferredVoicePriority(
        for voice: SpeechVoiceOption,
        preferredVoices: [(name: String, localePrefix: String)]
    ) -> Int {
        preferredVoices.firstIndex { preferredVoice in
            voice.name.caseInsensitiveCompare(preferredVoice.name) == .orderedSame &&
                voice.localeIdentifier.lowercased().hasPrefix(preferredVoice.localePrefix.lowercased())
        } ?? preferredVoices.count
    }

    private func previewSpeechVoice(_ voice: SpeechVoiceOption) {
        speechSynthesizer.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: "\(voice.name). \(voice.languageDisplayName)")
        utterance.voice = AVSpeechSynthesisVoice(identifier: voice.identifier)
        utterance.rate = Float(clampedTextToSpeechRate)
        speechSynthesizer.speak(utterance)
    }

    private func previewCurrentSpeechVoice() {
        guard let voice = availableSpeechVoices.first(where: { $0.identifier == resolvedTextToSpeechVoiceIdentifier }) else {
            return
        }

        previewSpeechVoice(voice)
    }

    private var clampedTextToSpeechRate: Double {
        min(max(textToSpeechRate, minimumTextToSpeechRate), maximumTextToSpeechRate)
    }

    private var textToSpeechRateLabel: String {
        String(format: "%.1f", clampedTextToSpeechPercentage / 100)
    }

    private var speechRatePercentageBinding: Binding<Double> {
        Binding(
            get: { clampedTextToSpeechPercentage },
            set: { newValue in
                let snappedPercentage = (newValue / textToSpeechPercentageStep).rounded() * textToSpeechPercentageStep
                textToSpeechRate = defaultTextToSpeechRate * min(max(snappedPercentage, minimumTextToSpeechPercentage), maximumTextToSpeechPercentage) / 100
            }
        )
    }

    private var clampedTextToSpeechPercentage: Double {
        let rawPercentage = (clampedTextToSpeechRate / defaultTextToSpeechRate) * 100
        let snappedPercentage = (rawPercentage / textToSpeechPercentageStep).rounded() * textToSpeechPercentageStep
        return min(max(snappedPercentage, minimumTextToSpeechPercentage), maximumTextToSpeechPercentage)
    }

    private var minimumTextToSpeechRate: Double {
        defaultTextToSpeechRate * minimumTextToSpeechPercentage / 100
    }

    private var maximumTextToSpeechRate: Double {
        defaultTextToSpeechRate * maximumTextToSpeechPercentage / 100
    }

}

private struct SpeechVoiceOption: Identifiable, Equatable {
    let identifier: String
    let localeIdentifier: String
    let languageCode: String
    let languageDisplayName: String
    let name: String
    let menuTitle: String

    var id: String { identifier }
}

private let settingsFullBackupImportRejectedMessage = """
This ZIP contains a full backup, including screens, images, sounds, text files and PDFs.

Import Screen(s) only accepts individual .screen files or ZIP packages containing screens and their configurations.

To import this backup, select Restore Full Backup from the Import menu.
"""

private let settingsUnsupportedFullBackupZIPMessage = """
This ZIP archive uses a compression format or ZIP feature that ESP cannot read.

ESP currently supports ZIP archives created by its own Export Backup function.

To restore a full backup, please use a ZIP file previously exported by ESP.
"""

private let settingsUnsupportedScreenZIPMessage = """
This ZIP archive uses a compression format or ZIP feature that ESP cannot read.

ESP currently supports screen ZIP archives created by its own Export function.
"""

private struct SettingsRenameAlertModifier: ViewModifier {
    @Binding var message: String?
    let isPresented: Binding<Bool>

    private var alertTitle: String {
        if message == settingsFullBackupImportRejectedMessage {
            return "Full Backup Detected"
        }

        if message == settingsUnsupportedFullBackupZIPMessage ||
            message == settingsUnsupportedScreenZIPMessage {
            return "Unsupported ZIP Format"
        }

        return "Alert"
    }

    private var dismissButtonTitle: String {
        message == settingsFullBackupImportRejectedMessage ? "Dismiss" : "OK"
    }

    func body(content: Content) -> some View {
        content.alert(alertTitle, isPresented: isPresented) {
            Button(dismissButtonTitle, role: .cancel) {
                message = nil
            }
        } message: {
            Text(message ?? "")
        }
    }
}

private struct DeleteAllDataConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let deleteAllData: () -> Void

    func body(content: Content) -> some View {
        content.alert("Delete All Data?", isPresented: $isPresented) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) {
                deleteAllData()
            }
        } message: {
            Text("This will permanently delete all ESP32 screen files, configs, text files, images, sounds, and PDFs.\n\nTHIS CANNOT BE UNDONE.")
        }
    }
}

private struct RestoreAllFilesConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let restoreAllFiles: () -> Void

    func body(content: Content) -> some View {
        content.alert("Restore All Files?", isPresented: $isPresented) {
            Button("Cancel", role: .cancel) { }
            Button("Restore") {
                restoreAllFiles()
            }
        } message: {
            Text("This will restore all files from the backup archive.\n\nExisting files with the same name will be replaced.")
        }
    }
}

private extension VerticalAlignment {
    private enum SliderTrackCenterAlignment: AlignmentID {
        static func defaultValue(in dimensions: ViewDimensions) -> CGFloat {
            dimensions[VerticalAlignment.center]
        }
    }

    static let sliderTrackCenter = VerticalAlignment(SliderTrackCenterAlignment.self)
}

private struct ESPHelpView: View {
    let onClose: () -> Void
    @State private var path: [ESPHelpDestination] = []

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            NavigationStack(path: $path) {
                ESPHelpContentsView(onClose: onClose)
                    .navigationDestination(for: ESPHelpDestination.self) { destination in
                        switch destination {
                        case .topic(let topic):
                            ESPHelpTopicPager(
                                initialTopic: topic,
                                onHome: { path = [] },
                                onClose: onClose
                            )

                        case .completeUserManual:
                            ESPHelpUserManualView(
                                onHome: { path = [] },
                                onClose: onClose
                            )
                        }
                    }
                    .toolbar(.hidden, for: .navigationBar)
            }
            .onAppear {
                path = []
            }
        }
    }
}

private enum ESPHelpDestination: Hashable {
    case topic(ESPHelpTopic)
    case completeUserManual
}

private enum ESPHelpTopic: CaseIterable, Hashable, Identifiable {
    case connectToMac
    case connectToESP32BLE
    case usingESP
    case troubleshooting

    var id: Self { self }

    var title: String {
        switch self {
        case .connectToMac:
            "Connect to Mac"
        case .connectToESP32BLE:
            "Connect to ESP32BLE"
        case .usingESP:
            "Using ESP"
        case .troubleshooting:
            "Troubleshooting"
        }
    }

    var symbolName: String {
        switch self {
        case .connectToMac:
            "desktopcomputer"
        case .connectToESP32BLE:
            "antenna.radiowaves.left.and.right"
        case .usingESP:
            "hand.tap"
        case .troubleshooting:
            "wrench.and.screwdriver"
        }
    }

    var previous: ESPHelpTopic? {
        guard let index = Self.allCases.firstIndex(of: self), index > 0 else {
            return nil
        }

        return Self.allCases[index - 1]
    }

    var next: ESPHelpTopic? {
        guard let index = Self.allCases.firstIndex(of: self), index < Self.allCases.count - 1 else {
            return nil
        }

        return Self.allCases[index + 1]
    }
}

private struct ESPHelpContentsView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("ESP Help")
                .font(.title2.weight(.semibold))

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(ESPHelpTopic.allCases) { topic in
                        NavigationLink(value: ESPHelpDestination.topic(topic)) {
                            ESPHelpContentsRow(
                                title: topic.title,
                                symbolName: topic.symbolName
                            )
                        }

                        if topic != ESPHelpTopic.allCases.last {
                            Divider()
                        }
                    }

                    NavigationLink(value: ESPHelpDestination.completeUserManual) {
                        ESPHelpContentsRow(
                            title: "Complete User Manual",
                            symbolName: "book"
                        )
                    }
                }
            }

            ESPHelpNavigationBar(
                showsHome: false,
                showsTopicNavigation: false,
                onPrevious: nil,
                onNext: nil,
                onHome: nil,
                onClose: onClose,
                isTopicTransitioning: false
            )
        }
        .padding()
    }
}

private struct ESPHelpContentsRow: View {
    let title: String
    let symbolName: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .frame(width: 24)
                .foregroundStyle(Color.accentColor)

            Text(title)
                .foregroundStyle(.primary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 14)
        .contentShape(.rect)
    }
}

private enum ESPHelpTopicNavigationDirection {
    case previous
    case next
}

private struct ESPHelpTopicPager: View {
    let onHome: () -> Void
    let onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var currentTopic: ESPHelpTopic
    @State private var navigationDirection: ESPHelpTopicNavigationDirection = .next
    @State private var isTransitioning = false

    init(
        initialTopic: ESPHelpTopic,
        onHome: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.onHome = onHome
        self.onClose = onClose
        _currentTopic = State(initialValue: initialTopic)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ZStack {
                ESPHelpTopicView(topic: currentTopic)
                    .id(currentTopic)
                    .transition(topicTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .simultaneousGesture(
                DragGesture(minimumDistance: 24)
                    .onEnded(handleTopicSwipe)
            )

            ESPHelpNavigationBar(
                showsHome: true,
                showsTopicNavigation: true,
                onPrevious: currentTopic.previous.map { previousTopic in
                    { changeTopic(to: previousTopic, direction: .previous) }
                },
                onNext: currentTopic.next.map { nextTopic in
                    { changeTopic(to: nextTopic, direction: .next) }
                },
                onHome: onHome,
                onClose: onClose,
                isTopicTransitioning: isTransitioning
            )
        }
        .padding()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var topicTransition: AnyTransition {
        switch navigationDirection {
        case .previous:
            .asymmetric(
                insertion: .move(edge: .leading),
                removal: .move(edge: .trailing)
            )
        case .next:
            .asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading)
            )
        }
    }

    private func changeTopic(
        to topic: ESPHelpTopic,
        direction: ESPHelpTopicNavigationDirection
    ) {
        guard !isTransitioning, topic != currentTopic else {
            return
        }

        navigationDirection = direction

        guard !accessibilityReduceMotion else {
            currentTopic = topic
            return
        }

        isTransitioning = true
        withAnimation(
            .easeInOut(duration: 0.25),
            completionCriteria: .logicallyComplete
        ) {
            currentTopic = topic
        } completion: {
            isTransitioning = false
        }
    }

    private func handleTopicSwipe(_ value: DragGesture.Value) {
        let horizontalDistance = value.translation.width
        let verticalDistance = value.translation.height

        guard abs(horizontalDistance) > abs(verticalDistance), abs(horizontalDistance) >= 60 else {
            return
        }

        if horizontalDistance < 0, let nextTopic = currentTopic.next {
            changeTopic(to: nextTopic, direction: .next)
        } else if horizontalDistance > 0, let previousTopic = currentTopic.previous {
            changeTopic(to: previousTopic, direction: .previous)
        }
    }
}

private struct ESPHelpTopicView: View {
    let topic: ESPHelpTopic

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(topic.title)
                .font(.title2.weight(.semibold))

            ScrollView {
                Text("Help content will be added in Stage 2B.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ESPHelpUserManualView: View {
    let onHome: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Complete User Manual")
                .font(.title2.weight(.semibold))

            Text("The complete PDF user manual will be available online when ESP is released.")
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer()

            ESPHelpNavigationBar(
                showsHome: true,
                showsTopicNavigation: false,
                onPrevious: nil,
                onNext: nil,
                onHome: onHome,
                onClose: onClose,
                isTopicTransitioning: false
            )
        }
        .padding()
        .toolbar(.hidden, for: .navigationBar)
    }
}
// MARK: - BM:😎 HELP Navigation bar
private struct ESPHelpNavigationBar: View {
    let showsHome: Bool
    let showsTopicNavigation: Bool
    let onPrevious: (() -> Void)?
    let onNext: (() -> Void)?
    let onHome: (() -> Void)?
    let onClose: () -> Void
    let isTopicTransitioning: Bool

    var body: some View {
        HStack(spacing: 12) {
            if showsHome, let onHome {
                ESPHelpNavigationButton(
                    systemName: "house",
                    rotation: .zero,
                    accessibilityLabel: "Home",
                    isEnabled: !isTopicTransitioning,
                    action: onHome
                )
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
            }

            Spacer(minLength: 0)

            if showsTopicNavigation {
                HStack(spacing: 12) {
                    ESPHelpNavigationButton(
                        systemName: "triangle.fill",
                        rotation: .degrees(-90),
                        accessibilityLabel: "Previous",
                        isEnabled: onPrevious != nil && !isTopicTransitioning,
                        action: onPrevious ?? {}
                    )

                    ESPHelpNavigationButton(
                        systemName: "triangle.fill",
                        rotation: .degrees(90),
                        accessibilityLabel: "Next",
                        isEnabled: onNext != nil && !isTopicTransitioning,
                        action: onNext ?? {}
                    )
                }
            }

            Spacer(minLength: 0)

            ESPHelpNavigationButton(
                systemName: "checkmark",
                rotation: .zero,
                accessibilityLabel: "Close",
                isEnabled: true,
                action: onClose
            )
        }
        .frame(minHeight: 44)
    }
}

private struct ESPHelpNavigationButton: View {
    let systemName: String
    let rotation: Angle
    let accessibilityLabel: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .rotationEffect(rotation)
                .frame(width: 44, height: 44)
                .foregroundStyle(.primary)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(uiColor: .tertiarySystemFill))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                }
                .clipShape(.rect(cornerRadius: 6))
                .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .contentShape(.rect)
        .accessibilityLabel(accessibilityLabel)
        .disabled(!isEnabled)
    }
}

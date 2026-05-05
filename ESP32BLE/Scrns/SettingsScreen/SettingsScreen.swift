import SwiftUI
import UIKit
import AVFoundation
import UniformTypeIdentifiers

struct SettingsScreen: View {
    private enum SettingsListMode: String {
        case files
        case images
        case sounds
        case pdfs
        case all

        var buttonTitle: String {
            switch self {
            case .files:
                return "text"
            case .images:
                return "imgs"
            case .sounds:
                return "snds"
            case .pdfs:
                return "pdfs"
            case .all:
                return "all"
            }
        }

        mutating func toggle() {
            switch self {
            case .files:
                self = .images
            case .images:
                self = .sounds
            case .sounds:
                self = .pdfs
            case .pdfs:
                self = .all
            case .all:
                self = .files
            }
        }
    }

    private enum ImportedContentKind {
        case document
        case image
        case sound
        case pdf
    }

    private struct PendingImportConflict {
        let sourceURL: URL
        let targetURL: URL
        let fileName: String
        let contentKind: ImportedContentKind
    }

    private struct PendingImportSession {
        let directoryURL: URL
        let importListMode: SettingsListMode
        var remainingURLs: [URL]
        var existingFileNames: Set<String>
        var existingImageNames: Set<String>
        var existingSoundNames: Set<String>
        var existingPDFNames: Set<String>
        var firstImportedDocumentURL: URL?
        var firstImportedImageURL: URL?
        var firstImportedSoundURL: URL?
        var firstImportedPDFURL: URL?
        var importedAnything = false
    }

    private let ttsControlColor = Color(red: 0.0, green: 0.2, blue: 0.45)
    private let defaultTextToSpeechRate = Double(AVSpeechUtteranceDefaultSpeechRate)
    private let minimumTextToSpeechPercentage = 40.0
    private let maximumTextToSpeechPercentage = 140.0
    private let textToSpeechPercentageStep = 5.0
    private let maximumSpeechRecognitionAutoOffMinutes = 31
    @Environment(\.dismiss) private var dismiss
    @AppStorage("speechRecognitionAutoOffMinutes") private var speechRecognitionAutoOffMinutes = 5
    @AppStorage("sendControlABeforeText") var sendControlABeforeText = false
    @AppStorage("keyboardTimingOnMs") private var keyboardTimingOnMs = 0.0
    @AppStorage("keyboardTimingOffMs") private var keyboardTimingOffMs = 0.0
    @AppStorage("keepScreenAwake") private var keepScreenAwake = false
    private let timingLabelWidth = 90.0
    @ObservedObject var ble: BLEKeyboardManager
    let documentFiles: [URL]
    let selectedDocumentName: String
    let refreshDocumentFiles: () -> Void
    let loadFunctionKeys: (URL) -> Void
    let saveSelectedDocumentAndReload: (String) -> Void
    let renameDocument: (String) -> String?
    let deleteDocument: (URL) -> Void
    let duplicateDocument: (URL) -> Void
    let canDeleteDocuments: Bool
    @Binding var bleTextToSend: String
    @State private var documentEditorText = ""
    @State private var documentEditorFontSize: CGFloat = 18
    @State private var isLoadingDocumentText = false
    @State private var isDocumentEditorFocused = false
    @State private var speechSynthesizer = AVSpeechSynthesizer()
    @State private var soundPreviewPlayer: AVAudioPlayer?
    @State private var loadedDocumentName = ""
    @State private var savedDocumentEditorText = ""
    @State private var isEditingDocumentName = false
    @State private var documentNameDraft = ""
    @State private var renameAlertMessage: String?
    @AppStorage("settingsListMode") private var listModeRawValue = SettingsListMode.files.rawValue
    @AppStorage("settingsFilesScrollPositionID") private var fileScrollPositionIDStorage = ""
    @AppStorage("settingsImagesScrollPositionID") private var imageScrollPositionIDStorage = ""
    @AppStorage("settingsSoundsScrollPositionID") private var soundScrollPositionIDStorage = ""
    @AppStorage("settingsPDFsScrollPositionID") private var pdfScrollPositionIDStorage = ""
    @AppStorage("settingsAllScrollPositionID") private var allScrollPositionIDStorage = ""
    @State private var pendingImportListMode: SettingsListMode?
    @State private var pendingImportSession: PendingImportSession?
    @State private var pendingImportConflict: PendingImportConflict?
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
    @AppStorage(ButtonClickFeedback.preferenceKey) private var isButtonClickEnabled = true
    @FocusState var focusedField: SettingsFocusField?
    @FocusState private var isDocumentNameFieldFocused: Bool

    var body: some View {
        configuredSettingsScreen
    }

    private var settingsScreenBase: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    if isPad {
                        editableDocumentSection
                    }

                    if !isPad || !isDocumentEditorFocused {
                        combinedBottomPanelSection
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                documentTableSection
                    .frame(width: documentTableWidth(for: geometry.size.width))
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var configuredSettingsScreen: some View {
        settingsScreenBase
        .background(Color.black.ignoresSafeArea())
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
            }
        }
        .navigationTitle("")
        .toolbar {
            if isPad {
                ToolbarItem(placement: .topBarLeading) {
                    SettingsToolbarButton(title: "main", backgroundColor: Color.gray.opacity(0.45), minWidth: 92, isEnabled: true) {
                        saveAndReturnToMain()
                    }
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                textToSpeechVoiceMenu
            }
            ToolbarItem(placement: .topBarLeading) {
                textToSpeechRateControl
            }
            ToolbarItem(placement: .principal) {
                settingsTitleControl
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    ButtonClickFeedback.playIfEnabled()
                    guard listMode != .all else { return }
                    pendingImportListMode = listMode
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                .contentShape(.rect)
                .accessibilityLabel("Import \(listMode.buttonTitle) from iCloud")
                .disabled(listMode == .all)
                .opacity(listMode == .all ? 0.45 : 1)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Export Single File") {
                        ButtonClickFeedback.playIfEnabled()
                        prepareSingleFileExport()
                    }
                    Button("Export Archive.zip") {
                        ButtonClickFeedback.playIfEnabled()
                        prepareArchiveExport()
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                .contentShape(.rect)
                .accessibilityLabel("Export to iCloud")
            }
            ToolbarItem(placement: .topBarTrailing) {
                SettingsToolbarButton(title: listMode.buttonTitle, backgroundColor: Color.gray.opacity(0.45), minWidth: 92, isEnabled: true) {
                    listMode.toggle()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                SettingsToolbarButton(title: "new", backgroundColor: Color.green.opacity(0.5), minWidth: 64.4, isEnabled: listMode == .files) {
                    createNewDocument()
                }
            }
        }
        .onChange(of: ble.isConnected) {
            if ble.isConnected {
                sendKeyboardTimingCommand()
            }
        }
        .task {
            refreshDocumentFiles()
            loadSelectedDocumentText()
        }
        .onChange(of: documentFiles.map(\.path)) {
            loadSelectedDocumentText()
        }
        .onChange(of: selectedDocumentName) {
            saveCurrentDocumentText()
            loadSelectedDocumentText()
            cancelNameEditing()
        }
        .onChange(of: documentEditorText) {
            guard !isLoadingDocumentText else { return }
            saveCurrentDocumentText()
        }
        .onChange(of: isDocumentNameFieldFocused) {
            guard isEditingDocumentName, !isDocumentNameFieldFocused else { return }
            cancelNameEditing()
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
        .alert("Alert", isPresented: renameAlertIsPresented) {
            Button("OK", role: .cancel) {
                renameAlertMessage = nil
            }
        } message: {
            Text(renameAlertMessage ?? "")
        }
        .confirmationDialog(
            "a file with that name already exists.",
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
        .fileImporter(
            isPresented: isImporting,
            allowedContentTypes: activeImportContentTypes,
            allowsMultipleSelection: true
        ) { result in
            pendingImportListMode = nil
            handleImportedSelection(result)
        }
        .fileExporter(
            isPresented: $isExportingArchive,
            document: exportArchiveDocument,
            contentType: archiveExportType,
            defaultFilename: "Archive"
        ) { result in
            if case let .failure(error) = result {
                renameAlertMessage = error.localizedDescription
            }
            exportArchiveDocument = nil
        }
    }

    private var listMode: SettingsListMode {
        get { SettingsListMode(rawValue: listModeRawValue) ?? .files }
        nonmutating set { listModeRawValue = newValue.rawValue }
    }

    private var fileScrollPositionID: Binding<String?> {
        Binding(
            get: { fileScrollPositionIDStorage.isEmpty ? nil : fileScrollPositionIDStorage },
            set: { fileScrollPositionIDStorage = $0 ?? "" }
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

    private var settingsModeEditResetKey: String {
        "\(listModeRawValue)|\(selectedImagePath)|\(selectedSoundPath)|\(selectedPDFPath)"
    }

    private var isImporting: Binding<Bool> {
        Binding(
            get: { pendingImportListMode != nil },
            set: { _ in }
        )
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
        switch pendingImportListMode {
        case .files:
            return [.data]
        case .images:
            return [.image]
        case .sounds:
            return [.data]
        case .pdfs:
            return [.pdf]
        case .all:
            return [.data]
        case nil:
            return [.data]
        }
    }

    private func documentTableWidth(for availableWidth: CGFloat) -> CGFloat {
        let safeWidth = availableWidth.isFinite ? max(0, availableWidth) : 0
        let widthRatio = safeWidth > 900 ? 0.184 : 0.16
        let maximumWidth: CGFloat = safeWidth > 900 ? 260 : 220
        return min(max(safeWidth * widthRatio, 140), maximumWidth)
    }

    private var editableDocumentSection: some View {
        SettingsEditorSectionView(
            text: $documentEditorText,
            fontSize: $documentEditorFontSize,
            isFocused: $isDocumentEditorFocused,
            savedText: savedDocumentEditorText,
            onUndo: { documentEditorText = savedDocumentEditorText }
        )
    }

    private var settingsTitleControl: some View {
        Group {
            if isEditingDocumentName {
                TextField("", text: $documentNameDraft)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.center)
                    .frame(minWidth: 180)
                    .focused($isDocumentNameFieldFocused)
                    .onSubmit {
                        commitNameEdit()
                    }
            } else {
                Button(currentTitleDisplayName) {
                    guard canEditCurrentTitle else { return }
                    ButtonClickFeedback.playIfEnabled()
                    documentNameDraft = currentTitleDisplayName
                    isEditingDocumentName = true
                }
                .buttonStyle(.plain)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .disabled(!canEditCurrentTitle)
            }
        }
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
            .frame(minWidth: 60, minHeight: 44)
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
            keepScreenAwake: $keepScreenAwake,
            isButtonClickEnabled: $isButtonClickEnabled,
            opacitySliderValue: $opacitySliderValue,
            imageControlButtons: AnyView(imageControlButtons)
        )
    }

    private var imagePreviewSection: some View {
        SettingsImagePreviewPanel(
            imageURL: selectedImageURL,
            opacitySliderValue: opacitySliderValue
        )
    }

    private var imageControlButtons: some View {
        SettingsImageControlsSection(
            canGoPrevious: (selectedImagePosition ?? 0) > 0,
            canGoNext: (selectedImagePosition ?? 0) < maximumSelectableImageIndex,
            onReset: {
                persistSelectedImage(nil)
            },
            onRandom: {
                guard maximumSelectableImageIndex > 0 else { return }
                let randomIndex = Int.random(in: 0..<maximumSelectableImageIndex)
                persistSelectedImage(availableImageURLs[randomIndex])
            },
            onPrevious: {
                guard let selectedImagePosition, selectedImagePosition > 1 else {
                    persistSelectedImage(nil)
                    return
                }
                persistSelectedImage(availableImageURLs[selectedImagePosition - 2])
            },
            onNext: {
                let currentPosition = selectedImagePosition ?? 0
                guard currentPosition < maximumSelectableImageIndex else { return }
                persistSelectedImage(availableImageURLs[currentPosition])
            }
        )
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
        HStack(alignment: .top, spacing: 20) {
            availableDevicesContent
                .frame(maxWidth: .infinity, alignment: .topLeading)

            keyboardSettingsContent
                .frame(maxWidth: .infinity, alignment: .topLeading)
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
            selectedDocumentName: selectedDocumentName,
            imageURLs: availableImageURLs,
            selectedImageURL: selectedImageURL,
            soundURLs: availableSoundURLs,
            selectedSoundURL: selectedSoundURL,
            pdfURLs: availablePDFURLs,
            selectedPDFURL: selectedPDFURL,
            allFileURLs: availableAllFileURLs,
            fileScrollPositionID: fileScrollPositionID,
            imageScrollPositionID: imageScrollPositionID,
            soundScrollPositionID: soundScrollPositionID,
            pdfScrollPositionID: pdfScrollPositionID,
            allScrollPositionID: allScrollPositionID,
            canDeleteDocuments: canDeleteDocuments,
            imagePreviewSection: settingsTablePreviewSection,
            loadFunctionKeys: loadFunctionKeys,
            deleteDocument: deleteDocument,
            duplicateDocument: duplicateDocument,
            selectImage: selectImage,
            deleteImage: deleteImage,
            selectSound: selectSound,
            deleteSound: deleteSound,
            selectPDF: selectPDF,
            deletePDF: deletePDF
        )
        .id(importRefreshID)
    }

    private var settingsDocumentTableListMode: SettingsDocumentTableSection.ListMode {
        switch listMode {
        case .files:
            return .files
        case .images:
            return .images
        case .sounds:
            return .sounds
        case .pdfs:
            return .pdfs
        case .all:
            return .all
        }
    }

    private var settingsTablePreviewSection: AnyView {
        if listMode == .images {
            return AnyView(imagePreviewSection)
        }

        return AnyView(EmptyView())
    }

    private var customKeyboardTimingSection: some View {
        SettingsKeyboardTimingSection(
            timingLabelWidth: timingLabelWidth,
            keyboardTimingOnMs: $keyboardTimingOnMs,
            keyboardTimingOffMs: $keyboardTimingOffMs,
            speechRecognitionAutoOffMinutes: $speechRecognitionAutoOffMinutes,
            onSetAndTest: {
                sendKeyboardTimingCommand()
                ble.sendString("Hello World! Let's go. (test) 1!2\"3#4$5%6&7'8(9)")
            }
        )
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

        guard let fileURL = selectedDocumentFileURL else {
            documentEditorText = ""
            savedDocumentEditorText = ""
            loadedDocumentName = ""
            return
        }

        let loadedText = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        documentEditorText = loadedText
        savedDocumentEditorText = loadedText
        loadedDocumentName = fileURL.lastPathComponent
        documentNameDraft = currentTitleDisplayName
    }

    private func saveSelectedDocumentText() {
        guard let fileURL = selectedDocumentFileURL else {
            return
        }

        saveDocumentText(documentEditorText, to: fileURL)
    }

    private func saveCurrentDocumentText() {
        guard !loadedDocumentName.isEmpty,
              let fileURL = availableDocumentURLs.first(where: { $0.lastPathComponent == loadedDocumentName }) else {
            return
        }

        saveDocumentText(documentEditorText, to: fileURL)
    }

    private func saveCurrentDocumentText(_ text: String) {
        guard !loadedDocumentName.isEmpty,
              let fileURL = availableDocumentURLs.first(where: { $0.lastPathComponent == loadedDocumentName }) else {
            return
        }

        saveDocumentText(text, to: fileURL)
    }

    private func saveAndReturnToMain(using text: String? = nil) {
        if let text {
            documentEditorText = text
            saveSelectedDocumentAndReload(text)
        } else {
            saveSelectedDocumentAndReload(documentEditorText)
        }
        dismiss()
    }

    private func saveDocumentText(_ text: String, to fileURL: URL) {
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            savedDocumentEditorText = text
            loadedDocumentName = fileURL.lastPathComponent
        } catch {
            print("Failed to save document: \(fileURL.lastPathComponent)")
        }
    }

    private var selectedDocumentFileURL: URL? {
        availableDocumentURLs.first(where: { $0.lastPathComponent == selectedDocumentName })
    }

    private var availableDocumentURLs: [URL] {
        guard let directoryURL = currentDocumentsDirectoryURL else {
            return []
        }

        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                return values?.isRegularFile == true && url.pathExtension.lowercased() == "txt"
            }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    private var selectedDocumentDisplayName: String {
        URL(fileURLWithPath: selectedDocumentName).deletingPathExtension().lastPathComponent
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
        guard let directoryURL = currentDocumentsDirectoryURL else {
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

    private var availablePDFURLs: [URL] {
        guard let directoryURL = currentDocumentsDirectoryURL else {
            return []
        }

        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                return values?.isRegularFile == true && url.pathExtension.lowercased() == "pdf"
            }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    private var availableAllFileURLs: [URL] {
        guard let directoryURL = currentDocumentsDirectoryURL else {
            return []
        }

        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                return values?.isRegularFile == true
            }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
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
        case .images:
            return selectedImageDisplayName
        case .sounds:
            return selectedSoundDisplayName
        case .pdfs:
            return selectedPDFDisplayName
        case .all:
            return "all files"
        }
    }

    private var canEditCurrentTitle: Bool {
        switch listMode {
        case .files:
            return selectedDocumentFileURL != nil
        case .images:
            return selectedImageURL != nil
        case .sounds:
            return selectedSoundURL != nil
        case .pdfs:
            return selectedPDFURL != nil
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
        case .images:
            alertMessage = renameSelectedImage(to: proposedName)
        case .sounds:
            alertMessage = renameSelectedSound(to: proposedName)
        case .pdfs:
            alertMessage = renameSelectedPDF(to: proposedName)
        case .all:
            return
        }

        if let alertMessage {
            renameAlertMessage = alertMessage
            return
        }

        documentNameDraft = currentTitleDisplayName
        isEditingDocumentName = false
        isDocumentNameFieldFocused = false
    }

    private func cancelNameEditing() {
        documentNameDraft = currentTitleDisplayName
        isEditingDocumentName = false
        isDocumentNameFieldFocused = false
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
            print("Failed to create document: \(fileURL.lastPathComponent)")
        }
    }

    private func prepareSingleFileExport() {
        saveCurrentDocumentText()
        do {
            let exportURL = try makeSingleFileExportURL()
            singleFileExportURL = exportURL
        } catch {
            cleanupSingleFileExportTemporaryURLIfNeeded()
            renameAlertMessage = "Couldn't prepare the single file export."
        }
    }

    private func prepareArchiveExport() {
        saveCurrentDocumentText()

        let textDocumentURLs = archiveTextDocumentURLs
        guard !textDocumentURLs.isEmpty else {
            renameAlertMessage = "There are no text files to export."
            return
        }

        do {
            let archiveData = try makeArchiveData(from: textDocumentURLs)
            exportArchiveDocument = SettingsArchiveFileDocument(data: archiveData)
            isExportingArchive = true
        } catch {
            renameAlertMessage = "Couldn't create Archive.zip."
        }
    }

    private func makeSingleFileExportURL() throws -> URL {
        cleanupSingleFileExportTemporaryURLIfNeeded()

        if let selectedDocumentFileURL,
           selectedDocumentFileURL.pathExtension.lowercased() == "txt" {
            return selectedDocumentFileURL
        }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(singleFileExportDisplayName).txt")
        try documentEditorText.write(to: temporaryURL, atomically: true, encoding: .utf8)
        singleFileExportTemporaryURL = temporaryURL
        return temporaryURL
    }

    private func cleanupSingleFileExportTemporaryURLIfNeeded() {
        guard let singleFileExportTemporaryURL else {
            return
        }

        try? FileManager.default.removeItem(at: singleFileExportTemporaryURL)
        self.singleFileExportTemporaryURL = nil
    }

    private func selectImage(_ imageURL: URL) {
        persistSelectedImage(imageURL)
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
            persistSelectedPDF(targetURL)
            return nil
        } catch {
            return "Couldn't rename the pdf."
        }
    }

    private func deleteImage(_ imageURL: URL) {
        let previousSelectedImageURL = selectedImageURL

        do {
            try FileManager.default.removeItem(at: imageURL)
        } catch {
            renameAlertMessage = "Couldn't delete the image."
            return
        }

        let refreshedImageURLs = availableImageURLs

        if let previousSelectedImageURL,
           previousSelectedImageURL.lastPathComponent == imageURL.lastPathComponent {
            if let replacementURL = refreshedImageURLs.first {
                persistSelectedImage(replacementURL)
            } else {
                persistSelectedImage(nil)
            }
        } else if let previousSelectedImageURL,
                  let refreshedImageIndex = refreshedImageURLs.firstIndex(where: { $0.lastPathComponent == previousSelectedImageURL.lastPathComponent }) {
            persistSelectedImage(refreshedImageURLs[refreshedImageIndex])
        } else if let selectedImagePosition, selectedImagePosition > refreshedImageURLs.count {
            persistSelectedImage(refreshedImageURLs.last)
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

    private var plainTextImportType: UTType {
        UTType(filenameExtension: "txt") ?? .plainText
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

    private func handleImportedSelection(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result else {
            return
        }

        guard let directoryURL = currentDocumentsDirectoryURL else {
            return
        }

        let session = PendingImportSession(
            directoryURL: directoryURL,
            importListMode: listMode,
            remainingURLs: urls,
            existingFileNames: Set(availableDocumentURLs.map { $0.lastPathComponent.lowercased() }),
            existingImageNames: Set(availableImageURLs.map { $0.lastPathComponent.lowercased() }),
            existingSoundNames: Set(availableSoundURLs.map { $0.lastPathComponent.lowercased() }),
            existingPDFNames: Set(availablePDFURLs.map { $0.lastPathComponent.lowercased() })
        )
        processPendingImportSession(session)
    }

    private func processPendingImportSession(_ session: PendingImportSession) {
        var session = session

        while !session.remainingURLs.isEmpty {
            let sourceURL = session.remainingURLs.removeFirst()
            let pathExtension = sourceURL.pathExtension.lowercased()
            let targetFileName = sourceURL.lastPathComponent
            let targetFileNameKey = targetFileName.lowercased()
            let targetURL = session.directoryURL.appendingPathComponent(targetFileName)

            if pathExtension == "txt" {
                if session.existingFileNames.contains(targetFileNameKey) ||
                    FileManager.default.fileExists(atPath: targetURL.path) {
                    pendingImportSession = session
                    pendingImportConflict = PendingImportConflict(
                        sourceURL: sourceURL,
                        targetURL: targetURL,
                        fileName: targetFileName,
                        contentKind: .document
                    )
                    return
                }

                do {
                    try importFileData(from: sourceURL, to: targetURL)
                    recordSuccessfulImport(
                        targetURL: targetURL,
                        fileNameKey: targetFileNameKey,
                        contentKind: .document,
                        session: &session
                    )
                } catch {
                    print("Failed to import text file \(targetFileName): \(error.localizedDescription)")
                }
                continue
            }

            if supportedImportedImageExtensions.contains(pathExtension) {
                if session.existingImageNames.contains(targetFileNameKey) ||
                    FileManager.default.fileExists(atPath: targetURL.path) {
                    pendingImportSession = session
                    pendingImportConflict = PendingImportConflict(
                        sourceURL: sourceURL,
                        targetURL: targetURL,
                        fileName: targetFileName,
                        contentKind: .image
                    )
                    return
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
                    print("Failed to import image \(targetFileName): \(error.localizedDescription)")
                }
                continue
            }

            if supportedImportedSoundExtensions.contains(pathExtension) {
                if session.existingSoundNames.contains(targetFileNameKey) ||
                    FileManager.default.fileExists(atPath: targetURL.path) {
                    pendingImportSession = session
                    pendingImportConflict = PendingImportConflict(
                        sourceURL: sourceURL,
                        targetURL: targetURL,
                        fileName: targetFileName,
                        contentKind: .sound
                    )
                    return
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
                    print("Failed to import sound \(targetFileName): \(error.localizedDescription)")
                }
                continue
            }

            if supportedImportedPDFExtensions.contains(pathExtension) {
                if session.existingPDFNames.contains(targetFileNameKey) ||
                    FileManager.default.fileExists(atPath: targetURL.path) {
                    pendingImportSession = session
                    pendingImportConflict = PendingImportConflict(
                        sourceURL: sourceURL,
                        targetURL: targetURL,
                        fileName: targetFileName,
                        contentKind: .pdf
                    )
                    return
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
                    print("Failed to import pdf \(targetFileName): \(error.localizedDescription)")
                }
            }
        }

        finishPendingImportSession(session)
    }

    private func recordSuccessfulImport(
        targetURL: URL,
        fileNameKey: String,
        contentKind: ImportedContentKind,
        session: inout PendingImportSession
    ) {
        session.importedAnything = true

        switch contentKind {
        case .document:
            session.existingFileNames.insert(fileNameKey)
            if session.firstImportedDocumentURL == nil {
                session.firstImportedDocumentURL = targetURL
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
        }
    }

    private func resolvePendingImportConflictByReplacing() {
        guard var session = pendingImportSession,
              let conflict = pendingImportConflict else {
            return
        }

        pendingImportConflict = nil
        pendingImportSession = nil

        do {
            if FileManager.default.fileExists(atPath: conflict.targetURL.path) {
                try FileManager.default.removeItem(at: conflict.targetURL)
            }

            try importFileData(from: conflict.sourceURL, to: conflict.targetURL)
            recordSuccessfulImport(
                targetURL: conflict.targetURL,
                fileNameKey: conflict.fileName.lowercased(),
                contentKind: conflict.contentKind,
                session: &session
            )
            processPendingImportSession(session)
        } catch {
            renameAlertMessage = "Couldn't import the file: \(error.localizedDescription)"
            finishPendingImportSession(session)
        }
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

    private func cancelPendingImportSession() {
        guard let session = pendingImportSession else {
            pendingImportConflict = nil
            return
        }

        pendingImportConflict = nil
        pendingImportSession = nil
        finishPendingImportSession(session)
    }

    private func finishPendingImportSession(_ session: PendingImportSession) {
        pendingImportConflict = nil
        pendingImportSession = nil

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
            guard sourceURL.pathExtension.lowercased() == "txt" else {
                renameAlertMessage = "Only .txt files can be imported."
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

        let fileExtension = "txt"
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
                importError = error
            }
        }

        if let importError {
            throw importError
        }

        if let coordinatorError {
            throw coordinatorError
        }
    }

    private var archiveTextDocumentURLs: [URL] {
        let textFiles = availableDocumentURLs
        if !textFiles.isEmpty {
            return textFiles
        }

        if let selectedDocumentFileURL, selectedDocumentFileURL.pathExtension.lowercased() == "txt" {
            return [selectedDocumentFileURL]
        }

        return []
    }

    private var archiveExportType: UTType {
        UTType(filenameExtension: "zip") ?? .data
    }

    private func makeArchiveData(from fileURLs: [URL]) throws -> Data {
        let entries = try fileURLs.map { fileURL in
            SettingsArchiveFileDocument.ArchiveEntry(
                fileName: fileURL.lastPathComponent,
                data: try Data(contentsOf: fileURL)
            )
        }

        return try SettingsArchiveFileDocument.makeArchiveData(with: entries)
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
        "\(Int(clampedTextToSpeechPercentage.rounded()))%"
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

private struct SettingsTextFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    static var writableContentTypes: [UTType] { [.plainText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

private struct SettingsArchiveFileDocument: FileDocument {
    struct ArchiveEntry {
        let fileName: String
        let data: Data
    }

    static var readableContentTypes: [UTType] {
        [UTType(filenameExtension: "zip") ?? .data]
    }

    static var writableContentTypes: [UTType] {
        readableContentTypes
    }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }

    static func makeArchiveData(with entries: [ArchiveEntry]) throws -> Data {
        guard entries.count <= Int(UInt16.max) else {
            throw CocoaError(.fileWriteUnknown)
        }

        var archiveData = Data()
        var centralDirectoryData = Data()

        for entry in entries {
            let fileNameData = Data(entry.fileName.utf8)
            guard fileNameData.count <= Int(UInt16.max),
                  entry.data.count <= Int(UInt32.max),
                  archiveData.count <= Int(UInt32.max) else {
                throw CocoaError(.fileWriteUnknown)
            }

            let crc32 = crc32(of: entry.data)
            let localHeaderOffset = UInt32(archiveData.count)
            let uncompressedSize = UInt32(entry.data.count)
            let compressedSize = UInt32(entry.data.count)
            let fileNameLength = UInt16(fileNameData.count)

            archiveData.appendUInt32LE(0x04034B50)
            archiveData.appendUInt16LE(20)
            archiveData.appendUInt16LE(0)
            archiveData.appendUInt16LE(0)
            archiveData.appendUInt16LE(0)
            archiveData.appendUInt16LE(0)
            archiveData.appendUInt32LE(crc32)
            archiveData.appendUInt32LE(compressedSize)
            archiveData.appendUInt32LE(uncompressedSize)
            archiveData.appendUInt16LE(fileNameLength)
            archiveData.appendUInt16LE(0)
            archiveData.append(fileNameData)
            archiveData.append(entry.data)

            centralDirectoryData.appendUInt32LE(0x02014B50)
            centralDirectoryData.appendUInt16LE(20)
            centralDirectoryData.appendUInt16LE(20)
            centralDirectoryData.appendUInt16LE(0)
            centralDirectoryData.appendUInt16LE(0)
            centralDirectoryData.appendUInt16LE(0)
            centralDirectoryData.appendUInt16LE(0)
            centralDirectoryData.appendUInt32LE(crc32)
            centralDirectoryData.appendUInt32LE(compressedSize)
            centralDirectoryData.appendUInt32LE(uncompressedSize)
            centralDirectoryData.appendUInt16LE(fileNameLength)
            centralDirectoryData.appendUInt16LE(0)
            centralDirectoryData.appendUInt16LE(0)
            centralDirectoryData.appendUInt16LE(0)
            centralDirectoryData.appendUInt16LE(0)
            centralDirectoryData.appendUInt32LE(0)
            centralDirectoryData.appendUInt32LE(localHeaderOffset)
            centralDirectoryData.append(fileNameData)
        }

        guard centralDirectoryData.count <= Int(UInt32.max),
              archiveData.count <= Int(UInt32.max) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let centralDirectoryOffset = UInt32(archiveData.count)
        let centralDirectorySize = UInt32(centralDirectoryData.count)

        archiveData.append(centralDirectoryData)
        archiveData.appendUInt32LE(0x06054B50)
        archiveData.appendUInt16LE(0)
        archiveData.appendUInt16LE(0)
        archiveData.appendUInt16LE(UInt16(entries.count))
        archiveData.appendUInt16LE(UInt16(entries.count))
        archiveData.appendUInt32LE(centralDirectorySize)
        archiveData.appendUInt32LE(centralDirectoryOffset)
        archiveData.appendUInt16LE(0)

        return archiveData
    }

    private static func crc32(of data: Data) -> UInt32 {
        var crc = UInt32.max

        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ crc32Table[index]
        }

        return crc ^ UInt32.max
    }

    private static let crc32Table: [UInt32] = (0..<256).map { value in
        var current = UInt32(value)

        for _ in 0..<8 {
            if current & 1 == 1 {
                current = 0xEDB88320 ^ (current >> 1)
            } else {
                current >>= 1
            }
        }

        return current
    }
}

private struct SettingsSingleFileExportPicker: UIViewControllerRepresentable {
    let url: URL
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onFinish()
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onFinish()
        }
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        var littleEndianValue = value.littleEndian
        append(Data(bytes: &littleEndianValue, count: MemoryLayout<UInt16>.size))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var littleEndianValue = value.littleEndian
        append(Data(bytes: &littleEndianValue, count: MemoryLayout<UInt32>.size))
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

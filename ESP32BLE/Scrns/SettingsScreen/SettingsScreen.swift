import SwiftUI
import UIKit
import AVFoundation
import UniformTypeIdentifiers

struct SettingsScreen: View {
    private enum SettingsListMode: String {
        case files
        case images

        var buttonTitle: String {
            switch self {
            case .files:
                return "Files"
            case .images:
                return "Images"
            }
        }

        mutating func toggle() {
            self = self == .files ? .images : .files
        }
    }

    private let ttsControlColor = Color(red: 0.0, green: 0.2, blue: 0.45)
    private let defaultTextToSpeechRate = Double(AVSpeechUtteranceDefaultSpeechRate)
    private let minimumTextToSpeechPercentage = 40.0
    private let maximumTextToSpeechPercentage = 140.0
    private let textToSpeechPercentageStep = 5.0
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
    @State var bleTextSelection: TextSelection?
    @State private var documentEditorText = ""
    @State private var documentEditorFontSize: CGFloat = 18
    @State private var isLoadingDocumentText = false
    @State private var isDocumentEditorFocused = false
    @State private var speechSynthesizer = AVSpeechSynthesizer()
    @State private var loadedDocumentName = ""
    @State private var savedDocumentEditorText = ""
    @State private var isEditingDocumentName = false
    @State private var documentNameDraft = ""
    @State private var renameAlertMessage: String?
    @AppStorage("settingsListMode") private var listModeRawValue = SettingsListMode.files.rawValue
    @State private var isImportingDocument = false
    @State private var isImportingImages = false
    @State private var isExportingDocument = false
    @State private var exportDocument: SettingsTextFileDocument?
    @State private var isExportingArchive = false
    @State private var exportArchiveDocument: SettingsArchiveFileDocument?
    @State private var availableSpeechVoices: [SpeechVoiceOption] = []
    @AppStorage("selectedTextToSpeechVoiceIdentifier") private var selectedTextToSpeechVoiceIdentifier = ""
    @AppStorage("textToSpeechRate") private var textToSpeechRate = Double(AVSpeechUtteranceDefaultSpeechRate)
    @AppStorage("backgroundImageOpacity") private var opacitySliderValue = 0.5
    @AppStorage("selectedBackgroundImageIndex") var selectedImageIndex = 0
    @AppStorage("selectedBackgroundImageName") var selectedImageName = ""
    @AppStorage("selectedBackgroundImagePath") var selectedImagePath = ""
    @AppStorage(ButtonClickFeedback.preferenceKey) private var isButtonClickEnabled = true
    @FocusState var focusedField: SettingsFocusField?
    @FocusState private var isDocumentNameFieldFocused: Bool

    var body: some View {
        GeometryReader { geometry in
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
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                SettingsToolbarButton(title: "main", backgroundColor: Color.gray.opacity(0.45)) {
                    saveAndReturnToMain()
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
                Menu {
                    Button("Import TXT") {
                        ButtonClickFeedback.playIfEnabled()
                        isImportingDocument = true
                    }
                    Button("Import Images") {
                        ButtonClickFeedback.playIfEnabled()
                        isImportingImages = true
                    }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                .contentShape(.rect)
                .accessibilityLabel("Import from iCloud")
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
                SettingsToolbarButton(title: listMode.buttonTitle, backgroundColor: Color.gray.opacity(0.45)) {
                    listMode.toggle()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                SettingsToolbarButton(title: "new", backgroundColor: Color.green.opacity(0.5)) {
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
            cancelDocumentRename()
        }
        .onChange(of: documentEditorText) {
            guard !isLoadingDocumentText else { return }
            saveCurrentDocumentText()
        }
        .onChange(of: isDocumentNameFieldFocused) {
            guard isEditingDocumentName, !isDocumentNameFieldFocused else { return }
            cancelDocumentRename()
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
            documentNameDraft = selectedDocumentDisplayName
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
        .fileImporter(
            isPresented: $isImportingDocument,
            allowedContentTypes: [plainTextImportType],
            allowsMultipleSelection: true
        ) { result in
            handleDocumentImport(result)
        }
        .fileImporter(
            isPresented: $isImportingImages,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            handleImageImport(result)
        }
        .fileExporter(
            isPresented: $isExportingDocument,
            document: exportDocument,
            contentType: .plainText,
            defaultFilename: selectedDocumentDisplayName
        ) { result in
            if case let .failure(error) = result {
                renameAlertMessage = error.localizedDescription
            }
            exportDocument = nil
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
                        commitDocumentRename()
                    }
            } else {
                Button(selectedDocumentDisplayName) {
                    ButtonClickFeedback.playIfEnabled()
                    documentNameDraft = selectedDocumentDisplayName
                    isEditingDocumentName = true
                }
                .buttonStyle(.plain)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
        }
    }

    private var textToSpeechVoiceMenu: some View {
        Menu {
            ForEach(availableSpeechVoices, id: \.identifier) { voice in
                Button {
                    ButtonClickFeedback.playIfEnabled()
                    selectedTextToSpeechVoiceIdentifier = voice.identifier
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
            displayName: truncatedImageDisplayName,
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
        .fixedSize(horizontal: false, vertical: true)
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
            listMode: listMode == .files ? .files : .images,
            documentFiles: documentFiles,
            selectedDocumentName: selectedDocumentName,
            imageURLs: availableImageURLs,
            selectedImageURL: selectedImageURL,
            canDeleteDocuments: canDeleteDocuments,
            imagePreviewSection: AnyView(imagePreviewSection),
            loadFunctionKeys: loadFunctionKeys,
            deleteDocument: deleteDocument,
            duplicateDocument: duplicateDocument,
            selectImage: selectImage,
            deleteImage: deleteImage
        )
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
                Text("\(speechRecognitionAutoOffMinutes) min")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)

                Slider(
                    value: Binding(
                        get: { Double(speechRecognitionAutoOffMinutes) },
                        set: { speechRecognitionAutoOffMinutes = Int($0.rounded()) }
                    ),
                    in: 1...30,
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
                speechRecognitionAutoOffMinutes = min(30, speechRecognitionAutoOffMinutes + 1)
            } label: {
                Image(systemName: "triangle.fill")
                    .font(.system(size: 26))
                    .rotationEffect(.degrees(90))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .disabled(speechRecognitionAutoOffMinutes >= 30)
            .alignmentGuide(.sliderTrackCenter) { dimensions in
                dimensions[VerticalAlignment.center]
            }
        }
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
        documentNameDraft = selectedDocumentDisplayName
    }

    private func saveSelectedDocumentText() {
        guard let fileURL = selectedDocumentFileURL else {
            return
        }

        saveDocumentText(documentEditorText, to: fileURL)
    }

    private func saveCurrentDocumentText() {
        guard !loadedDocumentName.isEmpty,
              let fileURL = documentFiles.first(where: { $0.lastPathComponent == loadedDocumentName }) else {
            return
        }

        saveDocumentText(documentEditorText, to: fileURL)
    }

    private func saveCurrentDocumentText(_ text: String) {
        guard !loadedDocumentName.isEmpty,
              let fileURL = documentFiles.first(where: { $0.lastPathComponent == loadedDocumentName }) else {
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
        documentFiles.first(where: { $0.lastPathComponent == selectedDocumentName })
    }

    private var selectedDocumentDisplayName: String {
        URL(fileURLWithPath: selectedDocumentName).deletingPathExtension().lastPathComponent
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

    private func commitDocumentRename() {
        let proposedName = documentNameDraft

        if let alertMessage = renameDocument(proposedName) {
            renameAlertMessage = alertMessage
            return
        }

        documentNameDraft = selectedDocumentDisplayName
        isEditingDocumentName = false
        isDocumentNameFieldFocused = false
    }

    private func cancelDocumentRename() {
        documentNameDraft = selectedDocumentDisplayName
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
        exportDocument = SettingsTextFileDocument(text: documentEditorText)
        isExportingDocument = true
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

    private func selectImage(_ imageURL: URL) {
        persistSelectedImage(imageURL)
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

    private var plainTextImportType: UTType {
        UTType(filenameExtension: "txt") ?? .plainText
    }

    private var supportedImportedImageExtensions: Set<String> {
        ["png", "jpg", "jpeg", "heic", "heif", "gif", "bmp", "tiff", "webp"]
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

        let existingFileNames = Set(documentFiles.map { $0.lastPathComponent.lowercased() })
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

            let didAccessSecurityScopedResource = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didAccessSecurityScopedResource {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let importedText = try String(contentsOf: sourceURL, encoding: .utf8)
                try importedText.write(to: targetURL, atomically: true, encoding: .utf8)
            } catch {
                renameAlertMessage = "Couldn't import the file."
                return
            }
        }

        refreshDocumentFiles()

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

        let existingImageNames = Set(availableImageURLs.map { $0.lastPathComponent.lowercased() })
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

            let didAccessSecurityScopedResource = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didAccessSecurityScopedResource {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            do {
                if FileManager.default.fileExists(atPath: targetURL.path) {
                    duplicateImageNames.append(targetFileName)
                    continue
                }
                try FileManager.default.copyItem(at: sourceURL, to: targetURL)
            } catch {
                renameAlertMessage = "Couldn't import the image."
                return
            }
        }

        if !availableImageURLs.isEmpty {
            let previousImageURL = selectedImageURL
            refreshDocumentFiles()
            if let previousImageURL,
               let refreshedImageIndex = availableImageURLs.firstIndex(where: { $0.lastPathComponent == previousImageURL.lastPathComponent }) {
                persistSelectedImage(availableImageURLs[refreshedImageIndex])
            }
        } else {
            refreshDocumentFiles()
        }

        if let duplicateImageName = duplicateImageNames.first {
            renameAlertMessage = duplicateImageNames.count == 1
                ? "a file with that name already exists."
                : "Some images were skipped because they already exist. First skipped: \(duplicateImageName)"
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

    private var currentDocumentsDirectoryURL: URL? {
        if let existingDocumentURL = documentFiles.first {
            return existingDocumentURL.deletingLastPathComponent()
        }

        if let selectedDocumentFileURL {
            return selectedDocumentFileURL.deletingLastPathComponent()
        }

        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    private var archiveTextDocumentURLs: [URL] {
        let textFiles = documentFiles.filter { $0.pathExtension.lowercased() == "txt" }
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

        availableSpeechVoices = AVSpeechSynthesisVoice.speechVoices()
            .map { voice in
                let localeName = Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language
                return SpeechVoiceOption(
                    identifier: voice.identifier,
                    languageCode: Locale(identifier: voice.language).language.languageCode?.identifier.lowercased() ?? "",
                    languageDisplayName: localeName,
                    name: voice.name,
                    menuTitle: "\(voice.name) (\(localeName))"
                )
            }
            .sorted {
                let leftPriority = speechVoiceSortPriority(for: $0)
                let rightPriority = speechVoiceSortPriority(for: $1)

                if leftPriority != rightPriority {
                    return leftPriority < rightPriority
                }

                if leftPriority == 2 {
                    let languageComparison = $0.languageDisplayName.localizedCaseInsensitiveCompare($1.languageDisplayName)
                    if languageComparison != .orderedSame {
                        return languageComparison == .orderedAscending
                    }
                }

                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    private func speechVoiceSortPriority(for voice: SpeechVoiceOption) -> Int {
        switch voice.languageCode {
        case "en":
            return 0
        case "ja":
            return 1
        default:
            return 2
        }
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
    let languageCode: String
    let languageDisplayName: String
    let name: String
    let menuTitle: String

    var id: String { identifier }
}

private struct SettingsTextFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

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

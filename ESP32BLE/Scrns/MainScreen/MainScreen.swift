
import SwiftUI
import UIKit

struct MainScreen: View {
    // Easy-to-find styling controls for the main button grid.
    private let mainGridButtonSpacing: CGFloat = 10
    let mainGridButtonCornerRadius: CGFloat = 30
    let mainGridButtonBorderWidth: CGFloat = 2
  
	// Easy-to-find spacing for the slot editor controls row.
    private let slotEditorButtonSpacing: CGFloat = 5
    // Easy-to-find width for all slot editor helper buttons.
    private let slotEditorHelperButtonWidth: CGFloat = 58

    @AppStorage("speechRecognitionAutoOffMinutes") private var speechRecognitionAutoOffMinutes = 5
    let allowedVisibleBoxCounts = [
        1, 2, 4, 6, 9, 12, 15, 16, 18, 20, 24, 28, 32, 36, 40, 42, 45, 48,
        50, 54, 56, 60, 63, 64, 70, 72, 80, 81, 84, 88, 90, 96, 99, 100
    ]
    private let displayModeButtonColor = Color(red: 0.05, green: 0.33, blue: 0.18)
    private let countControlColor = Color(red: 0.15, green: 0.72, blue: 0.22)
    private let fontControlColor = Color(red: 0.78, green: 0.68, blue: 0.12)
    private let speechRecognitionActiveColor = Color(red: 0.42, green: 0.12, blue: 0.12)
    private let bleSendActiveColor = Color(red: 0.55, green: 0.45, blue: 0.08)
    @State var visibleBoxCount = 20
    @State private var isBLESendEnabled = true
    @State private var isSpkRecEnabled = false
    @State private var unmatchedSpeechText: String?
    @State private var speechRecognitionAutoOffTask: Task<Void, Never>?
    @StateObject private var speechRecognition = SpeechRecognitionManager()
    @ObservedObject var ble: BLEKeyboardManager
    @State var displayMode: FunctionKeyDisplayMode = .both
    @State var isEditingDocumentName = false
    @State var documentNameDraft = ""
    @State var renameAlertMessage: String?
    @State var isGridEditModeEnabled = false
    @State var activeDragIndex: Int?
    @State var editingSlotIndex: Int?
    @State var editingSlotText = ""
    @FocusState var isDocumentNameFieldFocused: Bool
    @FocusState var isSlotEditorFocused: Bool
    let functionKeys: [FunctionKeyEntry]
    let documentFiles: [URL]
    let selectedDocumentName: String
    let selectedDocumentDisplayName: String
    let boxFontSize: Double
    let currentFileNumber: Int
    let totalFileCount: Int
    let definedFunctionKeyCount: Int
    let refreshDocumentFiles: () -> Void
    let loadFunctionKeys: (URL) -> Void
    let saveSelectedDocumentAndReload: (String) -> Void
    let renameDocument: (String) -> String?
    let deleteDocument: (URL) -> Void
    let duplicateDocument: (URL) -> Void
    let canDeleteDocuments: Bool
    let selectPreviousDocument: () -> Void
    let selectNextDocument: () -> Void
    let resizeVisibleBoxCount: (Int) -> Bool
    let moveFunctionKeySlot: (Int, Int) -> Bool
    let updateFunctionKeySlot: (Int, String) -> Bool
    let updateDocumentFontSize: (Double) -> Void
    let openKeyboardScreen: () -> Void
    @Binding var settingsBLEText: String

    var body: some View {
        mainScreenContent
            .task(id: isEditingDocumentName) {
                guard isEditingDocumentName else { return }
                isDocumentNameFieldFocused = true
            }
            .onAppear {
                reloadSelectedDocumentIfAvailable()
            }
            .onChange(of: selectedDocumentDisplayName) {
                handleSelectedDocumentDisplayNameChange()
            }
            .onChange(of: definedFunctionKeyCount) {
                updateVisibleBoxCountToFitDefinedButtons()
            }
            .onChange(of: isDocumentNameFieldFocused) {
                handleDocumentNameFieldFocusChange()
            }
            .onChange(of: isSpkRecEnabled) {
                handleSpeechRecognitionToggle()
            }
            .onChange(of: speechRecognitionAutoOffMinutes) {
                handleSpeechRecognitionAutoOffMinutesChange()
            }
            .onChange(of: latestRecognizedText) {
                handleLatestRecognizedTextChange()
            }
            .onDisappear {
                handleMainScreenDisappear()
            }
            .task(id: definedFunctionKeyCount) {
                updateVisibleBoxCountToFitDefinedButtons()
            }
            .alert("Rename File", isPresented: renameAlertIsPresented) {
                Button("OK", role: .cancel) {
                    renameAlertMessage = nil
                }
            } message: {
                Text(renameAlertMessage ?? "")
            }
    }

    private var mainScreenContent: some View {
        VStack(spacing: 20) {
            mainGridSection

            displayModeButtonSection
        }
        .background(Color.black.ignoresSafeArea())
        .ignoresSafeArea(.keyboard)
        .overlay {
            if editingSlotIndex != nil {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
            }
        }
        .overlay(alignment: .top) {
            if isGridEditModeEnabled, editingSlotIndex != nil {
                slotEditorSection
                    .offset(y: -2)
            }
        }
        .padding(.horizontal, 2)
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            MainScreenToolbarContent(
                isGridEditModeEnabled: isGridEditModeEnabled,
                editingSlotIndex: editingSlotIndex,
                currentFileNumber: currentFileNumber,
                totalFileCount: totalFileCount,
                isEditingDocumentName: $isEditingDocumentName,
                documentNameDraft: $documentNameDraft,
                selectedDocumentDisplayName: selectedDocumentDisplayName,
                isDocumentNameFieldFocused: $isDocumentNameFieldFocused,
                openKeyboardScreen: openKeyboardScreen,
                selectPreviousDocument: selectPreviousDocument,
                selectNextDocument: selectNextDocument,
                toggleGridEditMode: { isGridEditModeEnabled.toggle() },
                commitDocumentRename: commitDocumentRename,
                openSettings: AnyView(
                    NavigationLink {
                        SettingsScreen(
                            ble: ble,
                            documentFiles: documentFiles,
                            selectedDocumentName: selectedDocumentName,
                            refreshDocumentFiles: refreshDocumentFiles,
                            loadFunctionKeys: loadFunctionKeys,
                            saveSelectedDocumentAndReload: saveSelectedDocumentAndReload,
                            deleteDocument: deleteDocument,
                            duplicateDocument: duplicateDocument,
                            canDeleteDocuments: canDeleteDocuments,
                            bleTextToSend: $settingsBLEText
                        )
                    } label: {
                        settingsToolbarButtonLabel
                    }
                    .simultaneousGesture(TapGesture().onEnded { ButtonClickFeedback.playIfEnabled() })
                )
            )
        }
    }

    private var mainGridSection: some View {
        MainScreenGridSection(
            functionKeys: functionKeys,
            visibleBoxCount: visibleBoxCount,
            mainGridButtonSpacing: mainGridButtonSpacing,
            isGridEditModeEnabled: isGridEditModeEnabled,
            bleSendEnabled: isBLESendEnabled,
            onButtonClick: { ButtonClickFeedback.playIfEnabled() },
            sendLine: sendMainGridEntry,
            onBeginSlotEditing: beginSlotEditing,
            buttonLabel: { entry, index, buttonHeight in
                AnyView(mainGridButtonLabel(entry: entry, index: index, buttonHeight: buttonHeight))
            },
            dragGesture: { entry, index, gridDimensions in
                AnyGesture(mainGridButtonDragGesture(entry: entry, index: index, gridDimensions: gridDimensions))
            }
        )
    }

    private var settingsToolbarButtonLabel: some View {
        Text("settings >")
            .font(.headline)
            .foregroundStyle(.white)
            .frame(minWidth: 92, minHeight: 44)
            .background(Color.gray.opacity(0.45))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
            }
            .clipShape(.rect(cornerRadius: 12))
            .contentShape(.rect)
    }

    private var displayModeButtonSection: some View {
        MainScreenBottomBar(
            allowedVisibleBoxCounts: allowedVisibleBoxCounts,
            visibleBoxCount: visibleBoxCount,
            boxFontSize: boxFontSize,
            minimumBoxFontSize: minimumBoxFontSize,
            maximumBoxFontSize: maximumBoxFontSize,
            speechRecognitionDisplayText: speechRecognitionDisplayText,
            speechRecognitionDisplayColor: speechRecognitionDisplayColor,
            isSpeechRecognitionEnabled: isSpkRecEnabled,
            isBLESendEnabled: isBLESendEnabled,
            displayMode: displayMode,
            displayModeButtonColor: displayModeButtonColor,
            countControlColor: countControlColor,
            fontControlColor: fontControlColor,
            speechRecognitionActiveColor: speechRecognitionActiveColor,
            bleSendActiveColor: bleSendActiveColor,
            onDecreaseVisibleBoxCount: decreaseVisibleBoxCount,
            onIncreaseVisibleBoxCount: increaseVisibleBoxCount,
            onDecreaseBoxFontSize: decreaseBoxFontSize,
            onIncreaseBoxFontSize: increaseBoxFontSize,
            onToggleSpeechRecognition: { isSpkRecEnabled.toggle() },
            onToggleBLESend: { isBLESendEnabled.toggle() },
            onAdvanceDisplayMode: { displayMode = displayMode.next() }
        )
    }

    private var slotEditorSection: some View {
        MainScreenSlotEditorOverlay(
            editingSlotText: $editingSlotText,
            focusBinding: $isSlotEditorFocused,
            buttonSpacing: slotEditorButtonSpacing,
            helperButtonWidth: slotEditorHelperButtonWidth,
            onCancel: cancelSlotEditing,
            onCommit: commitSlotEditing,
            onTest: testEditingSlotText
        )
    }

    private func testEditingSlotText() {
        guard ble.isConnected else {
            print("Bluetooth not connected.")
            return
        }

        ble.sendString(editingSlotText)
    }

    private func applyRecognizedSpeech(_ recognizedText: String) {
        guard isSpkRecEnabled, !isGridEditModeEnabled else {
            return
        }

        scheduleSpeechRecognitionAutoOff()

        guard let matchingEntry = functionKeys.first(where: { entry in
            guard let alternateDisplayText = entry.alternateDisplayText else {
                return false
            }

            return normalizedSpeechMatchText(alternateDisplayText) == recognizedText
        }) else {
            unmatchedSpeechText = recognizedText
            return
        }

        unmatchedSpeechText = nil

        guard isBLESendEnabled else {
            return
        }

        for sendText in matchingEntry.sendTexts {
            ble.sendLine(sendText)
        }
    }

    private func normalizedSpeechMatchText(_ text: String) -> String {
        canonicalSpeechText(from: displayText(from: text))
    }

    private func canonicalSpeechText(from text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func handleSpeechRecognitionToggle() {
        if isSpkRecEnabled {
            unmatchedSpeechText = nil
            sendModifierFunctionKey("f20")
            speechRecognition.setListeningEnabled(true)
            scheduleSpeechRecognitionAutoOff()
            return
        }

        speechRecognitionAutoOffTask?.cancel()
        speechRecognitionAutoOffTask = nil
        unmatchedSpeechText = nil
        speechRecognition.setListeningEnabled(false)
        sendModifierFunctionKey("f19")
    }

    private var latestRecognizedText: String? {
        speechRecognition.latestRecognition?.text
    }

    private func handleSelectedDocumentDisplayNameChange() {
        cancelDocumentRename()
        isGridEditModeEnabled = false
        activeDragIndex = nil
        cancelSlotEditing()
    }

    private func handleDocumentNameFieldFocusChange() {
        guard isEditingDocumentName, !isDocumentNameFieldFocused else {
            return
        }

        cancelDocumentRename()
    }

    private func reloadSelectedDocumentIfAvailable() {
        guard let selectedDocumentURL = documentFiles.first(where: { $0.lastPathComponent == selectedDocumentName }) else {
            return
        }

        loadFunctionKeys(selectedDocumentURL)
    }

    private func handleSpeechRecognitionAutoOffMinutesChange() {
        guard isSpkRecEnabled else {
            return
        }

        scheduleSpeechRecognitionAutoOff()
    }

    private func handleLatestRecognizedTextChange() {
        guard let recognizedText = latestRecognizedText else {
            return
        }

        applyRecognizedSpeech(recognizedText)
    }

    private func handleMainScreenDisappear() {
        speechRecognitionAutoOffTask?.cancel()
        speechRecognition.setListeningEnabled(false)
    }

    private func scheduleSpeechRecognitionAutoOff() {
        speechRecognitionAutoOffTask?.cancel()

        let autoOffMinutes = min(max(speechRecognitionAutoOffMinutes, 1), 30)
        speechRecognitionAutoOffTask = Task {
            do {
                try await Task.sleep(for: .seconds(autoOffMinutes * 60))
            } catch {
                return
            }

            await MainActor.run {
                guard isSpkRecEnabled else {
                    return
                }

                isSpkRecEnabled = false
            }
        }
    }

    private func sendModifierFunctionKey(_ functionKey: String) {
        guard !isGridEditModeEnabled else {
            return
        }

        ble.sendLine("ct")
        ble.sendLine("sh")
        ble.sendLine("op")
        ble.sendLine("cm")
        ble.sendLine(functionKey)
    }

    private var speechRecognitionDisplayText: String {
        if let unmatchedSpeechText {
            return unmatchedSpeechText
        }

        switch speechRecognition.displayState {
        case .disabled:
            return "disabled"
        case .recognizing:
            return "recognizing..."
        case .recognized(let text):
            return text
        }
    }

    private var speechRecognitionDisplayColor: Color {
        if unmatchedSpeechText != nil {
            return .white
        }

        switch speechRecognition.displayState {
        case .recognized:
            return .white
        case .disabled, .recognizing:
            return .gray
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

    var minimumBoxFontSize: Double { 12 }

    var maximumBoxFontSize: Double { 100 }

    private func gridDimensions(for itemCount: Int) -> (columns: Int, rows: Int) {
        let preferredDimensions: [Int: (columns: Int, rows: Int)] = [
            15: (5, 3),
            18: (6, 3),
            24: (6, 4),
            28: (7, 4),
            32: (8, 4),
            40: (8, 5),
            45: (9, 5),
            48: (8, 6),
            50: (10, 5),
            54: (9, 6),
            60: (10, 6),
            63: (9, 7),
            70: (10, 7),
            80: (10, 8),
            84: (12, 7),
            88: (11, 8),
            96: (12, 8),
            99: (11, 9)
        ]

        if let preferred = preferredDimensions[itemCount] {
            return preferred
        }

        guard itemCount > 0 else {
            return (1, 1)
        }

        let baseColumns = Int(ceil(sqrt(Double(itemCount))))
        var columns = max(baseColumns, Int(ceil(Double(itemCount) / Double(baseColumns))))
        var rows = Int(ceil(Double(itemCount) / Double(columns)))

        if rows > columns {
            swap(&rows, &columns)
        }

        return (columns, rows)
    }

    func handleEditDragEnded(
        from sourceIndex: Int,
        translation: CGSize,
        gridDimensions: (columns: Int, rows: Int)
    ) {
        defer {
            activeDragIndex = nil
        }

        guard isGridEditModeEnabled,
              editingSlotIndex == nil,
              let targetIndex = targetIndexForEditDrag(
                from: sourceIndex,
                translation: translation,
                gridDimensions: gridDimensions
              ) else {
            return
        }

        _ = moveFunctionKeySlot(sourceIndex, targetIndex)
    }

}

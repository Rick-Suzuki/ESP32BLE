
import SwiftUI
import UIKit
import AVFoundation

struct MainScreen: View {
    // Easy-to-find styling controls for the main button grid.
    private let mainGridButtonSpacing: CGFloat = 10
    let mainGridButtonCornerRadius: CGFloat = 30
    let mainGridButtonBorderWidth: CGFloat = 2
  
	// Easy-to-find spacing for the slot editor controls row.
    private let slotEditorButtonSpacing: CGFloat = 5
    // Easy-to-find width for all slot editor helper buttons.
    private let slotEditorHelperButtonWidth: CGFloat = 58

    @AppStorage("speechRecognitionAutoOffMinutes") var speechRecognitionAutoOffMinutes = 5
	
	// MARK: - BM:🔆 grid dims - allowed sizes
	
    let allowedVisibleBoxCounts = [
        1, 2, 4, 6, 9, 12, 15, 16, 18, 20, 21, 24, 25, 28, 32, 35, 36, 40, 42, 45, 48,
        50, 54, 56, 60, 63, 64, 70, 72, 80, 81, 84, 88, 90, 96, 99, 100
    ]
    private let displayModeButtonColor = Color(red: 0.05, green: 0.33, blue: 0.18)
    private let countControlColor = Color(red: 0.15, green: 0.72, blue: 0.22)
    private let fontControlColor = Color(red: 0.78, green: 0.68, blue: 0.12)
    private let speechRecognitionActiveColor = Color(red: 0.0, green: 0.2, blue: 0.45)
    private let bleSendActiveColor = Color(red: 0.55, green: 0.45, blue: 0.08)
    @State var visibleBoxCount = 20
    @State var mainGridButtonMode: MainGridButtonMode = .active
    @State var isSpkRecEnabled = false
    @State var unmatchedSpeechText: String?
    @State var speechRecognitionAutoOffTask: Task<Void, Never>?
    @StateObject var speechRecognition = SpeechRecognitionManager()
    @State var speechSynthesizer = AVSpeechSynthesizer()
    @ObservedObject var ble: BLEKeyboardManager
    @State var displayMode: FunctionKeyDisplayMode = .right
    @State var isEditingDocumentName = false
    @State var documentNameDraft = ""
    @State var alertTitle = "Alert"
    @State var renameAlertMessage: String?
    @State var isGridEditModeEnabled = false
    @State var activeDragIndex: Int?
    @State var editingSlotIndex: Int?
    @State var editingSlotText = ""
    @State private var keyboardMinY: CGFloat = .greatestFiniteMagnitude
    @State private var popupDismissTask: Task<Void, Never>?
    @AppStorage("selectedTextToSpeechVoiceIdentifier") var selectedTextToSpeechVoiceIdentifier = ""
    @AppStorage("textToSpeechRate") var textToSpeechRate = Double(AVSpeechUtteranceDefaultSpeechRate)
    @AppStorage("selectedBackgroundImageIndex") var selectedBackgroundImageIndex = 0
    @AppStorage("backgroundImageOpacity") var backgroundImageOpacity = 0.5
    @AppStorage("mainGridBackgroundOpacity") var mainGridBackgroundOpacity = 1.0
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
    let goBackToPreviousDocument: () -> Void
    let canGoBackToPreviousDocument: Bool
    let selectDocumentNamedFromGrid: (String) -> Bool
    let resizeVisibleBoxCount: (Int) -> Bool
    let moveFunctionKeySlot: (Int, Int) -> Bool
    let duplicateFunctionKeySlot: (Int, Int) -> Bool
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
                popupDismissTask?.cancel()
            }
            .task(id: definedFunctionKeyCount) {
                updateVisibleBoxCountToFitDefinedButtons()
            }
            .task {
                await observeKeyboardFrameChanges()
            }
            .overlay {
                popupOverlay
            }
            .onChange(of: renameAlertMessage) {
                schedulePopupDismissIfNeeded()
            }
    }

    private var mainScreenContent: some View {
        GeometryReader { geometry in
            let horizontalContentInset: CGFloat = 0
            let contentWidth = max(0, geometry.size.width - (horizontalContentInset * 2))
            let topContentInset: CGFloat = 8
            let bottomContentInset: CGFloat = 0
            let containerFrame = geometry.frame(in: .global)
            let maskBottomY = min(containerFrame.maxY, keyboardMinY)
            let maskHeight = max(0, maskBottomY - containerFrame.minY)
            let maskedScreenHeight = maskHeight + geometry.safeAreaInsets.top

            ZStack(alignment: .top) {
                VStack(spacing: 20) {
                    mainGridSection(availableWidth: contentWidth)

                    if !isGridEditModeEnabled {
                        displayModeButtonSection(availableWidth: contentWidth)
                    }
                }
                .frame(width: contentWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, topContentInset)
                .padding(.bottom, bottomContentInset)
                .ignoresSafeArea(.keyboard)

                if isGridEditModeEnabled {
                    VStack {
                        Spacer()
                        displayModeButtonSection(availableWidth: contentWidth)
                    }
                    .frame(maxWidth: contentWidth, maxHeight: .infinity)
                }

                if editingSlotIndex != nil {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .mask(alignment: .top) {
                            Rectangle()
                                .frame(height: maskedScreenHeight)
                                .padding(.horizontal, -2)
                        }
                        .contentShape(Rectangle())
                        .allowsHitTesting(false)
                }

                if isGridEditModeEnabled, editingSlotIndex != nil {
                    slotEditorSection
                        .offset(y: topContentInset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 2)
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .toolbarVisibility(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            MainScreenToolbarContent(
                isGridEditModeEnabled: isGridEditModeEnabled,
                editingSlotIndex: editingSlotIndex,
                currentFileNumber: currentFileNumber,
                totalFileCount: totalFileCount,
                gridBackgroundOpacity: $mainGridBackgroundOpacity,
                isEditingDocumentName: $isEditingDocumentName,
                documentNameDraft: $documentNameDraft,
                selectedDocumentDisplayName: selectedDocumentDisplayName,
                isHomeDocumentSelected: selectedDocumentName.caseInsensitiveCompare("home.txt") == .orderedSame,
                isDocumentNameFieldFocused: $isDocumentNameFieldFocused,
                openKeyboardScreen: openKeyboardScreen,
                openHomeDocument: { _ = selectDocumentNamedFromGrid("home.txt") },
                canGoBackToPreviousDocument: canGoBackToPreviousDocument,
                goBackToPreviousDocument: goBackToPreviousDocument,
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
                            renameDocument: renameDocument,
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

    private func mainGridSection(availableWidth: CGFloat) -> some View {
        MainScreenGridSection(
            availableWidth: availableWidth,
            reservedBottomInset: isGridEditModeEnabled ? 74 : 0,
            functionKeys: functionKeys,
            visibleBoxCount: visibleBoxCount,
            mainGridButtonSpacing: mainGridButtonSpacing,
            isGridEditModeEnabled: isGridEditModeEnabled,
            bleSendEnabled: mainGridButtonMode != .disabled,
            onButtonClick: { ButtonClickFeedback.playIfEnabled() },
            sendLine: sendMainGridEntry,
            onBeginSlotEditing: beginSlotEditing,
            buttonLabel: { entry, index, buttonHeight in
                AnyView(
                    mainGridButtonLabel(
                        entry: entry,
                        index: index,
                        buttonHeight: buttonHeight,
                        backgroundOpacity: mainGridBackgroundOpacity
                    )
                )
            },
            dragGesture: { entry, index, gridDimensions in
                AnyGesture(mainGridButtonDragGesture(entry: entry, index: index, gridDimensions: gridDimensions))
            },
            onDuplicateSlot: { entry, index, gridDimensions in
                duplicateSlotIfPossible(entry: entry, index: index, gridDimensions: gridDimensions)
            },
            onDeleteSlot: { entry, index in
                deleteSlotIfPossible(entry: entry, index: index)
            }
        )
    }

    private var settingsToolbarButtonLabel: some View {
        Text("settings >")
            .font(.headline)
            .foregroundStyle((isGridEditModeEnabled || editingSlotIndex != nil) ? Color(white: 0.65) : .white)
            .frame(minWidth: 92, minHeight: 44)
            .background(Color.gray.opacity(0.45))
            .overlay {
                RoundedRectangle(cornerRadius: 23)
                    .stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
            }
            .clipShape(.rect(cornerRadius: 23))
            .contentShape(.rect)
    }

    private func displayModeButtonSection(availableWidth: CGFloat) -> some View {
        MainScreenBottomBar(
            availableWidth: availableWidth,
            allowedVisibleBoxCounts: allowedVisibleBoxCounts,
            visibleBoxCount: visibleBoxCount,
            visibleActiveBoxCount: visibleActiveBoxCount,
            isGridEditModeEnabled: isGridEditModeEnabled,
            boxFontSize: boxFontSize,
            minimumBoxFontSize: minimumBoxFontSize,
            maximumBoxFontSize: maximumBoxFontSize,
            speechRecognitionDisplayText: speechRecognitionDisplayText,
            speechRecognitionDisplayColor: speechRecognitionDisplayColor,
            isSpeechRecognitionEnabled: isSpkRecEnabled,
            mainGridButtonMode: mainGridButtonMode,
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
            onCycleMainGridButtonMode: cycleMainGridButtonMode,
            onStopSpeech: stopSpokenGridText,
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
            onTest: testEditingSlotText,
            onCopy: showSlotCopiedPopup,
            onPaste: showSlotPastedPopup
        )
    }

    private func testEditingSlotText() {
        guard ble.isConnected else {
            alertTitle = "Bluetooth not connected"
            renameAlertMessage = "Bluetooth not connected. Bluetooth needs to be connected before sending data to the ESP32."
            return
        }

        let actionText = editingSlotText.components(separatedBy: "::").first ?? editingSlotText
        let actionTokens = actionText
            .components(separatedBy: ":")
            .compactMap { component -> String? in
                if !component.isEmpty,
                   component.allSatisfy({ $0.isWhitespace && !$0.isNewline }) {
                    return " "
                }

                let trimmedComponent = component.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmedComponent.isEmpty ? nil : trimmedComponent
            }

        for actionToken in actionTokens where targetDocumentNameForSendText(actionToken) == nil {
            ble.sendLine(normalizedBluetoothSendText(actionToken))
        }
    }

    private func showSlotCopiedPopup() {
        alertTitle = ""
        renameAlertMessage = "Copied"
    }

    private func showSlotPastedPopup() {
        alertTitle = ""
        renameAlertMessage = "Pasted"
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

    @MainActor
    private func observeKeyboardFrameChanges() async {
        let notificationCenter = NotificationCenter.default

        Task {
            for await _ in notificationCenter.notifications(named: UIResponder.keyboardWillHideNotification) {
                await MainActor.run {
                    keyboardMinY = .greatestFiniteMagnitude
                }
            }
        }

        for await notification in notificationCenter.notifications(named: UIResponder.keyboardWillChangeFrameNotification) {
            guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
                keyboardMinY = .greatestFiniteMagnitude
                continue
            }

            let screenHeight = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.screen.bounds.height ?? 0

            if screenHeight > 0, endFrame.minY >= screenHeight {
                keyboardMinY = .greatestFiniteMagnitude
            } else {
                keyboardMinY = endFrame.minY
            }
        }
    }

    private func reloadSelectedDocumentIfAvailable() {
        guard let selectedDocumentURL = documentFiles.first(where: { $0.lastPathComponent == selectedDocumentName }) else {
            return
        }

        loadFunctionKeys(selectedDocumentURL)
    }

    func cycleMainGridButtonMode() {
        mainGridButtonMode = mainGridButtonMode.next()
        if !mainGridButtonMode.speaksText {
            stopSpokenGridText()
        }
    }

    func stopSpokenGridText() {
        speechSynthesizer.stopSpeaking(at: .immediate)
    }

    @ViewBuilder
    private var popupOverlay: some View {
        if let renameAlertMessage {
            VStack {
                Spacer()

                VStack(spacing: 8) {
                    if !alertTitle.isEmpty, alertTitle != "Alert" {
                        Text(alertTitle)
                            .font(.headline)
                            .foregroundStyle(.white)
                    }

                    Text(renameAlertMessage)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color.black.opacity(0.88))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 24)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
            .allowsHitTesting(false)
        }
    }

    private func schedulePopupDismissIfNeeded() {
        popupDismissTask?.cancel()

        guard renameAlertMessage != nil else {
            popupDismissTask = nil
            return
        }

        popupDismissTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                renameAlertMessage = nil
            }
        }
    }

    var minimumBoxFontSize: Double { 12 }

    var maximumBoxFontSize: Double { 100 }

    var visibleActiveBoxCount: Int {
        functionKeys
            .prefix(visibleBoxCount)
            .filter { entry in
                !entry.isBlankPlaceholder && !isEmptyButtonEntry(entry)
            }
            .count
    }

    private func gridDimensions(for itemCount: Int) -> (columns: Int, rows: Int) {
        let preferredDimensions: [Int: (columns: Int, rows: Int)] = [
            15: (5, 3),
            18: (6, 3),
            24: (6, 4),
            25: (5, 5),
            28: (7, 4),
            32: (8, 4),
            35: (7, 5),
            36: (6, 6),
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
            99: (11, 9),
            100: (10, 10)
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


import SwiftUI
import UIKit
import AVFoundation

struct MainScreen: View {
    // Easy-to-find styling controls for the main button grid.
    private let mainGridButtonSpacingMaximum: CGFloat = 10
    private let mainGridButtonSpacingMinimum: CGFloat = 4
    private let mainGridButtonCornerRadiusMaximum: CGFloat = 20
    private let mainGridButtonCornerRadiusMinimum: CGFloat = 5
    let mainGridButtonBorderWidth: CGFloat = 2
  
	// Easy-to-find spacing for the slot editor controls row.
    private let slotEditorButtonSpacing: CGFloat = 5
    // Easy-to-find width for all slot editor helper buttons.
    private let slotEditorHelperButtonWidth: CGFloat = 58

    @AppStorage("speechRecognitionAutoOffMinutes") var speechRecognitionAutoOffMinutes = 5
	
	// MARK: - BM:🔆 grid dims - allowed sizes
	
    private let displayModeButtonColor = Color(red: 0.05, green: 0.33, blue: 0.18)
    private let fontControlColor = Color(red: 0.78, green: 0.68, blue: 0.12)
    private let speechRecognitionActiveColor = Color(red: 0.0, green: 0.2, blue: 0.45)
    private let bleSendActiveColor = Color(red: 0.55, green: 0.45, blue: 0.08)
    @State var visibleBoxCount = 20
    @State var visibleGridDimensions: GridDimensions = functionKeyGridDimensions(for: 20)
    @State var mainGridButtonMode: MainGridButtonMode = .active
    @State var isSpkRecEnabled = false
    @State var unmatchedSpeechText: String?
    @State var speechRecognitionAutoOffTask: Task<Void, Never>?
    @StateObject var speechRecognition = SpeechRecognitionManager()
    @State var speechSynthesizer = AVSpeechSynthesizer()
    @State var soundEffectPlayer: AVAudioPlayer?
    @StateObject var mainGridTimerState = MainGridSharedTimerState()
    @StateObject var mainGridAmbientSoundState = MainGridAmbientSoundState()
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
    @Binding var boxFontSize: Double
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
    let resizeVisibleBoxCount: (GridDimensions, GridDimensions) -> Bool
    let moveFunctionKeySlot: (Int, Int) -> Bool
    let duplicateFunctionKeySlot: (Int, Int) -> Bool
    let updateFunctionKeySlot: (Int, String) -> Bool
    let loadGridDimensions: (String, Int) -> GridDimensions
    let saveGridDimensions: (String, GridDimensions) -> Void
    let openKeyboardScreen: () -> Void
    let openSettingsScreen: () -> Void
    let isSettingsScreenPresented: Bool
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
            .onChange(of: speechRecognition.latestRecognition) {
                handleLatestRecognizedTextChange()
            }
            .onChange(of: isSettingsScreenPresented) {
                guard !isSettingsScreenPresented else { return }
                reloadSelectedDocumentIfAvailable()
            }
            .onDisappear {
                handleMainScreenDisappear()
                mainGridAmbientSoundState.stopPlayback()
                popupDismissTask?.cancel()
            }
            .task(id: definedFunctionKeyCount) {
                updateVisibleBoxCountToFitDefinedButtons()
            }
            .task {
                await observeKeyboardFrameChanges()
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

                popupOverlay(
                    isSlotEditorPresented: editingSlotIndex != nil,
                    maskedScreenHeight: maskedScreenHeight
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 2)
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .compatibleNavigationBarVisibility(.visible)
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
                    Button {
                        ButtonClickFeedback.playIfEnabled()
                        openSettingsScreen()
                    } label: {
                        settingsToolbarButtonLabel
                    }
                    .buttonStyle(.plain)
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
            visibleGridDimensions: visibleGridDimensions,
            mainGridButtonSpacing: mainGridButtonSpacing,
            isGridEditModeEnabled: isGridEditModeEnabled,
            bleSendEnabled: mainGridButtonMode != .disabled,
            onButtonClick: { ButtonClickFeedback.playIfEnabled() },
            isHiddenEntry: isMainGridEntryHidden,
            isInteractiveWidgetEntry: isInteractiveMainGridWidgetEntry,
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
        Text(isPad ? "settings >" : ">")
            .font(.headline)
            .foregroundStyle((isGridEditModeEnabled || editingSlotIndex != nil) ? Color(white: 0.65) : .white)
            .frame(minWidth: isPad ? 92 : 44, minHeight: 44)
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
            visibleGridDimensions: visibleGridDimensions,
            isGridEditModeEnabled: isGridEditModeEnabled,
            boxFontSize: boxFontSize,
            minimumBoxFontSize: minimumBoxFontSize,
            maximumBoxFontSize: maximumBoxFontSize,
            speechRecognitionDisplayText: speechRecognitionDisplayText,
            speechRecognitionDisplayColor: speechRecognitionDisplayColor,
            isSpeechRecognitionEnabled: isSpkRecEnabled,
            isBluetoothConnected: ble.isConnected,
            mainGridButtonMode: mainGridButtonMode,
            displayMode: displayMode,
            displayModeButtonColor: displayModeButtonColor,
            fontControlColor: fontControlColor,
            speechRecognitionActiveColor: speechRecognitionActiveColor,
            bleSendActiveColor: bleSendActiveColor,
            onDecreaseRows: decreaseGridRows,
            onIncreaseRows: increaseGridRows,
            onDecreaseColumns: decreaseGridColumns,
            onIncreaseColumns: increaseGridColumns,
            onDecreaseBoxFontSize: decreaseBoxFontSize,
            onIncreaseBoxFontSize: increaseBoxFontSize,
            onResetBoxFontSize: resetBoxFontSize,
            onToggleSpeechRecognition: { isSpkRecEnabled.toggle() },
            onCycleMainGridButtonMode: cycleMainGridButtonMode,
            onStopSpeech: stopSpokenGridText,
            onAdvanceDisplayMode: { displayMode = displayMode.next() }
        )
    }

    private var slotEditorSection: some View {
        MainScreenSlotEditorOverlay(
            editingSlotText: $editingSlotText,
            editingSlotIndex: editingSlotIndex,
            gridDimensions: visibleGridDimensions,
            focusBinding: $isSlotEditorFocused,
            buttonSpacing: slotEditorButtonSpacing,
            helperButtonWidth: slotEditorHelperButtonWidth,
            onCancel: cancelSlotEditing,
            onCommit: commitSlotEditing,
            onSave: saveSlotEditing,
            onTest: testEditingSlotText,
            onCopy: showSlotCopiedPopup,
            onPaste: showSlotPastedPopup,
            onVisibilityChange: showSlotVisibilityPopup,
            onSelectPreviousButton: selectPreviousEditableSlot,
            onSelectNextButton: selectNextEditableSlot
        )
    }

    private func testEditingSlotText() {
        let actionText = editingSlotText.components(separatedBy: "::").first ?? editingSlotText
        let actionTokens = parsedActionTokens(from: actionText)

        for actionToken in actionTokens {
            if let clipboardText = targetClipboardTextForSendText(actionToken) {
                UIPasteboard.general.string = clipboardText
            }
        }

        let bluetoothTokens = actionTokens
            .filter { actionToken in
                targetDocumentNameForSendText(actionToken) == nil &&
                    targetURLForSendText(actionToken) == nil &&
                    targetSoundFilenameForSendText(actionToken) == nil &&
                    targetSpokenTextForSendText(actionToken) == nil &&
                    targetAppURLForSendText(actionToken) == nil &&
                    targetClipboardTextForSendText(actionToken) == nil &&
                    targetWidgetDescriptorForSendText(actionToken) == nil
            }
            .map(normalizedBluetoothSendText)

        guard !bluetoothTokens.isEmpty else {
            return
        }

        guard ble.isConnected else {
            alertTitle = "Bluetooth not connected"
            renameAlertMessage = "Bluetooth needs to be connected\nbefore sending data to the ESP32."
            return
        }

        guard bluetoothTokens.allSatisfy(isASCIIOnlyBluetoothText(_:)) else {
            showBluetoothEmojiBlockedPopup()
            return
        }

        for bluetoothToken in bluetoothTokens {
            ble.sendLine(bluetoothToken)
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

    private func showSlotVisibilityPopup(isHidden: Bool) {
        alertTitle = ""
        renameAlertMessage = isHidden ? "btn will\nbe hidden" : "btn will\nbe visible"
    }

    private func showSlotSavedPopup() {
        alertTitle = ""
        renameAlertMessage = "btn hasbeen\naved to file"
    }

    var mainGridButtonSpacing: CGFloat {
        let buttonCount = max(visibleGridDimensions.columns * visibleGridDimensions.rows, 1)
        let normalizedProgress = min(max(CGFloat(buttonCount - 1) / CGFloat(144 - 1), 0), 1)
        return mainGridButtonSpacingMaximum - ((mainGridButtonSpacingMaximum - mainGridButtonSpacingMinimum) * normalizedProgress)
    }

    var mainGridButtonCornerRadius: CGFloat {
        let buttonCount = max(visibleGridDimensions.columns * visibleGridDimensions.rows, 1)
        let normalizedProgress = min(max(CGFloat(buttonCount - 1) / CGFloat(144 - 1), 0), 1)
        return mainGridButtonCornerRadiusMaximum - ((mainGridButtonCornerRadiusMaximum - mainGridButtonCornerRadiusMinimum) * normalizedProgress)
    }

    private func handleSelectedDocumentDisplayNameChange() {
        restoreVisibleGridState()
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
            restoreVisibleGridState()
            return
        }

        loadFunctionKeys(selectedDocumentURL)
        restoreVisibleGridState()
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
    private func popupOverlay(
        isSlotEditorPresented: Bool,
        maskedScreenHeight: CGFloat
    ) -> some View {
        if let renameAlertMessage {
            let isSlotEditorTopPopup = isSlotEditorPresented && (
                alertTitle == "Bluetooth not connected" ||
                renameAlertMessage == "btn has been\nsaved to file"
            )

            VStack {
                if isSlotEditorTopPopup {
                    popupCard(message: renameAlertMessage)
                        .padding(.top, max(72, maskedScreenHeight * 0.18))
                } else if isSlotEditorPresented {
                    Spacer(minLength: 0)
                    popupCard(message: renameAlertMessage)
                } else {
                    Spacer()
                    popupCard(message: renameAlertMessage)
                }

                if isSlotEditorTopPopup {
                    Spacer(minLength: 0)
                } else if isSlotEditorPresented {
                    Spacer(minLength: max(32, maskedScreenHeight * 0.16))
                } else {
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
            .allowsHitTesting(false)
        }
    }

    private func popupCard(message: String) -> some View {
        VStack(spacing: 8) {
            if !alertTitle.isEmpty, alertTitle != "Alert" {
                Text(alertTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            Text(message)
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

    var minimumBoxFontSize: Double { 10 }

    var maximumBoxFontSize: Double { 200 }

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

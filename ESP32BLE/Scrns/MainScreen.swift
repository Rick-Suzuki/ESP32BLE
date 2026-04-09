import SwiftUI
import AVFAudio
import Combine
import Speech
import UIKit
//
private enum FunctionKeyDisplayMode: CaseIterable {
    case left
    case right
    case both

    func next() -> Self {
        switch self {
        case .left:
            return .right
        case .right:
            return .both
        case .both:
            return .left
        }
    }

    var title: String {
        switch self {
        case .left:
            return "Left cmd"
        case .right:
            return "Right text"
        case .both:
            return "Both texts"
        }
    }
}

struct MainScreen: View {
    // Easy-to-find styling controls for the main button grid.
    private let mainGridButtonSpacing: CGFloat = 10
    private let mainGridButtonCornerRadius: CGFloat = 30
    private let mainGridButtonBorderWidth: CGFloat = 2
  
	// Easy-to-find spacing for the slot editor controls row.
    private let slotEditorButtonSpacing: CGFloat = 5
    // Easy-to-find width for all slot editor helper buttons.
    private let slotEditorHelperButtonWidth: CGFloat = 58

    @AppStorage("speechRecognitionAutoOffMinutes") private var speechRecognitionAutoOffMinutes = 5
    private let allowedVisibleBoxCounts = [
        1, 2, 4, 6, 9, 12, 15, 16, 18, 20, 24, 28, 32, 36, 40, 42, 45, 48,
        50, 54, 56, 60, 63, 64, 70, 72, 80, 81, 84, 88, 90, 96, 99, 100
    ]
    private let displayModeButtonColor = Color(red: 0.05, green: 0.33, blue: 0.18)
    private let countControlColor = Color(red: 0.15, green: 0.72, blue: 0.22)
    private let fontControlColor = Color(red: 0.78, green: 0.68, blue: 0.12)
    private let speechRecognitionActiveColor = Color(red: 0.42, green: 0.12, blue: 0.12)
    private let bleSendActiveColor = Color(red: 0.55, green: 0.45, blue: 0.08)
    @State private var visibleBoxCount = 20
    @State private var isBLESendEnabled = true
    @State private var isSpkRecEnabled = false
    @State private var unmatchedSpeechText: String?
    @State private var speechRecognitionAutoOffTask: Task<Void, Never>?
    @StateObject private var speechRecognition = SpeechRecognitionManager()
    @ObservedObject var ble: BLEKeyboardManager
    @State private var displayMode: FunctionKeyDisplayMode = .both
    @State private var isEditingDocumentName = false
    @State private var documentNameDraft = ""
    @State private var renameAlertMessage: String?
    @State private var isGridEditModeEnabled = false
    @State private var activeDragIndex: Int?
    @State private var editingSlotIndex: Int?
    @State private var editingSlotText = ""
    @FocusState private var isDocumentNameFieldFocused: Bool
    @FocusState private var isSlotEditorFocused: Bool
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
            GeometryReader { geometry in
                let gridDimensions = gridDimensions(for: visibleBoxCount)
                let columns = Array(repeating: GridItem(.flexible(), spacing: mainGridButtonSpacing), count: gridDimensions.columns)
                let totalGridSpacing = mainGridButtonSpacing * CGFloat(max(gridDimensions.rows - 1, 0))
                let availableGridHeight = geometry.size.height.isFinite ? max(0, geometry.size.height - totalGridSpacing) : 0
                let buttonHeight = availableGridHeight / CGFloat(max(gridDimensions.rows, 1))
                let visibleEntries = Array(functionKeys.prefix(visibleBoxCount).enumerated())

                LazyVGrid(columns: columns, spacing: mainGridButtonSpacing) {
                    ForEach(visibleEntries, id: \.offset) { index, entry in
                        Button {
                            guard !isGridEditModeEnabled else {
                                return
                            }

                            ButtonClickFeedback.playIfEnabled()

                            guard isBLESendEnabled else {
                                return
                            }

                            guard ble.isConnected else {
                                print("Bluetooth not connected.")
                                return
                            }

                            guard !entry.sendTexts.isEmpty else {
                                return
                            }

                            logMainButtonPress(entry)

                            for sendText in entry.sendTexts {
                                ble.sendLine(sendText)
                            }
                        } label: {
                            mainGridButtonLabel(entry: entry, index: index, buttonHeight: buttonHeight)
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(
                            mainGridButtonDragGesture(
                                entry: entry,
                                index: index,
                                gridDimensions: gridDimensions
                            )
                        )
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.4)
                                .onEnded { _ in
                                    guard isGridEditModeEnabled else {
                                        return
                                    }

                                    beginSlotEditing(at: index)
                                }
                        )
                    }
                }
                .background(Color.black)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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
            ToolbarItem(placement: .topBarLeading) {
                Button("Keyboard") {
                    ButtonClickFeedback.playIfEnabled()
                    openKeyboardScreen()
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(toolbarButtonBackgroundColor(isEditingSlotActive: editingSlotIndex != nil, normalBackground: isGridEditModeEnabled ? Color.gray.opacity(0.3) : Color.gray.opacity(0.45)))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(toolbarButtonBorderColor(isEditingSlotActive: editingSlotIndex != nil), lineWidth: 1.5)
                }
                .clipShape(.rect(cornerRadius: 12))
                .contentShape(.rect)
                .disabled(isGridEditModeEnabled || editingSlotIndex != nil)
                .opacity(isGridEditModeEnabled || editingSlotIndex != nil ? 0.45 : 1)
            }

            ToolbarItem(placement: .principal) {
                documentTitle
                    .opacity(isGridEditModeEnabled || editingSlotIndex != nil ? 0.45 : 1)
                    .allowsHitTesting(!(isGridEditModeEnabled || editingSlotIndex != nil))
            }

            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        ButtonClickFeedback.playIfEnabled()
                        isGridEditModeEnabled.toggle()
                    } label: {
                        Text(isGridEditModeEnabled ? "done" : "edit")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(minWidth: 84, minHeight: 44)
                            .background(toolbarButtonBackgroundColor(isEditingSlotActive: editingSlotIndex != nil, normalBackground: editModeButtonBackgroundColor))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(toolbarButtonBorderColor(isEditingSlotActive: editingSlotIndex != nil), lineWidth: 1.5)
                            }
                            .clipShape(.rect(cornerRadius: 12))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(editingSlotIndex != nil)
                    .opacity(editingSlotIndex == nil ? 1 : 0.45)

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
                    .disabled(isGridEditModeEnabled || editingSlotIndex != nil)
                    .opacity(isGridEditModeEnabled || editingSlotIndex != nil ? 0.45 : 1)
                }
            }
        }
    }

    private var documentTitle: some View {
        HStack(spacing: 20) {
                Button {
                    ButtonClickFeedback.playIfEnabled()
                    selectPreviousDocument()
                } label: {
                Image(systemName: "triangle.fill")
                    .font(.system(size: 20))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 20, height: 20)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .disabled(currentFileNumber <= 1)

            Group {
                if isEditingDocumentName {
                    TextField("Filename", text: $documentNameDraft)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.done)
                        .focused($isDocumentNameFieldFocused)
                        .onSubmit(commitDocumentRename)
                } else {
                Button {
                    ButtonClickFeedback.playIfEnabled()
                    documentNameDraft = selectedDocumentDisplayName
                    isEditingDocumentName = true
                } label: {
                        Text(selectedDocumentDisplayName)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)

                Button {
                    ButtonClickFeedback.playIfEnabled()
                    selectNextDocument()
                } label: {
                Image(systemName: "triangle.fill")
                    .font(.system(size: 20))
                    .rotationEffect(.degrees(90))
                    .frame(width: 20, height: 20)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .disabled(currentFileNumber >= totalFileCount)
        }
    }

    private var settingsToolbarButtonLabel: some View {
        Text("settings >")
            .font(.headline)
            .foregroundStyle(.white)
            .frame(minWidth: 92, minHeight: 44)
            .background(
                toolbarButtonBackgroundColor(
                    isEditingSlotActive: editingSlotIndex != nil,
                    normalBackground: Color.gray.opacity(0.45)
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(toolbarButtonBorderColor(isEditingSlotActive: editingSlotIndex != nil), lineWidth: 1.5)
            }
            .clipShape(.rect(cornerRadius: 12))
            .contentShape(.rect)
    }

    private var displayModeButtonSection: some View {
        HStack {
            HStack(spacing: 12) {
                Button {
                    ButtonClickFeedback.playIfEnabled()
                    decreaseVisibleBoxCount()
                } label: {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 30))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(countControlColor)
                .disabled(visibleBoxCount == allowedVisibleBoxCounts.first)

                Text("num:\(visibleBoxCount)")
                    .font(.headline)
					.foregroundStyle(.white)
                    .frame(minWidth: 32)

                Button {
                    ButtonClickFeedback.playIfEnabled()
                    increaseVisibleBoxCount()
                } label: {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 30))
                        .rotationEffect(.degrees(90))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(countControlColor)
                .disabled(visibleBoxCount == allowedVisibleBoxCounts.last)
            }

            HStack(spacing: 12) {
                Button {
                    ButtonClickFeedback.playIfEnabled()
                    decreaseBoxFontSize()
                } label: {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 30))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(fontControlColor)
                .disabled(boxFontSize <= minimumBoxFontSize)

                Text("fnt:\(Int(boxFontSize))")
                    .font(.headline)
					.foregroundStyle(.white)
                    .frame(minWidth: 32)

                Button {
                    ButtonClickFeedback.playIfEnabled()
                    increaseBoxFontSize()
                } label: {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 30))
                        .rotationEffect(.degrees(90))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(fontControlColor)
                .disabled(boxFontSize >= maximumBoxFontSize)
            }

            Spacer(minLength: 12)

            Text(speechRecognitionDisplayText)
                .font(.body)
                .foregroundStyle(speechRecognitionDisplayColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(minHeight: 38)
                .background(Color.black.opacity(0.8))
                .clipShape(.rect(cornerRadius: 6))
                .frame(maxWidth: 360)

            Spacer(minLength: 12)

            Button {
                isSpkRecEnabled.toggle()
            } label: {
                Text(isSpkRecEnabled ? "spk rec on" : "spk rec off")
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(isSpkRecEnabled ? speechRecognitionActiveColor : Color.gray.opacity(0.45))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSpkRecEnabled ? speechRecognitionActiveColor : Color.gray.opacity(0.4), lineWidth: 2)
            }
            .clipShape(.rect(cornerRadius: 12))
            .frame(maxWidth: 150)

            Button {
                isBLESendEnabled.toggle()
            } label: {
                Text(isBLESendEnabled ? "btn active" : "disabled")
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(isBLESendEnabled ? bleSendActiveColor : Color.gray.opacity(0.45))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isBLESendEnabled ? bleSendActiveColor : Color.gray.opacity(0.4), lineWidth: 2)
            }
            .clipShape(.rect(cornerRadius: 12))
            .frame(maxWidth: 150)

            Button {
                displayMode = displayMode.next()
            } label: {
                displayModeLabel
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(displayModeButtonColor)
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(displayModeButtonColor, lineWidth: 2)
            }
            .clipShape(.rect(cornerRadius: 12))
            .frame(maxWidth: 180)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.thinMaterial)
        .clipShape(.rect(cornerRadius: 16))
    }

    private var displayModeLabel: some View {
        VStack(spacing: 2) {
            Text(displayMode.title)
        }
    }

    private var editModeButtonBackgroundColor: Color {
        if editingSlotIndex != nil {
            return Color.gray.opacity(0.3)
        }

        return isGridEditModeEnabled ? Color.blue : Color.gray.opacity(0.45)
    }

    private var editModeButtonBorderColor: Color {
        if editingSlotIndex != nil {
            return Color.gray.opacity(0.35)
        }

        return isGridEditModeEnabled ? Color.blue : Color.gray.opacity(0.5)
    }

    private func toolbarButtonBackgroundColor(isEditingSlotActive: Bool, normalBackground: Color) -> Color {
        isEditingSlotActive ? Color.gray.opacity(0.3) : normalBackground
    }

    private func toolbarButtonBorderColor(isEditingSlotActive: Bool) -> Color {
        isEditingSlotActive ? Color.gray.opacity(0.35) : Color.gray.opacity(0.5)
    }

    private var slotEditorSection: some View {
        GeometryReader { geometry in
            VStack(spacing: slotEditorButtonSpacing) {
                HStack(spacing: slotEditorButtonSpacing) {
                    Button("cancel") {
                        ButtonClickFeedback.playIfEnabled()
                        cancelSlotEditing()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(minWidth: 101)
                    .frame(minHeight: 44)
                    .background(Color.gray.opacity(0.45))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
                    }
                    .clipShape(.rect(cornerRadius: 12))

                    SlotEditorTextField(text: $editingSlotText, placeholder: "edit button text") {
                        commitSlotEditing()
                    }
                    .frame(width: geometry.size.width.isFinite ? max(0, geometry.size.width * 0.36) : 0, height: 36)
                    .focused($isSlotEditorFocused)

                    Button {
                        ButtonClickFeedback.playIfEnabled()
                        editingSlotText = ""
                        isSlotEditorFocused = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.red)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Button("test") {
                        ButtonClickFeedback.playIfEnabled()
                        guard ble.isConnected else {
                            print("Bluetooth not connected.")
                            return
                        }

                        ble.sendString(editingSlotText)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(minWidth: 71)
                    .frame(minHeight: 44)
                    .background(Color(red: 0.0, green: 0.5, blue: 0.0))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(red: 0.0, green: 0.5, blue: 0.0), lineWidth: 1.5)
                    }
                    .clipShape(.rect(cornerRadius: 12))

                    Button("save") {
                        ButtonClickFeedback.playIfEnabled()
                        commitSlotEditing()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(minWidth: 71)
                    .frame(minHeight: 44)
                    .background(Color.blue)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue, lineWidth: 1.5)
                    }
                    .clipShape(.rect(cornerRadius: 12))
                }

                HStack(spacing: slotEditorButtonSpacing) {
                    slotEditorInsertButton("ctl:")
                    slotEditorInsertButton("sh:")
                    slotEditorInsertButton("op:")
                    slotEditorInsertButton("cm:")
                    slotEditorInsertButton("F")
                    slotEditorInsertButton("F1::")
                    slotEditorInsertButton(":")
                    slotEditorInsertButton("::")
                    slotEditorInsertButton("kp")
                    slotEditorBackspaceButton()
                }

                HStack(spacing: slotEditorButtonSpacing) {
                    slotEditorInsertButton("0")
                    slotEditorInsertButton("1")
                    slotEditorInsertButton("2")
                    slotEditorInsertButton("3")
                    slotEditorInsertButton("4")
                    slotEditorInsertButton("5")
                    slotEditorInsertButton("6")
                    slotEditorInsertButton("7")
                    slotEditorInsertButton("8")
                    slotEditorInsertButton("9")
                }

                HStack(spacing: slotEditorButtonSpacing) {
                    slotEditorInsertButton(systemImage: "triangle.fill", rotationDegrees: 0, insertedText: "UP::")
                    slotEditorInsertButton(systemImage: "triangle.fill", rotationDegrees: 180, insertedText: "DOWN::")
                    slotEditorInsertButton(systemImage: "triangle.fill", rotationDegrees: -90, insertedText: "LEFT::")
                    slotEditorInsertButton(systemImage: "triangle.fill", rotationDegrees: 90, insertedText: "RIGHT::")
                    slotEditorInsertButton("+")
                    slotEditorInsertButton("_")
                    slotEditorInsertButton("/")
                    slotEditorInsertButton("*")
                    slotEditorInsertButton("ESC:")
                    slotEditorInsertButton("RET:")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.7))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.35), lineWidth: 1)
            }
            .clipShape(.rect(cornerRadius: 12))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(height: 192)
    }

    private func slotEditorInsertButton(_ text: String) -> some View {
        Button(text) {
            ButtonClickFeedback.playIfEnabled()
            editingSlotText.append(text)
            isSlotEditorFocused = true
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .frame(width: slotEditorHelperButtonWidth, height: 44)
        .background(Color.black)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white, lineWidth: 2)
        }
        .clipShape(.rect(cornerRadius: 12))
    }

    private func slotEditorInsertButton(systemImage: String, rotationDegrees: Double, insertedText: String) -> some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            editingSlotText.append(insertedText)
            isSlotEditorFocused = true
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .rotationEffect(.degrees(rotationDegrees))
                .foregroundStyle(.white)
                .frame(width: slotEditorHelperButtonWidth, height: 44)
        }
        .buttonStyle(.plain)
        .background(Color.black)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white, lineWidth: 2)
        }
        .clipShape(.rect(cornerRadius: 12))
    }

    private func slotEditorBackspaceButton() -> some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            guard !editingSlotText.isEmpty else {
                isSlotEditorFocused = true
                return
            }

            editingSlotText.removeLast()
            isSlotEditorFocused = true
        } label: {
            Image(systemName: "delete.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: slotEditorHelperButtonWidth, height: 44)
        }
        .buttonStyle(.plain)
        .background(Color(red: 0.0, green: 0.2, blue: 0.45))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white, lineWidth: 2)
        }
        .clipShape(.rect(cornerRadius: 12))
    }

    private func buttonTitle(for entry: FunctionKeyEntry) -> String {
        guard entry.displayUsesAlternateText else {
            return displayText(from: entry.rawLine)
        }

        let alternateDisplayText = resolvedAlternateDisplayText(for: entry)

        switch displayMode {
        case .left:
            return displayText(from: entry.primaryDisplayText)
        case .right:
            return displayText(from: alternateDisplayText)
        case .both:
            return "\(displayText(from: entry.primaryDisplayText))\n\(displayText(from: alternateDisplayText))"
        }
    }

    private func displayText(from text: String) -> String {
        text
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")
    }

    private func resolvedAlternateDisplayText(for entry: FunctionKeyEntry) -> String {
        if let alternateDisplayText = entry.alternateDisplayText {
            return alternateDisplayText
        }

        let components = entry.rawLine.components(separatedBy: "::")
        guard components.count >= 2 else {
            return entry.rawLine
        }

        let rawRightText = components.dropFirst().joined(separator: "::").trimmingCharacters(in: .whitespacesAndNewlines)
        let rightComponents = rawRightText.components(separatedBy: ":")

        if let firstComponent = rightComponents.first,
           firstComponent.count == 1,
           let manualColorCode = firstComponent.lowercased().first,
           "lwgborypk".contains(manualColorCode) {
            let remainingText = rightComponents.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
            return remainingText.isEmpty ? rawRightText : remainingText
        }

        return rawRightText
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

    private func logMainButtonPress(_ entry: FunctionKeyEntry) {
        let leftText = entry.sendTexts.joined(separator: ":")
        let rightText = entry.alternateDisplayText ?? ""
        print("Main button pressed. left: [\(leftText)] right: [\(rightText)]")
    }

    private func buttonBackgroundColor(for entry: FunctionKeyEntry) -> Color {
        if entry.isBlankPlaceholder {
            return .black
        }

        switch entry.buttonColorCode {
        case "l":
            return Color.black.opacity(0.4)
        case "w":
            return Color.white.opacity(0.4)
        case "g":
            return Color.green.opacity(0.4)
        case "b":
            return Color.blue.opacity(0.4)
        case "o":
            return Color.orange.opacity(0.4)
        case "r", "dest":
            return Color.red.opacity(entry.buttonColorCode == "r" ? 0.4 : 0.6)
        case "y":
            return Color.yellow.opacity(0.4)
        case "p", "pos":
            return Color.purple.opacity(entry.buttonColorCode == "p" ? 0.4 : 0.6)
        case "k":
            return Color.pink.opacity(0.6)
        case "warning":
            return Color.orange.opacity(0.6)
        case "actions":
            return Color.green.opacity(0.6)
        case "info":
            return Color.blue.opacity(0.6)
        default:
            return entry.alternateDisplayText == nil ? .black : Color(white: 0.12)
        }
    }

    private func buttonTextColor(for entry: FunctionKeyEntry) -> Color {
        if entry.buttonColorCode == "w" {
            return .black
        }

        if entry.buttonColorCode == nil, entry.alternateDisplayText != nil {
            return .yellow
        }

        return .white
    }

    private func mainGridButtonLabel(entry: FunctionKeyEntry, index: Int, buttonHeight: CGFloat) -> some View {
        let backgroundColor = buttonBackgroundColor(for: entry)
        let title = buttonTitle(for: entry)
        let textColor = buttonTextColor(for: entry)

        return ZStack {
            RoundedRectangle(cornerRadius: mainGridButtonCornerRadius, style: .continuous)
                .fill(backgroundColor)

            Text(title)
                .font(.system(size: boxFontSize, weight: .semibold))
                .foregroundStyle(textColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
        }
        .frame(maxWidth: .infinity, minHeight: buttonHeight, maxHeight: buttonHeight)
        .background(Color.clear)
        .overlay(buttonOverlay(for: entry, index: index))
        .contentShape(.rect(cornerRadius: mainGridButtonCornerRadius))
    }

    private func mainGridButtonDragGesture(
        entry: FunctionKeyEntry,
        index: Int,
        gridDimensions: (columns: Int, rows: Int)
    ) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { _ in
                guard isGridEditModeEnabled,
                      editingSlotIndex == nil,
                      !entry.isBlankPlaceholder else {
                    return
                }

                activeDragIndex = index
            }
            .onEnded { value in
                handleEditDragEnded(
                    from: index,
                    translation: value.translation,
                    gridDimensions: gridDimensions
                )
            }
    }

    @ViewBuilder
    private func buttonOverlay(for entry: FunctionKeyEntry, index: Int) -> some View {
        if shouldShowBorder(for: entry) {
            RoundedRectangle(cornerRadius: mainGridButtonCornerRadius, style: .continuous)
                .stroke(Color.white, lineWidth: mainGridButtonBorderWidth)
        }

        if isGridEditModeEnabled, activeDragIndex == index, !entry.isBlankPlaceholder {
            RoundedRectangle(cornerRadius: mainGridButtonCornerRadius, style: .continuous)
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
        }
    }

    private func shouldShowBorder(for entry: FunctionKeyEntry) -> Bool {
        !(entry.isBlankPlaceholder || isEmptyButtonEntry(entry))
    }

    private func isEmptyButtonEntry(_ entry: FunctionKeyEntry) -> Bool {
        entry.sendTexts.isEmpty && entry.alternateDisplayText == nil && entry.rawLine.isEmpty
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

    private func updateVisibleBoxCountToFitDefinedButtons() {
        let requiredBoxCount = max(definedFunctionKeyCount, 1)
        visibleBoxCount = allowedVisibleBoxCounts.first(where: { $0 >= requiredBoxCount }) ?? allowedVisibleBoxCounts.last ?? requiredBoxCount
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

    private var minimumBoxFontSize: Double { 12 }

    private var maximumBoxFontSize: Double { 100 }

    private func decreaseVisibleBoxCount() {
        guard let currentIndex = allowedVisibleBoxCounts.firstIndex(of: visibleBoxCount),
              currentIndex > 0 else {
            return
        }

        let nextCount = allowedVisibleBoxCounts[currentIndex - 1]

        if resizeVisibleBoxCount(nextCount) {
            visibleBoxCount = nextCount
        }
    }

    private func increaseVisibleBoxCount() {
        guard let currentIndex = allowedVisibleBoxCounts.firstIndex(of: visibleBoxCount),
              currentIndex < allowedVisibleBoxCounts.count - 1 else {
            return
        }

        let nextCount = allowedVisibleBoxCounts[currentIndex + 1]

        if resizeVisibleBoxCount(nextCount) {
            visibleBoxCount = nextCount
        }
    }

    private func decreaseBoxFontSize() {
        updateDocumentFontSize(max(minimumBoxFontSize, boxFontSize - 2))
    }

    private func increaseBoxFontSize() {
        updateDocumentFontSize(min(maximumBoxFontSize, boxFontSize + 2))
    }

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

    private func commitDocumentRename() {
        let proposedName = documentNameDraft

        if let alertMessage = renameDocument(proposedName) {
            renameAlertMessage = alertMessage
            return
        }

        documentNameDraft = selectedDocumentDisplayName
        isEditingDocumentName = false
    }

    private func cancelDocumentRename() {
        documentNameDraft = selectedDocumentDisplayName
        isEditingDocumentName = false
        isDocumentNameFieldFocused = false
    }

    private func beginSlotEditing(at index: Int) {
        guard index >= 0, index < visibleBoxCount else {
            return
        }

        activeDragIndex = nil
        editingSlotIndex = index
        editingSlotText = editableText(for: functionKeys[index])
        isSlotEditorFocused = true
    }

    private func commitSlotEditing() {
        guard let editingSlotIndex else {
            return
        }

        _ = updateFunctionKeySlot(editingSlotIndex, editingSlotText)
        cancelSlotEditing()
    }

    private func cancelSlotEditing() {
        editingSlotIndex = nil
        editingSlotText = ""
        isSlotEditorFocused = false
    }

    private func editableText(for entry: FunctionKeyEntry) -> String {
        if entry.isBlankPlaceholder || isEmptyButtonEntry(entry) {
            return ""
        }

        return entry.rawLine
    }

    private func handleEditDragEnded(
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

    private func targetIndexForEditDrag(
        from sourceIndex: Int,
        translation: CGSize,
        gridDimensions: (columns: Int, rows: Int)
    ) -> Int? {
        let horizontalDistance = translation.width
        let verticalDistance = translation.height

        guard max(abs(horizontalDistance), abs(verticalDistance)) >= 24 else {
            return nil
        }

        if abs(horizontalDistance) > abs(verticalDistance) {
            let step = horizontalDistance > 0 ? 1 : -1
            let targetIndex = sourceIndex + step
            let sourceRow = sourceIndex / gridDimensions.columns
            let targetRow = targetIndex / gridDimensions.columns

            guard targetIndex >= 0,
                  targetIndex < visibleBoxCount,
                  sourceRow == targetRow else {
                return nil
            }

            return targetIndex
        }

        let step = verticalDistance > 0 ? gridDimensions.columns : -gridDimensions.columns
        let targetIndex = sourceIndex + step

        guard targetIndex >= 0, targetIndex < visibleBoxCount else {
            return nil
        }

        return targetIndex
    }
}

private struct SlotEditorTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.borderStyle = .none
        textField.returnKeyType = .default
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.smartQuotesType = .no
        textField.smartDashesType = .no
        textField.smartInsertDeleteType = .no
        textField.delegate = context.coordinator
        textField.placeholder = placeholder
        textField.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        textField.textColor = .white
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.lightGray]
        )
        textField.layer.cornerRadius = 8
        textField.layer.borderWidth = 1
        textField.layer.borderColor = UIColor.darkGray.cgColor
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        textField.leftViewMode = .always
        textField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        textField.rightViewMode = .always
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        if textField.text != text {
            textField.text = text
        }

        textField.placeholder = placeholder

        if textField.isFirstResponder, !context.coordinator.didPlaceCursorAtEnd {
            let endOfDocument = textField.endOfDocument
            textField.selectedTextRange = textField.textRange(from: endOfDocument, to: endOfDocument)
            context.coordinator.didPlaceCursorAtEnd = true
        } else if !textField.isFirstResponder {
            context.coordinator.didPlaceCursorAtEnd = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        let onSubmit: () -> Void
        var didPlaceCursorAtEnd = false

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            _text = text
            self.onSubmit = onSubmit
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            text = textField.text ?? ""
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            ButtonClickFeedback.playIfEnabled()
            return true
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            ButtonClickFeedback.playIfEnabled()
            onSubmit()
            return false
        }
    }
}
private struct SpeechRecognitionEvent: Equatable {
    let id = UUID()
    let text: String
}

private enum SpeechRecognitionDisplayState: Equatable {
    case disabled
    case recognizing
    case recognized(String)
}

@MainActor
private final class SpeechRecognitionManager: NSObject, ObservableObject {
    @Published private(set) var latestRecognition: SpeechRecognitionEvent?
    @Published private(set) var displayState: SpeechRecognitionDisplayState = .disabled

    private let audioEngine = AVAudioEngine()
    private let audioSession = AVAudioSession.sharedInstance()
    private let silenceDuration: Duration = .milliseconds(700)
    private let restartDelay: Duration = .milliseconds(150)

    private var speechRecognizer = SFSpeechRecognizer(locale: .current)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTask: Task<Void, Never>?
    private var restartTask: Task<Void, Never>?
    private var wantsListening = false
    private var latestTranscript = ""
    private var activeSessionID: UUID?
    private var isInputTapInstalled = false

    override init() {
        super.init()
        speechRecognizer?.delegate = self
    }

    func setListeningEnabled(_ isEnabled: Bool) {
        wantsListening = isEnabled

        if isEnabled {
            restartTask?.cancel()
            Task {
                await startListeningIfNeeded()
            }
        } else {
            stopListening()
        }
    }

    private func startListeningIfNeeded() async {
        guard wantsListening, activeSessionID == nil else {
            return
        }

        guard await hasRequiredPermissions() else {
            wantsListening = false
            return
        }

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            displayState = .recognizing
            return
        }

        do {
            try configureAudioSession()
            try startRecognitionSession(using: speechRecognizer)
        } catch {
            finishRecognitionSession(shouldRestart: wantsListening)
        }
    }

    private func stopListening() {
        restartTask?.cancel()
        finishRecognitionSession(shouldRestart: false)
    }

    private func hasRequiredPermissions() async -> Bool {
        let speechAuthorized = await requestSpeechAuthorizationIfNeeded()
        guard speechAuthorized else {
            return false
        }

        return await requestMicrophonePermissionIfNeeded()
    }

    private func requestSpeechAuthorizationIfNeeded() async -> Bool {
        let currentStatus = SFSpeechRecognizer.authorizationStatus()

        switch currentStatus {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            let status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { authorizationStatus in
                    continuation.resume(returning: authorizationStatus)
                }
            }

            return status == .authorized
        @unknown default:
            return false
        }
    }

    private func requestMicrophonePermissionIfNeeded() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { isGranted in
                    continuation.resume(returning: isGranted)
                }
            }
        @unknown default:
            return false
        }
    }

    private func configureAudioSession() throws {
        try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func startRecognitionSession(using speechRecognizer: SFSpeechRecognizer) throws {
        finishRecognitionSession(shouldRestart: false)

        let sessionID = UUID()
        activeSessionID = sessionID
        latestTranscript = ""
        displayState = .recognizing

        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest.shouldReportPartialResults = true

        if speechRecognizer.supportsOnDeviceRecognition {
            recognitionRequest.requiresOnDeviceRecognition = true
        }

        self.recognitionRequest = recognitionRequest

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        if isInputTapInstalled {
            inputNode.removeTap(onBus: 0)
            isInputTapInstalled = false
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        isInputTapInstalled = true

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor [weak self] in
                self?.handleRecognitionCallback(result: result, error: error, sessionID: sessionID)
            }
        }
    }

    private func handleRecognitionCallback(
        result: SFSpeechRecognitionResult?,
        error: Error?,
        sessionID: UUID
    ) {
        guard activeSessionID == sessionID else {
            return
        }

        if let result {
            latestTranscript = normalizedTranscript(from: result.bestTranscription.formattedString)
            scheduleSilenceCommit(for: sessionID)

            if result.isFinal {
                commitTranscriptIfNeeded()
                finishRecognitionSession(shouldRestart: wantsListening)
            }

            return
        }

        if error != nil {
            finishRecognitionSession(shouldRestart: wantsListening)
        }
    }

    private func scheduleSilenceCommit(for sessionID: UUID) {
        let silenceDuration = self.silenceDuration

        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: silenceDuration)
            } catch {
                return
            }

            await MainActor.run {
                self?.handleSilenceTimeout(for: sessionID)
            }
        }
    }

    private func handleSilenceTimeout(for sessionID: UUID) {
        guard activeSessionID == sessionID else {
            return
        }

        commitTranscriptIfNeeded()
        finishRecognitionSession(shouldRestart: wantsListening)
    }

    private func commitTranscriptIfNeeded() {
        guard !latestTranscript.isEmpty else {
            return
        }

        latestRecognition = SpeechRecognitionEvent(text: latestTranscript)
        displayState = .recognized(latestTranscript)
    }

    private func finishRecognitionSession(shouldRestart: Bool) {
        silenceTask?.cancel()
        silenceTask = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }

        if isInputTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isInputTapInstalled = false
        }

        latestTranscript = ""
        activeSessionID = nil

        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)

        if !wantsListening {
            displayState = .disabled
        }

        guard shouldRestart, wantsListening else {
            return
        }

        let restartDelay = self.restartDelay
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            do {
                try await Task.sleep(for: restartDelay)
            } catch {
                return
            }

            await self?.startListeningIfNeeded()
        }
    }

    private func normalizedTranscript(from text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

extension SpeechRecognitionManager: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        guard !available else {
            if wantsListening {
                restartTask?.cancel()
                restartTask = Task { [weak self] in
                    await self?.startListeningIfNeeded()
                }
            }

            return
        }

        finishRecognitionSession(shouldRestart: false)
    }
}

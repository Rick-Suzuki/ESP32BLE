import SwiftUI
import UIKit

private enum SettingsFocusField: Hashable {
    case sendText
}

struct SettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("speechRecognitionAutoOffMinutes") private var speechRecognitionAutoOffMinutes = 5
    @AppStorage("sendControlABeforeText") private var sendControlABeforeText = false
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
    let deleteDocument: (URL) -> Void
    let duplicateDocument: (URL) -> Void
    let canDeleteDocuments: Bool
    @Binding var bleTextToSend: String
    @State private var bleTextSelection: TextSelection?
    @State private var documentEditorText = ""
    @State private var documentEditorFontSize: CGFloat = 18
    @State private var isLoadingDocumentText = false
    @State private var isDocumentEditorFocused = false
    @State private var loadedDocumentName = ""
    @State private var savedDocumentEditorText = ""
    @State private var imageNameSliderValue = 0.5
    @State private var opacitySliderValue = 0.5
    @AppStorage(ButtonClickFeedback.preferenceKey) private var isButtonClickEnabled = true
    @FocusState private var focusedField: SettingsFocusField?

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
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("main") {
                    ButtonClickFeedback.playIfEnabled()
                    saveAndReturnToMain()
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(minWidth: 92, minHeight: 44)
                .background(Color.gray.opacity(0.45))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
                }
                .clipShape(.rect(cornerRadius: 12))
                .contentShape(.rect)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("new") {
                    ButtonClickFeedback.playIfEnabled()
                    createNewDocument()
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(minWidth: 92, minHeight: 44)
                .background(Color.green.opacity(0.5))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
                }
                .clipShape(.rect(cornerRadius: 12))
                .contentShape(.rect)
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
        }
        .onChange(of: documentEditorText) {
            guard !isLoadingDocumentText else { return }
            saveCurrentDocumentText()
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
        }
        .onChange(of: keepScreenAwake) {
            UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
        }
    }

    private func documentTableWidth(for availableWidth: CGFloat) -> CGFloat {
        let safeWidth = availableWidth.isFinite ? max(0, availableWidth) : 0
        let widthRatio = safeWidth > 900 ? 0.184 : 0.16
        let maximumWidth: CGFloat = safeWidth > 900 ? 260 : 220
        return min(max(safeWidth * widthRatio, 140), maximumWidth)
    }

    private var editableDocumentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PlainDocumentEditor(
                text: $documentEditorText,
                fontSize: $documentEditorFontSize,
                isFocused: $isDocumentEditorFocused
            )
                .background(Color.black.opacity(0.55))
                .clipShape(.rect(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .background(Color.black)
        .overlay {
            Rectangle()
                .stroke(Color.white, lineWidth: 1)
        }
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 8) {
                fontSizeControls
                undoButton
            }
            .padding(8)
        }
        .clipShape(.rect(cornerRadius: 0))
    }

    private var fontSizeControls: some View {
        HStack(spacing: 8) {
            Button {
                documentEditorFontSize = max(10, documentEditorFontSize - 1)
            } label: {
                Image(systemName: "triangle.fill")
                    .font(.system(size: 16))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 18, height: 18)
                    .padding(8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .contentShape(.rect)

            Text("font:\(Int(documentEditorFontSize))")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            Button {
                documentEditorFontSize = min(40, documentEditorFontSize + 1)
            } label: {
                Image(systemName: "triangle.fill")
                    .font(.system(size: 16))
                    .rotationEffect(.degrees(90))
                    .frame(width: 18, height: 18)
                    .padding(8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .contentShape(.rect)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .background(Color.black.opacity(0.5))
        .clipShape(.rect(cornerRadius: 10))
    }

    private var undoButton: some View {
        Button("undo") {
            ButtonClickFeedback.playIfEnabled()
            documentEditorText = savedDocumentEditorText
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.gray.opacity(0.45))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.5), lineWidth: 1)
        }
        .clipShape(.rect(cornerRadius: 8))
        .disabled(documentEditorText == savedDocumentEditorText)
        .opacity(documentEditorText == savedDocumentEditorText ? 0.35 : 1)
    }

    private var availableDevicesContent: some View {
        HStack(alignment: .top, spacing: 32) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text("ESP32")
                        .font(.headline)

                    Button("Disconnect") {
                        ButtonClickFeedback.playIfEnabled()
                        ble.disconnect()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!ble.isConnected)
                }

                if ble.discoveredDevices.isEmpty {
                    Text("No ESP32 devices found yet")
                        .foregroundStyle(.secondary)
                }

                ForEach(ble.discoveredDevices) { device in
                    Button {
                        ButtonClickFeedback.playIfEnabled()
                        ble.selectedPeripheralID = device.id
                        if !ble.isConnected {
                            ble.connectToSelectedDevice()
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                VStack {
                                    Text(device.displayName)
                                        .font(.body)
                                }
                            }
                            Spacer()

                            if ble.selectedPeripheralID == device.id {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                        .padding(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(ble.selectedPeripheralID == device.id ? .blue.opacity(0.15) : .clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(ble.isConnected && ble.selectedPeripheralID != device.id)
                    .opacity(ble.isConnected && ble.selectedPeripheralID != device.id ? 0.45 : 1)
                }

            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 12) {
                settingsPlaceholderSlider(title: "image name", value: $imageNameSliderValue)
                settingsPlaceholderSlider(title: "opacity: 0.5", value: $opacitySliderValue)

                HStack(spacing: 18) {
                    sleepWakeButton
                    buttonClickToggleButton
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var sleepWakeButton: some View {
        Button(ble.isConnected && keepScreenAwake ? "wake" : "sleep") {
            guard ble.isConnected else { return }
            ButtonClickFeedback.playIfEnabled()
            keepScreenAwake.toggle()
        }
        .buttonStyle(.plain)
        .font(.headline)
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(sleepWakeButtonBackgroundColor)
        .clipShape(.rect(cornerRadius: 18))
        .disabled(!ble.isConnected)
    }

    private var sleepWakeButtonBackgroundColor: Color {
        guard ble.isConnected else {
            return Color.gray.opacity(0.5)
        }

        if keepScreenAwake {
            return Color(red: 0.45, green: 0.0, blue: 0.0)
        }

        return Color(red: 0.0, green: 0.25, blue: 0.55)
    }

    private var buttonClickToggleButton: some View {
        Button(isButtonClickEnabled ? "btn click" : "btn off") {
            let willEnableButtonClicks = !isButtonClickEnabled
            isButtonClickEnabled = willEnableButtonClicks

            if willEnableButtonClicks {
                ButtonClickFeedback.playIfEnabled()
            }
        }
        .buttonStyle(.plain)
        .font(.headline)
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isButtonClickEnabled ? Color.blue.opacity(0.5) : Color.gray.opacity(0.5))
        .clipShape(.rect(cornerRadius: 18))
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

    private func settingsPlaceholderSlider(title: String, value: Binding<Double>) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)

            Slider(value: value, in: 0...1)
                .tint(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var sendTextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button("del") {
                    ButtonClickFeedback.playIfEnabled()
                    bleTextToSend = ""
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(bleTextToSend.isEmpty)

                TextField("Text to send", text: $bleTextToSend, selection: $bleTextSelection)
                    .focused($focusedField, equals: .sendText)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(sendEnteredText)

                Button("tab") {
                    ButtonClickFeedback.playIfEnabled()
                    insertTextAtCursor("\\n")
                }
                .buttonStyle(.bordered)

                Button("return") {
                    ButtonClickFeedback.playIfEnabled()
                    insertTextAtCursor("\\n")
                }
                .buttonStyle(.bordered)

                Button("Send") {
                    ButtonClickFeedback.playIfEnabled()
                    sendEnteredText()
                }
                .buttonStyle(.borderedProminent)
                .disabled(bleTextToSend.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial)
        .clipShape(.rect(cornerRadius: 16))
    }

    private var documentTableSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            List {
                ForEach(documentFiles, id: \.path) { fileURL in
                    documentRow(for: fileURL)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(.clear)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.bottom)
        .background(Color.black)
        .overlay {
            Rectangle()
                .stroke(Color.white, lineWidth: 1)
        }
        .clipShape(.rect(cornerRadius: 0))
    }

    private var customKeyboardTimingSection: some View {
        VStack(alignment: .center, spacing: 5) {
            HStack(spacing: 12) {
                Text("custom kb timing")
                    .font(.headline)

                Button("set & test") {
                    ButtonClickFeedback.playIfEnabled()
                    sendKeyboardTimingCommand()
                    ble.sendString("Hello World! Let's go. (test) 1!2\"3#4$5%6&7'8(9)")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.red.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 2)
                {
                    sliderRow(
                        title: "on",
                        value: $keyboardTimingOnMs,
                        range: 0...1000
                    )

                    sliderRow(
                        title: "off",
                        value: $keyboardTimingOffMs,
                        range: 0...3000
                    )

                    speechRecognitionAutoOffRow
                }
                .frame(maxWidth: 520, alignment: .leading)

                Spacer(minLength: 0)
            }
        }
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

    private func sendEnteredText() {
        let trimmedText = bleTextToSend.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedText.isEmpty else {
            return
        }

        guard ble.isConnected else {
            print("Bluetooth not connected.")
            return
        }

        if sendControlABeforeText {
            ble.sendLine("ca")
        }

        print("Settings text sent: [\(trimmedText)]")
        ble.sendString(trimmedText)
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

    private func nextAvailableNewDocumentURL() -> URL? {
        let directoryURL: URL
        if let existingDocumentURL = documentFiles.first {
            directoryURL = existingDocumentURL.deletingLastPathComponent()
        } else if let selectedDocumentFileURL {
            directoryURL = selectedDocumentFileURL.deletingLastPathComponent()
        } else {
            guard let defaultDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return nil
            }
            directoryURL = defaultDirectoryURL
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

    private func sendKeyboardTimingCommand() {
        ble.sendKeyboardTiming(onMs: Int(keyboardTimingOnMs), offMs: Int(keyboardTimingOffMs))
    }

    private func insertTextAtCursor(_ insertedText: String) {
        guard let selection = bleTextSelection else {
            bleTextToSend.append(insertedText)
            bleTextSelection = TextSelection(insertionPoint: bleTextToSend.endIndex)
            return
        }

        switch selection.indices {
        case .selection(let range):
            let lowerOffset = bleTextToSend.distance(from: bleTextToSend.startIndex, to: range.lowerBound)
            let upperOffset = bleTextToSend.distance(from: bleTextToSend.startIndex, to: range.upperBound)
            let lowerBound = bleTextToSend.index(bleTextToSend.startIndex, offsetBy: lowerOffset)
            let upperBound = bleTextToSend.index(bleTextToSend.startIndex, offsetBy: upperOffset)

            bleTextToSend.replaceSubrange(lowerBound..<upperBound, with: insertedText)

            let insertionOffset = lowerOffset + insertedText.count
            let insertionPoint = bleTextToSend.index(bleTextToSend.startIndex, offsetBy: insertionOffset)
            bleTextSelection = TextSelection(insertionPoint: insertionPoint)
        case .multiSelection:
            bleTextToSend.append(insertedText)
            bleTextSelection = TextSelection(insertionPoint: bleTextToSend.endIndex)
        @unknown default:
            bleTextToSend.append(insertedText)
            bleTextSelection = TextSelection(insertionPoint: bleTextToSend.endIndex)
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

private struct PlainDocumentEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var fontSize: CGFloat
    @Binding var isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused)
    }

    func makeUIView(context: Context) -> NoWrapDocumentTextView {
        let textView = NoWrapDocumentTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textColor = .white
        textView.tintColor = .white
        textView.keyboardAppearance = .dark
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.isScrollEnabled = true
        textView.alwaysBounceHorizontal = true
        textView.alwaysBounceVertical = true
        textView.showsHorizontalScrollIndicator = true
        textView.showsVerticalScrollIndicator = true
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byClipping
        textView.textContainer.widthTracksTextView = false
        textView.textContainer.size = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.font = .systemFont(ofSize: fontSize)
        textView.text = text
        return textView
    }

    func updateUIView(_ textView: NoWrapDocumentTextView, context: Context) {
        context.coordinator.parent = self
        let previousOffset = textView.contentOffset
        var shouldRestoreOffset = false
        var didChangeContent = false

        if textView.text != text {
            textView.text = text
            shouldRestoreOffset = true
            didChangeContent = true
        }

        let currentSize = textView.font?.pointSize ?? fontSize
        if abs(currentSize - fontSize) > 0.25 {
            textView.font = .systemFont(ofSize: fontSize)
            shouldRestoreOffset = true
        }

        if shouldRestoreOffset {
            textView.layoutIfNeeded()
            textView.refreshNoWrapContentSize()
            let targetOffset: CGPoint
            if didChangeContent, !textView.hasUserAdjustedHorizontalOffset {
                targetOffset = .zero
            } else {
                targetOffset = textView.clampedContentOffset(for: previousOffset)
            }
            textView.setContentOffset(targetOffset, animated: false)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: PlainDocumentEditor

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            self.parent = PlainDocumentEditor(text: text, fontSize: .constant(18), isFocused: isFocused)
        }

        func textViewDidChange(_ textView: UITextView) {
            let updatedText = textView.text ?? ""
            guard parent.text != updatedText else { return }
            parent.text = updatedText
            (textView as? NoWrapDocumentTextView)?.ensureCaretVisible()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            (textView as? NoWrapDocumentTextView)?.ensureCaretVisible()
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            ButtonClickFeedback.playIfEnabled()
            return true
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            guard !parent.isFocused else { return }
            parent.isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            guard parent.isFocused else { return }
            parent.isFocused = false
        }
    }
}

private final class NoWrapDocumentTextView: UITextView {
    var hasUserAdjustedHorizontalOffset = false

    override func layoutSubviews() {
        super.layoutSubviews()
        textContainer.size = CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        refreshNoWrapContentSize()
    }

    override var contentOffset: CGPoint {
        didSet {
            if abs(contentOffset.x) > 0.5 {
                hasUserAdjustedHorizontalOffset = true
            }
        }
    }

    override func scrollRectToVisible(_ rect: CGRect, animated: Bool) {
        // Keep the user's horizontal position instead of auto-jumping back to the caret.
    }

    override func scrollRangeToVisible(_ range: NSRange) {
        // Keep the user's horizontal position instead of auto-jumping back to the caret.
    }

    func refreshNoWrapContentSize() {
        let measuredSize = sizeThatFits(
            CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        )
        contentSize = CGSize(
            width: max(bounds.width + 1, ceil(measuredSize.width)),
            height: max(bounds.height + 1, ceil(measuredSize.height))
        )
    }

    func ensureCaretVisible() {
        guard let selectedTextRange else { return }

        let caretRect = self.caretRect(for: selectedTextRange.end).insetBy(dx: -16, dy: -12)
        var targetOffset = contentOffset

        let visibleMinX = contentOffset.x
        let visibleMaxX = contentOffset.x + bounds.width
        if caretRect.maxX > visibleMaxX {
            targetOffset.x = caretRect.maxX - bounds.width
        } else if caretRect.minX < visibleMinX {
            targetOffset.x = caretRect.minX
        }

        let visibleMinY = contentOffset.y
        let visibleMaxY = contentOffset.y + bounds.height
        if caretRect.maxY > visibleMaxY {
            targetOffset.y = caretRect.maxY - bounds.height
        } else if caretRect.minY < visibleMinY {
            targetOffset.y = caretRect.minY
        }

        setContentOffset(clampedContentOffset(for: targetOffset), animated: false)
    }

    func clampedContentOffset(for proposedOffset: CGPoint) -> CGPoint {
        let maximumX = max(0, contentSize.width - bounds.width)
        let maximumY = max(0, contentSize.height - bounds.height)

        return CGPoint(
            x: min(max(0, proposedOffset.x), maximumX),
            y: min(max(0, proposedOffset.y), maximumY)
        )
    }
}

private struct BackButton: View {
    @Environment(\.dismiss) private var dismiss
    let action: () -> Void

    var body: some View {
        Button("main") {
            ButtonClickFeedback.playIfEnabled()
            action()
            dismiss()
        }
        .font(.headline)
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(minWidth: 92, minHeight: 44)
        .background(Color.gray.opacity(0.45))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
        }
        .clipShape(.rect(cornerRadius: 12))
        .contentShape(.rect)
    }
}

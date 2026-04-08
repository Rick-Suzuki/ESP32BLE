import SwiftUI
import UIKit

private enum SettingsFocusField: Hashable {
    case sendText
}

struct SettingsScreen: View {
    @AppStorage("speechRecognitionAutoOffMinutes") private var speechRecognitionAutoOffMinutes = 5
    @AppStorage("sendControlABeforeText") private var sendControlABeforeText = false
    @AppStorage("keyboardTimingOnMs") private var keyboardTimingOnMs = 0.0
    @AppStorage("keyboardTimingOffMs") private var keyboardTimingOffMs = 0.0
    @AppStorage("keepScreenAwake") private var keepScreenAwake = false
    private let documentTableWidth: CGFloat = 166
    private let timingLabelWidth = 90.0
    @ObservedObject var ble: BLEKeyboardManager
    let documentFiles: [URL]
    let selectedDocumentName: String
    let refreshDocumentFiles: () -> Void
    let loadFunctionKeys: (URL) -> Void
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
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                editableDocumentSection

                if !isDocumentEditorFocused {
                    combinedBottomPanelSection
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            documentTableSection
                .frame(width: documentTableWidth)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                BackButton {
                    saveCurrentDocumentText()
                }
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
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
        }
        .onChange(of: keepScreenAwake) {
            UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
        }
    }

    private var editableDocumentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PinchZoomDocumentEditor(
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
            .padding(8)
            .disabled(documentEditorText == savedDocumentEditorText)
            .opacity(documentEditorText == savedDocumentEditorText ? 0.35 : 1)
        }
        .clipShape(.rect(cornerRadius: 0))
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
        }
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
    }

    private var combinedBottomPanelSection: some View {
        HStack(alignment: .top, spacing: 20) {
            availableDevicesContent
                .frame(maxWidth: .infinity, alignment: .topLeading)

            keyboardSettingsContent
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
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

private struct PinchZoomDocumentEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var fontSize: CGFloat
    @Binding var isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, fontSize: $fontSize, isFocused: $isFocused)
    }

    func makeUIView(context: Context) -> DocumentCanvasEditorView {
        let editorView = DocumentCanvasEditorView()
        editorView.onTextChange = { updatedText in
            context.coordinator.updateText(updatedText)
        }
        editorView.onFontSizeChange = { updatedFontSize in
            context.coordinator.updateFontSize(updatedFontSize)
        }
        editorView.onFocusChange = { focused in
            context.coordinator.updateFocus(focused)
        }
        editorView.update(text: text, fontSize: fontSize, isFocused: isFocused)
        return editorView
    }

    func updateUIView(_ editorView: DocumentCanvasEditorView, context: Context) {
        editorView.update(text: text, fontSize: fontSize, isFocused: isFocused)
    }

    final class Coordinator: NSObject {
        @Binding var text: String
        @Binding var fontSize: CGFloat
        @Binding var isFocused: Bool

        init(text: Binding<String>, fontSize: Binding<CGFloat>, isFocused: Binding<Bool>) {
            _text = text
            _fontSize = fontSize
            _isFocused = isFocused
        }

        func updateText(_ updatedText: String) {
            guard text != updatedText else { return }
            text = updatedText
        }

        func updateFontSize(_ updatedFontSize: CGFloat) {
            guard abs(fontSize - updatedFontSize) > 0.25 else { return }
            fontSize = updatedFontSize
        }

        func updateFocus(_ focused: Bool) {
            guard isFocused != focused else { return }
            DispatchQueue.main.async {
                self.isFocused = focused
            }
        }
    }
}

private final class DocumentCanvasEditorView: UIView, UITextViewDelegate, UIGestureRecognizerDelegate {
    var onTextChange: ((String) -> Void)?
    var onFontSizeChange: ((CGFloat) -> Void)?
    var onFocusChange: ((Bool) -> Void)?

    private let scrollView = UIScrollView()
    private let canvasView = UIView()
    private let textView = UITextView()
    private let pinchGesture = UIPinchGestureRecognizer()

    private var currentFontSize: CGFloat = 18
    private var didApplyInitialOffset = false
    private var isUpdatingFromSwiftUI = false
    private var pinchStartFontSize: CGFloat = 18

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        layoutCanvas(preserveOffset: true)
    }

    func update(text: String, fontSize: CGFloat, isFocused: Bool) {
        isUpdatingFromSwiftUI = true

        if textView.text != text {
            textView.text = text
        }

        if abs(currentFontSize - fontSize) > 0.25 {
            currentFontSize = fontSize
            textView.font = .systemFont(ofSize: currentFontSize)
        }

        layoutCanvas(preserveOffset: true)

        if isFocused, !textView.isFirstResponder {
            DispatchQueue.main.async {
                self.textView.becomeFirstResponder()
            }
        } else if !isFocused, textView.isFirstResponder {
            DispatchQueue.main.async {
                self.textView.resignFirstResponder()
            }
        }

        isUpdatingFromSwiftUI = false
    }

    private func configure() {
        backgroundColor = .clear

        scrollView.backgroundColor = .clear
        scrollView.alwaysBounceHorizontal = true
        scrollView.alwaysBounceVertical = true
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true

        canvasView.backgroundColor = .clear

        textView.delegate = self
        textView.backgroundColor = .clear
        textView.textColor = .white
        textView.font = .systemFont(ofSize: currentFontSize)
        textView.isScrollEnabled = false
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.keyboardDismissMode = .interactive
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byClipping
        textView.textContainer.widthTracksTextView = false
        textView.textContainer.size = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.panGestureRecognizer.isEnabled = false

        pinchGesture.addTarget(self, action: #selector(handlePinch(_:)))
        pinchGesture.delegate = self
        scrollView.addGestureRecognizer(pinchGesture)

        addSubview(scrollView)
        scrollView.addSubview(canvasView)
        canvasView.addSubview(textView)
    }

    private func layoutCanvas(preserveOffset: Bool) {
        guard bounds.width > 0, bounds.height > 0 else { return }

        let previousOffset = scrollView.contentOffset
        let horizontalMargin = max(bounds.width, 300)
        let verticalMargin = max(bounds.height, 200)
        let measuredTextSize = measuredTextSize()
        let textOrigin = CGPoint(x: horizontalMargin, y: verticalMargin)

        canvasView.frame = CGRect(
            x: 0,
            y: 0,
            width: measuredTextSize.width + (horizontalMargin * 2),
            height: measuredTextSize.height + (verticalMargin * 2)
        )
        textView.frame = CGRect(origin: textOrigin, size: measuredTextSize)
        scrollView.contentSize = canvasView.bounds.size

        if !didApplyInitialOffset {
            scrollView.setContentOffset(textOrigin, animated: false)
            didApplyInitialOffset = true
        } else if preserveOffset {
            scrollView.setContentOffset(clampedOffset(previousOffset), animated: false)
        }
    }

    private func measuredTextSize() -> CGSize {
        let fittingSize = textView.sizeThatFits(
            CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        )

        return CGSize(
            width: max(ceil(fittingSize.width), bounds.width - 16),
            height: max(ceil(fittingSize.height), bounds.height - 16)
        )
    }

    private func clampedOffset(_ proposedOffset: CGPoint) -> CGPoint {
        let maxOffsetX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        let maxOffsetY = max(0, scrollView.contentSize.height - scrollView.bounds.height)

        return CGPoint(
            x: min(max(0, proposedOffset.x), maxOffsetX),
            y: min(max(0, proposedOffset.y), maxOffsetY)
        )
    }

    func textViewDidChange(_ textView: UITextView) {
        onTextChange?(textView.text ?? "")
        layoutCanvas(preserveOffset: true)
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        onFocusChange?(true)
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        onFocusChange?(false)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            pinchStartFontSize = currentFontSize
        case .changed:
            let updatedFontSize = min(max(pinchStartFontSize * gesture.scale, 10), 72)
            guard abs(updatedFontSize - currentFontSize) > 0.25 else { return }
            currentFontSize = updatedFontSize
            textView.font = .systemFont(ofSize: currentFontSize)
            onFontSizeChange?(updatedFontSize)
            layoutCanvas(preserveOffset: true)
        default:
            break
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

private final class NonWrappingTextView: UITextView {
    override func layoutSubviews() {
        super.layoutSubviews()
        setNonWrappingContainerSize()
        updatePanningInsets()
    }

    func setNonWrappingContainerSize() {
        let visibleHeight = max(bounds.height - textContainerInset.top - textContainerInset.bottom, 0)
        textContainer.size = CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: max(visibleHeight, CGFloat.greatestFiniteMagnitude / 4)
        )
    }

    private func updatePanningInsets() {
        let horizontalInset = max(bounds.width * 0.5, 80)
        let verticalInset = max(bounds.height * 0.5, 80)
        let newInset = UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )

        guard contentInset != newInset else {
            return
        }

        let previousInset = contentInset
        let adjustedOffset = CGPoint(
            x: previousInset == .zero ? contentOffset.x : contentOffset.x + previousInset.left - newInset.left,
            y: previousInset == .zero ? contentOffset.y : contentOffset.y + previousInset.top - newInset.top
        )

        contentInset = newInset
        scrollIndicatorInsets = newInset
        setContentOffset(adjustedOffset, animated: false)
    }
}

private struct BackButton: View {
    @Environment(\.dismiss) private var dismiss
    let action: () -> Void

    var body: some View {
        Button("main") {
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

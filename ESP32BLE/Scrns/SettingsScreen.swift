import SwiftUI

private enum SettingsFocusField: Hashable {
    case documentEditor
    case sendText
}

struct SettingsScreen: View {
    @AppStorage("speechRecognitionAutoOffMinutes") private var speechRecognitionAutoOffMinutes = 5
    @AppStorage("sendControlABeforeText") private var sendControlABeforeText = false
    @AppStorage("keyboardTimingOnMs") private var keyboardTimingOnMs = 0.0
    @AppStorage("keyboardTimingOffMs") private var keyboardTimingOffMs = 0.0
    private let documentTableWidth: CGFloat = 208
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
    @State private var pendingDeleteFile: URL?
    @State private var documentEditorText = ""
    @State private var isLoadingDocumentText = false
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
            .padding(.leading)
            .padding(.bottom)

            documentTableSection
                .frame(width: documentTableWidth)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                BackButton()
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
        .onChange(of: selectedDocumentName) {
            loadSelectedDocumentText()
        }
        .onChange(of: documentEditorText) {
            guard !isLoadingDocumentText else {
                return
            }

            saveSelectedDocumentText()
        }
    }

    private var editableDocumentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $documentEditorText)
                .focused($focusedField, equals: .documentEditor)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.black.opacity(0.55))
                .clipShape(.rect(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding()
        .background(Color.black)
        .overlay {
            Rectangle()
                .stroke(Color.white, lineWidth: 1)
        }
        .clipShape(.rect(cornerRadius: 0))
    }

    private var availableDevicesContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Available ESP32 Devices: \(ble.discoveredDevices.count)")
                .font(.headline)

            if ble.discoveredDevices.isEmpty {
                Text("No ESP32 devices found yet")
                    .foregroundStyle(.secondary)
            }

            ForEach(ble.discoveredDevices) { device in
                Button {
                    ble.selectedPeripheralID = device.id
                } label: {
                    HStack {
						VStack(alignment: .leading, spacing: 4) {
							VStack {
								Text(device.displayName)
									.font(.body)
								
						//		Text("RSSI:\(device.rssi), UUID:\(device.id.uuidString)")
						//			.font(.caption)
						//			.foregroundStyle(.secondary)
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

            HStack(spacing: 12) {
                Button("Scan") {
                    ble.startScan()
                }
                .buttonStyle(.borderedProminent)

                Button("Connect") {
                    ble.connectToSelectedDevice()
                }
                .buttonStyle(.borderedProminent)
                .disabled(ble.selectedPeripheralID == nil)

                Button("Disconnect") {
                    ble.disconnect()
                }
                .buttonStyle(.bordered)
                .disabled(!ble.isConnected)
            }

          //  Text("Connected Device ID: \(ble.connectedDeviceID)")
            Text("Status: \(ble.connectionText)")
          //  Text("BT State: \(ble.bluetoothStateText)")
        }
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
                    insertTextAtCursor("\\n")
                }
                .buttonStyle(.bordered)

                Button("return") {
                    insertTextAtCursor("\\n")
                }
                .buttonStyle(.bordered)

                Button("Send") {
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
        .clipShape(.rect(cornerRadius: 0))
        .alert("Delete File?", isPresented: pendingDeleteAlertIsPresented, presenting: pendingDeleteFile) { fileURL in
            Button("Delete", role: .destructive) {
                deleteDocument(fileURL)
                pendingDeleteFile = nil
            }

            Button("Cancel", role: .cancel) {
                pendingDeleteFile = nil
            }
        } message: { fileURL in
            Text("Delete \(fileURL.lastPathComponent)?")
        }
    }

    private var customKeyboardTimingSection: some View {
        VStack(alignment: .center, spacing: 5) {
            HStack(spacing: 12) {
                Text("custom kb timing")
                    .font(.headline)

                Button("set & test") {
                    sendKeyboardTimingCommand()
                    ble.sendString("Hello World! Let's go. (test) 1!2\"3#4$5%6&7'8(9)")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 10) {
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
        HStack(spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(width: timingLabelWidth, alignment: .trailing)

            Button {
                value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1)
            } label: {
                Image(systemName: "triangle.fill")
					.font(.system(size: 30))
					.rotationEffect(.degrees(-90))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .disabled(value.wrappedValue <= range.lowerBound)

            VStack(spacing: -5) {
                Text("\(Int(value.wrappedValue)) ms")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)

                Slider(value: value, in: range, step: 10)
                    .tint(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Button {
                value.wrappedValue = min(range.upperBound, value.wrappedValue + 1)
            } label: {
                Image(systemName: "triangle.fill")
					.font(.system(size: 30))
					.rotationEffect(.degrees(90))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .disabled(value.wrappedValue >= range.upperBound)
        }
    }

    private var speechRecognitionAutoOffRow: some View {
        HStack(spacing: 4) {
            Text("rec off")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: timingLabelWidth, alignment: .trailing)

            Button {
                speechRecognitionAutoOffMinutes = max(1, speechRecognitionAutoOffMinutes - 1)
            } label: {
                Image(systemName: "triangle.fill")
                    .font(.system(size: 30))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .disabled(speechRecognitionAutoOffMinutes <= 1)

            VStack(spacing: -5) {
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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Button {
                speechRecognitionAutoOffMinutes = min(30, speechRecognitionAutoOffMinutes + 1)
            } label: {
                Image(systemName: "triangle.fill")
                    .font(.system(size: 30))
                    .rotationEffect(.degrees(90))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .disabled(speechRecognitionAutoOffMinutes >= 30)
        }
    }

    private func documentRow(for fileURL: URL) -> some View {
        let isSelected = selectedDocumentName == fileURL.lastPathComponent

        return Button {
            loadFunctionKeys(fileURL)
        } label: {
            HStack {
                Text(fileURL.lastPathComponent)
                    .fontWeight(isSelected ? .bold : .regular)
                    .foregroundStyle(.white)
                    .lineLimit(1)

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
                    pendingDeleteFile = fileURL
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private var pendingDeleteAlertIsPresented: Binding<Bool> {
        Binding(
            get: { pendingDeleteFile != nil },
            set: { newValue in
                if !newValue {
                    pendingDeleteFile = nil
                }
            }
        )
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
            return
        }

        documentEditorText = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    private func saveSelectedDocumentText() {
        guard let fileURL = selectedDocumentFileURL else {
            return
        }

        do {
            try documentEditorText.write(to: fileURL, atomically: true, encoding: .utf8)
            loadFunctionKeys(fileURL)
        } catch {
            print("Failed to save document: \(fileURL.lastPathComponent)")
        }
    }

    private var selectedDocumentFileURL: URL? {
        documentFiles.first(where: { $0.lastPathComponent == selectedDocumentName })
    }

    private var isDocumentEditorFocused: Bool {
        focusedField == .documentEditor
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

private struct BackButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("main") {
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

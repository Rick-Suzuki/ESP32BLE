import SwiftUI
import AVFAudio
import Combine
import Speech

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
    @AppStorage("speechRecognitionAutoOffMinutes") private var speechRecognitionAutoOffMinutes = 5
    private let allowedVisibleBoxCounts = [
        1, 2, 4, 6, 9, 12, 15, 16, 18, 20, 24, 28, 32, 36, 40, 42, 45, 48,
        50, 54, 56, 60, 63, 64, 70, 72, 80, 81, 84, 88, 90, 96, 99, 100
    ]
    private let displayModeButtonColor = Color(red: 0.0, green: 0.24, blue: 0.55)
    @State private var visibleBoxCount = 20
    @State private var boxFontSize = 28.0
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
    @FocusState private var isDocumentNameFieldFocused: Bool
    let functionKeys: [FunctionKeyEntry]
    let documentFiles: [URL]
    let selectedDocumentName: String
    let selectedDocumentDisplayName: String
    let currentFileNumber: Int
    let totalFileCount: Int
    let definedFunctionKeyCount: Int
    let refreshDocumentFiles: () -> Void
    let loadFunctionKeys: (URL) -> Void
    let renameDocument: (String) -> String?
    let deleteDocument: (URL) -> Void
    let duplicateDocument: (URL) -> Void
    let canDeleteDocuments: Bool
    let selectPreviousDocument: () -> Void
    let selectNextDocument: () -> Void
    @Binding var settingsBLEText: String

    var body: some View {
        VStack(spacing: 20) {
            GeometryReader { geometry in
                let gridDimensions = gridDimensions(for: visibleBoxCount)
                let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: gridDimensions.columns)
                let buttonHeight = geometry.size.height / CGFloat(max(gridDimensions.rows, 1))

                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(Array(functionKeys.prefix(visibleBoxCount).enumerated()), id: \.offset) { _, entry in
                        Button {
                            guard isBLESendEnabled else {
                                return
                            }

                            guard !entry.sendTexts.isEmpty else {
                                return
                            }

                            for sendText in entry.sendTexts {
                                ble.sendLine(sendText)
                            }
                        } label: {
                            Text(buttonTitle(for: entry))
                                .font(.system(size: boxFontSize, weight: .semibold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, minHeight: buttonHeight, maxHeight: buttonHeight)
                                .background(Color.black)
                                .overlay {
                                    Rectangle()
                                        .stroke(Color.white, lineWidth: 1)
                                }
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            displayModeButtonSection
        }
        .padding(.horizontal, 2)
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                documentTitle
            }

            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("settings >") {
                    SettingsScreen(
                        ble: ble,
                        documentFiles: documentFiles,
                        selectedDocumentName: selectedDocumentName,
                        refreshDocumentFiles: refreshDocumentFiles,
                        loadFunctionKeys: loadFunctionKeys,
                        deleteDocument: deleteDocument,
                        duplicateDocument: duplicateDocument,
                        canDeleteDocuments: canDeleteDocuments,
                        bleTextToSend: $settingsBLEText
                    )
                }
            }
        }
        .task(id: isEditingDocumentName) {
            guard isEditingDocumentName else { return }
            isDocumentNameFieldFocused = true
        }
        .onChange(of: selectedDocumentDisplayName) {
            cancelDocumentRename()
        }
        .onChange(of: definedFunctionKeyCount) {
            updateVisibleBoxCountToFitDefinedButtons()
        }
        .onChange(of: isDocumentNameFieldFocused) {
            guard isEditingDocumentName, !isDocumentNameFieldFocused else {
                return
            }

            cancelDocumentRename()
        }
        .onChange(of: isSpkRecEnabled) {
            handleSpeechRecognitionToggle()
        }
        .onChange(of: speechRecognitionAutoOffMinutes) {
            guard isSpkRecEnabled else {
                return
            }

            scheduleSpeechRecognitionAutoOff()
        }
        .onChange(of: speechRecognition.latestRecognition) {
            guard let latestRecognition = speechRecognition.latestRecognition else {
                return
            }

            applyRecognizedSpeech(latestRecognition.text)
        }
        .onDisappear {
            speechRecognitionAutoOffTask?.cancel()
            speechRecognition.setListeningEnabled(false)
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

    private var documentTitle: some View {
        HStack(spacing: 20) {
            Button {
                selectPreviousDocument()
            } label: {
                Image(systemName: "triangle.fill")
                    .font(.system(size: 20))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .disabled(currentFileNumber <= 1)

            Text("\(currentFileNumber)")
                .font(.headline)
                .frame(minWidth: 20, alignment: .leading)

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
                selectNextDocument()
            } label: {
                Image(systemName: "triangle.fill")
                    .font(.system(size: 20))
                    .rotationEffect(.degrees(90))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .disabled(currentFileNumber >= totalFileCount)
        }
    }

    private var displayModeButtonSection: some View {
        HStack {
            HStack(spacing: 12) {
                Button {
                    decreaseVisibleBoxCount()
                } label: {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 30))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .disabled(visibleBoxCount == allowedVisibleBoxCounts.first)

                Text("num:\(visibleBoxCount)")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(minWidth: 32)

                Button {
                    increaseVisibleBoxCount()
                } label: {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 30))
                        .rotationEffect(.degrees(90))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .disabled(visibleBoxCount == allowedVisibleBoxCounts.last)
            }

            HStack(spacing: 12) {
                Button {
                    decreaseBoxFontSize()
                } label: {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 30))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .disabled(boxFontSize <= minimumBoxFontSize)

                Text("fnt:\(Int(boxFontSize))")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(minWidth: 32)

                Button {
                    increaseBoxFontSize()
                } label: {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 30))
                        .rotationEffect(.degrees(90))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
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
            .background(isSpkRecEnabled ? Color.green.opacity(0.5) : Color.gray.opacity(0.45))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSpkRecEnabled ? Color.green.opacity(0.5) : Color.gray.opacity(0.4), lineWidth: 2)
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
            .background(isBLESendEnabled ? Color.blue : Color.gray.opacity(0.45))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isBLESendEnabled ? Color.blue : Color.gray.opacity(0.4), lineWidth: 2)
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

    private func buttonTitle(for entry: FunctionKeyEntry) -> String {
        guard entry.displayUsesAlternateText else {
            return displayText(from: entry.rawLine)
        }

        switch displayMode {
        case .left:
            return displayText(from: entry.primaryDisplayText)
        case .right:
            return displayText(from: entry.alternateDisplayText ?? entry.rawLine)
        case .both:
            return "\(displayText(from: entry.primaryDisplayText))\n\(displayText(from: entry.alternateDisplayText ?? entry.rawLine))"
        }
    }

    private func displayText(from text: String) -> String {
        text
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")
    }

    private func applyRecognizedSpeech(_ recognizedText: String) {
        guard isSpkRecEnabled else {
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

        visibleBoxCount = allowedVisibleBoxCounts[currentIndex - 1]
    }

    private func increaseVisibleBoxCount() {
        guard let currentIndex = allowedVisibleBoxCounts.firstIndex(of: visibleBoxCount),
              currentIndex < allowedVisibleBoxCounts.count - 1 else {
            return
        }

        visibleBoxCount = allowedVisibleBoxCounts[currentIndex + 1]
    }

    private func decreaseBoxFontSize() {
        boxFontSize = max(minimumBoxFontSize, boxFontSize - 2)
    }

    private func increaseBoxFontSize() {
        boxFontSize = min(maximumBoxFontSize, boxFontSize + 2)
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

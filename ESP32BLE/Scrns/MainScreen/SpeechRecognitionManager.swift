import AVFAudio
import Combine
import Speech
import SwiftUI

private let spokenDigitTokenMap: [String: String] = [
    "zero": "0",
    "one": "1",
    "two": "2",
    "three": "3",
    "four": "4",
    "five": "5",
    "six": "6",
    "seven": "7",
    "eight": "8",
    "nine": "9"
]

func normalizedSpeechRecognitionText(_ text: String) -> String {
    text
        .lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
        .map { spokenDigitTokenMap[$0] ?? $0 }
        .joined(separator: " ")
}

struct SpeechRecognitionEvent: Equatable {
    let id = UUID()
    let text: String
}

enum SpeechRecognitionDisplayState: Equatable {
    case disabled
    case recognizing
    case recognized(String)
}

@MainActor
final class SpeechRecognitionManager: NSObject, ObservableObject {
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
        normalizedSpeechRecognitionText(text)
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

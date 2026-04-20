import SwiftUI
import AVFAudio

extension MainScreen {
    func applyRecognizedSpeech(_ recognizedText: String) {
        guard isSpkRecEnabled, !isGridEditModeEnabled else {
            return
        }

        scheduleSpeechRecognitionAutoOff()

        if recognizedText == canonicalSpeechText(from: "go back") {
            unmatchedSpeechText = nil

            guard canGoBackToPreviousDocument else {
                return
            }

            goBackToPreviousDocument()
            return
        }

        if recognizedText == canonicalSpeechText(from: "speech off") {
            unmatchedSpeechText = nil
            isSpkRecEnabled = false
            return
        }

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

        let bluetoothSendTexts = matchingEntry.sendTexts.filter { sendText in
            targetDocumentNameForSendText(sendText) == nil
        }
        let targetDocumentName = targetDocumentNameForGridEntry(matchingEntry)

        if let targetDocumentName {
            guard selectDocumentNamedFromGrid(targetDocumentName) else {
                alertTitle = "File Not Found"
                renameAlertMessage = "Couldn't find \(targetDocumentName.lowercased())."
                return
            }
        }

        guard mainGridButtonMode.sendsBluetooth, !bluetoothSendTexts.isEmpty else {
            return
        }

        for sendText in bluetoothSendTexts {
            ble.sendLine(normalizedBluetoothSendText(sendText))
        }
    }

    func normalizedSpeechMatchText(_ text: String) -> String {
        canonicalSpeechText(from: speechMatchDisplayText(from: text))
    }

    func canonicalSpeechText(from text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func speechMatchDisplayText(from text: String) -> String {
        let displayString = displayText(from: text)
        let trailingComponent = displayString
            .components(separatedBy: ":")
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return trailingComponent.isEmpty ? displayString : trailingComponent
    }

    func handleSpeechRecognitionToggle() {
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
        resetAudioSessionForSpeechPlayback()
        sendModifierFunctionKey("f19")
    }

    var latestRecognizedText: String? {
        speechRecognition.latestRecognition?.text
    }

    func handleSpeechRecognitionAutoOffMinutesChange() {
        guard isSpkRecEnabled else {
            return
        }

        scheduleSpeechRecognitionAutoOff()
    }

    func handleLatestRecognizedTextChange() {
        guard let recognizedText = latestRecognizedText else {
            return
        }

        applyRecognizedSpeech(recognizedText)
    }

    func handleMainScreenDisappear() {
        speechRecognitionAutoOffTask?.cancel()
        speechRecognition.setListeningEnabled(false)
    }

    func scheduleSpeechRecognitionAutoOff() {
        speechRecognitionAutoOffTask?.cancel()

        let autoOffMinutes = max(speechRecognitionAutoOffMinutes, 1)
        guard autoOffMinutes < 31 else {
            speechRecognitionAutoOffTask = nil
            return
        }

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

    func activateAudioSessionForSpeechPlayback() {
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }

    func resetAudioSessionForSpeechPlayback() {
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    }

    func sendModifierFunctionKey(_ functionKey: String) {
        guard !isGridEditModeEnabled else {
            return
        }

        ble.sendLine("ct")
        ble.sendLine("sh")
        ble.sendLine("op")
        ble.sendLine("cm")
        ble.sendLine(functionKey)
    }

    var speechRecognitionDisplayText: String {
        if let unmatchedSpeechText {
            return unmatchedSpeechText
        }

        switch speechRecognition.displayState {
        case .disabled:
            return "disabled"
        case .recognizing:
            if let latestRecognizedText, !latestRecognizedText.isEmpty {
                return latestRecognizedText
            }
            return "recognizing..."
        case .recognized(let text):
            return text
        }
    }

    var speechRecognitionDisplayColor: Color {
        if unmatchedSpeechText != nil {
            return .white
        }

        switch speechRecognition.displayState {
        case .recognized:
            return .white
        case .recognizing:
            return latestRecognizedText == nil ? .gray : .white
        case .disabled:
            return .gray
        }
    }
}

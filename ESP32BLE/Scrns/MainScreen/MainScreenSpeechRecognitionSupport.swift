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

        if recognizedText == canonicalSpeechText(from: "speech off") ||
            recognizedText == canonicalSpeechText(from: "stop listening") {
            unmatchedSpeechText = nil
            isSpkRecEnabled = false
            return
        }

        if let targetDocumentName = targetDocumentNameForSpeechOpenCommand(recognizedText) {
            unmatchedSpeechText = nil

            guard selectDocumentNamedFromGrid(targetDocumentName) else {
                alertTitle = "File Not Found"
                renameAlertMessage = "Couldn't find \(targetDocumentName.lowercased())."
                return
            }

            return
        }

        guard let matchingEntry = matchingSpeechEntry(for: recognizedText) else {
            unmatchedSpeechText = recognizedText
            return
        }

        unmatchedSpeechText = nil

        let bluetoothSendTexts = matchingEntry.sendTexts.filter { sendText in
            targetDocumentNameForSendText(sendText) == nil &&
                targetPreviewFilenameForSendText(sendText) == nil
        }
        let targetDocumentName = targetDocumentNameForGridEntry(matchingEntry)
        let targetPreviewFilename = targetPreviewFilenameForGridEntry(matchingEntry)

        if let targetDocumentName {
            guard selectDocumentNamedFromGrid(targetDocumentName) else {
                alertTitle = "File Not Found"
                renameAlertMessage = "Couldn't find \(targetDocumentName.lowercased())."
                return
            }
        }

        if let targetPreviewFilename {
            openPreviewFile(named: targetPreviewFilename)
        }

        guard mainGridButtonMode.sendsBluetooth, !bluetoothSendTexts.isEmpty else {
            return
        }

        let normalizedBluetoothSendTexts = bluetoothSendTexts.map(normalizedBluetoothSendText)
        guard normalizedBluetoothSendTexts.allSatisfy(isBluetoothSendableText(_:)) else {
            showBluetoothEmojiBlockedPopup()
            return
        }

        for sendText in normalizedBluetoothSendTexts {
            ble.sendLine(sendText)
        }
    }

    func normalizedSpeechMatchText(_ text: String) -> String {
        canonicalSpeechText(from: speechSynthesisText(from: speechMatchDisplayText(from: text)))
    }

    func canonicalSpeechText(from text: String) -> String {
        normalizedSpeechRecognitionText(text)
    }

    func speechMatchDisplayText(from text: String) -> String {
        let displayString = displayText(from: text)
        let trailingComponent = displayString
            .components(separatedBy: ":")
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return trailingComponent.isEmpty ? displayString : trailingComponent
    }

    func targetDocumentNameForSpeechOpenCommand(_ recognizedText: String) -> String? {
        let openPrefix = "\(canonicalSpeechText(from: "open")) "
        guard recognizedText.hasPrefix(openPrefix) else {
            return nil
        }

        let targetDocumentName = String(recognizedText.dropFirst(openPrefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return targetDocumentName.isEmpty ? nil : targetDocumentName
    }

    func matchingSpeechEntry(for recognizedText: String) -> FunctionKeyEntry? {
        let recognizedTextWithoutSpaces = recognizedText.replacingOccurrences(of: " ", with: "")
        let entriesWithAlternateText = functionKeys.filter { $0.alternateDisplayText != nil }

        if let exactMatch = entriesWithAlternateText.first(where: { entry in
            guard let alternateDisplayText = entry.alternateDisplayText else {
                return false
            }

            return normalizedSpeechMatchText(alternateDisplayText) == recognizedText
        }) {
            return exactMatch
        }

        if recognizedTextWithoutSpaces != recognizedText,
           let exactMatchWithoutSpaces = entriesWithAlternateText.first(where: { entry in
               guard let alternateDisplayText = entry.alternateDisplayText else {
                   return false
               }

               return normalizedSpeechMatchText(alternateDisplayText)
                   .replacingOccurrences(of: " ", with: "") == recognizedTextWithoutSpaces
           }) {
            return exactMatchWithoutSpaces
        }

        if let subphraseMatch = entriesWithAlternateText.first(where: { entry in
            guard let alternateDisplayText = entry.alternateDisplayText else {
                return false
            }

            return speechText(normalizedSpeechMatchText(alternateDisplayText), containsPhrase: recognizedText)
        }) {
            return subphraseMatch
        }

        if recognizedTextWithoutSpaces != recognizedText {
            return entriesWithAlternateText.first(where: { entry in
                guard let alternateDisplayText = entry.alternateDisplayText else {
                    return false
                }

                return normalizedSpeechMatchText(alternateDisplayText)
                    .replacingOccurrences(of: " ", with: "")
                    .contains(recognizedTextWithoutSpaces)
            })
        }

        return nil
    }

    func speechText(_ candidateText: String, containsPhrase phraseText: String) -> Bool {
        let candidateTokens = candidateText
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        let phraseTokens = phraseText
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        guard !candidateTokens.isEmpty,
              !phraseTokens.isEmpty,
              phraseTokens.count <= candidateTokens.count else {
            return false
        }

        let lastStartIndex = candidateTokens.count - phraseTokens.count
        for startIndex in 0...lastStartIndex {
            let candidateSlice = candidateTokens[startIndex..<(startIndex + phraseTokens.count)]
            if Array(candidateSlice).elementsEqual(phraseTokens) {
                return true
            }
        }

        return false
    }

    func handleSpeechRecognitionToggle() {
        if isSpkRecEnabled {
            unmatchedSpeechText = nil
            speechRecognition.setListeningEnabled(true)
            scheduleSpeechRecognitionAutoOff()
            return
        }

        speechRecognitionAutoOffTask?.cancel()
        speechRecognitionAutoOffTask = nil
        unmatchedSpeechText = nil
        speechRecognition.setListeningEnabled(false)
        resetAudioSessionForSpeechPlayback()
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

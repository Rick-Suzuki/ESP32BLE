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

        if recognizedText == canonicalSpeechText(from: "go home") {
            unmatchedSpeechText = nil

            guard selectDocumentNamedFromGrid("home.screen") else {
                alertTitle = "File Not Found"
                renameAlertMessage = "Couldn't find home.screen."
                return
            }

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

        let speechMatchResult = speechMatchResult(for: recognizedText)
        let matchingEntry: FunctionKeyEntry

        switch speechMatchResult {
        case .unique(let entry):
            matchingEntry = entry
        case .ambiguous:
            unmatchedSpeechText = nil
            renameAlertMessage = "Voice command matches\nmultiple buttons"
            return
        case .noMatch:
            unmatchedSpeechText = recognizedText
            return
        }

        unmatchedSpeechText = nil

        if containsWaitCommand(in: matchingEntry.sendTexts) {
            startWaitChainCommandTokens(
                matchingEntry.sendTexts,
                sourceEntry: matchingEntry,
                respectsBluetoothMode: true
            )
            return
        }

        if matchingEntry.sendTexts.contains(where: isStopMediaCommandText) {
            stopAllMainGridMedia()
            return
        }

        let bluetoothSendTexts = bluetoothSendTexts(for: matchingEntry)
        let targetDocumentName = targetDocumentNameForGridEntry(matchingEntry)
        let targetPreviewFilename = targetPreviewFilenameForGridEntry(matchingEntry)
        let targetSoundResult = targetSoundRequestForGridEntry(matchingEntry)
        let targetSoundRequest: MainGridSoundRequest?
        switch targetSoundResult {
        case .request(let request):
            targetSoundRequest = request
        case .invalidVolume:
            showInvalidSoundVolumeAlert()
            return
        case nil:
            targetSoundRequest = nil
        }
        let targetSpokenFilename = targetSpokenFilenameForGridEntry(matchingEntry)
        let targetSpokenText = targetSpokenTextForGridEntry(matchingEntry)
        var didSendBluetooth = false

        func sendBluetoothIfNeeded() -> Bool {
            guard !didSendBluetooth else {
                return true
            }

            guard sendKeyboardOutputTokens(
                bluetoothSendTexts,
                respectsButtonMode: true
            ) else {
                return false
            }

            if mainGridButtonMode.sendsBluetooth && !bluetoothSendTexts.isEmpty {
                didSendBluetooth = true
            }
            return true
        }

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

        if targetSoundRequest != nil || targetSpokenText != nil || targetSpokenFilename != nil {
            guard sendBluetoothIfNeeded() else {
                return
            }
        }

        if let targetSoundRequest {
            playMainGridSound(
                named: targetSoundRequest.filename,
                volumePercentage: targetSoundRequest.volumePercentage
            )
        }

        if let targetSpokenText {
            speakMainGridText(targetSpokenText)
        } else if let targetSpokenFilename {
            alertTitle = "File Not Found"
            renameAlertMessage = "Couldn't find \(targetSpokenFilename.lowercased())."
            return
        }

        _ = sendBluetoothIfNeeded()
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

    private enum SpeechMatchResult {
        case unique(FunctionKeyEntry)
        case ambiguous
        case noMatch
    }

    private func speechMatchResult(for recognizedText: String) -> SpeechMatchResult {
        let recognizedTextWithoutSpaces = recognizedText.replacingOccurrences(of: " ", with: "")
        let entriesWithAlternateText = functionKeys.enumerated().filter { $0.element.alternateDisplayText != nil }

        func matchResult(where matchesEntry: (FunctionKeyEntry) -> Bool) -> SpeechMatchResult {
            let matches = entriesWithAlternateText.filter { matchesEntry($0.element) }

            switch matches.count {
            case 0:
                return .noMatch
            case 1:
                return .unique(matches[0].element)
            default:
                return .ambiguous
            }
        }

        let exactMatchResult = matchResult { entry in
            guard let alternateDisplayText = entry.alternateDisplayText else {
                return false
            }

            return normalizedSpeechMatchText(alternateDisplayText) == recognizedText
        }
        if case .unique = exactMatchResult {
            return exactMatchResult
        }
        if case .ambiguous = exactMatchResult {
            return exactMatchResult
        }

        if recognizedTextWithoutSpaces != recognizedText {
            let exactMatchWithoutSpacesResult = matchResult { entry in
               guard let alternateDisplayText = entry.alternateDisplayText else {
                   return false
               }

               return normalizedSpeechMatchText(alternateDisplayText)
                   .replacingOccurrences(of: " ", with: "") == recognizedTextWithoutSpaces
            }
            if case .unique = exactMatchWithoutSpacesResult {
                return exactMatchWithoutSpacesResult
            }
            if case .ambiguous = exactMatchWithoutSpacesResult {
                return exactMatchWithoutSpacesResult
            }
        }

        let subphraseMatchResult = matchResult { entry in
            guard let alternateDisplayText = entry.alternateDisplayText else {
                return false
            }

            return speechText(normalizedSpeechMatchText(alternateDisplayText), containsPhrase: recognizedText)
        }
        if case .unique = subphraseMatchResult {
            return subphraseMatchResult
        }
        if case .ambiguous = subphraseMatchResult {
            return subphraseMatchResult
        }

        if recognizedTextWithoutSpaces != recognizedText {
            return matchResult { entry in
                guard let alternateDisplayText = entry.alternateDisplayText else {
                    return false
                }

                return normalizedSpeechMatchText(alternateDisplayText)
                    .replacingOccurrences(of: " ", with: "")
                    .contains(recognizedTextWithoutSpaces)
            }
        }

        return .noMatch
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

    func activateAudioSessionForSpeechPlayback() async -> Bool {
        do {
            try await AudioSessionOperationCoordinator.shared.configurePlaybackSession()
            return true
        } catch {
            return false
        }
    }

    func sendModifierFunctionKey(_ functionKey: String) {
        guard !isGridEditModeEnabled else {
            return
        }

        _ = sendKeyboardOutputTokens(
            ["ct", "sh", "op", "cm", functionKey],
            respectsButtonMode: false
        )
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

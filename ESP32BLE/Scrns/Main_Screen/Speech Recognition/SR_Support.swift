import SwiftUI
import AVFAudio

extension MainScreen {
    func applyRecognizedSpeech(_ recognizedText: String) {
        guard isSpkRecEnabled, !isSpeechRecognitionBlockedByEditing else {
            return
        }

        scheduleSpeechRecognitionAutoOff()

        let initialResolution = resolveSpeechCommand(for: recognizedText)
        var resolutionForExecution = initialResolution

        if case .open(let targetDocumentName, .noMatch) = initialResolution {
            if let substitutedText = substitutedSpeechText(for: recognizedText) {
                let substitutedResolution = resolveSpeechCommand(for: substitutedText)
                if case .button(.noMatch) = substitutedResolution {
                    presentSpeechOpenFailure(for: targetDocumentName)
                    return
                }
                resolutionForExecution = substitutedResolution
            } else {
                presentSpeechOpenFailure(for: targetDocumentName)
                return
            }
        } else if case .button(.noMatch) = initialResolution,
                  let substitutedText = substitutedSpeechText(for: recognizedText) {
            resolutionForExecution = resolveSpeechCommand(for: substitutedText)
        }

        switch resolutionForExecution {
        case .goBack:
            unmatchedSpeechText = nil

            guard canGoBackToPreviousDocument else {
                return
            }

            goBackToPreviousDocument()
        case .goHome:
            unmatchedSpeechText = nil

            guard selectDocumentNamedFromGrid("home.screen") else {
                alertTitle = "File Not Found"
                renameAlertMessage = "Couldn't find home.screen."
                return
            }
        case .speechOff:
            unmatchedSpeechText = nil
            isSpkRecEnabled = false
        case .open(let targetDocumentName, let openButtonMatchResult):
            unmatchedSpeechText = nil

            switch openButtonMatchResult {
            case .unique(let entry):
                executeRecognizedSpeechButton(entry)
            case .ambiguous:
                renameAlertMessage = "Voice command matches\nmultiple buttons"
            case .noMatch:
                presentSpeechOpenFailure(for: targetDocumentName)
            }
        case .button(let buttonSpeechMatchResult):
            switch buttonSpeechMatchResult {
            case .unique(let entry):
                executeRecognizedSpeechButton(entry)
            case .ambiguous:
                unmatchedSpeechText = nil
                renameAlertMessage = "Voice command matches\nmultiple buttons"
            case .noMatch:
                unmatchedSpeechText = recognizedText
            }
        }
    }

    private func executeRecognizedSpeechButton(_ matchingEntry: FunctionKeyEntry) {
        unmatchedSpeechText = nil
        #if DEBUG
        printMainGridButtonActivation(matchingEntry, via: "speech")
        #endif
        if containsWaitCommand(in: matchingEntry.sendTexts) {
            startWaitChainCommandTokens(
                matchingEntry.sendTexts,
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

    private func resolveSpeechCommand(for recognizedText: String) -> SpeechCommandResolution {
        if recognizedText == canonicalSpeechText(from: "go back") {
            return .goBack
        }

        if recognizedText == canonicalSpeechText(from: "go home") {
            return .goHome
        }

        if recognizedText == canonicalSpeechText(from: "speech off") ||
            recognizedText == canonicalSpeechText(from: "stop listening") {
            return .speechOff
        }

        if let targetDocumentName = targetDocumentNameForSpeechOpenCommand(recognizedText) {
            return .open(
                targetDocumentName: targetDocumentName,
                buttonMatchResult: speechMatchResult(for: recognizedText)
            )
        }

        return .button(speechMatchResult(for: recognizedText))
    }

    private func substitutedSpeechText(for recognizedText: String) -> String? {
        SpeechSubstitutions.replacing(
            in: recognizedText,
            rules: speechSubstitutionRules,
            normalize: canonicalSpeechText(from:)
        )
    }

    private func presentSpeechOpenFailure(for targetDocumentName: String) {
        switch selectScreenDocumentNamedForSpeechOpen(targetDocumentName) {
        case .selected:
            return
        case .ambiguous:
            alertTitle = "Ambiguous Screen Name"
            renameAlertMessage = "More than one screen matches \(targetDocumentName.lowercased())."
        case .notFound:
            alertTitle = "File Not Found"
            renameAlertMessage = "Couldn't find \(targetDocumentName.lowercased())."
        }
    }

    func normalizedSpeechMatchText(_ text: String) -> String {
        let displayText = speechMatchDisplayText(from: text)
        let comparisonText = speechMatchTextWithAmpersandEquivalence(displayText)
        return canonicalSpeechText(from: speechSynthesisText(from: comparisonText))
    }

    private func speechMatchTextWithAmpersandEquivalence(_ text: String) -> String {
        let characters = Array(text)
        var result = String()
        result.reserveCapacity(text.count)

        for index in characters.indices {
            let character = characters[index]
            guard character == "&" else {
                result.append(character)
                continue
            }

            let previousCharacter = index > characters.startIndex ? characters[index - 1] : nil
            let nextIndex = characters.index(after: index)
            let nextCharacter = nextIndex < characters.endIndex ? characters[nextIndex] : nil
            let isAdjacentToWordCharacter =
                previousCharacter?.isLetter == true ||
                previousCharacter?.isNumber == true ||
                nextCharacter?.isLetter == true ||
                nextCharacter?.isNumber == true

            if isAdjacentToWordCharacter {
                result.append(character)
            } else {
                result.append(contentsOf: " and ")
            }
        }

        return result
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

    private enum SpeechCommandResolution {
        case goBack
        case goHome
        case speechOff
        case open(targetDocumentName: String, buttonMatchResult: SpeechMatchResult)
        case button(SpeechMatchResult)
    }

    private func speechMatchResult(for recognizedText: String) -> SpeechMatchResult {
        let recognizedTextWithoutSpaces = recognizedText.replacingOccurrences(of: " ", with: "")
        let entriesWithAlternateText = functionKeys.enumerated().filter { $0.element.alternateDisplayText != nil }

        func matchResult(for matches: [(offset: Int, element: FunctionKeyEntry)]) -> SpeechMatchResult {

            switch matches.count {
            case 0:
                return .noMatch
            case 1:
                return .unique(matches[0].element)
            default:
                return .ambiguous
            }
        }

        func matchingEntries(where matchesEntry: (FunctionKeyEntry) -> Bool) -> [(offset: Int, element: FunctionKeyEntry)] {
            entriesWithAlternateText.filter { matchesEntry($0.element) }
        }

        func partialMatchResult() -> SpeechMatchResult {
            let partialMatches = matchingEntries { entry in
                guard let alternateDisplayText = entry.alternateDisplayText else {
                    return false
                }

                return speechText(
                    normalizedSpeechMatchText(alternateDisplayText),
                    containsWholeTokenPhrase: recognizedText
                )
            }
            return matchResult(for: partialMatches)
        }

        let exactMatches = matchingEntries { entry in
            guard let alternateDisplayText = entry.alternateDisplayText else {
                return false
            }

            return normalizedSpeechMatchText(alternateDisplayText) == recognizedText
        }

        let spaceStrippedMatches: [(offset: Int, element: FunctionKeyEntry)] = matchingEntries { entry in
            guard let alternateDisplayText = entry.alternateDisplayText else {
                return false
            }

            return normalizedSpeechMatchText(alternateDisplayText)
                .replacingOccurrences(of: " ", with: "") == recognizedTextWithoutSpaces
        }

        guard speechRecognition.recognitionLocale.language.languageCode?.identifier.lowercased() == "en" else {
            let exactMatchResult = matchResult(for: exactMatches)
            if case .noMatch = exactMatchResult {
                let spaceStrippedMatchResult = matchResult(for: spaceStrippedMatches)
                if case .noMatch = spaceStrippedMatchResult {
                    return partialMatchResult()
                }
                return spaceStrippedMatchResult
            }
            return exactMatchResult
        }

        let recognizedTokens = EnglishHomophones.tokens(from: recognizedText)
        let homophoneMatches = matchingEntries { entry in
            guard let alternateDisplayText = entry.alternateDisplayText else {
                return false
            }

            let candidateTokens = EnglishHomophones.tokens(
                from: normalizedSpeechMatchText(alternateDisplayText)
            )
            guard candidateTokens.count == recognizedTokens.count else {
                return false
            }

            return zip(candidateTokens, recognizedTokens).allSatisfy { candidateToken, recognizedToken in
                candidateToken == recognizedToken || EnglishHomophones.matches(candidateToken, recognizedToken)
            }
        }

        var candidatesByOffset: [Int: FunctionKeyEntry] = [:]
        for candidate in exactMatches + spaceStrippedMatches + homophoneMatches {
            candidatesByOffset[candidate.offset] = candidate.element
        }

        let existingMatchResult = matchResult(
            for: candidatesByOffset.map { (offset: $0.key, element: $0.value) }
        )
        if case .noMatch = existingMatchResult {
            let normalizedRecognizedText = canonicalSpeechText(from: recognizedText)
            let finalSMatches = matchingEntries { entry in
                guard let alternateDisplayText = entry.alternateDisplayText else {
                    return false
                }

                let normalizedCandidateText = normalizedSpeechMatchText(alternateDisplayText)
                guard !normalizedCandidateText.isEmpty,
                      !normalizedRecognizedText.isEmpty,
                      normalizedCandidateText != "s",
                      normalizedRecognizedText != "s" else {
                    return false
                }

                if normalizedCandidateText.hasSuffix("s") {
                    return String(normalizedCandidateText.dropLast()) == normalizedRecognizedText
                }

                return normalizedCandidateText + "s" == normalizedRecognizedText
            }

            let finalSMatchResult = matchResult(for: finalSMatches)
            if case .noMatch = finalSMatchResult {
                return partialMatchResult()
            }
            return finalSMatchResult
        }
        return existingMatchResult

    }

    private func speechText(
        _ candidateText: String,
        containsWholeTokenPhrase phraseText: String
    ) -> Bool {
        let candidateTokens = candidateText.split(whereSeparator: \.isWhitespace).map(String.init)
        let phraseTokens = phraseText.split(whereSeparator: \.isWhitespace).map(String.init)

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
            guard !isSpeechRecognitionBlockedByEditing else {
                handleSpeechRecognitionEditingStateChange()
                return
            }

            unmatchedSpeechText = nil
            speechSubstitutionRules = SpeechSubstitutions.load(normalize: canonicalSpeechText(from:))
            speechRecognition.setListeningEnabled(true)
            scheduleSpeechRecognitionAutoOff()
            return
        }

        speechRecognitionAutoOffTask?.cancel()
        speechRecognitionAutoOffTask = nil
        unmatchedSpeechText = nil
        speechRecognition.setListeningEnabled(false)
    }

    private var isSpeechRecognitionBlockedByEditing: Bool {
        isGridEditModeEnabled || editingSlotIndex != nil
    }

    func handleSpeechRecognitionEditingStateChange() {
        guard isSpeechRecognitionBlockedByEditing else {
            return
        }

        speechRecognitionAutoOffTask?.cancel()
        speechRecognitionAutoOffTask = nil
        unmatchedSpeechText = nil
        isSpkRecEnabled = false
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

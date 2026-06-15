
/*
 This contains most of the button behavior logic:
 tap handling,
 edit-mode actions,
 resizing,
 duplicate/delete behavior,
 movement rules/helpers.
 */

import SwiftUI
import AVFoundation
import UIKit
import Combine
import PDFKit

extension MainScreen {
		// MARK: - BM:🔳 main scrn SF symbols
    private var supportedMainScreenSFSymbolNames: Set<String> {
        [
            "folder", "eye", "magnifyingglass", "gearshape", "house",
            "lightbulb.max.fill", "speaker.wave.2", "star", "heart", "bell",
            "paperclip", "link", "paperplane", "doc", "calendar",
            "camera", "photo", "tray", "sun.max.fill", "chart.bar.fill"
        ]
    }

    func buttonTitle(for entry: FunctionKeyEntry) -> String {
        guard entry.displayUsesAlternateText else {
            return displayText(from: rawLineWithoutHiddenMetadata(entry))
        }

        let alternateDisplayText = resolvedAlternateDisplayText(for: entry)

        switch displayMode {
        case .left:
            return displayText(from: entry.primaryDisplayText)
        case .right:
            return displayText(from: alternateDisplayText)
        case .last:
            return displayTextAfterLastColon(in: alternateDisplayText)
        case .both:
            return "\(displayText(from: entry.primaryDisplayText))\n\(displayText(from: alternateDisplayText))"
        }
    }

    func displayText(from text: String) -> String {
        text
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")
    }

    func displayTextAfterLastColon(in text: String) -> String {
        let normalizedText = displayText(from: text)
        let components = normalizedText.components(separatedBy: ":")
        guard let lastComponent = components.last?.trimmingCharacters(in: .whitespacesAndNewlines),
              !lastComponent.isEmpty else {
            return normalizedText
        }

        return lastComponent
    }

    func resolvedAlternateDisplayText(for entry: FunctionKeyEntry) -> String {
        if let alternateDisplayText = entry.alternateDisplayText {
            return alternateDisplayText
        }

        let components = rawLineWithoutHiddenMetadata(entry).components(separatedBy: "::")
        guard components.count >= 2 else {
            return ""
        }

        let rawRightText = components
            .dropFirst()
            .joined(separator: "::")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rightComponents = rawRightText.components(separatedBy: ":")

        if rightComponents.count > 1,
           let firstComponent = rightComponents.first,
           firstComponent.count == 1,
           let manualColorCode = firstComponent.lowercased().first,
		   // MARK: - BM:🟪 color keycodes-available
           "0123456789abcdefghijklmnopqrstuvwxyz".contains(manualColorCode) {
            let remainingText = rightComponents
                .dropFirst()
                .joined(separator: ":")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return remainingText
        }

        return rawRightText
    }

    func logMainButtonPress(_ entry: FunctionKeyEntry) {
        let leftText = entry.sendTexts.joined(separator: ":")
        let rightText = entry.alternateDisplayText ?? ""
        print("Main button pressed. left: [\(leftText)] right: [\(rightText)]")
    }

    func sendMainGridEntry(_ entry: FunctionKeyEntry) {
        guard mainGridButtonMode != .disabled else {
            return
        }

        if mainGridButtonMode.speaksText {
            speakMainGridEntry(entry)
        }

        guard !entry.sendTexts.isEmpty else {
            return
        }

        if containsWaitCommand(in: entry.sendTexts) {
            Task { @MainActor in
                await runWaitChainCommandTokens(
                    entry.sendTexts,
                    sourceEntry: entry,
                    respectsBluetoothMode: true
                )
            }
            return
        }

        let bluetoothSendTexts = bluetoothSendTexts(for: entry)
        let targetDocumentName = targetDocumentNameForGridEntry(entry)
        let targetURL = targetURLForGridEntry(entry)
        let targetSoundFilename = targetSoundFilenameForGridEntry(entry)
        let targetAppURL = targetAppURLForGridEntry(entry)
        let targetClipboardText = targetClipboardTextForGridEntry(entry)
        let targetPreviewFilename = targetPreviewFilenameForGridEntry(entry)
        let targetSpokenFilename = targetSpokenFilenameForGridEntry(entry)
        let targetSpokenText = targetSpokenTextForGridEntry(entry)
        let targetShortcutURL = targetShortcutURLForGridEntry(entry)
        let shouldGoBackToPreviousDocument = targetBackDocumentCommandForGridEntry(entry)
        let shouldSelectPreviousDocument = targetPreviousDocumentCommandForGridEntry(entry)
        let shouldSelectNextDocument = targetNextDocumentCommandForGridEntry(entry)
        let hasPostBluetoothChainCommand = targetSoundFilename != nil ||
            targetSpokenText != nil ||
            targetSpokenFilename != nil ||
            targetShortcutURL != nil
        var didSendBluetooth = false

        func sendBluetoothIfNeeded() -> Bool {
            guard !didSendBluetooth else {
                return true
            }

            guard mainGridButtonMode.sendsBluetooth, !bluetoothSendTexts.isEmpty else {
                return true
            }

            guard ble.isConnected else {
                alertTitle = "Bluetooth not connected"
                renameAlertMessage = "Bluetooth needs to be connected\nin order to send data to the ESP32."
                return false
            }

            logMainButtonPress(entry)

            guard bluetoothSendTexts.allSatisfy(isBluetoothSendableText(_:)) else {
                showBluetoothUnsupportedTextBlockedPopup()
                return false
            }

            for sendText in bluetoothSendTexts {
                ble.sendLine(sendText)
            }

            didSendBluetooth = true
            return true
        }

        if let targetURL {
            UIApplication.shared.open(targetURL)
            return
        }

        if let targetAppURL {
            UIApplication.shared.open(targetAppURL) { success in
                guard !success else {
                    return
                }

                alertTitle = "App Not Available"
                renameAlertMessage = "Couldn't open \(targetAppURL.absoluteString)."
            }
            return
        }

        if let targetClipboardText {
            UIPasteboard.general.string = targetClipboardText
        }

        if let targetPreviewFilename {
            openPreviewFile(named: targetPreviewFilename)
        }

        if hasPostBluetoothChainCommand {
            guard sendBluetoothIfNeeded() else {
                return
            }
        }

        if let targetSoundFilename {
            playMainGridSound(named: targetSoundFilename)
        }

        if let targetSpokenText {
            speakMainGridText(targetSpokenText)
        } else if let targetSpokenFilename {
            alertTitle = "File Not Found"
            renameAlertMessage = "Couldn't find \(targetSpokenFilename.lowercased())."
        }

        if let targetShortcutURL {
            UIApplication.shared.open(targetShortcutURL)
        }

        if shouldGoBackToPreviousDocument {
            goBackToPreviousDocument()
        }

        if shouldSelectPreviousDocument {
            selectPreviousDocument()
        }

        if shouldSelectNextDocument {
            selectNextDocument()
        }

        if let targetDocumentName {
            guard selectDocumentNamedFromGrid(targetDocumentName) else {
                alertTitle = "File Not Found"
                renameAlertMessage = "Couldn't find \(targetDocumentName.lowercased())."
                return
            }
        }

        _ = sendBluetoothIfNeeded()
    }

    func bluetoothSendTexts(for entry: FunctionKeyEntry) -> [String] {
        entry.sendTexts
            .filter { sendText in
                targetDocumentNameForSendText(sendText) == nil &&
                targetURLForSendText(sendText) == nil &&
                targetShortcutURLForSendText(sendText) == nil &&
                targetSoundFilenameForSendText(sendText) == nil &&
                targetSpokenTextForSendText(sendText) == nil &&
                targetSpokenFilenameForSendText(sendText) == nil &&
                targetAppURLForSendText(sendText) == nil &&
                targetClipboardTextForSendText(sendText) == nil &&
                targetPreviewFilenameForSendText(sendText) == nil &&
                !isBackDocumentCommandText(sendText) &&
                !isPreviousDocumentCommandText(sendText) &&
                !isNextDocumentCommandText(sendText) &&
                !isWaitCommandText(sendText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) &&
                targetWidgetDescriptorForSendText(sendText) == nil
            }
            .map(normalizedBluetoothSendText)
    }

    func containsWaitCommand(in actionTokens: [String]) -> Bool {
        actionTokens.contains { actionToken in
            isWaitCommandText(actionToken.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
    }

    @MainActor
    func runWaitChainCommandTokens(
        _ actionTokens: [String],
        sourceEntry: FunctionKeyEntry?,
        respectsBluetoothMode: Bool
    ) async {
        var didLogBluetoothPress = false

        for actionToken in actionTokens {
            let trimmedActionToken = actionToken.trimmingCharacters(in: .whitespacesAndNewlines)
            let loweredActionToken = trimmedActionToken.lowercased()
            guard !trimmedActionToken.isEmpty else {
                continue
            }

            if isWaitCommandText(loweredActionToken) {
                guard let waitDuration = waitDurationForSendText(trimmedActionToken) else {
                    alertTitle = "Invalid wait"
                    renameAlertMessage = "Use wait followed by seconds,\nfor example wait 1 or wait 0.5."
                    return
                }

                let nanoseconds = min(waitDuration * 1_000_000_000, Double(UInt64.max))
                try? await Task.sleep(nanoseconds: UInt64(nanoseconds.rounded()))
                continue
            }

            if let targetURL = targetURLForSendText(trimmedActionToken) {
                await UIApplication.shared.open(targetURL)
                continue
            }

            if let targetAppURL = targetAppURLForSendText(trimmedActionToken) {
                UIApplication.shared.open(targetAppURL) { success in
                    guard !success else {
                        return
                    }

                    alertTitle = "App Not Available"
                    renameAlertMessage = "Couldn't open \(targetAppURL.absoluteString)."
                }
                continue
            }

            if let targetClipboardText = targetClipboardTextForSendText(trimmedActionToken) {
                UIPasteboard.general.string = targetClipboardText
                continue
            }

            if let targetPreviewFilename = targetPreviewFilenameForSendText(trimmedActionToken) {
                openPreviewFile(named: targetPreviewFilename)
                continue
            }

            if let targetSoundFilename = targetSoundFilenameForSendText(trimmedActionToken) {
                playMainGridSound(named: targetSoundFilename)
                continue
            }

            if let targetSpokenText = targetSpokenTextForSendText(trimmedActionToken) {
                speakMainGridText(targetSpokenText)
                continue
            } else if let targetSpokenFilename = targetSpokenFilenameForSendText(trimmedActionToken) {
                alertTitle = "File Not Found"
                renameAlertMessage = "Couldn't find \(targetSpokenFilename.lowercased())."
                return
            }

            if let targetShortcutURL = targetShortcutURLForSendText(trimmedActionToken) {
                await UIApplication.shared.open(targetShortcutURL)
                continue
            }

            if isBackDocumentCommandText(trimmedActionToken) {
                goBackToPreviousDocument()
                continue
            }

            if isPreviousDocumentCommandText(trimmedActionToken) {
                selectPreviousDocument()
                continue
            }

            if isNextDocumentCommandText(trimmedActionToken) {
                selectNextDocument()
                continue
            }

            if let targetDocumentName = targetDocumentNameForSendText(trimmedActionToken) {
                guard selectDocumentNamedFromGrid(targetDocumentName) else {
                    alertTitle = "File Not Found"
                    renameAlertMessage = "Couldn't find \(targetDocumentName.lowercased())."
                    return
                }
                continue
            }

            if targetWidgetDescriptorForSendText(trimmedActionToken) != nil {
                continue
            }

            guard sendBluetoothCommandToken(
                trimmedActionToken,
                sourceEntry: sourceEntry,
                respectsBluetoothMode: respectsBluetoothMode,
                didLogBluetoothPress: &didLogBluetoothPress
            ) else {
                return
            }
        }
    }

    private func sendBluetoothCommandToken(
        _ actionToken: String,
        sourceEntry: FunctionKeyEntry?,
        respectsBluetoothMode: Bool,
        didLogBluetoothPress: inout Bool
    ) -> Bool {
        guard !respectsBluetoothMode || mainGridButtonMode.sendsBluetooth else {
            return true
        }

        let bluetoothSendText = normalizedBluetoothSendText(actionToken)
        guard !bluetoothSendText.isEmpty else {
            return true
        }

        guard ble.isConnected else {
            alertTitle = "Bluetooth not connected"
            renameAlertMessage = "Bluetooth needs to be connected\nin order to send data to the ESP32."
            return false
        }

        if let sourceEntry, !didLogBluetoothPress {
            logMainButtonPress(sourceEntry)
            didLogBluetoothPress = true
        }

        guard isBluetoothSendableText(bluetoothSendText) else {
            showBluetoothUnsupportedTextBlockedPopup()
            return false
        }

        ble.sendLine(bluetoothSendText)
        return true
    }

    func speakMainGridEntry(_ entry: FunctionKeyEntry) {
        let spokenText = spokenTitle(for: entry)
            .replacingOccurrences(of: "\n", with: ", ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        speakMainGridText(spokenText)
    }

    func speakMainGridText(_ text: String) {
        guard !isSpkRecEnabled else {
            return
        }

        let spokenText = speechSynthesisText(from: text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spokenText.isEmpty else {
            return
        }

        stopSpokenGridText()
        activateAudioSessionForSpeechPlayback()

        let utterance = AVSpeechUtterance(string: spokenText)
        utterance.voice = resolvedSpeechVoice
        utterance.rate = Float(clampedTextToSpeechRate)
        speechSynthesizer.speak(utterance)
    }

    func speechSynthesisText(from text: String) -> String {
        let transformedText = text.map { character in
            spokenReplacementForEmoji(character) ?? String(character)
        }.joined()

        return transformedText
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func spokenReplacementForEmoji(_ character: Character) -> String? {
        guard db_emoji_parsing else {
            return nil
        }

        let configuration = emojiSpeechConfiguration()

        if let override = configuration.overrides[character] {
            return override
        }

        return derivedEmojiSpeechName(for: character, removableSuffixes: configuration.removableSuffixes)
    }

    private struct EmojiSpeechConfiguration {
        let overrides: [Character: String]
        let removableSuffixes: [String]
    }

    private func emojiSpeechConfiguration() -> EmojiSpeechConfiguration {
        let defaultConfiguration = parseEmojiSpeechConfiguration(ContentView.defaultEmojiSpeechConfigContents)

        guard let documentsDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return defaultConfiguration
        }

        let fileURL = documentsDirectoryURL.appendingPathComponent(ContentView.emojiSpeechConfigFilename)
        guard let fileContents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return defaultConfiguration
        }

        let loadedConfiguration = parseEmojiSpeechConfiguration(fileContents)
        let resolvedSuffixes = loadedConfiguration.removableSuffixes.isEmpty
            ? defaultConfiguration.removableSuffixes
            : loadedConfiguration.removableSuffixes

        return EmojiSpeechConfiguration(
            overrides: loadedConfiguration.overrides,
            removableSuffixes: resolvedSuffixes
        )
    }

    // The config file is intentionally plain text so it is easy to tweak without
    // touching code. Supported lines:
    // `suffix = symbol`
    // `⏯ = play pause media`
    private func parseEmojiSpeechConfiguration(_ contents: String) -> EmojiSpeechConfiguration {
        var overrides: [Character: String] = [:]
        var removableSuffixes: [String] = []

        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }
            guard !line.hasPrefix("#"), !line.hasPrefix("//") else {
                continue
            }

            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                continue
            }

            let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else {
                continue
            }

            if key.caseInsensitiveCompare("suffix") == .orderedSame {
                removableSuffixes.append(value.lowercased())
                continue
            }

            guard key.count == 1, let emojiCharacter = key.first else {
                continue
            }

            overrides[emojiCharacter] = value
        }

        return EmojiSpeechConfiguration(
            overrides: overrides,
            removableSuffixes: removableSuffixes
        )
    }

    private func derivedEmojiSpeechName(for character: Character, removableSuffixes: [String]) -> String? {
        guard !removableSuffixes.isEmpty else {
            return nil
        }

        let scalarNames = character.unicodeScalars.compactMap { scalar -> String? in
            guard scalar.properties.isEmoji || scalar.properties.isEmojiPresentation else {
                return nil
            }
            guard !scalar.properties.isVariationSelector else {
                return nil
            }
            guard !scalar.properties.isJoinControl else {
                return nil
            }

            return scalar.properties.name?.lowercased()
        }

        guard !scalarNames.isEmpty else {
            return nil
        }

        var derivedName = scalarNames.joined(separator: " ")
        var removedSuffix = false

        while let matchingSuffix = removableSuffixes.first(where: { suffix in
            derivedName == suffix || derivedName.hasSuffix(" " + suffix)
        }) {
            if derivedName == matchingSuffix {
                derivedName = ""
            } else {
                derivedName.removeLast(matchingSuffix.count)
                derivedName = derivedName.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            removedSuffix = true
        }

        guard removedSuffix else {
            return nil
        }

        let normalizedName = derivedName
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return normalizedName.isEmpty ? nil : normalizedName
    }

    func spokenTitle(for entry: FunctionKeyEntry) -> String {
        if let spokenCommandText = targetSpokenTextForGridEntry(entry) {
            return spokenCommandText
        }

        let rightTitle = resolvedAlternateDisplayText(for: entry)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !rightTitle.isEmpty {
            return speechMatchDisplayText(from: rightTitle)
        }

        if targetWidgetDescriptorForGridEntry(entry) != nil {
            return ""
        }

        let leftTitle = displayText(from: entry.primaryDisplayText)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !leftTitle.isEmpty else {
            return ""
        }

        return speechMatchDisplayText(from: leftTitle)
    }

    var resolvedSpeechVoice: AVSpeechSynthesisVoice? {
        if let selectedVoice = AVSpeechSynthesisVoice(identifier: selectedTextToSpeechVoiceIdentifier) {
            return selectedVoice
        }

        return AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
    }

    var clampedTextToSpeechRate: Double {
        min(max(textToSpeechRate, 0.2), 0.7)
    }

    func targetDocumentNameForGridEntry(_ entry: FunctionKeyEntry) -> String? {
        entry.sendTexts.first(where: { targetDocumentNameForSendText($0) != nil })
    }

    func targetBackDocumentCommandForGridEntry(_ entry: FunctionKeyEntry) -> Bool {
        entry.sendTexts.contains(where: isBackDocumentCommandText)
    }

    func targetPreviousDocumentCommandForGridEntry(_ entry: FunctionKeyEntry) -> Bool {
        entry.sendTexts.contains(where: isPreviousDocumentCommandText)
    }

    func targetNextDocumentCommandForGridEntry(_ entry: FunctionKeyEntry) -> Bool {
        entry.sendTexts.contains(where: isNextDocumentCommandText)
    }

    func isBackDocumentCommandText(_ sendText: String) -> Bool {
        sendText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "back"
    }

    func isPreviousDocumentCommandText(_ sendText: String) -> Bool {
        sendText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "prev"
    }

    func isNextDocumentCommandText(_ sendText: String) -> Bool {
        sendText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "next"
    }

    func targetDocumentNameForSendText(_ sendText: String) -> String? {
        let trimmedSendText = sendText.trimmingCharacters(in: .whitespacesAndNewlines)
        let loweredSendText = trimmedSendText.lowercased()
        guard !loweredSendText.hasPrefix("spk ") else {
            return nil
        }
        guard !isWaitCommandText(loweredSendText) else {
            return nil
        }
        guard !isShortcutCommandText(loweredSendText) else {
            return nil
        }
        guard !loweredSendText.hasPrefix("file ") else {
            return nil
        }

        if loweredSendText == "home" {
            return "home.txt"
        }

        return loweredSendText.hasSuffix(".txt") ? trimmedSendText : nil
    }

    func targetURLForGridEntry(_ entry: FunctionKeyEntry) -> URL? {
        entry.sendTexts.compactMap(targetURLForSendText).first
    }

    func targetClipboardTextForGridEntry(_ entry: FunctionKeyEntry) -> String? {
        entry.sendTexts.compactMap(targetClipboardTextForSendText).first
    }

    func targetPreviewFilenameForGridEntry(_ entry: FunctionKeyEntry) -> String? {
        entry.sendTexts.compactMap(targetPreviewFilenameForSendText).first
    }

    func targetAppURLForGridEntry(_ entry: FunctionKeyEntry) -> URL? {
        entry.sendTexts.compactMap(targetAppURLForSendText).first
    }

    func targetShortcutURLForGridEntry(_ entry: FunctionKeyEntry) -> URL? {
        entry.sendTexts.compactMap(targetShortcutURLForSendText).first
    }

    func targetURLForSendText(_ sendText: String) -> URL? {
        let trimmedSendText = sendText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSendText: String

        if trimmedSendText.lowercased().hasPrefix("https//") {
            normalizedSendText = "https://" + trimmedSendText.dropFirst("https//".count)
        } else if trimmedSendText.lowercased().hasPrefix("http//") {
            normalizedSendText = "http://" + trimmedSendText.dropFirst("http//".count)
        } else {
            normalizedSendText = trimmedSendText
        }

        let loweredSendText = normalizedSendText.lowercased()

        guard loweredSendText.hasPrefix("http://") || loweredSendText.hasPrefix("https://") else {
            return nil
        }

        if let url = URL(string: normalizedSendText) {
            return url
        }

        guard let encodedSendText = normalizedSendText.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) else {
            return nil
        }

        return URL(string: encodedSendText)
    }

    func targetSoundFilenameForGridEntry(_ entry: FunctionKeyEntry) -> String? {
        entry.sendTexts.compactMap(targetSoundFilenameForSendText).first
    }

    func targetSpokenTextForGridEntry(_ entry: FunctionKeyEntry) -> String? {
        entry.sendTexts.compactMap(targetSpokenTextForSendText).first
    }

    func targetSpokenFilenameForGridEntry(_ entry: FunctionKeyEntry) -> String? {
        entry.sendTexts.compactMap(targetSpokenFilenameForSendText).first
    }

    func targetWidgetDescriptorForGridEntry(_ entry: FunctionKeyEntry) -> MainGridWidgetDescriptor? {
        entry.sendTexts.compactMap(targetWidgetDescriptorForSendText).first
    }

    func targetAppURLForSendText(_ sendText: String) -> URL? {
        let trimmedSendText = sendText.trimmingCharacters(in: .whitespacesAndNewlines)
        let loweredSendText = trimmedSendText.lowercased()

        guard loweredSendText.hasPrefix("app ") else {
            return nil
        }

        let appName = String(trimmedSendText.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appName.isEmpty else {
            return nil
        }

        if appName.contains(":") {
            return URL(string: appName)
        }

        switch appName
            .lowercased()
            .replacingOccurrences(of: " ", with: "") {
        case "notes", "applenotes":
            return URL(string: "mobilenotes://")
        case "mail":
            return URL(string: "message://")
        case "messages", "imessage":
            return URL(string: "sms:")
        case "facetime":
            return URL(string: "facetime://")
        case "maps":
            return URL(string: "maps://")
        case "music":
            return URL(string: "music://")
        case "calendar":
            return URL(string: "calshow://")
        case "phone":
            return URL(string: "tel://")
        default:
            return URL(string: "\(appName.lowercased().replacingOccurrences(of: " ", with: ""))://")
        }
    }

    func targetShortcutURLForSendText(_ sendText: String) -> URL? {
        let trimmedSendText = sendText.trimmingCharacters(in: .whitespacesAndNewlines)
        let loweredSendText = trimmedSendText.lowercased()
        let shortcutName: String

        if loweredSendText.hasPrefix("sc ") {
            shortcutName = String(trimmedSendText.dropFirst(3))
        } else if loweredSendText.hasPrefix("shortcut ") {
            shortcutName = String(trimmedSendText.dropFirst(9))
        } else {
            return nil
        }

        let trimmedShortcutName = shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedShortcutName.isEmpty else {
            return nil
        }

        // Shortcuts expects the shortcut name in the URL query. Keep normal
        // letters readable, but encode spaces as %20 and protect query
        // separators so names like "hello & bye" remain one shortcut name.
        var allowedCharacters = CharacterSet.urlQueryAllowed
        allowedCharacters.remove(charactersIn: "&=+?")
        guard let encodedShortcutName = trimmedShortcutName.addingPercentEncoding(withAllowedCharacters: allowedCharacters) else {
            return nil
        }

        return URL(string: "shortcuts://run-shortcut?name=\(encodedShortcutName)")
    }

    func targetClipboardTextForSendText(_ sendText: String) -> String? {
        let trimmedSendText = sendText.trimmingCharacters(in: .whitespacesAndNewlines)
        let loweredSendText = trimmedSendText.lowercased()

        guard loweredSendText.hasPrefix("cb ") else {
            return nil
        }

        let quoteCharacters = CharacterSet(charactersIn: "'\"‘’“”`´")
        let clipboardText = String(trimmedSendText.dropFirst(3))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .unicodeScalars
            .filter { !quoteCharacters.contains($0) }
            .map(String.init)
            .joined()
            .replacingOccurrences(of: "\\", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clipboardText.isEmpty ? nil : clipboardText
    }

    func targetPreviewFilenameForSendText(_ sendText: String) -> String? {
        let trimmedSendText = sendText.trimmingCharacters(in: .whitespacesAndNewlines)
        let loweredSendText = trimmedSendText.lowercased()

        guard loweredSendText.hasPrefix("file ") else {
            return nil
        }

        let filename = String(trimmedSendText.dropFirst(5))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return filename.isEmpty ? nil : filename
    }

    func targetSoundFilenameForSendText(_ sendText: String) -> String? {
        let trimmedSendText = sendText.trimmingCharacters(in: .whitespacesAndNewlines)
        let loweredSendText = trimmedSendText.lowercased()
        let soundFilename: String

        guard !loweredSendText.hasPrefix("amb "),
              !loweredSendText.hasPrefix("ambient "),
              !loweredSendText.hasPrefix("cb "),
              !isWaitCommandText(loweredSendText),
              !isShortcutCommandText(loweredSendText),
              !isBareWidgetCommandText(loweredSendText) else {
            return nil
        }

        if loweredSendText.hasPrefix("snd ") {
            soundFilename = String(trimmedSendText.dropFirst(4))
        } else {
            soundFilename = trimmedSendText
        }

        let normalizedFilename = normalizedSoundFilename(soundFilename)
        let pathExtension = URL(fileURLWithPath: normalizedFilename).pathExtension.lowercased()
        guard supportedSoundExtensions.contains(pathExtension) else {
            return nil
        }

        return normalizedFilename.isEmpty ? nil : normalizedFilename
    }

    func targetSpokenTextForSendText(_ sendText: String) -> String? {
        let trimmedSendText = sendText.trimmingCharacters(in: .whitespacesAndNewlines)
        let loweredSendText = trimmedSendText.lowercased()

        guard loweredSendText.hasPrefix("spk ") else {
            return nil
        }

        let spokenText = displayText(from: String(trimmedSendText.dropFirst(4)))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spokenText.isEmpty else {
            return nil
        }

        if let spokenFilename = targetSpokenFilenameForSendText(trimmedSendText) {
            return spokenTextFileContents(named: spokenFilename)
        }

        return spokenText
    }

    func targetSpokenFilenameForSendText(_ sendText: String) -> String? {
        let trimmedSendText = sendText.trimmingCharacters(in: .whitespacesAndNewlines)
        let loweredSendText = trimmedSendText.lowercased()

        guard loweredSendText.hasPrefix("spk ") else {
            return nil
        }

        let spokenFilename = displayText(from: String(trimmedSendText.dropFirst(4)))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard spokenFilename.lowercased().hasSuffix(".txt") else {
            return nil
        }

        return spokenFilename.isEmpty ? nil : spokenFilename
    }

    private func spokenTextFileContents(named filename: String) -> String? {
        let trimmedFilename = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFilename.isEmpty else {
            return nil
        }

        if let documentsDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let documentFileURL = documentsDirectoryURL.appendingPathComponent(trimmedFilename)
            if FileManager.default.fileExists(atPath: documentFileURL.path),
               let contents = try? String(contentsOf: documentFileURL, encoding: .utf8) {
                return contents
            }
        }

        if let bundledFileURL = Bundle.main.resourceURL?.appendingPathComponent(trimmedFilename),
           FileManager.default.fileExists(atPath: bundledFileURL.path),
           let contents = try? String(contentsOf: bundledFileURL, encoding: .utf8) {
            return contents
        }

        return nil
    }

    func openPreviewFile(named filename: String) {
        let trimmedFilename = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFilename.isEmpty else {
            return
        }

        guard let fileURL = resolvedPreviewFileURL(named: trimmedFilename) else {
            alertTitle = "File Not Found"
            renameAlertMessage = "Couldn't find \(trimmedFilename.lowercased())."
            return
        }

        if let contents = try? String(contentsOf: fileURL, encoding: .utf8) {
            presentedPreviewFile = .text(filename: fileURL.lastPathComponent, contents: contents)
            return
        }

        if fileURL.pathExtension.caseInsensitiveCompare("pdf") == .orderedSame,
           let renderedPDFImage = renderedSinglePagePDFPreviewImage(from: fileURL) {
            presentedPreviewFile = .renderedImage(
                filename: fileURL.lastPathComponent,
                image: renderedPDFImage
            )
            return
        }

        guard UIImage(contentsOfFile: fileURL.path) != nil else {
            alertTitle = "Unsupported File"
            renameAlertMessage = "Couldn't preview \(trimmedFilename.lowercased())."
            return
        }

        presentedPreviewFile = .image(filename: fileURL.lastPathComponent, url: fileURL)
    }

    private func resolvedPreviewFileURL(named filename: String) -> URL? {
        let trimmedFilename = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFilename.isEmpty else {
            return nil
        }

        if let documentsDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
           let matchedDocumentFileURL = matchedRegularFileURL(in: documentsDirectoryURL, named: trimmedFilename) {
            return matchedDocumentFileURL
        }

        if let bundleResourceURL = Bundle.main.resourceURL,
           let matchedBundledFileURL = matchedRegularFileURL(in: bundleResourceURL, named: trimmedFilename) {
            return matchedBundledFileURL
        }

        return nil
    }

    private func matchedRegularFileURL(in directoryURL: URL, named filename: String) -> URL? {
        let exactFileURL = directoryURL.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: exactFileURL.path) {
            return exactFileURL
        }

        let candidateURLs = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return candidateURLs.first { candidateURL in
            let resourceValues = try? candidateURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues?.isRegularFile == true else {
                return false
            }

            return candidateURL.lastPathComponent.caseInsensitiveCompare(filename) == .orderedSame
        }
    }

    private func renderedSinglePagePDFPreviewImage(from fileURL: URL) -> UIImage? {
        guard let pdfDocument = PDFDocument(url: fileURL),
              pdfDocument.pageCount == 1,
              let pdfPage = pdfDocument.page(at: 0) else {
            return nil
        }

        let pageBounds = pdfPage.bounds(for: .mediaBox)
        guard pageBounds.width > 0, pageBounds.height > 0 else {
            return nil
        }

        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: pageBounds.size, format: rendererFormat)

        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: pageBounds.size))

            context.cgContext.saveGState()
            context.cgContext.translateBy(x: 0, y: pageBounds.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            pdfPage.draw(with: .mediaBox, to: context.cgContext)
            context.cgContext.restoreGState()
        }
    }

    private func parseWidgetTimerDuration(_ durationText: String) -> Int {
        let trimmedDurationText = durationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDurationText.isEmpty else {
            return 0
        }

        if let durationInSeconds = Int(trimmedDurationText) {
            return durationInSeconds
        }

        let loweredDurationText = trimmedDurationText.lowercased()
        let numericPrefix = loweredDurationText.prefix { $0.isNumber }
        guard let numericValue = Int(numericPrefix) else {
            return 0
        }

        let suffix = loweredDurationText
            .dropFirst(numericPrefix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let unit = suffix.first else {
            return numericValue
        }

        switch unit {
        case "m":
            return numericValue * 60
        case "h":
            return numericValue * 3600
        case "s":
            return numericValue
        default:
            return numericValue
        }
    }

    func targetWidgetDescriptorForSendText(_ sendText: String) -> MainGridWidgetDescriptor? {
        let trimmedSendText = sendText.trimmingCharacters(in: .whitespacesAndNewlines)
        let loweredSendText = trimmedSendText.lowercased()
        let widgetText: String

        if loweredSendText.hasPrefix("amb ") {
            let filename = normalizedSoundFilename(String(trimmedSendText.dropFirst(4)))
            return filename.isEmpty ? nil : .ambientSound(filename: filename)
        } else if loweredSendText.hasPrefix("ambient ") {
            let filename = normalizedSoundFilename(String(trimmedSendText.dropFirst(8)))
            return filename.isEmpty ? nil : .ambientSound(filename: filename)
        } else if isBareWidgetCommandText(loweredSendText) {
            widgetText = trimmedSendText
        } else {
            return nil
        }

        let trimmedWidgetText = widgetText.trimmingCharacters(in: .whitespacesAndNewlines)

        let components = trimmedWidgetText
            .split(separator: " ", omittingEmptySubsequences: true)
        guard let widgetName = components.first?.lowercased() else {
            return nil
        }

        if widgetName.hasSuffix(".txt") {
            return .textFileRandom(filename: String(components[0]))
        }

        switch widgetName {
        case "clock":
            let cityLabel: String?
            if components.count > 1 {
                let resolvedCityLabel = components.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                cityLabel = resolvedCityLabel.isEmpty ? nil : resolvedCityLabel
            } else {
                cityLabel = nil
            }
            return .clock(cityLabel: cityLabel)
        case "day":
            let cityLabel: String?
            if components.count > 1 {
                let resolvedCityLabel = components.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                cityLabel = resolvedCityLabel.isEmpty ? nil : resolvedCityLabel
            } else {
                cityLabel = nil
            }
            return .day(cityLabel: cityLabel)
        case "month":
            let cityLabel: String?
            if components.count > 1 {
                let resolvedCityLabel = components.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                cityLabel = resolvedCityLabel.isEmpty ? nil : resolvedCityLabel
            } else {
                cityLabel = nil
            }
            return .month(cityLabel: cityLabel)
        case "year":
            let cityLabel: String?
            if components.count > 1 {
                let resolvedCityLabel = components.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                cityLabel = resolvedCityLabel.isEmpty ? nil : resolvedCityLabel
            } else {
                cityLabel = nil
            }
            return .year(cityLabel: cityLabel)
        case "sec":
            let cityLabel: String?
            if components.count > 1 {
                let resolvedCityLabel = components.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                cityLabel = resolvedCityLabel.isEmpty ? nil : resolvedCityLabel
            } else {
                cityLabel = nil
            }
            return .second(cityLabel: cityLabel)
        case "min":
            let cityLabel: String?
            if components.count > 1 {
                let resolvedCityLabel = components.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                cityLabel = resolvedCityLabel.isEmpty ? nil : resolvedCityLabel
            } else {
                cityLabel = nil
            }
            return .minute(cityLabel: cityLabel)
        case "hour":
            let cityLabel: String?
            if components.count > 1 {
                let resolvedCityLabel = components.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                cityLabel = resolvedCityLabel.isEmpty ? nil : resolvedCityLabel
            } else {
                cityLabel = nil
            }
            return .hour(cityLabel: cityLabel)
        case "dow":
            let cityLabel: String?
            if components.count > 1 {
                let resolvedCityLabel = components.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                cityLabel = resolvedCityLabel.isEmpty ? nil : resolvedCityLabel
            } else {
                cityLabel = nil
            }
            return .dow(cityLabel: cityLabel)
        case "date":
            let cityLabel: String?
            if components.count > 1 {
                let resolvedCityLabel = components.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                cityLabel = resolvedCityLabel.isEmpty ? nil : resolvedCityLabel
            } else {
                cityLabel = nil
            }
            return .date(cityLabel: cityLabel)
        case "power", "battery":
            return .power
        case "add":
            return .add
        case "minus":
            let initialCount: Int
            if components.count > 1 {
                guard let parsedInitialCount = Int(components[1]) else {
                    return nil
                }
                initialCount = max(parsedInitialCount, 0)
            } else {
                initialCount = 0
            }
            return .minus(initialCount: initialCount)
        case "rnd", "random":
            if components.count > 1 {
                let filename = String(components.dropFirst().joined(separator: " "))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if filename.lowercased().hasSuffix(".txt") {
                    return .textFileRandom(filename: filename)
                }
            }

            let minimumValue: Int
            let maximumValue: Int

            switch components.count {
            case 1:
                minimumValue = 1
                maximumValue = 10
            case 2:
                guard let parsedMaximumValue = Int(components[1]) else {
                    return nil
                }
                minimumValue = 1
                maximumValue = parsedMaximumValue
            default:
                guard let parsedMinimumValue = Int(components[1]),
                      let parsedMaximumValue = Int(components[2]) else {
                    return nil
                }
                minimumValue = parsedMinimumValue
                maximumValue = parsedMaximumValue
            }

            return .random(minimumValue: minimumValue, maximumValue: maximumValue)
        case "stop", "stopwatch":
            return .stopwatch
        case "amb", "ambient":
            let filename = components.count > 1
                ? normalizedSoundFilename(String(components.dropFirst().joined(separator: " ")))
                : ""
            return filename.isEmpty ? nil : .ambientSound(filename: filename)
        case "timer":
            let initialDuration = components.count > 1
                ? parseWidgetTimerDuration(String(components[1]))
                : 0
            let completionText = components.count > 2
                ? String(components.dropFirst(2).joined(separator: " ")).trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            return .timer(
                initialDuration: max(initialDuration, 0),
                completion: timerCompletion(from: completionText)
            )
        default:
            return nil
        }
    }

    private func isBareWidgetCommandText(_ loweredText: String) -> Bool {
        let widgetCommands = [
            "add", "minus", "power", "rnd", "random", "clock", "date",
            "dow", "sec", "min", "hour", "day", "month", "year", "timer",
            "stop", "stopwatch", "amb", "ambient"
        ]

        return widgetCommands.contains { command in
            loweredText == command || loweredText.hasPrefix("\(command) ")
        }
    }

    private func isShortcutCommandText(_ loweredText: String) -> Bool {
        loweredText == "sc" ||
            loweredText.hasPrefix("sc ") ||
            loweredText == "shortcut" ||
            loweredText.hasPrefix("shortcut ")
    }

    private func waitDurationForSendText(_ sendText: String) -> TimeInterval? {
        let trimmedSendText = sendText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmedSendText.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
        guard parts.count == 2,
              parts[0].lowercased() == "wait" else {
            return nil
        }

        let durationText = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let seconds = Double(durationText), seconds.isFinite else {
            return nil
        }

        return max(seconds, 0)
    }

    func isWaitCommandText(_ loweredText: String) -> Bool {
        loweredText == "wait" || loweredText.hasPrefix("wait ")
    }

    private func timerCompletion(from text: String) -> MainGridTimerCompletion? {
        let trimmedText = displayText(from: text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return nil
        }

        let normalizedFilename = normalizedSoundFilename(trimmedText)
        let pathExtension = URL(fileURLWithPath: normalizedFilename).pathExtension.lowercased()
        if supportedSoundExtensions.contains(pathExtension) {
            return .sound(filename: normalizedFilename)
        }

        return .speech(text: trimmedText)
    }

    func playMainGridSound(named filename: String, repeats: Bool = false) {
        guard let audioURL = soundURL(named: filename) else {
            alertTitle = "Sound Not Found"
            renameAlertMessage = "Couldn't find \(filename)."
            return
        }

        activateAudioSessionForSpeechPlayback()

        do {
            let player = try AVAudioPlayer(contentsOf: audioURL)
            player.numberOfLoops = repeats ? -1 : 0
            player.prepareToPlay()
            player.play()
            soundEffectPlayer = player
        } catch {
            alertTitle = "Sound Error"
            renameAlertMessage = "Couldn't play \(filename)."
        }
    }

    func stopMainGridSoundPlayback() {
        soundEffectPlayer?.stop()
        soundEffectPlayer = nil
    }

    func soundURL(named filename: String) -> URL? {
        let normalizedFilename = normalizedSoundFilename(filename)
        guard !normalizedFilename.isEmpty else {
            return nil
        }

        if let documentsDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let documentSoundURL = documentsDirectoryURL.appendingPathComponent(normalizedFilename)
            if FileManager.default.fileExists(atPath: documentSoundURL.path) {
                return documentSoundURL
            }

            if let matchedDocumentSoundURL = matchedSoundURL(
                in: documentsDirectoryURL,
                matching: normalizedFilename
            ) {
                return matchedDocumentSoundURL
            }
        }

        guard let bundleResourceURL = Bundle.main.resourceURL else {
            return nil
        }

        let bundledSoundURL = bundleResourceURL.appendingPathComponent(normalizedFilename)
        if FileManager.default.fileExists(atPath: bundledSoundURL.path) {
            return bundledSoundURL
        }

        return matchedSoundURL(in: bundleResourceURL, matching: normalizedFilename)
    }

    private var supportedSoundExtensions: Set<String> {
        ["mp3", "wav", "m4a", "aiff", "aac", "caf"]
    }

    private func normalizedSoundFilename(_ filename: String) -> String {
        filename
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func normalizedSoundLookupKey(_ filename: String) -> String {
        normalizedSoundFilename(filename).lowercased()
    }

    private func matchedSoundURL(in directoryURL: URL, matching filename: String) -> URL? {
        let requestedLookupKey = normalizedSoundLookupKey(filename)
        guard !requestedLookupKey.isEmpty else {
            return nil
        }

        let candidateURLs = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [URLResourceKey.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        return candidateURLs?.first { candidateURL in
            let resourceValues = try? candidateURL.resourceValues(forKeys: [URLResourceKey.isRegularFileKey])
            guard resourceValues?.isRegularFile == true else {
                return false
            }

            guard supportedSoundExtensions.contains(candidateURL.pathExtension.lowercased()) else {
                return false
            }

            return normalizedSoundLookupKey(candidateURL.lastPathComponent) == requestedLookupKey
        }
    }

    func normalizedBluetoothSendText(_ sendText: String) -> String {
        let trimmedSendText = sendText.trimmingCharacters(in: .whitespacesAndNewlines)
        let loweredSendText = trimmedSendText.lowercased()

        if loweredSendText == "sp" {
            return " "
        }

        if let outputCommand = normalizedNumericBluetoothCommand(
            from: trimmedSendText,
            command: "out",
            expectedArgumentCount: 2
        ) {
            return outputCommand
        }

        if let pwmCommand = normalizedNumericBluetoothCommand(
            from: trimmedSendText,
            command: "pwm",
            expectedArgumentCount: 3
        ) {
            return pwmCommand
        }

        guard loweredSendText.first == "f",
              loweredSendText.dropFirst().allSatisfy({ $0.isNumber }) else {
            return sendText
        }

        return loweredSendText
    }

    private func normalizedNumericBluetoothCommand(
        from sendText: String,
        command: String,
        expectedArgumentCount: Int
    ) -> String? {
        let parts = sendText.split(whereSeparator: { $0.isWhitespace })
        guard parts.count == expectedArgumentCount + 1,
              parts[0].lowercased() == command else {
            return nil
        }

        let arguments = parts.dropFirst().map(String.init)
        guard arguments.allSatisfy({ Int($0) != nil }) else {
            return nil
        }

        return ([command] + arguments).joined(separator: ":")
    }

    func isBluetoothSendableText(_ sendText: String) -> Bool {
        sendText.unicodeScalars.allSatisfy(\.isASCII)
    }

    func showBluetoothUnsupportedTextBlockedPopup() {
        alertTitle = ""
        renameAlertMessage = nil

        Task { @MainActor in
            alertTitle = ""
            renameAlertMessage = "text couldn't be sent to bluetooth\nbecause it contains emoji or non-English text"
        }
    }

    func mainGridButtonLabel(
        entry: FunctionKeyEntry,
        index: Int,
        buttonHeight: CGFloat,
        backgroundOpacity: Double
    ) -> some View {
        let leftTitle = displayText(from: entry.primaryDisplayText)
        let rightTitle = displayText(from: resolvedAlternateDisplayText(for: entry))
        let title = buttonTitle(for: entry)

        return MainScreenButtonLabelView(
            entry: entry,
            index: index,
            widgetID: "\(selectedDocumentName)#\(index)",
            title: title,
            leftTitle: leftTitle,
            rightTitle: rightTitle,
            displayMode: displayMode,
            widgetDescriptor: targetWidgetDescriptorForGridEntry(entry),
            rightSymbolDisplay: parsedSFSymbolDisplay(for: entry),
            rightEmojiDisplay: parsedEmojiDisplay(for: entry),
            boxFontSize: boxFontSize,
            buttonHeight: buttonHeight,
            cornerRadius: mainGridButtonCornerRadius,
            borderWidth: mainGridButtonBorderWidth,
            isGridEditModeEnabled: isGridEditModeEnabled,
            activeDragIndex: activeDragIndex,
            backgroundOpacity: backgroundOpacity,
            sharedTimer: mainGridTimerState,
            ambientSoundState: mainGridAmbientSoundState,
            playSoundNamed: { playMainGridSound(named: $0) },
            playLoopingSoundNamed: { playMainGridSound(named: $0, repeats: true) },
            stopSoundPlayback: stopMainGridSoundPlayback,
            sendTimerCompletionAction: { entry in
                let bluetoothSendTexts = bluetoothSendTexts(for: entry)
                guard !bluetoothSendTexts.isEmpty else {
                    return true
                }

                guard ble.isConnected else {
                    alertTitle = "Bluetooth not connected"
                    renameAlertMessage = "Bluetooth needs to be connected\nin order to send data to the ESP32."
                    return false
                }

                guard bluetoothSendTexts.allSatisfy(isBluetoothSendableText(_:)) else {
                    showBluetoothUnsupportedTextBlockedPopup()
                    return false
                }

                for sendText in bluetoothSendTexts {
                    ble.sendLine(sendText)
                }

                return true
            },
            resolveSoundURL: { soundURL(named: $0) },
            activateAudioSession: activateAudioSessionForSpeechPlayback,
            reportSoundError: { title, message in
                alertTitle = title
                renameAlertMessage = nil
                Task { @MainActor in
                    alertTitle = title
                    renameAlertMessage = message
                }
            },
            shouldSpeakWidgetSelections: mainGridButtonMode.speaksText,
            speakText: speakMainGridText
        )
    }

    func isInteractiveMainGridWidgetEntry(_ entry: FunctionKeyEntry) -> Bool {
        guard !isGridEditModeEnabled,
              let widgetDescriptor = targetWidgetDescriptorForGridEntry(entry) else {
            return false
        }

        switch widgetDescriptor {
        case .add:
            return true
        case .minus:
            return true
        case .random:
            return true
        case .textFileRandom:
            return true
        case .stopwatch:
            return true
        case .ambientSound:
            return true
        case .timer:
            return true
        default:
            return false
        }
    }

    func isMainGridEntryHidden(_ entry: FunctionKeyEntry) -> Bool {
        guard !isGridEditModeEnabled else {
            return false
        }

        return entry.isHiddenInNormalMode
    }

    func mainGridButtonDragGesture(
        entry: FunctionKeyEntry,
        index: Int,
        gridDimensions: GridDimensions
    ) -> AnyGesture<DragGesture.Value> {
        AnyGesture(
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
        )
    }

    func editableText(for entry: FunctionKeyEntry) -> String {
        if entry.isBlankPlaceholder || isEmptyButtonEntry(entry) {
            return ""
        }

        return entry.rawLine
    }

    func isEmptyButtonEntry(_ entry: FunctionKeyEntry) -> Bool {
        let trimmedRawLine = entry.rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAlternateText = entry.alternateDisplayText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedRawLine.isEmpty && entry.sendTexts.isEmpty && trimmedAlternateText.isEmpty
    }

    func parsedSFSymbolDisplay(for entry: FunctionKeyEntry) -> (name: String, subtitle: String?)? {
        let rightText = displayText(from: resolvedAlternateDisplayText(for: entry))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let components = rightText.components(separatedBy: ":")
        let candidateName = components.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !candidateName.isEmpty,
              !candidateName.contains(where: \.isWhitespace),
              supportedMainScreenSFSymbolNames.contains(candidateName),
              UIImage(systemName: candidateName) != nil else {
            return nil
        }

        let subtitle = components
            .dropFirst()
            .joined(separator: ":")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (candidateName, subtitle.isEmpty ? nil : subtitle)
    }

    func parsedEmojiDisplay(for entry: FunctionKeyEntry) -> (emoji: String, subtitle: String?)? {
        let rightText = displayText(from: resolvedAlternateDisplayText(for: entry))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let components = rightText.components(separatedBy: ":")
        let candidateEmoji = components.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard isEmojiDisplayToken(candidateEmoji) else {
            return nil
        }

        let subtitle = components
            .dropFirst()
            .joined(separator: ":")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (candidateEmoji, subtitle.isEmpty ? nil : subtitle)
    }

    private func isEmojiDisplayToken(_ token: String) -> Bool {
        guard !token.isEmpty,
              !token.contains(where: \.isWhitespace),
              UIImage(systemName: token) == nil else {
            return false
        }

        // Treat only a single rendered emoji character as an emoji token.
        guard token.count == 1, let character = token.first else {
            return false
        }

        let isPlainASCIIAlphaNumeric = character.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && CharacterSet.alphanumerics.contains(scalar)
        }
        guard !isPlainASCIIAlphaNumeric else {
            return false
        }

        return character.unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation || scalar.properties.isEmoji
        }
    }

    private func rawLineWithoutHiddenMetadata(_ entry: FunctionKeyEntry) -> String {
        entry.rawLine
            .components(separatedBy: "::")
            .filter { $0 != hiddenButtonMetadataToken }
            .joined(separator: "::")
    }
}

struct MainScreenButtonLabelView: View {
    // Easy-to-tune size for buttons that display only a single emoji.
    private let loneEmojiScaleMultiplier: CGFloat = 1.5
    let entry: FunctionKeyEntry
    let index: Int
    let widgetID: String
    let title: String
    let leftTitle: String
    let rightTitle: String
    let displayMode: FunctionKeyDisplayMode
    let widgetDescriptor: MainGridWidgetDescriptor?
    let rightSymbolDisplay: (name: String, subtitle: String?)?
    let rightEmojiDisplay: (emoji: String, subtitle: String?)?
    let boxFontSize: Double
    let buttonHeight: CGFloat
    let cornerRadius: CGFloat
    let borderWidth: CGFloat
    let isGridEditModeEnabled: Bool
    let activeDragIndex: Int?
    let backgroundOpacity: Double
    @ObservedObject var sharedTimer: MainGridSharedTimerState
    @ObservedObject var ambientSoundState: MainGridAmbientSoundState
    let playSoundNamed: (String) -> Void
    let playLoopingSoundNamed: (String) -> Void
    let stopSoundPlayback: () -> Void
    let sendTimerCompletionAction: (FunctionKeyEntry) -> Bool
    let resolveSoundURL: (String) -> URL?
    let activateAudioSession: () -> Void
    let reportSoundError: (String, String) -> Void
    let shouldSpeakWidgetSelections: Bool
    let speakText: (String) -> Void

    // Adjust emojiScaleMultiplier to tune how much larger emoji should render than text.
    private let emojiScaleMultiplier: CGFloat = 1.5

    var body: some View {
        Group {
            if entry.isBlankPlaceholder || isEmptyButtonEntry {
                Group {
                    if isGridEditModeEnabled {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color.white.opacity(0.5), lineWidth: borderWidth)
                    } else {
                        Color.clear
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isHiddenMainGridEntry {
                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(buttonBackgroundColor)

                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(borderColor, lineWidth: borderWidth)

                    buttonContent
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var isHiddenMainGridEntry: Bool {
        !isGridEditModeEnabled && entry.isHiddenInNormalMode
    }

    @ViewBuilder
    private var buttonContent: some View {
        if let widgetDescriptor {
            widgetContent(descriptor: widgetDescriptor)
        } else if let rightSymbolDisplay {
            switch displayMode {
            case .left:
                textLabel(title: leftTitle)
            case .right:
                symbolContent(name: rightSymbolDisplay.name, subtitle: rightSymbolDisplay.subtitle)
            case .last:
                textLabel(title: lastRightTitleComponent)
            case .both:
                VStack(spacing: 6) {
                    textLabel(title: leftTitle)
                    symbolContent(name: rightSymbolDisplay.name, subtitle: rightSymbolDisplay.subtitle)
                }
            }
        } else if let rightEmojiDisplay {
            switch displayMode {
            case .left:
                textLabel(title: leftTitle)
            case .right:
                emojiContent(emoji: rightEmojiDisplay.emoji, subtitle: rightEmojiDisplay.subtitle)
            case .last:
                textLabel(title: lastRightTitleComponent)
            case .both:
                VStack(spacing: 6) {
                    textLabel(title: leftTitle)
                    emojiContent(emoji: rightEmojiDisplay.emoji, subtitle: rightEmojiDisplay.subtitle)
                }
            }
        } else {
            textLabel(title: title)
        }
    }
	//
	//-----------------------------------------------------------------------------------------------
	// MARK: - BM:😎 FUNCS widgetContent
	//
    @ViewBuilder
    private func widgetContent(descriptor: MainGridWidgetDescriptor) -> some View {
        switch descriptor {
        case .clock(let cityLabel):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 4) {
                    if let widgetCityLabel {
                        Text(widgetCityLabel)
                            .font(.system(size: boxFontSize, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }

                    Text(clockText(for: context.date, cityLabel: cityLabel))
                        .font(.system(size: boxFontSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .foregroundStyle(buttonTextColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .date(let cityLabel):
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(spacing: 4) {
                    Text(dateHeaderText(for: context.date, cityLabel: cityLabel))
                        .font(.system(size: boxFontSize, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)

                    Text(dateValueText(for: context.date))
                        .font(.system(size: boxFontSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .foregroundStyle(buttonTextColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .day(let cityLabel):
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let headerText = dowHeaderText(for: context.date, cityLabel: cityLabel)
                VStack(spacing: 4) {
                    if !headerText.isEmpty {
                        Text(headerText)
                            .font(.system(size: boxFontSize, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                    }

                    Text(dayOfMonthOrdinalText(for: context.date, cityLabel: cityLabel))
                        .font(.system(size: boxFontSize, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .foregroundStyle(buttonTextColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .month(let cityLabel):
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let headerText = dowHeaderText(for: context.date, cityLabel: cityLabel)
                VStack(spacing: 4) {
                    if !headerText.isEmpty {
                        Text(headerText)
                            .font(.system(size: boxFontSize, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                    }

                    Text(monthNameText(for: context.date, cityLabel: cityLabel))
                        .font(.system(size: boxFontSize, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .foregroundStyle(buttonTextColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .year(let cityLabel):
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let headerText = dowHeaderText(for: context.date, cityLabel: cityLabel)
                VStack(spacing: 4) {
                    if !headerText.isEmpty {
                        Text(headerText)
                            .font(.system(size: boxFontSize, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                    }

                    Text(yearText(for: context.date, cityLabel: cityLabel))
                        .font(.system(size: boxFontSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .foregroundStyle(buttonTextColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .second(let cityLabel):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let headerText = dowHeaderText(for: context.date, cityLabel: cityLabel)
                VStack(spacing: 4) {
                    if !headerText.isEmpty {
                        Text(headerText)
                            .font(.system(size: boxFontSize, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                    }

                    Text(widgetTimeComponentText(for: context.date, cityLabel: cityLabel, format: "ss"))
                        .font(.system(size: boxFontSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .foregroundStyle(buttonTextColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .minute(let cityLabel):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let headerText = dowHeaderText(for: context.date, cityLabel: cityLabel)
                VStack(spacing: 4) {
                    if !headerText.isEmpty {
                        Text(headerText)
                            .font(.system(size: boxFontSize, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                    }

                    Text(widgetTimeComponentText(for: context.date, cityLabel: cityLabel, format: "mm"))
                        .font(.system(size: boxFontSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .foregroundStyle(buttonTextColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .hour(let cityLabel):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let headerText = dowHeaderText(for: context.date, cityLabel: cityLabel)
                VStack(spacing: 4) {
                    if !headerText.isEmpty {
                        Text(headerText)
                            .font(.system(size: boxFontSize, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                    }

                    Text(widgetTimeComponentText(for: context.date, cityLabel: cityLabel, format: "HH"))
                        .font(.system(size: boxFontSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .foregroundStyle(buttonTextColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .dow(let cityLabel):
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let headerText = dowHeaderText(for: context.date, cityLabel: cityLabel)
                VStack(spacing: 4) {
                    if !headerText.isEmpty {
                        Text(headerText)
                            .font(.system(size: boxFontSize, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                    }

                    Text(dateFullWeekdayText(for: context.date))
                        .font(.system(size: boxFontSize, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .foregroundStyle(buttonTextColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .power:
            MainGridBatteryWidgetView(
                fontSize: boxFontSize,
                foregroundColor: buttonTextColor
            )
        case .add:
            MainGridStepUpCounterWidgetView(
                configurationText: rightTitleWithoutColorPrefix,
                fontSize: boxFontSize,
                foregroundColor: buttonTextColor
            )
        case .minus(let initialCount):
            MainGridStepDownCounterWidgetView(
                title: rightTitleWithoutColorPrefix,
                initialCount: initialCount,
                fontSize: boxFontSize,
                foregroundColor: buttonTextColor
            )
        case .random(let minimumValue, let maximumValue):
            MainGridRandomNumberWidgetView(
                title: rightTitleWithoutColorPrefix,
                minimumValue: minimumValue,
                maximumValue: maximumValue,
                fontSize: boxFontSize,
                foregroundColor: buttonTextColor
            )
        case .textFileRandom(let filename):
            MainGridRandomTextWidgetView(
                title: rightTitleWithoutColorPrefix,
                filename: filename,
                fontSize: boxFontSize,
                foregroundColor: buttonTextColor,
                onSelectionCommitted: shouldSpeakWidgetSelections ? { selectedText in
                    speakText(selectedText)
                } : nil,
                onRepeatRequested: shouldSpeakWidgetSelections ? { selectedText in
                    speakText(selectedText)
                } : nil
            )
        case .stopwatch:
            MainGridStopwatchWidgetView(
                title: rightTitleWithoutColorPrefix,
                fontSize: boxFontSize,
                foregroundColor: buttonTextColor
            )
        case .ambientSound(let filename):
            MainGridAmbientSoundWidgetView(
                widgetID: widgetID,
                title: rightTitleWithoutColorPrefix,
                filename: filename,
                fontSize: boxFontSize,
                foregroundColor: buttonTextColor,
                isInteractionEnabled: !isGridEditModeEnabled,
                sharedState: ambientSoundState,
                resolveSoundURL: resolveSoundURL,
                activateAudioSession: activateAudioSession,
                reportSoundError: reportSoundError
            )
        case .timer(let initialDuration, let completion):
            MainGridTimerWidgetView(
                widgetID: widgetID,
                entry: entry,
                configurationText: rightTitleWithoutColorPrefix,
                initialDuration: initialDuration,
                completion: completion,
                sharedTimer: sharedTimer,
                fontSize: boxFontSize,
                foregroundColor: buttonTextColor,
                onTimerCompletionAction: sendTimerCompletionAction,
                onPlayCompletionSound: playLoopingSoundNamed,
                onStopCompletionSound: stopSoundPlayback,
                onSpeakCompletionText: speakText
            )
        }
    }

    private var widgetCityLabel: String? {
        let trimmedRightTitle = rightTitleWithoutColorPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedRightTitle.isEmpty ? nil : trimmedRightTitle
    }

    private var widgetTimeZone: TimeZone? {
        guard let widgetCityLabel else {
            return nil
        }

        if let directMatch = TimeZone(identifier: widgetCityLabel) {
            return directMatch
        }

        let normalizedQuery = normalizedWidgetLocation(widgetCityLabel)
        let matchingIdentifier = TimeZone.knownTimeZoneIdentifiers.first { identifier in
            let normalizedIdentifier = normalizedWidgetLocation(identifier)
            let normalizedLastComponent = normalizedWidgetLocation(identifier.components(separatedBy: "/").last ?? identifier)
            return normalizedIdentifier == normalizedQuery ||
                normalizedLastComponent == normalizedQuery ||
                normalizedIdentifier.hasSuffix("/\(normalizedQuery)")
        }

        return matchingIdentifier.flatMap(TimeZone.init(identifier:))
    }

    private func clockText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = widgetTimeZone ?? .current
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func clockText(for date: Date, cityLabel: String?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = widgetTimeZone(for: cityLabel) ?? widgetTimeZone ?? .current
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func dateWeekdayText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = widgetTimeZone ?? .current
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private func dateFullWeekdayText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = widgetTimeZone ?? .current
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    private func widgetTimeComponentText(for date: Date, cityLabel: String?, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = widgetTimeZone(for: cityLabel) ?? .current
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private func parseWidgetTimerDuration(_ durationText: String) -> Int {
        let trimmedDurationText = durationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDurationText.isEmpty else {
            return 0
        }

        if let durationInSeconds = Int(trimmedDurationText) {
            return durationInSeconds
        }

        let loweredDurationText = trimmedDurationText.lowercased()
        let numericPrefix = loweredDurationText.prefix { $0.isNumber }
        guard let numericValue = Int(numericPrefix) else {
            return 0
        }

        let suffix = loweredDurationText
            .dropFirst(numericPrefix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let unit = suffix.first else {
            return numericValue
        }

        switch unit {
        case "m":
            return numericValue * 60
        case "h":
            return numericValue * 3600
        case "s":
            return numericValue
        default:
            return numericValue
        }
    }

    private func dayOfMonthOrdinalText(for date: Date, cityLabel: String?) -> String {
        var calendar = Calendar.current
        calendar.timeZone = widgetTimeZone(for: cityLabel) ?? .current
        let day = calendar.component(.day, from: date)
        let suffix: String
        switch day % 100 {
        case 11, 12, 13:
            suffix = "th"
        default:
            switch day % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(day)\(suffix)"
    }

    private func monthNameText(for date: Date, cityLabel: String?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = widgetTimeZone(for: cityLabel) ?? .current
        formatter.dateFormat = "LLLL"
        return formatter.string(from: date)
    }

    private func yearText(for date: Date, cityLabel: String?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = widgetTimeZone(for: cityLabel) ?? .current
        formatter.dateFormat = "yyyy"
        return formatter.string(from: date)
    }

    private func dateValueText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = widgetTimeZone ?? .current
        formatter.dateFormat = "dd/MM/yy"
        return formatter.string(from: date)
    }

    private func dateHeaderText(for date: Date, cityLabel: String?) -> String {
        let trimmedRightTitle = rightTitleWithoutColorPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedRightTitle.isEmpty {
            return trimmedRightTitle
        }

        return widgetDateCityCode(for: date, cityLabel: cityLabel)
    }

    private func dowHeaderText(for date: Date, cityLabel: String?) -> String {
        let trimmedRightTitle = rightTitleWithoutColorPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedRightTitle.isEmpty {
            return trimmedRightTitle
        }

        return ""
    }

    private func widgetDateCityCode(for date: Date, cityLabel: String?) -> String {
        let timeZone = widgetTimeZone(for: cityLabel) ?? .current
        let cityKeyCandidates = [
            cityLabel,
            timeZone.identifier.components(separatedBy: "/").last
        ]
            .compactMap { $0 }
            .map(normalizedWidgetLocation)

        let manualCityCodes: [String: String] = [
            "beijing": "BJD/PEK",
            "tokyo": "TYO/HND",
            "london": "LON",
            "new york": "NYC",
            "los angeles": "LAX",
            "sydney": "SYD",
            "melbourne": "MEL"
        ]

        for cityKey in cityKeyCandidates {
            if let mappedCode = manualCityCodes[cityKey] {
                return mappedCode.components(separatedBy: "/").first ?? mappedCode
            }
        }

        if let abbreviation = timeZone.abbreviation(for: date)?
            .components(separatedBy: "/")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !abbreviation.isEmpty,
           !abbreviation.uppercased().hasPrefix("GMT") {
            return abbreviation.uppercased()
        }

        let identifierTail = timeZone.identifier.components(separatedBy: "/").last ?? timeZone.identifier
        let compactIdentifier = identifierTail
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let words = compactIdentifier.split(separator: " ")
        let initialism = words
            .compactMap { $0.first.map { String($0).uppercased() } }
            .joined()
        if initialism.count >= 2 {
            return initialism
        }

        let lettersOnly = compactIdentifier.filter(\.isLetter).uppercased()
        if !lettersOnly.isEmpty {
            return String(lettersOnly.prefix(3))
        }

        return "LOC"
    }

    private func widgetTimeZone(for cityLabel: String?) -> TimeZone? {
        guard let cityLabel else {
            return nil
        }

        if let directMatch = TimeZone(identifier: cityLabel) {
            return directMatch
        }

        let normalizedQuery = normalizedWidgetLocation(cityLabel)
        let matchingIdentifier = TimeZone.knownTimeZoneIdentifiers.first { identifier in
            let normalizedIdentifier = normalizedWidgetLocation(identifier)
            let normalizedLastComponent = normalizedWidgetLocation(identifier.components(separatedBy: "/").last ?? identifier)
            return normalizedIdentifier == normalizedQuery ||
                normalizedLastComponent == normalizedQuery ||
                normalizedIdentifier.hasSuffix("/\(normalizedQuery)")
        }

        return matchingIdentifier.flatMap(TimeZone.init(identifier:))
    }

    private func normalizedWidgetLocation(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var rightTitleWithoutColorPrefix: String {
        let components = rightTitle.components(separatedBy: ":")

        if components.count > 1,
           let firstComponent = components.first?.trimmingCharacters(in: .whitespacesAndNewlines),
           firstComponent.count == 1,
           let existingCode = firstComponent.lowercased().first,
           "0123456789abcde".contains(existingCode) {
            return components.dropFirst().joined(separator: ":")
        }

        return rightTitle
    }

    private var lastRightTitleComponent: String {
        let components = rightTitleWithoutColorPrefix.components(separatedBy: ":")
        guard let lastComponent = components.last?.trimmingCharacters(in: .whitespacesAndNewlines),
              !lastComponent.isEmpty else {
            return rightTitleWithoutColorPrefix
        }

        return lastComponent
    }

    private func textLabel(title: String) -> some View {
        Text(title)
            .font(.system(size: boxFontSize, weight: .bold))
            .multilineTextAlignment(.center)
            .lineLimit(4)
            .truncationMode(.tail)
            .allowsTightening(true)
            .foregroundStyle(buttonTextColor)
    }

    private func symbolContent(name: String, subtitle: String?) -> some View {
        VStack(spacing: 4) {
            Image(systemName: name)
                .resizable()
                .scaledToFit()
                .foregroundStyle(symbolForegroundColor(for: name))
                .frame(
                    width: max(18, CGFloat(boxFontSize) * 1.5),
                    height: max(18, CGFloat(boxFontSize) * 1.5)
                )

            if let subtitle {
                textLabel(title: subtitle)
                    .lineLimit(2)
            }
        }
    }

    private func emojiContent(emoji: String, subtitle: String?) -> some View {
        Group {
            if let subtitle {
                VStack(spacing: 4) {
                    Text(emoji)
                        .font(.system(size: CGFloat(boxFontSize) * emojiScaleMultiplier))
                        .lineLimit(1)

                    textLabel(title: subtitle)
                        .lineLimit(2)
                }
            } else {
                Text(emoji)
                    .font(.system(size: max(18, CGFloat(boxFontSize) * loneEmojiScaleMultiplier)))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

	// MARK: - BM:🟪 color keycodes-btn
    private var buttonBackgroundColor: Color {
        guard !isEmptyButtonEntry else {
            return Color.black.opacity(backgroundOpacity)
        }

        switch (entry.buttonColorCode ?? "").lowercased() {
			
			case "0":	return .clear
			
			case "1": return Color(hex: "FF0000").opacity(backgroundOpacity)
			case "2": return Color(hex: "910000").opacity(backgroundOpacity)
			case "3": return Color(hex: "C97827").opacity(backgroundOpacity)
			case "4": return Color(hex: "5E3812").opacity(backgroundOpacity)
				
			case "5": return Color(hex: "8A8A8A").opacity(backgroundOpacity)
			case "6": return Color(hex: "0000FF").opacity(backgroundOpacity)
			case "7": return Color(hex: "171775").opacity(backgroundOpacity)
			case "8": return Color(hex: "919100").opacity(backgroundOpacity)
			case "9": return Color(hex: "595900").opacity(backgroundOpacity)
				
			case "a": return Color(hex: "424242").opacity(backgroundOpacity)
			case "b": return Color(hex: "00A600").opacity(backgroundOpacity)
			case "c": return Color(hex: "004F00").opacity(backgroundOpacity)
			case "d": return Color(hex: "D42AD4").opacity(backgroundOpacity)
			case "e": return Color(hex: "870087").opacity(backgroundOpacity)
			
			case "f": return Color(hex: "21A3A3").opacity(backgroundOpacity)
			case "g": return Color(hex: "CC1451").opacity(backgroundOpacity)
			case "h": return Color(hex: "CC7AA3").opacity(backgroundOpacity)
			case "i": return Color(hex: "CCCC00").opacity(backgroundOpacity)
			case "j": return Color(hex: "103954").opacity(backgroundOpacity)
			
			case "k": return Color(hex: "FF6666").opacity(backgroundOpacity)
			case "l": return Color(hex: "00CC66").opacity(backgroundOpacity)
			case "m": return Color(hex: "492545").opacity(backgroundOpacity)
			case "n": return Color(hex: "007FFF").opacity(backgroundOpacity)
			case "o": return Color(hex: "99004D").opacity(backgroundOpacity)
			
			case "p": return Color(hex: "FFB366").opacity(backgroundOpacity)
			case "q": return Color(hex: "009999").opacity(backgroundOpacity)
			case "r": return Color(hex: "994C00").opacity(backgroundOpacity)
			case "s": return Color(hex: "134CD4").opacity(backgroundOpacity)
			case "t": return Color(hex: "4E877B").opacity(backgroundOpacity)
			
			case "u": return Color(hex: "42151F").opacity(backgroundOpacity)
			case "v": return Color(hex: "FF8000").opacity(backgroundOpacity)
			case "w": return Color(hex: "635387").opacity(backgroundOpacity)
			case "x": return Color(hex: "9999FF").opacity(backgroundOpacity)
			case "y": return Color(hex: "20A663").opacity(backgroundOpacity)

			case "z": return Color(hex: "FFFFFF").opacity(backgroundOpacity)
				
			default:  return Color.black.opacity(backgroundOpacity)
        }
    }

    private var buttonTextColor: Color {
        .white
    }

    private var borderColor: Color {
        if isGridEditModeEnabled && activeDragIndex == index {
            return .green
        }

        return Color.white.opacity(0.8)
    }

    private func symbolForegroundColor(for name: String) -> Color {
        switch name {
        case "eye", "eye.slash":
            return .green
        default:
            return buttonTextColor
        }
    }

    private var isEmptyButtonEntry: Bool {
        let trimmedRawLine = entry.rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAlternateText = entry.alternateDisplayText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedRawLine.isEmpty && entry.sendTexts.isEmpty && trimmedAlternateText.isEmpty
    }
}

enum MainGridWidgetDescriptor {
    case clock(cityLabel: String?)
    case day(cityLabel: String?)
    case month(cityLabel: String?)
    case year(cityLabel: String?)
    case second(cityLabel: String?)
    case minute(cityLabel: String?)
    case hour(cityLabel: String?)
    case dow(cityLabel: String?)
    case date(cityLabel: String?)
    case power
    case add
    case minus(initialCount: Int)
    case random(minimumValue: Int, maximumValue: Int)
    case textFileRandom(filename: String)
    case stopwatch
    case ambientSound(filename: String)
    case timer(initialDuration: Int, completion: MainGridTimerCompletion?)
}

enum MainGridTimerCompletion {
    case sound(filename: String)
    case speech(text: String)
}

private struct MainGridBatteryWidgetView: View {
    let fontSize: Double
    let foregroundColor: Color
    @State private var batteryLevel: Float = UIDevice.current.batteryLevel
    @State private var batteryState: UIDevice.BatteryState = UIDevice.current.batteryState

    var body: some View {
        VStack(spacing: 4) {
            Text(batteryStateText)
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(batteryPercentageText)
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(foregroundColor)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            refreshBatteryState()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in
            refreshBatteryState()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in
            refreshBatteryState()
        }
    }

    private var batteryPercentageText: String {
        guard batteryLevel >= 0 else {
            return "--%"
        }

        return "\(Int((batteryLevel * 100).rounded()))%"
    }

    private var batteryStateText: String {
        switch batteryState {
        case .charging:
            return "charging"
        case .full:
            return "full"
        case .unplugged:
            return "battery"
        case .unknown:
            return "unknown"
        @unknown default:
            return "unknown"
        }
    }

    private func refreshBatteryState() {
        batteryLevel = UIDevice.current.batteryLevel
        batteryState = UIDevice.current.batteryState
    }
}

private struct MainGridStepUpCounterWidgetView: View {
    let configurationText: String
    let fontSize: Double
    let foregroundColor: Color

    @State private var initialCount = 0
    @State private var currentCount = 0
    @State private var title = ""

    var body: some View {
        VStack(spacing: 4) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.2)
                    .multilineTextAlignment(.center)
            }

            Text("\(currentCount)")
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.2)
        }
        .foregroundStyle(foregroundColor)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            TapGesture(count: 2)
                .onEnded {
                    currentCount = 0
                }
                .exclusively(before:
                    TapGesture()
                        .onEnded {
                            currentCount += 1
                        }
                )
        )
        .onAppear {
            applyConfiguration()
        }
        .onChange(of: configurationText) {
            applyConfiguration()
        }
    }

    private func applyConfiguration() {
        let components = configurationText.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let firstComponent = components.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parsedInitialCount = Int(firstComponent) ?? 0
        let parsedTitle: String

        if components.count > 1 {
            parsedTitle = String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if Int(firstComponent) == nil {
            parsedTitle = firstComponent
        } else {
            parsedTitle = ""
        }

        initialCount = max(parsedInitialCount, 0)
        currentCount = initialCount
        title = parsedTitle
    }
}

private struct MainGridStepDownCounterWidgetView: View {
    let title: String
    let initialCount: Int
    let fontSize: Double
    let foregroundColor: Color

    @State private var currentCount = 0

    var body: some View {
        VStack(spacing: 4) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.2)
                    .multilineTextAlignment(.center)
            }

            Text("\(currentCount)")
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.2)
        }
        .foregroundStyle(foregroundColor)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            TapGesture(count: 2)
                .onEnded {
                    currentCount = initialCount
                }
                .exclusively(before:
                    TapGesture()
                        .onEnded {
                            currentCount = max(0, currentCount - 1)
                        }
                )
        )
        .onAppear {
            currentCount = max(initialCount, 0)
        }
        .onChange(of: initialCount) {
            currentCount = max(initialCount, 0)
        }
    }
}

final class MainGridSharedTimerState: ObservableObject {
    struct TimerSnapshot {
        var configuredDuration = 0
        var remainingSeconds = 0
        var isRunning = false
        var isCompletionSoundLooping = false
    }

    @Published private var timerSnapshots: [String: TimerSnapshot] = [:]

    private var completions: [String: MainGridTimerCompletion?] = [:]
    private var startCompletionSoundLoopCallbacks: [String: (String) -> Void] = [:]
    private var stopCompletionSoundLoopCallbacks: [String: () -> Void] = [:]
    private var speakCompletionTextCallbacks: [String: (String) -> Void] = [:]
    private var timerCompletionActionCallbacks: [String: () -> Bool] = [:]
    private var endDates: [String: Date] = [:]
    private var tickTasks: [String: Task<Void, Never>] = [:]

    deinit {
        tickTasks.values.forEach { $0.cancel() }
    }

    func startTimer(
        widgetID: String,
        duration: Int,
        completion: MainGridTimerCompletion?,
        onTimerCompletionAction: @escaping () -> Bool,
        onPlayCompletionSound: @escaping (String) -> Void,
        onStopCompletionSound: @escaping () -> Void,
        onSpeakCompletionText: @escaping (String) -> Void
    ) {
        stopCompletionSoundLoop(widgetID: widgetID)
        cancelTickTask(widgetID: widgetID)

        let resolvedDuration = max(duration, 0)
        var snapshot = timerSnapshots[widgetID] ?? TimerSnapshot()
        snapshot.configuredDuration = resolvedDuration
        snapshot.remainingSeconds = resolvedDuration
        snapshot.isRunning = resolvedDuration > 0
        snapshot.isCompletionSoundLooping = false
        timerSnapshots[widgetID] = snapshot
        endDates[widgetID] = snapshot.isRunning ? Date().addingTimeInterval(TimeInterval(resolvedDuration)) : nil
        completions[widgetID] = normalizedCompletion(completion)
        timerCompletionActionCallbacks[widgetID] = onTimerCompletionAction
        startCompletionSoundLoopCallbacks[widgetID] = onPlayCompletionSound
        stopCompletionSoundLoopCallbacks[widgetID] = onStopCompletionSound
        speakCompletionTextCallbacks[widgetID] = onSpeakCompletionText

        guard snapshot.isRunning else {
            return
        }

        startTicking(for: widgetID)
    }

    func resumeTimer(
        widgetID: String,
        duration: Int,
        completion: MainGridTimerCompletion?,
        onTimerCompletionAction: @escaping () -> Bool,
        onPlayCompletionSound: @escaping (String) -> Void,
        onStopCompletionSound: @escaping () -> Void,
        onSpeakCompletionText: @escaping (String) -> Void
    ) {
        guard timerSnapshots[widgetID] != nil else {
            startTimer(
                widgetID: widgetID,
                duration: duration,
                completion: completion,
                onTimerCompletionAction: onTimerCompletionAction,
                onPlayCompletionSound: onPlayCompletionSound,
                onStopCompletionSound: onStopCompletionSound,
                onSpeakCompletionText: onSpeakCompletionText
            )
            return
        }

        stopCompletionSoundLoop(widgetID: widgetID)

        var snapshot = timerSnapshots[widgetID] ?? TimerSnapshot()
        if snapshot.remainingSeconds <= 0 {
            snapshot.remainingSeconds = max(duration, 0)
        }

        snapshot.configuredDuration = max(duration, 0)
        snapshot.isCompletionSoundLooping = false
        completions[widgetID] = normalizedCompletion(completion)
        timerCompletionActionCallbacks[widgetID] = onTimerCompletionAction
        startCompletionSoundLoopCallbacks[widgetID] = onPlayCompletionSound
        stopCompletionSoundLoopCallbacks[widgetID] = onStopCompletionSound
        speakCompletionTextCallbacks[widgetID] = onSpeakCompletionText

        guard snapshot.remainingSeconds > 0 else {
            snapshot.isRunning = false
            timerSnapshots[widgetID] = snapshot
            endDates[widgetID] = nil
            return
        }

        snapshot.isRunning = true
        timerSnapshots[widgetID] = snapshot
        endDates[widgetID] = Date().addingTimeInterval(TimeInterval(snapshot.remainingSeconds))
        startTicking(for: widgetID)
    }

    func pauseTimer(widgetID: String) {
        guard timerSnapshots[widgetID] != nil else {
            return
        }

        stopCompletionSoundLoop(widgetID: widgetID)
        syncRemainingFromEndDate(widgetID: widgetID)
        var snapshot = timerSnapshots[widgetID] ?? TimerSnapshot()
        snapshot.isRunning = false
        timerSnapshots[widgetID] = snapshot
        endDates[widgetID] = nil
        cancelTickTask(widgetID: widgetID)
    }

    func resetAndPauseTimer(
        widgetID: String,
        duration: Int,
        completion: MainGridTimerCompletion?,
        onTimerCompletionAction: @escaping () -> Bool,
        onPlayCompletionSound: @escaping (String) -> Void,
        onStopCompletionSound: @escaping () -> Void,
        onSpeakCompletionText: @escaping (String) -> Void
    ) {
        stopCompletionSoundLoop(widgetID: widgetID)
        cancelTickTask(widgetID: widgetID)

        let resolvedDuration = max(duration, 0)
        timerSnapshots[widgetID] = TimerSnapshot(
            configuredDuration: resolvedDuration,
            remainingSeconds: resolvedDuration,
            isRunning: false,
            isCompletionSoundLooping: false
        )
        endDates[widgetID] = nil
        completions[widgetID] = normalizedCompletion(completion)
        timerCompletionActionCallbacks[widgetID] = onTimerCompletionAction
        startCompletionSoundLoopCallbacks[widgetID] = onPlayCompletionSound
        stopCompletionSoundLoopCallbacks[widgetID] = onStopCompletionSound
        speakCompletionTextCallbacks[widgetID] = onSpeakCompletionText
    }

    func stopCompletionSoundLoop(widgetID: String) {
        guard var snapshot = timerSnapshots[widgetID], snapshot.isCompletionSoundLooping else {
            return
        }

        stopCompletionSoundLoopCallbacks[widgetID]?()
        snapshot.isCompletionSoundLooping = false
        timerSnapshots[widgetID] = snapshot
    }

    private func startTicking(for widgetID: String) {
        cancelTickTask(widgetID: widgetID)
        let task = Task { [weak self] in
            guard let self else {
                return
            }

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))

                await MainActor.run {
                    guard var snapshot = self.timerSnapshots[widgetID], snapshot.isRunning else {
                        return
                    }

                    self.syncRemainingFromEndDate(widgetID: widgetID)
                    snapshot = self.timerSnapshots[widgetID] ?? TimerSnapshot()

                    guard snapshot.remainingSeconds == 0 else {
                        return
                    }

                    snapshot.isRunning = false
                    self.timerSnapshots[widgetID] = snapshot
                    self.endDates[widgetID] = nil
                    self.cancelTickTask(widgetID: widgetID)
                    guard self.timerCompletionActionCallbacks[widgetID]?() ?? true else {
                        return
                    }

                    switch self.completions[widgetID] ?? nil {
                    case .sound(let filename):
                        self.startCompletionSoundLoopCallbacks[widgetID]?(filename)
                        snapshot.isCompletionSoundLooping = true
                        self.timerSnapshots[widgetID] = snapshot
                    case .speech(let text):
                        self.speakCompletionTextCallbacks[widgetID]?(text)
                    case nil:
                        break
                    }
                }
            }
        }
        tickTasks[widgetID] = task
    }

    private func syncRemainingFromEndDate(widgetID: String) {
        guard let endDate = endDates[widgetID] else {
            return
        }

        var snapshot = timerSnapshots[widgetID] ?? TimerSnapshot()
        snapshot.remainingSeconds = max(Int(ceil(endDate.timeIntervalSinceNow)), 0)
        timerSnapshots[widgetID] = snapshot
    }

    private func cancelTickTask(widgetID: String) {
        tickTasks[widgetID]?.cancel()
        tickTasks[widgetID] = nil
    }

    private func normalizedCompletion(_ completion: MainGridTimerCompletion?) -> MainGridTimerCompletion? {
        switch completion {
        case .sound(let filename):
            let trimmedFilename = filename.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedFilename.isEmpty ? nil : .sound(filename: trimmedFilename)
        case .speech(let text):
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedText.isEmpty ? nil : .speech(text: trimmedText)
        case nil:
            return nil
        }
    }

    func remainingSeconds(for widgetID: String, default defaultValue: Int) -> Int {
        timerSnapshots[widgetID]?.remainingSeconds ?? defaultValue
    }

    func isRunning(widgetID: String) -> Bool {
        timerSnapshots[widgetID]?.isRunning ?? false
    }

    func isCompletionSoundLooping(widgetID: String) -> Bool {
        timerSnapshots[widgetID]?.isCompletionSoundLooping ?? false
    }
}

final class MainGridAmbientSoundState: ObservableObject {
    @Published var activeWidgetID: String?
    @Published var currentVolume: Float = 0.05
    @Published var isPlaying = false

    private var activeFilename: String?
    private var player: AVAudioPlayer?

    func togglePlayback(
        widgetID: String,
        filename: String,
        resolveSoundURL: (String) -> URL?,
        activateAudioSession: () -> Void,
        reportSoundError: (String, String) -> Void
    ) {
        let normalizedFilename = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedFilename.isEmpty else {
            return
        }

        if activeWidgetID == widgetID, isPlaying {
            stopPlayback()
            return
        }

        if activeWidgetID != widgetID || activeFilename != normalizedFilename {
            currentVolume = 0.05
        }

        guard let audioURL = resolveSoundURL(normalizedFilename) else {
            reportSoundError("Sound Not Found", "Couldn't find \(normalizedFilename).")
            return
        }

        activateAudioSession()

        do {
            let player = try AVAudioPlayer(contentsOf: audioURL)
            player.numberOfLoops = -1
            player.volume = currentVolume
            player.prepareToPlay()
            player.play()
            self.player = player
            activeWidgetID = widgetID
            activeFilename = normalizedFilename
            isPlaying = true
        } catch {
            reportSoundError("Sound Error", "Couldn't play \(normalizedFilename).")
        }
    }

    func adjustVolume(widgetID: String, by delta: Float) {
        guard activeWidgetID == nil || activeWidgetID == widgetID else {
            return
        }

        let updatedVolume = min(max(currentVolume + delta, 0.0), 1.0)
        currentVolume = updatedVolume
        player?.volume = updatedVolume
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        activeWidgetID = nil
        activeFilename = nil
        isPlaying = false
    }
}

private struct MainGridTimerWidgetView: View {
    let widgetID: String
    let entry: FunctionKeyEntry
    let configurationText: String
    let initialDuration: Int
    let completion: MainGridTimerCompletion?
    @ObservedObject var sharedTimer: MainGridSharedTimerState
    let fontSize: Double
    let foregroundColor: Color
    let onTimerCompletionAction: (FunctionKeyEntry) -> Bool
    let onPlayCompletionSound: (String) -> Void
    let onStopCompletionSound: () -> Void
    let onSpeakCompletionText: (String) -> Void

    @State private var configuredDuration = 0
    @State private var title = ""

    var body: some View {
        VStack(spacing: 4) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .multilineTextAlignment(.center)
            }

            Text(formattedRemainingTime)
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .foregroundStyle(foregroundColor)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            TapGesture(count: 2)
                .onEnded {
                    resetAndPause()
                }
                .exclusively(before:
                    TapGesture()
                        .onEnded {
                            togglePlayback()
                        }
                )
        )
        .onAppear {
            applyConfiguration()
        }
        .onChange(of: configurationText) {
            applyConfiguration()
        }
        .onChange(of: initialDuration) {
            applyConfiguration()
        }
    }

    private var displayedRemainingSeconds: Int {
        sharedTimer.remainingSeconds(for: widgetID, default: configuredDuration)
    }

    private var formattedRemainingTime: String {
        let remainingSeconds = max(displayedRemainingSeconds, 0)
        let hours = remainingSeconds / 3600
        let minutes = (remainingSeconds % 3600) / 60
        let seconds = remainingSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func applyConfiguration() {
        configuredDuration = max(initialDuration, 0)
        title = configurationText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sharedTimer.isRunning(widgetID: widgetID),
              !sharedTimer.isCompletionSoundLooping(widgetID: widgetID) else {
            return
        }

        sharedTimer.resetAndPauseTimer(
            widgetID: widgetID,
            duration: configuredDuration,
            completion: completion,
            onTimerCompletionAction: { onTimerCompletionAction(entry) },
            onPlayCompletionSound: onPlayCompletionSound,
            onStopCompletionSound: onStopCompletionSound,
            onSpeakCompletionText: onSpeakCompletionText
        )
    }

    private func togglePlayback() {
        guard configuredDuration > 0 else {
            return
        }

        if sharedTimer.isCompletionSoundLooping(widgetID: widgetID) {
            sharedTimer.stopCompletionSoundLoop(widgetID: widgetID)
            return
        }

        if sharedTimer.isRunning(widgetID: widgetID) {
            sharedTimer.pauseTimer(widgetID: widgetID)
            return
        }

        sharedTimer.resumeTimer(
            widgetID: widgetID,
            duration: configuredDuration,
            completion: completion,
            onTimerCompletionAction: { onTimerCompletionAction(entry) },
            onPlayCompletionSound: onPlayCompletionSound,
            onStopCompletionSound: onStopCompletionSound,
            onSpeakCompletionText: onSpeakCompletionText
        )
    }

    private func resetAndPause() {
        sharedTimer.resetAndPauseTimer(
            widgetID: widgetID,
            duration: configuredDuration,
            completion: completion,
            onTimerCompletionAction: { onTimerCompletionAction(entry) },
            onPlayCompletionSound: onPlayCompletionSound,
            onStopCompletionSound: onStopCompletionSound,
            onSpeakCompletionText: onSpeakCompletionText
        )
    }
}

private struct MainGridAmbientSoundWidgetView: View {
    let widgetID: String
    let title: String
    let filename: String
    let fontSize: Double
    let foregroundColor: Color
    let isInteractionEnabled: Bool
    @ObservedObject var sharedState: MainGridAmbientSoundState
    let resolveSoundURL: (String) -> URL?
    let activateAudioSession: () -> Void
    let reportSoundError: (String, String) -> Void

    var body: some View {
        Text(displayTitle)
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .lineLimit(4)
            .minimumScaleFactor(0.2)
            .multilineTextAlignment(.center)
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                TapGesture(count: 3)
                    .onEnded {
                        guard isInteractionEnabled else {
                            return
                        }
                        sharedState.togglePlayback(
                            widgetID: widgetID,
                            filename: filename,
                            resolveSoundURL: resolveSoundURL,
                            activateAudioSession: activateAudioSession,
                            reportSoundError: reportSoundError
                        )
                    }
                    .exclusively(before:
                        TapGesture(count: 2)
                            .onEnded {
                                guard isInteractionEnabled else {
                                    return
                                }
                                sharedState.adjustVolume(widgetID: widgetID, by: 0.05)
                            }
                            .exclusively(before:
                                TapGesture()
                                    .onEnded {
                                        guard isInteractionEnabled else {
                                            return
                                        }
                                        sharedState.adjustVolume(widgetID: widgetID, by: -0.05)
                                    }
                            )
                    )
            )
    }

    private var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTitle.isEmpty else {
            return trimmedTitle
        }
        return ""
    }
}

private struct MainGridStopwatchWidgetView: View {
    let title: String
    let fontSize: Double
    let foregroundColor: Color

    @State private var elapsedTenths = 0
    @State private var isRunning = false
    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 4) {
            if !trimmedTitle.isEmpty {
                Text(trimmedTitle)
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.2)
                    .multilineTextAlignment(.center)
            }

            Text(formattedElapsedTime)
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.2)
        }
        .foregroundStyle(foregroundColor)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            isRunning.toggle()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            isRunning = false
            elapsedTenths = 0
        }
        .onReceive(ticker) { _ in
            guard isRunning else {
                return
            }

            elapsedTenths += 1
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var formattedElapsedTime: String {
        let totalSeconds = elapsedTenths / 10
        let tenths = elapsedTenths % 10
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d.%01d", hours, minutes, seconds, tenths)
        }

        return String(format: "%02d:%02d.%01d", minutes, seconds, tenths)
    }
}

private struct MainGridRandomNumberWidgetView: View {
    let title: String
    let minimumValue: Int
    let maximumValue: Int
    let fontSize: Double
    let foregroundColor: Color

    @State private var displayedValue = 0
    @State private var animationTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 4) {
            if !trimmedTitle.isEmpty {
                Text(trimmedTitle)
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.2)
                    .multilineTextAlignment(.center)
            }

            Text("\(displayedValue)")
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.2)
        }
        .foregroundStyle(foregroundColor)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            generateRandomValue()
        }
        .onAppear {
            displayedValue = normalizedRange.lowerBound
        }
        .onChange(of: minimumValue) {
            displayedValue = normalizedRange.lowerBound
        }
        .onChange(of: maximumValue) {
            displayedValue = normalizedRange.lowerBound
        }
        .onDisappear {
            animationTask?.cancel()
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedRange: ClosedRange<Int> {
        let lowerBound = min(minimumValue, maximumValue)
        let upperBound = max(minimumValue, maximumValue)
        return lowerBound...upperBound
    }

    private func generateRandomValue() {
        animationTask?.cancel()

        animationTask = Task {
            for _ in 0..<10 {
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    displayedValue = Int.random(in: normalizedRange)
                    ButtonClickFeedback.playIfEnabled()
                }

                try? await Task.sleep(for: .milliseconds(100))
            }

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                displayedValue = Int.random(in: normalizedRange)
                animationTask = nil
            }
        }
    }
}

private struct MainGridRandomTextWidgetView: View {
    let title: String
    let filename: String
    let fontSize: Double
    let foregroundColor: Color
    let onSelectionCommitted: ((String) -> Void)?
    let onRepeatRequested: ((String) -> Void)?

    @State private var displayedLine = ""
    @State private var availableLines: [String] = []
    @State private var shuffledLines: [String] = []
    @State private var nextShuffledLineIndex = 0
    @State private var animationTask: Task<Void, Never>?

    var body: some View {
        Text(displayedLine)
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .multilineTextAlignment(.center)
            .lineLimit(4)
            .minimumScaleFactor(0.2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(foregroundColor)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            TapGesture(count: 2)
                .onEnded {
                    repeatDisplayedLine()
                }
                .exclusively(before:
                    TapGesture()
                        .onEnded {
                            chooseRandomLine()
                        }
                )
        )
        .task(id: "\(filename)|\(title)") {
            availableLines = loadLines()
            shuffledLines = []
            nextShuffledLineIndex = 0
            displayedLine = trimmedTitle
        }
        .onDisappear {
            animationTask?.cancel()
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func chooseRandomLine() {
        let lines = availableLines.isEmpty ? loadLines() : availableLines
        availableLines = lines

        guard !lines.isEmpty else {
            displayedLine = ""
            return
        }

        let previousLine = displayedLine
        let selectedLine = nextQueuedLine(from: lines, avoiding: previousLine)

        animationTask?.cancel()
        animationTask = Task {
            for _ in 0..<10 {
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    displayedLine = previewLine(from: lines, avoiding: previousLine, preferredLine: selectedLine)
                    ButtonClickFeedback.playIfEnabled()
                }

                try? await Task.sleep(for: .milliseconds(100))
            }

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                displayedLine = selectedLine
                onSelectionCommitted?(selectedLine)
                animationTask = nil
            }
        }
    }

    private func nextQueuedLine(from lines: [String], avoiding previousLine: String) -> String {
        if shuffledLines.count != lines.count || Set(shuffledLines) != Set(lines) {
            shuffledLines = reshuffledLines(from: lines, avoidingFirst: previousLine)
            nextShuffledLineIndex = 0
        }

        guard !shuffledLines.isEmpty else {
            return ""
        }

        if nextShuffledLineIndex >= shuffledLines.count {
            shuffledLines = reshuffledLines(from: lines, avoidingFirst: previousLine)
            nextShuffledLineIndex = 0
        }

        let selectedLine = shuffledLines[nextShuffledLineIndex]
        nextShuffledLineIndex += 1
        return selectedLine
    }

    private func reshuffledLines(from lines: [String], avoidingFirst previousLine: String) -> [String] {
        guard lines.count > 1 else {
            return lines
        }

        var shuffled = lines.shuffled()
        if shuffled.first == previousLine,
           let replacementIndex = shuffled.firstIndex(where: { $0 != previousLine }) {
            shuffled.swapAt(0, replacementIndex)
        }
        return shuffled
    }

    private func previewLine(from lines: [String], avoiding previousLine: String, preferredLine: String) -> String {
        let previewCandidates = lines.filter { $0 != previousLine }
        if let previewLine = previewCandidates.randomElement() {
            return previewLine
        }

        if !preferredLine.isEmpty {
            return preferredLine
        }

        guard lines.count > 1 else {
            return lines.first ?? ""
        }

        return lines.randomElement() ?? ""
    }

    private func repeatDisplayedLine() {
        let trimmedDisplayedLine = displayedLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDisplayedLine.isEmpty else {
            return
        }

        onRepeatRequested?(trimmedDisplayedLine)
    }

    private func loadLines() -> [String] {
        guard let fileURL = textFileURL(named: filename),
              let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }

        return contents
            .components(separatedBy: CharacterSet.newlines)
            .compactMap { line in
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("//") else {
                    return nil
                }
                return line.replacingOccurrences(of: "\r", with: "")
            }
    }

    private func textFileURL(named filename: String) -> URL? {
        let trimmedFilename = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFilename.isEmpty else {
            return nil
        }

        if let documentsDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let documentFileURL = documentsDirectoryURL.appendingPathComponent(trimmedFilename)
            if FileManager.default.fileExists(atPath: documentFileURL.path) {
                return documentFileURL
            }
        }

        return Bundle.main.resourceURL?.appendingPathComponent(trimmedFilename)
    }
}

import SwiftUI
import AVFoundation
import UIKit
import Combine

extension MainScreen {
    private var defaultNewButtonEntryText: String { "cb ::" }
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
            return rawLineWithoutHiddenMetadata(entry)
        }

        let rawRightText = components
            .dropFirst()
            .joined(separator: "::")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rightComponents = rawRightText.components(separatedBy: ":")

        if let firstComponent = rightComponents.first,
           firstComponent.count == 1,
           let manualColorCode = firstComponent.lowercased().first,
           "lwbgorpucya12345".contains(manualColorCode) {
            let remainingText = rightComponents
                .dropFirst()
                .joined(separator: ":")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return remainingText.isEmpty ? rawRightText : remainingText
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

        let bluetoothSendTexts = bluetoothSendTexts(for: entry)
        let targetDocumentName = targetDocumentNameForGridEntry(entry)
        let targetURL = targetURLForGridEntry(entry)
        let targetSoundFilename = targetSoundFilenameForGridEntry(entry)
        let targetAppURL = targetAppURLForGridEntry(entry)
        let targetClipboardText = targetClipboardTextForGridEntry(entry)
        let targetSpokenText = targetSpokenTextForGridEntry(entry)

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

        if let targetSoundFilename {
            playMainGridSound(named: targetSoundFilename)
        }

        if let targetSpokenText {
            speakMainGridText(targetSpokenText)
        }

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

        guard ble.isConnected else {
            alertTitle = "Bluetooth not connected"
            renameAlertMessage = "Bluetooth needs to be connected\nin order to send data to the ESP32."
            return
        }

        logMainButtonPress(entry)

        guard bluetoothSendTexts.allSatisfy(isASCIIOnlyBluetoothText(_:)) else {
            showBluetoothEmojiBlockedPopup()
            return
        }

        for sendText in bluetoothSendTexts {
            ble.sendLine(sendText)
        }
    }

    func bluetoothSendTexts(for entry: FunctionKeyEntry) -> [String] {
        entry.sendTexts
            .filter { sendText in
                targetDocumentNameForSendText(sendText) == nil &&
                    targetURLForSendText(sendText) == nil &&
                    targetSoundFilenameForSendText(sendText) == nil &&
                    targetSpokenTextForSendText(sendText) == nil &&
                    targetAppURLForSendText(sendText) == nil &&
                    targetClipboardTextForSendText(sendText) == nil &&
                    targetWidgetDescriptorForSendText(sendText) == nil
            }
            .map(normalizedBluetoothSendText)
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

    func targetDocumentNameForSendText(_ sendText: String) -> String? {
        let trimmedSendText = sendText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedSendText.lowercased().hasSuffix(".txt") ? trimmedSendText : nil
    }

    func targetURLForGridEntry(_ entry: FunctionKeyEntry) -> URL? {
        entry.sendTexts.compactMap(targetURLForSendText).first
    }

    func targetClipboardTextForGridEntry(_ entry: FunctionKeyEntry) -> String? {
        entry.sendTexts.compactMap(targetClipboardTextForSendText).first
    }

    func targetAppURLForGridEntry(_ entry: FunctionKeyEntry) -> URL? {
        entry.sendTexts.compactMap(targetAppURLForSendText).first
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
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clipboardText.isEmpty ? nil : clipboardText
    }

    func targetSoundFilenameForSendText(_ sendText: String) -> String? {
        let trimmedSendText = sendText.trimmingCharacters(in: .whitespacesAndNewlines)
        let loweredSendText = trimmedSendText.lowercased()

        guard !loweredSendText.hasPrefix("snd "),
              !loweredSendText.hasPrefix("amb "),
              !loweredSendText.hasPrefix("ambient "),
              !loweredSendText.hasPrefix("cb "),
              !loweredSendText.hasPrefix("wid "),
              !loweredSendText.hasPrefix("widget ") else {
            return nil
        }

        let normalizedFilename = normalizedSoundFilename(trimmedSendText)
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
        return spokenText.isEmpty ? nil : spokenText
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
        } else if loweredSendText.hasPrefix("wid ") {
            widgetText = String(trimmedSendText.dropFirst(4))
        } else if loweredSendText.hasPrefix("widget ") {
            widgetText = String(trimmedSendText.dropFirst(7))
        } else {
            return nil
        }

        let trimmedWidgetText = widgetText.trimmingCharacters(in: .whitespacesAndNewlines)
        let loweredWidgetText = trimmedWidgetText.lowercased()

        if loweredWidgetText.hasPrefix("timer:") {
            let completionSoundFilename = normalizedSoundFilename(
                String(trimmedWidgetText.dropFirst("timer:".count))
            )
            return .timer(completionSoundFilename: completionSoundFilename.isEmpty ? nil : completionSoundFilename)
        }

        if loweredWidgetText.hasPrefix("timer ") {
            let completionSoundFilename = normalizedSoundFilename(
                String(trimmedWidgetText.dropFirst("timer".count))
            )
            return .timer(completionSoundFilename: completionSoundFilename.isEmpty ? nil : completionSoundFilename)
        }

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
            return .clock
        case "date":
            return .date
        case "power", "battery":
            return .power
        case "add":
            return .add
        case "minus":
            return .minus
        case "rnd", "random":
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
            let completionSoundFilename = components.count > 1
                ? normalizedSoundFilename(String(components.dropFirst().joined(separator: " ")))
                : ""
            return .timer(completionSoundFilename: completionSoundFilename.isEmpty ? nil : completionSoundFilename)
        default:
            return nil
        }
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

        guard loweredSendText.first == "f",
              loweredSendText.dropFirst().allSatisfy({ $0.isNumber }) else {
            return sendText
        }

        return loweredSendText
    }

    func isASCIIOnlyBluetoothText(_ sendText: String) -> Bool {
        sendText.unicodeScalars.allSatisfy(\.isASCII)
    }

    func showBluetoothEmojiBlockedPopup() {
        alertTitle = ""
        renameAlertMessage = nil

        Task { @MainActor in
            alertTitle = ""
            renameAlertMessage = "text couldn't be sent to bluetooth\nbecause it contains emoji"
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
                guard ble.isConnected else {
                    return
                }

                let bluetoothSendTexts = bluetoothSendTexts(for: entry)
                guard bluetoothSendTexts.allSatisfy(isASCIIOnlyBluetoothText(_:)) else {
                    return
                }

                for sendText in bluetoothSendTexts {
                    ble.sendLine(sendText)
                }
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
            return defaultNewButtonEntryText
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
    let sendTimerCompletionAction: (FunctionKeyEntry) -> Void
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

    @ViewBuilder
    private func widgetContent(descriptor: MainGridWidgetDescriptor) -> some View {
        switch descriptor {
        case .clock:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 4) {
                    if let widgetCityLabel {
                        Text(widgetCityLabel)
                            .font(.system(size: boxFontSize, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }

                    Text(clockText(for: context.date))
                        .font(.system(size: boxFontSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .foregroundStyle(buttonTextColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .date:
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(spacing: 4) {
                    Text(dateWeekdayText(for: context.date))
                    .font(.system(size: max(12, boxFontSize * 0.85), weight: .bold, design: .rounded))

                    Text(dateValueText(for: context.date))
                    .font(.system(size: boxFontSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
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
        case .minus:
            MainGridStepDownCounterWidgetView(
                configurationText: rightTitleWithoutColorPrefix,
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
        case .timer(let completionSoundFilename):
            MainGridTimerWidgetView(
                widgetID: widgetID,
                entry: entry,
                configurationText: rightTitleWithoutColorPrefix,
                completionSoundFilename: completionSoundFilename,
                sharedTimer: sharedTimer,
                fontSize: boxFontSize,
                foregroundColor: buttonTextColor,
                onTimerCompletionAction: sendTimerCompletionAction,
                onPlayCompletionSound: playLoopingSoundNamed,
                onStopCompletionSound: stopSoundPlayback
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

    private func dateWeekdayText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = widgetTimeZone ?? .current
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private func dateValueText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = widgetTimeZone ?? .current
        formatter.dateFormat = "dd/MM/yy"
        return formatter.string(from: date)
    }

    private func normalizedWidgetLocation(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var rightTitleWithoutColorPrefix: String {
        if entry.buttonColorCode != nil {
            return rightTitle
        }

        let components = rightTitle.components(separatedBy: ":")

        if let firstComponent = components.first?.trimmingCharacters(in: .whitespacesAndNewlines),
           firstComponent.count == 1,
           let existingCode = firstComponent.lowercased().first,
           "lwbgorpucya12345".contains(existingCode) {
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

	// MARK: - BM:🟩 main scrn btn colors
    private var buttonBackgroundColor: Color {
        guard !isEmptyButtonEntry else {
            return Color.black.opacity(backgroundOpacity)
        }

        switch (entry.buttonColorCode ?? "").lowercased() {
        case "l":
            return .clear
        case "w":
            return Color.brown.opacity(backgroundOpacity)
        case "b":
            return Color(red: 0.0, green: 0.2, blue: 0.45).opacity(backgroundOpacity)
        case "g":
            return Color(red: 0.05, green: 0.33, blue: 0.18).opacity(backgroundOpacity)
        case "o":
            return Color(red: 0.5, green: 0.28, blue: 0.0).opacity(backgroundOpacity)
        case "r":
            return Color(red: 0.42, green: 0.12, blue: 0.12).opacity(backgroundOpacity)
        case "p":
            return Color(red: 0.82, green: 0.42, blue: 0.58).opacity(backgroundOpacity)
        case "u":
            return Color(red: 0.42, green: 0.18, blue: 0.52).opacity(backgroundOpacity)
        case "c":
            return Color.cyan.opacity(backgroundOpacity)
        case "y":
            return Color(red: 0.55, green: 0.45, blue: 0.08).opacity(backgroundOpacity)
        case "a":
            return Color(red: 0.25, green: 0.25, blue: 0.25).opacity(backgroundOpacity)
        case "1":
            return Color(red: 0.20, green: 0.22, blue: 0.30).opacity(backgroundOpacity)
        case "2":
            return Color(red: 0.14, green: 0.3, blue: 0.25).opacity(backgroundOpacity)
        case "3":
            return Color(red: 0.38, green: 0.14, blue: 0.24).opacity(backgroundOpacity)
        case "4":
            return Color(red: 0.23, green: 0.26, blue: 0.08).opacity(backgroundOpacity)
        case "5":
            return Color(red: 0.14, green: 0.16, blue: 0.38).opacity(backgroundOpacity)
        default:
            return Color.black.opacity(backgroundOpacity)
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
    case clock
    case date
    case power
    case add
    case minus
    case random(minimumValue: Int, maximumValue: Int)
    case textFileRandom(filename: String)
    case stopwatch
    case ambientSound(filename: String)
    case timer(completionSoundFilename: String?)
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
        .onTapGesture {
            currentCount += 1
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            currentCount = 0
        }
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
        .onTapGesture {
            currentCount = max(0, currentCount - 1)
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            currentCount = initialCount
        }
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

final class MainGridSharedTimerState: ObservableObject {
    struct TimerSnapshot {
        var configuredDuration = 0
        var remainingSeconds = 0
        var isRunning = false
        var isCompletionSoundLooping = false
    }

    @Published private var timerSnapshots: [String: TimerSnapshot] = [:]

    private var completionSoundFilenames: [String: String?] = [:]
    private var startCompletionSoundLoopCallbacks: [String: (String) -> Void] = [:]
    private var stopCompletionSoundLoopCallbacks: [String: () -> Void] = [:]
    private var timerCompletionActionCallbacks: [String: () -> Void] = [:]
    private var endDates: [String: Date] = [:]
    private var tickTasks: [String: Task<Void, Never>] = [:]

    deinit {
        tickTasks.values.forEach { $0.cancel() }
    }

    func startTimer(
        widgetID: String,
        duration: Int,
        completionSoundFilename: String?,
        onTimerCompletionAction: @escaping () -> Void,
        onPlayCompletionSound: @escaping (String) -> Void,
        onStopCompletionSound: @escaping () -> Void
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
        completionSoundFilenames[widgetID] = normalizedCompletionSoundFilename(completionSoundFilename)
        timerCompletionActionCallbacks[widgetID] = onTimerCompletionAction
        startCompletionSoundLoopCallbacks[widgetID] = onPlayCompletionSound
        stopCompletionSoundLoopCallbacks[widgetID] = onStopCompletionSound

        guard snapshot.isRunning else {
            return
        }

        startTicking(for: widgetID)
    }

    func resumeTimer(
        widgetID: String,
        duration: Int,
        completionSoundFilename: String?,
        onTimerCompletionAction: @escaping () -> Void,
        onPlayCompletionSound: @escaping (String) -> Void,
        onStopCompletionSound: @escaping () -> Void
    ) {
        guard timerSnapshots[widgetID] != nil else {
            startTimer(
                widgetID: widgetID,
                duration: duration,
                completionSoundFilename: completionSoundFilename,
                onTimerCompletionAction: onTimerCompletionAction,
                onPlayCompletionSound: onPlayCompletionSound,
                onStopCompletionSound: onStopCompletionSound
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
        completionSoundFilenames[widgetID] = normalizedCompletionSoundFilename(completionSoundFilename)
        timerCompletionActionCallbacks[widgetID] = onTimerCompletionAction
        startCompletionSoundLoopCallbacks[widgetID] = onPlayCompletionSound
        stopCompletionSoundLoopCallbacks[widgetID] = onStopCompletionSound

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
        completionSoundFilename: String?,
        onTimerCompletionAction: @escaping () -> Void,
        onPlayCompletionSound: @escaping (String) -> Void,
        onStopCompletionSound: @escaping () -> Void
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
        completionSoundFilenames[widgetID] = normalizedCompletionSoundFilename(completionSoundFilename)
        timerCompletionActionCallbacks[widgetID] = onTimerCompletionAction
        startCompletionSoundLoopCallbacks[widgetID] = onPlayCompletionSound
        stopCompletionSoundLoopCallbacks[widgetID] = onStopCompletionSound
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
                    self.timerCompletionActionCallbacks[widgetID]?()

                    if let completionSoundFilename = self.completionSoundFilenames[widgetID] ?? nil {
                        self.startCompletionSoundLoopCallbacks[widgetID]?(completionSoundFilename)
                        snapshot.isCompletionSoundLooping = true
                        self.timerSnapshots[widgetID] = snapshot
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

    private func normalizedCompletionSoundFilename(_ filename: String?) -> String? {
        let trimmedFilename = filename?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedFilename.isEmpty ? nil : trimmedFilename
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
    let completionSoundFilename: String?
    @ObservedObject var sharedTimer: MainGridSharedTimerState
    let fontSize: Double
    let foregroundColor: Color
    let onTimerCompletionAction: (FunctionKeyEntry) -> Void
    let onPlayCompletionSound: (String) -> Void
    let onStopCompletionSound: () -> Void

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
        .onTapGesture {
            togglePlayback()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            resetAndPause()
        }
        .onAppear {
            applyConfiguration()
        }
        .onChange(of: configurationText) {
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
        let components = configurationText.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let parsedDuration = components.first
            .map { parseTimerDuration(String($0)) } ?? 0
        let parsedTitle = components.count > 1
            ? String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""

        configuredDuration = max(parsedDuration, 0)
        title = parsedTitle

        guard !sharedTimer.isRunning(widgetID: widgetID),
              !sharedTimer.isCompletionSoundLooping(widgetID: widgetID) else {
            return
        }

        sharedTimer.resetAndPauseTimer(
            widgetID: widgetID,
            duration: configuredDuration,
            completionSoundFilename: completionSoundFilename,
            onTimerCompletionAction: { onTimerCompletionAction(entry) },
            onPlayCompletionSound: onPlayCompletionSound,
            onStopCompletionSound: onStopCompletionSound
        )
    }

    private func parseTimerDuration(_ durationText: String) -> Int {
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
            completionSoundFilename: completionSoundFilename,
            onTimerCompletionAction: { onTimerCompletionAction(entry) },
            onPlayCompletionSound: onPlayCompletionSound,
            onStopCompletionSound: onStopCompletionSound
        )
    }

    private func resetAndPause() {
        sharedTimer.resetAndPauseTimer(
            widgetID: widgetID,
            duration: configuredDuration,
            completionSoundFilename: completionSoundFilename,
            onTimerCompletionAction: { onTimerCompletionAction(entry) },
            onPlayCompletionSound: onPlayCompletionSound,
            onStopCompletionSound: onStopCompletionSound
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
            .onLongPressGesture(minimumDuration: 0.5) {
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

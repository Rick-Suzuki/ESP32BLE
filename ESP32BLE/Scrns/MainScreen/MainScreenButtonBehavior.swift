import SwiftUI
import AVFoundation
import UIKit
import Combine

extension MainScreen {
    private var defaultNewButtonEntryText: String { "F::spare" }
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
        case .both:
            return "\(displayText(from: entry.primaryDisplayText))\n\(displayText(from: alternateDisplayText))"
        }
    }

    func displayText(from text: String) -> String {
        text
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")
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
           "lwbgorpucya".contains(manualColorCode) {
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

        let bluetoothSendTexts = entry.sendTexts.filter { sendText in
            targetDocumentNameForSendText(sendText) == nil &&
                targetURLForSendText(sendText) == nil &&
                targetSoundFilenameForSendText(sendText) == nil &&
                targetSpokenTextForSendText(sendText) == nil &&
                targetAppURLForSendText(sendText) == nil &&
                targetWidgetDescriptorForSendText(sendText) == nil
        }
        let targetDocumentName = targetDocumentNameForGridEntry(entry)
        let targetURL = targetURLForGridEntry(entry)
        let targetSoundFilename = targetSoundFilenameForGridEntry(entry)
        let targetAppURL = targetAppURLForGridEntry(entry)

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

        if let targetSoundFilename {
            playMainGridSound(named: targetSoundFilename)
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

        for sendText in bluetoothSendTexts {
            ble.sendLine(normalizedBluetoothSendText(sendText))
        }
    }

    func speakMainGridEntry(_ entry: FunctionKeyEntry) {
        guard !isSpkRecEnabled else {
            return
        }

        let spokenText = spokenTitle(for: entry)
            .replacingOccurrences(of: "\n", with: ", ")
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

    func targetSoundFilenameForSendText(_ sendText: String) -> String? {
        let trimmedSendText = sendText.trimmingCharacters(in: .whitespacesAndNewlines)
        let loweredSendText = trimmedSendText.lowercased()

        guard loweredSendText.hasPrefix("snd ") else {
            return nil
        }

        let filename = trimmedSendText.dropFirst(4).trimmingCharacters(in: .whitespacesAndNewlines)
        return filename.isEmpty ? nil : filename
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

        if loweredSendText.hasPrefix("wid ") {
            widgetText = String(trimmedSendText.dropFirst(4))
        } else if loweredSendText.hasPrefix("widget ") {
            widgetText = String(trimmedSendText.dropFirst(7))
        } else {
            return nil
        }

        let components = widgetText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let widgetName = components.first?.lowercased() else {
            return nil
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
        case "timer":
            let completionSoundFilename = components.count > 1
                ? String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            return .timer(completionSoundFilename: completionSoundFilename.isEmpty ? nil : completionSoundFilename)
        default:
            return nil
        }
    }

    func playMainGridSound(named filename: String) {
        guard let audioURL = soundURL(named: filename) else {
            alertTitle = "Sound Not Found"
            renameAlertMessage = "Couldn't find \(filename)."
            return
        }

        activateAudioSessionForSpeechPlayback()

        do {
            let player = try AVAudioPlayer(contentsOf: audioURL)
            player.prepareToPlay()
            player.play()
            soundEffectPlayer = player
        } catch {
            alertTitle = "Sound Error"
            renameAlertMessage = "Couldn't play \(filename)."
        }
    }

    func soundURL(named filename: String) -> URL? {
        let trimmedFilename = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFilename.isEmpty else {
            return nil
        }

        if let documentsDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let documentSoundURL = documentsDirectoryURL.appendingPathComponent(trimmedFilename)
            if FileManager.default.fileExists(atPath: documentSoundURL.path) {
                return documentSoundURL
            }
        }

        return Bundle.main.resourceURL?.appendingPathComponent(trimmedFilename)
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
            playSoundNamed: playMainGridSound
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
    let playSoundNamed: (String) -> Void

    // Adjust emojiScaleMultiplier to tune how much larger emoji should render than text.
    private let emojiScaleMultiplier: CGFloat = 1.5

    var body: some View {
        Group {
            if entry.isBlankPlaceholder {
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
        case .timer(let completionSoundFilename):
            MainGridTimerWidgetView(
                configurationText: rightTitleWithoutColorPrefix,
                completionSoundFilename: completionSoundFilename,
                fontSize: boxFontSize,
                foregroundColor: buttonTextColor,
                onPlayCompletionSound: playSoundNamed
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
        let components = rightTitle.components(separatedBy: ":")

        if let firstComponent = components.first?.trimmingCharacters(in: .whitespacesAndNewlines),
           firstComponent.count == 1,
           let existingCode = firstComponent.lowercased().first,
           "lwbgorpucya".contains(existingCode) {
            return components.dropFirst().joined(separator: ":")
        }

        return rightTitle
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
        case "b", "actions":
            return Color(red: 0.0, green: 0.2, blue: 0.45).opacity(backgroundOpacity)
        case "g", "pos":
            return Color(red: 0.05, green: 0.33, blue: 0.18).opacity(backgroundOpacity)
        case "o":
            return Color(red: 0.5, green: 0.28, blue: 0.0).opacity(backgroundOpacity)
        case "r", "dest":
            return Color(red: 0.42, green: 0.12, blue: 0.12).opacity(backgroundOpacity)
        case "p":
            return Color(red: 0.82, green: 0.42, blue: 0.58).opacity(backgroundOpacity)
        case "u", "info":
            return Color(red: 0.42, green: 0.18, blue: 0.52).opacity(backgroundOpacity)
        case "c":
            return Color.cyan.opacity(backgroundOpacity)
        case "y", "warning":
            return Color(red: 0.55, green: 0.45, blue: 0.08).opacity(backgroundOpacity)
        case "a":
            return Color.gray.opacity(backgroundOpacity)
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

private struct MainGridTimerWidgetView: View {
    let configurationText: String
    let completionSoundFilename: String?
    let fontSize: Double
    let foregroundColor: Color
    let onPlayCompletionSound: (String) -> Void

    @State private var configuredDuration = 0
    @State private var remainingSeconds = 0
    @State private var title = ""
    @State private var isRunning = false
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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
        .onReceive(ticker) { _ in
            guard isRunning, remainingSeconds > 0 else {
                return
            }

            remainingSeconds -= 1

            guard remainingSeconds == 0 else {
                return
            }

            isRunning = false

            if let completionSoundFilename,
               !completionSoundFilename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onPlayCompletionSound(completionSoundFilename)
            }
        }
    }

    private var formattedRemainingTime: String {
        let hours = remainingSeconds / 3600
        let minutes = (remainingSeconds % 3600) / 60
        let seconds = remainingSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func applyConfiguration() {
        isRunning = false

        let components = configurationText.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let parsedDuration = components.first
            .map { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0 } ?? 0
        let parsedTitle = components.count > 1
            ? String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""

        configuredDuration = max(parsedDuration, 0)
        remainingSeconds = configuredDuration
        title = parsedTitle
    }

    private func togglePlayback() {
        guard configuredDuration > 0 else {
            return
        }

        if isRunning {
            pause()
            return
        }

        if remainingSeconds == 0 {
            remainingSeconds = configuredDuration
        }

        isRunning = true
    }

    private func pause() {
        isRunning = false
    }

    private func resetAndPause() {
        pause()
        remainingSeconds = configuredDuration
    }
}

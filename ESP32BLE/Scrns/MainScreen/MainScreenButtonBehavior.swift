import SwiftUI
import AVFoundation
import UIKit

extension MainScreen {
    private var defaultNewButtonEntryText: String { "F::spare" }

    func buttonTitle(for entry: FunctionKeyEntry) -> String {
        guard entry.displayUsesAlternateText else {
            return displayText(from: entry.rawLine)
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

        let components = entry.rawLine.components(separatedBy: "::")
        guard components.count >= 2 else {
            return entry.rawLine
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

        guard mainGridButtonMode.sendsBluetooth else {
            return
        }

        guard ble.isConnected else {
            alertTitle = "Bluetooth Not Connected"
            renameAlertMessage = "Bluetooth needs to be connected\nbefore using buttons."
            return
        }

        guard !entry.sendTexts.isEmpty else {
            return
        }

        logMainButtonPress(entry)

        let bluetoothSendTexts = entry.sendTexts.filter { sendText in
            targetDocumentNameForSendText(sendText) == nil
        }

        for sendText in bluetoothSendTexts {
            ble.sendLine(normalizedBluetoothSendText(sendText))
        }

        if let targetDocumentName = targetDocumentNameForGridEntry(entry) {
            if selectDocumentNamedFromGrid(targetDocumentName) {
                return
            }

            alertTitle = "File Not Found"
            renameAlertMessage = "Couldn't find \(targetDocumentName.lowercased())."
        }
    }

    func speakMainGridEntry(_ entry: FunctionKeyEntry) {
        let spokenText = spokenTitle(for: entry)
            .replacingOccurrences(of: "\n", with: ", ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !spokenText.isEmpty else {
            return
        }

        stopSpokenGridText()

        let utterance = AVSpeechUtterance(string: spokenText)
        utterance.voice = resolvedSpeechVoice
        utterance.rate = Float(clampedTextToSpeechRate)
        speechSynthesizer.speak(utterance)
    }

    func spokenTitle(for entry: FunctionKeyEntry) -> String {
        let leftTitle = displayText(from: entry.primaryDisplayText)

        if let rightSymbolDisplay = parsedSFSymbolDisplay(for: entry) {
            let spokenRightText = rightSymbolDisplay.subtitle ?? ""

            switch displayMode {
            case .left:
                return leftTitle
            case .right:
                return spokenRightText
            case .both:
                if spokenRightText.isEmpty {
                    return leftTitle
                }
                return "\(leftTitle)\n\(spokenRightText)"
            }
        }

        return buttonTitle(for: entry)
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
            rightSymbolDisplay: parsedSFSymbolDisplay(for: entry),
            boxFontSize: boxFontSize,
            buttonHeight: buttonHeight,
            cornerRadius: mainGridButtonCornerRadius,
            borderWidth: mainGridButtonBorderWidth,
            isGridEditModeEnabled: isGridEditModeEnabled,
            activeDragIndex: activeDragIndex,
            backgroundOpacity: backgroundOpacity
        )
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
              UIImage(systemName: candidateName) != nil else {
            return nil
        }

        let subtitle = components
            .dropFirst()
            .joined(separator: ":")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (candidateName, subtitle.isEmpty ? nil : subtitle)
    }
}

struct MainScreenButtonLabelView: View {
    let entry: FunctionKeyEntry
    let index: Int
    let title: String
    let leftTitle: String
    let rightTitle: String
    let displayMode: FunctionKeyDisplayMode
    let rightSymbolDisplay: (name: String, subtitle: String?)?
    let boxFontSize: Double
    let buttonHeight: CGFloat
    let cornerRadius: CGFloat
    let borderWidth: CGFloat
    let isGridEditModeEnabled: Bool
    let activeDragIndex: Int?
    let backgroundOpacity: Double

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

    @ViewBuilder
    private var buttonContent: some View {
        if let rightSymbolDisplay {
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
        } else {
            textLabel(title: title)
        }
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
                .foregroundStyle(buttonTextColor)
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

	// MARK: - BM:🟩 main scrn btn colors
    private var buttonBackgroundColor: Color {
        guard !isEmptyButtonEntry else {
            return Color.black.opacity(backgroundOpacity)
        }

        switch (entry.buttonColorCode ?? "").lowercased() {
        case "l":
            return Color.black.opacity(backgroundOpacity)
        case "w":
            return .white.opacity(backgroundOpacity)
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
        switch (entry.buttonColorCode ?? "").lowercased() {
        case "w", "y", "c":
            return .black
        default:
            return .white
        }
    }

    private var borderColor: Color {
        if isGridEditModeEnabled && activeDragIndex == index {
            return .green
        }

        return Color.white.opacity(0.8)
    }

    private var isEmptyButtonEntry: Bool {
        let trimmedRawLine = entry.rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAlternateText = entry.alternateDisplayText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedRawLine.isEmpty && entry.sendTexts.isEmpty && trimmedAlternateText.isEmpty
    }
}

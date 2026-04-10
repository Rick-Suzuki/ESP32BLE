import SwiftUI

extension MainScreen {
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
           "lwgborypk".contains(manualColorCode) {
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
        if let targetDocumentName = targetDocumentNameForGridEntry(entry) {
            if selectDocumentNamedFromGrid(targetDocumentName) {
                return
            }

            alertTitle = "File Not Found"
            renameAlertMessage = "Couldn't find \(targetDocumentName.lowercased())."
            return
        }

        guard ble.isConnected else {
            print("Bluetooth not connected.")
            return
        }

        guard !entry.sendTexts.isEmpty else {
            return
        }

        logMainButtonPress(entry)

        for sendText in entry.sendTexts {
            ble.sendLine(sendText)
        }
    }

    func targetDocumentNameForGridEntry(_ entry: FunctionKeyEntry) -> String? {
        entry.sendTexts.first { sendText in
            sendText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasSuffix(".txt")
        }
    }

    func mainGridButtonLabel(
        entry: FunctionKeyEntry,
        index: Int,
        buttonHeight: CGFloat,
        backgroundOpacity: Double
    ) -> some View {
        let title = buttonTitle(for: entry)

        return MainScreenButtonLabelView(
            entry: entry,
            index: index,
            title: title,
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
            return ""
        }

        return entry.rawLine
    }

    func isEmptyButtonEntry(_ entry: FunctionKeyEntry) -> Bool {
        let trimmedRawLine = entry.rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAlternateText = entry.alternateDisplayText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedRawLine.isEmpty && entry.sendTexts.isEmpty && trimmedAlternateText.isEmpty
    }
}

struct MainScreenButtonLabelView: View {
    let entry: FunctionKeyEntry
    let index: Int
    let title: String
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
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: buttonHeight)
            } else {
                Text(title)
                    .font(.system(size: boxFontSize, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .minimumScaleFactor(0.35)
                    .foregroundStyle(buttonTextColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(8)
                    .frame(height: buttonHeight)
                    .background(buttonBackgroundColor)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(borderColor, lineWidth: borderWidth)
                    }
                    .clipShape(.rect(cornerRadius: cornerRadius))
            }
        }
    }

    private var buttonBackgroundColor: Color {
        guard !isEmptyButtonEntry else {
            return Color.black.opacity(backgroundOpacity)
        }

        switch (entry.buttonColorCode ?? "").lowercased() {
        case "l":
            return .white.opacity(backgroundOpacity)
        case "w", "warning":
            return Color(red: 0.55, green: 0.45, blue: 0.08).opacity(backgroundOpacity)
        case "g", "pos":
            return Color(red: 0.05, green: 0.33, blue: 0.18).opacity(backgroundOpacity)
        case "b", "actions":
            return Color(red: 0.0, green: 0.2, blue: 0.45).opacity(backgroundOpacity)
        case "o":
            return Color(red: 0.5, green: 0.28, blue: 0.0).opacity(backgroundOpacity)
        case "r", "dest":
            return Color(red: 0.42, green: 0.12, blue: 0.12).opacity(backgroundOpacity)
        case "y":
            return Color(red: 0.78, green: 0.68, blue: 0.12).opacity(backgroundOpacity)
        case "p", "info":
            return Color(red: 0.42, green: 0.18, blue: 0.52).opacity(backgroundOpacity)
        case "k":
            return Color.black.opacity(backgroundOpacity)
        default:
            return Color.black.opacity(backgroundOpacity)
        }
    }

    private var buttonTextColor: Color {
        switch (entry.buttonColorCode ?? "").lowercased() {
        case "l", "y":
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

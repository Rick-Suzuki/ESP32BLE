import SwiftUI

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

    var body: some View {
        let backgroundColor = buttonBackgroundColor(for: entry)
        let textColor = buttonTextColor(for: entry)

        return ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(backgroundColor)

            Text(title)
                .font(.system(size: boxFontSize, weight: .semibold))
                .foregroundStyle(textColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
        }
        .frame(maxWidth: .infinity, minHeight: buttonHeight, maxHeight: buttonHeight)
        .background(Color.clear)
        .overlay(buttonOverlay(for: entry, index: index))
        .contentShape(.rect(cornerRadius: cornerRadius))
    }

    @ViewBuilder
    private func buttonOverlay(for entry: FunctionKeyEntry, index: Int) -> some View {
        if shouldShowBorder(for: entry) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white, lineWidth: borderWidth)
        }

        if isGridEditModeEnabled, activeDragIndex == index, !entry.isBlankPlaceholder {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
        }
    }

    private func buttonBackgroundColor(for entry: FunctionKeyEntry) -> Color {
        if entry.isBlankPlaceholder {
            return .black
        }

        switch entry.buttonColorCode {
        case "l":
            return Color.black.opacity(0.4)
        case "w":
            return Color.white.opacity(0.4)
        case "g":
            return Color.green.opacity(0.4)
        case "b":
            return Color.blue.opacity(0.4)
        case "o":
            return Color.orange.opacity(0.4)
        case "r", "dest":
            return Color.red.opacity(entry.buttonColorCode == "r" ? 0.4 : 0.6)
        case "y":
            return Color.yellow.opacity(0.4)
        case "p", "pos":
            return Color.purple.opacity(entry.buttonColorCode == "p" ? 0.4 : 0.6)
        case "k":
            return Color.pink.opacity(0.6)
        case "warning":
            return Color.orange.opacity(0.6)
        case "actions":
            return Color.green.opacity(0.6)
        case "info":
            return Color.blue.opacity(0.6)
        default:
            return entry.alternateDisplayText == nil ? .black : Color(white: 0.12)
        }
    }

    private func buttonTextColor(for entry: FunctionKeyEntry) -> Color {
        if entry.buttonColorCode == "w" {
            return .black
        }

        if entry.buttonColorCode == nil, entry.alternateDisplayText != nil {
            return .yellow
        }

        return .white
    }

    private func shouldShowBorder(for entry: FunctionKeyEntry) -> Bool {
        !(entry.isBlankPlaceholder || isEmptyButtonEntry(entry))
    }

    private func isEmptyButtonEntry(_ entry: FunctionKeyEntry) -> Bool {
        entry.sendTexts.isEmpty && entry.alternateDisplayText == nil && entry.rawLine.isEmpty
    }
}

import SwiftUI

struct KeyboardCell {
    let title: String
    let systemImageName: String?
    let fontSize: CGFloat?
    let imageRotationDegrees: Double
    let background: Color
    let foreground: Color
    let isEnabled: Bool
    let isVisible: Bool
    let widthUnits: Int
    let action: () -> Void

    init(
        title: String,
        systemImageName: String? = nil,
        fontSize: CGFloat? = nil,
        imageRotationDegrees: Double = 0,
        background: Color,
        foreground: Color,
        isEnabled: Bool = true,
        isVisible: Bool = true,
        widthUnits: Int = 1,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImageName = systemImageName
        self.fontSize = fontSize
        self.imageRotationDegrees = imageRotationDegrees
        self.background = background
        self.foreground = foreground
        self.isEnabled = isEnabled
        self.isVisible = isVisible
        self.widthUnits = widthUnits
        self.action = action
    }
}

struct KeyboardGridCellView: View {
    let cell: KeyboardCell
    let gridKeyFontSize: CGFloat
    let gridKeyCornerRadius: CGFloat
    let cellWidth: CGFloat
    let action: () -> Void

    var body: some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            action()
        } label: {
            Group {
                if let systemImageName = cell.systemImageName {
                    Image(systemName: systemImageName)
                        .font(.system(size: gridKeyFontSize, weight: .bold))
                        .rotationEffect(.degrees(cell.imageRotationDegrees))
                        .foregroundStyle(cell.foreground)
                } else {
                    Text(cell.title)
                        .font(.system(size: cell.fontSize ?? gridKeyFontSize, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.45)
                        .foregroundStyle(cell.foreground)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: cellWidth)
        .frame(maxHeight: .infinity)
        .background(cell.background, in: RoundedRectangle(cornerRadius: gridKeyCornerRadius, style: .continuous))
        .disabled(!cell.isEnabled)
        .opacity(cell.isVisible ? 1 : 0)
        .allowsHitTesting(cell.isVisible && cell.isEnabled)
    }
}

enum KeyboardMode: Int, CaseIterable {
    case mode1 = 1
    case mode2 = 2
    case mode3 = 3
    case mode4 = 4
}

struct Mode4RowDefinition {
    let title: String
    let modifierTokens: [String]
    let background: Color
    let foreground: Color
}

enum KeyboardModifier: CaseIterable, Hashable {
    case control
    case option
    case shift
    case command

    static let orderedCases: [KeyboardModifier] = [.control, .option, .shift, .command]

    var title: String {
        switch self {
        case .control:
            return "⌃:"
        case .shift:
            return "⇧:"
        case .option:
            return "⌥:"
        case .command:
            return "⌘:"
        }
    }

    var token: String {
        switch self {
        case .control:
            return "ct"
        case .shift:
            return "sh"
        case .option:
            return "op"
        case .command:
            return "cm"
        }
    }

    var displayToken: String {
        title
    }

    nonisolated init?(token: String) {
        switch token {
        case "ct":
            self = .control
        case "sh":
            self = .shift
        case "op":
            self = .option
        case "cm":
            self = .command
        default:
            return nil
        }
    }
}

enum CursorMovement {
    case left
    case right
}

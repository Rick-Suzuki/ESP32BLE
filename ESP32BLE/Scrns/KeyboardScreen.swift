import SwiftUI
import UIKit

struct KeyboardScreen: View {
    // Easy-to-find key label sizing for the custom keyboard grid.
    private let gridKeyFontSize: CGFloat = 24
    private let keypadKeyFontSize: CGFloat = 31
    private let typingAreaFontSize: CGFloat = 34
    // Easy-to-find key shape tuning for the custom keyboard grid.
    private let gridKeyCornerRadius: CGFloat = 12
    private let gridKeySpacing: CGFloat = 6
    private let gridRowHeightScale: CGFloat = 0.99
    // Easy-to-find sizing for the top keyboard control row.
    private let topControlSingleButtonWidth: CGFloat = 95
    private let topControlDoubleButtonWidth: CGFloat = 193

    @ObservedObject var ble: BLEKeyboardManager
    let isPresented: Bool
    @AppStorage("keyboardSendImmediatelyEnabled") private var isSendImmediatelyEnabled = true
    @AppStorage("keyboardAutoCapEnabled") private var isAutoCapEnabled = false
    @AppStorage("keyboardEachWordCapEnabled") private var isEachWordCapEnabled = false
    @AppStorage("keyboardAutoCorrectEnabled") private var isAutoCorrectEnabled = false
    let returnToMain: () -> Void

    @State private var typingText = ""
    @State private var shouldFocusInput = false
    @State private var activeModifiers: Set<KeyboardModifier> = []
    @State private var cursorCommand: CursorMovement = .right
    @State private var cursorCommandID = 0

    var body: some View {
        VStack(spacing: 0) {
            topSection
       //     Divider()
			//.overlay(Color.gray.opacity(0.45))
            keyGrid
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            if isPresented {
                requestKeyboardFocus()
            }
        }
        .onChange(of: isPresented) {
            if isPresented {
                requestKeyboardFocus()
            } else {
                shouldFocusInput = false
            }
        }
        .onTapGesture {
            requestKeyboardFocus()
        }
    }

    private var topSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                topNavButton(title: "mode") {
                }

                KeyboardInputField(
                    text: $typingText,
                    shouldBeFirstResponder: shouldFocusInput,
                    fontSize: typingAreaFontSize,
                    autocapitalizationType: keyboardAutocapitalizationType,
                    autocorrectionEnabled: isSendOnReturnMode && isAutoCorrectEnabled,
                    cursorCommand: cursorCommand,
                    cursorCommandID: cursorCommandID,
                    onInsertedText: handleInsertedText(_:),
                    onBackspace: handleBackspace,
                    onReturn: handleReturn
                )
                .frame(maxWidth: .infinity)
                .frame(height: 34)

                topNavButton(title: "Main") {
                    shouldFocusInput = false
                    returnToMain()
                }
            }

            HStack(spacing: 4) {
                topControlButton(
                    title: isSendImmediatelyEnabled ? "Send Immediately" : "Send on Return",
                    background: isSendImmediatelyEnabled ? .blue : Color.gray.opacity(0.45),
                    width: topControlDoubleButtonWidth
                ) {
                    isSendImmediatelyEnabled.toggle()
                    requestKeyboardFocus()
                }

                topOptionButton(
                    title: "auto-capitalize",
                    isOn: $isAutoCapEnabled,
                    isEnabled: isSendOnReturnMode,
                    width: topControlDoubleButtonWidth
                )
                topOptionButton(
                    title: "cap 1st letter",
                    isOn: $isEachWordCapEnabled,
                    isEnabled: isSendOnReturnMode,
                    width: topControlDoubleButtonWidth
                )
                topOptionButton(
                    title: "auto-correct",
                    isOn: $isAutoCorrectEnabled,
                    isEnabled: isSendOnReturnMode,
                    width: topControlDoubleButtonWidth
                )

                topControlButton(systemImageName: "triangle.fill", rotationDegrees: -90, background: .blue, width: topControlSingleButtonWidth) {
                    moveCursor(.left)
                }
                topControlButton(systemImageName: "triangle.fill", rotationDegrees: 90, background: .blue, width: topControlSingleButtonWidth) {
                    moveCursor(.right)
                }
                topControlButton(title: "clr all", background: .red, width: topControlSingleButtonWidth) {
                    typingText = ""
                    requestKeyboardFocus()
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }

    private func topNavButton(title: String, action: @escaping () -> Void) -> some View {
        Button(title) {
            action()
        }
        .buttonStyle(.plain)
        .font(.headline)
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(Color.gray.opacity(0.45))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
        }
        .clipShape(.rect(cornerRadius: 12))
    }

    private var keyGrid: some View {
        GeometryReader { geometry in
            let rowCount = 6
            let totalSpacing = gridKeySpacing * CGFloat(rowCount - 1)
            let safeGridHeight = geometry.size.height.isFinite ? max(0, geometry.size.height - totalSpacing) : 0
            let availableRowHeight = floor(safeGridHeight / CGFloat(rowCount))
            let rowHeight = max(32, floor(availableRowHeight * gridRowHeightScale))

            VStack(spacing: gridKeySpacing) {
                keyRow(topRowCells)
                    .frame(height: rowHeight)
                keyRow(secondRowCells)
                    .frame(height: rowHeight)
                keyRow(thirdRowCells)
                    .frame(height: rowHeight)
                keyRow(fourthRowCells)
                    .frame(height: rowHeight)
                keyRow(fifthRowCells)
                    .frame(height: rowHeight)
                keyRow(bottomRowCells)
                    .frame(height: rowHeight)
            }
            .padding(gridKeySpacing)
            .background(Color.black)
        }
    }

    private func keyRow(_ cells: [KeyboardCell]) -> some View {
        HStack(spacing: gridKeySpacing) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Button {
                    cell.action()
                    requestKeyboardFocus()
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(cell.background, in: RoundedRectangle(cornerRadius: gridKeyCornerRadius, style: .continuous))
                .disabled(!cell.isEnabled)
            }
        }
    }

    private var topRowCells: [KeyboardCell] {
        [
            comboFunctionCell(title: "ctl+cmd\nF13", tokens: ["ct", "cm"], functionKey: "f13", background: Color.blue.opacity(0.55)),
            comboFunctionCell(title: "F14", tokens: ["ct", "cm"], functionKey: "f14", background: Color.blue.opacity(0.55)),
            comboFunctionCell(title: "F15", tokens: ["ct", "cm"], functionKey: "f15", background: Color.blue.opacity(0.55)),
            keyTokenCell(title: "/", keyToken: "kp/", background: keypadColor),
            comboFunctionCell(title: "ctl\nF13", tokens: ["ct"], functionKey: "f13", background: modifierRowColor),
            comboFunctionCell(title: "F14", tokens: ["ct"], functionKey: "f14", background: modifierRowColor),
            comboFunctionCell(title: "F15", tokens: ["ct"], functionKey: "f15", background: modifierRowColor),
            comboFunctionCell(title: "F16", tokens: ["ct"], functionKey: "f16", background: modifierRowColor),
            comboFunctionCell(title: "F17", tokens: ["ct"], functionKey: "f17", background: modifierRowColor),
            comboFunctionCell(title: "F18", tokens: ["ct"], functionKey: "f18", background: modifierRowColor),
            comboFunctionCell(title: "F19", tokens: ["ct"], functionKey: "f19", background: modifierRowColor),
            comboFunctionCell(title: "F20", tokens: ["ct"], functionKey: "f20", background: modifierRowColor),
            comboFunctionCell(title: "sh+cmd\nF13", tokens: ["sh", "cm"], functionKey: "f13", background: commandShiftColor),
            comboFunctionCell(title: "F14", tokens: ["sh", "cm"], functionKey: "f14", background: commandShiftColor),
            comboFunctionCell(title: "F15", tokens: ["sh", "cm"], functionKey: "f15", background: commandShiftColor),
            comboFunctionCell(title: "F16", tokens: ["sh", "cm"], functionKey: "f16", background: commandShiftColor)
        ]
    }

    private var secondRowCells: [KeyboardCell] {
        [
            keyTokenCell(title: "7", keyToken: "kp7", background: keypadColor),
            keyTokenCell(title: "8", keyToken: "kp8", background: keypadColor),
            keyTokenCell(title: "9", keyToken: "kp9", background: keypadColor),
            keyTokenCell(title: "*", keyToken: "kp*", background: keypadColor),
            comboFunctionCell(title: "shift\nF13", tokens: ["sh"], functionKey: "f13", background: shiftRowColor),
            comboFunctionCell(title: "F14", tokens: ["sh"], functionKey: "f14", background: shiftRowColor),
            comboFunctionCell(title: "F15", tokens: ["sh"], functionKey: "f15", background: shiftRowColor),
            comboFunctionCell(title: "F16", tokens: ["sh"], functionKey: "f16", background: shiftRowColor),
            comboFunctionCell(title: "F17", tokens: ["sh"], functionKey: "f17", background: shiftRowColor),
            comboFunctionCell(title: "F18", tokens: ["sh"], functionKey: "f18", background: shiftRowColor),
            comboFunctionCell(title: "F19", tokens: ["sh"], functionKey: "f19", background: shiftRowColor),
            comboFunctionCell(title: "F20", tokens: ["sh"], functionKey: "f20", background: shiftRowColor),
            comboFunctionCell(title: "F17", tokens: ["sh", "cm"], functionKey: "f17", background: commandShiftColor),
            comboFunctionCell(title: "F18", tokens: ["sh", "cm"], functionKey: "f18", background: commandShiftColor),
            comboFunctionCell(title: "F19", tokens: ["sh", "cm"], functionKey: "f19", background: commandShiftColor),
            comboFunctionCell(title: "F20", tokens: ["sh", "cm"], functionKey: "f20", background: commandShiftColor)
        ]
    }

    private var thirdRowCells: [KeyboardCell] {
        [
            keyTokenCell(title: "4", keyToken: "kp4", background: keypadColor),
            keyTokenCell(title: "5", keyToken: "kp5", background: keypadColor),
            keyTokenCell(title: "6", keyToken: "kp6", background: keypadColor),
            keyTokenCell(title: "-", keyToken: "kp-", background: keypadColor),
            comboFunctionCell(title: "opt\nF13", tokens: ["op"], functionKey: "f13", background: optionRowColor),
            comboFunctionCell(title: "F14", tokens: ["op"], functionKey: "f14", background: optionRowColor),
            comboFunctionCell(title: "F15", tokens: ["op"], functionKey: "f15", background: optionRowColor),
            comboFunctionCell(title: "F16", tokens: ["op"], functionKey: "f16", background: optionRowColor),
            comboFunctionCell(title: "F17", tokens: ["op"], functionKey: "f17", background: optionRowColor),
            comboFunctionCell(title: "F18", tokens: ["op"], functionKey: "f18", background: optionRowColor),
            comboFunctionCell(title: "F19", tokens: ["op"], functionKey: "f19", background: optionRowColor),
            comboFunctionCell(title: "F20", tokens: ["op"], functionKey: "f20", background: optionRowColor),
            comboFunctionCell(title: "op+cmd\nF13", tokens: ["op", "cm"], functionKey: "f13", background: optionCommandColor),
            comboFunctionCell(title: "F14", tokens: ["op", "cm"], functionKey: "f14", background: optionCommandColor),
            comboFunctionCell(title: "F15", tokens: ["op", "cm"], functionKey: "f15", background: optionCommandColor),
            comboFunctionCell(title: "F16", tokens: ["op", "cm"], functionKey: "f16", background: optionCommandColor)
        ]
    }

    private var fourthRowCells: [KeyboardCell] {
        [
            keyTokenCell(title: "1", keyToken: "kp1", background: keypadColor),
            keyTokenCell(title: "2", keyToken: "kp2", background: keypadColor),
            keyTokenCell(title: "3", keyToken: "kp3", background: keypadColor),
            keyTokenCell(title: "+", keyToken: "kp+", background: keypadColor),
            comboFunctionCell(title: "cmd\nF13", tokens: ["cm"], functionKey: "f13", background: commandRowColor),
            comboFunctionCell(title: "F14", tokens: ["cm"], functionKey: "f14", background: commandRowColor),
            comboFunctionCell(title: "F15", tokens: ["cm"], functionKey: "f15", background: commandRowColor),
            comboFunctionCell(title: "F16", tokens: ["cm"], functionKey: "f16", background: commandRowColor),
            comboFunctionCell(title: "F17", tokens: ["cm"], functionKey: "f17", background: commandRowColor),
            comboFunctionCell(title: "F18", tokens: ["cm"], functionKey: "f18", background: commandRowColor),
            comboFunctionCell(title: "F19", tokens: ["cm"], functionKey: "f19", background: commandRowColor),
            comboFunctionCell(title: "F20", tokens: ["cm"], functionKey: "f20", background: commandRowColor),
            comboFunctionCell(title: "F17", tokens: ["op", "cm"], functionKey: "f17", background: optionCommandColor),
            comboFunctionCell(title: "F18", tokens: ["op", "cm"], functionKey: "f18", background: optionCommandColor),
            comboFunctionCell(title: "F19", tokens: ["op", "cm"], functionKey: "f19", background: optionCommandColor),
            comboFunctionCell(title: "F20", tokens: ["op", "cm"], functionKey: "f20", background: optionCommandColor)
        ]
    }

    private var fifthRowCells: [KeyboardCell] {
        [
            keyTokenCell(title: ".", keyToken: "kp.", background: keypadColor),
            keyTokenCell(title: "0", keyToken: "kp0", background: keypadColor),
            modifierCell(.control),
            modifierCell(.option),
            plainFunctionCell("F13"),
            plainFunctionCell("F14"),
            plainFunctionCell("F15"),
            plainFunctionCell("F16"),
            plainFunctionCell("F17"),
            plainFunctionCell("F18"),
            plainFunctionCell("F19"),
            plainFunctionCell("F20"),
            keyTokenCell(title: "", systemImageName: "triangle.fill", keyToken: "UP", background: arrowColor, applyStickyModifiers: true),
            keyTokenCell(title: "", systemImageName: "triangle.fill", keyToken: "DOWN", background: arrowColor, applyStickyModifiers: true),
            keyTokenCell(title: "", systemImageName: "triangle.fill", keyToken: "LEFT", background: arrowColor, applyStickyModifiers: true),
            keyTokenCell(title: "", systemImageName: "triangle.fill", keyToken: "RIGHT", background: arrowColor, applyStickyModifiers: true)
        ]
    }

    private var bottomRowCells: [KeyboardCell] {
        [
            keyTokenCell(title: "ESC", keyToken: "ESC", background: standardFunctionColor),
            KeyboardCell(title: "clr all", background: clearAllButtonColor, foreground: activeModifiers.isEmpty ? .white : .black) {
                resetModifierToggles()
            },
            modifierCell(.shift),
            modifierCell(.command),
            plainFunctionCell("F1"),
            plainFunctionCell("F2"),
            plainFunctionCell("F3"),
            plainFunctionCell("F4"),
            plainFunctionCell("F5"),
            plainFunctionCell("F6"),
            plainFunctionCell("F7"),
            plainFunctionCell("F8"),
            plainFunctionCell("F9"),
            plainFunctionCell("F10"),
            plainFunctionCell("F11"),
            plainFunctionCell("F12")
        ]
    }

    private func topControlButton(
        title: String? = nil,
        systemImageName: String? = nil,
        rotationDegrees: Double = 0,
        background: Color,
        width: CGFloat? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if let systemImageName {
                    Image(systemName: systemImageName)
                        .font(.system(size: 16, weight: .bold))
                        .rotationEffect(.degrees(rotationDegrees))
                } else {
                    Text(title ?? "")
                }
            }
            .foregroundStyle(.white)
            .frame(width: width, height: 30)
            .padding(.horizontal, width == nil ? 10 : 0)
            .background(background)
            .clipShape(.rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func topOptionButton(title: String, isOn: Binding<Bool>, isEnabled: Bool, width: CGFloat? = nil) -> some View {
        Button(title) {
            guard isEnabled else {
                return
            }

            isOn.wrappedValue.toggle()
            requestKeyboardFocus()
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.7))
        .frame(width: width, height: 30)
        .padding(.horizontal, width == nil ? 10 : 0)
        .background(optionButtonBackgroundColor(isEnabled: isEnabled, isOn: isOn.wrappedValue))
        .clipShape(.rect(cornerRadius: 6))
        .disabled(!isEnabled)
    }

    private func optionButtonBackgroundColor(isEnabled: Bool, isOn: Bool) -> Color {
        guard isEnabled else {
            return Color.gray.opacity(0.35)
        }

        return isOn ? .blue : Color.gray.opacity(0.45)
    }

    private func modifierCell(_ modifier: KeyboardModifier) -> KeyboardCell {
        let isOn = activeModifiers.contains(modifier)
        return KeyboardCell(
            title: modifier.title,
            background: modifierButtonColor(isOn: isOn),
            foreground: .white
        ) {
            toggleModifier(modifier)
        }
    }

    private func modifierButtonColor(isOn: Bool) -> Color {
        isOn
            ? Color(red: 0.7, green: 0.7, blue: 0.0)
            : Color(red: 0.35, green: 0.35, blue: 0.0)
    }

    private var clearAllButtonColor: Color {
        activeModifiers.isEmpty
            ? Color(red: 0.35, green: 0.35, blue: 0.0)
            : Color(red: 0.8, green: 0.8, blue: 0.0)
    }

    private func plainFunctionCell(_ title: String) -> KeyboardCell {
        KeyboardCell(title: title, background: standardFunctionColor, foreground: .white) {
            sendKeyWithStickyModifiers(title.lowercased())
        }
    }

    private func comboFunctionCell(
        title: String,
        tokens: [String],
        functionKey: String,
        background: Color
    ) -> KeyboardCell {
        KeyboardCell(title: title, background: background, foreground: .white) {
            sendTokens(tokens + [functionKey])
        }
    }

    private func keyTokenCell(
        title: String,
        systemImageName: String? = nil,
        keyToken: String,
        background: Color,
        applyStickyModifiers: Bool = true
    ) -> KeyboardCell {
        KeyboardCell(
            title: title,
            systemImageName: systemImageName,
            fontSize: background == keypadColor ? keypadKeyFontSize : nil,
            imageRotationDegrees: triangleRotationDegrees(for: keyToken, preferredName: systemImageName),
            background: background,
            foreground: .white
        ) {
            if applyStickyModifiers {
                sendKeyWithStickyModifiers(keyToken)
            } else {
                sendTokens([keyToken])
            }
        }
    }

    private var isSendOnReturnMode: Bool {
        !isSendImmediatelyEnabled
    }

    private var keyboardAutocapitalizationType: UITextAutocapitalizationType {
        if isSendOnReturnMode, isEachWordCapEnabled {
            return .words
        }

        if isSendOnReturnMode, isAutoCapEnabled {
            return .sentences
        }

        return .none
    }

    private func handleInsertedText(_ insertedText: String) {
        guard !insertedText.isEmpty else {
            return
        }

        if !activeModifiers.isEmpty {
            sendModifiedTypedText(insertedText)
            typingText = ""
            return
        }

        guard isSendImmediatelyEnabled else {
            return
        }

        ble.sendString(insertedText)
        typingText = ""
    }

    private func handleBackspace() {
        guard isSendImmediatelyEnabled else {
            return
        }

        ble.pressBackspace()
        typingText = ""
    }

    private func handleReturn() {
        if isSendImmediatelyEnabled {
            ble.pressEnter()
        } else {
            let trimmedText = typingText.trimmingCharacters(in: .newlines)
            guard !trimmedText.isEmpty else {
                return
            }

            ble.sendString(trimmedText)
            typingText = ""
        }

        requestKeyboardFocus()
    }

    private func moveCursor(_ movement: CursorMovement) {
        cursorCommand = movement
        cursorCommandID += 1
        requestKeyboardFocus()
    }

    private func toggleModifier(_ modifier: KeyboardModifier) {
        if activeModifiers.contains(modifier) {
            activeModifiers.remove(modifier)
        } else {
            activeModifiers.insert(modifier)
        }
    }

    private func resetModifierToggles() {
        activeModifiers.removeAll()
    }

    private func sendKeyWithStickyModifiers(_ keyToken: String) {
        sendTokens(activeModifierTokens + [keyToken])
    }

    private func sendTokens(_ tokens: [String]) {
        for token in tokens {
            ble.sendLine(token)
        }
    }

    private func sendModifiedTypedText(_ text: String) {
        for character in text {
            let token = String(character)
            sendKeyWithStickyModifiers(token)
        }
    }

    private var activeModifierTokens: [String] {
        KeyboardModifier.allCases.compactMap { modifier in
            activeModifiers.contains(modifier) ? modifier.token : nil
        }
    }

    private func requestKeyboardFocus() {
        DispatchQueue.main.async {
            shouldFocusInput = true
        }
    }

    private var keypadColor: Color {
        Color(red: 0.56, green: 0.16, blue: 0.10)
    }

    private var modifierRowColor: Color {
        Color(red: 0.40, green: 0.18, blue: 0.30)
    }

    private var shiftRowColor: Color {
		Color(red: 0.0, green: 0.0, blue: 0.40)
    }

    private var optionRowColor: Color {
        Color(red: 0.33, green: 0.19, blue: 0.78)
    }

    private var commandRowColor: Color {
        Color(red: 0.11, green: 0.20, blue: 0.88)
    }

    private var commandShiftColor: Color {
        Color(red: 0.7, green: 0.1, blue: 0.16)
    }

    private var optionCommandColor: Color {
        Color(red: 0.4, green: 0.2, blue: 0.5)
    }

    private var standardFunctionColor: Color {
        Color(red: 0.22, green: 0.22, blue: 0.22)
    }

    private var arrowColor: Color {
        Color(red: 0.1, green: 0.3, blue: 0.1)
    }

    private func triangleRotationDegrees(for keyToken: String, preferredName: String?) -> Double {
        guard preferredName == "triangle.fill" else {
            return 0
        }

        switch keyToken {
        case "UP":
            return 0
        case "DOWN":
            return 180
        case "LEFT":
            return -90
        case "RIGHT":
            return 90
        default:
            return 0
        }
    }
}

private struct KeyboardCell {
    let title: String
    let systemImageName: String?
    let fontSize: CGFloat?
    let imageRotationDegrees: Double
    let background: Color
    let foreground: Color
    let isEnabled: Bool
    let action: () -> Void

    init(
        title: String,
        systemImageName: String? = nil,
        fontSize: CGFloat? = nil,
        imageRotationDegrees: Double = 0,
        background: Color,
        foreground: Color,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImageName = systemImageName
        self.fontSize = fontSize
        self.imageRotationDegrees = imageRotationDegrees
        self.background = background
        self.foreground = foreground
        self.isEnabled = isEnabled
        self.action = action
    }
}

private enum KeyboardModifier: CaseIterable, Hashable {
    case control
    case shift
    case option
    case command

    var title: String {
        switch self {
        case .control:
            return "ctl"
        case .shift:
            return "sh"
        case .option:
            return "opt"
        case .command:
            return "cmd"
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
}

private enum CursorMovement {
    case left
    case right
}

private struct KeyboardInputField: UIViewRepresentable {
    @Binding var text: String
    let shouldBeFirstResponder: Bool
    let fontSize: CGFloat
    let autocapitalizationType: UITextAutocapitalizationType
    let autocorrectionEnabled: Bool
    let cursorCommand: CursorMovement
    let cursorCommandID: Int
    let onInsertedText: (String) -> Void
    let onBackspace: () -> Void
    let onReturn: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let textField = BackspaceAwareTextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.onDeleteBackward = {
            context.coordinator.onBackspace()
        }
        textField.borderStyle = .none
        textField.returnKeyType = .default
        textField.autocapitalizationType = autocapitalizationType
        textField.autocorrectionType = autocorrectionEnabled ? .yes : .no
        textField.spellCheckingType = .no
        textField.smartQuotesType = .no
        textField.smartDashesType = .no
        textField.smartInsertDeleteType = .no
        textField.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        textField.textColor = .white
        textField.font = UIFont.systemFont(ofSize: fontSize, weight: .regular)
        textField.textAlignment = .center
        textField.attributedPlaceholder = NSAttributedString(
            string: "typing area",
            attributes: [
                .foregroundColor: UIColor.lightGray,
                .font: UIFont.systemFont(ofSize: fontSize, weight: .regular)
            ]
        )
        textField.layer.cornerRadius = 4
        textField.layer.borderWidth = 1
        textField.layer.borderColor = UIColor.darkGray.cgColor
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 8, height: 1))
        textField.leftViewMode = .always
        textField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 8, height: 1))
        textField.rightViewMode = .always
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.clipsToBounds = true
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        if textField.text != text {
            textField.text = text
        }

        if let textField = textField as? BackspaceAwareTextField {
            textField.onDeleteBackward = {
                context.coordinator.onBackspace()
            }
        }

        let nextAutocorrectionType: UITextAutocorrectionType = autocorrectionEnabled ? .yes : .no
        let traitsChanged =
            textField.autocapitalizationType != autocapitalizationType ||
            textField.autocorrectionType != nextAutocorrectionType

        textField.font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        textField.textAlignment = .center
        textField.autocapitalizationType = autocapitalizationType
        textField.autocorrectionType = nextAutocorrectionType

        context.coordinator.onInsertedText = onInsertedText
        context.coordinator.onReturn = onReturn

        if context.coordinator.lastCursorCommandID != cursorCommandID {
            context.coordinator.lastCursorCommandID = cursorCommandID
            context.coordinator.applyCursorMove(cursorCommand, in: textField)
        }

        if shouldBeFirstResponder, !textField.isFirstResponder {
            textField.becomeFirstResponder()
        } else if !shouldBeFirstResponder, textField.isFirstResponder {
            textField.resignFirstResponder()
        } else if traitsChanged, textField.isFirstResponder {
            textField.reloadInputViews()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            onInsertedText: onInsertedText,
            onBackspace: onBackspace,
            onReturn: onReturn
        )
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        var onInsertedText: (String) -> Void
        var onBackspace: () -> Void
        var onReturn: () -> Void
        var lastCursorCommandID = 0

        init(
            text: Binding<String>,
            onInsertedText: @escaping (String) -> Void,
            onBackspace: @escaping () -> Void,
            onReturn: @escaping () -> Void
        ) {
            _text = text
            self.onInsertedText = onInsertedText
            self.onBackspace = onBackspace
            self.onReturn = onReturn
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            if string == "\n" {
                onReturn()
                return false
            }

            let currentText = textField.text ?? ""
            guard let stringRange = Range(range, in: currentText) else {
                return false
            }

            let updatedText = currentText.replacingCharacters(in: stringRange, with: string)
            DispatchQueue.main.async {
                self.text = updatedText

                if !string.isEmpty {
                    self.onInsertedText(string)
                }
            }

            return true
        }

        func applyCursorMove(_ movement: CursorMovement, in textField: UITextField) {
            guard let selectedRange = textField.selectedTextRange else {
                return
            }

            switch movement {
            case .left:
                guard let nextPosition = textField.position(from: selectedRange.start, offset: -1) else {
                    return
                }
                textField.selectedTextRange = textField.textRange(from: nextPosition, to: nextPosition)
            case .right:
                guard let nextPosition = textField.position(from: selectedRange.end, offset: 1) else {
                    return
                }
                textField.selectedTextRange = textField.textRange(from: nextPosition, to: nextPosition)
            }
        }
    }
}

private final class BackspaceAwareTextField: UITextField {
    var onDeleteBackward: (() -> Void)?

    override func deleteBackward() {
        onDeleteBackward?()
        super.deleteBackward()
    }
}

import SwiftUI

extension KeyboardScreen {
    var topRowCells: [KeyboardCell] {
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

    var secondRowCells: [KeyboardCell] {
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

    var thirdRowCells: [KeyboardCell] {
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

    var fourthRowCells: [KeyboardCell] {
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

    var fifthRowCells: [KeyboardCell] {
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

    var bottomRowCells: [KeyboardCell] {
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

    var mode2TopRowCells: [KeyboardCell] {
        [
            keyTokenCell(title: "/", keyToken: "kp/", background: keypadColor),
            keyTokenCell(title: "*", keyToken: "kp*", background: keypadColor),
            comboFunctionCell(title: "shift\nF13", tokens: ["sh"], functionKey: "f13", background: shiftRowColor),
            comboFunctionCell(title: "F14", tokens: ["sh"], functionKey: "f14", background: shiftRowColor),
            comboFunctionCell(title: "F15", tokens: ["sh"], functionKey: "f15", background: shiftRowColor),
            comboFunctionCell(title: "opt\nF13", tokens: ["op"], functionKey: "f13", background: optionRowColor),
            comboFunctionCell(title: "F14", tokens: ["op"], functionKey: "f14", background: optionRowColor),
            comboFunctionCell(title: "F15", tokens: ["op"], functionKey: "f15", background: optionRowColor),
            comboFunctionCell(title: "F16", tokens: ["op"], functionKey: "f16", background: optionRowColor),
            comboFunctionCell(title: "F17", tokens: ["op"], functionKey: "f17", background: optionRowColor),
            comboFunctionCell(title: "F18", tokens: ["op"], functionKey: "f18", background: optionRowColor),
            comboFunctionCell(title: "F19", tokens: ["op"], functionKey: "f19", background: optionRowColor),
            comboFunctionCell(title: "F20", tokens: ["op"], functionKey: "f20", background: optionRowColor)
        ]
    }

    var mode2SecondRowCells: [KeyboardCell] {
        [
            keyTokenCell(title: "7", keyToken: "kp7", background: keypadColor),
            keyTokenCell(title: "8", keyToken: "kp8", background: keypadColor),
            keyTokenCell(title: "9", keyToken: "kp9", background: keypadColor),
            keyTokenCell(title: "-", keyToken: "kp-", background: keypadColor),
            comboFunctionCell(title: "F16", tokens: ["sh"], functionKey: "f16", background: shiftRowColor),
            comboFunctionCell(title: "cmd F13", tokens: ["cm"], functionKey: "f13", background: commandRowColor),
            comboFunctionCell(title: "F14", tokens: ["cm"], functionKey: "f14", background: commandRowColor),
            comboFunctionCell(title: "F15", tokens: ["cm"], functionKey: "f15", background: commandRowColor),
            comboFunctionCell(title: "F16", tokens: ["cm"], functionKey: "f16", background: commandRowColor),
            comboFunctionCell(title: "F17", tokens: ["cm"], functionKey: "f17", background: commandRowColor),
            comboFunctionCell(title: "F18", tokens: ["cm"], functionKey: "f18", background: commandRowColor),
            comboFunctionCell(title: "F19", tokens: ["cm"], functionKey: "f19", background: commandRowColor),
            comboFunctionCell(title: "F20", tokens: ["cm"], functionKey: "f20", background: commandRowColor)
        ]
    }

    var mode2ThirdRowCells: [KeyboardCell] {
        [
            keyTokenCell(title: "4", keyToken: "kp4", background: keypadColor),
            keyTokenCell(title: "5", keyToken: "kp5", background: keypadColor),
            keyTokenCell(title: "6", keyToken: "kp6", background: keypadColor),
            keyTokenCell(title: "+", keyToken: "kp+", background: keypadColor),
            KeyboardCell(title: "clr all", background: clearAllButtonColor, foreground: activeModifiers.isEmpty ? .white : .black) {
                resetModifierToggles()
            },
            modifierCell(.control),
            modifierCell(.shift),
            modifierCell(.option),
            modifierCell(.command),
            keyTokenCell(title: "", systemImageName: "triangle.fill", keyToken: "UP", background: arrowColor, applyStickyModifiers: true),
            keyTokenCell(title: "", systemImageName: "triangle.fill", keyToken: "DOWN", background: arrowColor, applyStickyModifiers: true),
            keyTokenCell(title: "", systemImageName: "triangle.fill", keyToken: "LEFT", background: arrowColor, applyStickyModifiers: true),
            keyTokenCell(title: "", systemImageName: "triangle.fill", keyToken: "RIGHT", background: arrowColor, applyStickyModifiers: true)
        ]
    }

    var mode2FourthRowCells: [KeyboardCell] {
        [
            keyTokenCell(title: "1", keyToken: "kp1", background: keypadColor),
            keyTokenCell(title: "2", keyToken: "kp2", background: keypadColor),
            keyTokenCell(title: "3", keyToken: "kp3", background: keypadColor),
            plainFunctionCell("F11"),
            plainFunctionCell("F12"),
            plainFunctionCell("F13"),
            plainFunctionCell("F14"),
            plainFunctionCell("F15"),
            plainFunctionCell("F16"),
            plainFunctionCell("F17"),
            plainFunctionCell("F18"),
            plainFunctionCell("F19"),
            plainFunctionCell("F20")
        ]
    }

    var mode2BottomRowCells: [KeyboardCell] {
        [
            keyTokenCell(title: "ESC", keyToken: "ESC", background: standardFunctionColor),
            keyTokenCell(title: "0", keyToken: "kp0", background: keypadColor),
            keyTokenCell(title: ".", keyToken: "kp.", background: keypadColor),
            plainFunctionCell("F1"),
            plainFunctionCell("F2"),
            plainFunctionCell("F3"),
            plainFunctionCell("F4"),
            plainFunctionCell("F5"),
            plainFunctionCell("F6"),
            plainFunctionCell("F7"),
            plainFunctionCell("F8"),
            plainFunctionCell("F9"),
            plainFunctionCell("F10")
        ]
    }

    var mode3TopRowCells: [KeyboardCell] {
        [
            keyTokenCell(title: "7", keyToken: "kp7", background: keypadColor),
            keyTokenCell(title: "8", keyToken: "kp8", background: keypadColor),
            keyTokenCell(title: "9", keyToken: "kp9", background: keypadColor),
            keyTokenCell(title: "/", keyToken: "kp/", background: keypadColor),
            KeyboardCell(title: "clr all", background: clearAllButtonColor, foreground: activeModifiers.isEmpty ? .white : .black) {
                resetModifierToggles()
            },
            comboFunctionCell(title: "cmd F13", tokens: ["cm"], functionKey: "f13", background: commandRowColor),
            comboFunctionCell(title: "F14", tokens: ["cm"], functionKey: "f14", background: commandRowColor),
            comboFunctionCell(title: "F15", tokens: ["cm"], functionKey: "f15", background: commandRowColor),
            keyTokenCell(title: "", systemImageName: "triangle.fill", keyToken: "UP", background: arrowColor, applyStickyModifiers: true),
            keyTokenCell(title: "", systemImageName: "triangle.fill", keyToken: "DOWN", background: arrowColor, applyStickyModifiers: true)
        ]
    }

    var mode3SecondRowCells: [KeyboardCell] {
        [
            keyTokenCell(title: "4", keyToken: "kp4", background: keypadColor),
            keyTokenCell(title: "5", keyToken: "kp5", background: keypadColor),
            keyTokenCell(title: "6", keyToken: "kp6", background: keypadColor),
            keyTokenCell(title: "*", keyToken: "kp*", background: keypadColor),
            modifierCell(.control),
            modifierCell(.option),
            comboFunctionCell(title: "F16", tokens: ["cm"], functionKey: "f16", background: commandRowColor),
            comboFunctionCell(title: "F17", tokens: ["cm"], functionKey: "f17", background: commandRowColor),
            keyTokenCell(title: "", systemImageName: "triangle.fill", keyToken: "LEFT", background: arrowColor, applyStickyModifiers: true),
            keyTokenCell(title: "", systemImageName: "triangle.fill", keyToken: "RIGHT", background: arrowColor, applyStickyModifiers: true)
        ]
    }

    var mode3ThirdRowCells: [KeyboardCell] {
        [
            keyTokenCell(title: "1", keyToken: "kp1", background: keypadColor),
            keyTokenCell(title: "2", keyToken: "kp2", background: keypadColor),
            keyTokenCell(title: "3", keyToken: "kp3", background: keypadColor),
            keyTokenCell(title: "-", keyToken: "kp-", background: keypadColor),
            modifierCell(.shift),
            modifierCell(.command),
            comboFunctionCell(title: "F18", tokens: ["cm"], functionKey: "f18", background: commandRowColor),
            comboFunctionCell(title: "F19", tokens: ["cm"], functionKey: "f19", background: commandRowColor),
            plainFunctionCell("F19"),
            plainFunctionCell("F20")
        ]
    }

    var mode3BottomRowCells: [KeyboardCell] {
        [
            keyTokenCell(title: "ESC", keyToken: "ESC", background: standardFunctionColor),
            keyTokenCell(title: "0", keyToken: "kp0", background: keypadColor),
            keyTokenCell(title: ".", keyToken: "kp.", background: keypadColor),
            keyTokenCell(title: "+", keyToken: "kp+", background: keypadColor),
            plainFunctionCell("F13"),
            plainFunctionCell("F14"),
            plainFunctionCell("F15"),
            plainFunctionCell("F16"),
            plainFunctionCell("F17"),
            plainFunctionCell("F18")
        ]
    }

    var mode4Rows: [[KeyboardCell]] {
        let definitions: [Mode4RowDefinition] = [
            .init(title: "all F1", modifierTokens: ["ct", "sh", "op", "cm"], background: mode4AllRowColor, foreground: .black),
            .init(title: "ct op\nsh F1", modifierTokens: ["ct", "op", "sh"], background: mode4TripleRowColors[0], foreground: .white),
            .init(title: "ct sh\ncm F1", modifierTokens: ["ct", "sh", "cm"], background: mode4TripleRowColors[1], foreground: .black),
            .init(title: "ct op\ncm F1", modifierTokens: ["ct", "op", "cm"], background: mode4TripleRowColors[2], foreground: .white),
            .init(title: "sh op\ncm F1", modifierTokens: ["sh", "op", "cm"], background: mode4TripleRowColors[3], foreground: .black),
            .init(title: "sh ct\nF1", modifierTokens: ["sh", "ct"], background: mode4DoubleRowColors[0], foreground: .white),
            .init(title: "ct op\nF1", modifierTokens: ["ct", "op"], background: mode4DoubleRowColors[1], foreground: .black),
            .init(title: "op cm\nF1", modifierTokens: ["op", "cm"], background: mode4DoubleRowColors[2], foreground: .white),
            .init(title: "ct cm\nF1", modifierTokens: ["ct", "cm"], background: mode4DoubleRowColors[3], foreground: .black),
            .init(title: "sh cm\nF1", modifierTokens: ["sh", "cm"], background: mode4DoubleRowColors[4], foreground: .white),
            .init(title: "op cm\nF1", modifierTokens: ["op", "cm"], background: mode4DoubleRowColors[5], foreground: .black),
            .init(title: "ct F1", modifierTokens: ["ct"], background: mode4SingleRowColors[0], foreground: .white),
            .init(title: "sh F1", modifierTokens: ["sh"], background: mode4SingleRowColors[1], foreground: .black),
            .init(title: "op F1", modifierTokens: ["op"], background: mode4SingleRowColors[2], foreground: .white),
            .init(title: "cmd F1", modifierTokens: ["cm"], background: mode4SingleRowColors[3], foreground: .black),
            .init(title: "F1", modifierTokens: [], background: standardFunctionColor, foreground: .white)
        ]

        return definitions.map(mode4Row(from:))
    }

    private func mode4Row(from definition: Mode4RowDefinition) -> [KeyboardCell] {
        var cells = [
            KeyboardCell(title: definition.title, background: definition.background, foreground: definition.foreground) {
                sendTokens(definition.modifierTokens + ["f1"])
            }
        ]

        for functionNumber in 2...20 {
            let functionKey = "f\(functionNumber)"
            cells.append(
                KeyboardCell(
                    title: "F\(functionNumber)",
                    background: definition.background,
                    foreground: definition.foreground
                ) {
                    sendTokens(definition.modifierTokens + [functionKey])
                }
            )
        }

        return cells
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

    private var mode4AllRowColor: Color {
        Color(red: 1.0, green: 0.82, blue: 0.24)
    }

    private var mode4TripleRowColors: [Color] {
        [
            Color(red: 0.24, green: 0.18, blue: 0.08),
            Color(red: 0.86, green: 0.98, blue: 0.40),
            Color(red: 0.26, green: 0.14, blue: 0.34),
            Color(red: 1.0, green: 0.42, blue: 0.52)
        ]
    }

    private var mode4DoubleRowColors: [Color] {
        [
            Color(red: 0.22, green: 0.22, blue: 0.08),
            Color(red: 1.0, green: 0.66, blue: 0.20),
            Color(red: 0.11, green: 0.29, blue: 0.22),
            Color(red: 0.68, green: 0.44, blue: 1.0),
            Color(red: 0.22, green: 0.10, blue: 0.14),
            Color(red: 0.44, green: 1.0, blue: 0.78)
        ]
    }

    private var mode4SingleRowColors: [Color] {
        [
            Color(red: 0.27, green: 0.18, blue: 0.07),
            Color(red: 0.84, green: 0.42, blue: 1.0),
            Color(red: 0.08, green: 0.23, blue: 0.11),
            Color(red: 0.34, green: 0.46, blue: 1.0)
        ]
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

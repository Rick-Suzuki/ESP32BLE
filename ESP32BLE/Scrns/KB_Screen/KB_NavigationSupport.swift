import SwiftUI

extension KeyboardScreen {
    var currentKeyboardMode: KeyboardMode {
        KeyboardMode(rawValue: keyboardModeNumber) ?? .mode1
    }

    func advanceKeyboardMode() {
        let allModes = KeyboardMode.allCases
        let currentIndex = allModes.firstIndex(of: currentKeyboardMode) ?? 0
		let nextIndex = (currentIndex + 1) % (isPad ? allModes.count : allModes.count-1)
        keyboardModeNumber = allModes[nextIndex].rawValue
    }

    func hiddenCell(widthUnits: Int = 1) -> KeyboardCell {
        KeyboardCell(
            title: "",
            background: .clear,
            foreground: .clear,
            isEnabled: false,
            isVisible: false,
            widthUnits: widthUnits
        ) {
        }
    }
}

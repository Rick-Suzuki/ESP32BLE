import SwiftUI

extension KeyboardScreen {
    private var bluetoothDisconnectedPopupMessage: String {
        "Bluetooth not connected. Bluetooth needs to be connected before sending data to the ESP32."
    }

    func showBluetoothDisconnectedPopup() {
        popupMessage = bluetoothDisconnectedPopupMessage
    }

    var activeModifierTokens: [String] {
        KeyboardModifier.allCases
            .filter { activeModifiers.contains($0) }
            .map(\.token)
    }

    func toggleModifier(_ modifier: KeyboardModifier) {
        if activeModifiers.contains(modifier) {
            activeModifiers.remove(modifier)
        } else {
            activeModifiers.insert(modifier)
        }
    }

    func resetModifierToggles() {
        activeModifiers.removeAll()
    }

    func sendKeyWithStickyModifiers(_ keyToken: String) {
        sendTokens(activeModifierTokens + [keyToken])
    }

    func sendTokens(_ tokens: [String]) {
        guard !tokens.isEmpty else {
            return
        }

        if isSendOnReturnMode {
            replaceSoftKeyTokensBuffer(with: tokens)
            return
        }

        sendTokensDirectlyToBLE(tokens)
    }

    func sendTokensDirectlyToBLE(_ tokens: [String]) {
        guard ble.isConnected else {
            showBluetoothDisconnectedPopup()
            return
        }

        for token in tokens {
            ble.sendLine(token)
        }

        resetModifierToggles()
    }

    func sendModifiedTypedText() {
        let trimmedText = typingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }

        guard ble.isConnected else {
            showBluetoothDisconnectedPopup()
            return
        }

        ble.sendString(typingText)
    }

    func sendBufferedKeyboardContent() {
        if !bufferedSoftKeyTokens.isEmpty {
            sendTokensDirectlyToBLE(bufferedSoftKeyTokens)
            clearTypingArea()
            return
        }

        sendModifiedTypedText()
        clearTypingArea()
    }
}

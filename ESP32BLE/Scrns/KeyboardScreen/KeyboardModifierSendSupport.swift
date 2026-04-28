import SwiftUI

extension KeyboardScreen {
    private var bluetoothDisconnectedPopupMessage: String {
        "Bluetooth not connected. Bluetooth needs to be connected before sending data to the ESP32."
    }

    func showBluetoothDisconnectedPopup() {
        popupMessage = bluetoothDisconnectedPopupMessage
    }

    var activeModifierTokens: [String] {
        KeyboardModifier.orderedCases
            .filter { activeModifiers.contains($0) }
            .map(\.token)
    }

    func toggleModifier(_ modifier: KeyboardModifier) {
        if activeModifiers.contains(modifier) {
            activeModifiers.remove(modifier)
        } else {
            activeModifiers.insert(modifier)
        }

        syncBufferedTokensWithActiveModifiers()
    }

    func resetModifierToggles() {
        activeModifiers.removeAll()
        syncBufferedTokensWithActiveModifiers()
    }

    func sendKeyWithStickyModifiers(_ keyToken: String) {
        sendTokens(activeModifierTokens + [keyToken])
    }

    func sendTokens(_ tokens: [String]) {
        let normalizedTokens = normalizedModifierTokenSequence(tokens)

        guard !normalizedTokens.isEmpty else {
            return
        }

        if isSendOnReturnMode {
            replaceSoftKeyTokensBuffer(with: normalizedTokens)
            return
        }

        sendTokensDirectlyToBLE(normalizedTokens)
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

    func normalizedModifierTokenSequence(_ tokens: [String]) -> [String] {
        let activeModifierSet = Set(tokens.compactMap(KeyboardModifier.init(token:)))
        let orderedModifierTokens = KeyboardModifier.orderedCases
            .filter { activeModifierSet.contains($0) }
            .map(\.token)
        let nonModifierTokens = tokens.filter { KeyboardModifier(token: $0) == nil }
        return orderedModifierTokens + nonModifierTokens
    }

    func syncBufferedTokensWithActiveModifiers() {
        guard isSendOnReturnMode else {
            return
        }

        let nonModifierTokens = bufferedSoftKeyTokens.filter { KeyboardModifier(token: $0) == nil }
        bufferedSoftKeyTokens = activeModifierTokens + nonModifierTokens
        syncTypingTextWithBufferedTokens()
    }
}

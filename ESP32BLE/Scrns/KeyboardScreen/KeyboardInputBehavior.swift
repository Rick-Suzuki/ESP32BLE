import SwiftUI
import UIKit

extension KeyboardScreen {
    var isSendOnReturnMode: Bool {
        !isSendImmediatelyEnabled
    }

    var keyboardAutocapitalizationType: UITextAutocapitalizationType {
        if isAutoCapEnabled {
            return .allCharacters
        }

        if isEachWordCapEnabled {
            return .sentences
        }

        return .none
    }

    var effectiveKeyboardAutocapitalizationType: UITextAutocapitalizationType {
        keyboardAutocapitalizationType
    }

    var effectiveAutocorrectionEnabled: Bool {
        isAutoCorrectEnabled
    }

    var isSendButtonEnabled: Bool {
        isSendOnReturnMode && !typingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var activeModifierTokens: [String] {
        KeyboardModifier.allCases
            .filter { activeModifiers.contains($0) }
            .map(\.token)
    }

    func handleInsertedText(_ insertedText: String) {
        guard !insertedText.isEmpty else {
            return
        }

        if !bufferedSoftKeyTokens.isEmpty && typingText != bufferedSoftKeyTokens.joined(separator: ":") {
            bufferedSoftKeyTokens.removeAll()
        }
    }

    func handleBackspace() {
        guard !bufferedSoftKeyTokens.isEmpty else {
            return
        }

        if typingText.isEmpty {
            bufferedSoftKeyTokens.removeAll()
        }
    }

    func handleReturn() {
        guard isSendOnReturnMode else {
            return
        }

        sendBufferedKeyboardContent()
    }

    func moveCursor(_ movement: CursorMovement) {
        cursorCommand = movement
        cursorCommandID += 1
    }

    func sendTokensDirectlyToBLE(_ tokens: [String]) {
        guard ble.isConnected else {
            print("Bluetooth not connected.")
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
            print("Bluetooth not connected.")
            return
        }

        ble.sendString(typingText)
    }

    func replaceSoftKeyTokensBuffer(with tokens: [String]) {
        bufferedSoftKeyTokens = tokens
        syncTypingTextWithBufferedTokens()
        requestKeyboardFocus()
    }

    func syncTypingTextWithBufferedTokens() {
        typingText = bufferedSoftKeyTokens.joined(separator: ":")
    }

    func clearTypingArea() {
        typingText = ""
        bufferedSoftKeyTokens.removeAll()
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

    func requestKeyboardFocus() {
        shouldFocusInput = true
    }
}

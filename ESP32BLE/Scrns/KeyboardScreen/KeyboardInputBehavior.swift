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
        isSendOnReturnMode ? keyboardAutocapitalizationType : .none
    }

    var effectiveAutocorrectionEnabled: Bool {
        isSendOnReturnMode ? isAutoCorrectEnabled : false
    }

    var isSendButtonEnabled: Bool {
        isSendOnReturnMode && !typingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func handleInsertedText(_ insertedText: String) {
        guard !insertedText.isEmpty else {
            return
        }

        if isSendImmediatelyEnabled {
            guard ble.isConnected else {
                showBluetoothDisconnectedPopup()
                return
            }

            ble.sendString(insertedText)
            showImmediateTypingPreview(insertedText)
            return
        }

        if !bufferedSoftKeyTokens.isEmpty && typingText != displayText(for: bufferedSoftKeyTokens) {
            bufferedSoftKeyTokens.removeAll()
        }
    }

    func handleBackspace() {
        if isSendImmediatelyEnabled {
            guard ble.isConnected else {
                showBluetoothDisconnectedPopup()
                return
            }

            ble.pressBackspace()
            showImmediateTypingPreview("⏪")
            return
        }

        // In send-on-return mode, backspace is local text editing only.
        guard !bufferedSoftKeyTokens.isEmpty else {
            return
        }

        if typingText.isEmpty {
            bufferedSoftKeyTokens.removeAll()
        }
    }

    func handleReturn() {
        guard isSendOnReturnMode else {
            guard ble.isConnected else {
                showBluetoothDisconnectedPopup()
                return
            }

            ble.pressEnter()
            showImmediateTypingPreview("➡️")
            return
        }

        sendBufferedKeyboardContent()
    }

    func moveCursor(_ movement: CursorMovement) {
        cursorCommand = movement
        cursorCommandID += 1
    }

    func replaceSoftKeyTokensBuffer(with tokens: [String]) {
        bufferedSoftKeyTokens = tokens
        syncTypingTextWithBufferedTokens()
        requestKeyboardFocus()
    }

    func syncTypingTextWithBufferedTokens() {
        typingText = displayText(for: bufferedSoftKeyTokens)
    }

    func clearTypingArea() {
        typingText = ""
        bufferedSoftKeyTokens.removeAll()
    }

    func requestKeyboardFocus() {
        shouldFocusInput = true
    }

    func showImmediateTypingPreview(_ insertedText: String) {
        guard isSendImmediatelyEnabled else {
            return
        }

        immediateTypingPreviewTask?.cancel()
        typingText = insertedText

        immediateTypingPreviewTask = Task {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                typingText = ""
            }
        }
    }

    func displayText(for tokens: [String]) -> String {
        normalizedModifierTokenSequence(tokens)
            .map { token in
                if let modifier = KeyboardModifier(token: token) {
                    return modifier.displayToken
                }

                if token.hasPrefix("f"), token.dropFirst().allSatisfy(\.isNumber) {
                    return token.uppercased()
                }

                return token
            }
            .joined(separator: " ")
    }
}

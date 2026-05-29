import SwiftUI
import UIKit

struct KeyboardInputField: UIViewRepresentable {
    static let immediateModePlaceholder = "\u{200B}"

    @Binding var text: String
    @Binding var isFocused: Bool
    let shouldBeFirstResponder: Bool
    let isSendImmediatelyEnabled: Bool
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
        textField.onDeleteBackward = nil
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
        let displayedText = isSendImmediatelyEnabled
            ? (text.isEmpty ? Self.immediateModePlaceholder : text)
            : text
        if textField.text != displayedText {
            textField.text = displayedText
        }

        if let textField = textField as? BackspaceAwareTextField {
            textField.onDeleteBackward = nil
        }

        let nextAutocorrectionType: UITextAutocorrectionType = autocorrectionEnabled ? .yes : .no
        let traitsChanged =
            textField.autocapitalizationType != autocapitalizationType ||
            textField.autocorrectionType != nextAutocorrectionType

        textField.font = UIFont.systemFont(ofSize: fontSize, weight: .regular)
        textField.textAlignment = .center
        textField.autocapitalizationType = autocapitalizationType
        textField.autocorrectionType = nextAutocorrectionType

        context.coordinator.onInsertedText = onInsertedText
        context.coordinator.onBackspace = onBackspace
        context.coordinator.isSendImmediatelyEnabled = isSendImmediatelyEnabled
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

        if isSendImmediatelyEnabled,
           let endPosition = textField.endOfDocument as UITextPosition? {
            textField.selectedTextRange = textField.textRange(from: endPosition, to: endPosition)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            isFocused: $isFocused,
            isSendImmediatelyEnabled: isSendImmediatelyEnabled,
            onInsertedText: onInsertedText,
            onBackspace: onBackspace,
            onReturn: onReturn
        )
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        @Binding var isFocused: Bool
        var isSendImmediatelyEnabled: Bool
        var onInsertedText: (String) -> Void
        var onBackspace: () -> Void
        var onReturn: () -> Void
        var lastCursorCommandID = 0

        init(
            text: Binding<String>,
            isFocused: Binding<Bool>,
            isSendImmediatelyEnabled: Bool,
            onInsertedText: @escaping (String) -> Void,
            onBackspace: @escaping () -> Void,
            onReturn: @escaping () -> Void
        ) {
            _text = text
            _isFocused = isFocused
            self.isSendImmediatelyEnabled = isSendImmediatelyEnabled
            self.onInsertedText = onInsertedText
            self.onBackspace = onBackspace
            self.onReturn = onReturn
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            DispatchQueue.main.async {
                self.isFocused = true
            }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            DispatchQueue.main.async {
                self.isFocused = false
            }
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            ButtonClickFeedback.playIfEnabled()
            if string == "\n" {
                onReturn()
                return false
            }

            if isSendImmediatelyEnabled {
                if string.isEmpty, range.length > 0 {
                    onBackspace()
                } else if !string.isEmpty {
                    onInsertedText(string)
                }

                DispatchQueue.main.async {
                    textField.text = KeyboardInputField.immediateModePlaceholder
                    if let endPosition = textField.endOfDocument as UITextPosition? {
                        textField.selectedTextRange = textField.textRange(from: endPosition, to: endPosition)
                    }
                }

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

final class BackspaceAwareTextField: UITextField {
    var onDeleteBackward: (() -> Void)?

    override func deleteBackward() {
        onDeleteBackward?()
        super.deleteBackward()
    }
}

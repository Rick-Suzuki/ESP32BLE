import SwiftUI
import UIKit

final class SlotEditorInputController {
    weak var textField: UITextField?

    func insertText(_ text: String) {
        guard let textField else { return }
        textField.insertText(text)
    }

    func deleteBackward() {
        guard let textField else { return }
        textField.deleteBackward()
    }

    func focus() {
        textField?.becomeFirstResponder()
    }
}

struct SlotEditorTextField: UIViewRepresentable {
    @Binding var text: String
    let inputController: SlotEditorInputController
    let placeholder: String
    let onSubmit: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.borderStyle = .none
        textField.returnKeyType = .default
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.smartQuotesType = .no
        textField.smartDashesType = .no
        textField.smartInsertDeleteType = .no
        textField.delegate = context.coordinator
        textField.placeholder = placeholder
        textField.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        textField.textColor = .white
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.lightGray]
        )
        textField.layer.cornerRadius = 8
        textField.layer.borderWidth = 1
        textField.layer.borderColor = UIColor.darkGray.cgColor
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        textField.leftViewMode = .always
        textField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        textField.rightViewMode = .always
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        inputController.textField = textField

        if textField.text != text {
            textField.text = text
        }

        textField.placeholder = placeholder

        if textField.isFirstResponder, !context.coordinator.didPlaceCursorAtEnd {
            let endOfDocument = textField.endOfDocument
            textField.selectedTextRange = textField.textRange(from: endOfDocument, to: endOfDocument)
            context.coordinator.didPlaceCursorAtEnd = true
        } else if !textField.isFirstResponder {
            context.coordinator.didPlaceCursorAtEnd = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, inputController: inputController, onSubmit: onSubmit)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        let inputController: SlotEditorInputController
        let onSubmit: () -> Void
        var didPlaceCursorAtEnd = false

        init(text: Binding<String>, inputController: SlotEditorInputController, onSubmit: @escaping () -> Void) {
            _text = text
            self.inputController = inputController
            self.onSubmit = onSubmit
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            inputController.textField = textField
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            text = textField.text ?? ""
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            ButtonClickFeedback.playIfEnabled()
            return true
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            ButtonClickFeedback.playIfEnabled()
            onSubmit()
            return false
        }
    }
}

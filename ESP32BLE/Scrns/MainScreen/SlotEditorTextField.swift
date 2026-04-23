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

    func deleteForward() {
        guard let textField,
              let selectedTextRange = textField.selectedTextRange else {
            return
        }

        if !selectedTextRange.isEmpty {
            textField.replace(selectedTextRange, withText: "")
            return
        }

        guard let nextPosition = textField.position(from: selectedTextRange.start, offset: 1),
              let forwardRange = textField.textRange(from: selectedTextRange.start, to: nextPosition) else {
            return
        }

        textField.replace(forwardRange, withText: "")
    }

    func focus() {
        textField?.becomeFirstResponder()
    }
}

struct SlotEditorTextField: UIViewRepresentable {
    enum JoinPosition {
        case single
        case left
        case right
    }

    @Binding var text: String
    let inputController: SlotEditorInputController
    let placeholder: String
    let joinPosition: JoinPosition
    let onBeginEditing: () -> Void
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
        textField.adjustsFontSizeToFitWidth = true
        textField.minimumFontSize = 12
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.layer.cornerRadius = 8
        textField.layer.borderWidth = 1
        textField.layer.borderColor = UIColor.darkGray.cgColor
        textField.layer.masksToBounds = true
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        textField.leftViewMode = .always
        textField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        textField.rightViewMode = .always
        applyCornerMask(to: textField)
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        inputController.textField = textField

        if textField.text != text {
            textField.text = text
        }

        textField.placeholder = placeholder
        applyCornerMask(to: textField)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            inputController: inputController,
            onBeginEditing: onBeginEditing,
            onSubmit: onSubmit
        )
    }

    private func applyCornerMask(to textField: UITextField) {
        switch joinPosition {
        case .single:
            textField.layer.maskedCorners = [
                .layerMinXMinYCorner,
                .layerMaxXMinYCorner,
                .layerMinXMaxYCorner,
                .layerMaxXMaxYCorner
            ]
        case .left:
            textField.layer.maskedCorners = [
                .layerMinXMinYCorner,
                .layerMinXMaxYCorner
            ]
        case .right:
            textField.layer.maskedCorners = [
                .layerMaxXMinYCorner,
                .layerMaxXMaxYCorner
            ]
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        let inputController: SlotEditorInputController
        let onBeginEditing: () -> Void
        let onSubmit: () -> Void

        init(
            text: Binding<String>,
            inputController: SlotEditorInputController,
            onBeginEditing: @escaping () -> Void,
            onSubmit: @escaping () -> Void
        ) {
            _text = text
            self.inputController = inputController
            self.onBeginEditing = onBeginEditing
            self.onSubmit = onSubmit
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            inputController.textField = textField
            onBeginEditing()
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

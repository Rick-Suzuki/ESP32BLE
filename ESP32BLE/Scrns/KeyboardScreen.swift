import SwiftUI
import UIKit

struct KeyboardScreen: View {
    @ObservedObject var ble: BLEKeyboardManager
    @AppStorage("keyboardSendImmediatelyEnabled") private var isSendImmediatelyEnabled = true
    @Environment(\.dismiss) private var dismiss
    @State private var typingText = ""
    @State private var isKeyboardFocused = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                KeyboardInputField(
                    text: $typingText,
                    isFocused: $isKeyboardFocused,
                    onInsertedText: handleInsertedText(_:),
                    onReturn: handleReturn
                )
                .frame(maxWidth: .infinity)
                .frame(height: 42)

                Button(isSendImmediatelyEnabled ? "Send Immediately" : "Send on Return") {
                    isSendImmediatelyEnabled.toggle()
                    isKeyboardFocused = true
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(minHeight: 42)
                .background(isSendImmediatelyEnabled ? Color.blue : Color.gray.opacity(0.45))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSendImmediatelyEnabled ? Color.blue : Color.gray.opacity(0.45), lineWidth: 1.5)
                }
                .clipShape(.rect(cornerRadius: 12))

                Button("Main") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(minHeight: 42)
                .background(Color.gray.opacity(0.45))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.45), lineWidth: 1.5)
                }
                .clipShape(.rect(cornerRadius: 12))
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Spacer()
        }
        .background(Color.black.ignoresSafeArea())
        .toolbarVisibility(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .onAppear {
            isKeyboardFocused = true
        }
        .onTapGesture {
            isKeyboardFocused = true
        }
    }

    private func handleInsertedText(_ insertedText: String) {
        guard isSendImmediatelyEnabled, !insertedText.isEmpty else {
            return
        }

        ble.sendString(insertedText)
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

        isKeyboardFocused = true
    }
}

private struct KeyboardInputField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let onInsertedText: (String) -> Void
    let onReturn: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.borderStyle = .none
        textField.returnKeyType = .default
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.smartQuotesType = .no
        textField.smartDashesType = .no
        textField.smartInsertDeleteType = .no
        textField.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        textField.textColor = .white
        textField.attributedPlaceholder = NSAttributedString(
            string: "typing area",
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
        if textField.text != text {
            textField.text = text
        }

        if isFocused, !textField.isFirstResponder {
            textField.becomeFirstResponder()
        } else if !isFocused, textField.isFirstResponder {
            textField.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            isFocused: $isFocused,
            onInsertedText: onInsertedText,
            onReturn: onReturn
        )
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        @Binding var isFocused: Bool
        let onInsertedText: (String) -> Void
        let onReturn: () -> Void

        init(
            text: Binding<String>,
            isFocused: Binding<Bool>,
            onInsertedText: @escaping (String) -> Void,
            onReturn: @escaping () -> Void
        ) {
            _text = text
            _isFocused = isFocused
            self.onInsertedText = onInsertedText
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
            text = updatedText

            if !string.isEmpty {
                onInsertedText(string)
            }

            return true
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            isFocused = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            isFocused = false
        }
    }
}

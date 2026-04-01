import SwiftUI
import UIKit

struct KeyboardScreen: View {
    @ObservedObject var ble: BLEKeyboardManager
    let isPresented: Bool
    @AppStorage("keyboardSendImmediatelyEnabled") private var isSendImmediatelyEnabled = true
    @AppStorage("keyboardAutoCapEnabled") private var isAutoCapEnabled = false
    @AppStorage("keyboardEachWordCapEnabled") private var isEachWordCapEnabled = false
    @AppStorage("keyboardAutoCorrectEnabled") private var isAutoCorrectEnabled = false
    let returnToMain: () -> Void
    @State private var typingText = ""
    @State private var shouldFocusInput = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    KeyboardInputField(
                        text: $typingText,
                        shouldBeFirstResponder: shouldFocusInput,
                        autocapitalizationType: keyboardAutocapitalizationType,
                        autocorrectionEnabled: isSendOnReturnMode && isAutoCorrectEnabled,
                        onInsertedText: handleInsertedText(_:),
                        onBackspace: handleBackspace,
                        onReturn: handleReturn
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)

                    Button("Main") {
                        shouldFocusInput = false
                        returnToMain()
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

                HStack(spacing: 12) {
                    Button(isSendImmediatelyEnabled ? "Send Immediately" : "Send on Return") {
                        isSendImmediatelyEnabled.toggle()
                        requestKeyboardFocus()
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

                    keyboardOptionButton(
                        "auto-cap",
                        isOn: $isAutoCapEnabled,
                        isEnabled: isSendOnReturnMode
                    )
                    keyboardOptionButton(
                        "each word",
                        isOn: $isEachWordCapEnabled,
                        isEnabled: isSendOnReturnMode
                    )
                    keyboardOptionButton(
                        "auto-correct",
                        isOn: $isAutoCorrectEnabled,
                        isEnabled: isSendOnReturnMode
                    )

                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Spacer()
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onChange(of: isPresented) {
            if isPresented {
                requestKeyboardFocus()
            } else {
                shouldFocusInput = false
            }
        }
        .onTapGesture {
            requestKeyboardFocus()
        }
    }

    private var isSendOnReturnMode: Bool {
        !isSendImmediatelyEnabled
    }

    private var keyboardAutocapitalizationType: UITextAutocapitalizationType {
        if isSendOnReturnMode, isEachWordCapEnabled {
            return .words
        }

        if isSendOnReturnMode, isAutoCapEnabled {
            return .sentences
        }

        return .none
    }

    private func keyboardOptionButton(_ title: String, isOn: Binding<Bool>, isEnabled: Bool) -> some View {
        Button(title) {
            guard isEnabled else {
                return
            }

            isOn.wrappedValue.toggle()
            requestKeyboardFocus()
        }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.7))
            .padding(.horizontal, 14)
            .frame(minHeight: 42)
            .background(optionButtonBackgroundColor(isEnabled: isEnabled, isOn: isOn.wrappedValue))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(optionButtonBorderColor(isEnabled: isEnabled, isOn: isOn.wrappedValue), lineWidth: 1.5)
            }
            .clipShape(.rect(cornerRadius: 12))
            .disabled(!isEnabled)
    }

    private func optionButtonBackgroundColor(isEnabled: Bool, isOn: Bool) -> Color {
        guard isEnabled else {
            return Color.gray.opacity(0.3)
        }

        return isOn ? Color.blue : Color.gray.opacity(0.45)
    }

    private func optionButtonBorderColor(isEnabled: Bool, isOn: Bool) -> Color {
        guard isEnabled else {
            return Color.gray.opacity(0.35)
        }

        return isOn ? Color.blue : Color.gray.opacity(0.45)
    }

    private func handleInsertedText(_ insertedText: String) {
        guard isSendImmediatelyEnabled, !insertedText.isEmpty else {
            return
        }

        ble.sendString(insertedText)
        typingText = ""
    }

    private func handleBackspace() {
        guard isSendImmediatelyEnabled else {
            return
        }

        ble.pressBackspace()
        typingText = ""
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

        requestKeyboardFocus()
    }

    private func requestKeyboardFocus() {
        DispatchQueue.main.async {
            shouldFocusInput = true
        }
    }
}

private struct KeyboardInputField: UIViewRepresentable {
    @Binding var text: String
    let shouldBeFirstResponder: Bool
    let autocapitalizationType: UITextAutocapitalizationType
    let autocorrectionEnabled: Bool
    let onInsertedText: (String) -> Void
    let onBackspace: () -> Void
    let onReturn: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let textField = BackspaceAwareTextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.onDeleteBackward = {
            context.coordinator.onBackspace()
        }
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

        if let textField = textField as? BackspaceAwareTextField {
            textField.onDeleteBackward = {
                context.coordinator.onBackspace()
            }
        }

        let nextAutocorrectionType: UITextAutocorrectionType = autocorrectionEnabled ? .yes : .no
        let traitsChanged =
            textField.autocapitalizationType != autocapitalizationType ||
            textField.autocorrectionType != nextAutocorrectionType

        textField.autocapitalizationType = autocapitalizationType
        textField.autocorrectionType = nextAutocorrectionType
        textField.reloadInputViews()

        context.coordinator.onInsertedText = onInsertedText
        context.coordinator.onReturn = onReturn

        if shouldBeFirstResponder, !textField.isFirstResponder {
            textField.becomeFirstResponder()
        } else if !shouldBeFirstResponder, textField.isFirstResponder {
            textField.resignFirstResponder()
        } else if traitsChanged, textField.isFirstResponder {
            textField.reloadInputViews()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            onInsertedText: onInsertedText,
            onBackspace: onBackspace,
            onReturn: onReturn
        )
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        var onInsertedText: (String) -> Void
        var onBackspace: () -> Void
        var onReturn: () -> Void

        init(
            text: Binding<String>,
            onInsertedText: @escaping (String) -> Void,
            onBackspace: @escaping () -> Void,
            onReturn: @escaping () -> Void
        ) {
            _text = text
            self.onInsertedText = onInsertedText
            self.onBackspace = onBackspace
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
    }
}

private final class BackspaceAwareTextField: UITextField {
    var onDeleteBackward: (() -> Void)?

    override func deleteBackward() {
        onDeleteBackward?()
        super.deleteBackward()
    }
}

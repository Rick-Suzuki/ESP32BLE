import SwiftUI
import UIKit

struct KeyboardTopSectionView: View {
    let currentModeNumber: Int
    @Binding var typingText: String
    @Binding var shouldFocusInput: Bool
    let isPresented: Bool
    let typingAreaFontSize: CGFloat
    let autocapitalizationType: UITextAutocapitalizationType
    let autocorrectionEnabled: Bool
    let cursorCommand: CursorMovement
    let cursorCommandID: Int
    let isSendImmediatelyEnabled: Binding<Bool>
    let isAutoCapEnabled: Binding<Bool>
    let isEachWordCapEnabled: Binding<Bool>
    let isAutoCorrectEnabled: Binding<Bool>
    let isSendOnReturnMode: Bool
    let isSendButtonEnabled: Bool
    let topControlSingleButtonWidth: CGFloat
    let topControlDoubleButtonWidth: CGFloat
    let topMainButtonWidth: CGFloat
    let onAdvanceMode: () -> Void
    let onInsertedText: (String) -> Void
    let onBackspace: () -> Void
    let onReturn: () -> Void
    let onClear: () -> Void
    let onReturnToMain: () -> Void
    let onMoveLeft: () -> Void
    let onMoveRight: () -> Void
    let onSend: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                topNavButton(title: "mode \(currentModeNumber)") {
                    onAdvanceMode()
                }

                KeyboardInputField(
                    text: $typingText,
                    isFocused: $shouldFocusInput,
                    shouldBeFirstResponder: shouldFocusInput && isPresented,
                    fontSize: typingAreaFontSize,
                    autocapitalizationType: autocapitalizationType,
                    autocorrectionEnabled: autocorrectionEnabled,
                    cursorCommand: cursorCommand,
                    cursorCommandID: cursorCommandID,
                    onInsertedText: onInsertedText,
                    onBackspace: onBackspace,
                    onReturn: onReturn
                )
                .frame(maxWidth: .infinity)
                .frame(height: 34)

                Button("x") {
                    ButtonClickFeedback.playIfEnabled()
                    onClear()
                }
                .buttonStyle(.plain)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.red)
                .clipShape(Circle())

                topNavButton(title: "Main") {
                    onReturnToMain()
                }
            }

            HStack(spacing: 4) {
                topControlButton(
                    title: isSendImmediatelyEnabled.wrappedValue ? "Send Immediately" : "Send on Return",
                    background: isSendImmediatelyEnabled.wrappedValue ? .blue : Color.gray.opacity(0.45),
                    width: topControlDoubleButtonWidth
                ) {
                    isSendImmediatelyEnabled.wrappedValue.toggle()
                }

                topOptionButton(
                    title: "auto-caps",
                    isOn: isAutoCapEnabled,
                    isEnabled: isSendOnReturnMode,
                    width: nil
                )
                topOptionButton(
                    title: "cap 1st letter",
                    isOn: isEachWordCapEnabled,
                    isEnabled: isSendOnReturnMode,
                    width: nil
                )
                topOptionButton(
                    title: "auto-correct",
                    isOn: isAutoCorrectEnabled,
                    isEnabled: isSendOnReturnMode,
                    width: nil
                )

                topControlButton(
                    systemImageName: "triangle.fill",
                    rotationDegrees: -90,
                    background: .blue,
                    width: topControlSingleButtonWidth
                ) {
                    onMoveLeft()
                }
                topControlButton(
                    systemImageName: "triangle.fill",
                    rotationDegrees: 90,
                    background: .blue,
                    width: topControlSingleButtonWidth
                ) {
                    onMoveRight()
                }

                Spacer(minLength: 0)

                topControlButton(
                    title: "Send",
                    background: Color.green.opacity(0.7),
                    width: topMainButtonWidth + 5,
                    isEnabled: isSendButtonEnabled
                ) {
                    onSend()
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }

    private func topNavButton(title: String, background: Color = Color.gray.opacity(0.45), action: @escaping () -> Void) -> some View {
        Button(title) {
            ButtonClickFeedback.playIfEnabled()
            action()
        }
        .buttonStyle(.plain)
        .font(.headline)
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(background)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
        }
        .clipShape(.rect(cornerRadius: 12))
    }

    private func topControlButton(
        title: String? = nil,
        systemImageName: String? = nil,
        rotationDegrees: Double = 0,
        background: Color,
        width: CGFloat? = nil,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            action()
        } label: {
            Group {
                if let systemImageName {
                    Image(systemName: systemImageName)
                        .font(.system(size: 16, weight: .bold))
                        .rotationEffect(.degrees(rotationDegrees))
                } else {
                    Text(title ?? "")
                }
            }
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.7))
            .frame(width: width, height: 30)
            .padding(.horizontal, width == nil ? 10 : 0)
            .background(isEnabled ? background : Color.gray.opacity(0.35))
            .clipShape(.rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func topOptionButton(title: String, isOn: Binding<Bool>, isEnabled: Bool, width: CGFloat? = nil) -> some View {
        Button(title) {
            guard isEnabled else {
                return
            }

            ButtonClickFeedback.playIfEnabled()
            isOn.wrappedValue.toggle()
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.7))
        .frame(width: width, height: 30)
        .padding(.horizontal, width == nil ? 10 : 0)
        .background(optionButtonBackgroundColor(isEnabled: isEnabled, isOn: isOn.wrappedValue))
        .clipShape(.rect(cornerRadius: 6))
        .disabled(!isEnabled)
    }

    private func optionButtonBackgroundColor(isEnabled: Bool, isOn: Bool) -> Color {
        guard isEnabled else {
            return Color.gray.opacity(0.35)
        }

        return isOn ? .blue : Color.gray.opacity(0.45)
    }
}

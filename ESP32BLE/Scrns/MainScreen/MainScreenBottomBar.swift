import SwiftUI

struct MainScreenBottomBar: View {
    private let inactiveButtonBackgroundColor = Color(red: 0.22, green: 0.22, blue: 0.24)
    private let inactiveButtonBorderColor = Color(red: 0.30, green: 0.30, blue: 0.32)
    let availableWidth: CGFloat
    let allowedVisibleBoxCounts: [Int]
    let visibleBoxCount: Int
    let boxFontSize: Double
    let minimumBoxFontSize: Double
    let maximumBoxFontSize: Double
    let speechRecognitionDisplayText: String
    let speechRecognitionDisplayColor: Color
    let isSpeechRecognitionEnabled: Bool
    let isBLESendEnabled: Bool
    let displayMode: FunctionKeyDisplayMode
    let displayModeButtonColor: Color
    let countControlColor: Color
    let fontControlColor: Color
    let speechRecognitionActiveColor: Color
    let bleSendActiveColor: Color
    let onDecreaseVisibleBoxCount: () -> Void
    let onIncreaseVisibleBoxCount: () -> Void
    let onDecreaseBoxFontSize: () -> Void
    let onIncreaseBoxFontSize: () -> Void
    let onToggleSpeechRecognition: () -> Void
    let onToggleBLESend: () -> Void
    let onAdvanceDisplayMode: () -> Void

    var body: some View {
        GeometryReader { _ in
            ViewThatFits(in: .horizontal) {
                bottomBarLayout(
                    isCompact: false,
                    speechBoxWidth: 270,
                    toggleWidth: 110,
                    displayModeWidth: 150
                )

                bottomBarLayout(
                    isCompact: true,
                    speechBoxWidth: 0,
                    toggleWidth: 88,
                    displayModeWidth: 100
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .frame(height: 62)
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }

    private func bottomBarLayout(
        isCompact: Bool,
        speechBoxWidth: CGFloat,
        toggleWidth: CGFloat,
        displayModeWidth: CGFloat
    ) -> some View {
        HStack(spacing: isCompact ? 8 : 12) {
            HStack(spacing: isCompact ? 8 : 12) {
                controlTriangle(rotationDegrees: -90, foreground: countControlColor) {
                    onDecreaseVisibleBoxCount()
                }
                .disabled(visibleBoxCount == allowedVisibleBoxCounts.first)

                Text("num:\(visibleBoxCount)")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(minWidth: isCompact ? 28 : 32)

                controlTriangle(rotationDegrees: 90, foreground: countControlColor) {
                    onIncreaseVisibleBoxCount()
                }
                .disabled(visibleBoxCount == allowedVisibleBoxCounts.last)
            }

            if !isCompact {
                HStack(spacing: 12) {
                    controlTriangle(rotationDegrees: -90, foreground: fontControlColor) {
                        onDecreaseBoxFontSize()
                    }
                    .disabled(boxFontSize <= minimumBoxFontSize)

                    Text("fnt:\(Int(boxFontSize))")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(minWidth: 32)

                    controlTriangle(rotationDegrees: 90, foreground: fontControlColor) {
                        onIncreaseBoxFontSize()
                    }
                    .disabled(boxFontSize >= maximumBoxFontSize)
                }
            }

            Spacer(minLength: isCompact ? 6 : 12)

            toggleButton(
                title: isSpeechRecognitionEnabled ? "spk rec on" : "spk rec off",
                background: isSpeechRecognitionEnabled ? speechRecognitionActiveColor : inactiveButtonBackgroundColor,
                border: isSpeechRecognitionEnabled ? speechRecognitionActiveColor : inactiveButtonBorderColor,
                action: onToggleSpeechRecognition
            )
            .frame(width: toggleWidth)

            if !isCompact {
                Text(speechRecognitionDisplayText)
                    .font(.body)
                    .foregroundStyle(speechRecognitionDisplayColor)
                    .opacity(0.6)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: speechBoxWidth, alignment: .leading)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 38)
                    .background(Color.black.opacity(0.7))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white, lineWidth: 1)
                    }
                    .clipShape(.rect(cornerRadius: 6))
            }

            toggleButton(
                title: isBLESendEnabled ? "btn active" : "disabled",
                background: isBLESendEnabled ? bleSendActiveColor : inactiveButtonBackgroundColor,
                border: isBLESendEnabled ? bleSendActiveColor : inactiveButtonBorderColor,
                action: onToggleBLESend
            )
            .frame(width: toggleWidth)

            Button {
                onAdvanceDisplayMode()
            } label: {
                Text(displayMode.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(displayModeButtonColor)
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(displayModeButtonColor, lineWidth: 2)
            }
            .clipShape(.rect(cornerRadius: 12))
            .frame(width: displayModeWidth)
        }
    }

    private func controlTriangle(rotationDegrees: Double, foreground: Color, action: @escaping () -> Void) -> some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            action()
        } label: {
            Image(systemName: "triangle.fill")
                .font(.system(size: 24))
                .rotationEffect(.degrees(rotationDegrees))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .foregroundStyle(foreground)
    }

    private func toggleButton(title: String, background: Color, border: Color, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 50)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(background)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(border, lineWidth: 2)
        }
        .clipShape(.rect(cornerRadius: 12))
    }
}

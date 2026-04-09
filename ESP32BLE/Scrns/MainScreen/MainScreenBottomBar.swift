import SwiftUI

struct MainScreenBottomBar: View {
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
            let isCompact = availableWidth < 1200
            let speechBoxWidth: CGFloat = 220
            let toggleWidth: CGFloat = isCompact ? 88 : 140
            let displayModeWidth: CGFloat = isCompact ? 100 : 170

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
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.35), lineWidth: 1)
                        }
                        .clipShape(.rect(cornerRadius: 6))

                    Spacer(minLength: 12)
                }

                toggleButton(
                    title: isSpeechRecognitionEnabled ? "spk rec on" : "spk rec off",
                    background: isSpeechRecognitionEnabled ? speechRecognitionActiveColor : Color.gray.opacity(0.45),
                    border: isSpeechRecognitionEnabled ? speechRecognitionActiveColor : Color.gray.opacity(0.4),
                    action: onToggleSpeechRecognition
                )
                .frame(width: toggleWidth)

                toggleButton(
                    title: isBLESendEnabled ? "btn active" : "disabled",
                    background: isBLESendEnabled ? bleSendActiveColor : Color.gray.opacity(0.45),
                    border: isBLESendEnabled ? bleSendActiveColor : Color.gray.opacity(0.4),
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .frame(height: 62)
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
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

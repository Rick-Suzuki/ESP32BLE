import SwiftUI

struct MainScreenBottomBar: View {
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
        HStack {
            HStack(spacing: 12) {
                controlTriangle(rotationDegrees: -90, foreground: countControlColor) {
                    onDecreaseVisibleBoxCount()
                }
                .disabled(visibleBoxCount == allowedVisibleBoxCounts.first)

                Text("num:\(visibleBoxCount)")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(minWidth: 32)

                controlTriangle(rotationDegrees: 90, foreground: countControlColor) {
                    onIncreaseVisibleBoxCount()
                }
                .disabled(visibleBoxCount == allowedVisibleBoxCounts.last)
            }

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

            Spacer(minLength: 12)

            Text(speechRecognitionDisplayText)
                .font(.body)
                .foregroundStyle(speechRecognitionDisplayColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(minHeight: 38)
                .background(Color.black.opacity(0.8))
                .clipShape(.rect(cornerRadius: 6))
                .frame(maxWidth: 360)

            Spacer(minLength: 12)

            toggleButton(
                title: isSpeechRecognitionEnabled ? "spk rec on" : "spk rec off",
                background: isSpeechRecognitionEnabled ? speechRecognitionActiveColor : Color.gray.opacity(0.45),
                border: isSpeechRecognitionEnabled ? speechRecognitionActiveColor : Color.gray.opacity(0.4),
                action: onToggleSpeechRecognition
            )
            .frame(maxWidth: 150)

            toggleButton(
                title: isBLESendEnabled ? "btn active" : "disabled",
                background: isBLESendEnabled ? bleSendActiveColor : Color.gray.opacity(0.45),
                border: isBLESendEnabled ? bleSendActiveColor : Color.gray.opacity(0.4),
                action: onToggleBLESend
            )
            .frame(maxWidth: 150)

            Button {
                onAdvanceDisplayMode()
            } label: {
                Text(displayMode.title)
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
            .frame(maxWidth: 180)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.thinMaterial)
        .clipShape(.rect(cornerRadius: 16))
    }

    private func controlTriangle(rotationDegrees: Double, foreground: Color, action: @escaping () -> Void) -> some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            action()
        } label: {
            Image(systemName: "triangle.fill")
                .font(.system(size: 30))
                .rotationEffect(.degrees(rotationDegrees))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .foregroundStyle(foreground)
    }

    private func toggleButton(title: String, background: Color, border: Color, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Text(title)
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

import SwiftUI

struct SettingsToolbarButton: View {
    let title: String
    let backgroundColor: Color
    let action: () -> Void

    var body: some View {
        Button(title) {
            ButtonClickFeedback.playIfEnabled()
            action()
        }
        .font(.headline)
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(minWidth: 92, minHeight: 44)
        .background(backgroundColor)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
        }
        .clipShape(.rect(cornerRadius: 12))
        .contentShape(.rect)
    }
}

struct SettingsEditorSectionView: View {
    @Binding var text: String
    @Binding var fontSize: CGFloat
    @Binding var isFocused: Bool
    let savedText: String
    let onUndo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PlainDocumentEditor(
                text: $text,
                fontSize: $fontSize,
                isFocused: $isFocused
            )
            .background(Color.black.opacity(0.55))
            .clipShape(.rect(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .background(Color.black)
        .overlay {
            Rectangle()
                .stroke(Color.white, lineWidth: 1)
        }
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 8) {
                fontSizeControls
                undoButton
            }
            .padding(8)
        }
        .clipShape(.rect(cornerRadius: 0))
    }

    private var fontSizeControls: some View {
        HStack(spacing: 8) {
            Button {
                fontSize = max(10, fontSize - 1)
            } label: {
                Image(systemName: "triangle.fill")
                    .font(.system(size: 16))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 18, height: 18)
                    .padding(8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .contentShape(.rect)

            Text("font:\(Int(fontSize))")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            Button {
                fontSize = min(40, fontSize + 1)
            } label: {
                Image(systemName: "triangle.fill")
                    .font(.system(size: 16))
                    .rotationEffect(.degrees(90))
                    .frame(width: 18, height: 18)
                    .padding(8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .contentShape(.rect)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .background(Color.black.opacity(0.5))
        .clipShape(.rect(cornerRadius: 10))
    }

    private var undoButton: some View {
        Button("undo") {
            ButtonClickFeedback.playIfEnabled()
            onUndo()
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.gray.opacity(0.45))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.5), lineWidth: 1)
        }
        .clipShape(.rect(cornerRadius: 8))
        .disabled(text == savedText)
        .opacity(text == savedText ? 0.35 : 1)
    }
}

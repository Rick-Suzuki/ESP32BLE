import SwiftUI

struct MainScreenSlotEditorOverlay: View {
    @Binding var editingSlotText: String
    let focusBinding: FocusState<Bool>.Binding
    let buttonSpacing: CGFloat
    let helperButtonWidth: CGFloat
    let onCancel: () -> Void
    let onCommit: () -> Void
    let onTest: () -> Void

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: buttonSpacing) {
                HStack(spacing: buttonSpacing) {
                    Button("cancel") {
                        ButtonClickFeedback.playIfEnabled()
                        onCancel()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(minWidth: 101)
                    .frame(minHeight: 44)
                    .background(Color.gray.opacity(0.45))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
                    }
                    .clipShape(.rect(cornerRadius: 12))

                    SlotEditorTextField(text: $editingSlotText, placeholder: "edit button text") {
                        onCommit()
                    }
                    .frame(width: geometry.size.width.isFinite ? max(0, geometry.size.width * 0.36) : 0, height: 36)
                    .focused(focusBinding)

                    Button {
                        ButtonClickFeedback.playIfEnabled()
                        editingSlotText = ""
                        focusBinding.wrappedValue = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.red)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Button("test") {
                        ButtonClickFeedback.playIfEnabled()
                        onTest()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(minWidth: 71)
                    .frame(minHeight: 44)
                    .background(Color(red: 0.0, green: 0.5, blue: 0.0))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(red: 0.0, green: 0.5, blue: 0.0), lineWidth: 1.5)
                    }
                    .clipShape(.rect(cornerRadius: 12))

                    Button("save") {
                        ButtonClickFeedback.playIfEnabled()
                        onCommit()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(minWidth: 71)
                    .frame(minHeight: 44)
                    .background(Color.blue)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue, lineWidth: 1.5)
                    }
                    .clipShape(.rect(cornerRadius: 12))
                }

                HStack(spacing: buttonSpacing) {
                    helperInsertButton("ctl:")
                    helperInsertButton("sh:")
                    helperInsertButton("op:")
                    helperInsertButton("cm:")
                    helperInsertButton("F")
                    helperInsertButton("F1::")
                    helperInsertButton(":")
                    helperInsertButton("::")
                    helperInsertButton("kp")
                    helperBackspaceButton()
                }

                HStack(spacing: buttonSpacing) {
                    helperInsertButton("0")
                    helperInsertButton("1")
                    helperInsertButton("2")
                    helperInsertButton("3")
                    helperInsertButton("4")
                    helperInsertButton("5")
                    helperInsertButton("6")
                    helperInsertButton("7")
                    helperInsertButton("8")
                    helperInsertButton("9")
                }

                HStack(spacing: buttonSpacing) {
                    helperInsertButton(systemImage: "triangle.fill", rotationDegrees: 0, insertedText: "UP::")
                    helperInsertButton(systemImage: "triangle.fill", rotationDegrees: 180, insertedText: "DOWN::")
                    helperInsertButton(systemImage: "triangle.fill", rotationDegrees: -90, insertedText: "LEFT::")
                    helperInsertButton(systemImage: "triangle.fill", rotationDegrees: 90, insertedText: "RIGHT::")
                    helperInsertButton("+")
                    helperInsertButton("_")
                    helperInsertButton("/")
                    helperInsertButton("*")
                    helperInsertButton("ESC:")
                    helperInsertButton("RET:")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.7))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.35), lineWidth: 1)
            }
            .clipShape(.rect(cornerRadius: 12))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(height: 192)
    }

    private func helperInsertButton(_ text: String) -> some View {
        Button(text) {
            ButtonClickFeedback.playIfEnabled()
            editingSlotText.append(text)
            focusBinding.wrappedValue = true
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .frame(width: helperButtonWidth, height: 44)
        .background(Color.black)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white, lineWidth: 2)
        }
        .clipShape(.rect(cornerRadius: 12))
    }

    private func helperInsertButton(systemImage: String, rotationDegrees: Double, insertedText: String) -> some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            editingSlotText.append(insertedText)
            focusBinding.wrappedValue = true
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .rotationEffect(.degrees(rotationDegrees))
                .foregroundStyle(.white)
                .frame(width: helperButtonWidth, height: 44)
        }
        .buttonStyle(.plain)
        .background(Color.black)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white, lineWidth: 2)
        }
        .clipShape(.rect(cornerRadius: 12))
    }

    private func helperBackspaceButton() -> some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            guard !editingSlotText.isEmpty else {
                focusBinding.wrappedValue = true
                return
            }

            editingSlotText.removeLast()
            focusBinding.wrappedValue = true
        } label: {
            Image(systemName: "delete.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: helperButtonWidth, height: 44)
        }
        .buttonStyle(.plain)
        .background(Color(red: 0.0, green: 0.2, blue: 0.45))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white, lineWidth: 2)
        }
        .clipShape(.rect(cornerRadius: 12))
    }
}

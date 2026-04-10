import SwiftUI

struct MainScreenSlotEditorOverlay: View {
    private enum ActiveEditorField {
        case action
        case text
    }

    @Binding var editingSlotText: String
    let focusBinding: FocusState<Bool>.Binding
    let buttonSpacing: CGFloat
    let helperButtonWidth: CGFloat
    let onCancel: () -> Void
    let onCommit: () -> Void
    let onTest: () -> Void
    @State private var actionInputController = SlotEditorInputController()
    @State private var rightInputController = SlotEditorInputController()
    @State private var activeEditorField: ActiveEditorField = .action
    @State private var actionDraft = ""
    @State private var rightDraft = ""

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
                    .frame(minWidth: 70)//101
                    .frame(minHeight: 44)
                    .background(Color.gray.opacity(0.45))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
                    }
                    .clipShape(.rect(cornerRadius: 12))

                    clearActionButton

                    HStack(spacing: 0) {
                        SlotEditorTextField(
                            text: actionTextBinding,
                            inputController: actionInputController,
                            placeholder: "action",
                            joinPosition: .left,
                            onBeginEditing: { activeEditorField = .action }
                        ) {
                            onCommit()
                        }
                        .frame(width: geometry.size.width.isFinite ? max(0, geometry.size.width * 0.18) : 0, height: 36)

                        SlotEditorTextField(
                            text: rightTextBinding,
                            inputController: rightInputController,
                            placeholder: "text",
                            joinPosition: .right,
                            onBeginEditing: { activeEditorField = .text }
                        ) {
                            onCommit()
                        }
                        .frame(width: geometry.size.width.isFinite ? max(0, geometry.size.width * 0.18) : 0, height: 36)
                    }

                    clearRightButton

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
					helperInsertButton("F")
                    helperInsertButton("ctl:")
                    helperInsertButton("sh:")
                    helperInsertButton("op:")
                    helperInsertButton("cm:")
                   
					helperInsertButton("ESC:")
					helperInsertButton("RET:")
					helperInsertButton("BS:")
					helperInsertButton("CA:")
                    helperBackspaceButton()
                }
				//
				//----------------------------------------
				//
                HStack(spacing: buttonSpacing) {
                    helperInsertButton("0")
                    helperInsertButton("1")
                    helperInsertButton("2")
                    helperInsertButton("3")
                    helperInsertButton("4")
					
					helperInsertButton("+")
					helperInsertButton("_")
					helperInsertButton("/")
					helperInsertButton("*")
					helperInsertButton("kp")
                }
				//
				//----------------------------------------
				//
                HStack(spacing: buttonSpacing) {
					helperInsertButton("5")
					helperInsertButton("6")
					helperInsertButton("7")
					helperInsertButton("8")
					helperInsertButton("9")

					helperInsertButton(":")

					helperInsertButton(systemImage: "triangle.fill", rotationDegrees: 0, insertedText: "UP:")
					helperInsertButton(systemImage: "triangle.fill", rotationDegrees: 180, insertedText: "DOWN:")
					helperInsertButton(systemImage: "triangle.fill", rotationDegrees: -90, insertedText: "LEFT:")
					helperInsertButton(systemImage: "triangle.fill", rotationDegrees: 90, insertedText: "RIGHT:")
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
        .onAppear {
            syncDraftsFromCombinedText()
        }
        .onChange(of: editingSlotText) {
            let currentCombinedText = composeEditingText(action: actionDraft, text: rightDraft)
            if editingSlotText != currentCombinedText {
                syncDraftsFromCombinedText()
            }
        }
        .onChange(of: actionDraft) {
            syncCombinedTextFromDrafts()
        }
        .onChange(of: rightDraft) {
            syncCombinedTextFromDrafts()
        }
    }

    private func helperInsertButton(_ text: String) -> some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            activeInputController.insertText(text)
            activeInputController.focus()
            focusBinding.wrappedValue = true
        } label: {
            Text(text)
                .foregroundStyle(.white)
                .frame(width: helperButtonWidth, height: 44)
                .background(Color.black)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white, lineWidth: 2)
                }
                .clipShape(.rect(cornerRadius: 12))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func helperInsertButton(systemImage: String, rotationDegrees: Double, insertedText: String) -> some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            activeInputController.insertText(insertedText)
            activeInputController.focus()
            focusBinding.wrappedValue = true
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .rotationEffect(.degrees(rotationDegrees))
                .foregroundStyle(.white)
                .frame(width: helperButtonWidth, height: 44)
                .background(Color.black)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white, lineWidth: 2)
                }
                .clipShape(.rect(cornerRadius: 12))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func helperBackspaceButton() -> some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            guard !editingSlotText.isEmpty else {
                activeInputController.focus()
                focusBinding.wrappedValue = true
                return
            }

            activeInputController.deleteBackward()
            activeInputController.focus()
            focusBinding.wrappedValue = true
        } label: {
            Image(systemName: "delete.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: helperButtonWidth, height: 44)
                .background(Color(red: 0.0, green: 0.2, blue: 0.45))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white, lineWidth: 2)
                }
                .clipShape(.rect(cornerRadius: 12))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var actionTextBinding: Binding<String> {
        $actionDraft
    }

    private var rightTextBinding: Binding<String> {
        $rightDraft
    }

    private var splitEditingText: (action: String, text: String) {
        let components = editingSlotText.components(separatedBy: "::")

        guard components.count > 1 else {
            return (editingSlotText, "")
        }

        let action = components.first ?? ""
        let text = components.dropFirst().joined(separator: "::")
        return (action, text)
    }

    private func composeEditingText(action: String, text: String) -> String {
        if text.isEmpty {
            return action
        }

        return "\(action)::\(text)"
    }

    private func syncDraftsFromCombinedText() {
        let splitText = splitEditingText
        if actionDraft != splitText.action {
            actionDraft = splitText.action
        }
        if rightDraft != splitText.text {
            rightDraft = splitText.text
        }
    }

    private func syncCombinedTextFromDrafts() {
        let combinedText = composeEditingText(action: actionDraft, text: rightDraft)
        if editingSlotText != combinedText {
            editingSlotText = combinedText
        }
    }

    private var clearActionButton: some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            actionTextBinding.wrappedValue = ""
            activeEditorField = .action
            actionInputController.focus()
            focusBinding.wrappedValue = true
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 35, height: 35)
                .background(Color(red: 0.42, green: 0.12, blue: 0.12))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
    }

    private var clearRightButton: some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            rightTextBinding.wrappedValue = ""
            activeEditorField = .text
            rightInputController.focus()
            focusBinding.wrappedValue = true
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 35, height: 35)
                .background(Color(red: 0.42, green: 0.12, blue: 0.12))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
    }

    private var activeInputController: SlotEditorInputController {
        switch activeEditorField {
        case .action:
            return actionInputController
        case .text:
            return rightInputController
        }
    }
}

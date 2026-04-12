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
    private let rightColumnButtonWidth: CGFloat = 90
	
	// MARK: - BM:🟦 SF symbols list
	
    private let sfSymbolNames = [
        "folder", "trash", "magnifyingglass", "gearshape", "house",
        "lightbulb.max.fill", "speaker.wave.2", "star", "heart", "bell",
		
        "paperclip", "link", "paperplane", "doc", "calendar",
        "camera", "photo", "tray", "sun.max.fill", "chart.bar.fill"
    ]
	
	// MARK: - BM:🟪 color keycodes
    private let colorKeyCodes: [(code: String, color: Color)] = [
        ("l", .black),
        ("w", .white),
		("b", .blue),
		("g", .green),
		("o", .orange),
		("r", .red),
		("c", .cyan),
		("u", .purple),
		("y", .yellow),
		("a", .gray)
    ]

    var body: some View {
        GeometryReader { geometry in
            let helperRowWidth = (helperButtonWidth * 10) + (buttonSpacing * 10) + rightColumnButtonWidth
            let totalEditorWidth = geometry.size.width - 24
            let sidePanelWidth = max(0, (totalEditorWidth - helperRowWidth - (buttonSpacing * 2)) / 2)
            let symbolButtonWidth = max(36, min(helperButtonWidth, (sidePanelWidth - buttonSpacing) / 2))
            let topRowWidth = max(0, min(geometry.size.width - 24, helperRowWidth))

            HStack(spacing: buttonSpacing) {
                sfSymbolPanel(symbolNames: leftSymbolNames, buttonWidth: symbolButtonWidth)

                VStack(spacing: buttonSpacing) {
                    HStack(spacing: buttonSpacing) {
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
                            .frame(minWidth: helperButtonWidth * 2.5, maxWidth: .infinity, minHeight: 44)

                            SlotEditorTextField(
                                text: rightTextBinding,
                                inputController: rightInputController,
                                placeholder: "text",
                                joinPosition: .right,
                                onBeginEditing: { activeEditorField = .text }
                            ) {
                                onCommit()
                            }
                            .frame(minWidth: helperButtonWidth * 2.5, maxWidth: .infinity, minHeight: 44)
                        }
                        .frame(maxWidth: .infinity)

                        clearRightButton
                    }
                    .frame(width: topRowWidth)

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

                        Button("cancel") {
                            ButtonClickFeedback.playIfEnabled()
                            onCancel()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(width: 90)
                        .frame(minHeight: 44)
                        .background(Color.gray.opacity(0.45))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
                        }
                        .clipShape(.rect(cornerRadius: 12))
                    }

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

                        Button("test") {
                            ButtonClickFeedback.playIfEnabled()
                            onTest()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(width: 90)
                        .frame(minHeight: 44)
                        .background(Color(red: 0.0, green: 0.5, blue: 0.0))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(red: 0.0, green: 0.5, blue: 0.0), lineWidth: 1.5)
                        }
                        .clipShape(.rect(cornerRadius: 12))
                    }

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

                        Button("del btn") {
                            ButtonClickFeedback.playIfEnabled()
                            actionDraft = ""
                            rightDraft = ""
                            editingSlotText = ""
                            onCommit()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .frame(width: rightColumnButtonWidth, height: 44)
                        .background(Color(red: 0.6, green: 0, blue: 0))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.red, lineWidth: 1.5)
                        }
                        .clipShape(.rect(cornerRadius: 12))
                    }

                    HStack(spacing: buttonSpacing) {
                        ForEach(colorKeyCodes, id: \.code) { colorKey in
                            colorInsertButton(
                                code: colorKey.code,
                                background: colorKey.color
                            )
                        }

                        Button("save") {
                            ButtonClickFeedback.playIfEnabled()
                            onCommit()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(width: 90)
                        .frame(minHeight: 44)
                        .background(Color.blue)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.blue, lineWidth: 1.5)
                        }
                        .clipShape(.rect(cornerRadius: 12))
                    }
                }

                sfSymbolPanel(symbolNames: rightSymbolNames, buttonWidth: symbolButtonWidth)
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
        .frame(height: 242)
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

    private func colorInsertButton(code: String, background: Color) -> some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            rightDraft = prefixedRightText(with: code)
            activeEditorField = .text
            rightInputController.focus()
            focusBinding.wrappedValue = true
        } label: {
            RoundedRectangle(cornerRadius: 12)
                .fill(background)
                .frame(width: helperButtonWidth, height: 44)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(1), lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sfSymbolPanel(symbolNames: [String], buttonWidth: CGFloat) -> some View {
        VStack(spacing: buttonSpacing) {
            ForEach(0..<5, id: \.self) { row in
                HStack(spacing: buttonSpacing) {
                    ForEach(0..<2, id: \.self) { column in
                        let symbolIndex = (row * 2) + column
                        if symbolIndex < symbolNames.count {
                            sfSymbolInsertButton(symbolNames[symbolIndex], width: buttonWidth)
                        }
                    }
                }
            }
        }
    }

    private func sfSymbolInsertButton(_ symbolName: String, width: CGFloat) -> some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            rightDraft = insertingRightTextPreservingColorPrefix(symbolName)
            activeEditorField = .text
            rightInputController.focus()
            focusBinding.wrappedValue = true
        } label: {
            Image(systemName: symbolName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.yellow)
                .frame(width: width, height: 44)
                .background(Color.black)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
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

    private func prefixedRightText(with code: String) -> String {
        let trimmedRightDraft = rightDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmedRightDraft.components(separatedBy: ":")

        if let firstComponent = components.first,
           firstComponent.count == 1,
           let existingCode = firstComponent.lowercased().first,
           "lwbgorpucya".contains(existingCode) {
            let remainingText = components.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
            return remainingText.isEmpty ? "\(code):" : "\(code):\(remainingText)"
        }

        return trimmedRightDraft.isEmpty ? "\(code):" : "\(code):\(trimmedRightDraft)"
    }

    private func insertingRightTextPreservingColorPrefix(_ symbolName: String) -> String {
        let trimmedRightDraft = rightDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmedRightDraft.components(separatedBy: ":")
        let insertedText = "\(symbolName):"

        if let firstComponent = components.first,
           firstComponent.count == 1,
           let existingCode = firstComponent.lowercased().first,
           "lwbgorpucya".contains(existingCode) {
            let trailingComponents = Array(components.dropFirst())
            let remainingComponents = droppingLeadingEditorSymbol(from: trailingComponents)
            let remainingText = remainingComponents.joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
            return remainingText.isEmpty ? "\(existingCode):\(insertedText)" : "\(existingCode):\(insertedText)\(remainingText)"
        }

        let remainingComponents = droppingLeadingEditorSymbol(from: components)
        let remainingText = remainingComponents.joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
        return remainingText.isEmpty ? insertedText : "\(insertedText)\(remainingText)"
    }

    private func droppingLeadingEditorSymbol(from components: [String]) -> [String] {
        guard let firstComponent = components.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              sfSymbolNames.contains(firstComponent) else {
            return components
        }

        return Array(components.dropFirst())
    }

    private var leftSymbolNames: [String] {
        Array(sfSymbolNames.prefix(10))
    }

    private var rightSymbolNames: [String] {
        Array(sfSymbolNames.suffix(10))
    }

    private var clearActionButton: some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            actionTextBinding.wrappedValue = ""
            activeEditorField = .action
            actionInputController.focus()
            focusBinding.wrappedValue = true
        } label: {
				Text("del")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: helperButtonWidth, height: 44)
					.background(
						RoundedRectangle(cornerRadius: 12)
							.fill(Color(red: 0.42, green: 0.12, blue: 0.12))
					)
			}
        .buttonStyle(.plain)
    }

    private var clearRightButton: some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            rightTextBinding.wrappedValue = ""
            activeEditorField = .text
            rightInputController.focus()
            focusBinding.wrappedValue = true
        } label: {
					Text("del")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
					.frame(width: rightColumnButtonWidth, height: 44)
					.background(
						RoundedRectangle(cornerRadius: 12)
							.fill(Color(red: 0.42, green: 0.12, blue: 0.12))
					)
        }
        .buttonStyle(.plain)
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

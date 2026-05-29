import SwiftUI

struct MainScreenSlotEditorOverlay: View {
    private enum ActiveEditorField {
        case action
        case text
    }

    @Binding var editingSlotText: String
    let editingSlotIndex: Int?
    let gridDimensions: GridDimensions
    let focusBinding: FocusState<Bool>.Binding
    let buttonSpacing: CGFloat
    let helperButtonWidth: CGFloat
    let onCancel: () -> Void
    let onCommit: () -> Void
    let onSave: () -> Void
    let onTest: () -> Void
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onVisibilityChange: (Bool) -> Void
    let onSelectPreviousButton: () -> Void
    let onSelectNextButton: () -> Void
    @State private var actionInputController = SlotEditorInputController()
    @State private var rightInputController = SlotEditorInputController()
    @State private var activeEditorField: ActiveEditorField = .action
    @State private var actionDraft = ""
    @State private var rightDraft = ""
    @State private var isHiddenInNormalMode = false
    @AppStorage("slotEditorClipboardAction") private var clipboardActionDraft = ""
    @AppStorage("slotEditorClipboardRight") private var clipboardRightDraft = ""
    private let rightColumnButtonWidth: CGFloat = 90
    private let slotPositionFontSize: CGFloat = 25
    private let orderedModifierPrefixes = ["ctl:", "op:", "sh:", "cm:"]
    private let actionFieldOnlyInsertions = ["SP:"]
    private let displayModifierPrefixes = ["⌃", "⌥", "⇧", "⌘"]
    private let supportedColorCodes = "lwbgorpucya12345"
		
	// MARK: - BM:🟦 SF symbols list
	
    private let visibilityToggleSymbolToken = "__visibility_toggle__"
    private let previousButtonSelectionSymbolToken = "__previous_button_selection__"
    private let nextButtonSelectionSymbolToken = "__next_button_selection__"
    private let visibleEyeSymbolName = "eye"
    private let hiddenEyeSymbolName = "eye.slash"
  
	private let leftSymbolNames = [
        "square.and.arrow.up.on.square.fill", "square.and.arrow.down.on.square.fill", "folder", "__visibility_toggle__", "magnifyingglass",
        "lightbulb.max.fill", "speaker.wave.2", "star", "heart", "bell"
    ]
    private let rightSymbolNames = [
        "__previous_button_selection__", "__next_button_selection__", "paperplane", "doc", "calendar", "camera",
        "photo", "tray", "sun.max.fill", "link"
    ]
	
    // MARK: - BM:🟪 color keycodes
    private let colorKeyCodes: [(code: String?, label: String?, color: Color)] = [
        ("l", "clr\ncol", Color(white: 0.22)),
        ("w", nil, Color.brown),
        ("b", nil, .blue),
        ("g", nil, .green),
        ("o", nil, .orange),
        ("r", nil, .red),
        ("c", nil, .cyan),
        ("u", nil, .purple),
        ("y", nil, .yellow),
        ("a", nil, Color(red: 0.25, green: 0.25, blue: 0.25)),// was .gray
        ("1", nil, Color(red: 0.20, green: 0.22, blue: 0.30)),
        ("2", nil, Color(red: 0.14, green: 0.30, blue: 0.25)),
        ("3", nil, Color(red: 0.38, green: 0.14, blue: 0.24)),
        ("4", nil, Color(red: 0.23, green: 0.26, blue: 0.08)),
        ("5", nil, Color(red: 0.14, green: 0.16, blue: 0.38))
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
                            .frame(minWidth: helperButtonWidth * 2.5, maxWidth: .infinity)
                            .frame(height: 44)

                            SlotEditorTextField(
                                text: rightTextBinding,
                                inputController: rightInputController,
                                placeholder: "text",
                                joinPosition: .right,
                                onBeginEditing: { activeEditorField = .text }
                            ) {
                                onCommit()
                            }
                            .frame(minWidth: helperButtonWidth * 2.5, maxWidth: .infinity)
                            .frame(height: 44)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)

                        clearRightButton
                    }
                    .frame(width: topRowWidth, height: 44)

                    HStack(spacing: buttonSpacing) {
                        helperInsertButton("F")
                        helperInsertButton(label: "⌃", insertedText: "ctl:")
                        helperInsertButton(label: "⌥", insertedText: "op:")
                        helperInsertButton(label: "⇧", insertedText: "sh:")
                        helperInsertButton(label: "⌘", insertedText: "cm:")

                        helperInsertButton("ESC:")
                        helperInsertButton("RET:")
                        helperInsertButton("BS:")
                        helperInsertButton("CA:")
                        helperBackspaceButton()

                        deleteButtonPlaceholder
                    }

                    HStack(alignment: .top, spacing: buttonSpacing) {
                        VStack(spacing: buttonSpacing) {
                            ForEach(Array(colorRows.enumerated()), id: \.offset) { row in
                                HStack(spacing: buttonSpacing) {
                                    ForEach(Array(row.element.enumerated()), id: \.offset) { colorKey in
                                        colorInsertButton(
                                            code: colorKey.element.code,
                                            label: colorKey.element.label,
                                            background: colorKey.element.color
                                        )
                                    }
                                }
                            }
                        }

                        VStack(spacing: buttonSpacing) {
                            HStack(spacing: buttonSpacing) {
                                helperInsertButton("SP:")
                                helperInsertButton("TAB:")
								helperInsertButton("MA:")
							//	helperInsertButton(label: "\\", insertedText: "\\")
                                helperInsertButton("*")
                                forwardDeleteButton
                                testButton
                            }

                            HStack(spacing: buttonSpacing) {
                                helperInsertButton(":")
                                helperInsertButton(systemImage: "triangle.fill", rotationDegrees: 0, insertedText: "UP:")
                                helperInsertButton(systemImage: "triangle.fill", rotationDegrees: 180, insertedText: "DOWN:")
                                helperInsertButton(systemImage: "triangle.fill", rotationDegrees: -90, insertedText: "LEFT:")
                                helperInsertButton(systemImage: "triangle.fill", rotationDegrees: 90, insertedText: "RIGHT:")
                                saveButton
                            }

                            HStack(spacing: buttonSpacing) {
								helperInsertButton("spk ")
								helperInsertButton("snd ")
                                helperInsertButton("timer ")
                                helperInsertButton("app ")
                                newlineInsertButton
                                closeButton
                            }
                        }
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
        .frame(height: 320)
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
        .onChange(of: isHiddenInNormalMode) {
            syncCombinedTextFromDrafts()
        }
    }

    private func helperInsertButton(_ text: String) -> some View {
        helperInsertButton(label: text, insertedText: text)
    }

    private func helperInsertButton(label: String, insertedText: String) -> some View {
        let insertsIntoActionField = orderedModifierPrefixes.contains(insertedText) || actionFieldOnlyInsertions.contains(insertedText)
        let isDisabled = insertsIntoActionField && activeEditorField == .text

        return Button {
            guard !isDisabled else {
                return
            }
            ButtonClickFeedback.playIfEnabled()
            if orderedModifierPrefixes.contains(insertedText) {
                actionDraft = toggledModifierPrefix(insertedText)
                activeEditorField = .action
                DispatchQueue.main.async {
                    actionInputController.focusAtStart()
                }
            } else if actionFieldOnlyInsertions.contains(insertedText) {
                actionInputController.insertText(insertedText)
                activeEditorField = .action
                actionInputController.focus()
            } else {
                activeInputController.insertText(insertedText)
                activeInputController.focus()
            }
            focusBinding.wrappedValue = true
        } label: {
            Text(label)
                .foregroundStyle(isDisabled ? Color.gray : .white)
                .multilineTextAlignment(.center)
                .frame(width: helperButtonWidth, height: 44)
                .background(Color.black)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isDisabled ? Color.gray : Color.white, lineWidth: 2)
                }
                .clipShape(.rect(cornerRadius: 12))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var colorRows: [[(code: String?, label: String?, color: Color)]] {
        stride(from: 0, to: colorKeyCodes.count, by: 5).map { startIndex in
            Array(colorKeyCodes[startIndex..<min(startIndex + 5, colorKeyCodes.count)])
        }
    }

    private func toggledModifierPrefix(_ modifier: String) -> String {
        var remainingText = actionDraft
        var enabledModifiers: Set<String> = []

        var didStripModifier = true
        while didStripModifier {
            didStripModifier = false
            for knownModifier in orderedModifierPrefixes {
                if remainingText.hasPrefix(knownModifier) {
                    enabledModifiers.insert(knownModifier)
                    remainingText.removeFirst(knownModifier.count)
                    didStripModifier = true
                    break
                }
            }
        }

        if enabledModifiers.contains(modifier) {
            enabledModifiers.remove(modifier)
        } else {
            enabledModifiers.insert(modifier)
        }

        let orderedPrefix = orderedModifierPrefixes
            .filter { enabledModifiers.contains($0) }
            .joined()

        return orderedPrefix + remainingText
    }

    private func displayedActionDraft(_ rawActionText: String) -> String {
        var remainingText = rawActionText
        var displayPrefix = ""

        var didStripModifier = true
        while didStripModifier {
            didStripModifier = false
            for (index, knownModifier) in orderedModifierPrefixes.enumerated() {
                if remainingText.hasPrefix(knownModifier) {
                    displayPrefix += displayModifierPrefixes[index]
                    remainingText.removeFirst(knownModifier.count)
                    didStripModifier = true
                    break
                }
            }
        }

        return displayPrefix + remainingText
    }

    private func normalizedActionDraftFromDisplayedText(_ displayedActionText: String) -> String {
        var remainingText = displayedActionText
        var rawPrefix = ""

        var didStripModifier = true
        while didStripModifier {
            didStripModifier = false
            for (index, displayModifier) in displayModifierPrefixes.enumerated() {
                if remainingText.hasPrefix(displayModifier) {
                    rawPrefix += orderedModifierPrefixes[index]
                    remainingText.removeFirst(displayModifier.count)
                    didStripModifier = true
                    break
                }
            }
        }

        return rawPrefix + remainingText
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

    private var newlineInsertButton: some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            switch activeEditorField {
            case .action:
                actionInputController.insertText("\\\\n")
            case .text:
                rightInputController.insertText("\\n")
            }
            activeInputController.focus()
            focusBinding.wrappedValue = true
        } label: {
            Text("NL")
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(width: helperButtonWidth, height: 44)
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

    private var forwardDeleteButton: some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            activeInputController.deleteForward()
            activeInputController.focus()
            focusBinding.wrappedValue = true
        } label: {
            Image(systemName: "delete.left")
                .font(.system(size: 16, weight: .semibold))
                .rotationEffect(.degrees(180))
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

    private var testButton: some View {
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

    private var deleteButtonPlaceholder: some View {
        slotPositionLabel
            .frame(width: rightColumnButtonWidth, height: 44)
            .background(Color.black)
            .clipShape(.rect(cornerRadius: 12))
    }

    @ViewBuilder
    private var slotPositionLabel: some View {
        if let editingSlotIndex, gridDimensions.columns > 0 {
            let column = (editingSlotIndex % gridDimensions.columns) + 1
            let row = (editingSlotIndex / gridDimensions.columns) + 1

            HStack(spacing: 0) {
				Text("\(column)")
					.foregroundStyle(.green)
                Text(" : ")
                    .foregroundStyle(.white)
				Text("\(row)")
					.foregroundStyle(.red)
            }
            .font(.system(size: slotPositionFontSize, weight: .semibold))
        }
    }

    private var saveButton: some View {
        Button("save") {
            ButtonClickFeedback.playIfEnabled()
            onSave()
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

    private var closeButton: some View {
        Button("close") {
            ButtonClickFeedback.playIfEnabled()
            onSave()
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

    private func colorInsertButton(code: String?, label: String?, background: Color) -> some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            rightDraft = code.map(prefixedRightText(with:)) ?? rightTextWithoutColorPrefix()
            activeEditorField = .text
            rightInputController.focus()
            focusBinding.wrappedValue = true
        } label: {
            RoundedRectangle(cornerRadius: 12)
                .fill(background)
                .frame(width: helperButtonWidth, height: 44)
                .overlay {
                    if let label {
                        Text(label)
                            .font(.system(size: 14, weight: .bold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                    }
                }
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
        if symbolName == visibilityToggleSymbolToken {
            return AnyView(visibilityToggleButton(width: width))
        }

        if symbolName == previousButtonSelectionSymbolToken {
            return AnyView(slotSelectionButton(width: width, systemImage: "arrow.left", action: onSelectPreviousButton))
        }

        if symbolName == nextButtonSelectionSymbolToken {
            return AnyView(slotSelectionButton(width: width, systemImage: "arrow.right", action: onSelectNextButton))
        }

        if symbolName == "square.and.arrow.up.on.square.fill" {
            return AnyView(copySlotButton(width: width))
        }

        if symbolName == "square.and.arrow.down.on.square.fill" {
            return AnyView(pasteSlotButton(width: width))
        }

        return AnyView(
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
        )
    }

    private func visibilityToggleButton(width: CGFloat) -> some View {
            Button {
                ButtonClickFeedback.playIfEnabled()
                isHiddenInNormalMode.toggle()
                onVisibilityChange(isHiddenInNormalMode)
                activeEditorField = .text
                rightInputController.focus()
                focusBinding.wrappedValue = true
        } label: {
            Image(systemName: currentVisibilitySymbolName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.green)
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

    private func slotSelectionButton(width: CGFloat, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.green)
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

    private func copySlotButton(width: CGFloat) -> some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            clipboardActionDraft = actionDraft
            clipboardRightDraft = rightDraft
            onCopy()
        } label: {
            Image(systemName: "square.and.arrow.up.on.square.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.green)
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

    private func pasteSlotButton(width: CGFloat) -> some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            actionDraft = clipboardActionDraft
            rightDraft = clipboardRightDraft
            activeEditorField = .action
            actionInputController.focus()
            focusBinding.wrappedValue = true
            onPaste()
        } label: {
            Image(systemName: "square.and.arrow.down.on.square.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.green)
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
        Binding(
            get: {
                displayedActionDraft(actionDraft)
            },
            set: { newValue in
                actionDraft = normalizedActionDraftFromDisplayedText(newValue)
            }
        )
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
        let textComponents = components
            .dropFirst()
            .filter { $0 != hiddenButtonMetadataToken }
        let text = textComponents.joined(separator: "::")
        return (action, text)
    }

    private func composeEditingText(action: String, text: String) -> String {
        let actionContainsOnlyInlineSpaces = !action.isEmpty &&
            action.allSatisfy { $0.isWhitespace && !$0.isNewline }
        let normalizedAction = actionContainsOnlyInlineSpaces
            ? action
            : action.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseText: String

        if normalizedAction.isEmpty && trimmedText.isEmpty {
            baseText = ""
        } else if normalizedAction.isEmpty {
            baseText = "::\(trimmedText)"
        } else if trimmedText.isEmpty {
            baseText = normalizedAction
        } else {
            baseText = "\(normalizedAction)::\(trimmedText)"
        }

        guard isHiddenInNormalMode, !baseText.isEmpty else {
            return baseText
        }

        return baseText.contains("::")
            ? "\(baseText)::\(hiddenButtonMetadataToken)"
            : "\(baseText)::\(hiddenButtonMetadataToken)"
    }

    private func syncDraftsFromCombinedText() {
        isHiddenInNormalMode = editingSlotText.components(separatedBy: "::").contains(hiddenButtonMetadataToken)
        let splitText = splitEditingText
        if actionDraft != splitText.action {
            actionDraft = splitText.action
        }
        let normalizedRightText = normalizedRightDraft(splitText.text)
        if rightDraft != normalizedRightText {
            rightDraft = normalizedRightText
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
           supportedColorCodes.contains(existingCode) {
            let remainingText = components.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
            return remainingText.isEmpty ? "\(code):" : "\(code):\(remainingText)"
        }

        return trimmedRightDraft.isEmpty ? "\(code):" : "\(code):\(trimmedRightDraft)"
    }

    private func rightTextWithoutColorPrefix() -> String {
        let trimmedRightDraft = rightDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmedRightDraft.components(separatedBy: ":")

        if let firstComponent = components.first,
           firstComponent.count == 1,
           let existingCode = firstComponent.lowercased().first,
           supportedColorCodes.contains(existingCode) {
            return components.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmedRightDraft
    }

    private func insertingRightTextPreservingColorPrefix(_ symbolName: String) -> String {
        let trimmedRightDraft = rightDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmedRightDraft.components(separatedBy: ":")
        let insertedText = "\(symbolName):"

        if let firstComponent = components.first,
           firstComponent.count == 1,
           let existingCode = firstComponent.lowercased().first,
           supportedColorCodes.contains(existingCode) {
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
              removableLeadingEditorSymbolNames.contains(firstComponent) else {
            return components
        }

        return Array(components.dropFirst())
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

    private var removableLeadingEditorSymbolNames: Set<String> {
        Set(leftSymbolNames + rightSymbolNames + [visibleEyeSymbolName, hiddenEyeSymbolName])
    }

    private var currentVisibilitySymbolName: String {
        isHiddenInNormalMode ? hiddenEyeSymbolName : visibleEyeSymbolName
    }

    private func normalizedRightDraft(_ text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmedText == visibleEyeSymbolName || trimmedText == hiddenEyeSymbolName) ? "" : text
    }
}

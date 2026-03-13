import SwiftUI

private enum ModifierCommand: String, CaseIterable, Identifiable {
    case command = "cm"
    case option = "op"
    case shift = "sh"
    case control = "ct"
    case off = "off"

    var id: Self { self }

    var title: String {
        switch self {
        case .command:
            return "cmd"
        case .option:
            return "option"
        case .shift:
            return "shift"
        case .control:
            return "control"
        case .off:
            return "off"
        }
    }
}

private enum FunctionKeyDisplayMode: CaseIterable {
    case left
    case right
    case both

    func next() -> Self {
        switch self {
        case .left:
            return .right
        case .right:
            return .both
        case .both:
            return .left
        }
    }

    var title: String {
        switch self {
        case .left:
            return "Left"
        case .right:
            return "Right"
        case .both:
            return "Both"
        }
    }
}

struct MainScreen: View {
    @ObservedObject var ble: BLEKeyboardManager
    @State private var activeModifiers: Set<ModifierCommand> = []
    @State private var displayMode: FunctionKeyDisplayMode = .left
    @State private var isEditingDocumentName = false
    @State private var documentNameDraft = ""
    @State private var renameAlertMessage: String?
    @FocusState private var isDocumentNameFieldFocused: Bool
    let functionKeys: [FunctionKeyEntry]
    let documentFiles: [URL]
    let selectedDocumentName: String
    let selectedDocumentDisplayName: String
    let refreshDocumentFiles: () -> Void
    let loadFunctionKeys: (URL) -> Void
    let renameDocument: (String) -> String?
    let deleteDocument: (URL) -> Void
    let duplicateDocument: (URL) -> Void
    let canDeleteDocuments: Bool

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 5)

    var body: some View {
        VStack(spacing: 20) {
            GeometryReader { geometry in
                let buttonHeight = geometry.size.height / 4

                LazyVGrid(columns: gridColumns, spacing: 0) {
                    ForEach(Array(functionKeys.enumerated()), id: \.offset) { _, entry in
                        Button {
                            let sendText = entry.sendText.trimmingCharacters(in: .whitespacesAndNewlines)

                            guard !sendText.isEmpty else {
                                return
                            }

                            ble.sendLine(sendText)
                        } label: {
                            Text(buttonTitle(for: entry))
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, minHeight: buttonHeight, maxHeight: buttonHeight)
                                .background(Color.black)
                                .overlay {
                                    Rectangle()
                                        .stroke(Color.white, lineWidth: 1)
                                }
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            modifierButtons
        }
        .padding(.horizontal, 2)
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                documentTitle
            }

            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("settings >") {
                    SettingsScreen(
                        ble: ble,
                        documentFiles: documentFiles,
                        selectedDocumentName: selectedDocumentName,
                        refreshDocumentFiles: refreshDocumentFiles,
                        loadFunctionKeys: loadFunctionKeys,
                        deleteDocument: deleteDocument,
                        duplicateDocument: duplicateDocument,
                        canDeleteDocuments: canDeleteDocuments
                    )
                }
            }
        }
        .task(id: isEditingDocumentName) {
            guard isEditingDocumentName else { return }
            isDocumentNameFieldFocused = true
        }
        .alert("Rename File", isPresented: renameAlertIsPresented) {
            Button("OK", role: .cancel) {
                renameAlertMessage = nil
            }
        } message: {
            Text(renameAlertMessage ?? "")
        }
    }

    private var documentTitle: some View {
        Group {
            if isEditingDocumentName {
                TextField("Filename", text: $documentNameDraft)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .focused($isDocumentNameFieldFocused)
                    .onSubmit(commitDocumentRename)
            } else {
                Button {
                    documentNameDraft = selectedDocumentDisplayName
                    isEditingDocumentName = true
                } label: {
                    Text(selectedDocumentDisplayName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var modifierButtons: some View {
        VStack(alignment: .leading, spacing: 2) {

            HStack(spacing: 10) {
                Text("Modifiers")
                    .font(.headline)
                ForEach(ModifierCommand.allCases) { modifier in
                    let isSelected = modifier == .off ? activeModifiers.isEmpty : activeModifiers.contains(modifier)

                    Button {
                        toggleModifier(modifier)
                    } label: {
                        Text(modifier.title)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .background(isSelected ? Color.blue : Color.gray.opacity(0.18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.blue : Color.gray.opacity(0.4), lineWidth: 2)
                    }
                    .clipShape(.rect(cornerRadius: 12))
                }

                Button {
                    displayMode = displayMode.next()
                } label: {
                    displayModeLabel
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(Color.blue)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue, lineWidth: 2)
                }
                .clipShape(.rect(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(.rect(cornerRadius: 16))
    }

    private func toggleModifier(_ modifier: ModifierCommand) {
        if modifier == .off {
            activeModifiers.removeAll()
            ble.sendLine(modifier.rawValue)
            return
        }

        if activeModifiers.contains(modifier) {
            activeModifiers.remove(modifier)
        } else {
            activeModifiers.insert(modifier)
            ble.sendLine(modifier.rawValue)
        }
    }

    private var displayModeLabel: some View {
        VStack(spacing: 2) {
            Text(displayMode.title)

            if displayMode == .both {
                Text("L / R")
                    .font(.caption)
            }
        }
    }

    private func buttonTitle(for entry: FunctionKeyEntry) -> String {
        guard entry.displayUsesAlternateText else {
            return entry.rawLine
        }

        switch displayMode {
        case .left:
            return entry.sendText
        case .right:
            return entry.alternateDisplayText ?? entry.rawLine
        case .both:
            return "\(entry.sendText)\n\(entry.alternateDisplayText ?? entry.rawLine)"
        }
    }

    private var renameAlertIsPresented: Binding<Bool> {
        Binding(
            get: { renameAlertMessage != nil },
            set: { newValue in
                if !newValue {
                    renameAlertMessage = nil
                }
            }
        )
    }

    private func commitDocumentRename() {
        let proposedName = documentNameDraft

        if let alertMessage = renameDocument(proposedName) {
            renameAlertMessage = alertMessage
            return
        }

        documentNameDraft = selectedDocumentDisplayName
        isEditingDocumentName = false
    }
}

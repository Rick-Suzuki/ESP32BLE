import SwiftUI

struct MainScreenToolbarContent: ToolbarContent {
    let isGridEditModeEnabled: Bool
    let editingSlotIndex: Int?
    let currentFileNumber: Int
    let totalFileCount: Int
    @Binding var isEditingDocumentName: Bool
    @Binding var documentNameDraft: String
    let selectedDocumentDisplayName: String
    let isDocumentNameFieldFocused: FocusState<Bool>.Binding
    let openKeyboardScreen: () -> Void
    let selectPreviousDocument: () -> Void
    let selectNextDocument: () -> Void
    let toggleGridEditMode: () -> Void
    let commitDocumentRename: () -> Void
    let openSettings: AnyView

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Keyboard") {
                ButtonClickFeedback.playIfEnabled()
                openKeyboardScreen()
            }
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(toolbarButtonBackgroundColor(normalBackground: isGridEditModeEnabled ? Color.gray.opacity(0.3) : Color.gray.opacity(0.45)))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(toolbarButtonBorderColor, lineWidth: 1.5)
            }
            .clipShape(.rect(cornerRadius: 12))
            .contentShape(.rect)
            .disabled(isGridEditModeEnabled || editingSlotIndex != nil)
            .opacity(isGridEditModeEnabled || editingSlotIndex != nil ? 0.45 : 1)
        }

        ToolbarItem(placement: .principal) {
            HStack(spacing: 20) {
                Button {
                    ButtonClickFeedback.playIfEnabled()
                    selectPreviousDocument()
                } label: {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 20))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 20, height: 20)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .disabled(currentFileNumber <= 1)

                Group {
                    if isEditingDocumentName {
                        TextField("Filename", text: $documentNameDraft)
                            .font(.title2.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.done)
                            .focused(isDocumentNameFieldFocused)
                            .onSubmit(commitDocumentRename)
                    } else {
                        Button {
                            ButtonClickFeedback.playIfEnabled()
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
                .frame(maxWidth: .infinity)

                Button {
                    ButtonClickFeedback.playIfEnabled()
                    selectNextDocument()
                } label: {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 20))
                        .rotationEffect(.degrees(90))
                        .frame(width: 20, height: 20)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .disabled(currentFileNumber >= totalFileCount)
            }
            .opacity(isGridEditModeEnabled || editingSlotIndex != nil ? 0.45 : 1)
            .allowsHitTesting(!(isGridEditModeEnabled || editingSlotIndex != nil))
        }

        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 12) {
                Button {
                    ButtonClickFeedback.playIfEnabled()
                    toggleGridEditMode()
                } label: {
                    Text(isGridEditModeEnabled ? "done" : "edit")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(minWidth: 84, minHeight: 44)
                        .background(toolbarButtonBackgroundColor(normalBackground: editModeButtonBackgroundColor))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(toolbarButtonBorderColor, lineWidth: 1.5)
                        }
                        .clipShape(.rect(cornerRadius: 12))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(editingSlotIndex != nil)
                .opacity(editingSlotIndex == nil ? 1 : 0.45)

                openSettings
                    .disabled(isGridEditModeEnabled || editingSlotIndex != nil)
                    .opacity(isGridEditModeEnabled || editingSlotIndex != nil ? 0.45 : 1)
            }
        }
    }

    private var editModeButtonBackgroundColor: Color {
        if editingSlotIndex != nil {
            return Color.gray.opacity(0.3)
        }
        return isGridEditModeEnabled ? Color.blue : Color.gray.opacity(0.45)
    }

    private var toolbarButtonBorderColor: Color {
        editingSlotIndex != nil ? Color.gray.opacity(0.35) : Color.gray.opacity(0.5)
    }

    private func toolbarButtonBackgroundColor(normalBackground: Color) -> Color {
        editingSlotIndex != nil ? Color.gray.opacity(0.3) : normalBackground
    }
}

import SwiftUI

struct MainScreenToolbarContent: ToolbarContent {
    private let inactiveToolbarBackgroundColor = Color(red: 0.22, green: 0.22, blue: 0.24)
    private let normalToolbarBackgroundColor = Color(red: 0.32, green: 0.32, blue: 0.34)
    private let inactiveToolbarBorderColor = Color(red: 0.30, green: 0.30, blue: 0.32)
    private let normalToolbarBorderColor = Color(red: 0.46, green: 0.46, blue: 0.48)
    private let inactiveToolbarForegroundColor = Color(red: 0.55, green: 0.55, blue: 0.57)
    let isGridEditModeEnabled: Bool
    let editingSlotIndex: Int?
    let currentFileNumber: Int
    let totalFileCount: Int
    @Binding var gridBackgroundOpacity: Double
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
            .background(toolbarButtonBackgroundColor(normalBackground: normalToolbarBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(toolbarButtonBorderColor, lineWidth: 1.5)
            }
            .clipShape(.rect(cornerRadius: 12))
            .contentShape(.rect)
            .disabled(isGridEditModeEnabled || editingSlotIndex != nil)
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
                .foregroundStyle(toolbarPrincipalForegroundColor)
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
                                .foregroundStyle(toolbarPrincipalForegroundColor)
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
                .foregroundStyle(toolbarPrincipalForegroundColor)
                .disabled(currentFileNumber >= totalFileCount)
            }
            .allowsHitTesting(!(isGridEditModeEnabled || editingSlotIndex != nil))
        }

        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 12) {
                Slider(value: $gridBackgroundOpacity, in: 0...1)
                    .tint(.white)
                    .frame(width: 126)

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

                openSettings
                    .disabled(isGridEditModeEnabled || editingSlotIndex != nil)
            }
        }
    }

    private var editModeButtonBackgroundColor: Color {
        if editingSlotIndex != nil {
            return inactiveToolbarBackgroundColor
        }
        return isGridEditModeEnabled ? Color.blue : normalToolbarBackgroundColor
    }

    private var toolbarButtonBorderColor: Color {
        editingSlotIndex != nil ? inactiveToolbarBorderColor : normalToolbarBorderColor
    }

    private func toolbarButtonBackgroundColor(normalBackground: Color) -> Color {
        editingSlotIndex != nil ? inactiveToolbarBackgroundColor : normalBackground
    }

    private var toolbarPrincipalForegroundColor: Color {
        isGridEditModeEnabled || editingSlotIndex != nil ? inactiveToolbarForegroundColor : .white
    }
}

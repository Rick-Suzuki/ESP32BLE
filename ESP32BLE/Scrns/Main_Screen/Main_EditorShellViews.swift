import SwiftUI

struct ESP001MiniDiagnosticPanels {
    let command: AnyView
    let color: AnyView
    let button: AnyView
    let sf: AnyView
}

struct ESP001MiniDiagnosticEditorShell: View {
    let width: CGFloat
    let height: CGFloat
    let commandWidth: CGFloat
    let colorWidth: CGFloat
    let buttonWidth: CGFloat
    let sfWidth: CGFloat
    let debugEditorGeometry: Bool
    let commandPanel: AnyView
    let colorPanel: AnyView
    let buttonPanel: AnyView
    let sfPanel: AnyView

    var body: some View {
        HStack(spacing: 0) {
            commandPanel
                .frame(width: commandWidth, height: height)
                .editorGeometryProbe(.leftPanel, isEnabled: debugEditorGeometry)

            colorPanel
                .frame(width: colorWidth, height: height)
                .editorGeometryProbe(.commandPanel, isEnabled: debugEditorGeometry)

            buttonPanel
                .frame(width: buttonWidth, height: height)
                .editorGeometryProbe(.buttonPanel, isEnabled: debugEditorGeometry)

            sfPanel
                .frame(width: sfWidth, height: height)
                .editorGeometryProbe(.sfPanel, isEnabled: debugEditorGeometry)
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .background(Color.black)
        .editorGeometryProbe(.smartView, isEnabled: debugEditorGeometry)
        .ignoresSafeArea(.keyboard)
    }
}

struct ESP001ExperimentalIPhoneEditorShell: View {
    let editorGroupWidth: CGFloat
    let outerWidth: CGFloat
    let outerHeight: CGFloat?
    let outerMaxWidth: CGFloat?
    let outerMaxHeight: CGFloat?
    let panelHeight: CGFloat?
    let panelMaxHeight: CGFloat?
    let editorGroupAlignment: Alignment
    let commandWidth: CGFloat
    let commandEditorWidth: CGFloat
    let buttonWidth: CGFloat
    let debugEditorGeometry: Bool
    let commandPanel: AnyView
    let commandEditorPanel: AnyView
    let buttonPanel: AnyView

    var body: some View {
        HStack(spacing: 0) {
            commandPanel
                .frame(width: commandWidth, height: panelHeight)
                .frame(maxHeight: panelMaxHeight)
                .editorGeometryProbe(.leftPanel, isEnabled: debugEditorGeometry)

            commandEditorPanel
                .frame(width: commandEditorWidth, height: panelHeight)
                .frame(maxHeight: panelMaxHeight)
                .editorGeometryProbe(.commandPanel, isEnabled: debugEditorGeometry)

            buttonPanel
                .frame(width: buttonWidth, height: panelHeight)
                .frame(maxHeight: panelMaxHeight)
                .editorGeometryProbe(.buttonPanel, isEnabled: debugEditorGeometry)
        }
        .editorGeometryProbe(.hStack, isEnabled: debugEditorGeometry)
        .frame(width: editorGroupWidth, height: outerHeight, alignment: .topLeading)
        .frame(width: outerWidth, height: outerHeight, alignment: editorGroupAlignment)
        .frame(maxWidth: outerMaxWidth, maxHeight: outerMaxHeight, alignment: .topLeading)
        .editorGeometryProbe(.smartView, isEnabled: debugEditorGeometry)
        .ignoresSafeArea(.keyboard)
    }
}

struct ESP001MiniDiagnosticEmptyPanel: View {
    let label: String?

    var body: some View {
        ZStack {
            Color.black

            if let label {
                Text(label)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

struct IPadSmartCommandKeypad<
    PlaceholderButton: View,
    EscapeCodeToggleButton: View,
    DismissKeyboardButton: View,
    CommandColonButton: View,
    ModifierButton: View
>: View {
    let topPlaceholderSymbols: [String]
    let keyCellWidth: CGFloat?
    let debugEditorGeometry: Bool
    let placeholderButton: (String) -> PlaceholderButton
    let escapeCodeToggleButton: () -> EscapeCodeToggleButton
    let dismissKeyboardButton: () -> DismissKeyboardButton
    let commandColonButton: () -> CommandColonButton
    let modifierButton: (String, String, String) -> ModifierButton

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(topPlaceholderSymbols.prefix(4)), id: \.self) { systemName in
                    placeholderButton(systemName)
                        .frame(width: keyCellWidth)
                }
            }
            .frame(height: 44)

            HStack(spacing: 0) {
                ForEach(Array(topPlaceholderSymbols.dropFirst(4).prefix(4)), id: \.self) { systemName in
                    placeholderButton(systemName)
                        .frame(width: keyCellWidth)
                }
            }
            .frame(height: 44)

            HStack(spacing: 0) {
                placeholderButton("delete.right.fill")
                    .frame(width: keyCellWidth)
                escapeCodeToggleButton()
                    .frame(width: keyCellWidth)
                dismissKeyboardButton()
                    .frame(width: keyCellWidth)
                commandColonButton()
                    .frame(width: keyCellWidth)
            }
            .frame(height: 44)

            HStack(spacing: 0) {
                modifierButton("control", "Control", "⌃")
                    .frame(width: keyCellWidth)
                modifierButton("option", "Option", "⌥")
                    .frame(width: keyCellWidth)
                modifierButton("shift", "Shift", "⇧")
                    .frame(width: keyCellWidth)
                modifierButton("command", "Command", "⌘")
                    .frame(width: keyCellWidth)
            }
            .frame(height: 44)
        }
        .editorGeometryProbe(.leftTop, isEnabled: debugEditorGeometry)
    }
}

struct IPadSmartButtonPanel<
    BrightnessSliderColumn: View,
    Preview: View,
    ClearPreviewBackground: View,
    LowerEditingArea: View,
    PanelBorder: View
>: View {
    let debugEditorGeometry: Bool
    @ViewBuilder let brightnessSliderColumn: () -> BrightnessSliderColumn
    @ViewBuilder let preview: () -> Preview
    @ViewBuilder let clearPreviewBackground: () -> ClearPreviewBackground
    @ViewBuilder let lowerEditingArea: () -> LowerEditingArea
    @ViewBuilder let panelBorder: () -> PanelBorder
    
	// MARK: - BM:🔆 IPAD, slider column height (bad name)
	private let previewButtonHeight: CGFloat = 121
   
	
	// MARK: - BM:🔆 IPAD, Top padding
	private let upperTopPadding: CGFloat = -2
	
	// MARK: - BM:🔆 IPAD, bottom padding
//	private let upperBottomPadding: CGFloat = 0
	private let upperBottomPadding: CGFloat = 5
	
	// MARK: - BM:🔆 IPAD, L+R padding
	private let previewLeadingPadding: CGFloat = 0
	private let previewTrailingPadding: CGFloat = 8
	
    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 0) {
                brightnessSliderColumn()
                    .frame(height: previewButtonHeight)
                    .padding(.top, 0)
                    .padding(.bottom, upperBottomPadding)
                    .editorGeometryProbe(.slider, isEnabled: debugEditorGeometry)

                VStack(spacing: 8) {
                    preview()
                }
                .frame(maxWidth: .infinity)
				.padding(.leading, previewLeadingPadding)
				.padding(.trailing, previewTrailingPadding)
				.padding(.top, upperTopPadding)
                .padding(.bottom, upperBottomPadding)
                .editorGeometryProbe(.previewFootprint, isEnabled: debugEditorGeometry)
            }
            .background {
                clearPreviewBackground()
            }
            .editorGeometryProbe(.rightPreviewArea, isEnabled: debugEditorGeometry)

            lowerEditingArea()
        }
        .frame(maxWidth: nil, maxHeight: nil, alignment: .top)
        .background(Color.black)
        .overlay {
            panelBorder()
        }
        .clipped()
    }
}

struct IPadSmartSFPanel<SymbolGrid: View, Controls: View>: View {
    @ViewBuilder let symbolGrid: () -> SymbolGrid
    @ViewBuilder let controls: () -> Controls

    var body: some View {
        VStack(spacing: 0) {
            symbolGrid()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            controls()
        }
        .background(Color.black)
        .overlay {
            Rectangle()
                .stroke(Color.white, lineWidth: 1)
        }
    }
}

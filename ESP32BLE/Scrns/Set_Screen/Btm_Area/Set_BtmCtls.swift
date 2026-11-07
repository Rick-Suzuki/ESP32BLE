import SwiftUI

struct SettingsBottomControlsSection: View {
    @ObservedObject var ble: BLEKeyboardManager
    @ObservedObject var macConnection: MacConnectionManager
    @Binding var outputModeRawValue: String
    @Binding var keepScreenAwake: Bool
    @Binding var isButtonClickEnabled: Bool
    @Binding var isBluetoothMonitorMode: Bool
    @Binding var isStatusBarVisible: Bool
    @Binding var opacitySliderValue: Double
    @Binding var documentEditorFontSize: CGFloat
    let imageControlButtons: AnyView
    let isImageControlsActive: Bool
    let isDocumentEditorControlsActive: Bool
    let onImageOpacityEditingChanged: (Bool) -> Void
    let isIPhoneImageEditorPresented: Bool
    let iPhoneEditorLeadingInset: CGFloat
    let iPhoneImageEditor: AnyView
    let isIPhoneSoundPlayerPresented: Bool
    let iPhoneSoundPlayer: AnyView
    let onHideIPhonePreview: () -> Void
    let presentDeleteAllDataConfirmation: () -> Void
    let presentHelp: () -> Void

    var body: some View {
        SettingsAvailableDevicesPanel(
            ble: ble,
            macConnection: macConnection,
            outputModeRawValue: $outputModeRawValue,
            keepScreenAwake: $keepScreenAwake,
            isButtonClickEnabled: $isButtonClickEnabled,
            isBluetoothMonitorMode: $isBluetoothMonitorMode,
            isStatusBarVisible: $isStatusBarVisible,
            opacitySliderValue: $opacitySliderValue,
            documentEditorFontSize: $documentEditorFontSize,
            imageControlButtons: imageControlButtons,
            isImageControlsActive: isImageControlsActive,
            isDocumentEditorControlsActive: isDocumentEditorControlsActive,
            onImageOpacityEditingChanged: onImageOpacityEditingChanged,
            isIPhoneImageEditorPresented: isIPhoneImageEditorPresented,
            iPhoneEditorLeadingInset: iPhoneEditorLeadingInset,
            iPhoneImageEditor: iPhoneImageEditor,
            isIPhoneSoundPlayerPresented: isIPhoneSoundPlayerPresented,
            iPhoneSoundPlayer: iPhoneSoundPlayer,
            onHideIPhonePreview: onHideIPhonePreview,
            presentDeleteAllDataConfirmation: presentDeleteAllDataConfirmation,
            presentHelp: presentHelp
        )
    }
}

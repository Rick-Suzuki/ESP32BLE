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
    let imageControlButtons: AnyView

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
            imageControlButtons: imageControlButtons
        )
    }
}

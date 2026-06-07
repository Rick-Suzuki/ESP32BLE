import SwiftUI

struct SettingsBottomControlsSection: View {
    @ObservedObject var ble: BLEKeyboardManager
    @Binding var keepScreenAwake: Bool
    @Binding var isButtonClickEnabled: Bool
    @Binding var isBluetoothMonitorMode: Bool
    @Binding var opacitySliderValue: Double
    let imageControlButtons: AnyView

    var body: some View {
        SettingsAvailableDevicesPanel(
            ble: ble,
            keepScreenAwake: $keepScreenAwake,
            isButtonClickEnabled: $isButtonClickEnabled,
            isBluetoothMonitorMode: $isBluetoothMonitorMode,
            opacitySliderValue: $opacitySliderValue,
            imageControlButtons: imageControlButtons
        )
    }
}

import SwiftUI

struct SettingsBottomControlsSection: View {
    @ObservedObject var ble: BLEKeyboardManager
    @Binding var keepScreenAwake: Bool
    @Binding var isButtonClickEnabled: Bool
    let imageControlButtons: AnyView

    var body: some View {
        SettingsAvailableDevicesPanel(
            ble: ble,
            keepScreenAwake: $keepScreenAwake,
            isButtonClickEnabled: $isButtonClickEnabled,
            imageControlButtons: imageControlButtons
        )
    }
}

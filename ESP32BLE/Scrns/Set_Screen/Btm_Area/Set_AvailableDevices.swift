import SwiftUI

struct SettingsAvailableDevicesPanel: View {
    @ObservedObject var ble: BLEKeyboardManager
    @Binding var keepScreenAwake: Bool
    @Binding var isButtonClickEnabled: Bool
    @Binding var opacitySliderValue: Double
    let imageControlButtons: AnyView

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    if isPad {
                        Text("ESP32")
                            .font(.headline)
                    }

                    Button {
                        ButtonClickFeedback.playIfEnabled()
                        ble.disconnect()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(ble.isConnected ? .white : Color.gray)
                            .frame(width: 30, height: 30)
                            .background(ble.isConnected ? Color.red : Color.gray.opacity(0.45))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!ble.isConnected)
                }

                if ble.discoveredDevices.isEmpty {
                    Text("No ESP32 devices found yet")
                        .foregroundStyle(.secondary)
                }

                ForEach(ble.discoveredDevices) { device in
                    Button {
                        ButtonClickFeedback.playIfEnabled()
                        ble.selectedPeripheralID = device.id
                        if !ble.isConnected {
                            ble.connectToSelectedDevice()
                        }
                    } label: {
                        HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    VStack {
                                        Text(settingsDeviceName(for: device))
                                            .font(settingsDeviceFont)
                                        .foregroundStyle(settingsDeviceNameColor(for: device))
                                    }
                                }
                            Spacer()

                            if showsDeviceCheckmark(for: device) {
                                Image(systemName: "checkmark.circle.fill")
									.foregroundStyle(.green)

                            }
                        }
                        .padding(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(settingsDeviceBackgroundColor(for: device))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(ble.isConnected && ble.selectedPeripheralID != device.id)
                    .opacity(ble.isConnected && ble.selectedPeripheralID != device.id ? 0.45 : 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 12) {
                imageControlButtons
                settingsPlaceholderSlider(title: "opacity: 0.5", value: $opacitySliderValue)

                HStack(spacing: 18) {
                    sleepWakeButton
                    buttonClickToggleButton
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var sleepWakeButton: some View {
        Button(ble.isConnected && keepScreenAwake ? "wake" : "sleep") {
            guard ble.isConnected else { return }
            ButtonClickFeedback.playIfEnabled()
            keepScreenAwake.toggle()
        }
        .buttonStyle(.plain)
        .font(.headline)
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 16)
        .frame(width: settingsActionButtonWidth, height: settingsActionButtonHeight-10)
        .background(sleepWakeButtonBackgroundColor)
        .clipShape(.rect(cornerRadius: 18))
        .disabled(!ble.isConnected)
    }

    private func settingsDeviceName(for device: BLEDiscoveredDevice) -> String {
        if isPad {
            return device.displayName
        }

        return device.compactDisplayName
    }

    private func settingsDeviceNameColor(for device: BLEDiscoveredDevice) -> Color {
        if !isPad && ble.isConnected && ble.selectedPeripheralID == device.id {
            return .green
        }

        return .white
    }

    private var settingsDeviceFont: Font {
        isPad ? .body : .system(size: settingsDeviceFontSize)
    }

    private var settingsDeviceFontSize: CGFloat {
        13
    }

    private func showsDeviceCheckmark(for device: BLEDiscoveredDevice) -> Bool {
        isPad && ble.selectedPeripheralID == device.id
    }

    private func settingsDeviceBackgroundColor(for device: BLEDiscoveredDevice) -> Color {
        if isPad && ble.selectedPeripheralID == device.id {
            return .blue.opacity(0.15)
        }

        return .clear
    }

    private var sleepWakeButtonBackgroundColor: Color {
        guard ble.isConnected else {
            return Color.gray.opacity(0.5)
        }

        if keepScreenAwake {
            return Color(red: 0.45, green: 0.0, blue: 0.0)
        }

        return Color(red: 0.0, green: 0.25, blue: 0.55)
    }

    private var buttonClickToggleButton: some View {
        Button(isButtonClickEnabled ? (isPad ? "btn click" : "click") : "btn off") {
            let willEnableButtonClicks = !isButtonClickEnabled
            isButtonClickEnabled = willEnableButtonClicks

            if willEnableButtonClicks {
                ButtonClickFeedback.playIfEnabled()
            }
        }
        .buttonStyle(.plain)
        .font(.headline)
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 16)
        .frame(width: settingsActionButtonWidth, height: settingsActionButtonHeight-10)
        .background(isButtonClickEnabled ? Color.blue.opacity(0.5) : Color.gray.opacity(0.5))
        .clipShape(.rect(cornerRadius: 18))
    }

    private var settingsActionButtonWidth: CGFloat {
        isPad ? 92 : 92
    }

    private var settingsActionButtonHeight: CGFloat {
        isPad ? 48 : 36
    }

    private func settingsPlaceholderSlider(title: String, value: Binding<Double>) -> some View {
        VStack(spacing: 8) {
            Slider(value: value, in: 0...1)
                .tint(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

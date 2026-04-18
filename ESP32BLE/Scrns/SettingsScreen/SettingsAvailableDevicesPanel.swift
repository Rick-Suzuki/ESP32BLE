import SwiftUI

struct SettingsAvailableDevicesPanel: View {
    @ObservedObject var ble: BLEKeyboardManager
    @Binding var keepScreenAwake: Bool
    @Binding var isButtonClickEnabled: Bool
    let imageControlButtons: AnyView

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text("ESP32")
                        .font(.headline)

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
                                    Text(device.displayName)
                                        .font(.body)
                                }
                            }
                            Spacer()

                            if ble.selectedPeripheralID == device.id {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                        .padding(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(ble.selectedPeripheralID == device.id ? .blue.opacity(0.15) : .clear)
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
        .padding(.vertical, 10)
        .background(sleepWakeButtonBackgroundColor)
        .clipShape(.rect(cornerRadius: 18))
        .disabled(!ble.isConnected)
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
        Button(isButtonClickEnabled ? "btn click" : "btn off") {
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
        .padding(.vertical, 10)
        .background(isButtonClickEnabled ? Color.blue.opacity(0.5) : Color.gray.opacity(0.5))
        .clipShape(.rect(cornerRadius: 18))
    }
}

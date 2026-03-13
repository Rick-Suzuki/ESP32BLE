import SwiftUI

struct SettingsScreen: View {
    @ObservedObject var ble: BLEKeyboardManager
    let documentFiles: [URL]
    let selectedDocumentName: String
    let refreshDocumentFiles: () -> Void
    let loadFunctionKeys: (URL) -> Void
    @State private var keyboardSliderOneValue = 0.0
    @State private var keyboardSliderTwoValue = 0.0

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 20) {
                ScrollView {
                    VStack(spacing: 20) {
                        availableDevicesSection
                        keyboardSettingsSection
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }

                documentTableSection
                    .frame(width: max(220, geometry.size.width * 0.28))
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                BackButton()
            }
        }
        .task {
            refreshDocumentFiles()
        }
    }

    private var availableDevicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Available ESP32 Devices")
                .font(.headline)

            if ble.discoveredDevices.isEmpty {
                Text("No ESP32 devices found yet")
                    .foregroundStyle(.secondary)
            }

            ForEach(ble.discoveredDevices) { device in
                Button {
                    ble.selectedPeripheralID = device.id
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.displayName)
                                .font(.body)

                            Text("RSSI: \(device.rssi)   UUID: \(device.id.uuidString)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if ble.selectedPeripheralID == device.id {
                            Image(systemName: "checkmark.circle.fill")
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(ble.selectedPeripheralID == device.id ? .blue.opacity(0.15) : .clear)
                    )
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                Button("Scan") {
                    ble.startScan()
                }
                .buttonStyle(.borderedProminent)

                Button("Connect Selected") {
                    ble.connectToSelectedDevice()
                }
                .buttonStyle(.borderedProminent)
                .disabled(ble.selectedPeripheralID == nil)

                Button("Disconnect") {
                    ble.disconnect()
                }
                .buttonStyle(.bordered)
                .disabled(!ble.isConnected)
            }

            Text("Connected Device ID: \(ble.connectedDeviceID)")
            Text("Status: \(ble.connectionText)")
            Text("BT State: \(ble.bluetoothStateText)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial)
        .clipShape(.rect(cornerRadius: 16))
    }

    private var keyboardSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keyboard Settings")
                .font(.headline)

            HStack(spacing: 12) {
                Button("MacOS ks") {
                    keyboardSliderOneValue = 0
                    keyboardSliderTwoValue = 0
                }
                .buttonStyle(.borderedProminent)

                Button("PS5 ks") {
                    keyboardSliderOneValue = 20
                    keyboardSliderTwoValue = 20
                }
                .buttonStyle(.borderedProminent)
				
            }

			Spacer().frame(height:10)
            customKeyboardTimingSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial)
        .clipShape(.rect(cornerRadius: 16))
    }

    private var documentTableSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Documents")
                .font(.headline)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(documentFiles, id: \.path) { fileURL in
                        let isSelected = selectedDocumentName == fileURL.lastPathComponent

                        Button {
                            loadFunctionKeys(fileURL)
                        } label: {
                            HStack {
                                Text(fileURL.lastPathComponent)
                                    .foregroundStyle(.white)
                                    .lineLimit(1)

                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .background(Color.black)
                            .overlay {
                                Rectangle()
                                    .stroke(isSelected ? Color.white : Color.gray, lineWidth: 1)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding()
        .background(.thinMaterial)
        .clipShape(.rect(cornerRadius: 16))
    }

    private var customKeyboardTimingSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("custom kb timing")
                .font(.headline)

            HStack(alignment: .center, spacing: 12) {
                VStack(spacing: 10) {
                    sliderRow(
                        title: "on",
                        value: $keyboardSliderOneValue,
                        range: 0...1000
                    )

                    sliderRow(
                        title: "off",
                        value: $keyboardSliderTwoValue,
                        range: 0...3000
                    )
                }
                .frame(maxWidth: 520, alignment: .leading)

                Button("set & test") {
                    ble.sendLine("set:\(Int(keyboardSliderOneValue)):\(Int(keyboardSliderTwoValue))")
                    ble.sendString("Hello World!")
                }
                .buttonStyle(.borderedProminent)

                Spacer(minLength: 0)
            }
        }
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(width: 28, alignment: .leading)

            Button {
                value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1)
            } label: {
                Image(systemName: "triangle.fill")
					.font(.system(size: 30))
					.rotationEffect(.degrees(-90))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .disabled(value.wrappedValue <= range.lowerBound)

            VStack(spacing: -5) {
                Text("\(Int(value.wrappedValue)) ms")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)

                Slider(value: value, in: range, step: 10)
                    .tint(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Button {
                value.wrappedValue = min(range.upperBound, value.wrappedValue + 1)
            } label: {
                Image(systemName: "triangle.fill")
					.font(.system(size: 30))
					.rotationEffect(.degrees(90))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .disabled(value.wrappedValue >= range.upperBound)
        }
    }
}

private struct BackButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("main") {
            dismiss()
        }
    }
}

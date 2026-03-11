import SwiftUI

struct SettingsScreen: View {
    @ObservedObject var ble: BLEKeyboardManager
    let documentFiles: [URL]
    let selectedDocumentName: String
    let refreshDocumentFiles: () -> Void
    let loadFunctionKeys: (URL) -> Void

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 20) {
                ScrollView {
                    VStack(spacing: 20) {
                        availableDevicesSection
                        ConnectionStatusSection(ble: ble)
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
            }

            Text("Connected Device ID: \(ble.connectedDeviceID)")
            Text("Status: \(ble.connectionText)")
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
                    ble.sendLine("set:0:0")
                }
                .buttonStyle(.borderedProminent)

                Button("PS5 ks") {
                    ble.sendLine("set:20:70")
                }
                .buttonStyle(.borderedProminent)
            }
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
}

private struct BackButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("main") {
            dismiss()
        }
    }
}

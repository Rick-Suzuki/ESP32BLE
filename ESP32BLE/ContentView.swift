import SwiftUI

struct ContentView: View {
	@StateObject private var ble = BLEKeyboardManager()
	@State private var customText = "good race"
	
	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(spacing: 20) {
					
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
					.clipShape(RoundedRectangle(cornerRadius: 16))
					
					ConnectionStatusSection(ble: ble)
					//CommandButtonsSection(ble: ble, customText: $customText)
					PhraseButtonsSection(ble: ble)
					TestArea(ble: ble)
				}
				.padding()
			}
			.navigationTitle("ESP32 PS5 Keyboard")
			
			.onAppear {
				print("ContentView onAppear")
				Task { @MainActor in
					await Task.yield()
					await Task.yield()
					print("UI likely interactive")
				}
			}
			.onChange(of: ble.connectionText) { _, newValue in
				print("connectionText = \(newValue)")
			}
		}
	}
}

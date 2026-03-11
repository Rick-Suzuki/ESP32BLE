import SwiftUI

struct ContentView: View {
	@StateObject private var ble = BLEKeyboardManager()
	@State private var customText = "good race"
	
	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(spacing: 20) {
					
					VStack(alignment: .leading, spacing: 12) {
						Text("Target Device")
							.font(.headline)
						
						Picker("ESP32", selection: $ble.selectedDeviceID) {
							Text("A").tag("A")
							Text("B").tag("B")
						}
						.pickerStyle(.segmented)
						
						Button("Scan and Connect") {
							ble.startScan()
						}
						.buttonStyle(.borderedProminent)
						
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

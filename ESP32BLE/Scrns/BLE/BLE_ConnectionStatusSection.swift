//
//  ConnectionStatusSection.swift
//  ESP32_ble
//
//  Created by Eric Beresford on 2026/03/07.
//

import SwiftUI
import Combine

struct ConnectionStatusSection: View {
	@ObservedObject var ble: BLEKeyboardManager
	
	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("Connection")
				.font(.headline)
			
			LabeledContent("Bluetooth", value: ble.bluetoothStateText)
			LabeledContent("Status", value: ble.connectionText)
			LabeledContent("Last Message", value: ble.lastMessage)
			
			HStack(spacing: 12) {
				Button("Scan / Reconnect") {
					ble.startScan()
				}
				.buttonStyle(.borderedProminent)
				
				Button("Disconnect") {
					ble.disconnect()
				}
				.buttonStyle(.bordered)
				.disabled(!ble.isConnected)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding()
		.background(.thinMaterial)
		.clipShape(RoundedRectangle(cornerRadius: 16))
	}
}

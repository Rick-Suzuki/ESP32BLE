//
//  CommandButtonsSection.swift
//  ESP32_ble
//
//  Created by Eric Beresford on 2026/03/07.
//

import SwiftUI
import Combine

struct CommandButtonsSection: View {
	@ObservedObject var ble: BLEKeyboardManager
	@Binding var customText: String
	
	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("Keyboard Commands")
				.font(.headline)
			
			TextField("Type text to send", text: $customText)
				.textFieldStyle(.roundedBorder)
			
			VStack(spacing: 12) {
				Button("1. Press Any Key") {
					ble.pressAnyKey()
				}
				.buttonStyle(.borderedProminent)
				.frame(maxWidth: .infinity)
				
				Button("2. Send String") {
					ble.sendString(customText)
				}
				.buttonStyle(.borderedProminent)
				.frame(maxWidth: .infinity)
				
				Button("3. Press Right Arrow") {
					ble.pressRightArrow()
				}
				.buttonStyle(.borderedProminent)
				.frame(maxWidth: .infinity)
				
				Button("4. Press Enter") {
					ble.pressEnter()
				}
				.buttonStyle(.borderedProminent)
				.frame(maxWidth: .infinity)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding()
		.background(.thinMaterial)
		.clipShape(RoundedRectangle(cornerRadius: 16))
	}
}

//
//  BLEDiscoveredDevice.swift
//  ESP32_ble
//
//  Created by Eric Beresford on 2026/03/09.
//

import Foundation
import CoreBluetooth

struct BLEDiscoveredDevice: Identifiable, Equatable {
	let id: UUID
	let peripheral: CBPeripheral
	let name: String
	let rssi: Int
	var deviceID: String?
	var lastSeenAt: Date
	
	var displayName: String {
		let baseName = trimmedBaseName
		if let deviceID, !deviceID.isEmpty {
			return "\(baseName) [\(deviceID)]"
		}
		return baseName
	}

	var compactDisplayName: String {
		String(trimmedBaseName.prefix(3))
	}

	private var trimmedBaseName: String {
		let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmedName.isEmpty ? "Unnamed ESP32" : trimmedName
	}
		
	static func == (lhs: BLEDiscoveredDevice, rhs: BLEDiscoveredDevice) -> Bool {
		lhs.id == rhs.id
	}
}

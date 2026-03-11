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
	
	var displayName: String {
		let baseName = name.isEmpty ? "Unnamed ESP32" : name
		if let deviceID, !deviceID.isEmpty {
			return "\(baseName) [\(deviceID)]"
		}
		return baseName
	}
	
	static func == (lhs: BLEDiscoveredDevice, rhs: BLEDiscoveredDevice) -> Bool {
		lhs.id == rhs.id
	}
}

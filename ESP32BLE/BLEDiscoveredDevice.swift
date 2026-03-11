//
//  BLEDiscoveredDevice.swift
//  ESP32_ble
//
//  Created by Eric Beresford on 2026/03/09.
//

import Foundation
import CoreBluetooth

struct BLEDiscoveredDevice: Identifiable {
	let id: UUID
	let peripheral: CBPeripheral
	let name: String
	let rssi: Int
	var deviceID: String?
}

//
//  BLEKeyboardManager.swift
//  ESP32_ble
//
//  Created by Eric Beresford on 2026/03/07.
//

import Foundation
import CoreBluetooth
import Combine
//
// BLE manager for talking to the ESP32.
//
// Responsibilities:
// 1. start Bluetooth
// 2. scan for the ESP32 peripheral
// 3. connect to it
// 4. discover the UART-style BLE service/characteristics
// 5. write text commands to the RX characteristic
//
final class BLEKeyboardManager: NSObject, ObservableObject {
	//
	// Published state for the SwiftUI interface.
	//
	@Published var bluetoothStateText = "Starting Bluetooth..."
	@Published var connectionText = "Not connected"
	@Published var isConnected = false
	@Published var lastMessage = "None"
	
	//
	// BLE central manager.
	//
	private var centralManager: CBCentralManager!
	
	//
	// The ESP32 peripheral once found.
	//
	private var esp32Peripheral: CBPeripheral?
	
	//
	// RX characteristic on the ESP32.
	// This is the one we WRITE TO.
	//
	private var rxCharacteristic: CBCharacteristic?
	
	//
	// UART-style UUIDs matching your ESP32 sketch.
	//
	private let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
	private let rxUUID      = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
	private let txUUID      = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
	
	
	@Published var discoveredDevices: [BLEDiscoveredDevice] = []
	@Published var selectedDeviceID: String = "A"
	@Published var connectedDeviceID: String = "Unknown"
	
	private let deviceIDUUID = CBUUID(string: "6E400004-B5A3-F393-E0A9-E50E24DCCA9E")
	private var idCharacteristic: CBCharacteristic?
	//
	// Friendly device name from the ESP32 sketch.
	//
//	private let targetName = "PS5 Keyboard Bridge"
	
	override init() {
		super.init()
		
		//
		// Create the central manager.
		// Delegate callbacks will tell us when Bluetooth is ready.
		//
		centralManager = CBCentralManager(delegate: self, queue: .main)
	}
	
	func clearDiscoveredDevices() {
		discoveredDevices.removeAll()
	}
	
	//-------------------------------------------------------------------------
	// MARK: - Public actions
	//-------------------------------------------------------------------------
	
	func startScan() {
		guard centralManager.state == .poweredOn else {
			bluetoothStateText = "Bluetooth is not powered on"
			return
		}
		
		connectionText = "Scanning..."
		clearDiscoveredDevices()
		
		centralManager.scanForPeripherals(
			withServices: [serviceUUID],
			options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
		)
	}
	
	
	func disconnect() {
		guard let esp32Peripheral else { return }
		centralManager.cancelPeripheralConnection(esp32Peripheral)
	}
	
	//
	// Send one full line to the ESP32.
	// The ESP32 code expects a newline at the end.
	//
	func sendLine(_ line: String) {
		guard let peripheral = esp32Peripheral,
			  let rxCharacteristic else {
			lastMessage = "Not connected / RX not ready"
			return
		}
		
		let fullLine = line + "\n"
		guard let data = fullLine.data(using: .utf8) else {
			lastMessage = "Failed to encode text"
			return
		}
		
		//
		// The characteristic is intended for write / write without response.
		// We use .withoutResponse for a simple fast command channel.
		//
		peripheral.writeValue(data, for: rxCharacteristic, type: .withoutResponse)
		lastMessage = "Sent: \(line)"
	}
	
	func connectToSelectedDevice() {
		guard let match = discoveredDevices.first(where: { $0.deviceID == selectedDeviceID }) else {
			connectionText = "No ESP32 with device ID \(selectedDeviceID) found"
			return
		}
		
		connectionText = "Connecting to device \(selectedDeviceID)..."
		esp32Peripheral = match.peripheral
		esp32Peripheral?.delegate = self
		centralManager.stopScan()
		centralManager.connect(match.peripheral, options: nil)
	}
	//
	// Command helpers for the UI.
	//
	func pressAnyKey() {
		//
		// The ESP32 types literal text unless it sees a bracket command.
		// Sending "z" is a simple "press any key" test.
		//
		sendLine("z")
	}
	
	func sendString(_ text: String) {
		sendLine("sa")
		sendLine("\(text)")
	}
	
	func pressRightArrow() {
		sendLine("r")
	}
	
	func pressEnter() {
		sendLine("ret")
	}
}

//-----------------------------------------------------------------------------
// MARK: - CBCentralManagerDelegate
//-----------------------------------------------------------------------------
extension BLEKeyboardManager: CBCentralManagerDelegate {
	func centralManagerDidUpdateState(_ central: CBCentralManager) {
		switch central.state {
			case .unknown:
				bluetoothStateText = "Bluetooth state: unknown"
			case .resetting:
				bluetoothStateText = "Bluetooth state: resetting"
			case .unsupported:
				bluetoothStateText = "Bluetooth not supported on this device"
			case .unauthorized:
				bluetoothStateText = "Bluetooth not authorized"
			case .poweredOff:
				bluetoothStateText = "Bluetooth is off"
			case .poweredOn:
				bluetoothStateText = "Bluetooth is on"
				startScan()
			@unknown default:
				bluetoothStateText = "Bluetooth state: unknown future case"
		}
	}
	
	func centralManager(
		_ central: CBCentralManager,
		didDiscover peripheral: CBPeripheral,
		advertisementData: [String : Any],
		rssi RSSI: NSNumber
	) {
		let name = peripheral.name ?? "Unknown"
		let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "nil"
		
		print("** Found peripheral: \(name)")
		print("** Found advertised local name: \(advertisedName)")
		print("** Peripheral identifier: \(peripheral.identifier.uuidString)")
		
		if !discoveredDevices.contains(where: { $0.id == peripheral.identifier }) {
			let item = BLEDiscoveredDevice(
				id: peripheral.identifier,
				peripheral: peripheral,
				name: name,
				rssi: RSSI.intValue,
				deviceID: nil
			)
			discoveredDevices.append(item)
			
			//
			// Connect briefly to read its device ID.
			//
			peripheral.delegate = self
			centralManager.connect(peripheral, options: nil)
		}
	}
	
	func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
		connectionText = "Connected, discovering services..."
		isConnected = true
		
		peripheral.discoverServices([serviceUUID])
	}
	
	func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
		if esp32Peripheral?.identifier == peripheral.identifier {
			connectionText = "Disconnected"
			isConnected = false
			rxCharacteristic = nil
			idCharacteristic = nil
			connectedDeviceID = "Unknown"
		}
	}
	
	func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
		connectionText = "Failed to connect"
		isConnected = false
		startScan()
	}
}

//-----------------------------------------------------------------------------
// MARK: - CBPeripheralDelegate
//-----------------------------------------------------------------------------
extension BLEKeyboardManager: CBPeripheralDelegate {
	func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
		guard error == nil else {
			connectionText = "Service discovery failed"
			return
		}
		
		guard let services = peripheral.services else { return }
		
		for service in services where service.uuid == serviceUUID {
			peripheral.discoverCharacteristics([rxUUID, txUUID, deviceIDUUID], for: service)
		}
	}
	
	func peripheral(
		_ peripheral: CBPeripheral,
		didDiscoverCharacteristicsFor service: CBService,
		error: Error?
	) {
		guard error == nil else {
			connectionText = "Characteristic discovery failed"
			return
		}
		
		guard let characteristics = service.characteristics else { return }
		
		for characteristic in characteristics {
			if characteristic.uuid == rxUUID {
				rxCharacteristic = characteristic
			}
			
			if characteristic.uuid == deviceIDUUID {
				idCharacteristic = characteristic
				peripheral.readValue(for: characteristic)
			}
		}
	}
	
	func peripheral(
		_ peripheral: CBPeripheral,
		didUpdateValueFor characteristic: CBCharacteristic,
		error: Error?
	) {
		guard error == nil else { return }
		
		if characteristic.uuid == deviceIDUUID,
		   let data = characteristic.value,
		   let value = String(data: data, encoding: .utf8) {
			
			print("** Device ID read: \(value) for \(peripheral.identifier.uuidString)")
			
			if let index = discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
				discoveredDevices[index].deviceID = value
			}
			
			//
			// If this is the selected device, make it the active one.
			//
			if value == selectedDeviceID {
				esp32Peripheral = peripheral
				esp32Peripheral?.delegate = self
				connectedDeviceID = value
				connectionText = "Connected to device \(value)"
				
				if let chars = peripheral.services?
					.flatMap({ $0.characteristics ?? [] }),
				   let rx = chars.first(where: { $0.uuid == rxUUID }) {
					rxCharacteristic = rx
				}
			} else {
				//
				// Disconnect from non-selected devices after reading ID.
				//
				centralManager.cancelPeripheralConnection(peripheral)
			}
		}
	}
}

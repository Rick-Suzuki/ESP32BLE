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
    private enum StoredTimingKey {
        static let onMs = "keyboardTimingOnMs"
        static let offMs = "keyboardTimingOffMs"
    }
	//
	// Published state for the SwiftUI interface.
	//
	@Published var bluetoothStateText = "Starting Bluetooth..."
	@Published var connectionText = "Not connected"
	@Published var isConnected = false
	@Published var lastMessage = "None"
	
	@Published var discoveredDevices: [BLEDiscoveredDevice] = []
	@Published var selectedPeripheralID: UUID?
	@Published var connectedDeviceID: String = "Unknown"
	
	//
	// BLE central manager.
	//
	private var centralManager: CBCentralManager!
	
	//
	// The ESP32 peripheral currently connected for actual use.
	//
	private var esp32Peripheral: CBPeripheral?
	
	//
	// RX characteristic on the ESP32.
	// This is the one we WRITE TO.
	//
	private var rxCharacteristic: CBCharacteristic?
	private var idCharacteristic: CBCharacteristic?
	
	//
	// Track peripherals that are temporarily connected just to read device ID.
	//
	private var probePeripheralIDs: Set<UUID> = []
	
	//
	// UART-style UUIDs matching your ESP32 sketch.
	//
	private let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
	private let rxUUID      = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
	private let txUUID      = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
	private let deviceIDUUID = CBUUID(string: "6E400004-B5A3-F393-E0A9-E50E24DCCA9E")
	
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
		selectedPeripheralID = nil
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
		probePeripheralIDs.removeAll()
		
		centralManager.scanForPeripherals(
			withServices: [serviceUUID],
			options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
		)
	}
	
	func connectToSelectedDevice() {
		guard let selectedPeripheralID else {
			connectionText = "Select an ESP32 first"
			return
		}
		
		guard let match = discoveredDevices.first(where: { $0.id == selectedPeripheralID }) else {
			connectionText = "Selected ESP32 not found"
			return
		}
		
		connectionText = "Connecting to \(match.displayName)..."
		esp32Peripheral = match.peripheral
		esp32Peripheral?.delegate = self
		centralManager.stopScan()
		centralManager.connect(match.peripheral, options: nil)
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
		sendNormalizedKeyboardText(text)
	}

	func sendKeyboardTiming(onMs: Int, offMs: Int) {
		sendLine("set:\(onMs):\(offMs)")
	}
	
	func pressRightArrow() {
		sendLine("r")
	}
	
	func pressEnter() {
		sendLine("ret")
	}

	private func sendNormalizedKeyboardText(_ text: String) {
		let normalizedText = normalizedKeyboardText(text)
		var literalBuffer = ""
		literalBuffer.reserveCapacity(normalizedText.count)

		for character in normalizedText {
			if shouldSendAsStandaloneCharacter(character) {
				flushLiteralBuffer(&literalBuffer)
				sendLine(String(character))
			} else {
				literalBuffer.append(character)
			}
		}

		flushLiteralBuffer(&literalBuffer)
	}

	private func flushLiteralBuffer(_ literalBuffer: inout String) {
		guard !literalBuffer.isEmpty else {
			return
		}

		sendLine(literalBuffer)
		literalBuffer.removeAll(keepingCapacity: true)
	}

	private func normalizedKeyboardText(_ text: String) -> String {
		var normalizedText = ""
		normalizedText.reserveCapacity(text.count)

		for character in text {
			switch character {
			case "‘", "’":
				normalizedText.append("'")
			case "“", "”":
				normalizedText.append("\"")
			default:
				normalizedText.append(character)
			}
		}

		return normalizedText
	}

	private func shouldSendAsStandaloneCharacter(_ character: Character) -> Bool {
		!(
			character.isLetter ||
			character.isNumber ||
			character == " "
		)
	}
}

//-----------------------------------------------------------------------------
// MARK: - CBCentralManagerDelegate
//-----------------------------------------------------------------------------
extension BLEKeyboardManager: CBCentralManagerDelegate {
	func centralManagerDidUpdateState(_ central: CBCentralManager) {
		switch central.state {
			case .unknown:
				bluetoothStateText = "unknown"
			case .resetting:
				bluetoothStateText = "resetting"
			case .unsupported:
				bluetoothStateText = "not supported on this device"
			case .unauthorized:
				bluetoothStateText = "not authorized"
			case .poweredOff:
				bluetoothStateText = "off"
			case .poweredOn:
				bluetoothStateText = "on"
				startScan()
			@unknown default:
				bluetoothStateText = "unknown future case"
		}
	}
	
	func centralManager(
		_ central: CBCentralManager,
		didDiscover peripheral: CBPeripheral,
		advertisementData: [String : Any],
		rssi RSSI: NSNumber
	) {
		let name = peripheral.name ?? "Unknown ESP32"
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
			
			if selectedPeripheralID == nil {
				selectedPeripheralID = peripheral.identifier
			}
			
			//
			// Connect briefly to read its device ID.
			//
			probePeripheralIDs.insert(peripheral.identifier)
			peripheral.delegate = self
			centralManager.connect(peripheral, options: nil)
		}
	}
	
	func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
		let isProbe = probePeripheralIDs.contains(peripheral.identifier)
		
		if isProbe {
			print("** Probe-connected to \(peripheral.identifier.uuidString)")
		} else {
			connectionText = "Connected, discovering services..."
			isConnected = true
			esp32Peripheral = peripheral
		}
		
		peripheral.discoverServices([serviceUUID])
	}
	
	func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
		probePeripheralIDs.remove(peripheral.identifier)
		
		if esp32Peripheral?.identifier == peripheral.identifier {
			connectionText = "Disconnected"
			isConnected = false
			rxCharacteristic = nil
			idCharacteristic = nil
			connectedDeviceID = "Unknown"
			esp32Peripheral = nil
		}
	}
	
	func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
		probePeripheralIDs.remove(peripheral.identifier)
		
		if esp32Peripheral?.identifier == peripheral.identifier {
			connectionText = "Failed to connect"
			isConnected = false
		}
	}
}

//-----------------------------------------------------------------------------
// MARK: - CBPeripheralDelegate
//-----------------------------------------------------------------------------
extension BLEKeyboardManager: CBPeripheralDelegate {
	func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
		guard error == nil else {
			if esp32Peripheral?.identifier == peripheral.identifier {
				connectionText = "Service discovery failed"
			}
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
			if esp32Peripheral?.identifier == peripheral.identifier {
				connectionText = "Characteristic discovery failed"
			}
			return
		}
		
		guard let characteristics = service.characteristics else { return }
		
		for characteristic in characteristics {
			if peripheral.identifier == esp32Peripheral?.identifier, characteristic.uuid == rxUUID {
				rxCharacteristic = characteristic
			}
			
			if characteristic.uuid == deviceIDUUID {
				if peripheral.identifier == esp32Peripheral?.identifier {
					idCharacteristic = characteristic
				}
				peripheral.readValue(for: characteristic)
			}
		}
		
			if peripheral.identifier == esp32Peripheral?.identifier {
				connectionText = "Connected"
				sendStoredKeyboardTiming()
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
		   let value = String(data: data, encoding: .utf8)?
			.trimmingCharacters(in: .whitespacesAndNewlines) {
			
			print("** Device ID read: \(value) for \(peripheral.identifier.uuidString)")
			
			if let index = discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
				discoveredDevices[index].deviceID = value
			}
			
			if peripheral.identifier == esp32Peripheral?.identifier {
				connectedDeviceID = value.isEmpty ? "Unknown" : value
				connectionText = "Connected to device \(connectedDeviceID)"
			}
			
			//
			// Disconnect from non-selected probe devices after reading ID.
			//
			if probePeripheralIDs.contains(peripheral.identifier),
			   peripheral.identifier != esp32Peripheral?.identifier {
				probePeripheralIDs.remove(peripheral.identifier)
				centralManager.cancelPeripheralConnection(peripheral)
			}
		}
	}

	private func sendStoredKeyboardTiming() {
		let defaults = UserDefaults.standard
		let onMs = Int(defaults.double(forKey: StoredTimingKey.onMs))
		let offMs = Int(defaults.double(forKey: StoredTimingKey.offMs))
		sendKeyboardTiming(onMs: onMs, offMs: offMs)
	}
}

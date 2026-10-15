//  BLEKeyboardManager.swift
//  ESP32_ble
//
//  Created by Eric Beresford on 2026/03/07.
//

import Foundation
import CoreBluetooth
import Combine

private let BLEProbeClock = DispatchTime.now()

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

	private struct QueuedBLELine: Identifiable {
		let id = UUID()
		let line: String
	}
	//
	// Published state for the SwiftUI interface.
	//
	@Published var bluetoothStateText = "Starting Bluetooth..."
		@Published var connectionText = "Not connected"
		@Published var isConnected = false
		@Published var lastMessage = "None"
		@Published var bluetoothMonitorText = ""
		
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
		private var txCharacteristic: CBCharacteristic?
		private var idCharacteristic: CBCharacteristic?
			private var outgoingLines: [QueuedBLELine] = []
			private var sendQueueTask: Task<Void, Never>?
			private let sendInterval: Duration = .milliseconds(25)
			private var isDeliberatelyStopped = true
			private var staleDeviceCleanupTimer: Timer?
		private let discoveredDeviceTimeout: TimeInterval = 8
		private let staleDeviceCleanupInterval: TimeInterval = 2
	
	//
	// Track peripherals that are temporarily connected just to read device ID.
	//
		private var probePeripheralIDs: Set<UUID> = []
        private var pendingProbeDisconnectPeripheralIDs: Set<UUID> = []
        private var serviceDiscoveryPeripheralIDs: Set<UUID> = []
        private var characteristicDiscoveryPeripheralIDs: Set<UUID> = []
        private var completedCharacteristicDiscoveryPeripheralIDs: Set<UUID> = []
        private var deviceIDReadPeripheralIDs: Set<UUID> = []
        private var selectedInitializationPeripheralIDs: Set<UUID> = []

        // MARK: - BM:🅱️  add your comments here
        // Connection-probe state is diagnostic only and does not participate in BLE decisions.
        private var connectionAttemptNumber = 0
        private var connectionAttemptByPeripheral: [UUID: Int] = [:]

        private func connectionProbeLog(_ message: String) {
            let now = DispatchTime.now().uptimeNanoseconds
            let start = BLEProbeClock.uptimeNanoseconds
            let elapsedNanoseconds = now >= start ? now - start : 0
            let elapsedSeconds = Double(elapsedNanoseconds) / 1_000_000_000
            print("[BLE-CONNECT-PROBE] 🐞 t=\(String(format: "%.3f", elapsedSeconds))s \(message)")
        }

        private func connectionAttempt(for peripheral: CBPeripheral) -> String {
            connectionAttemptByPeripheral[peripheral.identifier].map(String.init) ?? "none"
        }

        private func peripheralStateDescription(_ state: CBPeripheralState) -> String {
            switch state {
            case .disconnected:
                return "disconnected"
            case .connecting:
                return "connecting"
            case .connected:
                return "connected"
            case .disconnecting:
                return "disconnecting"
            @unknown default:
                return "unknown"
            }
        }

        private func bluetoothStateDescription(_ state: CBManagerState) -> String {
            switch state {
            case .unknown:
                return "unknown"
            case .resetting:
                return "resetting"
            case .unsupported:
                return "unsupported"
            case .unauthorized:
                return "unauthorized"
            case .poweredOff:
                return "poweredOff"
            case .poweredOn:
                return "poweredOn"
            @unknown default:
                return "unknownFuture"
            }
        }
	
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
                let previousSelectedPeripheralID = selectedPeripheralID
			discoveredDevices.removeAll()
			selectedPeripheralID = nil
                if previousSelectedPeripheralID != nil {
                    connectionProbeLog("state selectedPeripheralID previous=\(previousSelectedPeripheralID?.uuidString ?? "nil") new=nil reason=clearDiscoveredDevices attempt=\(connectionAttemptNumber)")
                }
		}

			private func startStaleDeviceCleanupTimer() {
			staleDeviceCleanupTimer?.invalidate()
			let timer = Timer(timeInterval: staleDeviceCleanupInterval, repeats: true) { [weak self] _ in
				self?.removeStaleDiscoveredDevices()
			}
			staleDeviceCleanupTimer = timer
			RunLoop.main.add(timer, forMode: .common)
		}

		private func removeStaleDiscoveredDevices() {
			let cutoffDate = Date().addingTimeInterval(-discoveredDeviceTimeout)
			discoveredDevices.removeAll { device in
				let isConnectedDevice = device.id == esp32Peripheral?.identifier
				let shouldExpire = !isConnectedDevice && device.lastSeenAt < cutoffDate

				if isConnectedDevice {
					return false
				}

				if shouldExpire && device.id == selectedPeripheralID {
                        connectionProbeLog("stale cleanup removing selected device uuid=\(device.id.uuidString) active=false")
                    }
                    if shouldExpire && device.id == esp32Peripheral?.identifier {
                        connectionProbeLog("stale cleanup unexpectedly removing active device uuid=\(device.id.uuidString)")
                    }
					return shouldExpire
			}

			if let selectedPeripheralID,
			   !discoveredDevices.contains(where: { $0.id == selectedPeripheralID }),
			   selectedPeripheralID != esp32Peripheral?.identifier {
				connectionProbeLog("state selectedPeripheralID previous=\(selectedPeripheralID.uuidString) new=nil reason=staleCleanup attempt=\(connectionAttemptNumber)")
					self.selectedPeripheralID = nil
			}
		}
	
	//-------------------------------------------------------------------------
	// MARK: - Public actions
	//-------------------------------------------------------------------------
	
		func startScan() {
                connectionProbeLog("scan start requested bluetoothState=\(bluetoothStateDescription(centralManager.state)) deliberatelyStopped=\(isDeliberatelyStopped) isConnected=\(isConnected) connectionText=\(connectionText.debugDescription) selectedPeripheralID=\(selectedPeripheralID?.uuidString ?? "nil") activePeripheralUUID=\(esp32Peripheral?.identifier.uuidString ?? "nil") discoveredDeviceCount=\(discoveredDevices.count)")
			isDeliberatelyStopped = false
		guard centralManager.state == .poweredOn else {
			bluetoothStateText = "Bluetooth is not powered on"
			return
		}
		
			let previousConnectionText = connectionText
				connectionText = "Scanning..."
                connectionProbeLog("state connectionText previous=\(previousConnectionText.debugDescription) new=\(connectionText.debugDescription) peripheralUUID=\(esp32Peripheral?.identifier.uuidString ?? "nil") attempt=\(connectionAttemptNumber)")
			clearDiscoveredDevices()
			probePeripheralIDs.removeAll()
			startStaleDeviceCleanupTimer()
			
				connectionProbeLog("scan started bluetoothState=\(bluetoothStateDescription(centralManager.state)) deliberatelyStopped=\(isDeliberatelyStopped) isConnected=\(isConnected) connectionText=\(connectionText.debugDescription) selectedPeripheralID=\(selectedPeripheralID?.uuidString ?? "nil") activePeripheralUUID=\(esp32Peripheral?.identifier.uuidString ?? "nil") discoveredDeviceCount=\(discoveredDevices.count)")
                    centralManager.scanForPeripherals(
				withServices: [serviceUUID],
				options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
			)
	}

		func stop() {
                connectionProbeLog("scan stop requested reason=stop() activePeripheralUUID=\(esp32Peripheral?.identifier.uuidString ?? "nil") discoveredDeviceCount=\(discoveredDevices.count)")
			isDeliberatelyStopped = true
			centralManager.stopScan()
                connectionProbeLog("scanning stopped")
			staleDeviceCleanupTimer?.invalidate()
			staleDeviceCleanupTimer = nil
			for device in discoveredDevices {
				centralManager.cancelPeripheralConnection(device.peripheral)
			}
			outgoingLines.removeAll()
			sendQueueTask?.cancel()
			sendQueueTask = nil
			selectedPeripheralID = nil
            connectionProbeLog("state isConnected previous=\(isConnected) new=false activePeripheralUUID=\(esp32Peripheral?.identifier.uuidString ?? "nil") attempt=\(connectionAttemptNumber)")
			isConnected = false
			rxCharacteristic = nil
			txCharacteristic = nil
			idCharacteristic = nil
				connectedDeviceID = "Unknown"
				probePeripheralIDs.removeAll()
                pendingProbeDisconnectPeripheralIDs.removeAll()
                serviceDiscoveryPeripheralIDs.removeAll()
                characteristicDiscoveryPeripheralIDs.removeAll()
                completedCharacteristicDiscoveryPeripheralIDs.removeAll()
                deviceIDReadPeripheralIDs.removeAll()
                selectedInitializationPeripheralIDs.removeAll()
				connectionText = "Not connected"

			if let esp32Peripheral {
				centralManager.cancelPeripheralConnection(esp32Peripheral)
				self.connectionProbeLog("state esp32Peripheral previous=\(esp32Peripheral.identifier.uuidString) new=nil reason=stop attempt=\(connectionAttempt(for: esp32Peripheral))")
				self.esp32Peripheral = nil
			}
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

        connectionAttemptNumber += 1
        connectionAttemptByPeripheral[match.id] = connectionAttemptNumber
        let previousActivePeripheralID = esp32Peripheral?.identifier
        let previousConnectionText = connectionText
        connectionProbeLog("selected connect attempt=\(connectionAttemptNumber) selectedPeripheralUUID=\(match.id.uuidString) name=\(match.displayName.debugDescription) previousActivePeripheralUUID=\(previousActivePeripheralID?.uuidString ?? "nil") previousPeripheralState=\(peripheralStateDescription(match.peripheral.state)) previousIsConnected=\(isConnected) connectionText=\(connectionText.debugDescription) alreadyProbe=\(probePeripheralIDs.contains(match.id)) CBPeripheral.state=\(peripheralStateDescription(match.peripheral.state))")

		connectionText = "Connecting to \(match.displayName)..."
        connectionProbeLog("state connectionText previous=\(previousConnectionText.debugDescription) new=\(connectionText.debugDescription) peripheralUUID=\(match.id.uuidString) attempt=\(connectionAttemptNumber)")
		esp32Peripheral = match.peripheral
        connectionProbeLog("state esp32Peripheral previous=\(previousActivePeripheralID?.uuidString ?? "nil") new=\(match.id.uuidString) attempt=\(connectionAttemptNumber)")
		esp32Peripheral?.delegate = self
        connectionProbeLog("scan stop requested reason=selectedConnect peripheralUUID=\(match.id.uuidString) attempt=\(connectionAttemptNumber)")
		centralManager.stopScan()
        connectionProbeLog("scanning stopped reason=selectedConnect peripheralUUID=\(match.id.uuidString) attempt=\(connectionAttemptNumber)")
        let isPendingProbeConnection = match.peripheral.state == .connecting
            && probePeripheralIDs.contains(match.id)
        let isPendingProbeDisconnect = match.peripheral.state == .disconnecting
            && pendingProbeDisconnectPeripheralIDs.contains(match.id)
        if isPendingProbeDisconnect {
            connectionProbeLog("PENDING RECONNECT WAITING peripheralUUID=\(match.id.uuidString) attempt=\(connectionAttemptNumber) CBPeripheral.state=\(peripheralStateDescription(match.peripheral.state)) pendingDisconnectMembership=\(pendingProbeDisconnectPeripheralIDs.contains(match.id))")
        } else if isPendingProbeConnection {
            connectionProbeLog("SKIPPED DUPLICATE CONNECT peripheralUUID=\(match.id.uuidString) attempt=\(connectionAttemptNumber) CBPeripheral.state=\(peripheralStateDescription(match.peripheral.state)) probeMembership=\(probePeripheralIDs.contains(match.id)) reason=temporaryProbeAlreadyConnecting")
        } else {
            connectionProbeLog("centralManager.connect requested kind=selected peripheralUUID=\(match.id.uuidString) attempt=\(connectionAttemptNumber) alreadyProbe=\(probePeripheralIDs.contains(match.id))")
			centralManager.connect(match.peripheral, options: nil)
        }
		}
	
			func disconnect() {
				isDeliberatelyStopped = true
				outgoingLines.removeAll()
				sendQueueTask?.cancel()
				sendQueueTask = nil
				selectedPeripheralID = nil
				guard let esp32Peripheral else {
					connectionText = "Not connected"
					return
				}
				centralManager.cancelPeripheralConnection(esp32Peripheral)
			}
	
	//
	// Send one full line to the ESP32.
	// The ESP32 code expects a newline at the end.
	//
	func sendLine(_ line: String) {
		guard esp32Peripheral != nil,
			  rxCharacteristic != nil else {
			lastMessage = "Not connected / RX not ready"
			return
		}

		outgoingLines.append(QueuedBLELine(line: normalizedKeyboardText(line)))
		startSendQueueIfNeeded()
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
		sendLine("RIGHT")
	}
	
	func pressEnter() {
		sendLine("ENTER")
	}

		func pressBackspace() {
			sendLine("BS")
		}

		private func sendNormalizedKeyboardText(_ text: String) {
			sendLine(normalizedKeyboardText(text))
	}

		private func normalizedKeyboardText(_ text: String) -> String {
		var normalizedText = ""
		normalizedText.reserveCapacity(text.count)

		for character in text {
			switch character {
			case "‘", "’", "‛", "ʼ", "ʻ", "＇":
				normalizedText.append("'")
			case "“", "”":
				normalizedText.append("\"")
			default:
				normalizedText.append(character)
			}
		}

			return normalizedText
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
				if !isDeliberatelyStopped {
					startScan()
				}
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
						let now = Date()
						
						if let index = discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
                                let previousState = discoveredDevices[index].peripheral.state
                                if (peripheral.identifier == selectedPeripheralID || peripheral.identifier == esp32Peripheral?.identifier),
                                   previousState != peripheral.state {
                                    connectionProbeLog("existing peripheral significant state change uuid=\(peripheral.identifier.uuidString) name=\(name.debugDescription) RSSI=\(RSSI.intValue) selected=\(peripheral.identifier == selectedPeripheralID) active=\(peripheral.identifier == esp32Peripheral?.identifier) previousState=\(peripheralStateDescription(previousState)) newState=\(peripheralStateDescription(peripheral.state))")
                                }
						discoveredDevices[index] = BLEDiscoveredDevice(
							id: peripheral.identifier,
							peripheral: peripheral,
					name: name,
					rssi: RSSI.intValue,
					deviceID: discoveredDevices[index].deviceID,
							lastSeenAt: now
						)
					} else {
						connectionProbeLog("new peripheral discovered uuid=\(peripheral.identifier.uuidString) name=\(name.debugDescription) RSSI=\(RSSI.intValue) selected=\(peripheral.identifier == selectedPeripheralID) active=\(peripheral.identifier == esp32Peripheral?.identifier) temporaryProbeRequested=true")
                            let item = BLEDiscoveredDevice(
							id: peripheral.identifier,
						peripheral: peripheral,
					name: name,
					rssi: RSSI.intValue,
					deviceID: nil,
					lastSeenAt: now
				)
				discoveredDevices.append(item)
			
				//
				// Connect briefly to read its device ID.
				//
			probePeripheralIDs.insert(peripheral.identifier)
                connectionProbeLog("centralManager.connect requested kind=temporaryProbe peripheralUUID=\(peripheral.identifier.uuidString) selected=\(peripheral.identifier == selectedPeripheralID) active=\(peripheral.identifier == esp32Peripheral?.identifier)")
			peripheral.delegate = self
			centralManager.connect(peripheral, options: nil)
		}
	}
	
	func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
		let matchesSelected = peripheral.identifier == selectedPeripheralID
            let matchesActive = peripheral.identifier == esp32Peripheral?.identifier
            let wasProbe = probePeripheralIDs.contains(peripheral.identifier)

            if wasProbe && matchesSelected && matchesActive {
                probePeripheralIDs.remove(peripheral.identifier)
                connectionProbeLog("PROMOTED PROBE TO SELECTED peripheralUUID=\(peripheral.identifier.uuidString) attempt=\(connectionAttempt(for: peripheral)) previousProbeMembership=\(wasProbe) resultingProbeMembership=\(probePeripheralIDs.contains(peripheral.identifier))")
            }

            let isProbe = probePeripheralIDs.contains(peripheral.identifier)
            let probeIDs = probePeripheralIDs.map(\.uuidString).sorted().joined(separator: ",")
            connectionProbeLog("didConnect peripheralUUID=\(peripheral.identifier.uuidString) attempt=\(connectionAttempt(for: peripheral)) classifiedAsProbe=\(isProbe) matchesSelectedPeripheralID=\(matchesSelected) matchesEsp32Peripheral=\(matchesActive) probePeripheralIDs=[\(probeIDs)] isConnectedBefore=\(isConnected) connectionTextBefore=\(connectionText.debugDescription) discoverServicesRequested=true")
		
			if !isProbe {
				connectionProbeLog("state connectionText previous=\(connectionText.debugDescription) new=\"Connected, discovering services...\" peripheralUUID=\(peripheral.identifier.uuidString) attempt=\(connectionAttempt(for: peripheral))")
					connectionText = "Connected, discovering services..."
				connectionProbeLog("state isConnected previous=\(isConnected) new=true peripheralUUID=\(peripheral.identifier.uuidString) attempt=\(connectionAttempt(for: peripheral))")
					isConnected = true
				connectionProbeLog("state esp32Peripheral previous=\(esp32Peripheral?.identifier.uuidString ?? "nil") new=\(peripheral.identifier.uuidString) attempt=\(connectionAttempt(for: peripheral))")
					esp32Peripheral = peripheral
		}
		
		let identifier = peripheral.identifier
            let needsSelectedRediscovery = matchesSelected
                && matchesActive
                && completedCharacteristicDiscoveryPeripheralIDs.contains(identifier)
                && !selectedInitializationPeripheralIDs.contains(identifier)

            if needsSelectedRediscovery {
                serviceDiscoveryPeripheralIDs.remove(identifier)
                characteristicDiscoveryPeripheralIDs.remove(identifier)
                completedCharacteristicDiscoveryPeripheralIDs.remove(identifier)
                deviceIDReadPeripheralIDs.remove(identifier)
            }

            if serviceDiscoveryPeripheralIDs.insert(identifier).inserted {
                connectionProbeLog("discoverServices requested peripheralUUID=\(identifier.uuidString) attempt=\(connectionAttempt(for: peripheral)) classifiedAsProbe=\(isProbe)")
                peripheral.discoverServices([serviceUUID])
            } else {
                connectionProbeLog("SKIPPED DUPLICATE SERVICE DISCOVERY peripheralUUID=\(identifier.uuidString) attempt=\(connectionAttempt(for: peripheral)) reason=serviceDiscoveryAlreadyRequested")
            }
	}
	
			func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
                let wasPendingProbeDisconnect = pendingProbeDisconnectPeripheralIDs.remove(peripheral.identifier) != nil
                let wasProbe = probePeripheralIDs.contains(peripheral.identifier)
                let wasActive = esp32Peripheral?.identifier == peripheral.identifier
                connectionProbeLog("didDisconnect peripheralUUID=\(peripheral.identifier.uuidString) error=\(error.map { String(describing: $0) } ?? "nil") active=\(wasActive) probe=\(wasProbe) isConnectedBefore=\(isConnected) connectionTextBefore=\(connectionText.debugDescription) scanningWillRestart=\(wasActive && !isDeliberatelyStopped) activePeripheralWillBeCleared=\(wasActive)")
				probePeripheralIDs.remove(peripheral.identifier)
                serviceDiscoveryPeripheralIDs.remove(peripheral.identifier)
                characteristicDiscoveryPeripheralIDs.remove(peripheral.identifier)
                completedCharacteristicDiscoveryPeripheralIDs.remove(peripheral.identifier)
                deviceIDReadPeripheralIDs.remove(peripheral.identifier)
                selectedInitializationPeripheralIDs.remove(peripheral.identifier)

                let selectedMatches = selectedPeripheralID == peripheral.identifier
                let activeMatches = esp32Peripheral?.identifier == peripheral.identifier
                if wasPendingProbeDisconnect
                    && selectedMatches
                    && activeMatches
                    && !isDeliberatelyStopped {
                    connectionProbeLog("PENDING RECONNECT STARTED peripheralUUID=\(peripheral.identifier.uuidString) attempt=\(connectionAttempt(for: peripheral)) error=\(error.map { String(describing: $0) } ?? "nil") selectedPeripheralIDMatch=\(selectedMatches) esp32PeripheralMatch=\(activeMatches) deliberatelyStopped=\(isDeliberatelyStopped)")
                    centralManager.connect(peripheral, options: nil)
                    return
                }

                if wasPendingProbeDisconnect {
                    let rejectionReason: String
                    if isDeliberatelyStopped {
                        rejectionReason = "deliberatelyStopped"
                    } else if !selectedMatches {
                        rejectionReason = "selectedPeripheralChanged"
                    } else if !activeMatches {
                        rejectionReason = "activePeripheralChanged"
                    } else {
                        rejectionReason = "currentIntentInvalid"
                    }
                    connectionProbeLog("PENDING RECONNECT IGNORED peripheralUUID=\(peripheral.identifier.uuidString) reason=\(rejectionReason) selectedPeripheralUUID=\(selectedPeripheralID?.uuidString ?? "nil") activePeripheralUUID=\(esp32Peripheral?.identifier.uuidString ?? "nil") deliberatelyStopped=\(isDeliberatelyStopped)")
                }
				
				if esp32Peripheral?.identifier == peripheral.identifier {
			connectionProbeLog("state connectionText previous=\(connectionText.debugDescription) new=\"Disconnected\" peripheralUUID=\(peripheral.identifier.uuidString) attempt=\(connectionAttempt(for: peripheral))")
				connectionText = "Disconnected"
                    connectionProbeLog("state isConnected previous=\(isConnected) new=false peripheralUUID=\(peripheral.identifier.uuidString) attempt=\(connectionAttempt(for: peripheral))")
				isConnected = false
				rxCharacteristic = nil
				txCharacteristic = nil
				idCharacteristic = nil
			let previousConnectedDeviceID = connectedDeviceID
            connectedDeviceID = "Unknown"
            connectionProbeLog("state connectedDeviceID previous=\(previousConnectedDeviceID.debugDescription) new=\(connectedDeviceID.debugDescription) peripheralUUID=\(peripheral.identifier.uuidString) attempt=\(connectionAttempt(for: peripheral))")
            connectionProbeLog("state esp32Peripheral previous=\(peripheral.identifier.uuidString) new=nil attempt=\(connectionAttempt(for: peripheral))")
			esp32Peripheral = nil
				outgoingLines.removeAll()
				sendQueueTask?.cancel()
				sendQueueTask = nil
				if !isDeliberatelyStopped {
					startScan()
				}
			}
		}
	
		func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
                let wasProbe = probePeripheralIDs.contains(peripheral.identifier)
                let wasActive = esp32Peripheral?.identifier == peripheral.identifier
                connectionProbeLog("didFailToConnect peripheralUUID=\(peripheral.identifier.uuidString) error=\(error.map { String(describing: $0) } ?? "nil") active=\(wasActive) probe=\(wasProbe) isConnectedBefore=\(isConnected) connectionTextBefore=\(connectionText.debugDescription) scanningWillRestart=\(wasActive && !isDeliberatelyStopped) activePeripheralWillBeCleared=false")
				probePeripheralIDs.remove(peripheral.identifier)
                serviceDiscoveryPeripheralIDs.remove(peripheral.identifier)
                characteristicDiscoveryPeripheralIDs.remove(peripheral.identifier)
                completedCharacteristicDiscoveryPeripheralIDs.remove(peripheral.identifier)
                deviceIDReadPeripheralIDs.remove(peripheral.identifier)
                selectedInitializationPeripheralIDs.remove(peripheral.identifier)
			
			if esp32Peripheral?.identifier == peripheral.identifier {
				connectionProbeLog("state connectionText previous=\(connectionText.debugDescription) new=\"Failed to connect\" peripheralUUID=\(peripheral.identifier.uuidString) attempt=\(connectionAttempt(for: peripheral))")
					connectionText = "Failed to connect"
                    connectionProbeLog("state isConnected previous=\(isConnected) new=false peripheralUUID=\(peripheral.identifier.uuidString) attempt=\(connectionAttempt(for: peripheral))")
				isConnected = false
				outgoingLines.removeAll()
				sendQueueTask?.cancel()
				sendQueueTask = nil
				if !isDeliberatelyStopped {
					startScan()
				}
			}
		}
}

//-----------------------------------------------------------------------------
// MARK: - CBPeripheralDelegate
//-----------------------------------------------------------------------------
extension BLEKeyboardManager: CBPeripheralDelegate {
		func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
            let identifier = peripheral.identifier
            let serviceUUIDs = peripheral.services?.map { $0.uuid.uuidString }.joined(separator: ",") ?? "nil"
            connectionProbeLog("didDiscoverServices peripheralUUID=\(identifier.uuidString) error=\(error.map { String(describing: $0) } ?? "nil") serviceCount=\(peripheral.services?.count ?? 0) serviceUUIDs=[\(serviceUUIDs)] active=\(identifier == esp32Peripheral?.identifier) classifiedAsProbe=\(probePeripheralIDs.contains(identifier))")
			guard error == nil else {
                serviceDiscoveryPeripheralIDs.remove(identifier)
                characteristicDiscoveryPeripheralIDs.remove(identifier)
                completedCharacteristicDiscoveryPeripheralIDs.remove(identifier)
				if esp32Peripheral?.identifier == identifier {
					connectionText = "Service discovery failed"
				}
				return
			}
			
			guard let services = peripheral.services,
                  let service = services.first(where: { $0.uuid == serviceUUID }) else {
                serviceDiscoveryPeripheralIDs.remove(identifier)
                return
            }

            let needsSelectedRediscovery = identifier == selectedPeripheralID
                && identifier == esp32Peripheral?.identifier
                && completedCharacteristicDiscoveryPeripheralIDs.contains(identifier)
                && !selectedInitializationPeripheralIDs.contains(identifier)

            if needsSelectedRediscovery {
                characteristicDiscoveryPeripheralIDs.remove(identifier)
                completedCharacteristicDiscoveryPeripheralIDs.remove(identifier)
                deviceIDReadPeripheralIDs.remove(identifier)
            }

            if characteristicDiscoveryPeripheralIDs.insert(identifier).inserted {
                connectionProbeLog("discoverCharacteristics requested peripheralUUID=\(identifier.uuidString) serviceUUID=\(service.uuid.uuidString) characteristicUUIDs=[\(rxUUID.uuidString),\(txUUID.uuidString),\(deviceIDUUID.uuidString)]")
                peripheral.discoverCharacteristics([rxUUID, txUUID, deviceIDUUID], for: service)
            } else {
                connectionProbeLog("SKIPPED DUPLICATE CHARACTERISTIC DISCOVERY peripheralUUID=\(identifier.uuidString) attempt=\(connectionAttempt(for: peripheral)) reason=characteristicDiscoveryAlreadyRequested")
            }
		}
	
	func peripheral(
		_ peripheral: CBPeripheral,
		didDiscoverCharacteristicsFor service: CBService,
		error: Error?
		) {
            let identifier = peripheral.identifier
            let characteristicUUIDs = service.characteristics?.map { $0.uuid.uuidString }.joined(separator: ",") ?? "nil"
            let foundRX = service.characteristics?.contains(where: { $0.uuid == rxUUID }) ?? false
            let foundTX = service.characteristics?.contains(where: { $0.uuid == txUUID }) ?? false
            let foundDeviceID = service.characteristics?.contains(where: { $0.uuid == deviceIDUUID }) ?? false
            let isActive = identifier == esp32Peripheral?.identifier
            connectionProbeLog("didDiscoverCharacteristics peripheralUUID=\(identifier.uuidString) serviceUUID=\(service.uuid.uuidString) error=\(error.map { String(describing: $0) } ?? "nil") characteristicUUIDs=[\(characteristicUUIDs)] rxFound=\(foundRX) txFound=\(foundTX) deviceIDFound=\(foundDeviceID) txNotificationsRequested=\(error == nil && isActive && foundTX) deviceIDReadRequested=\(error == nil && foundDeviceID)")
			guard error == nil else {
                serviceDiscoveryPeripheralIDs.remove(identifier)
                characteristicDiscoveryPeripheralIDs.remove(identifier)
                completedCharacteristicDiscoveryPeripheralIDs.remove(identifier)
                deviceIDReadPeripheralIDs.remove(identifier)
                selectedInitializationPeripheralIDs.remove(identifier)
				if esp32Peripheral?.identifier == identifier {
					connectionText = "Characteristic discovery failed"
				}
				return
			}
			
			guard let characteristics = service.characteristics else {
                serviceDiscoveryPeripheralIDs.remove(identifier)
                characteristicDiscoveryPeripheralIDs.remove(identifier)
                return
            }

            completedCharacteristicDiscoveryPeripheralIDs.insert(identifier)
            let shouldInitializeSelected = isActive
                && selectedInitializationPeripheralIDs.insert(identifier).inserted

            if isActive && !shouldInitializeSelected {
                connectionProbeLog("SKIPPED DUPLICATE SELECTED INITIALIZATION peripheralUUID=\(identifier.uuidString) attempt=\(connectionAttempt(for: peripheral)) reason=selectedInitializationAlreadyCompleted")
            }
			
			for characteristic in characteristics {
					if shouldInitializeSelected, characteristic.uuid == rxUUID {
						rxCharacteristic = characteristic
					}

					if shouldInitializeSelected, characteristic.uuid == txUUID {
						txCharacteristic = characteristic
						connectionProbeLog("TX notification request peripheralUUID=\(identifier.uuidString) serviceUUID=\(service.uuid.uuidString) characteristicUUID=\(characteristic.uuid.uuidString)")
							peripheral.setNotifyValue(true, for: characteristic)
					}
					
					if characteristic.uuid == deviceIDUUID,
                       deviceIDReadPeripheralIDs.insert(identifier).inserted {
					if shouldInitializeSelected {
						idCharacteristic = characteristic
					}
					connectionProbeLog("DEVICE_ID read request peripheralUUID=\(identifier.uuidString) serviceUUID=\(service.uuid.uuidString) characteristicUUID=\(characteristic.uuid.uuidString) active=\(isActive) classifiedAsProbe=\(probePeripheralIDs.contains(identifier))")
						peripheral.readValue(for: characteristic)
				}
			}
			
				if shouldInitializeSelected {
					connectionProbeLog("active characteristic discovery completion peripheralUUID=\(identifier.uuidString) connectionTextBefore=\(connectionText.debugDescription) willSetConnected=true storedTimingWillBeSent=true")
                    let previousConnectionText = connectionText
						connectionText = "Connected"
                    connectionProbeLog("state connectionText previous=\(previousConnectionText.debugDescription) new=\(connectionText.debugDescription) peripheralUUID=\(identifier.uuidString) attempt=\(connectionAttempt(for: peripheral)) connectedActuallySet=\(connectionText == "Connected")")
					connectionProbeLog("stored timing send requested peripheralUUID=\(identifier.uuidString) attempt=\(connectionAttempt(for: peripheral))")
							sendStoredKeyboardTiming()
				}
		}
	
	func peripheral(
		_ peripheral: CBPeripheral,
		didUpdateValueFor characteristic: CBCharacteristic,
		error: Error?
	) {
		if characteristic.uuid == deviceIDUUID {
                let isProbe = probePeripheralIDs.contains(peripheral.identifier)
                let isSelected = peripheral.identifier == selectedPeripheralID
                let isActive = peripheral.identifier == esp32Peripheral?.identifier
                let hasDecodableValue = characteristic.value.flatMap { String(data: $0, encoding: .utf8) } != nil
                let disconnectRequested = error == nil && hasDecodableValue && isProbe && !isActive
                connectionProbeLog("DEVICE_ID response peripheralUUID=\(peripheral.identifier.uuidString) error=\(error.map { String(describing: $0) } ?? "nil") classifiedAsProbe=\(isProbe) selected=\(isSelected) active=\(isActive) disconnectRequested=\(disconnectRequested)")
            } else if characteristic.uuid == txUUID, let error {
                connectionProbeLog("TX significant activity peripheralUUID=\(peripheral.identifier.uuidString) error=\(String(describing: error)) payloadBytes=\(characteristic.value?.count ?? 0)")
            }
			guard error == nil else { return }
		
			if characteristic.uuid == deviceIDUUID,
			   let data = characteristic.value,
			   let value = String(data: data, encoding: .utf8)?
				.trimmingCharacters(in: .whitespacesAndNewlines) {
			
			
			if let index = discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
				discoveredDevices[index].deviceID = value
			}
			
			if peripheral.identifier == esp32Peripheral?.identifier {
				let previousConnectedDeviceID = connectedDeviceID
                    connectedDeviceID = value.isEmpty ? "Unknown" : value
                    connectionProbeLog("state connectedDeviceID previous=\(previousConnectedDeviceID.debugDescription) new=\(connectedDeviceID.debugDescription) peripheralUUID=\(peripheral.identifier.uuidString) attempt=\(connectionAttempt(for: peripheral))")
				let previousConnectionText = connectionText
                    connectionText = "Connected to device \(connectedDeviceID)"
                    connectionProbeLog("state connectionText previous=\(previousConnectionText.debugDescription) new=\(connectionText.debugDescription) peripheralUUID=\(peripheral.identifier.uuidString) attempt=\(connectionAttempt(for: peripheral))")
			}
			
			//
			// Disconnect from non-selected probe devices after reading ID.
			//
				if probePeripheralIDs.contains(peripheral.identifier),
				   peripheral.identifier != esp32Peripheral?.identifier {
					probePeripheralIDs.remove(peripheral.identifier)
                    pendingProbeDisconnectPeripheralIDs.insert(peripheral.identifier)
                    connectionProbeLog("PENDING PROBE DISCONNECT RECORDED peripheralUUID=\(peripheral.identifier.uuidString) CBPeripheral.state=\(peripheralStateDescription(peripheral.state)) attempt=\(connectionAttempt(for: peripheral)) pendingDisconnectMembership=\(pendingProbeDisconnectPeripheralIDs.contains(peripheral.identifier))")
						connectionProbeLog("disconnect requested reason=temporaryProbeDeviceIDRead peripheralUUID=\(peripheral.identifier.uuidString) selected=\(peripheral.identifier == selectedPeripheralID) active=\(peripheral.identifier == esp32Peripheral?.identifier)")
						centralManager.cancelPeripheralConnection(peripheral)
				}
			}

			if characteristic.uuid == txUUID,
			   peripheral.identifier == esp32Peripheral?.identifier,
			   let data = characteristic.value,
			   let value = String(data: data, encoding: .utf8) {
				appendBluetoothMonitorMessage(value)
			}
		}

		private func appendBluetoothMonitorMessage(_ message: String) {
			let trimmedMessage = message.trimmingCharacters(in: .newlines)
			guard !trimmedMessage.isEmpty else {
				return
			}

			if bluetoothMonitorText.isEmpty {
				bluetoothMonitorText = trimmedMessage
			} else {
				bluetoothMonitorText += "\n" + trimmedMessage
			}

			if bluetoothMonitorText.count > 12_000 {
				bluetoothMonitorText = String(bluetoothMonitorText.suffix(12_000))
			}
		}
	
		private func sendStoredKeyboardTiming() {
		let defaults = UserDefaults.standard
		let onMs = Int(defaults.double(forKey: StoredTimingKey.onMs))
		let offMs = Int(defaults.double(forKey: StoredTimingKey.offMs))
		sendKeyboardTiming(onMs: onMs, offMs: offMs)
	}

	private func startSendQueueIfNeeded() {
		guard sendQueueTask == nil else {
			return
		}

		sendQueueTask = Task { [weak self] in
			await self?.processSendQueue()
		}
	}

	@MainActor
	private func processSendQueue() async {
		while !outgoingLines.isEmpty {
			guard let nextLine = outgoingLines.first else {
				break
			}

			guard writeQueuedLine(nextLine.line) else {
				break
			}

			outgoingLines.removeFirst()

			do {
				try await Task.sleep(for: sendInterval)
			} catch {
				break
			}
		}

		sendQueueTask = nil

		if !outgoingLines.isEmpty, esp32Peripheral != nil, rxCharacteristic != nil {
			startSendQueueIfNeeded()
		}
	}

	private func writeQueuedLine(_ line: String) -> Bool {
		guard let peripheral = esp32Peripheral,
			  let rxCharacteristic else {
			lastMessage = "Not connected / RX not ready"
			return false
		}

		let fullLine = line + "\n"
		guard let data = fullLine.data(using: .utf8) else {
			lastMessage = "Failed to encode text"
			return false
		}

		peripheral.writeValue(data, for: rxCharacteristic, type: .withoutResponse)
		lastMessage = "Sent: \(line)"
		return true
	}
}

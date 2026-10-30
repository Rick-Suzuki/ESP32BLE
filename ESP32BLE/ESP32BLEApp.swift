//
//  ESP32BLEApp.swift
//  ESP32BLE
//
//  Created by Eric Beresford on 2026/03/11.
//

import SwiftUI
import Foundation
import Observation

@main
struct ESP32BLEApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
//
//----------------------------------------
//
@MainActor
@Observable
final class DebugVersionStore {
	var value = """
V65.72
"""
}

@MainActor
let debugVersion = DebugVersionStore()

@MainActor
var db_version: String {
	get { debugVersion.value }
	set { debugVersion.value = newValue }
}

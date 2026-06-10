//
//  debug.swift
//  ESP32BLE
//
//  Created by Eric Beresford on 2026/04/09.
//

import SwiftUI
import AVFoundation

// debug BT - prints
let db_bt = false

// if disabled, no emoji text subs
let db_emoji_parsing = false

// force emoji map to overwrite file: emoji_speech_map.cfg
// with array in contentView, about line 145
let db_overwriteConfigFile:Bool = true


extension Color {
	init(hex: String) {
		let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
		var int: UInt64 = 0
		Scanner(string: hex).scanHexInt64(&int)
		
		let r = Double((int >> 16) & 0xFF) / 255.0
		let g = Double((int >> 8) & 0xFF) / 255.0
		let b = Double(int & 0xFF) / 255.0
		
		self.init(red: r, green: g, blue: b)
	}
}

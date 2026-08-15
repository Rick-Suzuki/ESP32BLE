//
//  debug.swift
//  ESP32BLE
//
//  Created by Eric Beresford on 2026/04/09.
//

import SwiftUI
import AVFoundation
import Foundation

// debug BT - prints
let db_bt = false

let db_dbCode = true

//
//----------------------------------------
//
func getTime()->String {
	let timestampFormatter = DateFormatter()
	timestampFormatter.dateFormat = "yyMMdd_HHmm_SSS"
	let timeStamp = timestampFormatter.string(from: Date())
	return timeStamp
}
//
//----------------------------------------
//
func db(
	_ format: String,
	_ args: CVarArg...,
	file: String = #file,
	function: String = #function,
	line: Int = #line
) {
	let message = String(format: format, arguments: args)
	
	let output: String
	
	if db_dbCode {
		output = "🐞\(URL(fileURLWithPath: file).lastPathComponent):\(function):\(line) \(message)"
	} else {
		output = "🐞\(message)"
	}
	
	print("\(getTime()) \(output)")
}


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

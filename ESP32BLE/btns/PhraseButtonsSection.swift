//
//  PhraseButtonsSection.swift
//  ESP32_ble
//
//  Created by Eric Beresford on 2026/03/07.
//

import SwiftUI
import Combine

struct PhraseButtonsSection: View {
	@ObservedObject var ble: BLEKeyboardManager
	
	private let phrases: [String] = [
		"that was very cool",
		"you're a very dirty driver",
		"that was some clean driving",
		"better luck next time loser",
		"well, we all\\learned\\nsomething\tout there\\n",

		"good, clean race, nobody call the stewards",
		"I came for a podium and left with emotional damage",
		"smooth race, my tyres would like a word",
		"that was fun, terrifying, and deeply educational",
		"good finish, somehow the car still has all four wheels",

		"thanks everyone, that was chaos with beautiful scenery",
		"brilliant race, I only panicked on every lap and every corner",
		"good race, I aged about ten years",
		"that was a beautiful disaster from start to finish",
		"never in the field of racing was so much contact made by so few with so little regard for others",
	]
	
	var body: some View {
		GeometryReader { geo in
			LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 5), spacing: 0) {
				ForEach(phrases, id: \.self) { phrase in
					Button(action: {
						ble.sendString(phrase)
					}) {
						Text(phrase)
							.font(.system(size: 32, weight: .semibold))
							.foregroundColor(.white)
							.multilineTextAlignment(.center)
							.lineLimit(nil)
							.frame(maxWidth: .infinity, maxHeight: .infinity)
							.background(Color.black)
							.overlay(
								RoundedRectangle(cornerRadius: 0)
									.stroke(Color.white, lineWidth: 1)
							)
					}
				}
			}
			.frame(width: geo.size.width, height: geo.size.height)
		}
		.frame(height: 500)
		.background(Color.black)
	}
}


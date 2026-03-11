//
//-----------------------------------------------------------------------------------------------
//
import SwiftUI

extension ContentView {
	//
	//-----------------------------------------------------------------------------------------------
	//
	struct TestArea: View {
		@ObservedObject var ble: BLEKeyboardManager

		var body: some View {
			HStack(spacing:20) {
				Button {
					ble.sendLine("cm")
					ble.sendLine("f11")
				} label: {
					Text("cm-f11")
				}

				Button {
					ble.sendLine("f11")
				} label: {
					Text("f11")
				}

				Button {
					ble.sendLine("f12")
				} label: {
					Text("f12")
				}

				Button {
					ble.sendLine("set:0:0")
				} label: {
					Text("MacOS ks")
				}

				Button {
					ble.sendLine("set:20:70")
				} label: {
					Text("PS5 ks")
				}
			}
		}
	}
	//
	//-----------------------------------------------------------------------------------------------
	//
}
//
//-----------------------------------------------------------------------------------------------
//


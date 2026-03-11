import SwiftUI

struct ContentView: View {
    @StateObject private var ble = BLEKeyboardManager()

    var body: some View {
        NavigationStack {
            MainScreen(ble: ble)
        }
		.onAppear {
			let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
			let testURL = documentsURL.appendingPathComponent("test.txt")
			
			do {
				try "** hello from iOS".write(to: testURL, atomically: true, encoding: .utf8)
				print("** WROTE:", testURL.path)
			} catch {
				print("** WRITE ERROR:", error)
			}
		}

    }
}

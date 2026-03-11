import SwiftUI

struct ContentView: View {
    @StateObject private var ble = BLEKeyboardManager()

    var body: some View {
        NavigationStack {
            MainScreen(ble: ble)
        }
    }
}

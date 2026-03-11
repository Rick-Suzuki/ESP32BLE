import SwiftUI

private enum ModifierCommand: String, CaseIterable, Identifiable {
    case command = "cm"
    case option = "op"
    case shift = "sh"
    case control = "ct"
    case off = "off"

    var id: Self { self }

    var title: String {
        switch self {
        case .command:
            return "cmd"
        case .option:
            return "option"
        case .shift:
            return "shift"
        case .control:
            return "control"
        case .off:
            return "off"
        }
    }
}

struct MainScreen: View {
    @ObservedObject var ble: BLEKeyboardManager
    @State private var selectedModifier: ModifierCommand = .off

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        VStack(spacing: 20) {
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(1...20, id: \.self) { number in
                    Button("F\(number)") {
                        ble.sendLine("f\(number)")
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, minHeight: 56)
                }
            }

            Spacer(minLength: 0)

            modifierButtons
        }
        .padding()
        .navigationTitle("Main")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Settings") {
                    SettingsScreen(ble: ble)
                }
            }
        }
    }

    private var modifierButtons: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Modifiers")
                .font(.headline)

            HStack(spacing: 10) {
                ForEach(ModifierCommand.allCases) { modifier in
                    Button(modifier.title) {
                        selectedModifier = modifier
                        ble.sendLine(modifier.rawValue)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(selectedModifier == modifier ? .blue : .gray)
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial)
        .clipShape(.rect(cornerRadius: 16))
    }
}

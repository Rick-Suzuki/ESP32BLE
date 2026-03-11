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
    @State private var activeModifiers: Set<ModifierCommand> = []

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 5)

    var body: some View {
        VStack(spacing: 20) {
            GeometryReader { geometry in
                let buttonHeight = geometry.size.height / 4

                LazyVGrid(columns: gridColumns, spacing: 0) {
                    ForEach(1...20, id: \.self) { number in
                        Button {
                            ble.sendLine("f\(number)")
                        } label: {
                            Text("F\(number)")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: buttonHeight, maxHeight: buttonHeight)
                                .background(Color.black)
                                .overlay {
                                    Rectangle()
                                        .stroke(Color.white, lineWidth: 1)
                                }
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            modifierButtons
        }
        .padding()
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("settings >") {
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
                    let isSelected = modifier == .off ? activeModifiers.isEmpty : activeModifiers.contains(modifier)

                    Button {
                        toggleModifier(modifier)
                    } label: {
                        Text(modifier.title)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .background(isSelected ? Color.blue : Color.gray.opacity(0.18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.blue : Color.gray.opacity(0.4), lineWidth: 2)
                    }
                    .clipShape(.rect(cornerRadius: 12))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial)
        .clipShape(.rect(cornerRadius: 16))
    }

    private func toggleModifier(_ modifier: ModifierCommand) {
        if modifier == .off {
            activeModifiers.removeAll()
            ble.sendLine(modifier.rawValue)
            return
        }

        if activeModifiers.contains(modifier) {
            activeModifiers.remove(modifier)
        } else {
            activeModifiers.insert(modifier)
            ble.sendLine(modifier.rawValue)
        }
    }
}

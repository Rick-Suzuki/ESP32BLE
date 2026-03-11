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
    @State private var functionKeyTitles = (1...20).map { "F\($0)" }

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 5)

    var body: some View {
        VStack(spacing: 20) {
            GeometryReader { geometry in
                let buttonHeight = geometry.size.height / 4

                LazyVGrid(columns: gridColumns, spacing: 0) {
                    ForEach(Array(functionKeyTitles.enumerated()), id: \.offset) { index, title in
                        Button {
                            ble.sendLine("f\(index + 1)")
                        } label: {
                            Text(title)
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
        .task {
            loadFunctionKeyTitles()
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

    private func loadFunctionKeyTitles() {
        let defaultTitles = (1...20).map { "F\($0)" }
        let fileURL = functionKeysFileURL()

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let defaultContents = defaultTitles.joined(separator: "\n")

            do {
                try defaultContents.write(to: fileURL, atomically: true, encoding: .utf8)
                functionKeyTitles = defaultTitles
            } catch {
                functionKeyTitles = defaultTitles
            }

            return
        }

        do {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            let loadedTitles = contents.components(separatedBy: .newlines)
            functionKeyTitles = normalizedFunctionKeyTitles(from: loadedTitles, defaults: defaultTitles)
        } catch {
            functionKeyTitles = defaultTitles
        }
    }

    private func functionKeysFileURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("fnkeys.txt")
    }

    private func normalizedFunctionKeyTitles(from loadedTitles: [String], defaults: [String]) -> [String] {
        let firstTwenty = Array(loadedTitles.prefix(20))

        return defaults.enumerated().map { index, fallback in
            guard index < firstTwenty.count else {
                return fallback
            }

            let title = firstTwenty[index].trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? fallback : title
        }
    }
}

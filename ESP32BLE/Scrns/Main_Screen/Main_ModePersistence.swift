import Foundation

private enum MainScreenPersistedModeFiles {
    static let displayMode = ".main_screen_view_mode.cfg"
    static let buttonActionMode = ".main_screen_button_action_mode.cfg"
}

extension MainScreen {

    func cycleMainGridButtonMode() {
        mainGridButtonMode = mainGridButtonMode.next()
        savePersistedMainGridButtonMode()
        if !mainGridButtonMode.speaksText {
            stopSpokenGridText()
        }
    }

    func advanceDisplayMode() {
        displayMode = displayMode.next()
        savePersistedDisplayMode()
    }

    @MainActor
    func restorePersistedMainScreenModes() {
        displayMode = readPersistedString(from: MainScreenPersistedModeFiles.displayMode)
            .flatMap(FunctionKeyDisplayMode.init(persistedValue:)) ?? .right

        mainGridButtonMode = readPersistedString(from: MainScreenPersistedModeFiles.buttonActionMode)
            .flatMap(MainGridButtonMode.init(persistedValue:)) ?? .active

        savePersistedDisplayMode()
        savePersistedMainGridButtonMode()
    }

    private func savePersistedDisplayMode() {
        writePersistedString(displayMode.persistedValue, to: MainScreenPersistedModeFiles.displayMode)
    }

    private func savePersistedMainGridButtonMode() {
        writePersistedString(mainGridButtonMode.persistedValue, to: MainScreenPersistedModeFiles.buttonActionMode)
    }

    private func readPersistedString(from filename: String) -> String? {
        guard let url = persistedModeFileURL(named: filename) else {
            return nil
        }

        guard let contents = try? String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !contents.isEmpty else {
            return nil
        }

        let keyedValues = persistedModeValues(from: contents)
        if let value = keyedValues[selectedDocumentName] {
            return value
        }

        // Legacy support for the old single-value mode files.
        return keyedValues.isEmpty ? contents : nil
    }

    private func writePersistedString(_ value: String, to filename: String) {
        guard let url = persistedModeFileURL(named: filename) else {
            return
        }

        let existingContents = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var keyedValues = persistedModeValues(from: existingContents)
        keyedValues[selectedDocumentName] = value

        let updatedContents = keyedValues
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n")

        try? updatedContents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func persistedModeValues(from contents: String) -> [String: String] {
        contents
            .split(whereSeparator: \.isNewline)
            .reduce(into: [:]) { result, line in
                let lineText = String(line)
                guard let separatorIndex = lineText.firstIndex(of: "=") else {
                    return
                }

                let key = String(lineText[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                let value = String(lineText[lineText.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty, !value.isEmpty else {
                    return
                }

                result[key] = value
            }
    }

    private func persistedModeFileURL(named filename: String) -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(filename, isDirectory: false)
    }
}

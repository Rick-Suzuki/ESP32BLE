import SwiftUI

extension SettingsScreen {
    var sendTextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button("del") {
                    ButtonClickFeedback.playIfEnabled()
                    bleTextToSend = ""
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(bleTextToSend.isEmpty)

                TextField("Text to send", text: $bleTextToSend, selection: $bleTextSelection)
                    .focused($focusedField, equals: .sendText)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(sendEnteredText)

                Button("tab") {
                    ButtonClickFeedback.playIfEnabled()
                    insertTextAtCursor("\\n")
                }
                .buttonStyle(.bordered)

                Button("return") {
                    ButtonClickFeedback.playIfEnabled()
                    insertTextAtCursor("\\n")
                }
                .buttonStyle(.bordered)

                Button("Send") {
                    ButtonClickFeedback.playIfEnabled()
                    sendEnteredText()
                }
                .buttonStyle(.borderedProminent)
                .disabled(bleTextToSend.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial)
        .clipShape(.rect(cornerRadius: 16))
    }

    func sendEnteredText() {
        let trimmedText = bleTextToSend.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedText.isEmpty else {
            return
        }

        guard ble.isConnected else {
            print("Bluetooth not connected.")
            return
        }

        if sendControlABeforeText {
            ble.sendLine("ca")
        }

        print("Settings text sent: [\(trimmedText)]")
        ble.sendString(trimmedText)
    }

    func insertTextAtCursor(_ insertedText: String) {
        guard let selection = bleTextSelection else {
            bleTextToSend.append(insertedText)
            bleTextSelection = TextSelection(insertionPoint: bleTextToSend.endIndex)
            return
        }

        switch selection.indices {
        case .selection(let range):
            let lowerOffset = bleTextToSend.distance(from: bleTextToSend.startIndex, to: range.lowerBound)
            let upperOffset = bleTextToSend.distance(from: bleTextToSend.startIndex, to: range.upperBound)
            let lowerBound = bleTextToSend.index(bleTextToSend.startIndex, offsetBy: lowerOffset)
            let upperBound = bleTextToSend.index(bleTextToSend.startIndex, offsetBy: upperOffset)

            bleTextToSend.replaceSubrange(lowerBound..<upperBound, with: insertedText)

            let insertionOffset = lowerOffset + insertedText.count
            let insertionPoint = bleTextToSend.index(bleTextToSend.startIndex, offsetBy: insertionOffset)
            bleTextSelection = TextSelection(insertionPoint: insertionPoint)
        case .multiSelection:
            bleTextToSend.append(insertedText)
            bleTextSelection = TextSelection(insertionPoint: bleTextToSend.endIndex)
        @unknown default:
            bleTextToSend.append(insertedText)
            bleTextSelection = TextSelection(insertionPoint: bleTextToSend.endIndex)
        }
    }
}

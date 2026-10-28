
/*
 This contains most of the button behavior logic:
 tap handling,
 edit-mode actions,
 resizing,
 duplicate/delete behavior,
 movement rules/helpers.
 */

import SwiftUI
import AVFoundation
import UIKit
import Combine
import PDFKit
import Observation

// MARK: - BM:🅱️ Runtime-only MIDI activations. Entries exist only after transport accepts the press message.
struct MainMIDITouchContext: Equatable {
    let documentSession: UUID
    let documentName: String
    let slot: Int
    let commandText: String
    let generation: UUID
    let connectionSession: UUID
    enum Message: Equatable {
        case note(number: UInt8, velocity: UInt8, mode: MIDINoteMode)
        case noteOff(number: UInt8)
        case controlChangeHold(controller: UInt8, value: UInt8, endValue: UInt8)
        case controlChangeToggle(controller: UInt8, value: UInt8, endValue: UInt8)
    }

    let message: Message
    let channel: UInt8

    var mode: MIDINoteMode {
        if case .note(_, _, let mode) = message { return mode }
        if case .controlChangeToggle = message { return .toggle }
        return .momentary
    }

    var releaseCommand: String {
        switch message {
        case .note(let note, _, _):
            return "MIDI:NOTE_OFF:\(note):\(channel)"
        case .noteOff(let note):
            return "MIDI:NOTE_OFF:\(note):\(channel)"
        case .controlChangeHold(let controller, _, let endValue), .controlChangeToggle(let controller, _, let endValue):
            return "MIDI:CC:\(controller):\(endValue):\(channel)"
        }
    }
}

struct MainGridMIDICCDisplayKey: Hashable {
    let documentSession: UUID
    let documentName: String
    let slot: Int
    let commandText: String
    let connectionSession: UUID
    let channel: UInt8

    init?(_ context: MainMIDITouchContext) {
        switch context.message {
        case .controlChangeHold, .controlChangeToggle:
            documentSession = context.documentSession
            documentName = context.documentName
            slot = context.slot
            commandText = context.commandText
            connectionSession = context.connectionSession
            channel = context.channel
        case .note, .noteOff:
            return nil
        }
    }
}

@MainActor
@Observable
final class MainMIDIActivationRegistry {
    let ownerID = UUID()
    private(set) var generation = UUID()
    private var activations: [UUID: MainMIDITouchContext] = [:]

    func activeToken(for context: MainMIDITouchContext) -> UUID? {
        activations.first { $0.value == context }?.key
    }

    private struct SoundingNote: Hashable {
        let connectionSession: UUID
        let channel: UInt8
        let note: UInt8

        init?(_ context: MainMIDITouchContext) {
            guard case .note(let note, _, _) = context.message else { return nil }
            connectionSession = context.connectionSession
            channel = context.channel
            self.note = note
        }

        init(connectionSession: UUID, channel: UInt8, note: UInt8) {
            self.connectionSession = connectionSession
            self.channel = channel
            self.note = note
        }
    }

    // MARK: - BM:🅱️ Each finger owns a token; notes and note toggles share one sounding pitch until the last owner releases.
    func begin(_ context: MainMIDITouchContext, sendOn: () -> Bool) -> UUID? {
        guard context.generation == generation else { return nil }
        let isMomentaryNote: Bool
        if case .note(_, _, .momentary) = context.message {
            isMomentaryNote = true
        } else {
            isMomentaryNote = false
        }
        guard isMomentaryNote || !activations.values.contains(where: {
            $0.documentSession == context.documentSession &&
            $0.documentName == context.documentName && $0.slot == context.slot
        }) else { return nil }

        let note = SoundingNote(context)
        let alreadySounding = note.map { key in
            activations.values.contains { SoundingNote($0) == key }
        } ?? false
        guard alreadySounding || sendOn() else { return nil }

        let token = UUID()
        activations[token] = context
        return token
    }

    // MARK: - BM:🅱️ A toggle press may change only the activation observed at touch-down.
    func toggle(
        _ context: MainMIDITouchContext,
        expectedToken: UUID?,
        connectionSession: UUID,
        sendOn: () -> Bool,
        sendControlChangeOff: (MainMIDITouchContext) -> Bool,
        sendOff: (MainMIDITouchContext) -> Void
    ) {
        guard context.mode == .toggle,
              context.generation == generation,
              context.connectionSession == connectionSession,
              activeToken(for: context) == expectedToken else { return }

        if let expectedToken {
            if case .controlChangeToggle = context.message {
                // MARK: - BM:🅱️ Keep CC Toggle active after a rejected OFF; lifecycle cleanup still clears invalid sessions.
                guard sendControlChangeOff(context) else { return }
                activations.removeValue(forKey: expectedToken)
            } else {
                release(expectedToken, connectionSession: connectionSession, sendOff: sendOff)
            }
        } else {
            _ = begin(context, sendOn: sendOn)
        }
    }

    func release(_ token: UUID, connectionSession: UUID, sendOff: (MainMIDITouchContext) -> Void) {
        guard let activation = activations[token] else { return }
        activations.removeValue(forKey: token)
        guard activation.connectionSession == connectionSession else { return }
        if let note = SoundingNote(activation),
           activations.values.contains(where: { SoundingNote($0) == note }) {
            return
        }
        sendOff(activation)
    }

    func reconcileExplicitNoteOff(_ identity: MIDINoteIdentity, connectionSession: UUID) {
        let soundingNote = SoundingNote(
            connectionSession: connectionSession,
            channel: identity.channel,
            note: identity.note
        )
        activations = activations.filter { _, activation in
            SoundingNote(activation) != soundingNote
        }
    }

    func reset(connectionSession: UUID, sendOff: (MainMIDITouchContext) -> Void) {
        let released = activations
        activations.removeAll()
        generation = UUID()
        var releasedNotes = Set<SoundingNote>()
        for activation in released.values where activation.connectionSession == connectionSession {
            if let note = SoundingNote(activation),
               !releasedNotes.insert(note).inserted {
                continue
            }
            sendOff(activation)
        }
    }
}

struct MainGridAutomaticMIDILabel {
    enum Content {
        case note(name: String, velocity: UInt8, mode: MIDINoteMode)
        case controlChange(name: String, value: String, mode: MIDIControlChangeMode)
    }

    let content: Content
    let channel: UInt8

    var title: String {
        switch content {
        case .note(let name, _, _), .controlChange(let name, _, _):
            return name
        }
    }

    var midiValue: String? {
        switch content {
        case .note(_, let velocity, _):
            return "\(velocity)"
        case .controlChange(_, let value, _):
            return value
        }
    }

    var usesControlChangeValueColor: Bool {
        if case .controlChange = content {
            return true
        }
        return false
    }

    var detailText: String {
        if case .note(_, _, let mode) = content {
            return mode == .toggle ? "ch \(channel) · toggle" : "ch \(channel)"
        }
        if case .controlChange(_, _, let mode) = content {
            switch mode {
            case .hold: return "ch \(channel) · hold"
            case .toggle: return "ch \(channel) · toggle"
            case .oneShot: break
            }
        }
        return "ch \(channel)"
    }

    var text: String {
        [title, midiValue, detailText].compactMap { $0 }.joined(separator: "\n")
    }
}

private enum MainGridSoundPreparationError: Error {
    case preparationFailed
}

final class MainGridSoundPlaybackDelegate: NSObject, AVAudioPlayerDelegate {
    nonisolated let requestID: UUID
    nonisolated let onCompletion: @MainActor @Sendable (UUID) -> Void

    init(requestID: UUID, onCompletion: @escaping @MainActor @Sendable (UUID) -> Void) {
        self.requestID = requestID
        self.onCompletion = onCompletion
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let requestID = requestID
        let onCompletion = onCompletion
        Task { @MainActor in
            onCompletion(requestID)
        }
    }
}

final class MainGridSpeechPlaybackDelegate: NSObject, AVSpeechSynthesizerDelegate {
    nonisolated let requestID: UUID
    nonisolated let utteranceID: ObjectIdentifier
    nonisolated let onCompletion: @MainActor @Sendable (UUID) -> Void

    init(
        requestID: UUID,
        utterance: AVSpeechUtterance,
        onCompletion: @escaping @MainActor @Sendable (UUID) -> Void
    ) {
        self.requestID = requestID
        utteranceID = ObjectIdentifier(utterance)
        self.onCompletion = onCompletion
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        finishIfCurrentUtterance(utterance)
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        finishIfCurrentUtterance(utterance)
    }

    nonisolated private func finishIfCurrentUtterance(_ utterance: AVSpeechUtterance) {
        guard ObjectIdentifier(utterance) == utteranceID else {
            return
        }

        let requestID = requestID
        let onCompletion = onCompletion
        Task { @MainActor in
            onCompletion(requestID)
        }
    }
}

struct MainGridSoundRequest {
    let filename: String
    let volumePercentage: Int
}

enum MainGridSoundRequestParseResult {
    case request(MainGridSoundRequest)
    case invalidVolume
}

enum MainGridOrdinarySoundPlaybackPhase {
    case stopped
    case preparing
    case playing
    case paused
}

actor MainGridSoundPlayerPreparer {
    static let shared = MainGridSoundPlayerPreparer()
    private static let preparationQueue = DispatchQueue(label: "ESP32BLE.MainGridSoundPreparation")

    func preparePlayer(at audioURL: URL, repeats: Bool) async throws -> AVAudioPlayer {
        try await withCheckedThrowingContinuation { continuation in
            Self.preparationQueue.async {
                do {
                    let player = try AVAudioPlayer(contentsOf: audioURL)
                    player.numberOfLoops = repeats ? -1 : 0
                    guard player.prepareToPlay() else {
                        throw MainGridSoundPreparationError.preparationFailed
                    }
                    continuation.resume(returning: player)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - BM:🅱️  W2A: Command Classification
private enum CommandClassification {
    case internalCommand
    case file
    case external
}

private func commandClassification(for token: String) -> CommandClassification {
    let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmedToken.hasPrefix(".") {
        return .internalCommand
    }

    let recognizedFileExtensions: Set<String> = [
        "screen", "s", "txt", "md", "pdf",
        "png", "jpg", "jpeg", "gif", "heic", "webp",
        "mp3", "wav", "m4a", "aiff", "aac", "caf"
    ]
    let pathExtension = URL(fileURLWithPath: trimmedToken).pathExtension.lowercased()

    if recognizedFileExtensions.contains(pathExtension) {
        return .file
    }

    return .external
}

struct ESPOutputSourceMetadata {
    let sfSymbolName: String
    let buttonText: String
}

// MARK: - BM:🅱️🅱️🅱️ ESP-OUTPUT diagnostic probe
private enum ESPOutputProbe {
    private static var sequenceNumber = 0

    static func printGeneratedItems(
        _ items: [String],
        sourceMetadata: ESPOutputSourceMetadata? = nil
    ) {
        for item in items {
            sequenceNumber += 1
            var output = "[ESP-OUTPUT] #\(sequenceNumber) \"\(escapedString(item))\""
            if let sourceMetadata {
                output += " | SF=\"\(escapedString(sourceMetadata.sfSymbolName))\""
                output += " | Text=\"\(escapedString(sourceMetadata.buttonText))\""
            }
            print(output)
        }
    }

    private static func escapedString(_ string: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(string.count)

        for character in string {
            switch character {
            case "\\":
                escaped += "\\\\"
            case "\"":
                escaped += "\\\""
            case "\n":
                escaped += "\\n"
            case "\r":
                escaped += "\\r"
            case "\t":
                escaped += "\\t"
            default:
                escaped.append(character)
            }
        }

        return escaped
    }
}

extension MainScreen {
		// MARK: - BM:🔳 main scrn SF symbols
    private var supportedMainScreenSFSymbolNames: Set<String> {
        [
            "folder", "eye", "magnifyingglass", "gearshape", "house",
            "lightbulb.max.fill", "speaker.wave.2", "star", "heart", "bell",
            "paperclip", "link", "paperplane", "doc", "calendar",
            "camera", "photo", "tray", "sun.max.fill", "chart.bar.fill"
        ]
    }

    func buttonTitle(for entry: FunctionKeyEntry, defaultMIDIChannel: Int) -> String {
        let commandDefaultLabel = commandDefaultLabel(for: entry, defaultMIDIChannel: defaultMIDIChannel)
        let alternateDisplayText = effectiveAlternateDisplayText(for: entry, defaultMIDIChannel: defaultMIDIChannel)

        guard entry.displayUsesAlternateText || commandDefaultLabel != nil else {
            return displayText(from: rawLineWithoutHiddenMetadata(entry))
        }

        switch displayMode {
        case .left:
            return displayText(from: entry.primaryDisplayText)
        case .right:
            return displayText(from: alternateDisplayText)
        case .last:
            return displayTextAfterLastColon(in: alternateDisplayText)
        case .both:
            return "\(displayText(from: entry.primaryDisplayText))\n\(displayText(from: alternateDisplayText))"
        }
    }

    func displayText(from text: String) -> String {
        text
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")
    }

    func displayTextAfterLastColon(in text: String) -> String {
        let normalizedText = displayText(from: text)
        let components = normalizedText.components(separatedBy: ":")
        guard let lastComponent = components.last?.trimmingCharacters(in: .whitespacesAndNewlines),
              !lastComponent.isEmpty else {
            return normalizedText
        }

        return lastComponent
    }

    func outputSourceMetadata(for entry: FunctionKeyEntry) -> ESPOutputSourceMetadata {
        if let sfSymbolDisplay = parsedSFSymbolDisplay(for: entry) {
            return ESPOutputSourceMetadata(
                sfSymbolName: sfSymbolDisplay.name,
                buttonText: sfSymbolDisplay.subtitle ?? ""
            )
        }

        let storedButtonText = entry.alternateDisplayText.map(displayText(from:)) ?? ""
        let buttonText: String
        switch displayMode {
        case .last:
            buttonText = displayTextAfterLastColon(in: storedButtonText)
        case .left, .right, .both:
            buttonText = storedButtonText
        }
        return ESPOutputSourceMetadata(sfSymbolName: "", buttonText: buttonText)
    }

    func resolvedAlternateDisplayText(for entry: FunctionKeyEntry) -> String {
        if let alternateDisplayText = entry.alternateDisplayText {
            return alternateDisplayText
        }

        let components = rawLineWithoutHiddenMetadata(entry).components(separatedBy: "::")
        guard components.count >= 2 else {
            return ""
        }

        let rawRightText = components
            .dropFirst()
            .joined(separator: "::")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rightComponents = rawRightText.components(separatedBy: ":")

        if rightComponents.count > 1,
           let firstComponent = rightComponents.first,
           isHexColorPrefix(firstComponent) {
            let remainingText = rightComponents
                .dropFirst()
                .joined(separator: ":")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return remainingText
        }

        return rawRightText
    }

    private func effectiveAlternateDisplayText(for entry: FunctionKeyEntry, defaultMIDIChannel: Int) -> String {
        let alternateDisplayText = resolvedAlternateDisplayText(for: entry)
        guard alternateDisplayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return alternateDisplayText
        }

        return commandDefaultLabel(for: entry, defaultMIDIChannel: defaultMIDIChannel) ?? alternateDisplayText
    }

    private func commandDefaultLabel(for entry: FunctionKeyEntry, defaultMIDIChannel: Int) -> String? {
        if let navigationLabel = navigationCommandDefaultLabel(for: entry.primaryDisplayText) {
            return navigationLabel
        }

        guard entry.sendTexts.count == 1,
              let sendText = entry.sendTexts.first,
              sendText.hasPrefix(".") else {
            return nil
        }

        if let midiCommand = MIDICommandParser.parse(sendText) {
            let effectiveChannel = MIDIChannelSettings.resolvedChannel(
                for: midiCommand,
                defaultChannel: defaultMIDIChannel
            )
            return MainGridAutomaticMIDILabel(
                content: .note(name: midiCommand.noteDisplayName, velocity: midiCommand.velocity, mode: midiCommand.mode),
                channel: effectiveChannel
            ).text
        }

        if MIDIControlChangeParser.parse(sendText) != nil {
            return automaticMIDILabel(for: entry, defaultMIDIChannel: defaultMIDIChannel)?.text
        }

        let displayText = String(sendText.dropFirst())

        if displayText.lowercased() == "home" {
            return displayText
        }

        let commandParts = displayText.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
        if commandParts.count == 2 {
            let command = commandParts[0].lowercased()
            let operand = commandParts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if (command == "app" || command == "cb" || command == "spk"), !operand.isEmpty {
                return displayText
            }
        }

        let shortcutParts = displayText.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
        if shortcutParts.count == 2 {
            let shortcutCommand = shortcutParts[0].lowercased()
            let shortcutName = shortcutParts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if (shortcutCommand == "sc" || shortcutCommand == "shortcut"), !shortcutName.isEmpty {
                return displayText
            }
        }

        if normalizedNumericBluetoothCommand(
            from: displayText,
            command: "out",
            expectedArgumentCount: 2
        ) != nil {
            return displayText
        }

        if normalizedNumericBluetoothCommand(
            from: displayText,
            command: "pwm",
            expectedArgumentCount: 3
        ) != nil {
            return displayText
        }

        return nil
    }

    private func automaticMIDILabel(
        for entry: FunctionKeyEntry,
        index: Int? = nil,
        defaultMIDIChannel: Int
    ) -> MainGridAutomaticMIDILabel? {
        guard resolvedAlternateDisplayText(for: entry)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty,
              navigationCommandDefaultLabel(for: entry.primaryDisplayText) == nil,
              entry.sendTexts.count == 1,
              let sendText = entry.sendTexts.first else {
            return nil
        }

        if let command = MIDIControlChangeParser.parse(sendText) {
            let value: String
            switch command.mode {
            case .oneShot:
                value = command.valueDisplayText
            case .hold, .toggle:
                if let index,
                   let lastAcceptedValue = midiCCDisplayValue(for: entry, index: index) {
                    value = "\(lastAcceptedValue)"
                } else {
                    value = "\(command.startValue)-\(command.endValue)"
                }
            }
            return MainGridAutomaticMIDILabel(
                content: .controlChange(name: command.controllerDisplayName, value: value, mode: command.mode),
                channel: MIDIChannelSettings.resolvedChannel(
                    channelOverride: command.channelOverride,
                    defaultChannel: defaultMIDIChannel
                )
            )
        }

        guard let midiCommand = MIDICommandParser.parse(sendText) else { return nil }
        return MainGridAutomaticMIDILabel(
            content: .note(name: midiCommand.noteDisplayName, velocity: midiCommand.velocity, mode: midiCommand.mode),
            channel: MIDIChannelSettings.resolvedChannel(
                for: midiCommand,
                defaultChannel: defaultMIDIChannel
            )
        )
    }

    func isHexColorPrefix(_ text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.count == 6 else {
            return false
        }

        let hexDigits = "0123456789abcdefABCDEF"
        return trimmedText.allSatisfy { hexDigits.contains($0) }
    }
    func sendMainGridEntry(_ entry: FunctionKeyEntry, defaultMIDIChannel: Int) {
			
        guard mainGridButtonMode != .disabled else {
            return
        }

        let outputSourceMetadata = outputSourceMetadata(for: entry)

        if isMIDIControlChangeCommandForGridEntry(entry) {
            guard let command = midiControlChangeCommandForGridEntry(entry),
                  command.mode == .oneShot,
                  mainGridButtonMode.sendsBluetooth else {
                return
            }

            guard outputMode == .mac, macConnection.canSend else {
                showMIDIOutputUnavailableWarning()
                return
            }

            let channel = MIDIChannelSettings.resolvedChannel(
                channelOverride: command.channelOverride,
                defaultChannel: defaultMIDIChannel
            )
            _ = macConnection.sendAuthenticatedCommand(
                "MIDI:CC:\(command.controller):\(command.value):\(channel)"
            )
            return
        }

        if isMIDICommandForGridEntry(entry) {
            return
        }

        // MARK: - BM:🅱️  Main Screen button command logging
        if db_btnCode {
            let command = entry.rawLine.components(separatedBy: "::").first ?? entry.rawLine
            print("🐞 \(command)")

            for token in entry.sendTexts {
                let classificationLabel: String

                switch commandClassification(for: token) {
                case .internalCommand:
                    classificationLabel = "internal"
                case .file:
                    classificationLabel = "file"
                case .external:
                    classificationLabel = "external"
                }

                print("🐞 \(token) → \(classificationLabel)")
            }
        }

        if mainGridButtonMode.speaksText {
            speakMainGridEntry(entry)
        }

        let shouldGoBackToPreviousDocument = targetBackDocumentCommandForGridEntry(entry)
        let shouldGoForwardToNextDocument = targetForwardDocumentCommandForGridEntry(entry)
        let shouldSelectPreviousDocument = targetPreviousDocumentCommandForGridEntry(entry)
        let shouldSelectNextDocument = targetNextDocumentCommandForGridEntry(entry)

        if entry.sendTexts.isEmpty {
            runDocumentNavigationCommandIfNeeded(
                shouldGoBackToPreviousDocument: shouldGoBackToPreviousDocument,
                shouldGoForwardToNextDocument: shouldGoForwardToNextDocument,
                shouldSelectPreviousDocument: shouldSelectPreviousDocument,
                shouldSelectNextDocument: shouldSelectNextDocument
            )
            return
        }

        if containsWaitCommand(in: entry.sendTexts) {
            startWaitChainCommandTokens(
                entry.sendTexts,
                sourceEntry: entry,
                respectsBluetoothMode: true
            )
            return
        }

        if entry.sendTexts.contains(where: isStopMediaCommandText) {
            stopAllMainGridMedia()
            return
        }

        let bluetoothSendTexts = bluetoothSendTexts(for: entry)
        let targetDocumentName = targetDocumentNameForGridEntry(entry)
        let targetURL = targetURLForGridEntry(entry)
        let targetSoundResult = targetSoundRequestForGridEntry(entry)
        let targetSoundRequest: MainGridSoundRequest?
        switch targetSoundResult {
        case .request(let request):
            targetSoundRequest = request
        case .invalidVolume:
            showInvalidSoundVolumeAlert()
            return
        case nil:
            targetSoundRequest = nil
        }
        let targetAppURL = targetAppURLForGridEntry(entry)
        let targetClipboardText = targetClipboardTextForGridEntry(entry)
        let targetPreviewFilename = targetPreviewFilenameForGridEntry(entry)
        let targetSpokenFilename = targetSpokenFilenameForGridEntry(entry)
        let targetSpokenText = targetSpokenTextForGridEntry(entry)
        let targetShortcutURL = targetShortcutURLForGridEntry(entry)
        if targetDocumentName != nil {
        } else if targetPreviewFilename != nil {
        } else {
        }
        let hasPostBluetoothChainCommand = targetSoundRequest != nil ||
            targetSpokenText != nil ||
            targetSpokenFilename != nil ||
            targetShortcutURL != nil
        var didSendBluetooth = false

        func sendBluetoothIfNeeded() -> Bool {
            guard !didSendBluetooth else {
                return true
            }

            guard sendKeyboardOutputTokens(
                bluetoothSendTexts,
                respectsButtonMode: true,
                sourceMetadata: outputSourceMetadata
            ) else {
                return false
            }

            if mainGridButtonMode.sendsBluetooth && !bluetoothSendTexts.isEmpty {
                didSendBluetooth = true
            }
            return true
        }

        if let targetURL {
            UIApplication.shared.open(targetURL)
            return
        }

        if let targetAppURL {
            UIApplication.shared.open(targetAppURL) { success in
                guard !success else {
                    return
                }

                alertTitle = "App Not Available"
                renameAlertMessage = "Couldn't open \(targetAppURL.absoluteString)."
            }
            return
        }

        if let targetClipboardText {
            UIPasteboard.general.string = targetClipboardText
        }

        if let targetPreviewFilename {
            openPreviewFile(named: targetPreviewFilename)
        }

        if hasPostBluetoothChainCommand {
            guard sendBluetoothIfNeeded() else {
                return
            }
        }

        if let targetSoundRequest {
            playMainGridSound(
                named: targetSoundRequest.filename,
                volumePercentage: targetSoundRequest.volumePercentage
            )
        }

        if let targetSpokenText {
            speakMainGridText(targetSpokenText)
        } else if let targetSpokenFilename {
            alertTitle = "File Not Found"
            renameAlertMessage = "Couldn't find \(targetSpokenFilename.lowercased())."
        }

        if let targetShortcutURL {
            UIApplication.shared.open(targetShortcutURL)
        }

        runDocumentNavigationCommandIfNeeded(
            shouldGoBackToPreviousDocument: shouldGoBackToPreviousDocument,
            shouldGoForwardToNextDocument: shouldGoForwardToNextDocument,
            shouldSelectPreviousDocument: shouldSelectPreviousDocument,
            shouldSelectNextDocument: shouldSelectNextDocument
        )

        if let targetDocumentName {
            let didSelectDocument = selectDocumentNamedFromGrid(targetDocumentName)
            guard didSelectDocument else {
                alertTitle = "File Not Found"
                renameAlertMessage = "Couldn't find \(targetDocumentName.lowercased())."
                return
            }
        }

        _ = sendBluetoothIfNeeded()
    }

    func midiCommandForGridEntry(_ entry: FunctionKeyEntry) -> MIDICommand? {
        guard entry.sendTexts.count == 1 else {
            return nil
        }

        return MIDICommandParser.parse(entry.sendTexts[0])
    }

    private func isMIDICommandForGridEntry(_ entry: FunctionKeyEntry) -> Bool {
        entry.sendTexts.contains { sendText in
            sendText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: \.isWhitespace)
                .first == ".midi"
        }
    }

    func midiControlChangeCommandForGridEntry(
        _ entry: FunctionKeyEntry
    ) -> MIDIControlChangeCommand? {
        guard entry.sendTexts.count == 1 else {
            return nil
        }

        return MIDIControlChangeParser.parse(entry.sendTexts[0])
    }

    private func isMIDIControlChangeCommandForGridEntry(_ entry: FunctionKeyEntry) -> Bool {
        entry.sendTexts.contains { sendText in
            sendText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: \.isWhitespace)
                .first == ".cc"
        }
    }

    func sendMIDINoteOnFromTouch(_ identity: MIDINoteIdentity, velocity: UInt8) -> Bool {
        guard identity.note <= 127,
              (1...127).contains(velocity),
              MIDIChannelSettings.validRange.contains(Int(identity.channel)),
              !isGridEditModeEnabled,
              mainGridButtonMode.sendsBluetooth,
              outputMode == .mac,
              macConnection.canSend else {
            return false
        }

        return macConnection.sendAuthenticatedCommand(
            "MIDI:NOTE_ON:\(identity.note):\(velocity):\(identity.channel)"
        )
    }

    func sendMIDINoteOffFromTouch(_ identity: MIDINoteIdentity) -> Bool {
        guard identity.note <= 127,
              MIDIChannelSettings.validRange.contains(Int(identity.channel)),
              macConnection.canSend else {
            return false
        }

        return macConnection.sendAuthenticatedCommand(
            "MIDI:NOTE_OFF:\(identity.note):\(identity.channel)"
        )
    }

    private func runDocumentNavigationCommandIfNeeded(
        shouldGoBackToPreviousDocument: Bool,
        shouldGoForwardToNextDocument: Bool,
        shouldSelectPreviousDocument: Bool,
        shouldSelectNextDocument: Bool
    ) {
        if shouldGoBackToPreviousDocument {
            goBackToPreviousDocument()
        }

        if shouldGoForwardToNextDocument {
            goForwardToNextDocument()
        }

        if shouldSelectPreviousDocument {
            selectPreviousDocument()
        }

        if shouldSelectNextDocument {
            selectNextDocument()
        }
    }

    func bluetoothSendTexts(for entry: FunctionKeyEntry) -> [String] {
        entry.sendTexts
            .filter { sendText in
                targetDocumentNameForSendText(sendText) == nil &&
                targetURLForSendText(sendText) == nil &&
                targetShortcutURLForSendText(sendText) == nil &&
                targetSoundRequestForSendText(sendText) == nil &&
                targetSpokenTextForSendText(sendText) == nil &&
                targetSpokenFilenameForSendText(sendText) == nil &&
                targetAppURLForSendText(sendText) == nil &&
                targetClipboardTextForSendText(sendText) == nil &&
                targetPreviewFilenameForSendText(sendText) == nil &&
                !isStopMediaCommandText(sendText) &&
                !isBackDocumentCommandText(sendText) &&
                !isForwardDocumentCommandText(sendText) &&
                !isPreviousDocumentCommandText(sendText) &&
                !isNextDocumentCommandText(sendText) &&
                !isWaitCommandText(sendText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) &&
                targetWidgetDescriptorForSendText(sendText) == nil
            }
            .map(normalizedBluetoothSendText)
    }

    func containsWaitCommand(in actionTokens: [String]) -> Bool {
        actionTokens.contains { actionToken in
            isWaitCommandText(actionToken.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
    }

    @MainActor
    func startWaitChainCommandTokens(
        _ actionTokens: [String],
        sourceEntry: FunctionKeyEntry?,
        respectsBluetoothMode: Bool
    ) {
        let sequenceID = UUID()
        let outputSourceMetadata = sourceEntry.map(outputSourceMetadata(for:))
        let task = Task { @MainActor in
            defer {
                activeWaitChainTasks.removeValue(forKey: sequenceID)
            }

            await runWaitChainCommandTokens(
                actionTokens,
                sourceMetadata: outputSourceMetadata,
                respectsBluetoothMode: respectsBluetoothMode
            )
        }

        activeWaitChainTasks[sequenceID] = task
    }

    @MainActor
    func cancelAllWaitChainCommands() {
        let tasks = Array(activeWaitChainTasks.values)
        activeWaitChainTasks.removeAll()

        for task in tasks {
            task.cancel()
        }
    }

    @MainActor
    func runWaitChainCommandTokens(
        _ actionTokens: [String],
        sourceMetadata: ESPOutputSourceMetadata?,
        respectsBluetoothMode: Bool
    ) async {
        var pendingModifierTokens: [String] = []
        defer {
            pendingModifierTokens.removeAll()
        }

        for actionToken in actionTokens {
            guard !Task.isCancelled else {
                return
            }

            let trimmedActionToken = actionToken.trimmingCharacters(in: .whitespacesAndNewlines)
            let loweredActionToken = trimmedActionToken.lowercased()
            guard !trimmedActionToken.isEmpty else {
                continue
            }

            if isWaitCommandText(loweredActionToken) {
                pendingModifierTokens.removeAll()
                guard let waitDuration = waitDurationForSendText(trimmedActionToken) else {
                    alertTitle = "Invalid wait"
                    renameAlertMessage = "Use .wait followed by seconds,\nfor example .wait 1 or .wait 0.5."
                    return
                }

                let nanoseconds = min(waitDuration * 1_000_000_000, Double(UInt64.max))
                guard !Task.isCancelled else {
                    return
                }

                do {
                    try await Task.sleep(nanoseconds: UInt64(nanoseconds.rounded()))
                } catch {
                    return
                }

                guard !Task.isCancelled else {
                    return
                }
                continue
            }

            if isStopMediaCommandText(trimmedActionToken) {
                pendingModifierTokens.removeAll()
                stopAllMainGridMedia()
                return
            }

            if let targetURL = targetURLForSendText(trimmedActionToken) {
                pendingModifierTokens.removeAll()
                await UIApplication.shared.open(targetURL)
                continue
            }

            if let targetAppURL = targetAppURLForSendText(trimmedActionToken) {
                pendingModifierTokens.removeAll()
                UIApplication.shared.open(targetAppURL) { success in
                    guard !success else {
                        return
                    }

                    alertTitle = "App Not Available"
                    renameAlertMessage = "Couldn't open \(targetAppURL.absoluteString)."
                }
                continue
            }

            if let targetClipboardText = targetClipboardTextForSendText(trimmedActionToken) {
                pendingModifierTokens.removeAll()
                UIPasteboard.general.string = targetClipboardText
                continue
            }

            if let targetPreviewFilename = targetPreviewFilenameForSendText(trimmedActionToken) {
                pendingModifierTokens.removeAll()
                openPreviewFile(named: targetPreviewFilename)
                continue
            }

            if let targetSoundResult = targetSoundRequestForSendText(trimmedActionToken) {
                pendingModifierTokens.removeAll()
                switch targetSoundResult {
                case .request(let request):
                    playMainGridSound(
                        named: request.filename,
                        volumePercentage: request.volumePercentage
                    )
                case .invalidVolume:
                    showInvalidSoundVolumeAlert()
                    return
                }
                continue
            }

            if let targetSpokenText = targetSpokenTextForSendText(trimmedActionToken) {
                pendingModifierTokens.removeAll()
                speakMainGridText(targetSpokenText)
                continue
            } else if let targetSpokenFilename = targetSpokenFilenameForSendText(trimmedActionToken) {
                pendingModifierTokens.removeAll()
                alertTitle = "File Not Found"
                renameAlertMessage = "Couldn't find \(targetSpokenFilename.lowercased())."
                return
            }

            if let targetShortcutURL = targetShortcutURLForSendText(trimmedActionToken) {
                pendingModifierTokens.removeAll()
                await UIApplication.shared.open(targetShortcutURL)
                continue
            }

            if isBackDocumentCommandText(trimmedActionToken) {
                pendingModifierTokens.removeAll()
                goBackToPreviousDocument()
                continue
            }

            if isForwardDocumentCommandText(trimmedActionToken) {
                pendingModifierTokens.removeAll()
                goForwardToNextDocument()
                continue
            }

            if isPreviousDocumentCommandText(trimmedActionToken) {
                pendingModifierTokens.removeAll()
                selectPreviousDocument()
                continue
            }

            if isNextDocumentCommandText(trimmedActionToken) {
                pendingModifierTokens.removeAll()
                selectNextDocument()
                continue
            }

            if let targetDocumentName = targetDocumentNameForSendText(trimmedActionToken) {
                pendingModifierTokens.removeAll()
                let didSelectDocument = selectDocumentNamedFromGrid(targetDocumentName)
                guard didSelectDocument else {
                    alertTitle = "File Not Found"
                    renameAlertMessage = "Couldn't find \(targetDocumentName.lowercased())."
                    return
                }
                continue
            }

            if targetWidgetDescriptorForSendText(trimmedActionToken) != nil {
                pendingModifierTokens.removeAll()
                continue
            }

            let bluetoothSendText = normalizedBluetoothSendText(trimmedActionToken)
            if KeyboardModifier(token: bluetoothSendText) != nil {
                pendingModifierTokens.append(bluetoothSendText)
                continue
            }

            if !pendingModifierTokens.isEmpty {
                let keyboardCommandTokens = pendingModifierTokens + [bluetoothSendText]
                let didSendKeyboardCommand = sendKeyboardOutputTokens(
                    keyboardCommandTokens,
                    respectsButtonMode: respectsBluetoothMode,
                    sourceMetadata: sourceMetadata
                )
                pendingModifierTokens.removeAll()

                guard didSendKeyboardCommand else {
                    return
                }
                continue
            }

            guard sendBluetoothCommandToken(
                trimmedActionToken,
                respectsBluetoothMode: respectsBluetoothMode,
                sourceMetadata: sourceMetadata
            ) else {
                return
            }
        }

    }

    private func sendBluetoothCommandToken(
        _ actionToken: String,
        respectsBluetoothMode: Bool,
        sourceMetadata: ESPOutputSourceMetadata?
    ) -> Bool {
        let bluetoothSendText = normalizedBluetoothSendText(actionToken)
        guard !bluetoothSendText.isEmpty else {
            return true
        }

        return sendKeyboardOutputTokens(
            [bluetoothSendText],
            respectsButtonMode: respectsBluetoothMode,
            sourceMetadata: sourceMetadata
        )
    }

    func sendKeyboardOutputTokens(
        _ tokens: [String],
        respectsButtonMode: Bool,
        sourceMetadata: ESPOutputSourceMetadata? = nil
    ) -> Bool {
        guard !respectsButtonMode || mainGridButtonMode.sendsBluetooth else {
            return true
        }

        let keyboardOutputTokens = tokens
            .compactMap { token in
                let normalizedToken = normalizedBluetoothSendText(token)
                if let smartKeycode = canonicalSmartScriptKeycode(normalizedToken) {
                    return smartKeycode
                }
                return normalizedToken.hasPrefix(".") ? nil : normalizedToken
            }

        guard !keyboardOutputTokens.isEmpty else {
            return true
        }

        ESPOutputProbe.printGeneratedItems(
            keyboardOutputTokens,
            sourceMetadata: sourceMetadata
        )

        switch outputMode {
        case .none:
            alertTitle = "Not connected"
            renameAlertMessage = "Select Mac or ESP32 before sending keyboard output."
            return false
        case .mac:
            guard macConnection.sendSmartScriptKeyboardTokens(keyboardOutputTokens) else {
                alertTitle = "Mac helper not connected"
                renameAlertMessage = "ESP needs to connect to ESP Mac Helper before sending keyboard output to the Mac."
                return false
            }

            return true
        case .esp32:
            break
        }

        guard ble.isConnected else {
            alertTitle = "Bluetooth not connected"
            renameAlertMessage = "Bluetooth needs to be connected\nin order to send data to the ESP32."
            return false
        }

        guard keyboardOutputTokens.allSatisfy(isBluetoothSendableText(_:)) else {
            showBluetoothUnsupportedTextBlockedPopup()
            return false
        }

        for keyboardOutputToken in keyboardOutputTokens {
            ble.sendLine(keyboardOutputToken)
        }

        return true
    }

    func speakMainGridEntry(_ entry: FunctionKeyEntry) {
        let spokenText = spokenTitle(for: entry)
            .replacingOccurrences(of: "\n", with: ", ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        speakMainGridText(spokenText)
    }

    func speakMainGridText(_ text: String) {
        guard !isSpkRecEnabled else {
            return
        }

        let spokenText = speechSynthesisText(from: text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spokenText.isEmpty else {
            return
        }

        stopSpokenGridText()
        let requestID = UUID()
        speechPlaybackRequestID = requestID
        speechSynthesisActive = true

        Task {
            guard await activateAudioSessionForSpeechPlayback() else {
                guard speechPlaybackRequestID == requestID else {
                    return
                }
                speechSynthesisActive = false
                return
            }

            guard speechPlaybackRequestID == requestID else {
                return
            }

            let utterance = AVSpeechUtterance(string: spokenText)
            utterance.voice = resolvedSpeechVoice
            utterance.rate = Float(clampedTextToSpeechRate)
            let playbackDelegate = MainGridSpeechPlaybackDelegate(
                requestID: requestID,
                utterance: utterance
            ) { completedRequestID in
                guard speechPlaybackRequestID == completedRequestID else {
                    return
                }
                speechSynthesisActive = false
                speechPlaybackDelegate = nil
            }
            speechPlaybackDelegate = playbackDelegate
            speechSynthesizer.delegate = playbackDelegate
            speechSynthesizer.speak(utterance)
        }
    }

    func speechSynthesisText(from text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func spokenTitle(for entry: FunctionKeyEntry) -> String {
        if let spokenCommandText = targetSpokenTextForGridEntry(entry) {
            return spokenCommandText
        }

        let rightTitle = resolvedAlternateDisplayText(for: entry)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !rightTitle.isEmpty {
            return speechMatchDisplayText(from: rightTitle)
        }

        if targetWidgetDescriptorForGridEntry(entry) != nil {
            return ""
        }

        let leftTitle = displayText(from: entry.primaryDisplayText)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !leftTitle.isEmpty else {
            return ""
        }

        return speechMatchDisplayText(from: leftTitle)
    }

    var resolvedSpeechVoice: AVSpeechSynthesisVoice? {
        if let selectedVoice = AVSpeechSynthesisVoice(identifier: selectedTextToSpeechVoiceIdentifier) {
            return selectedVoice
        }

        return AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
    }

    var clampedTextToSpeechRate: Double {
        min(max(textToSpeechRate, 0.2), 0.7)
    }

    func targetDocumentNameForGridEntry(_ entry: FunctionKeyEntry) -> String? {
        entry.sendTexts
            .compactMap { targetDocumentNameForSendText($0) }
            .first
    }

    func targetBackDocumentCommandForGridEntry(_ entry: FunctionKeyEntry) -> Bool {
        documentNavigationCommandTexts(for: entry).contains(where: isBackDocumentCommandText)
    }

    func targetForwardDocumentCommandForGridEntry(_ entry: FunctionKeyEntry) -> Bool {
        documentNavigationCommandTexts(for: entry).contains(where: isForwardDocumentCommandText)
    }

    func targetPreviousDocumentCommandForGridEntry(_ entry: FunctionKeyEntry) -> Bool {
        documentNavigationCommandTexts(for: entry).contains(where: isPreviousDocumentCommandText)
    }

    func targetNextDocumentCommandForGridEntry(_ entry: FunctionKeyEntry) -> Bool {
        documentNavigationCommandTexts(for: entry).contains(where: isNextDocumentCommandText)
    }

    func documentNavigationCommandTexts(for entry: FunctionKeyEntry) -> [String] {
        entry.sendTexts
    }

    func isBackDocumentCommandText(_ sendText: String) -> Bool {
        sendText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == ".back"
    }

    func isForwardDocumentCommandText(_ sendText: String) -> Bool {
        sendText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == ".forw"
    }

    func isPreviousDocumentCommandText(_ sendText: String) -> Bool {
        sendText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == ".prev"
    }

    func isNextDocumentCommandText(_ sendText: String) -> Bool {
        sendText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == ".next"
    }

    private func navigationCommandDefaultLabel(for title: String) -> String? {
        switch title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case ".prev":
            return "prev"
        case ".next":
            return "next"
        case ".back":
            return "back"
        case ".forw":
            return "forw"
        default:
            return nil
        }
    }

    func targetDocumentNameForSendText(_ sendText: String) -> String? {
        let trimmedSendText = sendText.trimmingCharacters(in: .whitespacesAndNewlines)
        let loweredSendText = trimmedSendText.lowercased()
        guard speechCommandPrefixLength(for: trimmedSendText) == nil else {
            return nil
        }
        guard !isWaitCommandText(loweredSendText) else {
            return nil
        }
        guard !isShortcutCommandText(loweredSendText) else {
            return nil
        }

        if loweredSendText == ".home" {
            return "home.screen"
        }

        let pathExtension = URL(fileURLWithPath: trimmedSendText).pathExtension.lowercased()
        if pathExtension == "s" {
            return URL(fileURLWithPath: trimmedSendText)
                .deletingPathExtension()
                .appendingPathExtension(screenDocumentFileExtension)
                .lastPathComponent
        }

        if pathExtension == screenDocumentFileExtension {
            return trimmedSendText
        }

        return nil
    }

    func targetURLForGridEntry(_ entry: FunctionKeyEntry) -> URL? {
        entry.sendTexts.compactMap(targetURLForSendText).first
    }

    func targetClipboardTextForGridEntry(_ entry: FunctionKeyEntry) -> String? {
        entry.sendTexts.compactMap(targetClipboardTextForSendText).first
    }

    func targetPreviewFilenameForGridEntry(_ entry: FunctionKeyEntry) -> String? {
        entry.sendTexts.compactMap(targetPreviewFilenameForSendText).first
    }

    func targetAppURLForGridEntry(_ entry: FunctionKeyEntry) -> URL? {
        entry.sendTexts.compactMap(targetAppURLForSendText).first
    }

    func targetShortcutURLForGridEntry(_ entry: FunctionKeyEntry) -> URL? {
        entry.sendTexts.compactMap(targetShortcutURLForSendText).first
    }

    func targetURLForSendText(_ sendText: String) -> URL? {
        let trimmedSendText = sendText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSendText: String

        if trimmedSendText.lowercased().hasPrefix("https//") {
            normalizedSendText = "https://" + trimmedSendText.dropFirst("https//".count)
        } else if trimmedSendText.lowercased().hasPrefix("http//") {
            normalizedSendText = "http://" + trimmedSendText.dropFirst("http//".count)
        } else {
            normalizedSendText = trimmedSendText
        }

        let loweredSendText = normalizedSendText.lowercased()

        guard loweredSendText.hasPrefix("http://") || loweredSendText.hasPrefix("https://") else {
            return nil
        }

        if let url = URL(string: normalizedSendText) {
            return url
        }

        guard let encodedSendText = normalizedSendText.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) else {
            return nil
        }

        return URL(string: encodedSendText)
    }

    func targetSoundFilenameForGridEntry(_ entry: FunctionKeyEntry) -> String? {
        entry.sendTexts.compactMap(targetSoundFilenameForSendText).first
    }

    func targetSoundRequestForGridEntry(_ entry: FunctionKeyEntry) -> MainGridSoundRequestParseResult? {
        entry.sendTexts.compactMap(targetSoundRequestForSendText).first
    }

    func isSimpleOrdinarySoundEntry(_ entry: FunctionKeyEntry) -> Bool {
        guard entry.sendTexts.count == 1,
              case .request = targetSoundRequestForSendText(entry.sendTexts[0]) else {
            return false
        }

        return true
    }

    func handleSimpleOrdinarySoundSingleTap(_ entry: FunctionKeyEntry, index: Int) {
        guard mainGridButtonMode != .disabled,
              entry.sendTexts.count == 1,
              case .request(let request) = targetSoundRequestForSendText(entry.sendTexts[0]) else {
            return
        }

        if mainGridButtonMode.speaksText {
            speakMainGridEntry(entry)
        }

        playMainGridSound(
            named: request.filename,
            volumePercentage: request.volumePercentage,
            gestureOwnerID: mainGridOrdinarySoundGestureOwnerID(index: index),
            gestureRequest: request
        )
    }

    func handleSimpleOrdinarySoundDoubleTap(_ entry: FunctionKeyEntry, index: Int) {
        guard mainGridButtonMode != .disabled,
              entry.sendTexts.count == 1,
              case .request(let request) = targetSoundRequestForSendText(entry.sendTexts[0]) else {
            return
        }

        if mainGridButtonMode.speaksText {
            speakMainGridEntry(entry)
        }

        let ownerID = mainGridOrdinarySoundGestureOwnerID(index: index)
        guard ordinarySoundGestureOwnerID == ownerID else {
            playMainGridSound(
                named: request.filename,
                volumePercentage: request.volumePercentage,
                gestureOwnerID: ownerID,
                gestureRequest: request
            )
            return
        }

        switch ordinarySoundPlaybackPhase {
        case .preparing:
            ordinarySoundPlaybackPhase = .paused
        case .playing:
            soundEffectPlayer?.pause()
            ordinarySoundPlaybackPhase = .paused
        case .paused:
            if let soundEffectPlayer {
                guard soundEffectPlayer.play() else {
                    stopMainGridSoundPlayback()
                    alertTitle = "Sound Error"
                    renameAlertMessage = "Couldn't play \(request.filename)."
                    return
                }
                ordinarySoundPlaybackPhase = .playing
            } else {
                ordinarySoundPlaybackPhase = .preparing
            }
        case .stopped:
            playMainGridSound(
                named: request.filename,
                volumePercentage: request.volumePercentage,
                gestureOwnerID: ownerID,
                gestureRequest: request
            )
        }
    }

    private func mainGridOrdinarySoundGestureOwnerID(index: Int) -> String {
        "\(selectedDocumentName)#\(index)"
    }

    private func clearMainGridOrdinarySoundGestureState(matching requestID: UUID? = nil) {
        if let requestID, ordinarySoundGestureRequestID != requestID {
            return
        }

        ordinarySoundGestureOwnerID = nil
        ordinarySoundGestureRequest = nil
        ordinarySoundGestureRequestID = nil
        ordinarySoundPlaybackPhase = .stopped
    }

    func targetSpokenTextForGridEntry(_ entry: FunctionKeyEntry) -> String? {
        entry.sendTexts.compactMap(targetSpokenTextForSendText).first
    }

    func targetSpokenFilenameForGridEntry(_ entry: FunctionKeyEntry) -> String? {
        entry.sendTexts.compactMap(targetSpokenFilenameForSendText).first
    }

    func targetWidgetDescriptorForGridEntry(_ entry: FunctionKeyEntry) -> MainGridWidgetDescriptor? {
        entry.sendTexts.compactMap(targetWidgetDescriptorForSendText).first
    }

    func targetAppURLForSendText(_ sendText: String) -> URL? {
        let trimmedSendText = sendText.trimmingCharacters(in: .whitespacesAndNewlines)
        let loweredSendText = trimmedSendText.lowercased()

        let appCommandLength: Int
        if loweredSendText.hasPrefix(".app ") {
            appCommandLength = 5
        } else if loweredSendText.hasPrefix("app ") {
            appCommandLength = 4
        } else {
            return nil
        }

        let appName = String(trimmedSendText.dropFirst(appCommandLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appName.isEmpty else {
            return nil
        }

        if appName.contains(":") {
            return URL(string: appName)
        }

        switch appName
            .lowercased()
            .replacingOccurrences(of: " ", with: "") {
        case "notes", "applenotes":
            return URL(string: "mobilenotes://")
        case "mail":
            return URL(string: "message://")
        case "messages", "imessage":
            return URL(string: "sms:")
        case "facetime":
            return URL(string: "facetime://")
        case "maps":
            return URL(string: "maps://")
        case "music":
            return URL(string: "music://")
        case "calendar":
            return URL(string: "calshow://")
        case "phone":
            return URL(string: "tel://")
        default:
            return URL(string: "\(appName.lowercased().replacingOccurrences(of: " ", with: ""))://")
        }
    }

    func targetShortcutURLForSendText(_ sendText: String) -> URL? {
        let trimmedSendText = sendText.trimmingCharacters(in: .whitespacesAndNewlines)
        let loweredSendText = trimmedSendText.lowercased()
        let shortcutName: String

        if loweredSendText.hasPrefix("sc ") {
            shortcutName = String(trimmedSendText.dropFirst(3))
        } else if loweredSendText.hasPrefix("shortcut ") {
            shortcutName = String(trimmedSendText.dropFirst(9))
        } else {
            return nil
        }

        let trimmedShortcutName = shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedShortcutName.isEmpty else {
            return nil
        }

        // Shortcuts expects the shortcut name in the URL query. Keep normal
        // letters readable, but encode spaces as %20 and protect query
        // separators so names like "hello & bye" remain one shortcut name.
        var allowedCharacters = CharacterSet.urlQueryAllowed
        allowedCharacters.remove(charactersIn: "&=+?")
        guard let encodedShortcutName = trimmedShortcutName.addingPercentEncoding(withAllowedCharacters: allowedCharacters) else {
            return nil
        }

        return URL(string: "shortcuts://run-shortcut?name=\(encodedShortcutName)")
    }

    func targetClipboardTextForSendText(_ sendText: String) -> String? {
        let trimmedSendText = sendText.trimmingCharacters(in: .whitespacesAndNewlines)
        let loweredSendText = trimmedSendText.lowercased()

        let clipboardCommandLength: Int
        if loweredSendText.hasPrefix(".cb ") {
            clipboardCommandLength = 4
        } else if loweredSendText.hasPrefix("cb ") {
            clipboardCommandLength = 3
        } else {
            return nil
        }

        let quoteCharacters = CharacterSet(charactersIn: "'\"‘’“”`´")
        let clipboardText = String(trimmedSendText.dropFirst(clipboardCommandLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .unicodeScalars
            .filter { !quoteCharacters.contains($0) }
            .map(String.init)
            .joined()
            .replacingOccurrences(of: "\\", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clipboardText.isEmpty ? nil : clipboardText
    }

    func targetPreviewFilenameForSendText(_ sendText: String) -> String? {
        let trimmedSendText = sendText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard speechCommandPrefixLength(for: trimmedSendText) == nil else {
            return nil
        }

        let pathExtension = URL(fileURLWithPath: trimmedSendText).pathExtension.lowercased()
        guard supportedPreviewExtensions.contains(pathExtension) else {
            return nil
        }

        return trimmedSendText.isEmpty ? nil : trimmedSendText
    }

    func targetSoundFilenameForSendText(_ sendText: String) -> String? {
        guard case .request(let request) = targetSoundRequestForSendText(sendText) else {
            return nil
        }

        return request.filename
    }

    func targetSoundRequestForSendText(_ sendText: String) -> MainGridSoundRequestParseResult? {
        let trimmedSendText = sendText.trimmingCharacters(in: .whitespacesAndNewlines)
        let loweredSendText = trimmedSendText.lowercased()
        let soundArguments: String

        guard speechCommandPrefixLength(for: trimmedSendText) == nil,
              !loweredSendText.hasPrefix("amb "),
              !loweredSendText.hasPrefix("ambient "),
              !loweredSendText.hasPrefix("cb "),
              !loweredSendText.hasPrefix(".cb "),
              !isWaitCommandText(loweredSendText),
              !isShortcutCommandText(loweredSendText),
              !isBareWidgetCommandText(loweredSendText) else {
            return nil
        }

        if loweredSendText.hasPrefix("snd ") {
            soundArguments = String(trimmedSendText.dropFirst(4))
        } else {
            soundArguments = trimmedSendText
        }

        let normalizedArguments = normalizedSoundFilename(soundArguments)
        guard !normalizedArguments.isEmpty else {
            return nil
        }

        if hasSupportedSoundExtension(normalizedArguments) {
            return .request(MainGridSoundRequest(
                filename: normalizedArguments,
                volumePercentage: 100
            ))
        }

        let components = normalizedArguments.split(whereSeparator: { $0.isWhitespace })
        guard components.count > 1, let volumeToken = components.last else {
            return nil
        }

        let filename = normalizedSoundFilename(String(components.dropLast().joined(separator: " ")))
        guard hasSupportedSoundExtension(filename) else {
            return nil
        }

        guard let volumePercentage = Int(volumeToken),
              (0...100).contains(volumePercentage) else {
            return .invalidVolume
        }

        return .request(MainGridSoundRequest(
            filename: filename,
            volumePercentage: volumePercentage
        ))
    }

    func targetSpokenTextForSendText(_ sendText: String) -> String? {
        let trimmedSendText = sendText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let commandPrefixLength = speechCommandPrefixLength(for: trimmedSendText) else {
            return nil
        }

        let spokenText = displayText(from: String(trimmedSendText.dropFirst(commandPrefixLength)))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spokenText.isEmpty else {
            return nil
        }

        if let spokenFilename = targetSpokenFilenameForSendText(trimmedSendText) {
            return spokenTextFileContents(named: spokenFilename)
        }

        return spokenText
    }

    func targetSpokenFilenameForSendText(_ sendText: String) -> String? {
        let trimmedSendText = sendText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let commandPrefixLength = speechCommandPrefixLength(for: trimmedSendText) else {
            return nil
        }

        let spokenFilename = displayText(from: String(trimmedSendText.dropFirst(commandPrefixLength)))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard spokenFilename.lowercased().hasSuffix(".txt") else {
            return nil
        }

        return spokenFilename.isEmpty ? nil : spokenFilename
    }

    private func speechCommandPrefixLength(for sendText: String) -> Int? {
        let loweredSendText = sendText.lowercased()

        for command in [".spk", "spk"] where loweredSendText.hasPrefix(command) {
            guard loweredSendText.count > command.count else {
                continue
            }

            let separatorIndex = loweredSendText.index(loweredSendText.startIndex, offsetBy: command.count)
            if loweredSendText[separatorIndex].isWhitespace {
                return command.count + 1
            }
        }

        return nil
    }

    private func spokenTextFileContents(named filename: String) -> String? {
        let trimmedFilename = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFilename.isEmpty else {
            return nil
        }

        if let documentsDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let documentFileURL = documentsDirectoryURL.appendingPathComponent(trimmedFilename)
            if FileManager.default.fileExists(atPath: documentFileURL.path),
               let contents = try? String(contentsOf: documentFileURL, encoding: .utf8) {
                return contents
            }
        }

        if let bundledFileURL = Bundle.main.resourceURL?.appendingPathComponent(trimmedFilename),
           FileManager.default.fileExists(atPath: bundledFileURL.path),
           let contents = try? String(contentsOf: bundledFileURL, encoding: .utf8) {
            return contents
        }

        return nil
    }

    func openPreviewFile(named filename: String) {
        let trimmedFilename = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFilename.isEmpty else {
            return
        }

        guard let fileURL = resolvedPreviewFileURL(named: trimmedFilename) else {
            alertTitle = "File Not Found"
            renameAlertMessage = "Couldn't find \(trimmedFilename.lowercased())."
            return
        }

        if let contents = try? String(contentsOf: fileURL, encoding: .utf8) {
            presentedPreviewFile = .text(filename: fileURL.lastPathComponent, contents: contents)
            return
        }

        if fileURL.pathExtension.caseInsensitiveCompare("pdf") == .orderedSame,
           let renderedPDFImage = renderedSinglePagePDFPreviewImage(from: fileURL) {
            presentedPreviewFile = .renderedImage(
                filename: fileURL.lastPathComponent,
                image: renderedPDFImage
            )
            return
        }

        guard UIImage(contentsOfFile: fileURL.path) != nil else {
            alertTitle = "Unsupported File"
            renameAlertMessage = "Couldn't preview \(trimmedFilename.lowercased())."
            return
        }

        presentedPreviewFile = .image(filename: fileURL.lastPathComponent, url: fileURL)
    }

    private func resolvedPreviewFileURL(named filename: String) -> URL? {
        let trimmedFilename = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFilename.isEmpty else {
            return nil
        }

        if let documentsDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
           let matchedDocumentFileURL = matchedRegularFileURL(in: documentsDirectoryURL, named: trimmedFilename) {
            return matchedDocumentFileURL
        }

        if let bundleResourceURL = Bundle.main.resourceURL,
           let matchedBundledFileURL = matchedRegularFileURL(in: bundleResourceURL, named: trimmedFilename) {
            return matchedBundledFileURL
        }

        return nil
    }

    private func matchedRegularFileURL(in directoryURL: URL, named filename: String) -> URL? {
        let exactFileURL = directoryURL.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: exactFileURL.path) {
            return exactFileURL
        }

        let candidateURLs = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return candidateURLs.first { candidateURL in
            let resourceValues = try? candidateURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues?.isRegularFile == true else {
                return false
            }

            return candidateURL.lastPathComponent.caseInsensitiveCompare(filename) == .orderedSame
        }
    }

    private func renderedSinglePagePDFPreviewImage(from fileURL: URL) -> UIImage? {
        guard let pdfDocument = PDFDocument(url: fileURL),
              pdfDocument.pageCount == 1,
              let pdfPage = pdfDocument.page(at: 0) else {
            return nil
        }

        let pageBounds = pdfPage.bounds(for: .mediaBox)
        guard pageBounds.width > 0, pageBounds.height > 0 else {
            return nil
        }

        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: pageBounds.size, format: rendererFormat)

        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: pageBounds.size))

            context.cgContext.saveGState()
            context.cgContext.translateBy(x: 0, y: pageBounds.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            pdfPage.draw(with: .mediaBox, to: context.cgContext)
            context.cgContext.restoreGState()
        }
    }

    private func parseWidgetTimerDuration(_ durationText: String) -> Int {
        let trimmedDurationText = durationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDurationText.isEmpty else {
            return 0
        }

        if let durationInSeconds = Int(trimmedDurationText) {
            return durationInSeconds
        }

        let loweredDurationText = trimmedDurationText.lowercased()
        let numericPrefix = loweredDurationText.prefix { $0.isNumber }
        guard let numericValue = Int(numericPrefix) else {
            return 0
        }

        let suffix = loweredDurationText
            .dropFirst(numericPrefix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let unit = suffix.first else {
            return numericValue
        }

        switch unit {
        case "m":
            return numericValue * 60
        case "h":
            return numericValue * 3600
        case "s":
            return numericValue
        default:
            return numericValue
        }
    }

    func targetWidgetDescriptorForSendText(_ sendText: String) -> MainGridWidgetDescriptor? {
        let trimmedSendText = sendText.trimmingCharacters(in: .whitespacesAndNewlines)
        let loweredSendText = trimmedSendText.lowercased()
        let widgetText: String

        if loweredSendText.hasPrefix(".amb ") {
            return ambientSoundDescriptor(from: String(trimmedSendText.dropFirst(5)))
        } else if loweredSendText.hasPrefix(".ambient ") {
            return ambientSoundDescriptor(from: String(trimmedSendText.dropFirst(9)))
        } else if isBareWidgetCommandText(loweredSendText) {
            widgetText = trimmedSendText
        } else {
            return nil
        }

        let trimmedWidgetText = widgetText.trimmingCharacters(in: .whitespacesAndNewlines)

        let components = trimmedWidgetText
            .split(separator: " ", omittingEmptySubsequences: true)
        guard let widgetName = components.first?.lowercased() else {
            return nil
        }

        if widgetName.hasSuffix(".txt") {
            return .textFileRandom(filename: String(components[0]))
        }

        switch widgetName {
        case ".clock":
            let cityLabel: String?
            if components.count > 1 {
                let resolvedCityLabel = components.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                cityLabel = resolvedCityLabel.isEmpty ? nil : resolvedCityLabel
            } else {
                cityLabel = nil
            }
            return .clock(cityLabel: cityLabel)
        case ".ord", ".ordinal":
            let cityLabel: String?
            if components.count > 1 {
                let resolvedCityLabel = components.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                cityLabel = resolvedCityLabel.isEmpty ? nil : resolvedCityLabel
            } else {
                cityLabel = nil
            }
            return .day(cityLabel: cityLabel)
        case ".month":
            let cityLabel: String?
            if components.count > 1 {
                let resolvedCityLabel = components.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                cityLabel = resolvedCityLabel.isEmpty ? nil : resolvedCityLabel
            } else {
                cityLabel = nil
            }
            return .month(cityLabel: cityLabel)
        case ".year":
            let cityLabel: String?
            if components.count > 1 {
                let resolvedCityLabel = components.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                cityLabel = resolvedCityLabel.isEmpty ? nil : resolvedCityLabel
            } else {
                cityLabel = nil
            }
            return .year(cityLabel: cityLabel)
        case ".sec":
            let cityLabel: String?
            if components.count > 1 {
                let resolvedCityLabel = components.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                cityLabel = resolvedCityLabel.isEmpty ? nil : resolvedCityLabel
            } else {
                cityLabel = nil
            }
            return .second(cityLabel: cityLabel)
        case ".min":
            let cityLabel: String?
            if components.count > 1 {
                let resolvedCityLabel = components.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                cityLabel = resolvedCityLabel.isEmpty ? nil : resolvedCityLabel
            } else {
                cityLabel = nil
            }
            return .minute(cityLabel: cityLabel)
        case ".hour":
            let cityLabel: String?
            if components.count > 1 {
                let resolvedCityLabel = components.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                cityLabel = resolvedCityLabel.isEmpty ? nil : resolvedCityLabel
            } else {
                cityLabel = nil
            }
            return .hour(cityLabel: cityLabel)
        case ".dow":
            let cityLabel: String?
            if components.count > 1 {
                let resolvedCityLabel = components.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                cityLabel = resolvedCityLabel.isEmpty ? nil : resolvedCityLabel
            } else {
                cityLabel = nil
            }
            return .dow(cityLabel: cityLabel)
        case ".date":
            let cityLabel: String?
            if components.count > 1 {
                let resolvedCityLabel = components.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                cityLabel = resolvedCityLabel.isEmpty ? nil : resolvedCityLabel
            } else {
                cityLabel = nil
            }
            return .date(cityLabel: cityLabel)
        case ".power":
            return .power
        case ".plus":
            return .add
        case ".minus":
            let initialCount: Int
            if components.count > 1 {
                guard let parsedInitialCount = Int(components[1]) else {
                    return nil
                }
                initialCount = max(parsedInitialCount, 0)
            } else {
                initialCount = 0
            }
            return .minus(initialCount: initialCount)
        case ".rnd", ".random":
            if components.count > 1 {
                let filename = String(components.dropFirst().joined(separator: " "))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if filename.lowercased().hasSuffix(".txt") {
                    return .textFileRandom(filename: filename)
                }
            }

            let minimumValue: Int
            let maximumValue: Int

            switch components.count {
            case 1:
                minimumValue = 1
                maximumValue = 10
            case 2:
                guard let parsedMaximumValue = Int(components[1]) else {
                    return nil
                }
                minimumValue = 1
                maximumValue = parsedMaximumValue
            default:
                guard let parsedMinimumValue = Int(components[1]),
                      let parsedMaximumValue = Int(components[2]) else {
                    return nil
                }
                minimumValue = parsedMinimumValue
                maximumValue = parsedMaximumValue
            }

            return .random(minimumValue: minimumValue, maximumValue: maximumValue)
        case ".stop", ".stopwatch":
            return .stopwatch
        case ".amb", ".ambient":
            return ambientSoundDescriptor(from: String(components.dropFirst().joined(separator: " ")))
        case ".timer":
            let initialDuration = components.count > 1
                ? parseWidgetTimerDuration(String(components[1]))
                : 0
            let completionText = components.count > 2
                ? String(components.dropFirst(2).joined(separator: " ")).trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            return .timer(
                initialDuration: max(initialDuration, 0),
                completion: timerCompletion(from: completionText)
            )
        default:
            return nil
        }
    }

    private func ambientSoundDescriptor(from commandArguments: String) -> MainGridWidgetDescriptor? {
        let normalizedArguments = normalizedSoundFilename(commandArguments)
        guard !normalizedArguments.isEmpty else {
            return nil
        }

        let components = normalizedArguments.split(whereSeparator: { $0.isWhitespace })
        guard let finalComponent = components.last else {
            return nil
        }

        if let volumePercentage = Int(finalComponent) {
            let filename = normalizedSoundFilename(String(components.dropLast().joined(separator: " ")))
            guard !filename.isEmpty else {
                return nil
            }

            guard (0...100).contains(volumePercentage) else {
                return .ambientSound(
                    filename: filename,
                    volume: .invalid(String(finalComponent))
                )
            }

            return .ambientSound(
                filename: filename,
                volume: .percentage(volumePercentage)
            )
        }

        return .ambientSound(
            filename: normalizedArguments,
            volume: .percentage(100)
        )
    }

    private func isBareWidgetCommandText(_ loweredText: String) -> Bool {
        let widgetCommands = [
            ".plus", ".minus", ".power", ".rnd", ".random", ".clock", ".date",
            ".dow", ".sec", ".min", ".hour", ".ord", ".ordinal", ".month", ".year", ".timer",
            ".stop", ".stopwatch", ".amb", ".ambient"
        ]

        return widgetCommands.contains { command in
            loweredText == command || loweredText.hasPrefix("\(command) ")
        }
    }

    private func isShortcutCommandText(_ loweredText: String) -> Bool {
        loweredText == "sc" ||
            loweredText.hasPrefix("sc ") ||
            loweredText == "shortcut" ||
            loweredText.hasPrefix("shortcut ")
    }

    private func waitDurationForSendText(_ sendText: String) -> TimeInterval? {
        let trimmedSendText = sendText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmedSendText.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
        guard parts.count == 2,
              parts[0].lowercased() == ".wait" else {
            return nil
        }

        let durationText = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let seconds = Double(durationText), seconds.isFinite else {
            return nil
        }

        return max(seconds, 0)
    }

    func isWaitCommandText(_ loweredText: String) -> Bool {
        loweredText == ".wait" || loweredText.hasPrefix(".wait ")
    }

    func isStopMediaCommandText(_ text: String) -> Bool {
        switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case ".sm", ".stopmedia":
            return true
        default:
            return false
        }
    }

    func stopAllMainGridMedia() {
        cancelAllWaitChainCommands()
        stopSpokenGridText()
        stopMainGridSoundPlayback()
        mainGridAmbientSoundState.stopPlayback()
    }

    private func timerCompletion(from text: String) -> MainGridTimerCompletion? {
        let trimmedText = displayText(from: text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return nil
        }

        let normalizedFilename = normalizedSoundFilename(trimmedText)
        let pathExtension = URL(fileURLWithPath: normalizedFilename).pathExtension.lowercased()
        if supportedSoundExtensions.contains(pathExtension) {
            return .sound(filename: normalizedFilename)
        }

        return .speech(text: trimmedText)
    }

    func playMainGridSound(
        named filename: String,
        repeats: Bool = false,
        volumePercentage: Int = 100,
        gestureOwnerID: String? = nil,
        gestureRequest: MainGridSoundRequest? = nil
    ) {
        guard (0...100).contains(volumePercentage) else {
            showInvalidSoundVolumeAlert()
            return
        }

        guard let audioURL = soundURL(named: filename) else {
            alertTitle = "Sound Not Found"
            renameAlertMessage = "Couldn't find \(filename)."
            return
        }

        let requestID = UUID()
        soundPlaybackRequestID = requestID
        clearMainGridOrdinarySoundGestureState()
        if let gestureOwnerID, let gestureRequest {
            ordinarySoundGestureOwnerID = gestureOwnerID
            ordinarySoundGestureRequest = gestureRequest
            ordinarySoundGestureRequestID = requestID
            ordinarySoundPlaybackPhase = .preparing
        }
        ordinarySoundActive = true
        soundEffectPlayer?.stop()
        soundEffectPlayer = nil
        soundPlaybackDelegate = nil

        Task {
            guard await activateAudioSessionForSpeechPlayback() else {
                guard soundPlaybackRequestID == requestID else {
                    return
                }
                ordinarySoundActive = false
                clearMainGridOrdinarySoundGestureState(matching: requestID)
                alertTitle = "Sound Error"
                renameAlertMessage = "Couldn't play \(filename)."
                return
            }

            guard soundPlaybackRequestID == requestID else {
                return
            }

            do {
                let player = try await MainGridSoundPlayerPreparer.shared.preparePlayer(
                    at: audioURL,
                    repeats: repeats
                )
                guard soundPlaybackRequestID == requestID else {
                    return
                }
                player.volume = Float(volumePercentage) / 100.0
                let playbackDelegate = MainGridSoundPlaybackDelegate(requestID: requestID) { completedRequestID in
                    guard soundPlaybackRequestID == completedRequestID else {
                        return
                    }
                    ordinarySoundActive = false
                    soundPlaybackDelegate = nil
                    clearMainGridOrdinarySoundGestureState(matching: completedRequestID)
                }
                soundPlaybackDelegate = playbackDelegate
                player.delegate = playbackDelegate
                soundEffectPlayer = player
                if ordinarySoundGestureRequestID == requestID,
                   ordinarySoundPlaybackPhase == .paused {
                    return
                }
                guard player.play() else {
                    soundEffectPlayer = nil
                    soundPlaybackDelegate = nil
                    ordinarySoundActive = false
                    clearMainGridOrdinarySoundGestureState(matching: requestID)
                    alertTitle = "Sound Error"
                    renameAlertMessage = "Couldn't play \(filename)."
                    return
                }
                if ordinarySoundGestureRequestID == requestID {
                    ordinarySoundPlaybackPhase = .playing
                }
            } catch {
                guard soundPlaybackRequestID == requestID else {
                    return
                }
                ordinarySoundActive = false
                soundPlaybackDelegate = nil
                clearMainGridOrdinarySoundGestureState(matching: requestID)
                alertTitle = "Sound Error"
                renameAlertMessage = "Couldn't play \(filename)."
            }
        }
    }

    func stopMainGridSoundPlayback() {
        soundPlaybackRequestID = UUID()
        soundEffectPlayer?.stop()
        soundEffectPlayer = nil
        soundPlaybackDelegate = nil
        ordinarySoundActive = false
        clearMainGridOrdinarySoundGestureState()
    }

    func soundURL(named filename: String) -> URL? {
        let normalizedFilename = normalizedSoundFilename(filename)
        guard !normalizedFilename.isEmpty else {
            return nil
        }

        if let documentsDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let documentSoundURL = documentsDirectoryURL.appendingPathComponent(normalizedFilename)
            if FileManager.default.fileExists(atPath: documentSoundURL.path) {
                return documentSoundURL
            }

            if let matchedDocumentSoundURL = matchedSoundURL(
                in: documentsDirectoryURL,
                matching: normalizedFilename
            ) {
                return matchedDocumentSoundURL
            }
        }

        guard let bundleResourceURL = Bundle.main.resourceURL else {
            return nil
        }

        let bundledSoundURL = bundleResourceURL.appendingPathComponent(normalizedFilename)
        if FileManager.default.fileExists(atPath: bundledSoundURL.path) {
            return bundledSoundURL
        }

        return matchedSoundURL(in: bundleResourceURL, matching: normalizedFilename)
    }

    private var supportedSoundExtensions: Set<String> {
        ["mp3", "wav", "m4a", "aiff", "aac", "caf"]
    }

    private func hasSupportedSoundExtension(_ filename: String) -> Bool {
        supportedSoundExtensions.contains(URL(fileURLWithPath: filename).pathExtension.lowercased())
    }

    func showInvalidSoundVolumeAlert() {
        alertTitle = "Invalid Sound Volume"
        renameAlertMessage = "Volume must be between 0 and 100."
    }

    private var supportedPreviewExtensions: Set<String> {
        ["txt", "md", "pdf", "png", "jpg", "jpeg", "gif", "heic", "webp"]
    }

    private func normalizedSoundFilename(_ filename: String) -> String {
        filename
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func normalizedSoundLookupKey(_ filename: String) -> String {
        normalizedSoundFilename(filename).lowercased()
    }

    private func matchedSoundURL(in directoryURL: URL, matching filename: String) -> URL? {
        let requestedLookupKey = normalizedSoundLookupKey(filename)
        guard !requestedLookupKey.isEmpty else {
            return nil
        }

        let candidateURLs = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [URLResourceKey.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        return candidateURLs?.first { candidateURL in
            let resourceValues = try? candidateURL.resourceValues(forKeys: [URLResourceKey.isRegularFileKey])
            guard resourceValues?.isRegularFile == true else {
                return false
            }

            guard supportedSoundExtensions.contains(candidateURL.pathExtension.lowercased()) else {
                return false
            }

            return normalizedSoundLookupKey(candidateURL.lastPathComponent) == requestedLookupKey
        }
    }

    func normalizedBluetoothSendText(_ sendText: String) -> String {
        let trimmedSendText = sendText.trimmingCharacters(in: .whitespacesAndNewlines)
        let loweredSendText = trimmedSendText.lowercased()

        if let outputCommand = normalizedNumericBluetoothCommand(
            from: trimmedSendText,
            command: "out",
            expectedArgumentCount: 2
        ) {
            return outputCommand
        }

        if let pwmCommand = normalizedNumericBluetoothCommand(
            from: trimmedSendText,
            command: "pwm",
            expectedArgumentCount: 3
        ) {
            return pwmCommand
        }

        guard loweredSendText.first == "f",
              loweredSendText.dropFirst().allSatisfy({ $0.isNumber }) else {
            return sendText
        }

        return loweredSendText
    }

    private func canonicalSmartScriptKeycode(_ token: String) -> String? {
        let uppercaseToken = token.uppercased()

        switch uppercaseToken {
        case ".ESC", ".RET", ".BS", ".SP", ".TAB",
             ".UP", ".DOWN", ".LEFT", ".RIGHT",
             ".CTA", ".CTC", ".CTV", ".CTX",
             ".MA", ".MC", ".MV", ".MX":
            return uppercaseToken
        default:
            return nil
        }
    }

    private func normalizedNumericBluetoothCommand(
        from sendText: String,
        command: String,
        expectedArgumentCount: Int
    ) -> String? {
        let parts = sendText.split(whereSeparator: { $0.isWhitespace })
        guard parts.count == expectedArgumentCount + 1,
              parts[0].lowercased() == command else {
            return nil
        }

        let arguments = parts.dropFirst().map(String.init)
        guard arguments.allSatisfy({ Int($0) != nil }) else {
            return nil
        }

        return ([command] + arguments).joined(separator: ":")
    }

    func isBluetoothSendableText(_ sendText: String) -> Bool {
        sendText.unicodeScalars.allSatisfy(\.isASCII)
    }

    func showBluetoothUnsupportedTextBlockedPopup() {
        alertTitle = ""
        renameAlertMessage = nil

        Task { @MainActor in
            alertTitle = ""
            renameAlertMessage = "text couldn't be sent to bluetooth\nbecause it contains emoji or non-English text"
        }
    }

    func mainGridButtonLabel(
        entry: FunctionKeyEntry,
        index: Int,
        buttonHeight: CGFloat,
        buttonSize: CGSize,
        backgroundOpacity: Double,
        defaultMIDIChannel: Int
    ) -> some View {
        let leftTitle = displayText(from: entry.primaryDisplayText)
        let rightTitle = displayText(from: effectiveAlternateDisplayText(for: entry, defaultMIDIChannel: defaultMIDIChannel))
        let title = buttonTitle(for: entry, defaultMIDIChannel: defaultMIDIChannel)
        let automaticMIDILabel = automaticMIDILabel(
            for: entry,
            index: index,
            defaultMIDIChannel: defaultMIDIChannel
        )

        return MainScreenButtonLabelView(
            entry: entry,
            index: index,
            widgetID: "\(selectedDocumentName)#\(index)",
            title: title,
            leftTitle: leftTitle,
            rightTitle: rightTitle,
            imageFilename: (parsedSFSymbolDisplay(for: entry)?.subtitle
                ?? displayText(from: resolvedAlternateDisplayText(for: entry)))
                .trimmingCharacters(in: .whitespacesAndNewlines),
            resolveImageURL: { resolvedPreviewFileURL(named: $0) },
            isMainScreenVisible: isMainScreenVisible,
            displayMode: displayMode,
            widgetDescriptor: targetWidgetDescriptorForGridEntry(entry),
            widgetHeaderContent: widgetHeaderContent(for: entry),
            rightSymbolDisplay: parsedSFSymbolDisplay(for: entry),
            rightEmojiDisplay: parsedEmojiDisplay(for: entry),
            automaticMIDILabel: automaticMIDILabel,
            boxFontSize: boxFontSize,
            buttonHeight: buttonHeight,
            buttonSize: buttonSize,
            cornerRadius: mainGridButtonCornerRadius,
            borderWidth: mainGridButtonBorderWidth,
            usesInsetBorder: !isPad,
            isGridEditModeEnabled: isGridEditModeEnabled,
            activeDragIndex: activeDragIndex,
            backgroundOpacity: backgroundOpacity,
            sharedTimer: mainGridTimerState,
            ambientSoundState: mainGridAmbientSoundState,
            playSoundNamed: { playMainGridSound(named: $0) },
            playLoopingSoundNamed: { playMainGridSound(named: $0, repeats: true) },
            stopSoundPlayback: stopMainGridSoundPlayback,
            sendTimerCompletionAction: { entry in
                let bluetoothSendTexts = bluetoothSendTexts(for: entry)
                return sendKeyboardOutputTokens(
                    bluetoothSendTexts,
                    respectsButtonMode: false,
                    sourceMetadata: outputSourceMetadata(for: entry)
                )
            },
            resolveSoundURL: { soundURL(named: $0) },
            activateAudioSession: activateAudioSessionForSpeechPlayback,
            reportSoundError: { title, message in
                alertTitle = title
                renameAlertMessage = nil
                Task { @MainActor in
                    alertTitle = title
                    renameAlertMessage = message
                }
            },
            shouldSpeakWidgetSelections: mainGridButtonMode.speaksText,
            speakText: speakMainGridText
        )
    }

    func widgetHeaderContent(for entry: FunctionKeyEntry) -> MainGridWidgetHeaderContent {
        guard targetWidgetDescriptorForGridEntry(entry) != nil else {
            return .none
        }

        let configuredText = displayText(from: resolvedAlternateDisplayText(for: entry))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let configuredHeader: MainGridWidgetHeaderContent
        if let symbolDisplay = parsedSFSymbolDisplay(for: entry) {
            configuredHeader = .symbol(name: symbolDisplay.name, subtitle: symbolDisplay.subtitle)
        } else if let emojiDisplay = parsedEmojiDisplay(for: entry) {
            configuredHeader = .emoji(emoji: emojiDisplay.emoji, subtitle: emojiDisplay.subtitle)
        } else if !configuredText.isEmpty {
            configuredHeader = .text(configuredText)
        } else {
            configuredHeader = .none
        }

        let completeCommand = displayText(from: entry.primaryDisplayText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let commandHeader: MainGridWidgetHeaderContent = completeCommand.isEmpty
            ? .none
            : .command(completeCommand)

        switch displayMode {
        case .left:
            return commandHeader
        case .right:
            return configuredHeader
        case .last:
            guard !configuredText.isEmpty else {
                return .none
            }
            return .text(displayTextAfterLastColon(in: configuredText))
        case .both:
            guard !completeCommand.isEmpty else {
                return configuredHeader
            }

            switch configuredHeader {
            case .symbol(let name, let subtitle):
                return .commandWithSymbol(command: completeCommand, name: name, subtitle: subtitle)
            case .emoji(let emoji, let subtitle):
                return .commandWithEmoji(command: completeCommand, emoji: emoji, subtitle: subtitle)
            case .text(let text):
                return .commandWithText(command: completeCommand, text: text)
            case .command, .none:
                return commandHeader
            case .commandWithSymbol, .commandWithEmoji, .commandWithText:
                return configuredHeader
            }
        }
    }

    func isInteractiveMainGridWidgetEntry(_ entry: FunctionKeyEntry) -> Bool {
        guard !isGridEditModeEnabled,
              let widgetDescriptor = targetWidgetDescriptorForGridEntry(entry) else {
            return false
        }

        switch widgetDescriptor {
        case .add:
            return true
        case .minus:
            return true
        case .random:
            return true
        case .textFileRandom:
            return true
        case .stopwatch:
            return true
        case .ambientSound:
            return true
        case .timer:
            return true
        default:
            return false
        }
    }

    func isMainGridEntryHidden(_ entry: FunctionKeyEntry) -> Bool {
        guard !isGridEditModeEnabled else {
            return false
        }

        return entry.isHiddenInNormalMode
    }

    func mainGridButtonDragGesture(
        entry: FunctionKeyEntry,
        index: Int,
        gridDimensions: GridDimensions
    ) -> AnyGesture<DragGesture.Value> {
        AnyGesture(
            DragGesture(minimumDistance: mainGridDragMinimumDistance)
                .onChanged { _ in
                    guard isGridEditModeEnabled,
                          editingSlotIndex == nil,
                          !entry.isBlankPlaceholder else {
                        return
                    }

                    activeDragIndex = index
                }
                .onEnded { value in
                    handleEditDragEnded(
                        from: index,
                        translation: value.translation,
                        gridDimensions: gridDimensions
                    )
                }
        )
    }

    private var mainGridDragMinimumDistance: CGFloat {
        isPad ? 20 : 10
    }

    func editableText(for entry: FunctionKeyEntry) -> String {
        if entry.isBlankPlaceholder || isEmptyButtonEntry(entry) {
            return ""
        }

        return entry.rawLine
    }

    func isEmptyButtonEntry(_ entry: FunctionKeyEntry) -> Bool {
        let trimmedRawLine = entry.rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAlternateText = entry.alternateDisplayText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedRawLine.isEmpty && entry.sendTexts.isEmpty && trimmedAlternateText.isEmpty
    }

    func parsedSFSymbolDisplay(for entry: FunctionKeyEntry) -> (name: String, subtitle: String?)? {
        let rightText = displayText(from: resolvedAlternateDisplayText(for: entry))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let components = rightText.components(separatedBy: ":")
        let candidateName = components.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard components.count > 1,
              !candidateName.isEmpty,
              !candidateName.contains(where: \.isWhitespace),
              UIImage(systemName: candidateName) != nil else {
            return nil
        }

        let subtitle = components
            .dropFirst()
            .joined(separator: ":")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (candidateName, subtitle.isEmpty ? nil : subtitle)
    }

    func parsedEmojiDisplay(for entry: FunctionKeyEntry) -> (emoji: String, subtitle: String?)? {
        let rightText = displayText(from: resolvedAlternateDisplayText(for: entry))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let components = rightText.components(separatedBy: ":")
        let candidateEmoji = components.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard isEmojiDisplayToken(candidateEmoji) else {
            return nil
        }

        let subtitle = components
            .dropFirst()
            .joined(separator: ":")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (candidateEmoji, subtitle.isEmpty ? nil : subtitle)
    }

    private func isEmojiDisplayToken(_ token: String) -> Bool {
        guard !token.isEmpty,
              !token.contains(where: \.isWhitespace),
              UIImage(systemName: token) == nil else {
            return false
        }

        // Treat only a single rendered emoji character as an emoji token.
        guard token.count == 1, let character = token.first else {
            return false
        }

        let isPlainASCIIAlphaNumeric = character.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && CharacterSet.alphanumerics.contains(scalar)
        }
        guard !isPlainASCIIAlphaNumeric else {
            return false
        }

        return character.unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation || scalar.properties.isEmoji
        }
    }

    private func rawLineWithoutHiddenMetadata(_ entry: FunctionKeyEntry) -> String {
        entry.rawLine
            .components(separatedBy: "::")
            .filter { $0 != hiddenButtonMetadataToken }
            .joined(separator: "::")
    }
}

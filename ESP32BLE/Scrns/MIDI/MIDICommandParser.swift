struct MIDICommand {
    let note: UInt8
    let velocity: UInt8
    let channelOverride: UInt8?

    var noteDisplayName: String {
        let pitchClasses = [
            "C", "C#", "D", "D#", "E", "F",
            "F#", "G", "G#", "A", "A#", "B"
        ]
        let noteValue = Int(note)
        let pitchClass = pitchClasses[noteValue % 12]
        let octave = (noteValue / 12) - 2
        return "\(pitchClass)\(octave)"
    }
}

struct MIDINoteIdentity {
    let note: UInt8
    let channel: UInt8
}

enum MIDIChannelSettings {
    static let storageKey = "midiDefaultChannel"
    static let defaultChannel = 1
    static let validRange = 1...16

    static func resolvedChannel(for command: MIDICommand, defaultChannel: Int) -> UInt8 {
        if let channelOverride = command.channelOverride {
            return channelOverride
        }

        let validDefaultChannel = validRange.contains(defaultChannel)
            ? defaultChannel
            : Self.defaultChannel
        return UInt8(validDefaultChannel)
    }
}

enum MIDICommandParser {
    static func parse(_ text: String) -> MIDICommand? {
        let components = text.split(whereSeparator: \.isWhitespace)

        guard (2...4).contains(components.count),
              components[0] == ".midi",
              let note = midiNote(from: components[1]) else {
            return nil
        }

        let velocity: UInt8
        if components.count >= 3 {
            guard let parsedVelocity = UInt8(components[2]),
                  (1...127).contains(parsedVelocity) else {
                return nil
            }
            velocity = parsedVelocity
        } else {
            velocity = 127
        }

        let channelOverride: UInt8?
        if components.count == 4 {
            guard let parsedChannel = UInt8(components[3]),
                  MIDIChannelSettings.validRange.contains(Int(parsedChannel)) else {
                return nil
            }
            channelOverride = parsedChannel
        } else {
            channelOverride = nil
        }

        return MIDICommand(
            note: note,
            velocity: velocity,
            channelOverride: channelOverride
        )
    }

    private static func midiNote(from token: Substring) -> UInt8? {
        if let numericNote = UInt8(token), numericNote <= 127 {
            return numericNote
        }

        let characters = Array(token)
        guard let noteLetter = characters.first?.uppercased().first else {
            return nil
        }

        let naturalSemitone: Int
        switch noteLetter {
        case "C": naturalSemitone = 0
        case "D": naturalSemitone = 2
        case "E": naturalSemitone = 4
        case "F": naturalSemitone = 5
        case "G": naturalSemitone = 7
        case "A": naturalSemitone = 9
        case "B": naturalSemitone = 11
        default: return nil
        }

        var octaveStartIndex = 1
        var accidentalOffset = 0
        if characters.count > octaveStartIndex {
            switch characters[octaveStartIndex] {
            case "#":
                accidentalOffset = 1
                octaveStartIndex += 1
            case "b", "B":
                accidentalOffset = -1
                octaveStartIndex += 1
            default:
                break
            }
        }

        let octaveCharacters = characters.dropFirst(octaveStartIndex)
        guard !octaveCharacters.isEmpty else {
            return nil
        }

        let octaveDigits: ArraySlice<Character>
        if octaveCharacters.first == "-" {
            octaveDigits = octaveCharacters.dropFirst()
            guard !octaveDigits.isEmpty else {
                return nil
            }
        } else {
            octaveDigits = octaveCharacters
        }

        guard octaveDigits.allSatisfy(\.isNumber),
              let octave = Int(String(octaveCharacters)) else {
            return nil
        }

        let resolvedNote = ((octave + 2) * 12) + naturalSemitone + accidentalOffset
        guard (0...127).contains(resolvedNote) else {
            return nil
        }

        return UInt8(resolvedNote)
    }
}

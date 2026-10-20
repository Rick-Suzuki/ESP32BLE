struct MIDICommand {
    let note: UInt8
    let velocity: UInt8
    let channelOverride: UInt8?
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
              let note = UInt8(components[1]),
              note <= 127 else {
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
}

struct MIDIControlChangeCommand {
    let controller: UInt8
    let value: UInt8
    let channelOverride: UInt8?
}

enum MIDIControlChangeParser {
    static func parse(_ text: String) -> MIDIControlChangeCommand? {
        let components = text.split(whereSeparator: \.isWhitespace)

        guard (3...4).contains(components.count),
              components[0] == ".cc",
              let controller = UInt8(components[1]),
              controller <= 127,
              let value = UInt8(components[2]),
              value <= 127 else {
            return nil
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

        return MIDIControlChangeCommand(
            controller: controller,
            value: value,
            channelOverride: channelOverride
        )
    }
}

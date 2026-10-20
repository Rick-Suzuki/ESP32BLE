struct MIDICommand {
    let note: UInt8
    let velocity: UInt8
}

enum MIDICommandParser {
    static func parse(_ text: String) -> MIDICommand? {
        let components = text.split(whereSeparator: \.isWhitespace)

        guard components.count == 2 || components.count == 3,
              components[0] == ".midi",
              let note = UInt8(components[1]),
              note <= 127 else {
            return nil
        }

        let velocity: UInt8
        if components.count == 3 {
            guard let parsedVelocity = UInt8(components[2]),
                  (1...127).contains(parsedVelocity) else {
                return nil
            }
            velocity = parsedVelocity
        } else {
            velocity = 100
        }

        return MIDICommand(note: note, velocity: velocity)
    }
}

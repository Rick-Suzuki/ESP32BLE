enum MIDIControlChangeMode {
    case oneShot
    case hold
    case toggle
}

struct MIDIControlChangeCommand {
    let controller: UInt8
    let value: UInt8
    let channelOverride: UInt8?
    let mode: MIDIControlChangeMode

    // MARK: - BM:🅱️ Display-only names; unlisted controllers retain their numeric identity.
    var controllerDisplayName: String {
        switch controller {
        case 0: return "bank select"
        case 1: return "mod"
        case 2: return "breath"
        case 4: return "foot controller"
        case 5: return "portamento time"
        case 6: return "data entry"
        case 7: return "vol"
        case 8: return "bal"
        case 10: return "pan"
        case 11: return "expr"
        case 64: return "sus"
        case 65: return "porta"
        case 66: return "sostenuto"
        case 67: return "soft pedal"
        case 68: return "legato"
        case 69: return "hold 2"
        case 70: return "sound variation"
        case 71: return "res"
        case 72: return "release time"
        case 73: return "attack time"
        case 74: return "brightness"
        case 75: return "decay time"
        case 76: return "vibrato rate"
        case 77: return "vibrato depth"
        case 78: return "vibrato delay"
        case 91: return "reverb"
        case 92: return "tremolo"
        case 93: return "chorus"
        case 94: return "celeste"
        case 95: return "phaser"
        case 120: return "all sound off"
        case 121: return "reset controllers"
        case 123: return "all notes off"
        default: return "cc\(controller)"
        }
    }

    // MARK: - BM:🅱️ Switch labels describe the command value, not live controller state.
    var valueDisplayText: String {
        (64...69).contains(controller) ? (value < 64 ? "off" : "on") : String(value)
    }
}

enum MIDIControlChangeParser {
    static func parse(_ text: String) -> MIDIControlChangeCommand? {
        var components = text.split(whereSeparator: \.isWhitespace)
        let mode: MIDIControlChangeMode
        switch components.last?.lowercased() {
        case "hold":
            mode = .hold
            components.removeLast()
        case "toggle":
            mode = .toggle
            components.removeLast()
        default:
            mode = .oneShot
        }

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
            channelOverride: channelOverride,
            mode: mode
        )
    }
}

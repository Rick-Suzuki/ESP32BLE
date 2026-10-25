enum MIDIControlChangeMode {
    case oneShot
    case hold
    case toggle
}

struct MIDIControlChangeCommand {
    let controller: UInt8
    let startValue: UInt8
    let endValue: UInt8
    let channelOverride: UInt8?
    let mode: MIDIControlChangeMode

    init(
        controller: UInt8,
        startValue: UInt8,
        endValue: UInt8 = 0,
        channelOverride: UInt8?,
        mode: MIDIControlChangeMode
    ) {
        self.controller = controller
        self.startValue = startValue
        self.endValue = endValue
        self.channelOverride = channelOverride
        self.mode = mode
    }

    init(
        controller: UInt8,
        value: UInt8,
        channelOverride: UInt8?,
        mode: MIDIControlChangeMode
    ) {
        self.init(
            controller: controller,
            startValue: value,
            channelOverride: channelOverride,
            mode: mode
        )
    }

    var value: UInt8 { startValue }

    static let controllerNumbersByAbbreviation: [String: UInt8] = [
        "alloff": 123,
        "sndoff": 120,
        "attack": 73,
        "bal": 8,
        "bank": 0,
        "breath": 2,
        "bright": 74,
        "vol": 7,
        "chorus": 93,
        "dec": 97,
        "data": 6,
        "inc": 96,
        "decay": 75,
        "effect1": 12,
        "effect2": 13,
        "expr": 11,
        "foot": 4,
        "gp1": 16,
        "gp2": 17,
        "gp3": 18,
        "gp4": 19,
        "gp5": 80,
        "gp6": 81,
        "gp7": 82,
        "gp8": 83,
        "hold2": 69,
        "legato": 68,
        "local": 122,
        "mod": 1,
        "mono": 126,
        "omnioff": 124,
        "omnion": 125,
        "pan": 10,
        "poly": 127,
        "portctl": 84,
        "portsw": 65,
        "porttime": 5,
        "release": 72,
        "reset": 121,
        "reverb": 91,
        "rpnlsb": 100,
        "rpnmsb": 101,
        "soft": 67,
        "sostenuto": 66,
        "variation": 70,
        "sus": 64,
        "timbre": 71,
        "trem": 92,
        "vibdelay": 78,
        "vibdepth": 77,
        "vibrate": 76
    ]

    // MARK: - BM:🅱️ Display-only names; unlisted controllers retain their numeric identity.
    var controllerDisplayName: String {
        switch controller {
        case 0: return "bank"
        case 1: return "mod"
        case 2: return "breath"
        case 4: return "foot"
        case 5: return "porta time"
        case 6: return "data"
        case 7: return "vol"
        case 8: return "bal"
        case 10: return "pan"
        case 11: return "expr"
        case 64: return "sus"
        case 65: return "porta"
        case 66: return "sost"
        case 67: return "soft"
        case 68: return "legato"
        case 69: return "hold 2"
        case 70: return "variation"
        case 71: return "res"
        case 72: return "release"
        case 73: return "attack"
        case 74: return "bright"
        case 75: return "decay"
        case 76: return "vib rate"
        case 77: return "vib depth"
        case 78: return "vib delay"
        case 91: return "reverb"
        case 92: return "tremolo"
        case 93: return "chorus"
        case 94: return "celeste"
        case 95: return "phaser"
        case 120: return "sound off"
        case 121: return "reset cc"
        case 123: return "notes off"
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

        let expectsEndValue = mode != .oneShot
        let expectedComponentCount = expectsEndValue ? 4...5 : 3...4
        guard expectedComponentCount.contains(components.count),
              components[0] == ".cc",
              let controller = controllerNumber(for: components[1]),
              controller <= 127,
              let startValue = UInt8(components[2]),
              startValue <= 127 else {
            return nil
        }

        let endValue: UInt8
        let channelOverride: UInt8?
        if expectsEndValue {
            guard let parsedEndValue = UInt8(components[3]),
                  parsedEndValue <= 127 else {
                return nil
            }
            endValue = parsedEndValue
        } else {
            endValue = 0
        }

        let channelIndex = expectsEndValue ? 4 : 3
        if components.count > channelIndex {
            guard let parsedChannel = UInt8(components[channelIndex]),
                  MIDIChannelSettings.validRange.contains(Int(parsedChannel)) else {
                return nil
            }
            channelOverride = parsedChannel
        } else {
            channelOverride = nil
        }

        return MIDIControlChangeCommand(
            controller: controller,
            startValue: startValue,
            endValue: endValue,
            channelOverride: channelOverride,
            mode: mode
        )
    }

    private static func controllerNumber(for token: Substring) -> UInt8? {
        UInt8(token) ?? MIDIControlChangeCommand.controllerNumbersByAbbreviation[token.lowercased()]
    }
}

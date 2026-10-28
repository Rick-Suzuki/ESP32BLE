
import SwiftUI
import Observation
import UIKit
import AVFoundation
import PDFKit
import Darwin

private enum ESP001MiniEditorTest: String {
    case empty
    case commandOnly
    case buttonOnly
    case colorOnly
    case sfOnly
    case commandAndButton
    case commandAndColor
    case allPanels
}

private enum ESP001IPhoneEditorStructure {
    case original
    case experimental
}

private enum ESP001IPhoneEditorDiagnostic {
    static let activeIPhoneEditorStructure: ESP001IPhoneEditorStructure = .experimental
}

private enum ESP001DiagnosticDevice {
    // MARK: - BM:🅱️ ADD COMMENTS HERE
    // Change this one value to select the active iPad Mini editor diagnostic configuration.
    static let activeMiniEditorTest: ESP001MiniEditorTest = .allPanels

    static var isIPadMini5: Bool {
        let identifier = UIDevice.current.hardwareModelIdentifier
        return identifier == "iPad11,1" || identifier == "iPad11,2"
    }

    static var isIPadAirM2: Bool {
        let identifier = UIDevice.current.hardwareModelIdentifier
        return identifier == "iPad14,8" ||
            identifier == "iPad14,9" ||
            identifier == "iPad14,10" ||
            identifier == "iPad14,11"
    }

    static var isIPadProTest11: Bool {
        let identifier = UIDevice.current.hardwareModelIdentifier
        return identifier == "iPad7,1"
    }

    static var usesESP001DiagnosticEditor: Bool {
        isIPadMini5 || isIPadAirM2 || isIPadProTest11
    }
}

private extension UIDevice {
    var hardwareModelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)

        return Mirror(reflecting: systemInfo.machine).children.reduce(into: "") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else {
                return
            }

            identifier.append(Character(UnicodeScalar(UInt8(value))))
        }
    }
}

private struct MainGridActionMenuTarget {
    let index: Int
    let buttonFrame: CGRect
    let gridDimensions: GridDimensions
}

private struct PopupUndoEntry {
    let documentName: String
    let slotLines: [String]
    let duplicateSourceTarget: MainGridActionMenuTarget?
    let resizeTarget: PopupResizeUndoTarget?
}

private struct PopupResizeUndoTarget {
    let beforeAnchor: Int
    let afterAnchor: Int
}

private enum MainGridActionMenuMode {
    case actions
    case resize
}

private enum MainGridDirectionalDeleteDirection {
    case up
    case down
    case left
    case right
}

private struct MainGridDeleteFootprint {
    let anchor: Int
    let row: Int
    let column: Int
    let width: Int
    let height: Int

    var minRow: Int { row }
    var maxRow: Int { row + height - 1 }
    var minColumn: Int { column }
    var maxColumn: Int { column + width - 1 }
}

// MARK: - BM:🅱️ iPhone bottom-toolbar geometry
private struct IPhoneBottomToolbarFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect?

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

private struct IPhoneBottomToolbarFrameReporter: View {
    var body: some View {
        GeometryReader { geometry in
            Color.clear.preference(
                key: IPhoneBottomToolbarFramePreferenceKey.self,
                value: geometry.frame(in: .global)
            )
        }
    }
}

struct MainScreen: View {
    enum PreviewedFile: Equatable, Identifiable {
        case text(filename: String, contents: String)
        case image(filename: String, url: URL)
        case renderedImage(filename: String, image: UIImage)

        var id: String {
            switch self {
            case let .text(filename, _):
                return "text:\(filename)"
            case let .image(filename, _):
                return "image:\(filename)"
            case let .renderedImage(filename, _):
                return "rendered-image:\(filename)"
            }
        }
    }

    @AppStorage(MIDIChannelSettings.storageKey) private var midiDefaultChannel = MIDIChannelSettings.defaultChannel
    @Environment(\.scenePhase) private var midiScenePhase
    @State private var midiActivations = MainMIDIActivationRegistry()
    @State private var midiCCDisplayValues: [MainGridMIDICCDisplayKey: UInt8] = [:]

    // Easy-to-find styling controls for the main button grid.
    private let mainGridButtonSpacingMaximum: CGFloat = 10
    private let mainGridButtonSpacingMinimum: CGFloat = 4
    private let mainGridButtonCornerRadiusMaximum: CGFloat = 20
    private let mainGridButtonCornerRadiusMinimum: CGFloat = 5
    let mainGridButtonBorderWidth: CGFloat = 2
  
	// Easy-to-find spacing for the slot editor controls row.
    private let slotEditorButtonSpacing: CGFloat = 5
    // Easy-to-find width for all slot editor helper buttons.
    private let slotEditorHelperButtonWidth: CGFloat = 58
    private let smartViewWidth: CGFloat = 1024
    private let smartViewHeight: CGFloat = 338
    private let smartEditControlsWidth: CGFloat = 205
    private let smartCommandEditorWidth: CGFloat = 343
    private let smartColorControlsWidth: CGFloat = 238
    private let smartSFPanelWidth: CGFloat = 238
    // MARK: - BM:🅱️🅱️🅱️  Temporary editor geometry overlay
    private let debugEditorGeometry = false
    private var smartViewWidthPhone: CGFloat {
        smartEditControlsWidthPhone +
        smartCommandEditorWidthPhone +
        smartColorControlsWidthPhone +
        smartSFPanelWidthPhone
    }
    private let smartViewHeightPhone: CGFloat = 338
    private let smartEditControlsWidthPhone: CGFloat = 322
    private let smartCommandEditorWidthPhone: CGFloat = 322
    private let smartColorControlsWidthPhone: CGFloat = 322
    private let smartSFPanelWidthPhone: CGFloat = 0
    private let smartFunctionKeyColumnWidth: CGFloat = 58
    private let smartColorSliderColumnWidth: CGFloat = 48
    private let smartTopPlaceholderSymbols = [
		// row 0
        "delete.left.fill", "arrow.left", "arrow.right", "arrow.uturn.backward",
		
		// row 1
        "doc.on.doc", "scissors", "doc.on.clipboard", "arrow.uturn.forward",
		
		// row 2
        "delete.right.fill", "", ""	// mode btn here
		
		// row 4
		// modifiers
    ]
    // Adjust this to tune the height of the color/visibility cells in the smart button panel.
    private let smartButtonPanelColorCellHeight: CGFloat = 46
    private let smartCommandTableRowHeight: CGFloat = 26
    // MARK: - BM:🅱️🅱️🅱️  Small optical correction for the bottom iPhone Test/Close row.
    private let smartIPhoneActionButtonHeightScale: CGFloat = 0.90
    // MARK: - BM:🅱️🅱️🅱️  Small proportional extension for the lower iPhone command-description area.
    private let smartIPhoneCommandLowerHeightScale: CGFloat = 1.025
    private let smartIPhoneButtonContentWidth: CGFloat = 322
    private let smartIPhoneButtonPreviewWidth: CGFloat = 108
    private let smartIPhoneButtonPreviewHeight: CGFloat = 72
    private var smartIPhoneButtonPreviewEnclosureHeight: CGFloat {
        smartCommandDescriptionTopOffset
    }
    private let smartIPhoneButtonEditorCellSize: CGFloat = 46
    private let smartIPhoneButtonControlRowHeight: CGFloat = 46
    private var smartPositionIndicatorHorizontalPadding: CGFloat {
        smartButtonPanelColorCellHeight * 0.08
    }
    private var smartCommandDescriptionTopOffset: CGFloat {
        44 * 4
    }
    private var smartIPhoneButtonSwatchHexColors: [String] {
        smartButtonSwatchHexColorsWithWhite + [
            "F2F2F2",
            "BFBFBF",
            "404040",
            "1A1A1A",
            "7F0000",
            "CC3333",
            "FF6666",
            "7F3F00",
            "CC6600",
            "FFB266",
            "336600",
            "66CC33",
            "B2FF66",
            "003F7F",
            "3366CC",
            "66B2FF",
            "33007F",
            "6633CC",
            "B266FF",
            "FF66B2"
        ]
    }
    private var smartButtonSwatchHexColorsWithWhite: [String] {
        var colors = smartButtonSwatchHexColors
        if let blackIndex = colors.firstIndex(of: "000000") {
            colors.insert("FFFFFF", at: colors.index(after: blackIndex))
        } else {
            colors.append("FFFFFF")
        }
        return colors
    }
  
	// Vertical gap between the MainScreen top toolbar and the first button row.
    // Smaller value moves the button grid upward toward the toolbar.
    private let topToolbarToGridSpacing: CGFloat = 2
    private let mainTopToolbarHeight: CGFloat = 44
    private let iPadGridToBottomToolbarSpacing: CGFloat = 20
    // MARK: - BM:🅱️ ADD COMMENTS HERE
    // iPad popup vertical adjustment: 0 = no adjustment, +5 = move down 5 points, -5 = move up 5 points.
    private let iPadPopupVerticalOffset: CGFloat = 0
    private let iPhoneBottomToolbarRegionHeight: CGFloat = 36
    private let iPhoneGridToBottomToolbarClearance: CGFloat = 4
    private let iPhoneGridReservedBottomInset: CGFloat = 30
    private let mainScreenPopupCoordinateSpaceName = "MainScreenPopupCoordinateSpace"
		
		// MARK: - BM:🟥 smart SF symbols
    
	private let smartSFPanelSymbols = [
        "folder", "folder", "magnifyingglass", "lightbulb.max.fill",
        "speaker.wave.2", "star", "heart", "bell",
        "house", "gearshape", "airplane", "book",
        "camera", "eye", "cloud", "envelope",
        "flag", "leaf", "moon", "wrench",
        "paperplane", "doc", "calendar", "paintbrush",
        "photo", "tray", "sun.max.fill", "link",
        "person", "person.2", "car", "bicycle",
        "map", "globe", "location", "wifi",
        "battery.100", "music.note", "phone", "message",
        "mail", "trash", "pencil", "square.and.pencil",
        "plus", "minus", "checkmark", "xmark",
        "arrow.left", "arrow.right", "arrow.up", "arrow.down",
        "chevron.left", "chevron.right", "chevron.up", "chevron.down",
        "play.fill", "pause.fill", "stop.fill", "record.circle",
        "forward.fill", "backward.fill", "gobackward", "goforward",
        "clock", "timer", "stopwatch", "alarm",
        "calendar.badge.clock", "textformat", "keyboard", "command",
        "option", "shift", "control", "escape",
        "return", "delete.left", "spacebar", "arrow.right.to.line",
        "lock", "lock.open", "key", "power",
        "bolt", "bolt.fill", "flame", "drop",
        "thermometer", "humidity", "wind", "snowflake",
        "gamecontroller", "headphones", "mic", "waveform",
        "antenna.radiowaves.left.and.right", "network", "server.rack", "desktopcomputer",
        "laptopcomputer", "ipad", "iphone", "apple.logo",
        "app", "square.grid.2x2", "list.bullet", "slider.horizontal.3",
        "moon.fill", "moon.stars", "moon.stars.fill", "sunrise", "sunset", "cloud.sun",
        "cloud.moon", "cloud.rain", "cloud.snow", "umbrella", "tornado", "hare",
        "tortoise", "pawprint", "fish", "bird", "ladybug", "ant",
        "bed.double", "sofa", "chair", "table.furniture", "lamp.desk", "fan",
        "lightbulb", "flashlight.on.fill", "cup.and.saucer", "fork.knife", "takeoutbag.and.cup.and.straw", "birthday.cake",
        "gift", "creditcard", "banknote", "dollarsign.circle", "eurosign.circle", "sterlingsign.circle",
        "cart.fill", "bag", "basket", "shippingbox", "archivebox", "briefcase",
        "printer", "scanner", "externaldrive", "memorychip", "cpu", "display",
        "tv", "radio", "hifispeaker", "video", "video.fill", "camera.fill",
        "photo.on.rectangle", "rectangle.stack", "doc.text", "doc.richtext", "clipboard", "note.text",
        "bookmark", "bookmark.fill", "tag", "tag.fill", "pin", "mappin",
        "location.fill", "safari", "network.badge.shield.half.filled", "wifi.router", "antenna.radiowaves.left.and.right.circle", "dot.radiowaves.left.and.right",
        "bell.fill", "bell.slash", "speaker.slash", "speaker.wave.3", "mic.fill", "mic.slash",
        "waveform.circle", "music.mic", "music.quarternote.3", "guitars", "pianokeys", "metronome",
        "play.circle", "pause.circle", "stop.circle", "record.circle.fill", "shuffle", "repeat",
        "arrow.clockwise", "arrow.counterclockwise", "arrow.up.left", "arrow.up.right", "arrow.down.left", "arrow.down.right",
        "arrowshape.left", "arrowshape.right", "arrowshape.turn.up.left", "arrowshape.turn.up.right",
        "arrow.uturn.left", "arrow.uturn.right", "arrow.turn.up.left", "arrow.turn.up.right"
    ]

    private var smartIPhoneSFPanelSymbols: [String] {
        smartSFPanelSymbols + ["heart.fill", "star.fill", "paperclip"]
    }
	
	// MARK: - BM:🟥 btn colors
private let smartButtonSwatchHexColors = [
    "000000",	// black
				// white
	"003366",	// music blue
	"FF0000",	// red
	"00A600",	// green
	
	"0000FF",	// blue
    "FFFF00",	// yellow
	"00FFFF",	// cyan
	"FF00FF",	// purple
	"FF8000",	// orange
    
	"8000FF",	// dark purple
	"FFCC99",	// light orange
	"FF0080",	// pink
    "800000",	// red/brown
	"005C5C",	// off green
	
	"666600",	// dark yellow
	"808080",	// gray
	
	"910000",
	"C97827",
	"8A8A8A",
	"D42AD4",
	"007FFF"
]
	// MARK: - BM:🟥 smart keycodes
    private let smartEscapeCodeRows: [(english: String, command: String, description: String)] = [
		("escape key", 			".ESC", 		"sends the escape key"),
		("send return", 		".RET", 		"sends the return key"),
		("backspace key", 		".BS", 		"sends a backspace key"),
		("space key", 			".SP", 		"sends the space character."),
		("tab key", 			".TAB", 		"sends the tab key"),
		("colon", 				":", 		"a colon is used to separate keyboard presses"),
		("up key", 				".UP", 		"sends up arrow"),
		("down key", 			".DOWN", 	"sends down arrow"),
		("left key", 			".LEFT", 	"sends left arrow"),
		("right key", 			".RIGHT",	"sends right arrow"),
		("select all (ctl-a)", 	".CTA", 		"sends control-a"),
		("copy (ctl-c)", 		".CTC", 		"sends control-c"),
		("paste (ctl-v)", 		".CTV", 		"sends control-v"),
		("cut (ctl-x)", 		".CTX", 		"sends control-x"),
		("select all (cmd-a)", 	".MA", 		"sends command-a"),
		("copy (cmd-c)", 		".MC", 		"sends command-c"),
		("paste (cmd-v)", 		".MV", 		"sends command-v"),
		("cut (cmd-x)", 		".MX", 		"sends command-x")
	]
	//
	//-----------------------------------------------------------------------------------------------
	// MARK: - BM:🟥 smart widgets
	//
	private let smartCommandRows: [(english: String, shortcut: String, description: String)] = [
		//
		//-----------------------------------------------------------------------------------------------
		// *** TIME, DAY, DATE ETC ***
		// table    cmd		details
		("clock", ".clock ","""
**Insert a Digital Clock**
	
**Syntax:** 	.clock

**Display:**	13.05:41

**Display with btn text:**	
    hello
13.05:41

Optionally specify a city:
	
.clock Paris
.clock Tokyo

**Notes:** This command works without an ESP32 or Mac Helper connection.
"""),
		//
		//----------------------------------------
		//
		("date", ".date ", """
**Insert the Current Date**
 
**Syntax:** .date

**Display:**	26.10.17

**Display with btn text:**	
   hello
26.10.17

Optionally specify a city:
 
.date Paris
.date Tokyo

**Note:** This command works without an ESP32 or Mac Helper connection.
"""),
		//
		//----------------------------------------
		//
		("year", ".year ", """
**Insert the current year**
 
**Syntax:** .year

**Display:**	2026

**Display with btn text:**	
  hello
2026

Optionally specify a city:
 
.year Paris
.year Tokyo

**Note:** This command works without an ESP32 or Mac Helper connection.
"""),
		//
		//----------------------------------------
		//
		("month", ".month ", """
**Insert the current month**

**Syntax:** .month

Optionally specify a city:
 
**Display:**	October

**Display with btn text:**	
 hello
10

.month Paris
.month Tokyo

**Note:** This command works without an ESP32 or Mac Helper connection.
"""),
		//
		//----------------------------------------
		//
			("day of month", ".ord ", """
**Insert the current ordinal day**
 
**Syntax:** .ord

**Equivalent:** .ordinal

**Display:**	17th

**Display with btn text:**	
  hello
17th

Optionally specify a city:
 
.ord Paris
.ordinal Tokyo

**Note:** This command works without an ESP32 or Mac Helper connection.
"""),
		//
		//----------------------------------------
		//
		("day of week", ".dow ", """
**Insert the day of the week**
 
**Syntax:** .dow

**Display:**	Monday

**Display with btn text:**	
  hello
Monday

Optionally specify a city:
 
dow Paris
dow Tokyo

**Note:** This command works without an ESP32 or Mac Helper connection.
"""),
		//
		//----------------------------------------
		//
		("hour", ".hour ", """
**Insert the current hour**

**Syntax:** .hour

**Display:**	23

**Display with btn text:**	
  hello
23

Optionally specify a city:
 
.hour Paris
.hour Tokyo

**Note:** This command works without an ESP32 or Mac Helper connection.
"""),
		//
		//----------------------------------------
		//
		("mins", ".min ", """
**Insert the current minutes**

**Syntax:** .min

**Display:**	42

**Display with btn text:**	
  hello
42

**Note:** This command works without an ESP32 or Mac Helper connection.
"""),
		//
		//----------------------------------------
		//
		("secs", ".sec ", """
**Insert the current seconds**

**Syntax:** .sec

**Display:**	42

**Display with btn text:**	
  hello
42

**Note:** This command works without an ESP32 or Mac Helper connection.
"""),
		//
		//----------------------------------------
		//
		("stopwatch", ".stop ", """
**Inserts a stopwatch**

**Insert the current seconds**

**Syntax:** .stop

**Display:**	01:02:03

**Display with btn text:**	
  hello
01:02:03

**taps**
1 tap	-	pause
2 taps	-	reset

**Note:** This command works without an ESP32 or Mac Helper connection.
"""),
		//
		//-----------------------------------------------------------------------------------------------
		// *** BACK, FORWARD ETC ***
		//
		("prev", ".prev", """
**Goes to the previous screen in list**

**Syntax:** .prev

**Display:** prev
 
**Display with btn text:**	
anything you want

**Note:** This command works without an ESP32 or Mac Helper connection.
"""),
		//
		//----------------------------------------
		//
		("next", ".next", """
**Goes to the next screen in list**

**Syntax:** .next

**Display:** next
 
**Display with btn text:**	
anything you want

**Note:** This command works without an ESP32 or Mac Helper connection.
"""),
		//
		//----------------------------------------
		//
		("back", ".back", """
**Goes backward in the loaded page stack**

**Syntax:** .back

**Display:** backward
 
**Display with btn text:**	
anything you want

**Note:** This command works without an ESP32 or Mac Helper connection.
"""),
		//
		//----------------------------------------
		//
		("forward", ".forw", """
**Goes forward in the loaded page stack**

**Syntax:** .forw

**Display:** forward
 
**Display with btn text:**	
anything you want

**Note:** This command works without an ESP32 or Mac Helper connection.
"""),
		//
		//----------------------------------------
		//
		("home", ".home", """
**Goes to home.screen page**

**Syntax:** .home

**Display:** home
 
**Display with btn text:**	
anything you want

**Note:** This command works without an ESP32 or Mac Helper connection.
"""),
		// TODO
		//-----------------------------------------------------------------------------------------------
		// *** MEDIA ***
		//
		//
		//----------------------------------------
		//
		("play sound", "snd.mp3", """
**Plays a sound file**

**Syntax:** [sound filename]

**Display:** filename
 
**Display with btn text:**	
anything you want

**Note:** This command works without an ESP32 or Mac Helper connection.
"""),
		//
		//----------------------------------------
		//
		("speak text", ".spk hello", """
**Speaks text aloud**

**Syntax:** .spk [some text]

**Display:** spk hello
 
**Display with btn text:**	
anything you want

**Note:** This command works without an ESP32 or Mac Helper connection.
"""),
		//
		//----------------------------------------
		//
		("preview media file", "hello.pdf", """
**Previews a Media File**

**Syntax:** [filename]

**Display:** [filename]
 
**Display with btn text:**	
anything you want

**Notes:**
1. Opens a preview panel with the selected file. Supported formats: text, markdown, image and PDF (Single page only)

2. This command works without an ESP32 or Mac Helper connection.
"""),
		//
		//----------------------------------------
		//
		("wait time", ".wait 5", """
Waits before continuing
a command chain.
"""),
		//
		//-----------------------------------------------------------------------------------------------
		// *** NUMBERS ***
		//
		//
		//----------------------------------------
		//
		("tap minus", ".minus 10", """
Subtracts from a
tap counter.

**Note:** This command works without an ESP32 or Mac Helper connection.
"""),
		//
		//----------------------------------------
		//
		("tap plus", ".plus ", """
Adds to a
tap counter.

**Note:** This command works without an ESP32 or Mac Helper connection.
"""),
		//
		//----------------------------------------
		//
		("random number", ".rnd 0 100", """
Generates a random
number.

**Note:** This command works without an ESP32 or Mac Helper connection.
"""),
		//
		//----------------------------------------
		//
		("random line", ".rnd file.txt", """
Uses a random line
from a file.

**Note:** This command works without an ESP32 or Mac Helper connection.
"""),
		//
		//-----------------------------------------------------------------------------------------------
		// *** IOS SYSTEM ***
		//
		//
		//----------------------------------------
		//
		("copy cb",".cb","""
**Copy to Clipboard**
Copies the specified text to the iOS clipboard.
 
**Syntax:** cb text
 
**Example:** cb Hello World
 
The clipboard will contain *Hello World*.
 
 **Note:** This command works without an ESP32 or Mac Helper connection.
"""),
		//
		//----------------------------------------
		//
		("device power", ".power ", """
Shows the device
power state.

**Note:** This command works without an ESP32 or Mac Helper connection.
"""),
		//
		//----------------------------------------
		//
		("ambient sound", ".amb snd.mp3 50", """
Starts ambient sound
playback.

**Note:** This command works without an ESP32 or Mac Helper connection.
"""),
		//
		//----------------------------------------
		//
		("timer sound", "timer 60 snd.wav", """
Runs a timer that
plays sound.

**Note:** This command works without an ESP32 or Mac Helper connection.
"""),
		//
		//----------------------------------------
		//
		("timer speak", "timer 10 hello", """
Runs a timer that
speaks text.

**Note:** This command works without an ESP32 or Mac Helper connection.
"""),
		//
		//----------------------------------------
		//
		("run shortcut", "sc shortcutName", """
Runs an iOS
shortcut.

**Note:** This command works without an ESP32 or Mac Helper connection.
"""),
		//
		//----------------------------------------
		//
		("open app",	// table title
		 ".app mail",	// example code
// details
"""
***Open an App***	
  
iOS Apps that can be opened on device:

mail			notes
messages		facetime
maps			music
calendar	    .   

**Note:** This command works without an ESP32 or Mac Helper connection.
"""),
		//
		//----------------------------------------
		//
		("preview file", " file.txt", """
Previews a file.

**Note:** This command works without an ESP32 or Mac Helper connection.
"""),
		//
		//----------------------------------------
		//
		("wait", ".wait 1", """
Wait for a length of time

Syntax: .wait number

number can be int like 1 or a fraction 0.5 = half a second

This is a chain command, so

F1:.wait 10:hello.txt
sends F1 then waits 10 secs, the opens hello.txt

F1:.wait 1:sp
sends F1, waits one send then sends sp(space)
"""),
		//
		//-----------------------------------------------------------------------------------------------
		// *** ESP32 CMDS ***
		//
		("Esp32 out", ".out 32 1", """
**Set an ESP32 Output Pin State**

**Syntax:**.out *num1 num2*
*num1* is the pin to send to
*num2* is the state, 1 or 0

**Note:** 
This command requires an ESP32 connection. Not all pins will work, it will depend on your device.
"""),
		//
		//----------------------------------------
		//
		("Esp32 pwm", ".pwm 32 5 4", """
**Sends an ESP32 PWM Command**

**Syntax:**.pwm *num1 num2 num3*
*num1* is the pin to send to
*num2* is the mark ratio
*num3* is the space ratio

**Note:** 
This command requires an ESP32 connection. Not all pins will work, it will depend on your device.
"""),
	] // END OF SMART COMMENTS
	//
	//-----------------------------------------------------------------------------------------------
	//
    @AppStorage("speechRecognitionAutoOffMinutes") var speechRecognitionAutoOffMinutes = 5
	
	// MARK: - BM:🔆 grid dims - allowed sizes
	
    private let displayModeButtonColor = Color(red: 0.05, green: 0.33, blue: 0.18)
    private let fontControlColor = Color(red: 0.78, green: 0.68, blue: 0.12)
    private let speechRecognitionActiveColor = Color(red: 0.0, green: 0.2, blue: 0.45)
    private let bleSendActiveColor = Color(red: 0.55, green: 0.45, blue: 0.08)
    @State var visibleBoxCount = 20
    @State var visibleGridDimensions: GridDimensions = functionKeyGridDimensions(for: 20)
    @State var mainGridButtonMode: MainGridButtonMode = .active
    @State var isSpkRecEnabled = false
    @State var unmatchedSpeechText: String?
    @State var speechRecognitionAutoOffTask: Task<Void, Never>?
    @StateObject var speechRecognition = SpeechRecognitionManager()
    @State var speechSynthesizer = AVSpeechSynthesizer()
    @State var speechPlaybackRequestID = UUID()
    @State var speechPlaybackDelegate: MainGridSpeechPlaybackDelegate?
    @State var speechSynthesisActive = false
    @State var soundEffectPlayer: AVAudioPlayer?
    @State var soundPlaybackRequestID = UUID()
    @State var soundPlaybackDelegate: MainGridSoundPlaybackDelegate?
    @State var ordinarySoundActive = false
    @State var ordinarySoundGestureOwnerID: String?
    @State var ordinarySoundGestureRequest: MainGridSoundRequest?
    @State var ordinarySoundGestureRequestID: UUID?
    @State var ordinarySoundPlaybackPhase: MainGridOrdinarySoundPlaybackPhase = .stopped
    @State var activeWaitChainTasks: [UUID: Task<Void, Never>] = [:]
    @StateObject var mainGridTimerState = MainGridSharedTimerState()
    @StateObject var mainGridAmbientSoundState = MainGridAmbientSoundState()
    @ObservedObject var ble: BLEKeyboardManager
    @ObservedObject var macConnection: MacConnectionManager
    let outputMode: OutputMode
    @State var displayMode: FunctionKeyDisplayMode = .right
    @State var isEditingDocumentName = false
    @State var documentNameDraft = ""
    @State var alertTitle = "Alert"
    @State var renameAlertMessage: String?
    @State private var filenameToastText: String?
    @State private var filenameToastDismissTask: Task<Void, Never>?
    @State var isGridEditModeEnabled = false
    @State var activeDragIndex: Int?
    @State var editingSlotIndex: Int?
    @State var editingSlotText = ""
    @State var didModifyCurrentSlotEditorSession = false
    @State private var mainGridActionMenuTarget: MainGridActionMenuTarget?
    @State private var mainGridActionMenuMode: MainGridActionMenuMode = .actions
    @State private var pendingPopupRestoreIndex: Int?
    @State private var pendingPopupRestoreDocumentName: String?
    @State private var pendingMovePopupRefreshIndex: Int?
    @State private var pendingMovePopupRefreshDocumentName: String?
    @State private var pendingActionMenuFrameRefreshIndex: Int?
    @State private var pendingActionMenuFrameRefreshDocumentName: String?
    @State private var pendingActionMenuFrameRefreshRequiresButton = false
    @State private var mainGridRenderedActionMenuTargets: [Int: MainGridActionMenuTarget] = [:]
    @State private var mainGridRenderedButtonFrameRefreshToken = 0
    @State private var mainGridRenderedFrame: CGRect?
    @State private var iPadBottomToolbarTopY: CGFloat?
    @State private var iPadBottomToolbarVisibleContentTopY: CGFloat?
    @State private var iPhoneBottomToolbarFrame: CGRect?
    @State private var popupUndoHistory: [PopupUndoEntry] = []
    @State private var popupRedoHistory: [PopupUndoEntry] = []
    @State private var directionalDeleteLastFootprint: MainGridDeleteFootprint?
    @State private var directionalDeleteDirection: MainGridDirectionalDeleteDirection?
    @State private var directionalDeleteExpectedAnchor: Int?
    // MARK: - BM:🅱️ ADD COMMENTS HERE
    // Increase or decrease this value to adjust how many popup edits Undo retains.
    private let popupUndoHistoryLimit = 20
	//
	//----------------------------------------
	// MARK: - BM:👨‍👩‍👧‍👦 commands help text area
	//
    @State private var smartCommandDescription = "command description"
   
	private let smartHelpButtonColor = """
Sets the button background color. 
"""
	
	private let smartHelpButtonColon = """
Inserts a colon at the cursor in the button text.
emojis can be added just the same as any other character. however colon can be used to zoom the emoji:
😄 hello  - gives emoji + hello
😄:hello  - gives double size emoji - above the word  hello
"""
	
	private let smartHelpButtonClearColor = """
Clears the button color.
The preview becomes transparent and shows a background image.
"""
	
	private let smartHelpButtonRandomColor = """
Sets a random button color.
"""
	
	private let smartHelpButtonVisibility = """
Toggles whether this button is visible on the main screen.
On the main screen, the button is invisible, but the hit area still exists. 
This is so you can place some buttons on an image, 
and the image is basically showing you where the hit areas are.
"""
	
	private let smartHelpSFArrows = """
Moves to the previous or next button while staying in the smart editor.
"""
	
	private let smartHelpSFTestButton = """
Runs the command text (top-left) without closing the smart editor.
This only sends keys to the ESP32 via bluetooth.
"""
	
	private let smartHelpCommandSwitchWidgets = """
**widget command table**

Widgets are small commands: for example, displaying a clock, tap counters, stopwatches, etc.

Tapping a row inserts the command at the cursor.
"""
	
	private let smartHelpCommandSwitchSpecialKeys = """
**special-key table**

Tapping a row inserts the key code at the cursor.
"""
	//
	//----------------------------------------
	//
	@State private var isSmartEscapeCodeTableVisible = false
    @State private var smartScriptEditingModel = SmartScriptEditingModel()
    @State private var smartPasteTarget = SmartEditorPasteTarget()
    @State private var softEditorAccessorySessionID = UUID()
    @State private var softEditorInsertionTargetRefreshID: UUID?
    // MARK: - BM:🅱️ add your comments here
    // Tools visibility changes only from the explicit Quick toggle or after successful
    // filename insertion. Editor focus, color/keypad/table actions and session invalidation
    // must not dismiss the Tools panel.
    @State private var isSoftEditorAccessoryPaletteVisible = false
    @State private var smartButtonBrightness = 0.5
    @State private var smartButtonBrightnessBaseHex: String?
    @State private var smartButtonPreviewFontSize = 34.0
    @State private var smartButtonPreviewSelectionRange = NSRange(location: 0, length: 0)
    @State private var isSmartPhoneSFSymbolMode = false
    @State private var keyboardMinY: CGFloat = .greatestFiniteMagnitude
    @State private var editorGeometryFrames: [EditorGeometryProbeTarget: CGRect] = [:]
    @State private var iPhoneButtonBrightnessSliderGlobalFrame: CGRect?
    @State private var smartIPhoneRightTableVisibleCellHeight: CGFloat?
    @State private var popupDismissTask: Task<Void, Never>?
    @State private var mainGridOperationMessageText: String?
    @State private var mainGridOperationMessageDismissTask: Task<Void, Never>?
    @State private var isDeleteAllButtonsConfirmationPresented = false
    private let iPhoneOrdinaryPreviewFontMultiplier: CGFloat = 1.5
    private let iPadSFSymbolPreviewGroupYOffset: CGFloat = 5
    private let iPadSFPreviewSizeMultiplier: CGFloat = 1.10
    private let iPhoneSFSymbolPreviewGroupMultiplier: CGFloat = 1.25
    @State var presentedPreviewFile: PreviewedFile?
    @AppStorage("selectedTextToSpeechVoiceIdentifier") var selectedTextToSpeechVoiceIdentifier = ""
    @AppStorage("textToSpeechRate") var textToSpeechRate = Double(AVSpeechUtteranceDefaultSpeechRate)
    @AppStorage("selectedBackgroundImageIndex") var selectedBackgroundImageIndex = 0
    @AppStorage("selectedBackgroundImageName") var selectedBackgroundImageName = ""
    @AppStorage("selectedBackgroundImagePath") var selectedBackgroundImagePath = ""
    @AppStorage("backgroundImageOpacity") var backgroundImageOpacity = 0.5
    @AppStorage("mainGridEditClipboardText") var mainGridEditClipboardText = ""
    @FocusState var isDocumentNameFieldFocused: Bool
    @FocusState var isSlotEditorFocused: Bool
    @FocusState private var isMainScreenKeyboardFocused: Bool
    let functionKeys: [FunctionKeyEntry]
    let midiDocumentSession: UUID
    let isMainScreenVisible: Bool
    let documentFiles: [URL]
    let selectedDocumentName: String
    let selectedDocumentDisplayName: String
    @Binding var boxFontSize: Double
    @Binding var mainGridBackgroundOpacity: Double
    let currentFileNumber: Int
    let totalFileCount: Int
    let definedFunctionKeyCount: Int
    let refreshDocumentFiles: () -> Void
    let loadFunctionKeys: (URL) -> Void
    let saveSelectedDocumentAndReload: (String) -> Void
    let renameDocument: (String) -> String?
    let deleteDocument: (URL) -> Void
    let duplicateDocument: (URL) -> Void
    let canDeleteDocuments: Bool
    let selectPreviousDocument: () -> Void
    let selectNextDocument: () -> Void
    let goBackToPreviousDocument: () -> Void
    let goForwardToNextDocument: () -> Void
    let canGoBackToPreviousDocument: Bool
    let previousDocumentDisplayName: String?
    let adjacentPreviousDocumentDisplayName: String?
    let adjacentNextDocumentDisplayName: String?
    let selectDocumentNamedFromGrid: (String) -> Bool
    let resizeVisibleBoxCount: (GridDimensions, GridDimensions) -> Bool
    let moveFunctionKeySlot: (Int, Int, Int, GridDimensions) -> Int?
    let duplicateFunctionKeySlot: (Int, Int) -> Bool
    let updateFunctionKeySlot: (Int, String) -> Bool
    let currentFunctionKeySlotLines: () -> [String]
    let restoreFunctionKeySlotLines: ([String]) -> Bool
    let loadGridDimensions: (String, Int) -> GridDimensions
    let saveGridDimensions: (String, GridDimensions) -> Void
    let openKeyboardScreen: () -> Void
    let openSettingsScreen: () -> Void
    let isSettingsScreenPresented: Bool
    @Binding var settingsBLEText: String

    var body: some View {
        mainScreenContent
            .focusable()
            .focused($isMainScreenKeyboardFocused)
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow], phases: [.down, .repeat]) { keyPress in
                handleExternalArrowKeyPress(keyPress.key)
            }
            .task(id: isEditingDocumentName) {
                guard isEditingDocumentName else { return }
                isDocumentNameFieldFocused = true
            }
            .onAppear {
                installMIDISessionCleanup()
                restorePersistedMainScreenModes()
                reloadSelectedDocumentIfAvailable()
                refreshMainScreenKeyboardFocus()
            }
            .onChange(of: selectedDocumentDisplayName) {
                handleSelectedDocumentDisplayNameChange()
            }
            .onChange(of: midiDocumentSession) {
                resetMIDIActivations()
            }
            .onChange(of: functionKeys.map(\.rawLine)) {
                resetMIDIActivations()
            }
            .onChange(of: midiDefaultChannel) {
                resetMIDIActivations()
            }
            .onChange(of: mainGridButtonMode) {
                resetMIDIActivations()
            }
            .onChange(of: midiInputEnabled) {
                if !midiInputEnabled { resetMIDIActivations() }
            }
            .onChange(of: macConnection.midiSessionID) {
                midiCCDisplayValues.removeAll()
            }
            .onChange(of: selectedDocumentName) {
                resetMIDIActivations()
                cancelPendingPopupRestore()
                cancelPendingMovePopupRefresh()
                cancelPendingActionMenuFrameRefresh()
                mainGridRenderedActionMenuTargets.removeAll()
                clearPopupUndoHistory()
                resetDirectionalDeleteState()
                showFilenameToastIfNeeded()
            }
            .onChange(of: editingSlotIndex) {
                handleSpeechRecognitionEditingStateChange()
                if editingSlotIndex != nil {
                    resetDirectionalDeleteState()
                    dismissMainGridActionMenu()
                } else {
                    restorePendingMainGridActionMenuIfPossible()
                }
                smartButtonBrightness = 0.5
                smartButtonBrightnessBaseHex = smartButtonColorHex
            }
            .onChange(of: isGridEditModeEnabled) {
                handleSpeechRecognitionEditingStateChange()
                if !isGridEditModeEnabled {
                    cancelPendingPopupRestore()
                    resetDirectionalDeleteState()
                    dismissMainGridActionMenu()
                }
            }
            .onChange(of: definedFunctionKeyCount) {
                updateVisibleBoxCountToFitDefinedButtons()
            }
            .onChange(of: isDocumentNameFieldFocused) {
                handleDocumentNameFieldFocusChange()
            }
            .onChange(of: isSpkRecEnabled) {
                handleSpeechRecognitionToggle()
            }
            .onChange(of: speechRecognitionAutoOffMinutes) {
                handleSpeechRecognitionAutoOffMinutesChange()
            }
            .onChange(of: speechRecognition.latestRecognition) {
                handleLatestRecognizedTextChange()
            }
            .onChange(of: isSettingsScreenPresented) {
                guard !isSettingsScreenPresented else { return }
                reloadSelectedDocumentIfAvailable()
            }
            .onChange(of: areExternalKeyboardCommandsDisabled) {
                refreshMainScreenKeyboardFocus()
            }
            .onDisappear {
                resetMIDIActivations()
                if macConnection.midiSessionWillEnd?.ownerID == midiActivations.ownerID {
                    macConnection.midiSessionWillEnd = nil
                }
                handleMainScreenDisappear()
                mainGridAmbientSoundState.stopPlayback()
                popupDismissTask?.cancel()
                filenameToastDismissTask?.cancel()
                mainGridOperationMessageDismissTask?.cancel()
                presentedPreviewFile = nil
            }
            .task(id: definedFunctionKeyCount) {
                updateVisibleBoxCountToFitDefinedButtons()
            }
            .task {
                await observeKeyboardFrameChanges()
            }
            .onChange(of: renameAlertMessage) {
                schedulePopupDismissIfNeeded()
            }
            .fullScreenCover(item: $presentedPreviewFile) { previewedFile in
                MainScreenFilePreviewOverlay(
                    previewedFile: previewedFile,
                    onClose: {
                        ButtonClickFeedback.playIfEnabled()
                        presentedPreviewFile = nil
                    }
                )
                .onAppear {
                }
                .onDisappear {
                }
            }
            .alert(
                "Delete all buttons?",
                isPresented: $isDeleteAllButtonsConfirmationPresented
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Delete All", role: .destructive) {
                    deleteAllButtonsOnCurrentScreen()
                }
            } message: {
                Text("This will delete every button on the current screen. You can restore them using Undo.")
            }
    }

    private var mainScreenContent: some View {
        GeometryReader { geometry in
            let horizontalContentInset: CGFloat = 0
            let contentWidth = max(0, geometry.size.width - (horizontalContentInset * 2))
            let topContentInset: CGFloat = 0
            let bottomContentInset: CGFloat = 0
            let iPhonePhysicalContentHeight = geometry.size.height + geometry.safeAreaInsets.bottom
            let iPhoneFallbackGridBottomY = iPhonePhysicalContentHeight
                - iPhoneBottomToolbarRegionHeight
                - iPhoneGridToBottomToolbarClearance
            let iPhoneToolbarTopY = iPhoneBottomToolbarFrame.map { frame in
                frame.minY - geometry.frame(in: .global).minY
            }
            // MARK: - BM:🅱️ Match the grid to the rendered toolbar position when it is available.
            let iPhoneGridBottomY = (iPhoneToolbarTopY.map { $0 - iPhoneGridToBottomToolbarClearance })
                ?? iPhoneFallbackGridBottomY
            let iPhoneGridHeight = max(
                0,
                iPhoneGridBottomY
                - mainTopToolbarHeight
                - topToolbarToGridSpacing
            )
            
			let containerFrame = geometry.frame(in: .global)
            
			let maskBottomY = min(containerFrame.maxY, keyboardMinY)
            let maskHeight = max(0, maskBottomY - containerFrame.minY)
            let maskedScreenHeight = maskHeight + geometry.safeAreaInsets.top

            ZStack(alignment: .top) {
                VStack(spacing: 0) {
						
						MainScreenToolbarContent(
							isGridEditModeEnabled: isGridEditModeEnabled,
						editingSlotIndex: editingSlotIndex,
						currentFileNumber: currentFileNumber,
						totalFileCount: totalFileCount,
						currentBackgroundImageNumber: selectedBackgroundImageIndex,
						totalBackgroundImageCount: availableBackgroundImageURLs.count,
                        outputMode: outputMode,
                        isBluetoothConnected: ble.isConnected,
                        isMacConnected: macConnection.canSend,
						backgroundImageOpacity: $backgroundImageOpacity,
						gridBackgroundOpacity: $mainGridBackgroundOpacity,
						isEditingDocumentName: $isEditingDocumentName,
						documentNameDraft: $documentNameDraft,
						selectedDocumentDisplayName: selectedDocumentDisplayName,
						isHomeDocumentSelected: isHomeDocumentSelected,
						isDocumentNameFieldFocused: $isDocumentNameFieldFocused,
						openKeyboardScreen: openKeyboardScreen,
						openHomeDocument: openHomeDocumentFromMainScreenControl,
						canGoBackToPreviousDocument: canGoBackToPreviousDocument,
						goBackToPreviousDocument: goBackToPreviousDocumentFromMainScreenControl,
						selectPreviousDocument: selectPreviousDocumentFromMainScreenControl,
						selectNextDocument: selectNextDocumentFromMainScreenControl,
						selectPreviousBackgroundImage: selectPreviousBackgroundImage,
						selectRandomBackgroundImage: selectRandomBackgroundImage,
						selectNextBackgroundImage: selectNextBackgroundImage,
                        showCurrentFilename: showFilenameToastIfNeeded,
						toggleGridEditMode: { isGridEditModeEnabled.toggle() },
						commitDocumentRename: commitDocumentRename,
						openSettings: AnyView(
							Button {
								ButtonClickFeedback.playIfEnabled()
								openSettingsScreen()
							} label: {
								settingsToolbarButtonLabel
							}
								.buttonStyle(.plain)
						)
						)
						
						
                    Color.clear
                        .frame(height: topToolbarToGridSpacing)

                    if isPad {
                        mainGridSection(availableWidth: contentWidth)

                        Color.clear
                            .frame(height: iPadGridToBottomToolbarSpacing)

                        displayModeButtonSection(availableWidth: contentWidth)
                            .background {
                                GeometryReader { toolbarGeometry in
                                    Color.clear.preference(
                                        key: IPadBottomToolbarFramePreferenceKey.self,
                                        value: toolbarGeometry.frame(in: .named(mainScreenPopupCoordinateSpaceName))
                                    )
                                }
                            }
                    } else {
                        mainGridSection(
                            availableWidth: contentWidth,
                            reservedBottomInset: iPhoneGridReservedBottomInset
                        )
                            .frame(height: iPhoneGridHeight)
                    }
                }
                .frame(width: contentWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, topContentInset)
                .padding(.bottom, bottomContentInset)
                .ignoresSafeArea(.keyboard)

                if !isPad {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)

                        displayModeButtonSection(availableWidth: contentWidth)
                            .background {
                                IPhoneBottomToolbarFrameReporter()
                            }
                    }
                    .frame(width: contentWidth)
                    .frame(height: geometry.size.height, alignment: .bottom)
                    .ignoresSafeArea(.keyboard)
                    .ignoresSafeArea(.container, edges: .bottom)
                }

                if editingSlotIndex != nil, isPad {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .mask(alignment: .top) {
                            Rectangle()
                                .frame(height: maskedScreenHeight)
                                .padding(.horizontal, -2)
                        }
                        .contentShape(Rectangle())
                        .allowsHitTesting(false)
                }

                if editingSlotIndex != nil {
                    if isPad {
                        if ESP001DiagnosticDevice.usesESP001DiagnosticEditor {
                            esp001MiniDiagnosticEditor(availableWidth: contentWidth)
                                .editorGeometryProbe(.editorContainer, isEnabled: debugEditorGeometry)
                        } else {
                            smartView(availableWidth: contentWidth)
                                .editorGeometryProbe(.editorContainer, isEnabled: debugEditorGeometry)
                        }
                    } else {
                        iPhoneSmartEditorPresentation(availableWidth: contentWidth)
                            .editorGeometryProbe(.editorContainer, isEnabled: debugEditorGeometry)
                    }
                }

                popupOverlay(
                    isSlotEditorPresented: editingSlotIndex != nil,
                    maskedScreenHeight: maskedScreenHeight
                )

                filenameToastOverlay(availableWidth: contentWidth)

                mainGridOperationMessageOverlay(availableWidth: contentWidth)

                mainGridActionMenuOverlay(
                    availableWidth: contentWidth,
                    availableHeight: geometry.size.height,
                    safeAreaInsets: geometry.safeAreaInsets,
                    gridTopY: topContentInset + mainTopToolbarHeight + topToolbarToGridSpacing,
                    gridHeight: iPhoneGridHeight
                )

                iPhoneButtonBrightnessTouchOverlay(containerFrame: containerFrame)

            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .coordinateSpace(name: mainScreenPopupCoordinateSpaceName)
            .overlayPreferenceValue(SoftEditorAccessoryBounds.self) { anchors in
                softEditorAccessoryOverlay(anchors: anchors)
            }
            .onChange(of: editingSlotIndex) {
                invalidateSoftEditorAccessorySession()
                softEditorInsertionTargetRefreshID = UUID()
            }
            .onChange(of: selectedDocumentName) { invalidateSoftEditorAccessorySession() }
            .onDisappear { invalidateSoftEditorAccessorySession() }
            .onPreferenceChange(IPadBottomToolbarFramePreferenceKey.self) { frame in
                let toolbarTopY = frame?.minY
                if iPadBottomToolbarTopY != toolbarTopY {
                    iPadBottomToolbarTopY = toolbarTopY
                }
            }
            .onPreferenceChange(MainScreenBottomBarVisibleContentFramePreferenceKey.self) { frame in
                let toolbarVisibleContentTopY = frame.flatMap { frame in
                    frame.minY.isFinite && frame.height > 0 ? frame.minY : nil
                }
                if iPadBottomToolbarVisibleContentTopY != toolbarVisibleContentTopY {
                    iPadBottomToolbarVisibleContentTopY = toolbarVisibleContentTopY
                }
            }
            .onPreferenceChange(IPhoneBottomToolbarFramePreferenceKey.self) { frame in
                guard !isPad, iPhoneBottomToolbarFrame != frame else { return }
                iPhoneBottomToolbarFrame = frame
            }
            .editorGeometryProbe(.screen, isEnabled: debugEditorGeometry)
            .ignoresSafeArea(.keyboard)
        }
        .onPreferenceChange(EditorGeometryPreferenceKey.self) { frames in
            guard debugEditorGeometry else { return }
            editorGeometryFrames = frames
        }
        .onPreferenceChange(SmartIPhoneRightTableVisibleCellHeightPreferenceKey.self) { height in
            guard !isPad, let height, height > 0 else { return }

            if smartIPhoneRightTableVisibleCellHeight != height {
                smartIPhoneRightTableVisibleCellHeight = height
            }
        }
        .onPreferenceChange(IPhoneButtonBrightnessSliderFramePreferenceKey.self) { frame in
            if iPhoneButtonBrightnessSliderGlobalFrame != frame {
                iPhoneButtonBrightnessSliderGlobalFrame = frame
            }
        }
        .padding(.horizontal, ESP001DiagnosticDevice.isIPadMini5 && editingSlotIndex != nil ? 0 : (isPad || editingSlotIndex == nil ? 2 : 0))
        .ignoresSafeArea(.keyboard)
        .overlay(alignment: .topLeading) {
            if debugEditorGeometry, isPad, editingSlotIndex != nil {
                DebugEditorGeometryOverlay(frames: editorGeometryFrames)
                    .padding(8)
            }
        }
        .overlay(alignment: .topLeading) {
            externalKeyboardShortcutLayer
        }
    }

    @ViewBuilder
    private func iPhoneButtonBrightnessTouchOverlay(containerFrame: CGRect) -> some View {
        if !isPad,
           editingSlotIndex != nil,
           let sourceFrame = iPhoneButtonBrightnessSliderGlobalFrame {
            let destinationFrame = CGRect(
                x: sourceFrame.minX - containerFrame.minX,
                y: sourceFrame.minY - containerFrame.minY,
                width: sourceFrame.width,
                height: sourceFrame.height
            )

            IPhoneButtonBrightnessTouchOverlay(
                destinationFrame: destinationFrame,
                onBrightnessGesture: { location, height in
                    updateIPhoneButtonBrightnessFromOverlay(
                        location: location,
                        height: height
                    )
                }
            )
            .position(x: destinationFrame.midX, y: destinationFrame.midY)
        }
    }

    private func updateIPhoneButtonBrightnessFromOverlay(
        location: CGPoint,
        height: CGFloat
    ) {
        guard height.isFinite, height > 0 else { return }

        let rawBrightness = 1.0 - (location.y / height)
        let brightness = min(1.0, max(0.0, Double(rawBrightness)))

        if smartButtonBrightness != brightness {
            smartButtonBrightness = brightness
        }
    }

    private var midiGridInteractionEnabled: Bool {
        isMainScreenVisible && midiScenePhase == .active &&
        !isGridEditModeEnabled && editingSlotIndex == nil && presentedPreviewFile == nil &&
        mainGridButtonMode.sendsBluetooth
    }

    private var midiOutputAvailable: Bool {
        outputMode == .mac && macConnection.canSend
    }

    // MARK: - BM:🅱️ MIDI ownership outlives individual touch views; every release consumes a unique token.
    private var midiInputEnabled: Bool {
        midiGridInteractionEnabled && midiOutputAvailable
    }

    private var midiUnavailableWarningEnabled: Bool {
        midiGridInteractionEnabled && !midiOutputAvailable
    }

    func showMIDIOutputUnavailableWarning() {
        guard midiUnavailableWarningEnabled else { return }
        presentMIDIOutputUnavailableWarning()
    }

    private func showSoftEditorMIDIOutputUnavailableWarning() {
        presentMIDIOutputUnavailableWarning()
    }

    private func presentMIDIOutputUnavailableWarning() {
        alertTitle = "MIDI output unavailable"
        renameAlertMessage = "Select Mac output and connect to ESP Mac Helper\nbefore sending MIDI commands."
    }

    private func midiTouchContext(_ entry: FunctionKeyEntry, index: Int) -> MainMIDITouchContext? {
        let message: MainMIDITouchContext.Message
        let channel: UInt8
        if let command = midiCommandForGridEntry(entry) {
            message = command.kind == .off
                ? .noteOff(number: command.note)
                : .note(number: command.note, velocity: command.velocity, mode: command.mode)
            channel = MIDIChannelSettings.resolvedChannel(for: command, defaultChannel: midiDefaultChannel)
        } else if let command = midiControlChangeCommandForGridEntry(entry), command.mode != .oneShot {
            message = command.mode == .hold
                ? .controlChangeHold(
                    controller: command.controller,
                    value: command.value,
                    endValue: command.endValue
                )
                : .controlChangeToggle(
                    controller: command.controller,
                    value: command.value,
                    endValue: command.endValue
                )
            channel = MIDIChannelSettings.resolvedChannel(
                channelOverride: command.channelOverride, defaultChannel: midiDefaultChannel
            )
        } else {
            return nil
        }
        return MainMIDITouchContext(
            documentSession: midiDocumentSession,
            documentName: selectedDocumentName,
            slot: index,
            commandText: entry.rawLine,
            generation: midiActivations.generation,
            connectionSession: macConnection.midiSessionID,
            message: message,
            channel: channel
        )
    }

    func midiCCDisplayValue(for entry: FunctionKeyEntry, index: Int) -> UInt8? {
        guard let context = midiTouchContext(entry, index: index),
              let key = MainGridMIDICCDisplayKey(context) else {
            return nil
        }
        return midiCCDisplayValues[key]
    }

    private func sendMIDIActivationOn(_ context: MainMIDITouchContext) -> Bool {
        switch context.message {
        case .note(let note, let velocity, _):
            return sendMIDINoteOnFromTouch(
                MIDINoteIdentity(note: note, channel: context.channel), velocity: velocity
            )
        case .noteOff:
            return false
        case .controlChangeHold(let controller, let value, _), .controlChangeToggle(let controller, let value, _):
            guard midiInputEnabled, context.connectionSession == macConnection.midiSessionID else { return false }
            let accepted = macConnection.sendAuthenticatedCommand(
                "MIDI:CC:\(controller):\(value):\(context.channel)"
            )
            if accepted {
                updateMIDICCDisplayValue(context, value: value)
            }
            return accepted
        }
    }

    private func sendMIDIActivationOff(_ context: MainMIDITouchContext) {
        guard context.connectionSession == macConnection.midiSessionID else { return }
        switch context.message {
        case .note(let note, _, _):
            _ = sendMIDINoteOffFromTouch(MIDINoteIdentity(note: note, channel: context.channel))
        case .noteOff:
            break
        case .controlChangeHold(_, _, let endValue), .controlChangeToggle(_, _, let endValue):
            guard macConnection.canSend else { return }
            if macConnection.sendAuthenticatedCommand(context.releaseCommand) {
                updateMIDICCDisplayValue(context, value: endValue)
            }
        }
    }

    private func updateMIDICCDisplayValue(_ context: MainMIDITouchContext, value: UInt8) {
        guard let key = MainGridMIDICCDisplayKey(context),
              context.documentSession == midiDocumentSession,
              context.documentName == selectedDocumentName,
              context.connectionSession == macConnection.midiSessionID,
              functionKeys.indices.contains(context.slot),
              functionKeys[context.slot].rawLine == context.commandText else {
            return
        }
        midiCCDisplayValues[key] = value
    }

    private func beginMIDIActivation(_ context: MainMIDITouchContext) -> UUID? {
        guard midiInputEnabled,
              context.documentSession == midiDocumentSession,
              context.documentName == selectedDocumentName,
              context.connectionSession == macConnection.midiSessionID,
              functionKeys.indices.contains(context.slot),
              functionKeys[context.slot].rawLine == context.commandText else { return nil }
        if case .noteOff(let note) = context.message {
            let identity = MIDINoteIdentity(note: note, channel: context.channel)
            guard sendMIDINoteOffFromTouch(identity) else {
                return nil
            }
            midiActivations.reconcileExplicitNoteOff(
                identity,
                connectionSession: context.connectionSession
            )
            return nil
        }
        if context.mode == .toggle {
            return midiActivations.activeToken(for: context)
        }
        return midiActivations.begin(context) {
            sendMIDIActivationOn(context)
        }
    }

    private func toggleMIDIActivation(_ context: MainMIDITouchContext, expectedToken: UUID?) {
        guard midiInputEnabled,
              context.documentSession == midiDocumentSession,
              context.documentName == selectedDocumentName,
              context.connectionSession == macConnection.midiSessionID,
              functionKeys.indices.contains(context.slot),
              functionKeys[context.slot].rawLine == context.commandText else { return }
        midiActivations.toggle(
            context,
            expectedToken: expectedToken,
            connectionSession: macConnection.midiSessionID,
            sendOn: {
                sendMIDIActivationOn(context)
            },
            sendControlChangeOff: { activation in
                guard activation.connectionSession == macConnection.midiSessionID,
                      macConnection.canSend else { return false }
                let accepted = macConnection.sendAuthenticatedCommand(activation.releaseCommand)
                if accepted,
                   case .controlChangeToggle(_, _, let endValue) = activation.message {
                    updateMIDICCDisplayValue(activation, value: endValue)
                }
                return accepted
            },
            sendOff: sendMIDIActivationOff
        )
    }

    private func endMIDIActivation(_ token: UUID) {
        midiActivations.release(
            token,
            connectionSession: macConnection.midiSessionID,
            sendOff: sendMIDIActivationOff
        )
    }

    private func resetMIDIActivations() {
        midiCCDisplayValues.removeAll()
        midiActivations.reset(
            connectionSession: macConnection.midiSessionID,
            sendOff: sendMIDIActivationOff
        )
    }

    private func installMIDISessionCleanup() {
        macConnection.midiSessionWillEnd = (midiActivations.ownerID, { [weak midiActivations, weak macConnection] canTransmit in
            guard let midiActivations, let macConnection else { return }
            midiActivations.reset(connectionSession: macConnection.midiSessionID) { activation in
                guard canTransmit, macConnection.canSend else { return }
                _ = macConnection.sendAuthenticatedCommand(
                    activation.releaseCommand
                )
            }
        })
    }

    private func mainGridSection(availableWidth: CGFloat, reservedBottomInset: CGFloat = 0) -> some View {

        MainScreenGridSection(
            availableWidth: availableWidth,
            reservedBottomInset: reservedBottomInset,
            functionKeys: functionKeys,
            visibleBoxCount: visibleBoxCount,
            visibleGridDimensions: visibleGridDimensions,
            mainGridButtonSpacing: mainGridButtonSpacing,
            mainGridButtonCornerRadius: mainGridButtonCornerRadius,
            boxFontSize: boxFontSize,
            clipsButtonContentToBounds: true,
            isGridEditModeEnabled: isGridEditModeEnabled,
            selectedActionMenuIndex: mainGridActionMenuTarget?.index,
            renderedButtonFrameRefreshToken: mainGridRenderedButtonFrameRefreshToken,
            bleSendEnabled: mainGridButtonMode != .disabled,
            onButtonClick: { ButtonClickFeedback.playIfEnabled() },
            onAcceptedOrdinaryButtonTap: { entry in
                #if DEBUG
                printMainGridButtonActivation(entry, via: "tap")
                #endif
            },
            isHiddenEntry: isMainGridEntryHidden,
            isEmptyEntry: isEmptyButtonEntry,
            isInteractiveWidgetEntry: isInteractiveMainGridWidgetEntry,
            isSimpleOrdinarySoundEntry: isSimpleOrdinarySoundEntry,
            midiContext: midiTouchContext,
            midiActivations: midiActivations,
            midiInputEnabled: midiInputEnabled,
            midiUnavailableWarningEnabled: midiUnavailableWarningEnabled,
            onMIDITouchDown: beginMIDIActivation,
            onMIDITouchUp: endMIDIActivation,
            onMIDITogglePress: toggleMIDIActivation,
            onMIDIOutputUnavailableAttempt: showMIDIOutputUnavailableWarning,
            sendLine: { entry in
                sendMainGridEntry(entry, defaultMIDIChannel: midiDefaultChannel)
            },
            onSimpleOrdinarySoundSingleTap: handleSimpleOrdinarySoundSingleTap,
            onSimpleOrdinarySoundDoubleTap: handleSimpleOrdinarySoundDoubleTap,
            onBeginSlotEditing: beginSlotEditing,
            buttonLabel: { entry, index, buttonHeight, buttonSize in
                mainGridButtonLabel(
                    entry: entry,
                    index: index,
                    buttonHeight: buttonHeight,
                    buttonSize: buttonSize,
                    backgroundOpacity: mainGridBackgroundOpacity,
                    defaultMIDIChannel: midiDefaultChannel
                )
            },
            dragGesture: { entry, index, gridDimensions in
                AnyGesture(mainGridButtonDragGesture(entry: entry, index: index, gridDimensions: gridDimensions))
            },
            onRenderedButtonFrame: { index, buttonFrame, gridDimensions in
                rememberRenderedMainGridButtonFrame(
                    index: index,
                    buttonFrame: buttonFrame,
                    gridDimensions: gridDimensions
                )
            },
            onRenderedGridFrame: { frame in
                rememberRenderedMainGridFrame(frame)
            },
            onSingleEditTap: { entry, index, buttonFrame, gridDimensions in
                presentMainGridActionMenu(
                    entry: entry,
                    index: index,
                    buttonFrame: buttonFrame,
                    gridDimensions: gridDimensions
                )
            },
            onResizeSlot: { entry, index, gridDimensions in
                resizeSlotIfPossible(entry: entry, index: index, gridDimensions: gridDimensions)
            },
            onResetSlotSize: { entry, index, gridDimensions in
                resetSlotSizeIfNeeded(entry: entry, index: index, gridDimensions: gridDimensions)
            },
            onDeleteSlot: { entry, index in
                deleteSlotIfPossible(entry: entry, index: index)
            }
        )
    }

    @ViewBuilder
    private func mainGridActionMenuOverlay(
        availableWidth: CGFloat,
        availableHeight: CGFloat,
        safeAreaInsets: EdgeInsets,
        gridTopY: CGFloat,
        gridHeight: CGFloat
    ) -> some View {
        if let mainGridActionMenuTarget {
            let menuSize = MainGridEditActionMenu.Metrics.menuSize
            let menuCornerRadius = isPad ? MainGridEditActionMenu.Metrics.cornerRadius : mainGridButtonCornerRadius
            let isButtonOperationAvailable = mainGridActionMenuSelectionContainsButton(mainGridActionMenuTarget)
            let isPasteAvailable = canPasteMainGridActionMenuSelection(to: mainGridActionMenuTarget)
            let resolvedGridHeight = resolvedMainGridActionMenuBoundaryHeight(
                gridTopY: gridTopY,
                fallbackGridHeight: gridHeight
            )
            if let resolvedGridHeight {
                let menuPosition = mainGridActionMenuPosition(
                    for: mainGridActionMenuTarget.buttonFrame,
                    menuSize: menuSize,
                    availableWidth: availableWidth,
                    availableHeight: availableHeight,
                    safeAreaInsets: safeAreaInsets,
                    gridTopY: gridTopY,
                    gridHeight: resolvedGridHeight
                )

                Group {
                    switch mainGridActionMenuMode {
                    case .actions:
                        MainGridEditActionMenu(
                            cornerRadius: menuCornerRadius,
                            isUndoAvailable: !popupUndoHistory.isEmpty,
                            isRedoAvailable: !popupRedoHistory.isEmpty,
                            isButtonOperationAvailable: isButtonOperationAvailable,
                            isPasteAvailable: isPasteAvailable
                        ) {
                            ButtonClickFeedback.playIfEnabled()
                            openMainGridActionMenuEditor()
                        } onUndo: {
                            ButtonClickFeedback.playIfEnabled()
                            undoMainGridActionMenuOperation()
                        } onRedo: {
                            ButtonClickFeedback.playIfEnabled()
                            redoMainGridActionMenuOperation()
                        } onCopy: {
                            ButtonClickFeedback.playIfEnabled()
                            copyMainGridActionMenuSelection()
                        } onCut: {
                            ButtonClickFeedback.playIfEnabled()
                            cutMainGridActionMenuSelection()
                        } onPaste: {
                            ButtonClickFeedback.playIfEnabled()
                            pasteMainGridActionMenuSelection()
                        } onDuplicate: {
                            ButtonClickFeedback.playIfEnabled()
                            duplicateMainGridActionMenuSelection()
                        } onResize: {
                            ButtonClickFeedback.playIfEnabled()
                            openMainGridResizeActionMenu()
                        } onDelete: {
                            ButtonClickFeedback.playIfEnabled()
                            deleteMainGridActionMenuSelection()
                        }
                    case .resize:
                        MainGridResizeActionMenu(
                            cornerRadius: menuCornerRadius,
                            selectedShape: currentMainGridActionMenuShape(),
                            isShapeEnabled: { shape in
                                isMainGridResizeShapeAvailable(shape, for: mainGridActionMenuTarget)
                            }
                        ) {
                            ButtonClickFeedback.playIfEnabled()
                            mainGridActionMenuMode = .actions
                        } onSelectShape: { shape in
                            ButtonClickFeedback.playIfEnabled()
                            resizeMainGridActionMenuSelection(to: shape)
                        }
                    }
                }
                .frame(width: menuSize.width, height: menuSize.height)
                .position(menuPosition)
                .zIndex(50)
            }
        }
    }

    private func presentMainGridActionMenu(
        entry: FunctionKeyEntry,
        index: Int,
        buttonFrame: CGRect,
        gridDimensions: GridDimensions
    ) {
        guard isGridEditModeEnabled,
              editingSlotIndex == nil else {
            return
        }

        if mainGridActionMenuTarget?.index == index {
            dismissMainGridActionMenu()
            return
        }

        let hadActionMenuTarget = mainGridActionMenuTarget != nil
        cancelPendingMovePopupRefresh()
        cancelPendingActionMenuFrameRefresh()
        if directionalDeleteDirection != nil,
           directionalDeleteExpectedAnchor != index {
            resetDirectionalDeleteState()
        }

        mainGridActionMenuTarget = MainGridActionMenuTarget(
            index: index,
            buttonFrame: buttonFrame,
            gridDimensions: gridDimensions
        )
        if !hadActionMenuTarget {
            mainGridActionMenuMode = .actions
        }
    }

    func dismissMainGridActionMenu() {
        cancelPendingMovePopupRefresh()
        cancelPendingActionMenuFrameRefresh()
        mainGridActionMenuTarget = nil
        mainGridActionMenuMode = .actions
    }

    func dismissMainGridActionMenuUnlessTargeted(at index: Int) {
        guard mainGridActionMenuTarget?.index != index else {
            return
        }

        dismissMainGridActionMenu()
    }

    private func openMainGridActionMenuEditor() {
        guard let target = mainGridActionMenuTarget,
              target.index >= 0,
              target.index < visibleBoxCount else {
            dismissMainGridActionMenu()
            return
        }

        let selectedIndex = target.index
        pendingPopupRestoreIndex = selectedIndex
        pendingPopupRestoreDocumentName = selectedDocumentName
        dismissMainGridActionMenu()
        beginSlotEditing(at: selectedIndex)
    }

    private func openMainGridResizeActionMenu() {
        guard isGridEditModeEnabled,
              let target = mainGridActionMenuTarget,
              popupButtonShapeForActionMenu(at: target.index, gridDimensions: target.gridDimensions) != nil else {
            return
        }

        mainGridActionMenuMode = .resize
    }

    private func mainGridActionMenuSelectionContainsButton(_ target: MainGridActionMenuTarget) -> Bool {
        mainGridIndexContainsButton(target.index)
    }

    private func mainGridIndexContainsButton(_ index: Int) -> Bool {
        guard isGridEditModeEnabled,
              index >= 0,
              index < functionKeys.count,
              index < visibleBoxCount,
              !isMainGridContinuationEntry(at: index),
              !functionKeys[index].isBlankPlaceholder,
              !isEmptyButtonEntry(functionKeys[index]) else {
            return false
        }

        return true
    }

    private func rememberRenderedMainGridButtonFrame(
        index: Int,
        buttonFrame: CGRect,
        gridDimensions: GridDimensions
    ) {
        guard index >= 0,
              index < visibleBoxCount else {
            return
        }

        let renderedTarget = MainGridActionMenuTarget(
            index: index,
            buttonFrame: buttonFrame,
            gridDimensions: gridDimensions
        )
        let existingTarget = mainGridRenderedActionMenuTargets[index]
        if existingTarget?.buttonFrame == buttonFrame,
           existingTarget?.gridDimensions.columns == gridDimensions.columns,
           existingTarget?.gridDimensions.rows == gridDimensions.rows {
            if refreshPendingMovedMainGridActionMenuIfPossible(with: renderedTarget) {
                return
            }
            _ = refreshPendingActionMenuFrameIfPossible(with: renderedTarget)
            return
        }

        mainGridRenderedActionMenuTargets[index] = renderedTarget
        if refreshPendingMovedMainGridActionMenuIfPossible(with: renderedTarget) {
            return
        }
        if refreshPendingActionMenuFrameIfPossible(with: renderedTarget) {
            return
        }
        restorePendingMainGridActionMenuIfPossible()
    }

    private func rememberRenderedMainGridFrame(_ frame: CGRect) {
        guard frame.width.isFinite,
              frame.height.isFinite,
              frame.width > 0,
              frame.height > 0 else {
            return
        }

        if mainGridRenderedFrame != frame {
            mainGridRenderedFrame = frame
        }
    }

    private func resolvedMainGridActionMenuBoundaryHeight(
        gridTopY: CGFloat,
        fallbackGridHeight: CGFloat
    ) -> CGFloat? {
        guard isPad else {
            return fallbackGridHeight
        }

        guard let visualGridHeight = mainGridRenderedFrame?.height,
              let toolbarTopY = resolvedIPadBottomToolbarBoundaryTopY() else {
            return nil
        }

        return min(visualGridHeight, max(0, toolbarTopY - gridTopY))
    }

    private func resolvedIPadBottomToolbarBoundaryTopY() -> CGFloat? {
        iPadBottomToolbarVisibleContentTopY ?? iPadBottomToolbarTopY
    }

    private func cancelPendingPopupRestore() {
        pendingPopupRestoreIndex = nil
        pendingPopupRestoreDocumentName = nil
    }

    private func beginPendingMovePopupRefresh(to index: Int) {
        cancelPendingActionMenuFrameRefresh()
        pendingMovePopupRefreshIndex = index
        pendingMovePopupRefreshDocumentName = selectedDocumentName
        mainGridRenderedButtonFrameRefreshToken += 1
    }

    private func cancelPendingMovePopupRefresh() {
        pendingMovePopupRefreshIndex = nil
        pendingMovePopupRefreshDocumentName = nil
    }

    private func beginPendingActionMenuFrameRefresh(to index: Int, requiresButton: Bool) {
        cancelPendingMovePopupRefresh()
        pendingActionMenuFrameRefreshIndex = index
        pendingActionMenuFrameRefreshDocumentName = selectedDocumentName
        pendingActionMenuFrameRefreshRequiresButton = requiresButton
        mainGridRenderedButtonFrameRefreshToken += 1
    }

    private func cancelPendingActionMenuFrameRefresh() {
        pendingActionMenuFrameRefreshIndex = nil
        pendingActionMenuFrameRefreshDocumentName = nil
        pendingActionMenuFrameRefreshRequiresButton = false
    }

    @discardableResult
    private func refreshPendingMovedMainGridActionMenuIfPossible(with renderedTarget: MainGridActionMenuTarget) -> Bool {
        guard let refreshIndex = pendingMovePopupRefreshIndex,
              refreshIndex == renderedTarget.index else {
            return false
        }

        guard isGridEditModeEnabled,
              editingSlotIndex == nil,
              pendingMovePopupRefreshDocumentName == selectedDocumentName,
              mainGridActionMenuTarget?.index == refreshIndex,
              mainGridIndexContainsButton(refreshIndex) else {
            cancelPendingMovePopupRefresh()
            return false
        }

        mainGridActionMenuTarget = MainGridActionMenuTarget(
            index: renderedTarget.index,
            buttonFrame: renderedTarget.buttonFrame,
            gridDimensions: renderedTarget.gridDimensions
        )
        cancelPendingMovePopupRefresh()
        return true
    }

    @discardableResult
    private func refreshPendingActionMenuFrameIfPossible(with renderedTarget: MainGridActionMenuTarget) -> Bool {
        guard let refreshIndex = pendingActionMenuFrameRefreshIndex,
              refreshIndex == renderedTarget.index else {
            return false
        }

        guard isGridEditModeEnabled,
              editingSlotIndex == nil,
              pendingActionMenuFrameRefreshDocumentName == selectedDocumentName,
              mainGridActionMenuTarget?.index == refreshIndex,
              refreshIndex >= 0,
              refreshIndex < visibleBoxCount,
              functionKeys.indices.contains(refreshIndex),
              !isMainGridContinuationEntry(at: refreshIndex) else {
            cancelPendingActionMenuFrameRefresh()
            return false
        }

        if pendingActionMenuFrameRefreshRequiresButton,
           !mainGridIndexContainsButton(refreshIndex) {
            cancelPendingActionMenuFrameRefresh()
            return false
        }

        mainGridActionMenuTarget = MainGridActionMenuTarget(
            index: renderedTarget.index,
            buttonFrame: renderedTarget.buttonFrame,
            gridDimensions: renderedTarget.gridDimensions
        )
        mainGridActionMenuMode = .actions
        cancelPendingActionMenuFrameRefresh()
        return true
    }

    private func restorePendingMainGridActionMenuIfPossible() {
        guard let restoreIndex = pendingPopupRestoreIndex else {
            return
        }

        guard isGridEditModeEnabled,
              editingSlotIndex == nil,
              pendingPopupRestoreDocumentName == selectedDocumentName else {
            cancelPendingPopupRestore()
            return
        }

        let targetIndex = editableMainGridAnchorIndex(containing: restoreIndex) ?? restoreIndex
        guard mainGridIndexContainsButton(targetIndex) else {
            cancelPendingPopupRestore()
            return
        }

        guard let renderedTarget = mainGridRenderedActionMenuTargets[targetIndex] else {
            return
        }

        mainGridActionMenuTarget = MainGridActionMenuTarget(
            index: targetIndex,
            buttonFrame: renderedTarget.buttonFrame,
            gridDimensions: renderedTarget.gridDimensions
        )
        mainGridActionMenuMode = .actions
        cancelPendingPopupRestore()
    }

    private func canPasteMainGridActionMenuSelection(to target: MainGridActionMenuTarget) -> Bool {
        guard isGridEditModeEnabled,
              target.index >= 0,
              target.index < visibleBoxCount else {
            return false
        }

        return hasValidMainGridActionMenuPastePayload()
    }

    private func deleteMainGridActionMenuSelection() {
        guard isGridEditModeEnabled,
              let target = mainGridActionMenuTarget,
              target.index >= 0,
              target.index < functionKeys.count,
              target.index < visibleBoxCount,
              let deletedFootprint = mainGridDeleteFootprint(at: target.index, gridDimensions: target.gridDimensions) else {
            return
        }

        let beforeSnapshot = currentFunctionKeySlotLines()
        let previousFootprint = directionalDeleteLastFootprint
        let previousDirection = directionalDeleteDirection
        guard deleteSlotForPopupIfPossible(
            entry: functionKeys[target.index],
            index: target.index,
            gridDimensions: target.gridDimensions
        ) else {
            return
        }

        recordPopupUndoSnapshot(beforeSnapshot)

        let resolvedDirection = previousDirection ?? previousFootprint.flatMap {
            directionalDeleteDirection(from: $0, to: deletedFootprint)
        }

        guard let resolvedDirection,
              let nextFootprint = nextDirectionalDeleteFootprint(
                after: deletedFootprint,
                direction: resolvedDirection,
                gridDimensions: target.gridDimensions
              ) else {
            directionalDeleteLastFootprint = deletedFootprint
            directionalDeleteDirection = nil
            directionalDeleteExpectedAnchor = nil
            return
        }

        directionalDeleteLastFootprint = deletedFootprint
        directionalDeleteDirection = resolvedDirection
        directionalDeleteExpectedAnchor = nextFootprint.anchor
        mainGridActionMenuTarget = mainGridActionMenuTargetForDeleteSelection(
            from: target,
            deletedFootprint: deletedFootprint,
            nextFootprint: nextFootprint
        )
    }

    private func copyMainGridActionMenuSelection() {
        guard isGridEditModeEnabled,
              let target = mainGridActionMenuTarget,
              target.index >= 0,
              target.index < functionKeys.count,
              target.index < visibleBoxCount else {
            return
        }

        guard copySlotForPopupIfPossible(
            entry: functionKeys[target.index],
            index: target.index,
            gridDimensions: target.gridDimensions
        ) else {
            return
        }

        showMainGridActionMenuMessage("Button copied")
    }

    private func cutMainGridActionMenuSelection() {
        guard isGridEditModeEnabled,
              let target = mainGridActionMenuTarget,
              target.index >= 0,
              target.index < functionKeys.count,
              target.index < visibleBoxCount else {
            return
        }

        let beforeSnapshot = currentFunctionKeySlotLines()
        guard let cutResult = updatedSlotLinesForPopupCut(
            entry: functionKeys[target.index],
            index: target.index,
            gridDimensions: target.gridDimensions,
            slotLines: beforeSnapshot
        ) else {
            return
        }

        guard restoreFunctionKeySlotLines(cutResult.slotLines) else {
            return
        }

        resetDirectionalDeleteState()
        mainGridEditClipboardText = cutResult.clipboardText
        recordPopupUndoSnapshot(beforeSnapshot)
        beginPendingActionMenuFrameRefresh(to: target.index, requiresButton: false)
        showMainGridActionMenuMessage("Button cut")
    }

    private func pasteMainGridActionMenuSelection() {
        guard isGridEditModeEnabled,
              let target = mainGridActionMenuTarget,
              target.index >= 0,
              target.index < visibleBoxCount else {
            return
        }

        let beforeSnapshot = currentFunctionKeySlotLines()
        switch updatedSlotLinesForPopupPaste(
            at: target.index,
            gridDimensions: target.gridDimensions,
            slotLines: beforeSnapshot
        ) {
        case let .success(pasteResult):
            guard pasteResult.slotLines != beforeSnapshot else {
                return
            }

            guard restoreFunctionKeySlotLines(pasteResult.slotLines) else {
                return
            }

            resetDirectionalDeleteState()
            mainGridActionMenuTarget = mainGridActionMenuTargetForPaste(from: target, result: pasteResult)
            beginPendingActionMenuFrameRefresh(to: pasteResult.targetIndex, requiresButton: true)
            recordPopupUndoSnapshot(beforeSnapshot)
            showMainGridActionMenuMessage("Button pasted")
        case .nothingToPaste:
            showMainGridActionMenuMessage("Nothing to paste")
        case .notEnoughSpace:
            showMainGridActionMenuMessage("not enough space")
        case .spaceOccupied:
            showMainGridActionMenuMessage("not enough space")
        }
    }

    private func duplicateMainGridActionMenuSelection() {
        guard isGridEditModeEnabled,
              let target = mainGridActionMenuTarget,
              target.index >= 0,
              target.index < functionKeys.count,
              target.index < visibleBoxCount else {
            return
        }

        let beforeSnapshot = currentFunctionKeySlotLines()
        let duplicateOutcome = updatedSlotLinesForPopupDuplicate(
            entry: functionKeys[target.index],
            index: target.index,
            gridDimensions: target.gridDimensions,
            slotLines: beforeSnapshot
        )

        let duplicateResult: MainGridPopupDuplicateResult
        switch duplicateOutcome {
        case let .success(result):
            duplicateResult = result
        case .invalidSource:
            return
        case .noSpace:
            showMainGridActionMenuMessage("No space to duplicate")
            return
        }

        guard duplicateResult.slotLines != beforeSnapshot else {
            return
        }

        guard restoreFunctionKeySlotLines(duplicateResult.slotLines) else {
            return
        }

        let duplicateTarget = mainGridActionMenuTargetForDuplicate(
            from: target,
            result: duplicateResult
        )
        let sourceTarget = MainGridActionMenuTarget(
            index: duplicateResult.sourceIndex,
            buttonFrame: target.buttonFrame,
            gridDimensions: target.gridDimensions
        )

        resetDirectionalDeleteState()
        recordPopupUndoSnapshot(beforeSnapshot, duplicateSourceTarget: sourceTarget)
        mainGridActionMenuTarget = duplicateTarget
        showMainGridActionMenuMessage("Button duplicated")
    }

    private func duplicateMainGridSlotFromTap(
        entry: FunctionKeyEntry,
        index: Int,
        gridDimensions: GridDimensions
    ) {
        let preservedActionMenuTarget = mainGridActionMenuTarget?.index == index ? mainGridActionMenuTarget : nil
        let beforeSnapshot = currentFunctionKeySlotLines()
        let sourceSpan = slotSpan(startingAt: index, gridDimensions: gridDimensions)
        let targetIndex = duplicateTargetIndex(from: index, span: sourceSpan, gridDimensions: gridDimensions)

        duplicateSlotIfPossible(entry: entry, index: index, gridDimensions: gridDimensions)

        guard let preservedActionMenuTarget,
              let targetIndex,
              currentFunctionKeySlotLines() != beforeSnapshot else {
            return
        }

        resetDirectionalDeleteState()
        mainGridActionMenuTarget = mainGridActionMenuTargetForMove(
            from: preservedActionMenuTarget,
            sourceIndex: index,
            targetIndex: targetIndex,
            span: sourceSpan
        )
    }

    private func resizeMainGridActionMenuSelection(to shape: MainGridPopupButtonShape) {
        guard isGridEditModeEnabled,
              let target = mainGridActionMenuTarget,
              target.index >= 0,
              target.index < functionKeys.count,
              target.index < visibleBoxCount else {
            return
        }

        let beforeSnapshot = currentFunctionKeySlotLines()
        let resizeOutcome = updatedSlotLinesForPopupResize(
            entry: functionKeys[target.index],
            index: target.index,
            gridDimensions: target.gridDimensions,
            slotLines: beforeSnapshot,
            targetShape: shape
        )

        let resizeResult: MainGridPopupResizeResult
        switch resizeOutcome {
        case let .success(result):
            resizeResult = result
        case .invalidSource, .sameSize:
            return
        case .notEnoughSpace:
            showMainGridActionMenuMessage("Not enough space")
            return
        case .spaceOccupied:
            showMainGridActionMenuMessage("Space occupied")
            return
        }

        guard resizeResult.slotLines != beforeSnapshot else {
            return
        }

        guard restoreFunctionKeySlotLines(resizeResult.slotLines) else {
            return
        }

        resetDirectionalDeleteState()
        recordPopupUndoSnapshot(
            beforeSnapshot,
            resizeTarget: PopupResizeUndoTarget(
                beforeAnchor: resizeResult.sourceIndex,
                afterAnchor: resizeResult.targetIndex
            )
        )
        mainGridActionMenuTarget = mainGridActionMenuTargetForResize(
            from: target,
            result: resizeResult
        )
        beginPendingMovePopupRefresh(to: resizeResult.targetIndex)
        showMainGridActionMenuMessage("Button resized")
    }

    private func isMainGridResizeShapeAvailable(
        _ shape: MainGridPopupButtonShape,
        for target: MainGridActionMenuTarget
    ) -> Bool {
        guard isGridEditModeEnabled,
              target.index >= 0,
              target.index < functionKeys.count,
              target.index < visibleBoxCount else {
            return false
        }

        return resolvedPopupResizePlacement(
            entry: functionKeys[target.index],
            index: target.index,
            gridDimensions: target.gridDimensions,
            targetShape: shape
        ) != nil
    }

    private func undoMainGridActionMenuOperation() {
        guard isGridEditModeEnabled,
              let undoEntry = popupUndoHistory.last else {
            return
        }

        guard undoEntry.documentName == selectedDocumentName else {
            clearPopupUndoHistory()
            return
        }

        let redoSnapshot = currentFunctionKeySlotLines()
        guard restoreFunctionKeySlotLines(undoEntry.slotLines) else {
            return
        }

        popupUndoHistory.removeLast()
        recordPopupRedoSnapshot(
            redoSnapshot,
            duplicateSourceTarget: undoEntry.duplicateSourceTarget,
            resizeTarget: undoEntry.resizeTarget
        )
        resetDirectionalDeleteState()

        if let duplicateSourceTarget = undoEntry.duplicateSourceTarget {
            mainGridActionMenuTarget = MainGridActionMenuTarget(
                index: duplicateSourceTarget.index,
                buttonFrame: duplicateSourceTarget.buttonFrame,
                gridDimensions: duplicateSourceTarget.gridDimensions
            )
        }
        refreshMainGridActionMenuTargetAfterSnapshotRestore(preferredButtonAnchor: undoEntry.resizeTarget?.beforeAnchor)
    }

    private func redoMainGridActionMenuOperation() {
        guard isGridEditModeEnabled,
              let redoEntry = popupRedoHistory.last else {
            return
        }

        guard redoEntry.documentName == selectedDocumentName else {
            clearPopupUndoHistory()
            return
        }

        let undoSnapshot = currentFunctionKeySlotLines()
        guard restoreFunctionKeySlotLines(redoEntry.slotLines) else {
            return
        }

        popupRedoHistory.removeLast()
        recordPopupUndoSnapshot(
            undoSnapshot,
            duplicateSourceTarget: redoEntry.duplicateSourceTarget,
            resizeTarget: redoEntry.resizeTarget,
            clearsRedoHistory: false
        )
        resetDirectionalDeleteState()
        refreshMainGridActionMenuTargetAfterSnapshotRestore(preferredButtonAnchor: redoEntry.resizeTarget?.afterAnchor)
    }

    private func deleteAllButtonsOnCurrentScreen() {
        guard currentScreenContainsButtonData() else {
            return
        }

        let beforeSnapshot = currentFunctionKeySlotLines()
        let clearedSlotLines = Array(repeating: "", count: beforeSnapshot.count)

        guard clearedSlotLines != beforeSnapshot else {
            return
        }

        guard restoreFunctionKeySlotLines(clearedSlotLines) else {
            return
        }

        resetDirectionalDeleteState()
        recordPopupUndoSnapshot(beforeSnapshot)
        isGridEditModeEnabled = true
        cancelSlotEditing()
    }

    private func currentScreenContainsButtonData() -> Bool {
        let maximumIndex = min(visibleBoxCount, functionKeys.count)

        return (0..<maximumIndex).contains { index in
            !isMainGridContinuationEntry(at: index)
                && !functionKeys[index].isBlankPlaceholder
                && !isEmptyButtonEntry(functionKeys[index])
        }
    }

    private func recordPopupUndoSnapshot(
        _ slotLines: [String],
        duplicateSourceTarget: MainGridActionMenuTarget? = nil,
        resizeTarget: PopupResizeUndoTarget? = nil,
        clearsRedoHistory: Bool = true
    ) {
        popupUndoHistory.append(PopupUndoEntry(
            documentName: selectedDocumentName,
            slotLines: slotLines,
            duplicateSourceTarget: duplicateSourceTarget,
            resizeTarget: resizeTarget
        ))

        if popupUndoHistory.count > popupUndoHistoryLimit {
            popupUndoHistory.removeFirst(popupUndoHistory.count - popupUndoHistoryLimit)
        }

        if clearsRedoHistory {
            clearPopupRedoHistory()
        }
    }

    private func recordPopupRedoSnapshot(
        _ slotLines: [String],
        duplicateSourceTarget: MainGridActionMenuTarget? = nil,
        resizeTarget: PopupResizeUndoTarget? = nil
    ) {
        popupRedoHistory.append(PopupUndoEntry(
            documentName: selectedDocumentName,
            slotLines: slotLines,
            duplicateSourceTarget: duplicateSourceTarget,
            resizeTarget: resizeTarget
        ))

        if popupRedoHistory.count > popupUndoHistoryLimit {
            popupRedoHistory.removeFirst(popupRedoHistory.count - popupUndoHistoryLimit)
        }
    }

    private func clearPopupUndoHistory() {
        popupUndoHistory.removeAll()
        clearPopupRedoHistory()
    }

    private func clearPopupRedoHistory() {
        popupRedoHistory.removeAll()
    }

    private func refreshMainGridActionMenuTargetAfterSnapshotRestore(preferredButtonAnchor: Int? = nil) {
        guard let target = mainGridActionMenuTarget else {
            return
        }

        let targetIndex = preferredButtonAnchor ?? (editableMainGridAnchorIndex(containing: target.index) ?? target.index)
        if preferredButtonAnchor != nil {
            guard targetIndex >= 0 else {
                return
            }

            if targetIndex != target.index {
                mainGridActionMenuTarget = MainGridActionMenuTarget(
                    index: targetIndex,
                    buttonFrame: target.buttonFrame,
                    gridDimensions: target.gridDimensions
                )
            }

            beginPendingActionMenuFrameRefresh(to: targetIndex, requiresButton: true)
            return
        }

        guard targetIndex >= 0,
              targetIndex < visibleBoxCount,
              functionKeys.indices.contains(targetIndex),
              !isMainGridContinuationEntry(at: targetIndex) else {
            dismissMainGridActionMenu()
            return
        }

        if targetIndex != target.index {
            mainGridActionMenuTarget = MainGridActionMenuTarget(
                index: targetIndex,
                buttonFrame: target.buttonFrame,
                gridDimensions: target.gridDimensions
            )
        }

        beginPendingActionMenuFrameRefresh(to: targetIndex, requiresButton: preferredButtonAnchor != nil)
    }

    private func showMainGridActionMenuMessage(_ message: String) {
        mainGridOperationMessageDismissTask?.cancel()
        mainGridOperationMessageText = message
        mainGridOperationMessageDismissTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                mainGridOperationMessageText = nil
                mainGridOperationMessageDismissTask = nil
            }
        }
    }

    private func currentMainGridActionMenuShape() -> MainGridPopupButtonShape? {
        guard let target = mainGridActionMenuTarget else {
            return nil
        }

        return popupButtonShapeForActionMenu(at: target.index, gridDimensions: target.gridDimensions)
    }

    private func resetDirectionalDeleteState() {
        directionalDeleteLastFootprint = nil
        directionalDeleteDirection = nil
        directionalDeleteExpectedAnchor = nil
    }

    private func mainGridDeleteFootprint(
        at index: Int,
        gridDimensions: GridDimensions
    ) -> MainGridDeleteFootprint? {
        guard index >= 0,
              index < functionKeys.count,
              index < visibleBoxCount,
              !isMainGridContinuationEntry(at: index),
              !functionKeys[index].isBlankPlaceholder,
              !isEmptyButtonEntry(functionKeys[index]) else {
            return nil
        }

        let columns = max(gridDimensions.columns, 1)
        let shape = mainGridPopupShapeDimensions(for: slotSpan(startingAt: index, gridDimensions: gridDimensions))
        return MainGridDeleteFootprint(
            anchor: index,
            row: index / columns,
            column: index % columns,
            width: max(shape.width, 1),
            height: max(shape.height, 1)
        )
    }

    private func isMainGridContinuationEntry(at index: Int) -> Bool {
        guard functionKeys.indices.contains(index) else {
            return false
        }

        let rawLine = functionKeys[index].rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return rawLine == wideButtonContinuationToken || rawLine == blockButtonContinuationToken
    }

    private func directionalDeleteDirection(
        from first: MainGridDeleteFootprint,
        to second: MainGridDeleteFootprint
    ) -> MainGridDirectionalDeleteDirection? {
        if second.minColumn == first.maxColumn + 1,
           rangesOverlap(first.minRow...first.maxRow, second.minRow...second.maxRow) {
            return .right
        }

        if second.maxColumn + 1 == first.minColumn,
           rangesOverlap(first.minRow...first.maxRow, second.minRow...second.maxRow) {
            return .left
        }

        if second.minRow == first.maxRow + 1,
           rangesOverlap(first.minColumn...first.maxColumn, second.minColumn...second.maxColumn) {
            return .down
        }

        if second.maxRow + 1 == first.minRow,
           rangesOverlap(first.minColumn...first.maxColumn, second.minColumn...second.maxColumn) {
            return .up
        }

        return nil
    }

    private func rangesOverlap(_ first: ClosedRange<Int>, _ second: ClosedRange<Int>) -> Bool {
        first.lowerBound <= second.upperBound && second.lowerBound <= first.upperBound
    }

    private func nextDirectionalDeleteFootprint(
        after footprint: MainGridDeleteFootprint,
        direction: MainGridDirectionalDeleteDirection,
        gridDimensions: GridDimensions
    ) -> MainGridDeleteFootprint? {
        let maximumIndex = min(visibleBoxCount, functionKeys.count)
        let candidates = (0..<maximumIndex).compactMap {
            mainGridDeleteFootprint(at: $0, gridDimensions: gridDimensions)
        }

        return candidates
            .filter { directionalDeleteDirection(from: footprint, to: $0) == direction }
            .sorted {
                let lhs = directionalDeleteCandidateScore($0, after: footprint, direction: direction)
                let rhs = directionalDeleteCandidateScore($1, after: footprint, direction: direction)
                if lhs.anchorOverlap != rhs.anchorOverlap {
                    return lhs.anchorOverlap < rhs.anchorOverlap
                }

                if lhs.distance != rhs.distance {
                    return lhs.distance < rhs.distance
                }

                return lhs.anchor < rhs.anchor
            }
            .first
    }

    private func directionalDeleteCandidateScore(
        _ candidate: MainGridDeleteFootprint,
        after footprint: MainGridDeleteFootprint,
        direction: MainGridDirectionalDeleteDirection
    ) -> (anchorOverlap: Int, distance: Int, anchor: Int) {
        switch direction {
        case .left, .right:
            let anchorOverlap = (candidate.minRow...candidate.maxRow).contains(footprint.row) ? 0 : 1
            let distance = rangeDistance(footprint.row, to: candidate.minRow...candidate.maxRow)
            return (anchorOverlap, distance, candidate.anchor)
        case .up, .down:
            let anchorOverlap = (candidate.minColumn...candidate.maxColumn).contains(footprint.column) ? 0 : 1
            let distance = rangeDistance(footprint.column, to: candidate.minColumn...candidate.maxColumn)
            return (anchorOverlap, distance, candidate.anchor)
        }
    }

    private func rangeDistance(_ value: Int, to range: ClosedRange<Int>) -> Int {
        if range.contains(value) {
            return 0
        }

        return min(abs(value - range.lowerBound), abs(value - range.upperBound))
    }

    private func mainGridActionMenuTargetForDuplicate(
        from sourceTarget: MainGridActionMenuTarget,
        result: MainGridPopupDuplicateResult
    ) -> MainGridActionMenuTarget {
        let columns = max(sourceTarget.gridDimensions.columns, 1)
        let sourceColumn = result.sourceIndex % columns
        let sourceRow = result.sourceIndex / columns
        let targetColumn = result.targetIndex % columns
        let targetRow = result.targetIndex / columns
        let width = max(result.sourceWidth, 1)
        let height = max(result.sourceHeight, 1)
        let cellWidth = (sourceTarget.buttonFrame.width - (mainGridButtonSpacing * CGFloat(width - 1))) / CGFloat(width)
        let cellHeight = (sourceTarget.buttonFrame.height - (mainGridButtonSpacing * CGFloat(height - 1))) / CGFloat(height)
        let xOffset = CGFloat(targetColumn - sourceColumn) * (cellWidth + mainGridButtonSpacing)
        let yOffset = CGFloat(targetRow - sourceRow) * (cellHeight + mainGridButtonSpacing)
        let duplicateFrame = sourceTarget.buttonFrame.offsetBy(dx: xOffset, dy: yOffset)

        return MainGridActionMenuTarget(
            index: result.targetIndex,
            buttonFrame: duplicateFrame,
            gridDimensions: sourceTarget.gridDimensions
        )
    }

    private func mainGridActionMenuTargetForResize(
        from sourceTarget: MainGridActionMenuTarget,
        result: MainGridPopupResizeResult
    ) -> MainGridActionMenuTarget {
        let sourceWidth = max(result.sourceWidth, 1)
        let sourceHeight = max(result.sourceHeight, 1)
        let targetWidth = max(result.targetWidth, 1)
        let targetHeight = max(result.targetHeight, 1)
        let cellWidth = (sourceTarget.buttonFrame.width - (mainGridButtonSpacing * CGFloat(sourceWidth - 1))) / CGFloat(sourceWidth)
        let cellHeight = (sourceTarget.buttonFrame.height - (mainGridButtonSpacing * CGFloat(sourceHeight - 1))) / CGFloat(sourceHeight)
        let resizedFrame = CGRect(
            x: sourceTarget.buttonFrame.minX,
            y: sourceTarget.buttonFrame.minY,
            width: (cellWidth * CGFloat(targetWidth)) + (mainGridButtonSpacing * CGFloat(targetWidth - 1)),
            height: (cellHeight * CGFloat(targetHeight)) + (mainGridButtonSpacing * CGFloat(targetHeight - 1))
        )

        return MainGridActionMenuTarget(
            index: result.targetIndex,
            buttonFrame: resizedFrame,
            gridDimensions: sourceTarget.gridDimensions
        )
    }

    private func mainGridActionMenuTargetForPaste(
        from sourceTarget: MainGridActionMenuTarget,
        result: MainGridPopupPasteResult
    ) -> MainGridActionMenuTarget {
        let sourceWidth = max(result.destinationWidth, 1)
        let sourceHeight = max(result.destinationHeight, 1)
        let targetWidth = max(result.pastedWidth, 1)
        let targetHeight = max(result.pastedHeight, 1)
        let cellWidth = (sourceTarget.buttonFrame.width - (mainGridButtonSpacing * CGFloat(sourceWidth - 1))) / CGFloat(sourceWidth)
        let cellHeight = (sourceTarget.buttonFrame.height - (mainGridButtonSpacing * CGFloat(sourceHeight - 1))) / CGFloat(sourceHeight)
        let pastedFrame = CGRect(
            x: sourceTarget.buttonFrame.minX,
            y: sourceTarget.buttonFrame.minY,
            width: (cellWidth * CGFloat(targetWidth)) + (mainGridButtonSpacing * CGFloat(targetWidth - 1)),
            height: (cellHeight * CGFloat(targetHeight)) + (mainGridButtonSpacing * CGFloat(targetHeight - 1))
        )

        return MainGridActionMenuTarget(
            index: result.targetIndex,
            buttonFrame: pastedFrame,
            gridDimensions: sourceTarget.gridDimensions
        )
    }

    private func mainGridActionMenuTargetForMove(
        from sourceTarget: MainGridActionMenuTarget,
        sourceIndex: Int,
        targetIndex: Int,
        span: Int
    ) -> MainGridActionMenuTarget {
        let columns = max(sourceTarget.gridDimensions.columns, 1)
        let sourceColumn = sourceIndex % columns
        let sourceRow = sourceIndex / columns
        let targetColumn = targetIndex % columns
        let targetRow = targetIndex / columns
        let shape = mainGridPopupShapeDimensions(for: span)
        let width = max(shape.width, 1)
        let height = max(shape.height, 1)
        let cellWidth = (sourceTarget.buttonFrame.width - (mainGridButtonSpacing * CGFloat(width - 1))) / CGFloat(width)
        let cellHeight = (sourceTarget.buttonFrame.height - (mainGridButtonSpacing * CGFloat(height - 1))) / CGFloat(height)
        let xOffset = CGFloat(targetColumn - sourceColumn) * (cellWidth + mainGridButtonSpacing)
        let yOffset = CGFloat(targetRow - sourceRow) * (cellHeight + mainGridButtonSpacing)
        let movedFrame = sourceTarget.buttonFrame.offsetBy(dx: xOffset, dy: yOffset)

        return MainGridActionMenuTarget(
            index: targetIndex,
            buttonFrame: movedFrame,
            gridDimensions: sourceTarget.gridDimensions
        )
    }

    private func mainGridActionMenuTargetForDeleteSelection(
        from sourceTarget: MainGridActionMenuTarget,
        deletedFootprint: MainGridDeleteFootprint,
        nextFootprint: MainGridDeleteFootprint
    ) -> MainGridActionMenuTarget {
        let cellWidth = (sourceTarget.buttonFrame.width - (mainGridButtonSpacing * CGFloat(max(deletedFootprint.width - 1, 0)))) / CGFloat(max(deletedFootprint.width, 1))
        let cellHeight = (sourceTarget.buttonFrame.height - (mainGridButtonSpacing * CGFloat(max(deletedFootprint.height - 1, 0)))) / CGFloat(max(deletedFootprint.height, 1))
        let xOffset = CGFloat(nextFootprint.column - deletedFootprint.column) * (cellWidth + mainGridButtonSpacing)
        let yOffset = CGFloat(nextFootprint.row - deletedFootprint.row) * (cellHeight + mainGridButtonSpacing)
        let nextFrame = CGRect(
            x: sourceTarget.buttonFrame.minX + xOffset,
            y: sourceTarget.buttonFrame.minY + yOffset,
            width: (cellWidth * CGFloat(nextFootprint.width)) + (mainGridButtonSpacing * CGFloat(max(nextFootprint.width - 1, 0))),
            height: (cellHeight * CGFloat(nextFootprint.height)) + (mainGridButtonSpacing * CGFloat(max(nextFootprint.height - 1, 0)))
        )

        return MainGridActionMenuTarget(
            index: nextFootprint.anchor,
            buttonFrame: nextFrame,
            gridDimensions: sourceTarget.gridDimensions
        )
    }

    private func mainGridPopupShapeDimensions(for span: Int) -> (width: Int, height: Int) {
        switch span {
        case 5:
            return (3, 3)
        case 8:
            return (3, 2)
        case 7:
            return (1, 3)
        case 6:
            return (1, 2)
        case 4:
            return (2, 2)
        default:
            return (max(1, min(span, 3)), 1)
        }
    }

    private func mainGridActionMenuPosition(
        for buttonFrame: CGRect,
        menuSize: CGSize,
        availableWidth: CGFloat,
        availableHeight: CGFloat,
        safeAreaInsets: EdgeInsets,
        gridTopY: CGFloat,
        gridHeight: CGFloat
    ) -> CGPoint {
        if isPad {
            return iPadMainGridActionMenuPosition(
                for: buttonFrame,
                menuSize: menuSize,
                availableWidth: availableWidth,
                availableHeight: availableHeight,
                safeAreaInsets: safeAreaInsets,
                gridTopY: gridTopY,
                gridHeight: gridHeight
            )
        }

        return iPhoneMainGridActionMenuPosition(
            for: buttonFrame,
            menuSize: menuSize,
            availableWidth: availableWidth,
            availableHeight: availableHeight,
            safeAreaInsets: safeAreaInsets,
            gridTopY: gridTopY,
            gridHeight: gridHeight
        )
    }

    private func iPadMainGridActionMenuPosition(
        for buttonFrame: CGRect,
        menuSize: CGSize,
        availableWidth: CGFloat,
        availableHeight: CGFloat,
        safeAreaInsets: EdgeInsets,
        gridTopY: CGFloat,
        gridHeight: CGFloat
    ) -> CGPoint {
        let margin: CGFloat = 6
        let horizontalGap: CGFloat = 0
        let selectedFrame = buttonFrame.offsetBy(dx: 0, dy: gridTopY)
        let minimumX = safeAreaInsets.leading + margin + (menuSize.width / 2)
        let maximumX = max(minimumX, availableWidth - safeAreaInsets.trailing - margin - (menuSize.width / 2))
        let rightX = selectedFrame.maxX + horizontalGap + (menuSize.width / 2)
        let leftX = selectedFrame.minX - horizontalGap - (menuSize.width / 2)
        let resolvedX: CGFloat

        if rightX <= maximumX {
            resolvedX = rightX
        } else if leftX >= minimumX {
            resolvedX = leftX
        } else {
            resolvedX = min(max(selectedFrame.midX, minimumX), maximumX)
        }

        let gridMinimumY = max(gridTopY, safeAreaInsets.top)
        let gridMaximumY = min(availableHeight - safeAreaInsets.bottom, gridTopY + gridHeight)
        let minimumY = gridMinimumY + (menuSize.height / 2)
        let maximumY = max(minimumY, gridMaximumY - (menuSize.height / 2))
        let resolvedY: CGFloat

        let topAlignedY = selectedFrame.minY + (menuSize.height / 2)
        let bottomAlignedY = selectedFrame.maxY - (menuSize.height / 2)

        if topAlignedY >= minimumY, topAlignedY <= maximumY {
            resolvedY = topAlignedY
        } else if bottomAlignedY >= minimumY, bottomAlignedY <= maximumY {
            resolvedY = bottomAlignedY
        } else {
            resolvedY = min(max(topAlignedY, minimumY), maximumY)
        }

        let finalY = min(max(resolvedY + iPadPopupVerticalOffset, minimumY), maximumY)

        return CGPoint(
            x: resolvedX,
            y: finalY
        )
    }

    private func iPhoneMainGridActionMenuPosition(
        for buttonFrame: CGRect,
        menuSize: CGSize,
        availableWidth: CGFloat,
        availableHeight: CGFloat,
        safeAreaInsets: EdgeInsets,
        gridTopY: CGFloat,
        gridHeight: CGFloat
    ) -> CGPoint {
        let margin: CGFloat = 6
        let horizontalGap: CGFloat = 0
        let selectedFrame = buttonFrame.offsetBy(dx: 0, dy: gridTopY)
        let minimumX = safeAreaInsets.leading + margin + (menuSize.width / 2)
        let maximumX = max(minimumX, availableWidth - safeAreaInsets.trailing - margin - (menuSize.width / 2))
        let rightX = selectedFrame.maxX + horizontalGap + (menuSize.width / 2)
        let leftX = selectedFrame.minX - horizontalGap - (menuSize.width / 2)
        let resolvedX: CGFloat

        if rightX <= maximumX {
            resolvedX = rightX
        } else if leftX >= minimumX {
            resolvedX = leftX
        } else {
            resolvedX = min(max(selectedFrame.midX, minimumX), maximumX)
        }

        let gridMinimumY = max(gridTopY, safeAreaInsets.top)
        let gridMaximumY = gridTopY + gridHeight
        let minimumY = gridMinimumY + (menuSize.height / 2)
        let maximumY = max(minimumY, gridMaximumY - (menuSize.height / 2))
        let topAlignedY = selectedFrame.minY + (menuSize.height / 2)
        let bottomAlignedY = selectedFrame.maxY - (menuSize.height / 2)
        let resolvedY: CGFloat

        if topAlignedY >= minimumY, topAlignedY <= maximumY {
            resolvedY = topAlignedY
        } else if bottomAlignedY >= minimumY, bottomAlignedY <= maximumY {
            resolvedY = bottomAlignedY
        } else {
            resolvedY = min(max(topAlignedY, minimumY), maximumY)
        }

        return CGPoint(
            x: resolvedX,
            y: resolvedY
        )
    }

    private var settingsToolbarButtonLabel: some View {

        Group {
            Image(systemName: "gearshape")
        }
        // .font(.headline)
        .foregroundStyle((isGridEditModeEnabled || editingSlotIndex != nil) ? Color(white: 0.65) : .white)
        .frame(minWidth: 44, minHeight: 36)
        //  .background(Color.gray.opacity(0.45))
        .background(Color(red: 0.32, green: 0.32, blue: 0.34).opacity(0.4))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
        }
        .clipShape(.rect(cornerRadius: 10))
        .contentShape(.rect)
    }
	//
	//----------------------------------------
	// MARK: - BM:😎 EXT KEYBOARD
	//
	
    private var externalKeyboardShortcutLayer: some View {
        ZStack {
            Group {
                externalKeyboardShortcutButton("f", isEnabled: boxFontSize < maximumBoxFontSize) {
                    increaseBoxFontSize()
                }
                externalKeyboardShortcutButton("d", isEnabled: boxFontSize > minimumBoxFontSize) {
                    decreaseBoxFontSize()
                }
                externalKeyboardShortcutButton("r") {
                    isSpkRecEnabled.toggle()
                }
                externalKeyboardShortcutButton("h", isEnabled: !isHomeDocumentSelected) {
                    openHomeDocumentFromMainScreenControl()
                }
                externalKeyboardShortcutButton("b", isEnabled: canGoBackToPreviousDocument) {
                    goBackToPreviousDocumentFromMainScreenControl()
                }
                externalKeyboardShortcutButton("m") {
                    advanceDisplayMode()
                }
            }

            Group {
                externalKeyboardShortcutButton("n") {
                    cycleMainGridButtonMode()
                }
                externalKeyboardShortcutButton(",", isEnabled: currentFileNumber > 1) {
                    selectPreviousDocumentFromMainScreenControl()
                }
                externalKeyboardShortcutButton(".", isEnabled: currentFileNumber < totalFileCount) {
                    selectNextDocumentFromMainScreenControl()
                }
            }
        }
        .frame(width: 1, height: 1)
        .clipped()
        .accessibilityHidden(true)
    }

    private func externalKeyboardShortcutButton(
        _ key: KeyEquivalent,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            runExternalKeyboardCommand(isEnabled: isEnabled, action: action)
        } label: {
            Color.clear
                .frame(width: 1, height: 1)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: [])
        .disabled(areExternalKeyboardCommandsDisabled || !isEnabled)
        .accessibilityHidden(true)
    }

    private func runExternalKeyboardCommand(isEnabled: Bool = true, action: () -> Void) {
        guard isEnabled, !areExternalKeyboardCommandsDisabled else {
            return
        }

        ButtonClickFeedback.playIfEnabled()
        action()
    }

    private func refreshMainScreenKeyboardFocus() {
        // Letter shortcuts use hidden Buttons, but arrow keys need a focused SwiftUI view.
        // Drop focus while text editors, previews, or settings are active so arrows keep their normal editor behavior.
        isMainScreenKeyboardFocused = !areExternalKeyboardCommandsDisabled
    }

    private func handleExternalArrowKeyPress(_ key: KeyEquivalent) -> KeyPress.Result {
        guard !areExternalKeyboardCommandsDisabled else {
            return .ignored
        }

        switch key {
        case .downArrow:
            runExternalKeyboardCommand(isEnabled: visibleGridDimensions.rows < maxGridDimension) {
                increaseGridRows()
            }
        case .upArrow:
            runExternalKeyboardCommand(isEnabled: visibleGridDimensions.rows > 1) {
                decreaseGridRows()
            }
        case .leftArrow:
            runExternalKeyboardCommand(isEnabled: visibleGridDimensions.columns > 1) {
                decreaseGridColumns()
            }
        case .rightArrow:
            runExternalKeyboardCommand(isEnabled: visibleGridDimensions.columns < maxGridDimension) {
                increaseGridColumns()
            }
        default:
            return .ignored
        }

        return .handled
    }

    private var areExternalKeyboardCommandsDisabled: Bool {
        isSettingsScreenPresented ||
        presentedPreviewFile != nil ||
        isEditingDocumentName ||
        isDocumentNameFieldFocused ||
        isSlotEditorFocused ||
        editingSlotIndex != nil
    }

    private var isHomeDocumentSelected: Bool {
        false
    }

    private func openHomeDocumentFromMainScreenControl() {
        if mainGridButtonMode == .speechActive {
            speakMainGridText("home")
        }
        _ = selectDocumentNamedFromGrid("home.screen")
    }

    private func goBackToPreviousDocumentFromMainScreenControl() {
        if mainGridButtonMode == .speechActive,
           let previousDocumentDisplayName,
           !previousDocumentDisplayName.isEmpty {
            speakMainGridText(previousDocumentDisplayName)
        }
        goBackToPreviousDocument()
    }

    private func selectPreviousDocumentFromMainScreenControl() {
        if mainGridButtonMode == .speechActive,
           let adjacentPreviousDocumentDisplayName,
           !adjacentPreviousDocumentDisplayName.isEmpty {
            speakMainGridText(adjacentPreviousDocumentDisplayName)
        }
        selectPreviousDocument()
    }

    private func selectNextDocumentFromMainScreenControl() {
        if mainGridButtonMode == .speechActive,
           let adjacentNextDocumentDisplayName,
           !adjacentNextDocumentDisplayName.isEmpty {
            speakMainGridText(adjacentNextDocumentDisplayName)
        }
        selectNextDocument()
    }

    private func selectPreviousBackgroundImage() {
        let imageURLs = availableBackgroundImageURLs
        guard selectedBackgroundImageIndex > 1,
              imageURLs.indices.contains(selectedBackgroundImageIndex - 2) else {
            return
        }

        persistMainBackgroundImage(imageURLs[selectedBackgroundImageIndex - 2])
    }

    private func selectNextBackgroundImage() {
        let imageURLs = availableBackgroundImageURLs
        let nextIndex = max(selectedBackgroundImageIndex, 0)
        guard nextIndex < imageURLs.count,
              imageURLs.indices.contains(nextIndex) else {
            return
        }

        persistMainBackgroundImage(imageURLs[nextIndex])
    }

    private func selectRandomBackgroundImage() {
        let imageURLs = availableBackgroundImageURLs
        guard !imageURLs.isEmpty else {
            return
        }

        let currentIndex = selectedBackgroundImageIndex - 1
        let candidateURLs = imageURLs.count > 1
            ? imageURLs.enumerated().compactMap { index, imageURL in
                index == currentIndex ? nil : imageURL
            }
            : imageURLs

        if let randomImageURL = candidateURLs.randomElement() {
            persistMainBackgroundImage(randomImageURL)
        }
    }

    private func persistMainBackgroundImage(_ imageURL: URL) {
        selectedBackgroundImagePath = imageURL.path
        selectedBackgroundImageName = imageURL.lastPathComponent
        if let imageIndex = availableBackgroundImageURLs.firstIndex(where: { $0.path == imageURL.path }) {
            selectedBackgroundImageIndex = imageIndex + 1
        }
    }

    private func displayModeButtonSection(availableWidth: CGFloat) -> some View {
        MainScreenBottomBar(
            availableWidth: availableWidth,
            visibleGridDimensions: visibleGridDimensions,
            isGridEditModeEnabled: isGridEditModeEnabled,
            boxFontSize: boxFontSize,
            minimumBoxFontSize: minimumBoxFontSize,
            maximumBoxFontSize: maximumBoxFontSize,
            speechRecognitionDisplayText: speechRecognitionDisplayText,
            speechRecognitionDisplayColor: speechRecognitionDisplayColor,
            isSpeechRecognitionEnabled: isSpkRecEnabled,
            outputMode: outputMode,
            isBluetoothConnected: ble.isConnected,
            isMacConnected: macConnection.canSend,
            isMediaOrWaitActive: isMediaOrWaitActive,
            mainGridButtonMode: mainGridButtonMode,
            displayMode: displayMode,
            displayModeButtonColor: displayModeButtonColor,
            fontControlColor: fontControlColor,
            speechRecognitionActiveColor: speechRecognitionActiveColor,
            bleSendActiveColor: bleSendActiveColor,
            popupCoordinateSpaceName: mainScreenPopupCoordinateSpaceName,
            onDecreaseRows: decreaseGridRows,
            onIncreaseRows: increaseGridRows,
            onDecreaseColumns: decreaseGridColumns,
            onIncreaseColumns: increaseGridColumns,
            onDecreaseBoxFontSize: decreaseBoxFontSize,
            onIncreaseBoxFontSize: increaseBoxFontSize,
            onResetBoxFontSize: resetBoxFontSize,
            onToggleSpeechRecognition: { isSpkRecEnabled.toggle() },
            onCycleMainGridButtonMode: cycleMainGridButtonMode,
            onStopMedia: stopAllMainGridMedia,
            onAdvanceDisplayMode: advanceDisplayMode
        )
    }

    private func esp001MiniDiagnosticEditor(availableWidth: CGFloat) -> some View {
        let panels = esp001MiniDiagnosticPanels(for: ESP001DiagnosticDevice.activeMiniEditorTest)

        return ESP001MiniDiagnosticEditorShell(
            width: min(smartViewWidth, availableWidth),
            height: smartViewHeight,
            commandWidth: smartEditControlsWidth,
            colorWidth: smartCommandEditorWidth,
            buttonWidth: smartColorControlsWidth,
            sfWidth: smartSFPanelWidth,
            debugEditorGeometry: debugEditorGeometry,
            commandPanel: panels.command,
            colorPanel: panels.color,
            buttonPanel: panels.button,
            sfPanel: panels.sf
        )
    }

    private func esp001MiniDiagnosticPanels(for test: ESP001MiniEditorTest) -> ESP001MiniDiagnosticPanels {
        switch test {
        case .empty:
            return ESP001MiniDiagnosticPanels(
                command: esp001MiniDiagnosticEmptyPanel(label: "ESP-001 TEST 4\nEMPTY"),
                color: esp001MiniDiagnosticEmptyPanel(),
                button: esp001MiniDiagnosticEmptyPanel(),
                sf: esp001MiniDiagnosticEmptyPanel()
            )
        case .commandOnly:
            return ESP001MiniDiagnosticPanels(
                command: AnyView(smartCommandPanel(columnWidth: smartEditControlsWidth)),
                color: esp001MiniDiagnosticEmptyPanel(),
                button: esp001MiniDiagnosticEmptyPanel(),
                sf: esp001MiniDiagnosticEmptyPanel()
            )
        case .buttonOnly:
            return ESP001MiniDiagnosticPanels(
                command: esp001MiniDiagnosticEmptyPanel(),
                color: esp001MiniDiagnosticEmptyPanel(),
                button: AnyView(smartButtonPanel()),
                sf: esp001MiniDiagnosticEmptyPanel()
            )
        case .colorOnly:
            return ESP001MiniDiagnosticPanels(
                command: esp001MiniDiagnosticEmptyPanel(),
                color: AnyView(smartColorPanel),
                button: esp001MiniDiagnosticEmptyPanel(),
                sf: esp001MiniDiagnosticEmptyPanel()
            )
        case .sfOnly:
            return ESP001MiniDiagnosticPanels(
                command: esp001MiniDiagnosticEmptyPanel(),
                color: esp001MiniDiagnosticEmptyPanel(),
                button: esp001MiniDiagnosticEmptyPanel(),
                sf: esp001MiniDiagnosticSFPanel()
            )
        case .commandAndButton:
            return ESP001MiniDiagnosticPanels(
                command: AnyView(smartCommandPanel(columnWidth: smartEditControlsWidth)),
                color: esp001MiniDiagnosticEmptyPanel(),
                button: AnyView(smartButtonPanel()),
                sf: esp001MiniDiagnosticEmptyPanel()
            )
        case .commandAndColor:
            return ESP001MiniDiagnosticPanels(
                command: AnyView(smartCommandPanel(columnWidth: smartEditControlsWidth)),
                color: AnyView(smartColorPanel),
                button: esp001MiniDiagnosticEmptyPanel(),
                sf: esp001MiniDiagnosticEmptyPanel()
            )
        case .allPanels:
            return ESP001MiniDiagnosticPanels(
                command: AnyView(smartCommandPanel(columnWidth: smartEditControlsWidth)),
                color: AnyView(smartColorPanel),
                button: AnyView(smartButtonPanel()),
                sf: esp001MiniDiagnosticSFPanel()
            )
        }
    }

    private func esp001MiniDiagnosticEmptyPanel(label: String? = nil) -> AnyView {
        AnyView(ESP001MiniDiagnosticEmptyPanel(label: label))
    }

    private func esp001MiniDiagnosticSFPanel() -> AnyView {
        AnyView(IPadSmartSFPanel(
            symbolGrid: {
                smartSFSymbolGrid
            },
            controls: {
                smartSFPanelControls
            }
        ))
    }

    private var slotEditorSection: some View {
        MainScreenSlotEditorOverlay(
            editingSlotText: $editingSlotText,
            editingSlotIndex: editingSlotIndex,
            gridDimensions: visibleGridDimensions,
            focusBinding: $isSlotEditorFocused,
            buttonSpacing: slotEditorButtonSpacing,
            helperButtonWidth: slotEditorHelperButtonWidth,
            onCancel: cancelSlotEditing,
            onCommit: commitSlotEditing,
            onSave: saveSlotEditing,
            onTest: testEditingSlotText,
            onCopy: showSlotCopiedPopup,
            onPaste: showSlotPastedPopup,
            onModify: markSlotEditorSessionModified,
            onVisibilityChange: showSlotVisibilityPopup,
            onSelectPreviousButton: selectPreviousEditableSlot,
            onSelectNextButton: selectNextEditableSlot
        )
        .ignoresSafeArea(.keyboard)
    }

    private func smartView(availableWidth: CGFloat, availableHeight: CGFloat? = nil) -> some View {
        let resolvedSmartViewWidth = isPad ? smartViewWidth : smartViewWidthPhone
        let resolvedSmartViewHeight = isPad ? smartViewHeight : smartViewHeightPhone
        let iPhoneReferencePanelWidth = availableWidth / 3
        let iPhoneLeftKeyCellWidth = smartIPhoneButtonEditorDynamicCellWidth(editorWidth: iPhoneReferencePanelWidth)
        let iPhoneLeftPanelWidth = iPhoneLeftKeyCellWidth * 4
        let iPhoneRightPanelWidth = iPhoneLeftKeyCellWidth * 5
        let resolvedSmartEditControlsWidth = isPad ? smartEditControlsWidth : iPhoneLeftPanelWidth
        let resolvedSmartCommandEditorWidth = isPad ? smartCommandEditorWidth : iPhoneReferencePanelWidth
        let resolvedSmartColorControlsWidth = isPad ? smartColorControlsWidth : iPhoneRightPanelWidth
        let resolvedSmartSFPanelWidth = isPad ? smartSFPanelWidth : smartSFPanelWidthPhone
        let outerWidth = isPad ? min(resolvedSmartViewWidth, availableWidth) : availableWidth
        let outerHeight = isPad ? resolvedSmartViewHeight : availableHeight
        let outerMaxWidth: CGFloat? = nil
        let outerMaxHeight = isPad || availableHeight != nil ? nil : CGFloat.infinity
        let panelHeight = isPad ? resolvedSmartViewHeight : availableHeight
        let panelMaxHeight = isPad || availableHeight != nil ? nil : CGFloat.infinity
        let editorGroupWidth = isPad ? outerWidth : resolvedSmartEditControlsWidth + resolvedSmartCommandEditorWidth + resolvedSmartColorControlsWidth
        let editorGroupAlignment: Alignment = isPad ? .topLeading : .top
        let isESP001DiagnosticIPadMini5 = ESP001DiagnosticDevice.isIPadMini5

        return HStack(spacing: 0) {
            if isESP001DiagnosticIPadMini5 {
                Rectangle()
                    .fill(Color.black)
                    .frame(width: resolvedSmartEditControlsWidth, height: panelHeight)
                    .frame(maxHeight: panelMaxHeight)
                    .editorGeometryProbe(.leftPanel, isEnabled: debugEditorGeometry)
            } else {
                smartCommandPanel(columnWidth: resolvedSmartEditControlsWidth)
                    .frame(width: resolvedSmartEditControlsWidth, height: panelHeight)
                    .frame(maxHeight: panelMaxHeight)
                    .editorGeometryProbe(.leftPanel, isEnabled: debugEditorGeometry)
            }

            smartColorPanel
                .frame(width: resolvedSmartCommandEditorWidth, height: panelHeight)
                .frame(maxHeight: panelMaxHeight)
                .editorGeometryProbe(.commandPanel, isEnabled: debugEditorGeometry)

            if isPad {
                smartButtonPanel()
                    .frame(width: resolvedSmartColorControlsWidth, height: panelHeight)
                    .frame(maxHeight: panelMaxHeight)
                    .editorGeometryProbe(.buttonPanel, isEnabled: debugEditorGeometry)

                IPadSmartSFPanel(
                    symbolGrid: {
                        smartSFSymbolGrid
                    },
                    controls: {
                        smartSFPanelControls
                    }
                )
                    .frame(width: resolvedSmartSFPanelWidth, height: panelHeight)
                    .frame(maxHeight: panelMaxHeight)
                    .editorGeometryProbe(.sfPanel, isEnabled: debugEditorGeometry)
            } else {
                smartButtonPanel(editorWidth: resolvedSmartColorControlsWidth)
                    .frame(width: resolvedSmartColorControlsWidth, height: panelHeight)
                    .frame(maxHeight: panelMaxHeight)
                    .editorGeometryProbe(.buttonPanel, isEnabled: debugEditorGeometry)
            }
        }
        .editorGeometryProbe(.hStack, isEnabled: debugEditorGeometry)
        .frame(width: editorGroupWidth, height: outerHeight, alignment: .topLeading)
        .frame(width: outerWidth, height: outerHeight, alignment: editorGroupAlignment)
        .frame(maxWidth: outerMaxWidth, maxHeight: outerMaxHeight, alignment: .topLeading)
        .editorGeometryProbe(.smartView, isEnabled: debugEditorGeometry)
        .ignoresSafeArea(.keyboard)
    }

    private func iPhoneSmartEditorPresentation(availableWidth: CGFloat) -> some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .ignoresSafeArea(.container)

                switch ESP001IPhoneEditorDiagnostic.activeIPhoneEditorStructure {
                case .original:
                    smartView(availableWidth: geometry.size.width, availableHeight: geometry.size.height)
                case .experimental:
                    esp001ExperimentalIPhoneEditor(
                        availableWidth: geometry.size.width,
                        availableHeight: geometry.size.height
                    )
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .editorGeometryProbe(.fullScreenZStack, isEnabled: debugEditorGeometry)
        .overlay(alignment: .topLeading) {
            if debugEditorGeometry {
                DebugEditorGeometryOverlay(frames: editorGeometryFrames)
                    .padding(8)
            }
        }
        .ignoresSafeArea(.container)
        .ignoresSafeArea(.keyboard)
    }

    private func esp001ExperimentalIPhoneEditor(
        availableWidth: CGFloat,
        availableHeight: CGFloat? = nil
    ) -> some View {
        let iPhoneReferencePanelWidth = availableWidth / 3
        let iPhoneLeftKeyCellWidth = smartIPhoneButtonEditorDynamicCellWidth(editorWidth: iPhoneReferencePanelWidth)
        let iPhoneLeftPanelWidth = iPhoneLeftKeyCellWidth * 4
        let iPhoneRightPanelWidth = iPhoneLeftKeyCellWidth * 5
        let resolvedSmartEditControlsWidth = iPhoneLeftPanelWidth
        let resolvedSmartCommandEditorWidth = iPhoneReferencePanelWidth
        let resolvedSmartColorControlsWidth = iPhoneRightPanelWidth
        let resolvedSmartSFPanelWidth = smartSFPanelWidthPhone
        let outerWidth = availableWidth
        let outerHeight = availableHeight
        let outerMaxWidth: CGFloat? = nil
        let outerMaxHeight: CGFloat? = availableHeight != nil ? nil : CGFloat.infinity
        let panelHeight = availableHeight
        let panelMaxHeight: CGFloat? = availableHeight != nil ? nil : CGFloat.infinity
        let editorGroupWidth = resolvedSmartEditControlsWidth + resolvedSmartCommandEditorWidth + resolvedSmartColorControlsWidth
        let editorGroupAlignment: Alignment = .top
        _ = resolvedSmartSFPanelWidth

        return ESP001ExperimentalIPhoneEditorShell(
            editorGroupWidth: editorGroupWidth,
            outerWidth: outerWidth,
            outerHeight: outerHeight,
            outerMaxWidth: outerMaxWidth,
            outerMaxHeight: outerMaxHeight,
            panelHeight: panelHeight,
            panelMaxHeight: panelMaxHeight,
            editorGroupAlignment: editorGroupAlignment,
            commandWidth: resolvedSmartEditControlsWidth,
            commandEditorWidth: resolvedSmartCommandEditorWidth,
            buttonWidth: resolvedSmartColorControlsWidth,
            debugEditorGeometry: debugEditorGeometry,
            commandPanel: AnyView(smartCommandPanel(columnWidth: resolvedSmartEditControlsWidth)),
            commandEditorPanel: AnyView(smartColorPanel),
            buttonPanel: AnyView(smartButtonPanel(editorWidth: resolvedSmartColorControlsWidth))
        )
    }

    private var dismissKeyboardButton: some View {
        Button {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        } label: {
            Image(systemName: "keyboard.chevron.compact.down")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .overlay {
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hide keyboard")
    }

    private func smartPanel(title: String) -> some View {
        Rectangle()
            .fill(Color.black)
            .overlay {
                Rectangle()
                    .stroke(Color.white, lineWidth: 1)
            }
            .overlay {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
    }

    private func smartPanelBorder(edges: Edge.Set = .all) -> some View {
        ZStack {
            if edges.contains(.top) {
                Rectangle()
                    .fill(Color.white)
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .top)
            }

            if edges.contains(.bottom) {
                Rectangle()
                    .fill(Color.white)
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }

            if edges.contains(.leading) {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if edges.contains(.trailing) {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .allowsHitTesting(false)
    }

    private var smartCommandEditorRow: some View {
        HStack(spacing: 0) {
            Button {
                deleteSmartEditorBackward()
            } label: {
                Image(systemName: "delete.left.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46)
                    .frame(maxHeight: .infinity)
                    .background(Color.black)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete backward")

            SmartActionTextField(
                placeholder: "characters/command(s)",
                text: smartActionTextBinding,
                selectedRange: smartScriptSelectionRangeBinding,
                fontSize: 20
            )
                .padding(.horizontal, 3)
                .frame(minWidth: 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black)
        .overlay {
            smartPanelBorder()
        }
    }
	//
	//----------------------------------------
	// MARK: - BM: CMD EDITOR 4*4 btns
	//
    private func smartCommandPanel(columnWidth: CGFloat = 0) -> some View {
        let keyCellWidth: CGFloat? = isPad || columnWidth <= 0 ? nil : columnWidth / 4
        let functionKeyColumnWidth = keyCellWidth ?? smartFunctionKeyColumnWidth

        return VStack(spacing: 0) {
            if isPad {
                IPadSmartCommandKeypad(
                    topPlaceholderSymbols: smartTopPlaceholderSymbols,
                    keyCellWidth: keyCellWidth,
                    debugEditorGeometry: debugEditorGeometry,
                    placeholderButton: { systemName in
                        smartPlaceholderButton(systemName: systemName)
                    },
                    escapeCodeToggleButton: {
                        smartEscapeCodeToggleButton
                    },
                    dismissKeyboardButton: {
                        dismissKeyboardButton
                    },
                    commandColonButton: {
                        smartCommandColonButton
                    },
                    modifierButton: { systemName, accessibilityLabel, prefix in
                        smartModifierButton(
                            systemName: systemName,
                            accessibilityLabel: accessibilityLabel,
                            prefix: prefix
                        )
                    }
                )
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(Array(smartTopPlaceholderSymbols.prefix(4)), id: \.self) { systemName in
                            smartPlaceholderButton(systemName: systemName)
                                .frame(width: keyCellWidth)
                        }
                    }
                    .frame(height: 44)

                    HStack(spacing: 0) {
                        ForEach(Array(smartTopPlaceholderSymbols.dropFirst(4).prefix(4)), id: \.self) { systemName in
                            smartPlaceholderButton(systemName: systemName)
                                .frame(width: keyCellWidth)
                        }
                    }
                    .frame(height: 44)

                    HStack(spacing: 0) {
                        smartPlaceholderButton(systemName: "delete.right.fill")
                            .frame(width: keyCellWidth)
                        smartEscapeCodeToggleButton
                            .frame(width: keyCellWidth)
                        dismissKeyboardButton
                            .frame(width: keyCellWidth)
                        smartCommandColonButton
                            .frame(width: keyCellWidth)
                    }
                    .frame(height: 44)

                    HStack(spacing: 0) {
                        smartModifierButton(systemName: "control", accessibilityLabel: "Control", prefix: "⌃")
                            .frame(width: keyCellWidth)
                        smartModifierButton(systemName: "option", accessibilityLabel: "Option", prefix: "⌥")
                            .frame(width: keyCellWidth)
                        smartModifierButton(systemName: "shift", accessibilityLabel: "Shift", prefix: "⇧")
                            .frame(width: keyCellWidth)
                        smartModifierButton(systemName: "command", accessibilityLabel: "Command", prefix: "⌘")
                            .frame(width: keyCellWidth)
                    }
                    .frame(height: 44)
                }
                .editorGeometryProbe(.leftTop, isEnabled: debugEditorGeometry)
            }

            HStack(spacing: 0) {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(1...20, id: \.self) { functionKeyNumber in
                            smartCommandTableButton("F\(functionKeyNumber)", foreground: .yellow) {
                                insertSmartActionTextAtSelection("F\(functionKeyNumber)")
                            }
                        }
                    }
                }
                .frame(width: functionKeyColumnWidth)
                .background(Color.black)
                .overlay {
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1)
                }

                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        if isSmartEscapeCodeTableVisible {
                            ForEach(smartEscapeCodeRows, id: \.english) { escapeCodeRow in
                                smartCommandTableButton(escapeCodeRow.english, foreground: .green) {
                                    insertSmartActionTextAtSelection(escapeCodeRow.command)
                                    smartCommandDescription = escapeCodeRow.description
                                }
                                .accessibilityHint(escapeCodeRow.description)
                            }
                        } else {
                            ForEach(smartCommandRows, id: \.english) { commandRow in
                                smartCommandTableButton(commandRow.english, foreground: .cyan) {
                                    insertSmartActionTextAtSelection(commandRow.shortcut)
                                    smartCommandDescription = commandRow.description
                                }
                                .accessibilityHint(commandRow.description)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .overlay {
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1)
                }
            }
        }
        .background(Color.black)
        .overlay {
            smartPanelBorder(edges: .all)
        }
        .clipped()
        .anchorPreference(key: SoftEditorAccessoryBounds.self, value: .bounds) {
            [.keypad: $0]
        }
    }

    private var smartScriptEditorTextBinding: Binding<String> {
        Binding(
            get: {
                smartScriptEditingModel.scriptText
            },
            set: { newText in
                let parts = smartEditingTextParts
                let canonicalScriptText = canonicalSmartScriptText(newText)
                smartScriptEditingModel.setKeyboardEditedText(canonicalScriptText)
                setEditingSlotTextFromUserEdit(composeSmartEditingText(
                    action: storedSmartScriptText(fromEditorText: canonicalScriptText),
                    right: parts.right,
                    isHidden: parts.isHidden
                ))

                guard let editingSlotIndex else {
                    return
                }

                _ = updateFunctionKeySlot(editingSlotIndex, editingSlotText)
            }
        )
    }

    private var smartScriptSelectionRangeBinding: Binding<NSRange> {
        Binding(
            get: {
                smartScriptEditingModel.selectionRange
            },
            set: { newRange in
                smartScriptEditingModel.setSelectionRange(newRange)
            }
        )
    }

    private var smartActionTextBinding: Binding<String> {
        Binding(
            get: {
                return smartScriptEditingModel.scriptText
            },
            set: { newActionText in
                let parts = smartEditingTextParts
                let canonicalScriptText = canonicalSmartScriptText(newActionText)
                smartScriptEditingModel.setEditedText(canonicalScriptText)
                setEditingSlotTextFromUserEdit(composeSmartEditingText(
                    action: storedSmartScriptText(fromEditorText: canonicalScriptText),
                    right: parts.right,
                    isHidden: parts.isHidden
                ))
            }
        )
    }

    private var smartRightTextBinding: Binding<String> {
        Binding(
            get: {
                smartEditingTextParts.right
            },
            set: { newRightText in
                let parts = smartEditingTextParts
                setEditingSlotTextFromUserEdit(composeSmartEditingText(
                    action: parts.action,
                    right: newRightText,
                    isHidden: parts.isHidden
                ))
            }
        )
    }

    func markSlotEditorSessionModified() {
        guard editingSlotIndex != nil else {
            return
        }

        didModifyCurrentSlotEditorSession = true
    }

    private func setEditingSlotTextFromUserEdit(_ newText: String) {
        guard editingSlotText != newText else {
            return
        }

        markSlotEditorSessionModified()
        editingSlotText = newText
    }

    private var smartButtonTextBinding: Binding<String> {
        Binding(
            get: {
                rightTextWithoutColorPrefix(smartRightTextBinding.wrappedValue)
            },
            set: { newButtonText in
                if let colorPrefix = smartButtonColorHex {
                    smartRightTextBinding.wrappedValue = newButtonText.isEmpty ? "\(colorPrefix):" : "\(colorPrefix):\(newButtonText)"
                } else {
                    smartRightTextBinding.wrappedValue = newButtonText
                }
            }
        )
    }

    private var smartButtonVisibilityBinding: Binding<Bool> {
        Binding(
            get: {
                !smartIsButtonHidden
            },
            set: { isVisible in
                setSmartButtonHidden(!isVisible)
            }
        )
    }

    private var smartIsButtonHidden: Bool {
        smartEditingTextParts.isHidden
    }

    private var smartEditingTextParts: (action: String, right: String, isHidden: Bool) {
        var textWithoutMetadata = editingSlotText
        var isHidden = false
        let hiddenSuffix = "::\(hiddenButtonMetadataToken)"

        if textWithoutMetadata == hiddenButtonMetadataToken {
            textWithoutMetadata = ""
            isHidden = true
        } else if textWithoutMetadata.hasSuffix(hiddenSuffix) {
            textWithoutMetadata.removeLast(hiddenSuffix.count)
            isHidden = true
        }

        guard let separatorRange = textWithoutMetadata.range(of: "::", options: .backwards) else {
            return (textWithoutMetadata, "", isHidden)
        }

        let actionText = String(textWithoutMetadata[..<separatorRange.lowerBound])
        let rightText = String(textWithoutMetadata[separatorRange.upperBound...])
        return (actionText, rightText, isHidden)
    }

    private func composeSmartEditingText(action: String, right: String, isHidden: Bool) -> String {
        var components = [action]

        if !right.isEmpty {
            components.append(right)
        }

        if isHidden {
            components.append(hiddenButtonMetadataToken)
        }

        return components.joined(separator: "::")
    }

    func canonicalSmartEditorStoredText(_ text: String) -> String {
        var textWithoutMetadata = text
        var isHidden = false
        let hiddenSuffix = "::\(hiddenButtonMetadataToken)"

        if textWithoutMetadata == hiddenButtonMetadataToken {
            textWithoutMetadata = ""
            isHidden = true
        } else if textWithoutMetadata.hasSuffix(hiddenSuffix) {
            textWithoutMetadata.removeLast(hiddenSuffix.count)
            isHidden = true
        }

        guard let separatorRange = textWithoutMetadata.range(of: "::", options: .backwards) else {
            return composeSmartEditingText(action: storedSmartScriptText(fromEditorText: canonicalSmartScriptText(editorSmartScriptText(fromStoredText: textWithoutMetadata))), right: "", isHidden: isHidden)
        }

        let actionText = String(textWithoutMetadata[..<separatorRange.lowerBound])
        let rightText = String(textWithoutMetadata[separatorRange.upperBound...])
        let canonicalRightText = canonicalSmartButtonRightTextForCommit(rightText)
        return composeSmartEditingText(action: storedSmartScriptText(fromEditorText: canonicalSmartScriptText(editorSmartScriptText(fromStoredText: actionText))), right: canonicalRightText, isHidden: isHidden)
    }

    private func canonicalSmartButtonRightTextForCommit(_ rightText: String) -> String {
        let components = rightText.components(separatedBy: ":")
        guard components.count > 1,
              let firstComponent = components.first,
              isColorPrefix(firstComponent) else {
            return canonicalSmartButtonTextForCommit(rightText)
        }

        let buttonText = components.dropFirst().joined(separator: ":")
        return "\(firstComponent):\(canonicalSmartButtonTextForCommit(buttonText))"
    }

    private func canonicalSmartButtonTextForCommit(_ buttonText: String) -> String {
        guard let symbolText = smartButtonEditorSFSymbolComponents(from: buttonText) else {
            return buttonText
        }

        return "\(symbolText.name):\(symbolText.subtitle.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    func resetSmartScriptEditingModel() {
        invalidateSoftEditorAccessorySession()
        smartScriptEditingModel.setText(canonicalSmartScriptText(editorSmartScriptText(fromStoredText: displayActionTextReplacingModifierCodes(smartEditingTextParts.action))))
    }

    private func syncSmartEditingTextFromScriptModel() {
        let parts = smartEditingTextParts
        setEditingSlotTextFromUserEdit(composeSmartEditingText(
            action: storedSmartScriptText(fromEditorText: smartScriptEditingModel.scriptText),
            right: parts.right,
            isHidden: parts.isHidden
        ))

        guard let editingSlotIndex else {
            return
        }

        _ = updateFunctionKeySlot(editingSlotIndex, editingSlotText)
    }

    private func editorSmartScriptText(fromStoredText storedText: String) -> String {
        storedText.replacingOccurrences(of: "\\n", with: "\n")
    }

    private func storedSmartScriptText(fromEditorText editorText: String) -> String {
        editorText.replacingOccurrences(of: "\n", with: "\\n")
    }

    private func canonicalSmartScriptText(_ actionText: String) -> String {
        let mappings = [(symbol: "⌃", legacy: "ctl:"), (symbol: "⌥", legacy: "op:"), (symbol: "⇧", legacy: "sh:"), (symbol: "⌘", legacy: "cm:")]
        var result = ""
        var currentIndex = actionText.startIndex

        while currentIndex < actionText.endIndex {
            var scanIndex = currentIndex
            var modifiers = Set<String>()
            var didConsumeModifier = true

            while didConsumeModifier {
                didConsumeModifier = false

                for mapping in mappings {
                    if actionText[scanIndex...].hasPrefix(mapping.legacy) {
                        modifiers.insert(mapping.symbol)
                        scanIndex = actionText.index(scanIndex, offsetBy: mapping.legacy.count)
                        didConsumeModifier = true
                        break
                    }

                    if actionText[scanIndex...].hasPrefix(mapping.symbol) {
                        modifiers.insert(mapping.symbol)
                        scanIndex = actionText.index(scanIndex, offsetBy: mapping.symbol.count)
                        didConsumeModifier = true
                        break
                    }
                }
            }

            if scanIndex != currentIndex {
                result += mappings
                    .map { $0.symbol }
                    .filter { modifiers.contains($0) }
                    .joined()
                currentIndex = scanIndex
            } else {
                result.append(actionText[currentIndex])
                currentIndex = actionText.index(after: currentIndex)
            }
        }

        return result
    }

    private var smartColorPanel: some View {
        VStack(spacing: 0) {
            SmartScriptTextEditor(
                text: smartScriptEditorTextBinding,
                selectedRange: smartScriptSelectionRangeBinding,
                fontSize: 20,
                onBeginEditing: { textView in
                    invalidateSoftEditorAccessorySession()
                    smartPasteTarget.activate(.command, textView: textView)
                },
                insertionTargetRefreshID: softEditorInsertionTargetRefreshID,
                onInsertionTargetRefresh: { textView in
                    smartPasteTarget.activate(.command, textView: textView)
                }
            )
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .background(Color.black)
                .frame(maxWidth: .infinity)
                .frame(height: smartCommandDescriptionTopOffset)
                .editorGeometryProbe(.smartScriptTextEditor, isEnabled: debugEditorGeometry)
                .editorGeometryProbe(.centreCommandTop, isEnabled: debugEditorGeometry)
                .overlay {
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1)
                }
                .anchorPreference(key: SoftEditorAccessoryBounds.self, value: .bounds) {
                    [.commandEditor: $0]
                }

            ScrollView(.vertical) {
                Text(.init(smartCommandDescription))
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .padding(6)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
            .layoutPriority(1)
            .background(Color.black)
            .overlay {
                Rectangle()
                    .stroke(Color.white, lineWidth: 1)
                    .scaleEffect(y: isPad ? 1 : smartIPhoneCommandLowerHeightScale, anchor: .top)
            }
            .editorGeometryProbe(.commandDescription, isEnabled: debugEditorGeometry)
            .anchorPreference(key: SoftEditorAccessoryBounds.self, value: .bounds) {
                [.description: $0]
            }

            if !isPad {
                smartIPhoneCommandActionControls
            }
        }
        .frame(maxWidth: .infinity, maxHeight: isPad ? nil : .infinity, alignment: .top)
        .background(Color.black)
        .overlay {
            Rectangle()
                .stroke(Color.white, lineWidth: 1)
        }
        .clipped()
    }

    private var smartIPhoneCommandActionControls: some View {
        let visibleButtonHeight = (smartIPhoneRightTableVisibleCellHeight ?? smartButtonPanelColorCellHeight) * smartIPhoneActionButtonHeightScale

        return HStack(spacing: 0) {
            smartDeleteAllButton(
                visibleHeight: visibleButtonHeight,
                visibleAlignment: .bottom,
                probeTarget: nil
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            smartControlButton(
                "test",
                systemName: "play.fill",
                background: Color(red: 0.0, green: 0.5, blue: 0.0),
                visibleHeight: visibleButtonHeight,
                visibleAlignment: .bottom,
                probeTarget: .testVisibleButton
            ) {
                testEditingSlotText()
                // Help text location: command panel test button.
                smartCommandDescription = smartHelpSFTestButton
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Test")
            .editorGeometryProbe(.testButton, isEnabled: debugEditorGeometry)
            smartControlButton(
                "close",
                systemName: "xmark",
                background: Color.gray.opacity(0.45),
                iconWeight: .bold,
                visibleHeight: visibleButtonHeight,
                visibleAlignment: .bottom,
                probeTarget: .closeVisibleButton
            ) {
                saveSlotEditing()
                cancelSlotEditing()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Close")
            .editorGeometryProbe(.closeButton, isEnabled: debugEditorGeometry)
        }
        .frame(height: smartButtonPanelColorCellHeight)
    }

    private func smartIPhoneButtonControlRow(editorWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            smartIPhoneSlotPositionLabel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .editorGeometryProbe(.rightControlRowCell, isEnabled: debugEditorGeometry)
            smartArrowButton(systemName: "arrow.left") {
                selectPreviousEditableSlot()
                // Help text location: button panel left arrow.
                smartCommandDescription = smartHelpSFArrows
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            smartArrowButton(systemName: "arrow.right") {
                selectNextEditableSlot()
                // Help text location: button panel right arrow.
                smartCommandDescription = smartHelpSFArrows
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            smartIPhoneModePlaceholderButton
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            smartColonButton
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: editorWidth, height: smartIPhoneButtonControlRowHeight)
        .editorGeometryProbe(.rightControlRow, isEnabled: debugEditorGeometry)
    }

    @ViewBuilder
    private var smartIPhoneSlotPositionLabel: some View {
        if let editingSlotIndex, visibleGridDimensions.columns > 0 {
            let column = (editingSlotIndex % visibleGridDimensions.columns) + 1
            let row = (editingSlotIndex / visibleGridDimensions.columns) + 1

            HStack(spacing: 0) {
                Text("\(column)")
                    .foregroundStyle(.green)
                Text(":")
                    .foregroundStyle(.white)
                Text("\(row)")
                    .foregroundStyle(.red)
            }
            .font(.system(size: 19, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.35)
            .allowsTightening(true)
            .padding(.horizontal, smartPositionIndicatorHorizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .overlay {
                Rectangle()
                    .stroke(Color.white, lineWidth: 1)
            }
        } else {
            Rectangle()
                .fill(Color.black)
                .overlay {
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1)
                }
        }
    }

    private var smartIPhoneModePlaceholderButton: some View {
        Button {
            isSmartPhoneSFSymbolMode.toggle()
        } label: {
            Image(systemName: isSmartPhoneSFSymbolMode ? "command" : "paintpalette")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(isSmartPhoneSFSymbolMode ? .yellow : .green)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .overlay {
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSmartPhoneSFSymbolMode ? "Show colour palette" : "Show SF Symbols")
    }

    private func smartButtonPanel(editorWidth: CGFloat = 0) -> some View {
        let resolvedEditorWidth = editorWidth > 0 ? editorWidth : smartIPhoneButtonContentWidth

        return Group {
            if isPad {
                IPadSmartButtonPanel(
                    debugEditorGeometry: debugEditorGeometry,
                    brightnessSliderColumn: {
                        AnyView(smartButtonBrightnessSliderColumn)
                    },
                    preview: {
                        AnyView(smartButtonPreview())
                    },
                    clearPreviewBackground: {
                        AnyView(smartButtonClearPreviewBackground)
                    },
                    lowerEditingArea: {
                        AnyView(
                            smartButtonLowerEditingArea(editorWidth: resolvedEditorWidth)
                        )
                    },
                    panelBorder: {
                        AnyView(smartPanelBorder(edges: .all))
                    }
                )
            } else {
                VStack(spacing: 0) {
                    smartIPhoneButtonPreviewRow(editorWidth: resolvedEditorWidth)

                    smartIPhoneButtonControlRow(editorWidth: resolvedEditorWidth)

                    smartButtonLowerEditingArea(editorWidth: resolvedEditorWidth)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Color.black)
                .overlay {
                    smartPanelBorder(edges: [.top, .trailing, .bottom])
                }
                .clipped()
            }
        }
    }

    private var smartButtonBrightnessSliderColumn: some View {
        Slider(value: $smartButtonBrightness, in: 0...1)
            .rotationEffect(.degrees(-90))
            .frame(width: 116, height: 24)
            .tint(.yellow)
            .onChange(of: smartButtonBrightness) {
                applySmartButtonBrightness()
            }
            .frame(width: smartColorSliderColumnWidth, height: 121, alignment: .center)
    }

    @ViewBuilder
    private func smartIPhoneButtonBrightnessSlider(height: CGFloat, width: CGFloat) -> some View {
        Slider(value: $smartButtonBrightness, in: 0...1)
            .frame(width: height, height: width * 0.55)
            .rotationEffect(.degrees(-90))
            .tint(.yellow)
            .onChange(of: smartButtonBrightness) {
                applySmartButtonBrightness()
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .iPhoneButtonBrightnessSliderFrameReporter()
    }

    private func smartIPhoneButtonPreviewRow(editorWidth: CGFloat) -> some View {
        let previewAreaHeight = smartIPhoneButtonPreviewEnclosureHeight
       
		// BUTTON HEIGHT
		let previewHeight = previewAreaHeight * (38.0 / 44.0)
		// BUTTON VERTICAL POSITION
		let previewTopAdjustment = previewAreaHeight * (0.0 / 44.0)
		// BUTTON WIDTH / RIGHT-SIDE SPACE
		let previewTrailingMargin = editorWidth * 0.0402
		//
		//----------------------------------------
		//
		let previewLeadingMargin = editorWidth * 0.015

		let sliderHeight = previewAreaHeight * (37.0 / 44.0)
		let previewSliderSpacing = editorWidth * 0.0048
		let sliderColumnWidth = editorWidth * 0.14
		//
		//----------------------------------------
		//
        let previewFootprintWidth = max(
            0,
            editorWidth - previewLeadingMargin - sliderColumnWidth - previewSliderSpacing - previewTrailingMargin
        )
        let previewVerticalPadding = (previewAreaHeight - previewHeight) / 2
        let previewRightPaddingInsideFootprint = max(0, previewVerticalPadding - previewTrailingMargin)
        let previewAspectRatio = max(0, (previewFootprintWidth - previewRightPaddingInsideFootprint) / previewHeight)

        return HStack(alignment: .top, spacing: previewSliderSpacing) {
            smartIPhoneButtonBrightnessSlider(height: sliderHeight, width: sliderColumnWidth)
                .editorGeometryProbe(.slider, isEnabled: debugEditorGeometry)
                .frame(width: sliderColumnWidth, height: previewAreaHeight, alignment: .center)

            smartButtonPreview(
                footprintWidth: previewFootprintWidth,
                previewHeight: previewHeight,
                aspectRatio: previewAspectRatio
            )
            .frame(width: previewFootprintWidth, height: previewHeight, alignment: .leading)
            .offset(y: previewTopAdjustment)
            .editorGeometryProbe(.previewFootprint, isEnabled: debugEditorGeometry)
            .frame(width: previewFootprintWidth, height: previewAreaHeight, alignment: .center)
        }
        .frame(height: previewAreaHeight, alignment: .top)
        .padding(.leading, previewLeadingMargin)
        .padding(.trailing, previewTrailingMargin)
        .frame(width: editorWidth, height: previewAreaHeight, alignment: .leading)
        .background {
            smartButtonClearPreviewBackground
        }
        .editorGeometryProbe(.rightPreviewArea, isEnabled: debugEditorGeometry)
    }

    @ViewBuilder
    private func smartButtonLowerEditingArea(editorWidth: CGFloat = 0) -> some View {
        let resolvedEditorWidth = editorWidth > 0 ? editorWidth : smartIPhoneButtonContentWidth

        if isPad {
            smartButtonColorGrid
                .frame(maxWidth: .infinity, alignment: .top)
                .frame(height: smartViewHeight - smartCommandDescriptionTopOffset + smartButtonPanelColorCellHeight, alignment: .top)
                .editorGeometryProbe(.rightTableRegion, isEnabled: debugEditorGeometry)
        } else {
            smartIPhoneButtonSharedEditingArea(editorWidth: resolvedEditorWidth)
                .frame(width: resolvedEditorWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                .layoutPriority(1)
                .editorGeometryProbe(.rightTableRegion, isEnabled: debugEditorGeometry)
        }
    }

    @ViewBuilder
    private func smartIPhoneButtonSharedEditingArea(editorWidth: CGFloat) -> some View {
        if !isSmartPhoneSFSymbolMode {
            smartIPhoneButtonColorGrid(editorWidth: editorWidth)
        } else {
            smartIPhoneSFSymbolGrid(editorWidth: editorWidth)
        }
    }

    private var smartButtonColorGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                smartVisibilityButton
                    .frame(maxWidth: .infinity)
                smartClearColorButton
                    .frame(maxWidth: .infinity)
                smartRandomColorButton
                    .frame(maxWidth: .infinity)
                smartColonButton
                    .frame(maxWidth: .infinity)
            }
            .frame(height: smartButtonPanelColorCellHeight)

            ScrollView(.vertical) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 5),
                    spacing: 0
                ) {
                    ForEach(Array(isPad ? smartIPadButtonSwatchHexColors : smartIPhoneButtonSwatchHexColors), id: \.self) { hexColor in
                        smartButtonColorSwatch(hexColor, usesBrightnessAdjustedFill: false)
                    }
                }
            }
        }
    }

    private var smartIPadButtonSwatchHexColors: [String] {
        smartIPhoneButtonSwatchHexColors + ["00E5FF", "7CFC00", "FFD700"]
    }

    private func smartIPhoneButtonEditorDynamicColumnCount(editorWidth: CGFloat) -> Int {
        max(1, Int((editorWidth / smartIPhoneButtonEditorCellSize).rounded()))
    }

    private func smartIPhoneButtonEditorDynamicCellWidth(editorWidth: CGFloat) -> CGFloat {
        editorWidth / CGFloat(smartIPhoneButtonEditorDynamicColumnCount(editorWidth: editorWidth))
    }

    private func smartIPhoneButtonEditorColumnCount(editorWidth: CGFloat) -> Int {
        5
    }

    private func smartIPhoneButtonEditorCellWidth(editorWidth: CGFloat) -> CGFloat {
        editorWidth / CGFloat(smartIPhoneButtonEditorColumnCount(editorWidth: editorWidth))
    }

    private func smartIPhoneButtonEditorGridItems(editorWidth: CGFloat) -> [GridItem] {
        let columnCount = smartIPhoneButtonEditorColumnCount(editorWidth: editorWidth)
        return Array(repeating: GridItem(.flexible(), spacing: 0), count: columnCount)
    }

    private func smartIPhoneButtonColorGrid(editorWidth: CGFloat) -> some View {
        smartIPhoneButtonSelectionGrid(editorWidth: editorWidth) {
            smartVisibilityButton
            smartClearColorButton
            smartRandomColorButton
            ForEach(Array(smartIPhoneButtonSwatchHexColors), id: \.self) { hexColor in
                smartButtonColorSwatch(hexColor, usesBrightnessAdjustedFill: false)
            }
        }
    }

    private func smartIPhoneButtonSelectionGrid<Content: View>(
        editorWidth: CGFloat,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        ScrollView(.vertical) {
            LazyVGrid(
                columns: smartIPhoneButtonEditorGridItems(editorWidth: editorWidth),
                spacing: 0
            ) {
                content()
            }
        }
        .frame(width: editorWidth)
    }

    @ViewBuilder
    private func smartButtonPreview(
        footprintWidth: CGFloat? = nil,
        previewHeight requestedPreviewHeight: CGFloat? = nil,
        aspectRatio: CGFloat = 1
    ) -> some View {

		// MARK: - BM:🔆 IPAD BUTTON HEIGHT (1st number)
//        let previewFootprintHeight: CGFloat = isPad ? 118 : requestedPreviewHeight ?? smartIPhoneButtonPreviewEnclosureHeight
        let previewFootprintHeight: CGFloat = isPad ? 110 : requestedPreviewHeight ?? smartIPhoneButtonPreviewEnclosureHeight
        
		
		let resolvedPreviewFootprintWidth = footprintWidth ?? smartIPhoneButtonPreviewWidth
        let previewHeight: CGFloat = isPad ? previewFootprintHeight : requestedPreviewHeight ?? min(max(0, previewFootprintHeight - 24), max(0, resolvedPreviewFootprintWidth - 24))
        let previewWidth: CGFloat? = isPad ? nil : min(previewHeight * aspectRatio, resolvedPreviewFootprintWidth)
        let previewMaxWidth: CGFloat? = isPad ? .infinity : nil
        let previewFootprintWidth: CGFloat? = isPad ? nil : resolvedPreviewFootprintWidth

        if smartIsButtonHidden {
            Color.clear
                .frame(width: previewWidth)
                .frame(maxWidth: previewMaxWidth)
                .frame(height: previewHeight)
                .editorGeometryProbe(.actualPreviewButton, isEnabled: debugEditorGeometry)
                .frame(width: previewFootprintWidth, height: previewFootprintHeight)
        } else {
            Group {
                if let symbolDisplay = smartButtonSFSymbolDisplay {
                    let sfGroupMultiplier = isPad ? iPadSFPreviewSizeMultiplier : iPhoneSFSymbolPreviewGroupMultiplier
                    let sfGroupYOffset = isPad ? iPadSFSymbolPreviewGroupYOffset : 0
                    let preferredSymbolSize = max(18, CGFloat(boxFontSize) * 1.0 * sfGroupMultiplier)
                    let subtitleFontSize = max(14, CGFloat(boxFontSize) * 0.8 * sfGroupMultiplier)
                    let subtitleVisibleLineCount = smartPreviewVisibleLineCount(
                        for: smartButtonEditablePreviewTextBinding.wrappedValue
                    )
                    let preferredSubtitleTextHeight = SmartPreviewTextView.preferredHeight(
                        fontSize: subtitleFontSize,
                        maximumVisibleLines: subtitleVisibleLineCount
                    )
                    let preferredGroupHeight = preferredSymbolSize + 4 + preferredSubtitleTextHeight
                    let fittingPreviewHeight = max(1, previewHeight - (sfGroupYOffset * 2))
                    let groupScale = min(1, fittingPreviewHeight / preferredGroupHeight)
                    let symbolSize = max(14, preferredSymbolSize * groupScale)
                    let fittedSubtitleFontSize = subtitleFontSize * groupScale
                    let subtitleTextFieldHeight = SmartPreviewTextView.preferredHeight(
                        fontSize: fittedSubtitleFontSize,
                        maximumVisibleLines: subtitleVisibleLineCount
                    )

                    VStack(spacing: 4) {
                        Image(systemName: symbolDisplay.name)
                            .resizable()
                            .scaledToFit()
                            .frame(width: symbolSize, height: symbolSize)

                        SmartPreviewTextView(
                            text: smartButtonEditablePreviewTextBinding,
                            selectedRange: $smartButtonPreviewSelectionRange,
                            fontSize: fittedSubtitleFontSize,
                            maximumVisibleLines: subtitleVisibleLineCount,
                            disablesAutomaticPeriodShortcut: true,
                            onBeginEditing: { textView in
                                invalidateSoftEditorAccessorySession()
                                smartPasteTarget.activate(.button, textView: textView)
                            },
                            insertionTargetRefreshID: softEditorInsertionTargetRefreshID,
                            onInsertionTargetRefresh: { textView in
                                smartPasteTarget.activate(.button, textView: textView)
                            }
                        )
                            .frame(height: subtitleTextFieldHeight)
                            .padding(.horizontal, 8)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .offset(y: sfGroupYOffset)
                } else {
                    let ordinaryPreviewFontSize = CGFloat(boxFontSize) * (isPad ? 1 : iPhoneOrdinaryPreviewFontMultiplier)
                    let ordinaryVisibleLineCount = smartPreviewVisibleLineCount(
                        for: smartButtonEditablePreviewTextBinding.wrappedValue
                    )

                    SmartPreviewTextView(
                        text: smartButtonEditablePreviewTextBinding,
                        selectedRange: $smartButtonPreviewSelectionRange,
                        fontSize: ordinaryPreviewFontSize,
                        maximumVisibleLines: ordinaryVisibleLineCount,
                        disablesAutomaticPeriodShortcut: true,
                        onBeginEditing: { textView in
                            invalidateSoftEditorAccessorySession()
                            smartPasteTarget.activate(.button, textView: textView)
                        },
                        insertionTargetRefreshID: softEditorInsertionTargetRefreshID,
                        onInsertionTargetRefresh: { textView in
                            smartPasteTarget.activate(.button, textView: textView)
                        }
                    )
                        .frame(height: min(previewHeight, SmartPreviewTextView.preferredHeight(
                            fontSize: ordinaryPreviewFontSize,
                            maximumVisibleLines: ordinaryVisibleLineCount
                        )))
                        .padding(.horizontal, 8)
                }
            }
            .frame(width: previewWidth)
            .frame(maxWidth: previewMaxWidth)
            .frame(height: previewHeight)
            .background(smartButtonPreviewBackground)
            .clipShape(.rect(cornerRadius: 18))
            .overlay(alignment: .topLeading) {
                smartButtonPreviewClearButton
            }
            .overlay {
                if isPad {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Color.white, lineWidth: 1.5)
                } else {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white, lineWidth: 1.5)
                }
            }
            .editorGeometryProbe(.actualPreviewButton, isEnabled: debugEditorGeometry)
            .frame(width: previewFootprintWidth, height: previewFootprintHeight)
        }
    }

    private var smartButtonPreviewClearButton: some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            smartButtonTextBinding.wrappedValue = ""
        } label: {
            Text("x")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 46, height: 46, alignment: .topLeading)
                .padding(.top, 7)
                .padding(.leading, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear button symbol and text")
    }

    private func smartButtonEditorSFSymbolComponents(from text: String) -> (name: String, subtitle: String)? {
        let components = text.components(separatedBy: ":")
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

        return (candidateName, subtitle)
    }

    private var smartButtonSFSymbolDisplay: (name: String, subtitle: String?)? {
        guard let symbolText = smartButtonEditorSFSymbolComponents(from: smartButtonTextBinding.wrappedValue) else {
            return nil
        }

        return (symbolText.name, symbolText.subtitle.isEmpty ? nil : symbolText.subtitle)
    }

    private var smartButtonEditablePreviewTextBinding: Binding<String> {
        Binding(
            get: {
                if let symbolDisplay = smartButtonSFSymbolDisplay {
                    return displayText(from: symbolDisplay.subtitle ?? "")
                }

                return displayText(from: smartButtonTextBinding.wrappedValue)
            },
            set: { newText in
                let storedText = escapedPreviewTextForStorage(newText)
                if let symbolDisplay = smartButtonSFSymbolDisplay {
                    smartButtonTextBinding.wrappedValue = "\(symbolDisplay.name):\(storedText)"
                } else {
                    smartButtonTextBinding.wrappedValue = storedText
                }
            }
        )
    }

    private func escapedPreviewTextForStorage(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    private func smartPreviewVisibleLineCount(for text: String) -> Int {
        min(max(text.components(separatedBy: .newlines).count, 1), 4)
    }

    private func setSmartButtonSFSymbol(_ symbolName: String) {
        let currentText = smartButtonTextBinding.wrappedValue
        let symbolText = smartButtonSymbolTextComponents(from: currentText)

        if let symbolText {
            smartButtonTextBinding.wrappedValue = "\(symbolName):\(symbolText.subtitle)"
        } else if currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            smartButtonTextBinding.wrappedValue = "\(symbolName):"
        } else {
            smartButtonTextBinding.wrappedValue = "\(symbolName):\(currentText)"
        }
    }

    private func smartButtonSymbolTextComponents(from text: String) -> (name: String, subtitle: String)? {
        smartButtonEditorSFSymbolComponents(from: text)
    }

    private var smartVisibilityButton: some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            smartButtonVisibilityBinding.wrappedValue.toggle()
            // Help text location: btn panel eye button.
            smartCommandDescription = smartHelpButtonVisibility
        } label: {
            Image(systemName: smartButtonVisibilityBinding.wrappedValue ? "eye" : "eye.slash")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: smartButtonPanelColorCellHeight)
                .background(Color.black)
                .overlay {
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1)
                }
                .editorGeometryProbe(.rightUtilityVisibleCell, isEnabled: debugEditorGeometry)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(smartButtonVisibilityBinding.wrappedValue ? "Hide button" : "Show button")
        .editorGeometryProbe(.rightUtilityRow, isEnabled: debugEditorGeometry)
    }

    private var smartClearColorButton: some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            setSmartButtonHidden(false)
            smartButtonBrightnessBaseHex = nil
            smartButtonBrightness = 0.5
            smartRightTextBinding.wrappedValue = rightTextWithoutColorPrefix(smartRightTextBinding.wrappedValue)
            // Help text location: btn panel clr button.
            smartCommandDescription = smartHelpButtonClearColor
        } label: {
            Text("clr")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: smartButtonPanelColorCellHeight)
                .background(Color.black)
                .overlay {
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private var smartRandomColorButton: some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            let red = Int.random(in: 0...255)
            let green = Int.random(in: 0...255)
            let blue = Int.random(in: 0...255)
            setSmartButtonColor(String(format: "%02X%02X%02X", red, green, blue))
            // Help text location: btn panel rnd button.
            smartCommandDescription = smartHelpButtonRandomColor
        } label: {
            Text("rnd")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: smartButtonPanelColorCellHeight)
                .background(Color.black)
                .overlay {
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set random button color")
    }

    private var smartColonButton: some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            insertSmartPreviewTextAtSelection(":")
            // Help text location: btn panel colon button.
            smartCommandDescription = smartHelpButtonColon
        } label: {
            Text(":")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: smartButtonPanelColorCellHeight)
                .background(Color.black)
                .overlay {
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Insert colon")
    }

    private func insertSmartPreviewTextAtSelection(_ insertedText: String) {
        var previewText = smartButtonEditablePreviewTextBinding.wrappedValue
        let textLength = previewText.utf16.count
        let location = min(max(smartButtonPreviewSelectionRange.location, 0), textLength)
        let length = max(0, min(smartButtonPreviewSelectionRange.length, textLength - location))
        let replacementRange = NSRange(location: location, length: length)

        if let range = Range(replacementRange, in: previewText) {
            previewText.replaceSubrange(range, with: insertedText)
        } else {
            previewText.append(insertedText)
        }

        smartButtonEditablePreviewTextBinding.wrappedValue = previewText
        smartButtonPreviewSelectionRange = NSRange(location: location + insertedText.utf16.count, length: 0)
    }

    private func smartButtonColorSwatch(_ hexColor: String, usesBrightnessAdjustedFill: Bool = true) -> some View {
        let normalizedHexColor = hexColor.uppercased()
        let displayHexColor = usesBrightnessAdjustedFill ? (adjustedSmartButtonColorHex(for: hexColor) ?? hexColor) : hexColor

        return Button {
            ButtonClickFeedback.playIfEnabled()
            setSmartButtonColor(hexColor)
            // Help text location: btn panel color swatches.
            smartCommandDescription = smartHelpButtonColor
        } label: {
            ZStack {
                Color(hex: displayHexColor)

                if normalizedHexColor == "000000" {
                    Text("black")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
                .frame(maxWidth: .infinity, minHeight: smartButtonPanelColorCellHeight)
                .overlay {
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1)
                }
                .smartIPhoneRightTableVisibleCellHeightReader(isEnabled: !isPad)
                .editorGeometryProbe(.rightTableVisibleCell, isEnabled: debugEditorGeometry)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set button color \(hexColor)")
        .editorGeometryProbe(.rightTableCell, isEnabled: debugEditorGeometry)
    }

    private func smartVerticalSliderLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
    }

    @ViewBuilder
    private var smartColorImage: some View {
        if let colorImage = UIImage(named: "color") ?? bundledColorImage() {
            Image(uiImage: colorImage)
                .resizable()
        } else {
            Color.black
        }
    }

    private func bundledColorImage() -> UIImage? {
        guard let imageURL = Bundle.main.url(forResource: "color", withExtension: "png") else {
            return nil
        }

        return UIImage(contentsOfFile: imageURL.path)
    }

    private func applySmartColorSelection(at location: CGPoint, in containerSize: CGSize) {
        guard let colorImage = UIImage(named: "color") ?? bundledColorImage(),
              let hexColor = hexColorFromImage(colorImage, at: location, in: containerSize) else {
            return
        }

        setSmartButtonColor(hexColor)
    }

    private func hexColorFromImage(_ image: UIImage, at location: CGPoint, in containerSize: CGSize) -> String? {
        guard let cgImage = image.cgImage,
              containerSize.width > 0,
              containerSize.height > 0 else {
            return nil
        }

        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        let imageX = min(max(location.x / containerSize.width * imageWidth, 0), imageWidth - 1)
        let imageY = min(max(location.y / containerSize.height * imageHeight, 0), imageHeight - 1)

        return hexColorFromPixel(
            x: Int(imageX.rounded(.down)),
            y: Int(imageY.rounded(.down)),
            in: cgImage
        )
    }

    private func hexColorFromPixel(x: Int, y: Int, in cgImage: CGImage) -> String? {
        guard let croppedImage = cgImage.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else {
            return nil
        }

        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return nil
        }

        context.draw(croppedImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return String(format: "%02X%02X%02X", pixel[0], pixel[1], pixel[2])
    }

    private func rightTextReplacingColorPrefix(with hexColor: String) -> String {
        "\(hexColor):\(rightTextWithoutColorPrefix(smartRightTextBinding.wrappedValue))"
    }

    private var smartButtonColorHex: String? {
        let rightText = smartRightTextBinding.wrappedValue
        let components = rightText.components(separatedBy: ":")

        guard let firstComponent = components.first,
              isSixDigitHexColor(firstComponent) else {
            return nil
        }

        return firstComponent.uppercased()
    }

    private var smartButtonPreviewColor: Color {
        guard let colorHex = smartButtonColorHex else {
            return Color.clear
        }

        return Color(hex: colorHex).opacity(mainGridBackgroundOpacity)
    }

    @ViewBuilder
    private var smartButtonPreviewBackground: some View {
        ZStack {
            smartButtonClearPreviewImageBackground

            if smartButtonColorHex == nil {
                Color.clear
            } else {
                smartButtonPreviewColor
            }
        }
    }

    @ViewBuilder
    private var smartButtonClearPreviewImageBackground: some View {
        if let image = smartButtonClearPreviewImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .opacity(backgroundImageOpacity)
                .clipped()
        } else {
            Color.black
        }
    }

    private var smartButtonClearPreviewBackground: some View {
        Color.black
    }

    private var smartButtonClearPreviewImage: UIImage? {
        if let mainBackgroundImage {
            return mainBackgroundImage
        }

        return nil
    }

    private func setSmartButtonColor(_ hexColor: String) {
        setSmartButtonHidden(false)
        let normalizedHex = hexColor.uppercased()
        smartButtonBrightnessBaseHex = normalizedHex
        smartRightTextBinding.wrappedValue = rightTextReplacingColorPrefix(
            with: adjustedSmartButtonColorHex(for: normalizedHex) ?? normalizedHex
        )
    }

    private func applySmartButtonBrightness() {
        guard let colorHex = smartButtonBrightnessBaseHex ?? smartButtonColorHex,
              let adjustedHex = adjustedSmartButtonColorHex(for: colorHex) else {
            return
        }

        if smartButtonBrightnessBaseHex == nil {
            smartButtonBrightnessBaseHex = colorHex
        }
        smartRightTextBinding.wrappedValue = rightTextReplacingColorPrefix(with: adjustedHex)
    }

    private func adjustedSmartButtonColorHex(for hexColor: String) -> String? {
        adjustedHexColor(hexColor, brightness: smartButtonBrightness)
    }

    private func adjustedHexColor(_ hexColor: String, brightness: Double) -> String? {
        guard let rgb = rgbComponents(from: hexColor) else {
            return nil
        }

        let clampedBrightness = min(max(brightness, 0), 1)
        let adjusted: (Double) -> Int = { component in
            let value: Double
            if clampedBrightness < 0.5 {
                value = component * (clampedBrightness / 0.5)
            } else {
                value = component + ((255 - component) * ((clampedBrightness - 0.5) / 0.5))
            }

            return Int(min(max(value.rounded(), 0), 255))
        }

        return String(
            format: "%02X%02X%02X",
            adjusted(rgb.red),
            adjusted(rgb.green),
            adjusted(rgb.blue)
        )
    }

    private func rgbComponents(from hexColor: String) -> (red: Double, green: Double, blue: Double)? {
        let trimmedHex = hexColor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSixDigitHexColor(trimmedHex) else {
            return nil
        }

        var intValue: UInt64 = 0
        Scanner(string: trimmedHex).scanHexInt64(&intValue)
        return (
            Double((intValue >> 16) & 0xFF),
            Double((intValue >> 8) & 0xFF),
            Double(intValue & 0xFF)
        )
    }

    private func rightTextWithoutColorPrefix(_ rightText: String) -> String {
        let components = rightText.components(separatedBy: ":")
        guard components.count > 1,
              let firstComponent = components.first,
              isColorPrefix(firstComponent) else {
            return rightText
        }

        return components.dropFirst().joined(separator: ":")
    }

    private func isColorPrefix(_ text: String) -> Bool {
        isSixDigitHexColor(text) || isLegacyColorPrefix(text)
    }

    // Old button files used a single character color code, for example "c:calendar:draw".
    private func isLegacyColorPrefix(_ text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.count == 1,
              let scalar = trimmedText.unicodeScalars.first else {
            return false
        }

        return CharacterSet.alphanumerics.contains(scalar)
    }

    private func isSixDigitHexColor(_ text: String) -> Bool {
        guard text.count == 6 else {
            return false
        }

        let hexDigits = "0123456789abcdefABCDEF"
        return text.allSatisfy { hexDigits.contains($0) }
    }

    private func setSmartButtonHidden(_ isHidden: Bool) {
        let parts = smartEditingTextParts
        setEditingSlotTextFromUserEdit(composeSmartEditingText(
            action: parts.action,
            right: parts.right,
            isHidden: isHidden
        ))
    }

    private func smartPlaceholderButton(systemName: String) -> some View {
        Button {
            guard !smartPlaceholderButtonIsDisabled(systemName) else {
                return
            }

            if systemName == "delete.left.fill" {
                deleteSmartEditorBackward()
            } else if systemName == "arrow.left" {
                ButtonClickFeedback.playIfEnabled()
                smartScriptEditingModel.moveCaretLeft()
            } else if systemName == "arrow.right" {
                ButtonClickFeedback.playIfEnabled()
                smartScriptEditingModel.moveCaretRight()
            } else if systemName == "arrow.uturn.backward" {
                ButtonClickFeedback.playIfEnabled()
                smartScriptEditingModel.undo()
                syncSmartEditingTextFromScriptModel()
            } else if systemName == "arrow.uturn.forward" {
                ButtonClickFeedback.playIfEnabled()
                smartScriptEditingModel.redo()
                syncSmartEditingTextFromScriptModel()
            } else if systemName == "arrow.up" {
                ButtonClickFeedback.playIfEnabled()
                smartScriptEditingModel.moveCaretUp()
            } else if systemName == "arrow.down" {
                ButtonClickFeedback.playIfEnabled()
                smartScriptEditingModel.moveCaretDown()
            } else if systemName == "doc.on.doc" || systemName == "scissors" {
                copyOrCutSmartEditorSelection(isCut: systemName == "scissors")
            } else if systemName == "doc.on.clipboard" {
                pasteSmartActionTextFromSystemClipboard()
            } else if systemName == "delete.right.fill" {
                ButtonClickFeedback.playIfEnabled()
                smartScriptEditingModel.deleteForward()
                smartActionTextBinding.wrappedValue = smartScriptEditingModel.scriptText
            } else if systemName == "delete.backward.fill" {
                ButtonClickFeedback.playIfEnabled()
                smartScriptEditingModel.deleteBackward()
                smartActionTextBinding.wrappedValue = smartScriptEditingModel.scriptText
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(smartPlaceholderButtonForegroundColor(for: systemName))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .overlay {
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
    }

    private func deleteSmartEditorBackward() {
        guard editingSlotIndex != nil,
              let textView = smartPasteTarget.textView,
              textView.window != nil,
              textView.text == softEditorAccessoryTargetText else {
            return
        }

        ButtonClickFeedback.playIfEnabled()
        switch smartPasteTarget.editor {
        case .command:
            smartScriptEditingModel.setSelectionRange(textView.selectedRange)
            smartScriptEditingModel.deleteBackward()
            smartActionTextBinding.wrappedValue = smartScriptEditingModel.scriptText
        case .button:
            textView.deleteBackward()
        }
    }

    private func clearSmartCommandText() {
        ButtonClickFeedback.playIfEnabled()
        smartActionTextBinding.wrappedValue = ""
        smartScriptEditingModel.setSelectionRange(NSRange(location: 0, length: 0))
    }

    private func smartPlaceholderButtonIsDisabled(_ systemName: String) -> Bool {
        if systemName == "delete.left.fill" {
            return !canDeleteSmartEditorBackward
        }

        if systemName == "doc.on.doc" || systemName == "scissors" {
            return smartClipboardSelection == nil
        }

        if systemName == "arrow.left" {
            return !smartScriptEditingModel.canMoveCaretLeft
        }

        if systemName == "arrow.right" {
            return !smartScriptEditingModel.canMoveCaretRight
        }

        if systemName == "arrow.uturn.backward" {
            return !smartScriptEditingModel.canUndo
        }

        if systemName == "arrow.uturn.forward" {
            return !smartScriptEditingModel.canRedo
        }

        if systemName == "arrow.up" {
            return !smartScriptEditingModel.canMoveCaretUp
        }

        if systemName == "arrow.down" {
            return !smartScriptEditingModel.canMoveCaretDown
        }

        if systemName == "delete.right.fill" {
            return !smartScriptEditingModel.canDeleteForward
        }

        if systemName == "delete.backward.fill" {
            return !smartScriptEditingModel.canDeleteBackward
        }

        return false
    }

    private var canDeleteSmartEditorBackward: Bool {
        guard editingSlotIndex != nil,
              let textView = smartPasteTarget.textView,
              textView.window != nil else {
            return false
        }

        let text: String
        let selection: NSRange
        switch smartPasteTarget.editor {
        case .command:
            text = smartScriptEditingModel.scriptText
            selection = smartScriptEditingModel.selectionRange
        case .button:
            text = smartButtonEditablePreviewTextBinding.wrappedValue
            selection = smartButtonPreviewSelectionRange
        }

        let textLength = text.utf16.count
        guard selection.location != NSNotFound,
              selection.location >= 0,
              selection.length >= 0,
              selection.location <= textLength,
              selection.length <= textLength - selection.location else {
            return false
        }

        return selection.length > 0 || selection.location > 0
    }

    private func smartPlaceholderButtonForegroundColor(for systemName: String) -> Color {
        if smartPlaceholderButtonIsDisabled(systemName) {
            return .gray
        }

        if systemName == "xmark" || systemName == "delete.left.fill" || systemName == "delete.right.fill" || systemName == "delete.backward.fill" {
            return .red
        }

        if systemName == "doc.on.clipboard" {
            return .green
        }

        if systemName.isEmpty {
            return .gray
        }

        return .white
    }

    private func smartModifierButton(systemName: String, accessibilityLabel: String, prefix: String) -> some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            toggleSmartModifierPrefix(prefix)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.yellow)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .overlay {
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var smartCommandColonButton: some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            insertSmartActionTextAtSelection(":")
            smartCommandDescription = smartHelpButtonColon
        } label: {
            Text(":")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .overlay {
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Insert colon")
    }

    private var smartEscapeCodeToggleButton: some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            isSmartEscapeCodeTableVisible.toggle()
            // Help text location: command panel widgets/special-keys switch.
            smartCommandDescription = isSmartEscapeCodeTableVisible
                ? smartHelpCommandSwitchSpecialKeys
                : smartHelpCommandSwitchWidgets
        } label: {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(isSmartEscapeCodeTableVisible ? .green : .cyan)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .overlay {
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSmartEscapeCodeTableVisible ? "Show widgets table" : "Show escape code table")
    }

    private func smartCommandTableButton(
        _ title: String,
        foreground: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            action()
        } label: {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity)
                .frame(height: smartCommandTableRowHeight)
                .background(Color.black)
                .overlay {
                    Rectangle()
                        .stroke(Color.white.opacity(0.55), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .editorGeometryProbe(.commandTableRow, isEnabled: debugEditorGeometry)
    }


    // MARK: - BM:🅱️ Resolve overlay anchors without adding columns or changing editor proposals.
    private func softEditorAccessoryOverlay(
        anchors: [SoftEditorAccessoryRegion: Anchor<CGRect>]
    ) -> some View {
        GeometryReader { geometry in
            if editingSlotIndex != nil,
               let commandEditorAnchor = anchors[.commandEditor],
               let keypadAnchor = anchors[.keypad] {
                let commandEditor = geometry[commandEditorAnchor]
                let keypad = geometry[keypadAnchor]
                let keyboardTop = keyboardMinY - geometry.frame(in: .global).minY
                let visibleBottom = min(geometry.size.height, keyboardTop)
                // MARK: - BM:🅱️ add your comments here
                // Temporary shared compact Files path: iPhone and iPad use this same
                // SoftEditorAccessoryBar view and the same beginSoftEditorFilesMenu action.
                // The expanded iPad row is intentionally omitted for this validation pass.
                let expanded = false
                // MARK: - BM:🅱️ add your comments here
                // Quick/Tools visibility is independent of the active editor. It must survive
                // Command/Button focus, colour-area interaction and anchor recomputation.
                let showBar = true
                let pickerHeight = max(0, min(keypad.maxY, visibleBottom) - max(0, keypad.minY))
                let pickerWidth = max(0, min(keypad.maxX, geometry.size.width) - max(0, keypad.minX))
                // MARK: - BM:🅱️ add your comments here
                // iPhone keeps the helper top position and bottom-anchors the added height
                // into the replacement area; iPad receives no height adjustment.
                let toolsHelperHeight = pickerHeight + (isPad ? 0 :
                    SoftEditorAccessoryConfiguration.iPhoneToolsHelperBottomHeightAdjustment +
                    SoftEditorAccessoryConfiguration.iPhoneToolsBottomGapAdjustment)

                if showBar {
                    SoftEditorAccessoryBar(
                        expanded: expanded,
                        showsCompact: true,
                        filesPanelWidth: pickerWidth,
                        defaultMIDIChannel: midiDefaultChannel,
                        midiNotePreviewTransport: softEditorMIDINotePreviewTransport,
                        midiControlChangeTestTransport: softEditorMIDIControlChangeTestTransport,
                        onAction: performSoftEditorAccessoryAction,
                        onFiles: beginSoftEditorFilesMenu,
                        onFileNameSelected: insertSoftEditorFileName,
                        onTimeCommandSelected: insertSoftEditorTimeCommand,
                        onMIDINoteInsert: insertSoftEditorMIDINoteCommand,
                        onMIDIControlChangeInsert: insertSoftEditorMIDIControlChangeCommand,
                        onDescriptionSelected: { smartCommandDescription = $0 },
                        onClear: clearSmartCommandText,
                        onOpen: { isSoftEditorAccessoryPaletteVisible.toggle() }
                    )
                    .frame(
                        width: SoftEditorAccessoryConfiguration.compactLauncherDimension * 2,
                        height: SoftEditorAccessoryConfiguration.compactLauncherDimension,
                        alignment: .leading
                    )
                    .position(
                        // MARK: - BM:🅱️ add your comments here
                        // The .commandEditor anchor keeps the button intentionally inside the Command panel at bottom-left.
                        x: commandEditor.minX + 44,
                        y: commandEditor.maxY - 22
                    )
                    // MARK: - BM:🅱️  Keep accessory controls above command-help hit testing.
                    .zIndex(100)
                }

                if isSoftEditorAccessoryPaletteVisible && showBar {
                    SoftEditorAccessoryPalette(
                        filesPanelWidth: pickerWidth,
                        defaultMIDIChannel: midiDefaultChannel,
                        midiNotePreviewTransport: softEditorMIDINotePreviewTransport,
                        midiControlChangeTestTransport: softEditorMIDIControlChangeTestTransport,
                        onAction: performSoftEditorAccessoryAction,
                        onFiles: beginSoftEditorFilesMenu,
                        onFileNameSelected: insertSoftEditorFileName,
                        onTimeCommandSelected: insertSoftEditorTimeCommand,
                        onMIDINoteInsert: insertSoftEditorMIDINoteCommand,
                        onMIDIControlChangeInsert: insertSoftEditorMIDIControlChangeCommand,
                        onDescriptionSelected: { smartCommandDescription = $0 },
                        onClose: { isSoftEditorAccessoryPaletteVisible = false },
                        bottomHeightAdjustment: isPad ? 0 : SoftEditorAccessoryConfiguration.iPhoneToolsHelperBottomHeightAdjustment
                    )
                    .frame(
                        width: pickerWidth,
                        height: toolsHelperHeight
                    )
                    .clipped()
                    .position(x: max(0, keypad.minX) + pickerWidth / 2,
                              y: max(0, keypad.minY) + toolsHelperHeight / 2)
                    .zIndex(101)
                }
            } else if editingSlotIndex != nil {
                // MARK: - BM:🅱️ Keep Quick/Tools visible while editor anchors are transiently unavailable.
                // This stable editor-region fallback is independent of the active Command/Button editor.
                let fallbackWidth = min(max(geometry.size.width - 16, 44), 420)
                let fallbackHeight = min(max(geometry.size.height - 16, 300), 520)
                SoftEditorAccessoryBar(
                    expanded: false,
                    showsCompact: true,
                    filesPanelWidth: fallbackWidth,
                    defaultMIDIChannel: midiDefaultChannel,
                    midiNotePreviewTransport: softEditorMIDINotePreviewTransport,
                    midiControlChangeTestTransport: softEditorMIDIControlChangeTestTransport,
                    onAction: performSoftEditorAccessoryAction,
                    onFiles: beginSoftEditorFilesMenu,
                    onFileNameSelected: insertSoftEditorFileName,
                    onTimeCommandSelected: insertSoftEditorTimeCommand,
                    onMIDINoteInsert: insertSoftEditorMIDINoteCommand,
                    onMIDIControlChangeInsert: insertSoftEditorMIDIControlChangeCommand,
                    onDescriptionSelected: { smartCommandDescription = $0 },
                    onClear: clearSmartCommandText,
                    onOpen: { isSoftEditorAccessoryPaletteVisible.toggle() }
                )
                .frame(
                    width: SoftEditorAccessoryConfiguration.compactLauncherDimension * 2,
                    height: SoftEditorAccessoryConfiguration.compactLauncherDimension
                )
                .position(x: 52, y: 30)
                .zIndex(100)

                if isSoftEditorAccessoryPaletteVisible {
                    SoftEditorAccessoryPalette(
                        filesPanelWidth: fallbackWidth,
                        defaultMIDIChannel: midiDefaultChannel,
                        midiNotePreviewTransport: softEditorMIDINotePreviewTransport,
                        midiControlChangeTestTransport: softEditorMIDIControlChangeTestTransport,
                        onAction: performSoftEditorAccessoryAction,
                        onFiles: beginSoftEditorFilesMenu,
                        onFileNameSelected: insertSoftEditorFileName,
                        onTimeCommandSelected: insertSoftEditorTimeCommand,
                        onMIDINoteInsert: insertSoftEditorMIDINoteCommand,
                        onMIDIControlChangeInsert: insertSoftEditorMIDIControlChangeCommand,
                        onDescriptionSelected: { smartCommandDescription = $0 },
                        onClose: { isSoftEditorAccessoryPaletteVisible = false },
                        bottomHeightAdjustment: isPad ? 0 : SoftEditorAccessoryConfiguration.iPhoneToolsHelperBottomHeightAdjustment
                    )
                    .frame(width: fallbackWidth, height: fallbackHeight)
                    .position(x: fallbackWidth / 2 + 8, y: fallbackHeight / 2 + 8)
                    .zIndex(101)
                }
            }
        }
    }

    private var softEditorMIDINotePreviewTransport: SoftEditorMIDINotePreviewTransport {
        SoftEditorMIDINotePreviewTransport(
            isAvailable: outputMode == .mac && macConnection.canSend,
            connectionSessionID: macConnection.midiSessionID,
            sendAuthenticatedCommand: { [macConnection, outputMode] command in
                guard outputMode == .mac, macConnection.canSend else { return false }
                return macConnection.sendAuthenticatedCommand(command)
            },
            showOutputUnavailableWarning: showSoftEditorMIDIOutputUnavailableWarning
        )
    }

    private var softEditorMIDIControlChangeTestTransport: SoftEditorMIDIControlChangeTestTransport {
        SoftEditorMIDIControlChangeTestTransport(
            isAvailable: outputMode == .mac && macConnection.canSend,
            sendAuthenticatedCommand: { [macConnection, outputMode] command in
                guard outputMode == .mac, macConnection.canSend else { return false }
                return macConnection.sendAuthenticatedCommand(command)
            },
            showOutputUnavailableWarning: showSoftEditorMIDIOutputUnavailableWarning
        )
    }

    private func performSoftEditorAccessoryAction(_ action: SoftEditorAccessoryAction) {
        guard let behavior = SoftEditorAccessoryConfiguration.behavior(for: action) else {
            return
        }

        switch behavior {
        case let .insertText(text):
            // Integration point: this helper reads the active editor's live selection and uses
            // the existing replacement/undo paths for command text or button-preview text.
            _ = insertSoftEditorAccessoryText(text)
        case .openPicker:
            // Files are opened by the accessory-bar-owned menu; this branch remains a safe
            // compatibility route for any future action configuration that uses the picker behavior.
            _ = beginSoftEditorFilesMenu()
        case let .revealTable(table):
            // Integration point: these routes deliberately use the existing editor tables rather
            // than introducing a second command source or changing the editor geometry.
            revealSoftEditorAccessoryTable(table)
        }
    }

    private func revealSoftEditorAccessoryTable(_ table: SoftEditorAccessoryTable) {
        switch table {
        case .timeDateCommands:
            isSmartEscapeCodeTableVisible = false
            smartCommandDescription = "**time/date command table**\n\nSelect a row to insert the syntax defined in the existing command table."
        case .widgets:
            isSmartEscapeCodeTableVisible = false
            smartCommandDescription = smartHelpCommandSwitchWidgets
        }
    }

    // MARK: - BM:🅱️ Capture the active editor before the local Files menu opens.
    private func beginSoftEditorFilesMenu() -> SoftEditorAccessoryInsertionContext? {
        // MARK: - BM:🅱️ add your comments here
        // textView.window is intentionally not required to open the local menu; final validation
        // in insertSoftEditorFileName verifies the window and captured target before insertion.
        guard let slot = editingSlotIndex,
              let textView = smartPasteTarget.textView else {
            return nil
        }

        return SoftEditorAccessoryInsertionContext(
            sessionID: softEditorAccessorySessionID,
            slot: slot,
            document: selectedDocumentName,
            editor: smartPasteTarget.editor,
            wasFirstResponder: textView.isFirstResponder
        )
    }

    // MARK: - BM:🅱️ Validate the local Files selection, restore the editor, and insert only its filename.
    private func insertSoftEditorFileName(
        _ filename: String,
        context: SoftEditorAccessoryInsertionContext
    ) -> Bool {
        guard context.slot == editingSlotIndex,
              context.document == selectedDocumentName,
              context.sessionID == softEditorAccessorySessionID,
              context.editor == smartPasteTarget.editor,
              let textView = smartPasteTarget.textView,
              textView.window != nil else {
            return false
        }

        // MARK: - BM:🅱️ add your comments here
        // Reacquire the current live UITextView for every file selection because SwiftUI may
        // recreate the editor view after focus, keyboard or layout changes. The retained context
        // validates the original slot/document only; the callback supplies a freshly captured
        // context for the current selection. The current editor and session therefore change
        // safely with intentional Command/Button switching while Files remains open.
        let liveText = textView.text ?? ""
        let liveSelection = textView.selectedRange
        let textLength = liveText.utf16.count
        guard liveSelection.location != NSNotFound,
              liveSelection.location >= 0,
              liveSelection.length >= 0,
              liveSelection.location <= textLength,
              liveSelection.length <= textLength - liveSelection.location else {
            return false
        }

        if context.wasFirstResponder && !textView.isFirstResponder {
            textView.becomeFirstResponder()
        }
        let currentEditor = smartPasteTarget.editor
        smartPasteTarget.activate(currentEditor, textView: textView)
        switch currentEditor {
        case .command:
            smartScriptEditingModel.setSelectionRange(liveSelection)
        case .button:
            smartButtonPreviewSelectionRange = liveSelection
        }
        return insertSoftEditorAccessoryText(filename)
    }

    // MARK: - BM:🅱️ Time reuses the validated Files insertion path for the active editor.
    private func insertSoftEditorTimeCommand(
        _ command: String,
        context: SoftEditorAccessoryInsertionContext
    ) -> Bool {
        insertSoftEditorFileName(command, context: context)
    }

    private func insertSoftEditorMIDINoteCommand(_ command: String) {
        guard let context = beginSoftEditorFilesMenu() else {
            return
        }

        _ = insertSoftEditorFileName(command, context: context)
    }

    private func insertSoftEditorMIDIControlChangeCommand(_ command: String) {
        guard let context = beginSoftEditorFilesMenu() else {
            return
        }

        _ = insertSoftEditorFileName(command, context: context)
    }

    private var softEditorAccessoryTargetText: String {
        switch smartPasteTarget.editor {
        case .command: smartScriptEditingModel.scriptText
        case .button: smartButtonEditablePreviewTextBinding.wrappedValue
        }
    }

    // MARK: - BM:🅱️ Read the live UTF-16 selection before using the existing model replacement paths.
    private func insertSoftEditorAccessoryText(_ text: String) -> Bool {
        guard editingSlotIndex != nil,
              let textView = smartPasteTarget.textView,
              textView.window != nil,
              textView.text == softEditorAccessoryTargetText else { return false }

        switch smartPasteTarget.editor {
        case .command:
            smartScriptEditingModel.setSelectionRange(textView.selectedRange)
            insertSmartActionTextAtSelection(text)
        case .button:
            smartButtonPreviewSelectionRange = textView.selectedRange
            insertSmartPreviewTextAtSelection(text)
        }
        return true
    }

    private func invalidateSoftEditorAccessorySession() {
        softEditorAccessorySessionID = UUID()
    }


    private func insertSmartActionTextAtSelection(_ insertedText: String) {
        smartScriptEditingModel.replaceSelection(with: editorSmartScriptText(fromStoredText: insertedText))
        smartActionTextBinding.wrappedValue = smartScriptEditingModel.scriptText
    }

    private var smartClipboardSelection: (text: String, range: NSRange)? {
        let text: String
        let storedRange: NSRange
        switch smartPasteTarget.editor {
        case .command:
            text = smartScriptEditingModel.scriptText
            storedRange = smartScriptEditingModel.selectionRange
        case .button:
            text = smartButtonEditablePreviewTextBinding.wrappedValue
            storedRange = smartButtonPreviewSelectionRange
        }
        let range = smartPasteTarget.textView.flatMap { view in
            view.text == text ? view.selectedRange : nil
        } ?? storedRange
        let nsText = text as NSString
        guard range.location != NSNotFound,
              range.location >= 0,
              range.length > 0,
              range.location <= nsText.length,
              range.length <= nsText.length - range.location,
              nsText.rangeOfComposedCharacterSequences(for: range) == range,
              let stringRange = Range(range, in: text) else {
            return nil
        }
        return (String(text[stringRange]), range)
    }

    private func copyOrCutSmartEditorSelection(isCut: Bool) {
        guard let selection = smartClipboardSelection else { return }
        if isCut {
            switch smartPasteTarget.editor {
            case .command:
                UIPasteboard.general.string = selection.text
                smartScriptEditingModel.setSelectionRange(selection.range)
                smartScriptEditingModel.replaceSelection(with: "")
                smartActionTextBinding.wrappedValue = smartScriptEditingModel.scriptText
            case .button:
                guard let textView = smartPasteTarget.textView,
                      textView.window != nil,
                      textView.text == smartButtonEditablePreviewTextBinding.wrappedValue,
                      textView.undoManager != nil else { return }
                textView.selectedRange = selection.range
                textView.cut(nil)
            }
        } else {
            UIPasteboard.general.string = selection.text
        }
        ButtonClickFeedback.playIfEnabled()
    }

    private func pasteSmartActionTextFromSystemClipboard() {
        guard let clipboardText = UIPasteboard.general.string, !clipboardText.isEmpty else {
            return
        }

        ButtonClickFeedback.playIfEnabled()
        switch smartPasteTarget.editor {
        case .command:
            if let textView = smartPasteTarget.textView,
               textView.text == smartScriptEditingModel.scriptText {
                smartScriptEditingModel.setSelectionRange(textView.selectedRange)
            }
            smartScriptEditingModel.replaceSelection(with: clipboardText)
            smartActionTextBinding.wrappedValue = smartScriptEditingModel.scriptText
        case .button:
            if let textView = smartPasteTarget.textView,
               textView.text == smartButtonEditablePreviewTextBinding.wrappedValue {
                smartButtonPreviewSelectionRange = textView.selectedRange
            }
            insertSmartPreviewTextAtSelection(clipboardText)
        }
    }

    private func toggleSmartModifierPrefix(_ prefix: String) {
        let orderedPrefixes = ["⌃", "⌥", "⇧", "⌘"]
        var actionText = smartActionTextBinding.wrappedValue
        let safeCursorLocation = min(max(smartScriptEditingModel.selectionRange.location, 0), actionText.utf16.count)
        let cursorRange = NSRange(location: safeCursorLocation, length: 0)
        let cursorIndex = Range(cursorRange, in: actionText)?.lowerBound ?? actionText.endIndex

        func isModifier(_ character: Character) -> Bool {
            orderedPrefixes.contains(String(character))
        }

        var groupStart = cursorIndex
        while groupStart > actionText.startIndex {
            let previousIndex = actionText.index(before: groupStart)
            guard isModifier(actionText[previousIndex]) else { break }
            groupStart = previousIndex
        }

        var groupEnd = cursorIndex
        while groupEnd < actionText.endIndex, isModifier(actionText[groupEnd]) {
            groupEnd = actionText.index(after: groupEnd)
        }

        var enabledPrefixes = Set(actionText[groupStart..<groupEnd].map { String($0) })
        if enabledPrefixes.contains(prefix) {
            enabledPrefixes.remove(prefix)
        } else {
            enabledPrefixes.insert(prefix)
        }

        let rebuiltGroup = orderedPrefixes
            .filter { enabledPrefixes.contains($0) }
            .joined()
        let replacementLocation = NSRange(groupStart..<groupStart, in: actionText).location
        actionText.replaceSubrange(groupStart..<groupEnd, with: rebuiltGroup)

        smartActionTextBinding.wrappedValue = actionText
        smartScriptEditingModel.setSelectionRange(NSRange(location: replacementLocation + rebuiltGroup.utf16.count, length: 0))
    }

    private func displayActionTextReplacingModifierCodes(_ actionText: String) -> String {
        let mappings = [("ctl:", "⌃"), ("op:", "⌥"), ("sh:", "⇧"), ("cm:", "⌘")]
        var remainingText = actionText
        var displayPrefixText = ""
        var didRemovePrefix = true

        while didRemovePrefix {
            didRemovePrefix = false
            for (commandPrefix, displayPrefix) in mappings where remainingText.hasPrefix(commandPrefix) {
                remainingText.removeFirst(commandPrefix.count)
                displayPrefixText += displayPrefix
                didRemovePrefix = true
                break
            }
        }

        return displayPrefixText + remainingText
    }

    func commandTextReplacingDisplayModifierSymbols(_ text: String) -> String {
        let components = text.components(separatedBy: "::")
        guard let actionText = components.first else {
            return text
        }

        var remainingText = actionText
        var commandPrefixText = ""
        let mappings = [("⌃", "ctl:"), ("⌥", "op:"), ("⇧", "sh:"), ("⌘", "cm:")]
        var didRemovePrefix = true

        while didRemovePrefix {
            didRemovePrefix = false
            for (displayPrefix, commandPrefix) in mappings where remainingText.hasPrefix(displayPrefix) {
                remainingText.removeFirst(displayPrefix.count)
                commandPrefixText += commandPrefix
                didRemovePrefix = true
                break
            }
        }

        let commandActionText = commandPrefixText + remainingText

        if components.count == 1 {
            return commandActionText
        }

        return ([commandActionText] + components.dropFirst()).joined(separator: "::")
    }

    private var smartSFSymbolGrid: some View {
        ScrollView(.vertical) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 4),
                spacing: 0
            ) {
                ForEach(Array(smartSFPanelSymbols.enumerated()), id: \.offset) { index, symbolName in
                    if index == 0 {
                        smartSFSymbolDeleteCell
                    } else {
                        smartSFSymbolCell(symbolName)
                    }
                }
            }
        }
    }

    private func smartIPhoneSFSymbolGrid(editorWidth: CGFloat) -> some View {
        smartIPhoneButtonSelectionGrid(editorWidth: editorWidth) {
            ForEach(Array(smartIPhoneSFPanelSymbols.enumerated()), id: \.offset) { index, symbolName in
                if index == 0 {
                    smartSFSymbolDeleteCell
                } else {
                    smartSFSymbolCell(symbolName)
                }
            }
        }
    }

    private var smartSFPanelControls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                smartSlotPositionLabel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                smartArrowButton(systemName: "arrow.left") {
                    selectPreviousEditableSlot()
                    // Help text location: SF panel left arrow.
                    smartCommandDescription = smartHelpSFArrows
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                smartArrowButton(systemName: "arrow.right") {
                    selectNextEditableSlot()
                    // Help text location: SF panel right arrow.
                    smartCommandDescription = smartHelpSFArrows
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 46)

            HStack(spacing: 0) {
                smartDeleteAllButton()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                smartControlButton("test", systemName: "play.fill", background: Color(red: 0.0, green: 0.5, blue: 0.0)) {
                    testEditingSlotText()
                    // Help text location: SF panel test button.
                    smartCommandDescription = smartHelpSFTestButton
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Test")
                smartControlButton("close", systemName: "xmark", background: Color.gray.opacity(0.45), iconWeight: .bold) {
                    saveSlotEditing()
                    cancelSlotEditing()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Close")
            }
            .frame(height: 46)
        }
    }

    private func smartDeleteAllButton(
        visibleHeight: CGFloat? = nil,
        visibleAlignment: Alignment = .center,
        probeTarget: EditorGeometryProbeTarget? = nil
    ) -> some View {
        smartControlButton(
            "Delete\nAll",
            systemName: "trash.fill",
            background: Color(hex: "8B3030"),
            fontSize: 15,
            lineLimit: 2,
            visibleHeight: visibleHeight,
            visibleAlignment: visibleAlignment,
            probeTarget: probeTarget
        ) {
            isDeleteAllButtonsConfirmationPresented = true
        }
        .accessibilityLabel("Delete All")
    }

    private func smartSFSymbolCell(_ symbolName: String) -> some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            setSmartButtonSFSymbol(symbolName)
        } label: {
            Image(systemName: symbolName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.yellow)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(Color.black)
                .overlay {
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbolName)
    }

	// MARK: - BM: sf symbol trash btn
    private var smartSFSymbolDeleteCell: some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            clearSmartButtonSFSymbol()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.red)
                 .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(Color.black)
                .overlay {
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove SF Symbol")
        .help("Remove SF Symbol")
    }

    private func clearSmartButtonSFSymbol() {
        let currentText = smartButtonTextBinding.wrappedValue
        let components = currentText.components(separatedBy: ":")
        let candidateName = components.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard components.count > 1,
              !candidateName.isEmpty,
              !candidateName.contains(where: \.isWhitespace),
              UIImage(systemName: candidateName) != nil else {
            return
        }

        smartButtonTextBinding.wrappedValue = components.dropFirst().joined(separator: ":")
    }

    @ViewBuilder
    private var smartSlotPositionLabel: some View {
        if let editingSlotIndex, visibleGridDimensions.columns > 0 {
            let column = (editingSlotIndex % visibleGridDimensions.columns) + 1
            let row = (editingSlotIndex / visibleGridDimensions.columns) + 1

            HStack(spacing: 0) {
                Text("\(column)")
                    .foregroundStyle(.green)
                Text(" : ")
                    .foregroundStyle(.white)
                Text("\(row)")
                    .foregroundStyle(.red)
            }
            .font(.system(size: 28, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.35)
            .allowsTightening(true)
            .padding(.horizontal, smartPositionIndicatorHorizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .overlay {
                Rectangle()
                    .stroke(Color.white, lineWidth: 1)
            }
        } else {
            Rectangle()
                .fill(Color.black)
                .overlay {
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1)
                }
        }
    }

    private func smartControlButton(
        _ title: String,
        systemName: String? = nil,
        foreground: Color = .white,
        background: Color = .black,
        fontSize: CGFloat = 22,
        iconWeight: Font.Weight = .semibold,
        lineLimit: Int = 1,
        visibleHeight: CGFloat? = nil,
        visibleAlignment: Alignment = .center,
        probeTarget: EditorGeometryProbeTarget? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            action()
        } label: {
            Group {
                if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 22, weight: iconWeight))
                } else {
                    Text(title)
                        .font(.system(size: fontSize, weight: .semibold))
                        .lineLimit(lineLimit)
                        .minimumScaleFactor(0.75)
                        .multilineTextAlignment(.center)
                }
            }
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(height: visibleHeight)
                .background(background)
                .overlay {
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1)
                }
                .optionalEditorGeometryProbe(probeTarget, isEnabled: debugEditorGeometry)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: visibleAlignment)
        }
        .buttonStyle(.plain)
    }

    private func smartArrowButton(
        systemName: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .overlay {
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func testEditingSlotText() {
        let normalizedEditingSlotText = commandTextReplacingDisplayModifierSymbols(editingSlotText)
        let actionText = normalizedEditingSlotText.components(separatedBy: "::").first ?? normalizedEditingSlotText
        let actionTokens = parsedActionTokens(from: actionText)

        if containsWaitCommand(in: actionTokens) {
            startWaitChainCommandTokens(
                actionTokens,
                respectsBluetoothMode: false
            )
            return
        }

        for actionToken in actionTokens {
            if isStopMediaCommandText(actionToken) {
                stopAllMainGridMedia()
            } else if let clipboardText = targetClipboardTextForSendText(actionToken) {
                UIPasteboard.general.string = clipboardText
            }
        }

        let bluetoothTokens = actionTokens
            .filter { actionToken in
                    targetDocumentNameForSendText(actionToken) == nil &&
                    targetURLForSendText(actionToken) == nil &&
                    targetShortcutURLForSendText(actionToken) == nil &&
                    targetSoundRequestForSendText(actionToken) == nil &&
                    targetSpokenTextForSendText(actionToken) == nil &&
                    targetSpokenFilenameForSendText(actionToken) == nil &&
                    targetAppURLForSendText(actionToken) == nil &&
                    targetClipboardTextForSendText(actionToken) == nil &&
                    targetPreviewFilenameForSendText(actionToken) == nil &&
                    !isStopMediaCommandText(actionToken) &&
                    !isWaitCommandText(actionToken.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) &&
                    targetWidgetDescriptorForSendText(actionToken) == nil
            }
            .map(normalizedBluetoothSendText)
        let targetSoundResult = actionTokens.compactMap(targetSoundRequestForSendText).first
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
        let targetSpokenFilename = actionTokens.compactMap(targetSpokenFilenameForSendText).first
        let targetSpokenText = actionTokens.compactMap(targetSpokenTextForSendText).first
        let targetShortcutURL = actionTokens.compactMap(targetShortcutURLForSendText).first

        guard sendKeyboardOutputTokens(
            bluetoothTokens,
            respectsButtonMode: false
        ) else {
            return
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
    }

    private func showSlotCopiedPopup() {
        alertTitle = ""
        renameAlertMessage = "Copied"
    }

    private func showSlotPastedPopup() {
        alertTitle = ""
        renameAlertMessage = "Pasted"
    }

    private func showSlotVisibilityPopup(isHidden: Bool) {
        alertTitle = ""
        renameAlertMessage = isHidden ? "btn will\nbe hidden" : "btn will\nbe visible"
    }

    private func showSlotSavedPopup() {
        alertTitle = ""
        renameAlertMessage = "btn hasbeen\naved to file"
    }

    var mainGridButtonSpacing: CGFloat {
        let buttonCount = max(visibleGridDimensions.columns * visibleGridDimensions.rows, 1)
        let normalizedProgress = min(max(CGFloat(buttonCount - 1) / CGFloat(144 - 1), 0), 1)
        return mainGridButtonSpacingMaximum - ((mainGridButtonSpacingMaximum - mainGridButtonSpacingMinimum) * normalizedProgress)
    }

    var mainGridButtonCornerRadius: CGFloat {
        let buttonCount = max(visibleGridDimensions.columns * visibleGridDimensions.rows, 1)
        let normalizedProgress = min(max(CGFloat(buttonCount - 1) / CGFloat(144 - 1), 0), 1)
        let resolvedRadius = mainGridButtonCornerRadiusMaximum - ((mainGridButtonCornerRadiusMaximum - mainGridButtonCornerRadiusMinimum) * normalizedProgress)
        return isPad ? resolvedRadius : resolvedRadius * 0.5
    }

    private func handleSelectedDocumentDisplayNameChange() {
        restorePersistedMainScreenModes()
        restoreVisibleGridState()
        cancelDocumentRename()
        isGridEditModeEnabled = false
        activeDragIndex = nil
        cancelSlotEditing()
    }

    private func showFilenameToastIfNeeded() {
        guard !isPad, !selectedDocumentName.isEmpty else { return }

        filenameToastDismissTask?.cancel()
        filenameToastText = selectedDocumentName
        filenameToastDismissTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                filenameToastText = nil
                filenameToastDismissTask = nil
            }
        }
    }

    private func handleDocumentNameFieldFocusChange() {
        guard isEditingDocumentName, !isDocumentNameFieldFocused else {
            return
        }

        cancelDocumentRename()
    }

    @MainActor
    private func observeKeyboardFrameChanges() async {
        let notificationCenter = NotificationCenter.default

        Task {
            for await _ in notificationCenter.notifications(named: UIResponder.keyboardWillHideNotification) {
                await MainActor.run {
                    keyboardMinY = .greatestFiniteMagnitude
                }
            }
        }

        for await notification in notificationCenter.notifications(named: UIResponder.keyboardWillChangeFrameNotification) {
            guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
                keyboardMinY = .greatestFiniteMagnitude
                continue
            }

            let screenBounds = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.screen.bounds ?? .zero
            let screenWidth = screenBounds.width
            let screenHeight = screenBounds.height
            let isFloatingKeyboard = screenWidth > 0 && (
                endFrame.width < (screenWidth * 0.9) ||
                endFrame.maxY < (screenHeight - 1)
            )

            if isFloatingKeyboard || (screenHeight > 0 && endFrame.minY >= screenHeight) {
                keyboardMinY = .greatestFiniteMagnitude
            } else {
                keyboardMinY = endFrame.minY
            }
        }
    }

    private func reloadSelectedDocumentIfAvailable() {
        guard let selectedDocumentURL = documentFiles.first(where: { $0.lastPathComponent == selectedDocumentName }) else {
            restoreVisibleGridState()
            return
        }

        loadFunctionKeys(selectedDocumentURL)
        restoreVisibleGridState()
    }

    func stopSpokenGridText() {
        speechPlaybackRequestID = UUID()
        speechSynthesisActive = false
        speechSynthesizer.stopSpeaking(at: .immediate)
        speechSynthesizer.delegate = nil
        speechPlaybackDelegate = nil
    }

    var isMediaOrWaitActive: Bool {
        ordinarySoundActive ||
            mainGridAmbientSoundState.isPlaybackActive ||
            speechSynthesisActive ||
            !activeWaitChainTasks.isEmpty
    }

    @ViewBuilder
    private func popupOverlay(
        isSlotEditorPresented: Bool,
        maskedScreenHeight: CGFloat
    ) -> some View {
        if let renameAlertMessage {
            let isSlotEditorTopPopup = isSlotEditorPresented && (
                alertTitle == "Bluetooth not connected" ||
                renameAlertMessage == "btn has been\nsaved to file"
            )

            VStack {
                if isSlotEditorTopPopup {
                    popupCard(message: renameAlertMessage)
                        .padding(.top, max(72, maskedScreenHeight * 0.18))
                } else if isSlotEditorPresented {
                    Spacer(minLength: 0)
                    popupCard(message: renameAlertMessage)
                } else {
                    Spacer()
                    popupCard(message: renameAlertMessage)
                }

                if isSlotEditorTopPopup {
                    Spacer(minLength: 0)
                } else if isSlotEditorPresented {
                    Spacer(minLength: max(32, maskedScreenHeight * 0.16))
                } else {
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
            .allowsHitTesting(false)
        }
    }

    private func popupCard(message: String) -> some View {
        VStack(spacing: 8) {
            if !alertTitle.isEmpty, alertTitle != "Alert" {
                Text(alertTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.black.opacity(0.88))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func filenameToastOverlay(availableWidth: CGFloat) -> some View {
        if !isPad, let filenameToastText {
            Text(filenameToastText)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: min(max(0, (availableWidth - 32) * 0.4489), 188.538))
                .background(Color.black.opacity(0.88))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.top, 48)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func mainGridOperationMessageOverlay(availableWidth: CGFloat) -> some View {
        if let mainGridOperationMessageText {
            let topPadding: CGFloat = !isPad && filenameToastText != nil ? 86 : 48

            Text(mainGridOperationMessageText)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: min(max(0, (availableWidth - 32) * 0.4489), 188.538))
                .background(Color.black.opacity(0.88))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.top, topPadding)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    private func schedulePopupDismissIfNeeded() {
        popupDismissTask?.cancel()

        guard renameAlertMessage != nil else {
            popupDismissTask = nil
            return
        }

        popupDismissTask = Task {
			// popup alert timeout
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                renameAlertMessage = nil
            }
        }
    }

    var minimumBoxFontSize: Double { 10 }

    var maximumBoxFontSize: Double { 200 }

	// MARK: - BM:😎 FUNCS handleEditDragEnded
    func handleEditDragEnded(
        from sourceIndex: Int,
        translation: CGSize,
        gridDimensions: (columns: Int, rows: Int)
    ) {
        defer {
            activeDragIndex = nil
        }

        guard isGridEditModeEnabled,
              editingSlotIndex == nil else {
            return
        }

        guard let targetIndex = targetIndexForEditDrag(
            from: sourceIndex,
            translation: translation,
            gridDimensions: gridDimensions
        ) else {
            return
        }

        let preservedActionMenuTarget = mainGridActionMenuTarget
        let sourceSpan = slotSpan(startingAt: sourceIndex, gridDimensions: gridDimensions)
        guard let finalAnchorIndex = moveFunctionKeySlot(sourceIndex, targetIndex, sourceSpan, gridDimensions) else {
            showMainGridActionMenuMessage("can't move btn")
            return
        }

        resetDirectionalDeleteState()
        if let preservedActionMenuTarget {
            mainGridActionMenuTarget = MainGridActionMenuTarget(
                index: finalAnchorIndex,
                buttonFrame: preservedActionMenuTarget.buttonFrame,
                gridDimensions: preservedActionMenuTarget.gridDimensions
            )
            beginPendingMovePopupRefresh(to: finalAnchorIndex)
        }
    }
}

// MARK: - BM:🅱️  ACCESSORY BAR CUSTOMISATION
// Keep all user-editable accessory-bar choices in this section. The view and action handler below
// should only consume these values; keeping the data here makes maintenance safe and predictable.
//
// permanentOrder controls the left-to-right order in both the expanded bar and More palette.
// labels and symbols control only the accessory-bar presentation and may be changed safely.
// compactVisible and expandedVisible control which actions appear in each existing layout.
// insertText values are inserted exactly as written; command syntax must match the ESP32 parser.
// behavior states whether the action inserts text, opens a picker, or reveals an existing table.
//
// To add another accessory-bar action: add one case to SoftEditorAccessoryAction, add its label and
// symbol here, add its behavior here, then add only its small routing branch in the handler below.
// To add a file category or extension: add one SoftEditorAccessoryFileCategory entry here. The file
// picker automatically filters regular Documents files and inserts only the filename with extension.
//
// MARK: - BM:🅱️  add your comments here
private enum SoftEditorAccessoryConfiguration {
    static let permanentOrder: [SoftEditorAccessoryAction] = [
        .filesAudio, .filesImage, .filesPDF, .filesTextMarkdown,
        .midiNote, .midiCC, .time
    ]

    static let labels: [SoftEditorAccessoryAction: String] = [
        .filesAudio: "Files: Audio", .filesImage: "Files: Image",
        .filesPDF: "Files: PDF", .filesTextMarkdown: "Files: Txt/MD",
        .midiNote: "Midi Note", .midiCC: "Midi CC", .time: "Time",
        .files: "Files", .wait: "Wait", .more: "More"
    ]

    static let symbols: [SoftEditorAccessoryAction: String] = [
        .filesAudio: "folder", .filesImage: "folder",
        .filesPDF: "folder", .filesTextMarkdown: "folder",
        .midiNote: "music.note", .midiCC: "slider.horizontal.3",
        .time: "clock", .files: "folder", .wait: "hourglass", .more: "list.bullet"
    ]

    static let timeDescription = """
**Time**

Select a Time command, then choose Local or City. Quick inserts `.date`, `.clock`, `.year`, `.month`, `.ord`, `.dow`, `.hour`, `.min`, or `.sec`.

Local inserts the command alone. A city appends its time-zone identifier, for example `.clock Asia/Tokyo`.
"""

    static let cityDescription = """
**City**

Choose local time or a listed city for the Time command selected previously. Local inserts the command without a time zone. A city appends its IANA identifier; for example, `.clock Asia/Tokyo`.

The selection applies only to the inserted command. It does not change the device time zone.
"""

    static func description(for action: SoftEditorAccessoryAction) -> String? {
        switch action {
        case .filesAudio:
            return """
**Files: Audio**

Select an audio file; Quick inserts its filename, including the extension.

**Playback:** `filename`, `snd filename`, or `snd filename 0...100`. Ordinary sound playback replaces the current ordinary sound. Use `.amb filename [0...100]` for the separate ambient-sound widget.

Audio files: `.mp3`, `.wav`, `.m4a`, `.aiff`, `.aac`, `.caf`.
"""
        case .filesImage:
            return """
**Files: Image**

Select an image file; Quick inserts its filename, including the extension. Enter a selected preview-supported filename by itself, for example `photo.png`, to open its preview.

The file list accepts `.png`, `.jpg`, `.jpeg`, `.heic`, `.heif`, `.gif`, `.bmp`, `.tiff`, and `.webp`. The current preview command recognizes `.png`, `.jpg`, `.jpeg`, `.gif`, `.heic`, and `.webp`.
"""
        case .filesPDF:
            return """
**Files: PDF**

Select a PDF; Quick inserts its filename. Enter the selected filename by itself, for example `manual.pdf`, to open the media preview.

PDF preview rendering supports a single-page PDF. The file list accepts `.pdf`.
"""
        case .filesTextMarkdown:
            return """
**Files: Txt/MD**

Select a text or Markdown file; Quick inserts its filename. The file list accepts `.txt`, `.md`, and `.markdown`.

Enter `notes.txt` or `notes.md` by itself to open a preview. `.spk notes.txt` speaks a text file, and `.rnd notes.txt` selects a random text-file line. `.markdown` is available for filename insertion; current preview recognition confirms `.txt` and `.md`.
"""
        case .midiNote:
            return """
**Midi Note**

**Syntax:** `.midi <note> [velocity] [channel] [toggle]`

Notes are 0...127. Note On velocity is 1...127 and defaults to 127. Channel defaults to the configured MIDI channel; an explicit channel is 1...16.

`.midi 60` and `.midi 60 120 1` are momentary: press sends Note On and release sends Note Off. `.midi 60 120 1 toggle` sends Note On on the first press and Note Off on the second.

**Note Off:** `.midi <note> off [channel]`, for example `.midi 60 off 1`, sends Note Off directly. MIDI requires Mac output and ESP Mac Helper.
"""
        case .midiCC:
            return """
**Midi CC**

Controllers are numeric 0...127 or supported named abbreviations. Start and End values are 0...127. An omitted channel uses the configured default; an explicit channel is 1...16.

**One-shot:** `.cc <controller> <start> [channel]` — `.cc vol 127` or `.cc 64 0` sends Start once.

**Hold:** `.cc <controller> <start> <end> [channel] hold` — `.cc vol 127 64 hold` sends Start on press and End on release.

**Toggle:** `.cc <controller> <start> <end> [channel] toggle` — `.cc mod 100 0 1 toggle` alternates Start and End. Thus `.cc 1 100 1 hold` means controller 1, Start 100, End 1, default channel. MIDI requires Mac output and ESP Mac Helper.
"""
        case .time:
            return timeDescription
        case .files, .wait, .more:
            return nil
        }
    }

    static let compactVisible: Set<SoftEditorAccessoryAction> = [
        .filesAudio, .filesImage, .filesPDF, .filesTextMarkdown,
        .midiNote, .midiCC, .time
    ]
    static let expandedVisible: Set<SoftEditorAccessoryAction> = [
        .filesAudio, .filesImage, .filesPDF, .filesTextMarkdown,
        .midiNote, .midiCC, .time
    ]

    // MARK: - BM:🅱️ add your comments here
    // Compact launcher styling only: 44 points matches the existing accessory/keypad buttons.
    static let compactLauncherDimension: CGFloat = 44
    static let compactLauncherColor: Color = .cyan
    static let compactLauncherBorderColor: Color = .white

    // MARK: - BM:🅱️ add your comments here
    // The Tools helper uses a solid white outer border. Only iPhone receives this
    // 16-point bottom adjustment so the panel fills the area it replaces; rows remain unchanged.
    static let toolsHelperBorderWidth: CGFloat = 1
    static let iPhoneToolsHelperBottomHeightAdjustment: CGFloat = 16

    // MARK: - BM:🅱️ add your comments here
    // USER-ADJUSTABLE: Extra iPhone Tools-helper height used to close the small bottom gap.
    // Increase or decrease this value in points if the device leaves a visible seam.
    static let iPhoneToolsBottomGapAdjustment: CGFloat = 4

    // MARK: - BM:🅱️ add your comments here
    // Files-menu height and internal padding are user-adjustable. Its width is supplied by
    // the owning compact Tools panel so the Files panel stays aligned and fully on-screen.
    static let filesMenuHeight: CGFloat = 340
    static let filesMenuContentPadding: CGFloat = 12

    static let insertionTemplates: [SoftEditorAccessoryAction: String] = [
        .wait: ".wait 5"
    ]

    // Time/Date uses the existing smartCommandRows table as the syntax source of truth.
    static let timeDateTableRoute: SoftEditorAccessoryTable = .timeDateCommands
    // More uses the existing widgets description/table route.
    static let moreTableRoute: SoftEditorAccessoryTable = .widgets

    static func behavior(for action: SoftEditorAccessoryAction) -> SoftEditorAccessoryBehavior? {
        switch action {
        case .wait:
            guard let text = insertionTemplates[action] else { return nil }
            return .insertText(text)
        case .midiNote, .midiCC:
            return nil
        case .time:
            return .revealTable(timeDateTableRoute)
        case .files, .filesAudio, .filesImage, .filesPDF, .filesTextMarkdown:
            return .openPicker(.files)
        case .more:
            return .revealTable(moreTableRoute)
        }
    }
}

// MARK: - BM:🅱️ ACCESSORY BAR FILES MENU
// These are the user-editable local Files menu categories and supported extensions.
// Add another category here; the local menu and Documents-first file catalog use it automatically.
private enum SoftEditorAccessoryFilesMenuConfiguration {
    // MARK: - BM:🅱️  add your comments here
    // Change titles and extensions safely when they match the files supplied by the app.
    static let categories: [SoftEditorAccessoryFileCategory] = [
        SoftEditorAccessoryFileCategory(id: "audio", title: "Audio", allowedExtensions: ["mp3", "wav", "m4a", "aiff", "aac", "caf"]),
        SoftEditorAccessoryFileCategory(id: "images", title: "Images", allowedExtensions: ["png", "jpg", "jpeg", "heic", "heif", "gif", "bmp", "tiff", "webp"]),
        SoftEditorAccessoryFileCategory(id: "pdfs", title: "PDFs", allowedExtensions: ["pdf"]),
        SoftEditorAccessoryFileCategory(id: "markdown", title: "Txt/MD", allowedExtensions: ["txt", "md", "markdown"])
    ]

    static func category(for action: SoftEditorAccessoryAction) -> SoftEditorAccessoryFileCategory? {
        guard let identifier = action.fileCategoryIdentifier else { return nil }
        return categories.first { $0.id == identifier }
    }
}

private final class SoftEditorAccessoryInsertionContext {
    let sessionID: UUID
    let slot: Int
    let document: String
    let editor: SmartEditorPasteTarget.Editor
    let wasFirstResponder: Bool

    init(sessionID: UUID, slot: Int, document: String,
         editor: SmartEditorPasteTarget.Editor, wasFirstResponder: Bool) {
        self.sessionID = sessionID
        self.slot = slot
        self.document = document
        self.editor = editor
        self.wasFirstResponder = wasFirstResponder
    }
}

private struct SoftEditorAccessoryFileCategory: Identifiable {
    let id: String
    let title: String
    let allowedExtensions: Set<String>
}

private enum SoftEditorAccessoryBehavior {
    case insertText(String)
    case openPicker(SoftEditorAccessoryPickerRoute)
    case revealTable(SoftEditorAccessoryTable)
}

private enum SoftEditorAccessoryPickerRoute {
    case files
}

private enum SoftEditorAccessoryTable {
    case timeDateCommands
    case widgets
}

// MARK: - BM:🅱️ Accessory overlays report bounds without changing the editor's layout proposal.
private enum SoftEditorAccessoryRegion: Hashable {
    case commandEditor
    case description
    case keypad
}

private struct SoftEditorAccessoryBounds: PreferenceKey {
    static var defaultValue: [SoftEditorAccessoryRegion: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [SoftEditorAccessoryRegion: Anchor<CGRect>],
        nextValue: () -> [SoftEditorAccessoryRegion: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private enum SoftEditorAccessoryAction: String, CaseIterable, Identifiable {
    case filesAudio, filesImage, filesPDF, filesTextMarkdown
    case midiNote, midiCC, time, files, wait, more
    var id: String { rawValue }

    var title: String {
        SoftEditorAccessoryConfiguration.labels[self] ?? rawValue.capitalized
    }

    var symbol: String {
        SoftEditorAccessoryConfiguration.symbols[self] ?? "questionmark"
    }

    var fileCategoryIdentifier: String? {
        switch self {
        case .filesAudio:
            return "audio"
        case .filesImage:
            return "images"
        case .filesPDF:
            return "pdfs"
        case .filesTextMarkdown:
            return "markdown"
        case .midiNote, .midiCC, .time, .files, .wait, .more:
            return nil
        }
    }
}

private enum SoftEditorMIDISelector {
    case note
    case controlChange

    init?(action: SoftEditorAccessoryAction) {
        switch action {
        case .midiNote:
            self = .note
        case .midiCC:
            self = .controlChange
        case .filesAudio, .filesImage, .filesPDF, .filesTextMarkdown,
             .time, .files, .wait, .more:
            return nil
        }
    }
}

private enum SoftEditorMIDIControlLayout {
    struct Dimensions {
        let labelWidth: CGFloat
        let controlWidth: CGFloat
    }

    static let preferredLabelWidth: CGFloat = 68
    static let minimumLabelWidth: CGFloat = 60
    static let labelControlSpacing: CGFloat = 4
    static let preferredControlWidth: CGFloat = 140
    static let preferredModeWidth: CGFloat = 120

    static func dimensions(for panelWidth: CGFloat) -> Dimensions {
        let contentWidth = max(
            0,
            panelWidth
                - (SoftEditorAccessoryConfiguration.filesMenuContentPadding * 2)
        )
        let labelWidth = min(
            preferredLabelWidth,
            max(
                minimumLabelWidth,
                contentWidth - labelControlSpacing - preferredControlWidth
            )
        )
        let controlWidth = max(
            0,
            min(
                preferredControlWidth,
                contentWidth - labelWidth - labelControlSpacing
            )
        )
        return Dimensions(
            labelWidth: labelWidth,
            controlWidth: controlWidth
        )
    }
}

private struct SoftEditorMIDILabelledControl<Control: View>: View {
    let label: String
    let dimensions: SoftEditorMIDIControlLayout.Dimensions
    let control: () -> Control

    init(
        label: String,
        dimensions: SoftEditorMIDIControlLayout.Dimensions,
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.label = label
        self.dimensions = dimensions
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: SoftEditorMIDIControlLayout.labelControlSpacing) {
            Text(label)
                .lineLimit(1)
                .frame(width: dimensions.labelWidth, alignment: .trailing)

            control()
                .frame(width: dimensions.controlWidth, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct SoftEditorMIDIMenuLabel: View {
    let value: String
    let width: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            Text(value)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
        }
        .frame(width: width, alignment: .leading)
        .foregroundStyle(.tint)
    }
}

private struct SoftEditorMIDINumericSelector: View {
    @Binding private var value: Int
    private let controlWidth: CGFloat
    private let presets: [Int]

    init(
        value: Binding<Int>,
        controlWidth: CGFloat,
        presets: [Int]
    ) {
        _value = value
        self.controlWidth = controlWidth
        self.presets = presets
    }

    var body: some View {
        Menu {
            ForEach(presets, id: \.self) { preset in
                Button("\(preset)") {
                    value = preset
                }
            }
        } label: {
            SoftEditorMIDIMenuLabel(value: "\(value)", width: controlWidth)
        }
        .accessibilityLabel("Value")
        .accessibilityValue("\(value)")
    }
}
private struct ManualMIDINotePlayControl: UIViewRepresentable {
    let onTouchDown: () -> Void
    let onTouchEnd: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTouchDown: onTouchDown, onTouchEnd: onTouchEnd)
    }

    func makeUIView(context: Context) -> UIButton {
        var configuration = UIButton.Configuration.gray()
        configuration.title = "Play"
        configuration.image = UIImage(systemName: "pianokeys.inverse")
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 4
        configuration.baseForegroundColor = .white
        configuration.background.backgroundColor = UIColor(white: 0.22, alpha: 1)
        configuration.background.cornerRadius = 6

        let button = UIButton(type: .system)
        button.configuration = configuration
        button.titleLabel?.font = .preferredFont(forTextStyle: .body)
        button.accessibilityLabel = "Play MIDI note while held"
        button.addTarget(context.coordinator, action: #selector(Coordinator.touchDown), for: .touchDown)
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.touchEnded),
            for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit]
        )
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {
        context.coordinator.onTouchDown = onTouchDown
        context.coordinator.onTouchEnd = onTouchEnd
    }

    static func dismantleUIView(_ uiView: UIButton, coordinator: Coordinator) {
        coordinator.touchEnded()
    }

    final class Coordinator: NSObject {
        var onTouchDown: () -> Void
        var onTouchEnd: () -> Void

        init(onTouchDown: @escaping () -> Void, onTouchEnd: @escaping () -> Void) {
            self.onTouchDown = onTouchDown
            self.onTouchEnd = onTouchEnd
        }

        @objc func touchDown() {
            onTouchDown()
        }

        @objc func touchEnded() {
            onTouchEnd()
        }
    }
}

private struct SoftEditorMIDINotePreviewTransport {
    let isAvailable: Bool
    let connectionSessionID: UUID
    let sendAuthenticatedCommand: (String) -> Bool
    let showOutputUnavailableWarning: () -> Void
}

private struct SoftEditorMIDIControlChangeTestTransport {
    let isAvailable: Bool
    let sendAuthenticatedCommand: (String) -> Bool
    let showOutputUnavailableWarning: () -> Void
}

@MainActor
@Observable
private final class SoftEditorMIDINotePreview {
    private struct ActiveNote {
        let id = UUID()
        let note: UInt8
        let channel: UInt8
        let connectionSessionID: UUID
    }

    var isEnabled = false
    private var activeNote: ActiveNote?
    private var activeManualNote: ActiveNote?
    private var releaseTask: Task<Void, Never>?

    func enable() {
        isEnabled = true
    }

    func disablePreview(using transport: SoftEditorMIDINotePreviewTransport) {
        isEnabled = false
        stopActivePreview(using: transport)
    }

    func reset(using transport: SoftEditorMIDINotePreviewTransport) {
        isEnabled = false
        stopActivePreview(using: transport)
        stopManualPlay(using: transport)
    }

    func trigger(
        note: Int?,
        velocity: Int,
        channel: Int,
        using transport: SoftEditorMIDINotePreviewTransport
    ) {
        guard activeManualNote == nil else { return }
        stopActivePreview(using: transport)

        guard isEnabled,
              let note,
              (0...127).contains(note),
              (1...127).contains(velocity),
              MIDIChannelSettings.validRange.contains(channel) else {
            return
        }

        guard transport.isAvailable else {
            isEnabled = false
            return
        }

        let noteValue = UInt8(note)
        let velocityValue = UInt8(velocity)
        let channelValue = UInt8(channel)
        let connectionSessionID = transport.connectionSessionID
        guard transport.sendAuthenticatedCommand(
            "MIDI:NOTE_ON:\(noteValue):\(velocityValue):\(channelValue)"
        ) else {
            isEnabled = false
            transport.showOutputUnavailableWarning()
            return
        }

        let activeNote = ActiveNote(
            note: noteValue,
            channel: channelValue,
            connectionSessionID: connectionSessionID
        )
        self.activeNote = activeNote
        releaseTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            self?.releasePreview(activeNote, using: transport)
        }
    }

    func handleTransportChange(using transport: SoftEditorMIDINotePreviewTransport) {
        isEnabled = false
        stopActivePreview(using: transport)
        stopManualPlay(using: transport)
    }

    func startManualPlay(
        note: Int?,
        velocity: Int,
        channel: Int,
        using transport: SoftEditorMIDINotePreviewTransport
    ) {
        guard activeManualNote == nil else { return }
        stopActivePreview(using: transport)

        guard transport.isAvailable else {
            transport.showOutputUnavailableWarning()
            return
        }

        guard let note,
              (0...127).contains(note),
              (1...127).contains(velocity),
              MIDIChannelSettings.validRange.contains(channel) else {
            return
        }

        let noteValue = UInt8(note)
        let velocityValue = UInt8(velocity)
        let channelValue = UInt8(channel)
        let connectionSessionID = transport.connectionSessionID
        guard transport.sendAuthenticatedCommand(
            "MIDI:NOTE_ON:\(noteValue):\(velocityValue):\(channelValue)"
        ) else {
            transport.showOutputUnavailableWarning()
            return
        }

        activeManualNote = ActiveNote(
            note: noteValue,
            channel: channelValue,
            connectionSessionID: connectionSessionID
        )
    }

    func stopManualPlay(using transport: SoftEditorMIDINotePreviewTransport) {
        guard let activeManualNote else { return }
        self.activeManualNote = nil

        guard transport.isAvailable,
              activeManualNote.connectionSessionID == transport.connectionSessionID else {
            return
        }

        _ = transport.sendAuthenticatedCommand(
            "MIDI:NOTE_OFF:\(activeManualNote.note):\(activeManualNote.channel)"
        )
    }

    private func releasePreview(_ note: ActiveNote, using transport: SoftEditorMIDINotePreviewTransport) {
        guard activeNote?.id == note.id else { return }
        releaseTask = nil
        activeNote = nil

        guard transport.isAvailable,
              note.connectionSessionID == transport.connectionSessionID else {
            return
        }

        _ = transport.sendAuthenticatedCommand(
            "MIDI:NOTE_OFF:\(note.note):\(note.channel)"
        )
    }

    private func stopActivePreview(using transport: SoftEditorMIDINotePreviewTransport) {
        releaseTask?.cancel()
        releaseTask = nil
        guard let activeNote else { return }
        self.activeNote = nil

        guard transport.isAvailable,
              activeNote.connectionSessionID == transport.connectionSessionID else {
            return
        }

        _ = transport.sendAuthenticatedCommand(
            "MIDI:NOTE_OFF:\(activeNote.note):\(activeNote.channel)"
        )
    }
}

// MARK: - BM:🟥 Soft Editor MIDI NOTE VIEW
private struct SoftEditorMIDINoteMenu: View {
    private static let notes = [
        "C", "C#", "D", "D#", "E", "F",
        "F#", "G", "G#", "A", "A#", "B"
    ]

    let defaultChannel: Int
    let previewTransport: SoftEditorMIDINotePreviewTransport
    let onClose: () -> Void
    let onInsert: (String) -> Void
    @State private var selectedNote: String
    @State private var selectedOctave: Int
    @State private var velocity: Int
    @State private var channel: Int
    @State private var isToggleEnabled: Bool
    @State private var notePreview = SoftEditorMIDINotePreview()

    init(
        defaultChannel: Int,
        previewTransport: SoftEditorMIDINotePreviewTransport,
        onClose: @escaping () -> Void,
        onInsert: @escaping (String) -> Void
    ) {
        let resolvedChannel = MIDIChannelSettings.validRange.contains(defaultChannel)
            ? defaultChannel
            : MIDIChannelSettings.defaultChannel
        self.defaultChannel = resolvedChannel
        self.previewTransport = previewTransport
        self.onClose = onClose
        self.onInsert = onInsert
        _selectedNote = State(initialValue: "C")
        _selectedOctave = State(initialValue: 3)
        _velocity = State(initialValue: 127)
        _channel = State(initialValue: resolvedChannel)
        _isToggleEnabled = State(initialValue: true)
    }

    var body: some View {
        GeometryReader { proxy in
            selectorContent(
                dimensions: SoftEditorMIDIControlLayout.dimensions(for: proxy.size.width)
            )
        }
        .onAppear {
            notePreview.reset(using: previewTransport)
        }
        .onChange(of: selectedNote) {
            triggerNotePreview()
        }
        .onChange(of: selectedOctave) {
            triggerNotePreview()
        }
        .onChange(of: velocity) {
            triggerNotePreview()
        }
        .onChange(of: channel) {
            triggerNotePreview()
        }
        .onChange(of: previewTransport.isAvailable) {
            guard !previewTransport.isAvailable else { return }
            notePreview.handleTransportChange(using: previewTransport)
        }
        .onChange(of: previewTransport.connectionSessionID) {
            notePreview.handleTransportChange(using: previewTransport)
        }
        .onDisappear {
            notePreview.reset(using: previewTransport)
        }
    }

    private func selectorContent(
        dimensions: SoftEditorMIDIControlLayout.Dimensions
    ) -> some View {
        VStack(spacing: 0) {
            header(title: "Note")

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SoftEditorMIDILabelledControl(label: "note", dimensions: dimensions) {
                        Menu {
                            ForEach(Self.notes, id: \.self) { note in
                                Button(note) {
                                    selectedNote = note
                                }
                            }
                        } label: {
                            SoftEditorMIDIMenuLabel(value: selectedNote, width: dimensions.controlWidth)
                        }
                        .accessibilityLabel("note")
                        .accessibilityValue(selectedNote)
                    }

                    SoftEditorMIDILabelledControl(label: "oct", dimensions: dimensions) {
                        Menu {
                            ForEach(0...8, id: \.self) { octave in
                                Button("\(octave)") {
                                    selectedOctave = octave
                                }
                            }
                        } label: {
                            SoftEditorMIDIMenuLabel(value: "\(selectedOctave)", width: dimensions.controlWidth)
                        }
                        .accessibilityLabel("oct")
                        .accessibilityValue("\(selectedOctave)")
                    }

                    SoftEditorMIDILabelledControl(label: "vol", dimensions: dimensions) {
                        SoftEditorMIDINumericSelector(
                            value: $velocity,
                            controlWidth: dimensions.controlWidth,
                            presets: [0, 16, 32, 48, 64, 80, 96, 112, 127]
                        )
                    }

                    SoftEditorMIDILabelledControl(label: "ch", dimensions: dimensions) {
                        Menu {
                            ForEach(MIDIChannelSettings.validRange, id: \.self) { item in
                                Button(channelTitle(for: item)) {
                                    channel = item
                                }
                            }
                        } label: {
                            SoftEditorMIDIMenuLabel(value: channelTitle(for: channel), width: dimensions.controlWidth)
                        }
                        .accessibilityLabel("ch")
                        .accessibilityValue(channelTitle(for: channel))
                    }

                    SoftEditorMIDILabelledControl(label: "toggle", dimensions: dimensions) {
                        Button {
                            isToggleEnabled.toggle()
                        } label: {
                            Image(systemName: isToggleEnabled ? "checkmark.square.fill" : "square")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("toggle")
                        .accessibilityValue(isToggleEnabled ? "On" : "Off")
                    }

                }
                .padding(.vertical, SoftEditorAccessoryConfiguration.filesMenuContentPadding)
            }

            actionButtons
                .padding(.bottom, 22)
        }
        .padding(.horizontal, SoftEditorAccessoryConfiguration.filesMenuContentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .background(Color(white: 0.12))
    }

    private func header(title: String) -> some View {
        HStack {
            Button(action: closeMenu) {
                Image(systemName: "house")
                    .frame(width: 44, height: 44)
                    .foregroundStyle(.cyan)
            }
            .accessibilityLabel("Exit \(title)")

            Spacer(minLength: 0)
            Text(title).foregroundStyle(.cyan)
            Spacer(minLength: 0)
            Color.clear.frame(width: 44, height: 44)
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button(action: toggleNotePreview) {
                    Image(systemName: "poweroutlet.type.k")
                        .foregroundStyle(notePreview.isEnabled ? Color.green : Color.gray)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel(notePreview.isEnabled ? "MIDI note preview enabled" : "MIDI note preview disabled")

                manualPlayButton
                    .frame(maxWidth: .infinity)
            }

            Button {
                if let midiCommand {
                    onInsert(midiCommand)
                }
            } label: {
                Text("insert MIDI")
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity)
            }
                .disabled(midiCommand == nil)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 8)
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 6))
        .tint(.gray)
    }

    private var manualPlayButton: some View {
        ManualMIDINotePlayControl(
            onTouchDown: beginManualPlay,
            onTouchEnd: endManualPlay
        )
        .frame(height: 32)
        .accessibilityLabel("Play MIDI note while held")
    }

    private func channelTitle(for item: Int) -> String {
        item == defaultChannel ? "(\(item))" : "\(item)"
    }

    private func toggleNotePreview() {
        if notePreview.isEnabled {
            notePreview.disablePreview(using: previewTransport)
        } else if !previewTransport.isAvailable {
            previewTransport.showOutputUnavailableWarning()
        } else {
            notePreview.enable()
        }
    }

    private func triggerNotePreview() {
        notePreview.trigger(
            note: midiNoteNumber,
            velocity: velocity,
            channel: channel,
            using: previewTransport
        )
    }

    private func beginManualPlay() {
        notePreview.startManualPlay(
            note: midiNoteNumber,
            velocity: velocity,
            channel: channel,
            using: previewTransport
        )
    }

    private func endManualPlay() {
        notePreview.stopManualPlay(using: previewTransport)
    }

    private func closeMenu() {
        notePreview.reset(using: previewTransport)
        onClose()
    }

    private var midiNoteNumber: Int? {
        guard let noteIndex = Self.notes.firstIndex(of: selectedNote) else {
            return nil
        }

        let noteNumber = (selectedOctave + 2) * 12 + noteIndex
        return (0...127).contains(noteNumber) ? noteNumber : nil
    }

    private var midiCommand: String? {
        guard let midiNoteNumber else {
            return nil
        }

        var components = [".midi", "\(midiNoteNumber)"]
        if velocity == 0 {
            components.append("off")
            if channel != defaultChannel {
                components.append("\(channel)")
            }
            return components.joined(separator: " ")
        }

        components.append("\(velocity)")
        if channel != defaultChannel {
            components.append("\(channel)")
        }
        if isToggleEnabled {
            components.append("toggle")
        }
        return components.joined(separator: " ")
    }
}

private struct SoftEditorMIDIControlChangeMenu: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case one = "one"
        case hold = "hold"
        case toggle = "tog"

        var id: String { rawValue }
    }

    private struct NamedController: Identifiable {
        let abbreviation: String
        let displayName: String

        var id: String { abbreviation }
    }

    private static let namedControllerDisplayNames: [String: String] = [
        "alloff": "All Notes Off",
        "sndoff": "All Sound Off",
        "attack": "Attack Time",
        "bal": "Balance",
        "bank": "Bank Select",
        "breath": "Breath Controller",
        "bright": "Brightness",
        "vol": "Channel Volume",
        "chorus": "Chorus Depth",
        "dec": "Data Decrement",
        "data": "Data Entry",
        "inc": "Data Increment",
        "decay": "Decay Time",
        "effect1": "Effect Control 1",
        "effect2": "Effect Control 2",
        "expr": "Expression",
        "foot": "Foot Controller",
        "gp1": "General Purpose 1",
        "gp2": "General Purpose 2",
        "gp3": "General Purpose 3",
        "gp4": "General Purpose 4",
        "gp5": "General Purpose 5",
        "gp6": "General Purpose 6",
        "gp7": "General Purpose 7",
        "gp8": "General Purpose 8",
        "hold2": "Hold 2",
        "legato": "Legato Footswitch",
        "local": "Local Control",
        "mod": "Modulation",
        "mono": "Mono Mode On",
        "omnioff": "Omni Mode Off",
        "omnion": "Omni Mode On",
        "pan": "Pan",
        "poly": "Poly Mode On",
        "portctl": "Portamento Control",
        "portsw": "Portamento Switch",
        "porttime": "Portamento Time",
        "release": "Release Time",
        "reset": "Reset All Controllers",
        "reverb": "Reverb Depth",
        "rpnlsb": "RPN LSB",
        "rpnmsb": "RPN MSB",
        "soft": "Soft Pedal",
        "sostenuto": "Sostenuto",
        "variation": "Sound Variation",
        "sus": "Sustain Pedal",
        "timbre": "Timbre / Harmonic Intensity",
        "trem": "Tremolo Depth",
        "vibdelay": "Vibrato Delay",
        "vibdepth": "Vibrato Depth",
        "vibrate": "Vibrato Rate"
    ]

    private static let namedControllers = namedControllerDisplayNames.compactMap { abbreviation, displayName in
        MIDIControlChangeCommand.controllerNumbersByAbbreviation[abbreviation].map { _ in
            NamedController(abbreviation: abbreviation, displayName: displayName)
        }
    }
    .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

    let defaultChannel: Int
    let testTransport: SoftEditorMIDIControlChangeTestTransport
    let onClose: () -> Void
    let onInsert: (String) -> Void
    @State private var controller: Int
    @State private var startValue: Int
    @State private var endValue: Int
    @State private var channel: Int
    @State private var mode: Mode
    @State private var selectedTypeAbbreviation: String?

    init(
        defaultChannel: Int,
        testTransport: SoftEditorMIDIControlChangeTestTransport,
        onClose: @escaping () -> Void,
        onInsert: @escaping (String) -> Void
    ) {
        let resolvedChannel = MIDIChannelSettings.validRange.contains(defaultChannel)
            ? defaultChannel
            : MIDIChannelSettings.defaultChannel
        self.defaultChannel = resolvedChannel
        self.testTransport = testTransport
        self.onClose = onClose
        self.onInsert = onInsert
        _controller = State(initialValue: 0)
        _startValue = State(initialValue: 127)
        _endValue = State(initialValue: 0)
        _channel = State(initialValue: resolvedChannel)
        _mode = State(initialValue: .one)
        _selectedTypeAbbreviation = State(initialValue: "bank")
    }

    var body: some View {
        GeometryReader { proxy in
            selectorContent(
                dimensions: SoftEditorMIDIControlLayout.dimensions(for: proxy.size.width)
            )
        }
    }

    private func selectorContent(
        dimensions: SoftEditorMIDIControlLayout.Dimensions
    ) -> some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    typeSelector

                    SoftEditorMIDILabelledControl(label: "start", dimensions: dimensions) {
                        SoftEditorMIDINumericSelector(
                            value: $startValue,
                            controlWidth: dimensions.controlWidth,
                            presets: [0, 16, 32, 48, 64, 80, 96, 112, 127]
                        )
                    }

                    SoftEditorMIDILabelledControl(label: "end", dimensions: dimensions) {
                        SoftEditorMIDINumericSelector(
                            value: $endValue,
                            controlWidth: dimensions.controlWidth,
                            presets: [0, 16, 32, 48, 64, 80, 96, 112, 127]
                        )
                        .disabled(isEndDisabled)
                    }
                    .grayscale(isEndDisabled ? 1 : 0)
                    .opacity(isEndDisabled ? 0.45 : 1)

                    SoftEditorMIDILabelledControl(label: "ch", dimensions: dimensions) {
                        Menu {
                            ForEach(MIDIChannelSettings.validRange, id: \.self) { item in
                                Button(channelTitle(for: item)) {
                                    channel = item
                                }
                            }
                        } label: {
                            SoftEditorMIDIMenuLabel(
                                value: channelTitle(for: channel),
                                width: dimensions.controlWidth
                            )
                        }
                        .accessibilityLabel("ch")
                        .accessibilityValue(channelTitle(for: channel))
                    }

                    if !isSpecialController {
                        Picker("mode", selection: $mode) {
                            ForEach(Mode.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .clipShape(.rect(cornerRadius: 6))
                        .frame(maxWidth: .infinity)
                    }

                }
                .padding(.vertical, SoftEditorAccessoryConfiguration.filesMenuContentPadding)
            }

            actionButtons
                .padding(.bottom, 22)
        }
        .padding(.horizontal, SoftEditorAccessoryConfiguration.filesMenuContentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .background(Color(white: 0.12))
    }

    private var header: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "house")
                    .frame(width: 44, height: 44)
                    .foregroundStyle(.cyan)
            }
            .accessibilityLabel("Exit MIDI CC")

            Spacer(minLength: 0)
            Text("CC").foregroundStyle(.cyan)
            Spacer(minLength: 0)
            Color.clear.frame(width: 44, height: 44)
        }
    }

    private var isSpecialController: Bool {
        [120, 121, 123].contains(controller)
    }

    private var effectiveMode: Mode {
        isSpecialController ? .one : mode
    }

    private var isEndDisabled: Bool {
        effectiveMode == .one
    }

    private var midiCommand: String? {
        guard let commandType,
              (0...127).contains(startValue),
              (0...127).contains(endValue),
              MIDIChannelSettings.validRange.contains(channel) else {
            return nil
        }

        var components = [".cc", commandType, "\(startValue)"]
        switch effectiveMode {
        case .one:
            if channel != defaultChannel {
                components.append("\(channel)")
            }
        case .hold, .toggle:
            components.append("\(endValue)")
            if channel != defaultChannel {
                components.append("\(channel)")
            }
            components.append(effectiveMode == .hold ? "hold" : "toggle")
        }
        return components.joined(separator: " ")
    }

    private var commandType: String? {
        if let selectedTypeAbbreviation {
            return MIDIControlChangeCommand.controllerNumbersByAbbreviation[selectedTypeAbbreviation] == nil
                ? nil
                : selectedTypeAbbreviation
        }
        return (0...127).contains(controller) ? "\(controller)" : nil
    }

    @ViewBuilder
    private var typeSelector: some View {
        if selectedTypeAbbreviation == nil {
            HStack(spacing: 20) {
                typeMenu(expandsToFill: false)

                Menu {
                    ForEach(0...127, id: \.self) { number in
                        Button("\(number)") {
                            controller = number
                        }
                    }
                } label: {
                    typeMenuLabel("\(controller)", expandsToFill: false)
                }
                .accessibilityLabel("CC number")
                .accessibilityValue("\(controller)")
            }
            .frame(maxWidth: .infinity, alignment: .center)
        } else {
            typeMenu(expandsToFill: false)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func typeMenu(expandsToFill: Bool) -> some View {
        Menu {
            ForEach(Self.namedControllers) { option in
                Button(option.displayName) {
                    selectNamedController(option)
                }
            }

            Button("NUM") {
                selectedTypeAbbreviation = nil
            }
        } label: {
            typeMenuLabel(typeTitle, expandsToFill: expandsToFill)
        }
        .accessibilityLabel("type")
        .accessibilityValue(typeTitle)
    }

    private func typeMenuLabel(_ value: String, expandsToFill: Bool) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
        }
        .frame(maxWidth: expandsToFill ? .infinity : nil, alignment: .leading)
        .fixedSize(horizontal: !expandsToFill, vertical: false)
        .foregroundStyle(.tint)
    }

    private var typeTitle: String {
        guard let selectedTypeAbbreviation,
              let option = Self.namedControllers.first(where: { $0.abbreviation == selectedTypeAbbreviation }) else {
            return "NUM"
        }
        return option.abbreviation
    }

    private func selectNamedController(_ option: NamedController) {
        guard let number = MIDIControlChangeCommand.controllerNumbersByAbbreviation[option.abbreviation] else {
            return
        }
        selectedTypeAbbreviation = option.abbreviation
        controller = Int(number)
    }

    private var actionButtons: some View {
        VStack(spacing: 8) {
            Button(action: sendControlChangeTest) {
                HStack(spacing: 4) {
                    Text("test")
                    Image(systemName: "poweroutlet.type.k")
                }
                .lineLimit(1)
                .foregroundStyle(isTestEnabled ? Color.white : Color.gray)
                .frame(maxWidth: .infinity)
            }
                .disabled(!isTestEnabled)
                .frame(maxWidth: .infinity)

            Button {
                if let midiCommand {
                    onInsert(midiCommand)
                }
            } label: {
                Text("insert MIDI")
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity)
            }
                .disabled(midiCommand == nil)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 8)
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 6))
        .tint(.gray)
    }

    private var isTestEnabled: Bool {
        mode == .one
    }

    private var testControllerNumber: Int? {
        if let selectedTypeAbbreviation,
           let number = MIDIControlChangeCommand.controllerNumbersByAbbreviation[selectedTypeAbbreviation] {
            return Int(number)
        }
        return (0...127).contains(controller) ? controller : nil
    }

    private func sendControlChangeTest() {
        guard isTestEnabled else { return }

        guard testTransport.isAvailable else {
            testTransport.showOutputUnavailableWarning()
            return
        }

        guard
              let controller = testControllerNumber,
              (0...127).contains(startValue),
              MIDIChannelSettings.validRange.contains(channel) else {
            return
        }

        _ = testTransport.sendAuthenticatedCommand(
            "MIDI:CC:\(controller):\(startValue):\(channel)"
        )
    }

    private func channelTitle(for item: Int) -> String {
        item == defaultChannel ? "(\(item))" : "\(item)"
    }
}

private struct SoftEditorAccessoryBar: View {
    let expanded: Bool
    let showsCompact: Bool
    let filesPanelWidth: CGFloat
    let defaultMIDIChannel: Int
    let midiNotePreviewTransport: SoftEditorMIDINotePreviewTransport
    let midiControlChangeTestTransport: SoftEditorMIDIControlChangeTestTransport
    let onAction: (SoftEditorAccessoryAction) -> Void
    let onFiles: () -> SoftEditorAccessoryInsertionContext?
    let onFileNameSelected: (String, SoftEditorAccessoryInsertionContext) -> Bool
    let onTimeCommandSelected: (String, SoftEditorAccessoryInsertionContext) -> Bool
    let onMIDINoteInsert: (String) -> Void
    let onMIDIControlChangeInsert: (String) -> Void
    let onDescriptionSelected: (String) -> Void
    let onClear: () -> Void
    let onOpen: () -> Void
    @State private var filesInsertionContext: SoftEditorAccessoryInsertionContext?
    // MARK: - BM:🅱️ add your comments here
    // Files presentation is intentionally local to this accessory-bar view; this Boolean
    // controls the real category and file-list panel without MainScreen presentation state.
    @State private var showFilesMenu = false
    @State private var initialFilesCategory: SoftEditorAccessoryFileCategory?
    // MARK: - BM:🅱️ Time presentation remains local to the accessory bar, like Files.
    @State private var showTimeMenu = false
    @State private var timeInsertionContext: SoftEditorAccessoryInsertionContext?
    @State private var midiSelector: SoftEditorMIDISelector?

    var body: some View {
        ZStack {
            if expanded {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) {
                        ForEach(SoftEditorAccessoryConfiguration.permanentOrder.filter {
                            SoftEditorAccessoryConfiguration.expandedVisible.contains($0)
                        }) { action in
                            Button {
                                if let description = SoftEditorAccessoryConfiguration.description(for: action) {
                                    onDescriptionSelected(description)
                                }
                                if let category = SoftEditorAccessoryFilesMenuConfiguration.category(for: action) {
                                    filesInsertionContext = onFiles()
                                    initialFilesCategory = category
                                    showFilesMenu = true
                                } else if action == .time {
                                    timeInsertionContext = onFiles()
                                    showTimeMenu = true
                                } else if let selector = SoftEditorMIDISelector(action: action) {
                                    midiSelector = selector
                                } else {
                                    onAction(action)
                                }
                            } label: {
                                VStack(spacing: 2) {
                                    Image(systemName: action.symbol)
                                    Text(action.title)
                                }
                                .font(.caption)
                                .fixedSize()
                                .padding(.horizontal, 8)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if showsCompact {
                        launcher
                    } else {
                        Color.clear.frame(width: 0, height: 0)
                    }
                }
                .foregroundStyle(.white)
                .background(Color(white: 0.16), in: .rect(cornerRadius: 8))
            } else if showsCompact {
                HStack(spacing: 0) {
                    launcher
                    clearLauncher
                }
            }

            if showFilesMenu {
                SoftEditorAccessoryFilesMenu(
                    initialCategory: initialFilesCategory,
                    onFileNameSelected: { filename in
                        if let currentContext = onFiles() {
                            // MARK: - BM:🅱️ Keep the open Files workflow while refreshing its target for the current slot.
                            filesInsertionContext = currentContext
                            _ = onFileNameSelected(filename, currentContext)
                        }
                        // MARK: - BM:🅱️ add your comments here
                        // Successful insertion keeps the local file list, category, Files menu
                        // and Tools panel open so the current live editor can accept another file.
                    },
                    onClose: {
                        filesInsertionContext = nil
                        initialFilesCategory = nil
                        showFilesMenu = false
                    }
                )
                .frame(
                    width: filesPanelWidth,
                    height: SoftEditorAccessoryConfiguration.filesMenuHeight
                )
                .contentShape(Rectangle())
                .allowsHitTesting(true)
                .zIndex(500)
            }

            if showTimeMenu {
                SoftEditorAccessoryTimeMenu(
                    onCitySelected: { onDescriptionSelected(SoftEditorAccessoryConfiguration.cityDescription) },
                    onReturnToTime: { onDescriptionSelected(SoftEditorAccessoryConfiguration.timeDescription) },
                    onTimeCommandSelected: { command in
                        if let currentContext = onFiles() {
                            // MARK: - BM:🅱️ Keep the open Time workflow while refreshing its target for the current slot.
                            timeInsertionContext = currentContext
                            _ = onTimeCommandSelected(command, currentContext)
                        }
                    },
                    onClose: { showTimeMenu = false }
                )
                .frame(
                    width: filesPanelWidth,
                    height: SoftEditorAccessoryConfiguration.filesMenuHeight
                )
                .contentShape(Rectangle())
                .allowsHitTesting(true)
                .zIndex(500)
            }

            midiSelectorView
        }
    }

    @ViewBuilder
    private var midiSelectorView: some View {
        switch midiSelector {
        case .note:
            SoftEditorMIDINoteMenu(
                defaultChannel: defaultMIDIChannel,
                previewTransport: midiNotePreviewTransport,
                onClose: { midiSelector = nil },
                onInsert: onMIDINoteInsert
            )
            .frame(width: filesPanelWidth, height: SoftEditorAccessoryConfiguration.filesMenuHeight)
            .zIndex(500)
        case .controlChange:
            SoftEditorMIDIControlChangeMenu(
                defaultChannel: defaultMIDIChannel,
                testTransport: midiControlChangeTestTransport,
                onClose: { midiSelector = nil },
                onInsert: onMIDIControlChangeInsert
            )
            .frame(width: filesPanelWidth, height: SoftEditorAccessoryConfiguration.filesMenuHeight)
            .zIndex(500)
        case nil:
            EmptyView()
        }
    }

    private var launcher: some View {
        Button(action: onOpen) {
            VStack(spacing: 2) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(SoftEditorAccessoryConfiguration.compactLauncherColor)
                Text("quick")
                    .font(.caption2)
                    .foregroundStyle(SoftEditorAccessoryConfiguration.compactLauncherColor)
            }
            .frame(
                width: SoftEditorAccessoryConfiguration.compactLauncherDimension,
                height: SoftEditorAccessoryConfiguration.compactLauncherDimension
            )
            .contentShape(Rectangle())
            .overlay {
                Rectangle()
                    .stroke(
                        SoftEditorAccessoryConfiguration.compactLauncherBorderColor,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Command tools: Files, Midi Note, Midi CC, Time")
        .foregroundStyle(.white)
        .background(Color(white: 0.16), in: .rect(cornerRadius: 8))
    }

    private var clearLauncher: some View {
        Button(action: onClear) {
            VStack(spacing: 2) {
                Image(systemName: "xmark")
                Text("clr")
                    .font(.caption2)
            }
            .foregroundStyle(.red)
            .frame(
                width: SoftEditorAccessoryConfiguration.compactLauncherDimension,
                height: SoftEditorAccessoryConfiguration.compactLauncherDimension
            )
            .contentShape(Rectangle())
            .overlay {
                Rectangle()
                    .stroke(
                        SoftEditorAccessoryConfiguration.compactLauncherBorderColor,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear command text")
        .background(Color(white: 0.16), in: .rect(cornerRadius: 8))
    }
}

private struct SoftEditorAccessoryPalette: View {
    let filesPanelWidth: CGFloat
    let defaultMIDIChannel: Int
    let midiNotePreviewTransport: SoftEditorMIDINotePreviewTransport
    let midiControlChangeTestTransport: SoftEditorMIDIControlChangeTestTransport
    let onAction: (SoftEditorAccessoryAction) -> Void
    let onFiles: () -> SoftEditorAccessoryInsertionContext?
    let onFileNameSelected: (String, SoftEditorAccessoryInsertionContext) -> Bool
    let onTimeCommandSelected: (String, SoftEditorAccessoryInsertionContext) -> Bool
    let onMIDINoteInsert: (String) -> Void
    let onMIDIControlChangeInsert: (String) -> Void
    let onDescriptionSelected: (String) -> Void
    let onClose: () -> Void
    let bottomHeightAdjustment: CGFloat
    // MARK: - BM:🅱️ add your comments here
    // Files presentation is intentionally local to this accessory-bar view; the Boolean below
    // controls both category and file-list rendering without MainScreen presentation state.
    @State private var showFilesMenu = false
    @State private var filesInsertionContext: SoftEditorAccessoryInsertionContext?
    @State private var initialFilesCategory: SoftEditorAccessoryFileCategory?
    // MARK: - BM:🅱️ Time presentation is local to Quick, preserving Files state and behavior.
    @State private var showTimeMenu = false
    @State private var timeInsertionContext: SoftEditorAccessoryInsertionContext?
    @State private var midiSelector: SoftEditorMIDISelector?

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(SoftEditorAccessoryConfiguration.permanentOrder.filter {
                            SoftEditorAccessoryConfiguration.compactVisible.contains($0)
                        }) { action in
                            Button {
                                if let description = SoftEditorAccessoryConfiguration.description(for: action) {
                                    onDescriptionSelected(description)
                                }
                                if let category = SoftEditorAccessoryFilesMenuConfiguration.category(for: action) {
                                    filesInsertionContext = onFiles()
                                    initialFilesCategory = category
                                    showFilesMenu = true
                                } else if action == .time {
                                    timeInsertionContext = onFiles()
                                    showTimeMenu = true
                                } else if let selector = SoftEditorMIDISelector(action: action) {
                                    midiSelector = selector
                                } else {
                                    onAction(action)
                                }
                            } label: {
                                Label {
                                    Text(action.title)
                                } icon: {
                                    Image(systemName: action.symbol)
										.foregroundStyle(.cyan)
                                }
                                .font(.callout)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                        }
                    }
                }
            }
            if showFilesMenu {
                SoftEditorAccessoryFilesMenu(
                    initialCategory: initialFilesCategory,
                    onFileNameSelected: { filename in
                        if let currentContext = onFiles() {
                            // MARK: - BM:🅱️ Refresh only the insertion target; retain the open Files workflow.
                            filesInsertionContext = currentContext
                            _ = onFileNameSelected(filename, currentContext)
                        }
                        // MARK: - BM:🅱️ add your comments here
                        // Successful file insertion intentionally leaves the file list, category,
                        // Files menu and Tools panel visible. The explicit Quick button remains
                        // the normal Tools dismissal control.
                    },
                    onClose: {
                        filesInsertionContext = nil
                        initialFilesCategory = nil
                        showFilesMenu = false
                    }
                )
                .frame(
                    width: filesPanelWidth,
                    height: SoftEditorAccessoryConfiguration.filesMenuHeight
                )
                .contentShape(Rectangle())
                .allowsHitTesting(true)
                .zIndex(500)
            }
            if showTimeMenu {
                SoftEditorAccessoryTimeMenu(
                    onCitySelected: { onDescriptionSelected(SoftEditorAccessoryConfiguration.cityDescription) },
                    onReturnToTime: { onDescriptionSelected(SoftEditorAccessoryConfiguration.timeDescription) },
                    onTimeCommandSelected: { command in
                        if let currentContext = onFiles() {
                            // MARK: - BM:🅱️ Refresh only the insertion target; retain the open Time workflow.
                            timeInsertionContext = currentContext
                            _ = onTimeCommandSelected(command, currentContext)
                        }
                    },
                    onClose: { showTimeMenu = false }
                )
                .frame(
                    width: filesPanelWidth,
                    height: SoftEditorAccessoryConfiguration.filesMenuHeight
                )
                .contentShape(Rectangle())
                .allowsHitTesting(true)
                .zIndex(500)
            }

            midiSelectorView
        }
        .buttonStyle(.plain)
        .frame(minHeight: bottomHeightAdjustment, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 8)
        .foregroundStyle(.white)
        .background(Color(white: 0.12))
        .overlay {
            Rectangle()
                .stroke(
                    SoftEditorAccessoryConfiguration.compactLauncherBorderColor,
                    lineWidth: SoftEditorAccessoryConfiguration.toolsHelperBorderWidth
                )
        }
    }

    @ViewBuilder
    private var midiSelectorView: some View {
        switch midiSelector {
        case .note:
            SoftEditorMIDINoteMenu(
                defaultChannel: defaultMIDIChannel,
                previewTransport: midiNotePreviewTransport,
                onClose: { midiSelector = nil },
                onInsert: onMIDINoteInsert
            )
            .frame(
                maxWidth: .infinity,
                minHeight: SoftEditorAccessoryConfiguration.filesMenuHeight,
                maxHeight: SoftEditorAccessoryConfiguration.filesMenuHeight,
                alignment: .topLeading
            )
            .zIndex(500)
        case .controlChange:
            SoftEditorMIDIControlChangeMenu(
                defaultChannel: defaultMIDIChannel,
                testTransport: midiControlChangeTestTransport,
                onClose: { midiSelector = nil },
                onInsert: onMIDIControlChangeInsert
            )
            .frame(
                maxWidth: .infinity,
                minHeight: SoftEditorAccessoryConfiguration.filesMenuHeight,
                maxHeight: SoftEditorAccessoryConfiguration.filesMenuHeight,
                alignment: .topLeading
            )
            .zIndex(500)
        case nil:
            EmptyView()
        }
    }

}

// MARK: - BM:🅱️ SoftEditor Accessory Time Menu
private struct SoftEditorAccessoryTimeMenu: View {
    let onCitySelected: () -> Void
    let onReturnToTime: () -> Void
    let onTimeCommandSelected: (String) -> Void
    let onClose: () -> Void
    @State private var selectedCommand: SoftEditorAccessoryTimeCommand?

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                LazyVStack(spacing: 0) {
                    if selectedCommand == nil {
                        ForEach(SoftEditorAccessoryTimeCommand.allCases) { command in
                            Button {
                                selectedCommand = command
                                onCitySelected()
                            } label: {
                                Text(command.title)
                                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                        }
                    } else {
                        ForEach(SoftEditorAccessoryTimeCity.allCases) { city in
                            Button {
                                if let selectedCommand {
                                    onTimeCommandSelected(selectedCommand.insertionText(for: city))
                                }
                            } label: {
                                Text(city.title)
                                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, SoftEditorAccessoryConfiguration.filesMenuContentPadding)
        .foregroundStyle(.white)
        .background(Color(white: 0.12))
        .overlay {
            Rectangle().stroke(
                SoftEditorAccessoryConfiguration.compactLauncherBorderColor,
                lineWidth: SoftEditorAccessoryConfiguration.toolsHelperBorderWidth
            )
        }
        .contentShape(Rectangle())
        .allowsHitTesting(true)
    }

    private var header: some View {
        HStack {
            Button {
                selectedCommand = nil
                onClose()
            } label: {
                Image(systemName: "house")
                    .frame(width: 44, height: 44)
                    .foregroundStyle(.cyan)
            }
            .accessibilityLabel(selectedCommand == nil ? "Exit Time" : "Exit City")

            Spacer(minLength: 0)
            Text(selectedCommand == nil ? "Time" : "City")
                .foregroundStyle(.cyan)
            Spacer(minLength: 0)

            if selectedCommand != nil {
                Button {
                    selectedCommand = nil
                    onReturnToTime()
                } label: {
                    Image(systemName: "arrowshape.backward")
                        .frame(width: 44, height: 44)
                        .foregroundStyle(.cyan)
                }
                .accessibilityLabel("Back to Time")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
    }
}

private enum SoftEditorAccessoryTimeCommand: String, CaseIterable, Identifiable {
    case date = ".date"
    case clock = ".clock"
    case year = ".year"
    case month = ".month"
    case day = ".ord"
    case dayOfWeek = ".dow"
    case hour = ".hour"
    case minute = ".min"
    case second = ".sec"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .date: "date"
        case .clock: "clock"
        case .year: "year"
        case .month: "month"
        case .day: "day"
        case .dayOfWeek: "day of week"
        case .hour: "hour"
        case .minute: "minute"
        case .second: "second"
        }
    }

    func insertionText(for city: SoftEditorAccessoryTimeCity) -> String {
        guard let timeZoneIdentifier = city.timeZoneIdentifier else {
            return rawValue
        }
        return "\(rawValue) \(timeZoneIdentifier)"
    }
}

private enum SoftEditorAccessoryTimeCity: String, CaseIterable, Identifiable {
    case local
    case losAngeles = "America/Los_Angeles"
    case newYork = "America/New_York"
    case london = "Europe/London"
    case paris = "Europe/Paris"
    case johannesburg = "Africa/Johannesburg"
    case dubai = "Asia/Dubai"
    case kolkata = "Asia/Kolkata"
    case tokyo = "Asia/Tokyo"
    case sydney = "Australia/Sydney"
    case auckland = "Pacific/Auckland"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local: "local"
        case .losAngeles: "Los Angeles"
        case .newYork: "New York"
        case .london: "London"
        case .paris: "Paris"
        case .johannesburg: "Johannesburg"
        case .dubai: "Dubai"
        case .kolkata: "Kolkata"
        case .tokyo: "Tokyo"
        case .sydney: "Sydney"
        case .auckland: "Auckland"
        }
    }

    var timeZoneIdentifier: String? {
        self == .local ? nil : rawValue
    }
}

// MARK: - BM:🅱️ SoftEditor Accessory Files Menu
private struct SoftEditorAccessoryFilesMenu: View {
    let initialCategory: SoftEditorAccessoryFileCategory?
    let onFileNameSelected: (String) -> Void
    let onClose: () -> Void
    @State private var selectedCategory: SoftEditorAccessoryFileCategory?
    @State private var fileChoices: [SoftEditorAccessoryChoice] = []
    @State private var fileError: String?

    init(
        initialCategory: SoftEditorAccessoryFileCategory? = nil,
        onFileNameSelected: @escaping (String) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.initialCategory = initialCategory
        self.onFileNameSelected = onFileNameSelected
        self.onClose = onClose
        _selectedCategory = State(initialValue: initialCategory)
    }

    var body: some View {
        VStack(spacing: 0) {
            // The category menu has only Home because it is the Files-workflow entry point.
            // The file list has Back to return to categories and Home to exit to normal Tools.
            HStack {

				if selectedCategory == nil {
					Button(action: onClose) {
						Image(systemName: "house")
							.frame(width: 44, height: 44)
							.foregroundStyle(.cyan)

					}
					.accessibilityLabel("Exit Files")

					Spacer(minLength: 0)
					Text("Files")
						.foregroundStyle(.cyan)

					Spacer(minLength: 0)
                    // Top-level Files-menu Home remains the sole navigation control and is left-aligned.
                } else {
					Button(action: onClose) {
						Image(systemName: "house")
							.frame(width: 44, height: 44)
							.foregroundStyle(.cyan)

					}
					.accessibilityLabel("Exit Files")

					Spacer(minLength: 0)

                    if initialCategory == nil {
                        Button {
                            selectedCategory = nil
                            fileChoices = []
                            fileError = nil
                        } label: {
                            Image(systemName: "arrowshape.backward")
                                .frame(width: 44, height: 44)
								.foregroundStyle(.cyan)
                        }
                        .accessibilityLabel("Back to file categories")
                    }
                }
            }

            if selectedCategory == nil {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(SoftEditorAccessoryFilesMenuConfiguration.categories) { category in
                            Button {
                                loadFiles(for: category)
                            } label: {
                                Text(category.title)
                                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                        }
                    }
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(fileChoices) { choice in
                            Button {
                                onFileNameSelected(choice.insertion)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(choice.title).font(.callout)
                                    if !choice.detail.isEmpty {
                                        Text(choice.detail)
                                            .font(.caption)
                                            .foregroundStyle(.gray)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                        }
                        if let fileError {
                            Text(fileError)
                                .font(.caption)
                                .padding(.vertical, 8)
                        } else if fileChoices.isEmpty {
                            Text("No matching files")
                                .font(.caption)
                                .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        // Files uses the same dark Tools-panel background and white border. The width comes
        // from the owning Tools panel; these values keep every label inside the panel edge.
        .padding(.horizontal, SoftEditorAccessoryConfiguration.filesMenuContentPadding)
        .foregroundStyle(.white)
        .background(Color(white: 0.12))
        .overlay {
            Rectangle().stroke(
                SoftEditorAccessoryConfiguration.compactLauncherBorderColor,
                lineWidth: SoftEditorAccessoryConfiguration.toolsHelperBorderWidth
            )
        }
        .contentShape(Rectangle())
        .allowsHitTesting(true)
        .onAppear {
            if let initialCategory {
                loadFiles(for: initialCategory)
            }
        }
    }

    // MARK: - BM:🅱️ Route a selected category through the existing Documents-first catalog.
    private func loadFiles(for category: SoftEditorAccessoryFileCategory) {
        selectedCategory = category
        do {
            fileChoices = try SoftEditorAccessoryCatalog.fileChoices(for: category)
            fileError = nil
        } catch {
            fileChoices = []
            fileError = "Unable to read files: \(error.localizedDescription)"
        }
    }
}

private struct SoftEditorAccessoryChoice: Identifiable {
    let id: String
    let title: String
    let detail: String
    let insertion: String
}

private enum SoftEditorAccessoryCatalog {
    // MARK: - BM:🅱️  File picker integration reads Documents first, then bundle files, and preserves extensions.
    nonisolated static func fileChoices(for category: SoftEditorAccessoryFileCategory) throws -> [SoftEditorAccessoryChoice] {
        let documentURLs: [URL]
        if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            documentURLs = try regularFiles(in: documentsDirectory)
        } else {
            documentURLs = []
        }

        let bundleURLs = try Bundle.main.resourceURL.map(regularFiles(in:)) ?? []
        var seenNames = Set<String>()

        return (documentURLs + bundleURLs)
            .filter { category.allowedExtensions.contains($0.pathExtension.lowercased()) }
            .filter { seenNames.insert($0.lastPathComponent.lowercased()).inserted }
            .sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
            }
            .map { url in
            SoftEditorAccessoryChoice(
                id: url.path, title: url.lastPathComponent, detail: category.title,
                insertion: url.lastPathComponent
            )
            }
    }

    private nonisolated static func regularFiles(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { url in
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true
        }
    }
}

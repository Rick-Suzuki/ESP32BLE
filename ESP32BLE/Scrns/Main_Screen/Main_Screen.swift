
import SwiftUI
import UIKit
import AVFoundation
import PDFKit

private enum MainScreenPersistedModeFiles {
    static let displayMode = ".main_screen_view_mode.cfg"
    static let buttonActionMode = ".main_screen_button_action_mode.cfg"
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
    private let smartViewHeight: CGFloat = 294
    // Adjust this to tune the height of the 16 color/visibility cells in the smart button panel.
    private let smartButtonPanelColorCellHeight: CGFloat = 46
    private let smartSFPanelSymbols = [
        "folder", "eye", "magnifyingglass", "lightbulb.max.fill",
        "speaker.wave.2", "star", "heart", "bell",
        "house", "gearshape", "airplane", "book",
        "camera", "cart", "cloud", "envelope",
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
    private let smartButtonSwatchHexColors = [
        "0000FF", "171775", "000000",
        "00A600", "004F00", "D42AD4",
        "21A3A3", "CC1451", "CC7AA3", "CCCC00",
        "FF6666", "00CC66", "492545", "007FFF",
        "C97827"
    ]
    private let smartEscapeCodeRows: [(english: String, command: String, description: String)] = [
        ("escape key", "ESC:", "sends the escape key"),
        ("send return", "RET:", "sends the return key"),
        ("backspace key", "BS:", "sends a backspace key"),
        ("sends space", "SP:", "sends the space character."),
        ("tab key", "TAB:", "sends the tab key"),
        ("new line", "NL:", "sends a newline character."),
        ("colon", ":", "a colon is used to separate keyboard presses"),
        ("up key", "UP:", "sends up arrow"),
        ("down key", "DOWN:", "sends down arrow"),
        ("left key", "LEFT:", "sends left arrow"),
        ("right key", "RIGHT:", "sends right arrow"),
        ("select all (ctl-a)", "CA:", "sends control-a"),
        ("copy (ctl-c)", "CC:", "sends control-c"),
        ("paste (ctl-v)", "CV:", "sends control-v"),
        ("cut (ctl-x)", "CX:", "sends control-x"),
        ("select all (cmd-a)", "MA:", "sends command-a"),
        ("copy (cmd-c)", "MC:", "sends command-c"),
        ("paste (cmd-v)", "MV:", "sends command-v"),
        ("cut (cmd-x)", "MX:", "sends command-x")
    ]
    private let smartCommandRows: [(english: String, shortcut: String, description: String)] = [
		//
		//----------------------------------------
		//
		("clock", "clock","""
Inserts the current time.
	
Optionally specify a city:
	
clock Paris
clock Tokyo
"""),
		//
		//----------------------------------------
		//
		("date", "date ", """
Inserts the current date.
 
Optionally specify a city:
 
date Paris
date Tokyo
"""),
		//
		//----------------------------------------
		//
		("day", "day ", """
Inserts the current day.
"""),
		//
		//----------------------------------------
		//
		("day of week", "dow ", """
Inserts the day of the week.
"""),
		//
		//----------------------------------------
		//
		("year", "year ", """
Inserts the current year.
"""),
		//
		//----------------------------------------
		//
		("prev", "prev", """
Goes to the previous document
in the file list.
"""),
		//
		//----------------------------------------
		//
		("next", "next", """
Goes to the next document
in the file list.
"""),
		//
		//----------------------------------------
		//
		("month", "month ", """
Inserts the current month.
"""),
		//
		//----------------------------------------
		//
		("hour", "hour ", """
Inserts the current hour.
"""),
		//
		//----------------------------------------
		//
		("mins", "min ", """
Inserts the current minutes.
"""),
		//
		//----------------------------------------
		//
		("secs", "sec ", """
Inserts the current seconds.
"""),
		//
		//----------------------------------------
		//
		("device power", "power ", """
Shows the device
power state.
"""),
		//
		//----------------------------------------
		//
		("back", "back", """
Goes back in the
loaded page stack.
"""),
		//
		//----------------------------------------
		//
		("forward", "forw", """
Goes forward in the
loaded page stack.
"""),
		//
		//----------------------------------------
		//
		("ambient sound", "amb snd.mp3", """
Starts ambient sound
playback.
"""),
		//
		//----------------------------------------
		//
		("play sound", "snd snd.mp3", """
Plays a sound file.
"""),
		//
		//----------------------------------------
		//
		("speak text", "spk hello", """
Speaks text aloud.
"""),
		//
		//----------------------------------------
		//
		("Esp32 out", "out 32 1", """
Sends an ESP32
output command.
"""),
		//
		//----------------------------------------
		//
		("Esp32 pwm", "pwm 32 5 4", """
Sends an ESP32
PWM command.
"""),
		//
		//----------------------------------------
		//
		("home", "home", """
Goes to the
home page.
"""),
		//
		//----------------------------------------
		//
		("wait time", "wait 5", """
Waits before continuing
a command chain.
"""),
		//
		//----------------------------------------
		//
		("tap minus", "minus 10", """
Subtracts from a
tap counter.
"""),
		//
		//----------------------------------------
		//
		("tap add", "add ", """
Adds to a
tap counter.
"""),
		//
		//----------------------------------------
		//
		("random number", "rnd 0 100", """
Generates a random
number.
"""),
		//
		//----------------------------------------
		//
		("random line", "rnd file.txt", """
Uses a random line
from a file.
"""),
		//
		//----------------------------------------
		//
		("timer sound", "timer 60 snd.wav", """
Runs a timer that
plays sound.
"""),
		//
		//----------------------------------------
		//
		("timer speak", "timer 10 hello", """
Runs a timer that
speaks text.
"""),
		//
		//----------------------------------------
		//
		("run shortcut", "sc shortcutName", """
Runs an iOS
shortcut.
"""),
		//
		//----------------------------------------
		//
		("open app", "app mail", """
Opens an app.
"""),
		//
		//----------------------------------------
		//
		("preview file", "file file.txt", """
Previews a file.
""")
	]

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
    @State var soundEffectPlayer: AVAudioPlayer?
    @StateObject var mainGridTimerState = MainGridSharedTimerState()
    @StateObject var mainGridAmbientSoundState = MainGridAmbientSoundState()
    @ObservedObject var ble: BLEKeyboardManager
    @State var displayMode: FunctionKeyDisplayMode = .right
    @State var isEditingDocumentName = false
    @State var documentNameDraft = ""
    @State var alertTitle = "Alert"
    @State var renameAlertMessage: String?
    @State var isGridEditModeEnabled = false
    @State var activeDragIndex: Int?
    @State var editingSlotIndex: Int?
    @State var editingSlotText = ""
    @State private var smartCommandDescription = "command description"
    @State private var isSmartEscapeCodeTableVisible = false
    @State private var smartActionTextSelectionRange = NSRange(location: 0, length: 0)
    @State private var smartButtonBrightness = 0.5
    @State private var smartButtonBrightnessBaseHex: String?
    @State private var smartButtonPreviewFontSize = 34.0
    @State private var keyboardMinY: CGFloat = .greatestFiniteMagnitude
    @State private var popupDismissTask: Task<Void, Never>?
    @State var presentedPreviewFile: PreviewedFile?
    @AppStorage("selectedTextToSpeechVoiceIdentifier") var selectedTextToSpeechVoiceIdentifier = ""
    @AppStorage("textToSpeechRate") var textToSpeechRate = Double(AVSpeechUtteranceDefaultSpeechRate)
    @AppStorage("selectedBackgroundImageIndex") var selectedBackgroundImageIndex = 0
    @AppStorage("selectedBackgroundImageName") var selectedBackgroundImageName = ""
    @AppStorage("selectedBackgroundImagePath") var selectedBackgroundImagePath = ""
    @AppStorage("backgroundImageOpacity") var backgroundImageOpacity = 0.5
    @AppStorage("mainGridBackgroundOpacity") var mainGridBackgroundOpacity = 1.0
    @AppStorage("mainGridEditClipboardText") var mainGridEditClipboardText = ""
    @FocusState var isDocumentNameFieldFocused: Bool
    @FocusState var isSlotEditorFocused: Bool
    @FocusState private var isMainScreenKeyboardFocused: Bool
    let functionKeys: [FunctionKeyEntry]
    let documentFiles: [URL]
    let selectedDocumentName: String
    let selectedDocumentDisplayName: String
    @Binding var boxFontSize: Double
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
    let moveFunctionKeySlot: (Int, Int, Int, GridDimensions) -> Bool
    let duplicateFunctionKeySlot: (Int, Int) -> Bool
    let updateFunctionKeySlot: (Int, String) -> Bool
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
                restorePersistedMainScreenModes()
                reloadSelectedDocumentIfAvailable()
                refreshMainScreenKeyboardFocus()
            }
            .onChange(of: selectedDocumentDisplayName) {
                handleSelectedDocumentDisplayNameChange()
            }
            .onChange(of: editingSlotIndex) {
                smartButtonBrightness = 0.5
                smartButtonBrightnessBaseHex = smartButtonColorHex
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
                handleMainScreenDisappear()
                mainGridAmbientSoundState.stopPlayback()
                popupDismissTask?.cancel()
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
            }
    }

    private var mainScreenContent: some View {
        GeometryReader { geometry in
            let horizontalContentInset: CGFloat = 0
            let contentWidth = max(0, geometry.size.width - (horizontalContentInset * 2))
            let topContentInset: CGFloat = 8
            let bottomContentInset: CGFloat = 0
            let containerFrame = geometry.frame(in: .global)
            let maskBottomY = min(containerFrame.maxY, keyboardMinY)
            let maskHeight = max(0, maskBottomY - containerFrame.minY)
            let maskedScreenHeight = maskHeight + geometry.safeAreaInsets.top

            ZStack(alignment: .top) {
                VStack(spacing: 20) {
                    mainGridSection(availableWidth: contentWidth)

                    if !isGridEditModeEnabled {
                        displayModeButtonSection(availableWidth: contentWidth)
                    }
                }
                .frame(width: contentWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, topContentInset)
                .padding(.bottom, bottomContentInset)
                .ignoresSafeArea(.keyboard)

                if isGridEditModeEnabled {
                    VStack {
                        Spacer()
                        displayModeButtonSection(availableWidth: contentWidth)
                    }
                    .frame(maxWidth: contentWidth, maxHeight: .infinity)
                }

                if editingSlotIndex != nil {
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
                    smartView(availableWidth: contentWidth)
                }

                popupOverlay(
                    isSlotEditorPresented: editingSlotIndex != nil,
                    maskedScreenHeight: maskedScreenHeight
                )

            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(.keyboard)
        }
        .padding(.horizontal, 2)
        .ignoresSafeArea(.keyboard)
        .overlay(alignment: .topLeading) {
            externalKeyboardShortcutLayer
        }
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .compatibleNavigationBarVisibility(.visible)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            MainScreenToolbarContent(
                isGridEditModeEnabled: isGridEditModeEnabled,
                editingSlotIndex: editingSlotIndex,
                currentFileNumber: currentFileNumber,
                totalFileCount: totalFileCount,
                currentBackgroundImageNumber: selectedBackgroundImageIndex,
                totalBackgroundImageCount: availableBackgroundImageURLs.count,
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
        }
    }

    private func mainGridSection(availableWidth: CGFloat) -> some View {
        MainScreenGridSection(
            availableWidth: availableWidth,
            reservedBottomInset: isGridEditModeEnabled ? 74 : 0,
            functionKeys: functionKeys,
            visibleBoxCount: visibleBoxCount,
            visibleGridDimensions: visibleGridDimensions,
            mainGridButtonSpacing: mainGridButtonSpacing,
            isGridEditModeEnabled: isGridEditModeEnabled,
            bleSendEnabled: mainGridButtonMode != .disabled,
            onButtonClick: { ButtonClickFeedback.playIfEnabled() },
            isHiddenEntry: isMainGridEntryHidden,
            isInteractiveWidgetEntry: isInteractiveMainGridWidgetEntry,
            sendLine: sendMainGridEntry,
            onBeginSlotEditing: beginSlotEditing,
            buttonLabel: { entry, index, buttonHeight in
                AnyView(
                    mainGridButtonLabel(
                        entry: entry,
                        index: index,
                        buttonHeight: buttonHeight,
                        backgroundOpacity: mainGridBackgroundOpacity
                    )
                )
            },
            dragGesture: { entry, index, gridDimensions in
                AnyGesture(mainGridButtonDragGesture(entry: entry, index: index, gridDimensions: gridDimensions))
            },
            onDuplicateSlot: { entry, index, gridDimensions in
                duplicateSlotIfPossible(entry: entry, index: index, gridDimensions: gridDimensions)
            },
            onCopyPasteSlot: { entry, index in
                handleThreeTapEditAction(entry: entry, index: index)
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

    private var settingsToolbarButtonLabel: some View {
        Text(isPad ? "settings >" : ">")
            .font(.headline)
            .foregroundStyle((isGridEditModeEnabled || editingSlotIndex != nil) ? Color(white: 0.65) : .white)
            .frame(minWidth: isPad ? 92 : 44, minHeight: 44)
            .background(Color.gray.opacity(0.45))
            .overlay {
                RoundedRectangle(cornerRadius: 23)
                    .stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
            }
            .clipShape(.rect(cornerRadius: 23))
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
        selectedDocumentName.caseInsensitiveCompare("home.txt") == .orderedSame
    }

    private func openHomeDocumentFromMainScreenControl() {
        if mainGridButtonMode == .speechActive {
            speakMainGridText("home")
        }
        _ = selectDocumentNamedFromGrid("home.txt")
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
            isBluetoothConnected: ble.isConnected,
            mainGridButtonMode: mainGridButtonMode,
            displayMode: displayMode,
            displayModeButtonColor: displayModeButtonColor,
            fontControlColor: fontControlColor,
            speechRecognitionActiveColor: speechRecognitionActiveColor,
            bleSendActiveColor: bleSendActiveColor,
            onDecreaseRows: decreaseGridRows,
            onIncreaseRows: increaseGridRows,
            onDecreaseColumns: decreaseGridColumns,
            onIncreaseColumns: increaseGridColumns,
            onDecreaseBoxFontSize: decreaseBoxFontSize,
            onIncreaseBoxFontSize: increaseBoxFontSize,
            onResetBoxFontSize: resetBoxFontSize,
            onToggleSpeechRecognition: { isSpkRecEnabled.toggle() },
            onCycleMainGridButtonMode: cycleMainGridButtonMode,
            onStopSpeech: stopSpokenGridText,
            onAdvanceDisplayMode: advanceDisplayMode
        )
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
            onVisibilityChange: showSlotVisibilityPopup,
            onSelectPreviousButton: selectPreviousEditableSlot,
            onSelectNextButton: selectNextEditableSlot
        )
        .ignoresSafeArea(.keyboard)
    }

    private func smartView(availableWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            smartCommandPanel
                .frame(width: 256, height: smartViewHeight)

            smartColorPanel
                .frame(width: 224, height: smartViewHeight)

            smartButtonPanel
                .frame(width: 280, height: smartViewHeight)

            smartSFPanel
                .frame(maxWidth: .infinity)
                .frame(height: smartViewHeight)
        }
        .frame(width: min(smartViewWidth, availableWidth), height: smartViewHeight)
        .ignoresSafeArea(.keyboard)
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

    private var smartCommandPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    ButtonClickFeedback.playIfEnabled()
                    smartActionTextBinding.wrappedValue = ""
                    smartActionTextSelectionRange = NSRange(location: 0, length: 0)
                } label: {
                    Text("X")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.gray)
                        .frame(width: 46, height: 46)
                        .background(Color.black)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear command text")

                SmartActionTextField(
                    placeholder: "command",
                    text: smartActionTextBinding,
                    selectedRange: $smartActionTextSelectionRange,
                    fontSize: 20
                )
                    .padding(.horizontal, 3)
                    .frame(minWidth: 0)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
            }
            .frame(height: 46)
            .background(Color.black)
            .overlay {
                Rectangle()
                    .stroke(Color.white, lineWidth: 1)
            }

            HStack(spacing: 0) {
                smartModifierButton(systemName: "control", accessibilityLabel: "Control", prefix: "⌃")
                smartModifierButton(systemName: "option", accessibilityLabel: "Option", prefix: "⌥")
                smartModifierButton(systemName: "shift", accessibilityLabel: "Shift", prefix: "⇧")
                smartModifierButton(systemName: "command", accessibilityLabel: "Command", prefix: "⌘")
                smartEscapeCodeToggleButton
            }
            .frame(height: 44)

            HStack(spacing: 0) {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(1...20, id: \.self) { functionKeyNumber in
                            smartCommandTableButton("F\(functionKeyNumber)", foreground: .yellow) {
                                smartActionTextBinding.wrappedValue = "F\(functionKeyNumber)"
                            }
                        }
                    }
                }
                .frame(width: 72)
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
                                smartCommandTableButton(commandRow.english, foreground: .white) {
                                    smartActionTextBinding.wrappedValue = commandRow.shortcut
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
            Rectangle()
                .stroke(Color.white, lineWidth: 1)
        }
    }

    private var smartActionTextBinding: Binding<String> {
        Binding(
            get: {
                let actionText = editingSlotText.components(separatedBy: "::").first ?? editingSlotText
                return displayActionTextReplacingModifierCodes(actionText)
            },
            set: { newActionText in
                let components = editingSlotText.components(separatedBy: "::")
                let rightSideText = components.dropFirst().joined(separator: "::")

                if rightSideText.isEmpty {
                    editingSlotText = newActionText
                } else {
                    editingSlotText = "\(newActionText)::\(rightSideText)"
                }
            }
        )
    }

    private var smartRightTextBinding: Binding<String> {
        Binding(
            get: {
                let components = editingSlotText.components(separatedBy: "::")
                return components
                    .dropFirst()
                    .filter { $0 != hiddenButtonMetadataToken }
                    .joined(separator: "::")
            },
            set: { newRightText in
                let actionText = editingSlotText.components(separatedBy: "::").first ?? ""
                let isHidden = smartIsButtonHidden

                if newRightText.isEmpty && !isHidden {
                    editingSlotText = actionText
                } else {
                    let rightComponents = newRightText.isEmpty ? [] : [newRightText]
                    let metadataComponents = isHidden ? [hiddenButtonMetadataToken] : []
                    editingSlotText = ([actionText] + rightComponents + metadataComponents).joined(separator: "::")
                }
            }
        )
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
        editingSlotText.components(separatedBy: "::").contains(hiddenButtonMetadataToken)
    }

    private var smartColorPanel: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                smartColorImage
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { dragValue in
                                applySmartColorSelection(
                                    at: dragValue.location,
                                    in: geometry.size
                                )
                            }
                    )
            }
            .frame(maxWidth: .infinity)
            .frame(height: 132)
            .background(Color.black)
            .overlay {
                Rectangle()
                    .stroke(Color.white, lineWidth: 1)
            }

            ScrollView(.vertical) {
                Text(smartCommandDescription)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.cyan)
                    .multilineTextAlignment(.center)
                    .padding(6)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .overlay {
                Rectangle()
                    .stroke(Color.white, lineWidth: 1)
            }
        }
        .background(Color.black)
        .overlay {
            Rectangle()
                .stroke(Color.white, lineWidth: 1)
        }
    }

    private var smartButtonPanel: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: 4) {
                    smartVerticalSliderLabel("")
                    Slider(value: $smartButtonBrightness, in: 0...1)
                        .rotationEffect(.degrees(-90))
                        .frame(width: 140, height: 26)
                        .tint(.yellow)
                        .onChange(of: smartButtonBrightness) {
                            applySmartButtonBrightness()
                        }
                }
                .frame(width: 64)

                VStack(spacing: 8) {
                    smartButtonPreview
                }
                .frame(maxWidth: .infinity)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 4),
                spacing: 0
            ) {
                smartVisibilityButton
                smartClearColorButton
                ForEach(Array(smartButtonSwatchHexColors.prefix(14)), id: \.self) { hexColor in
                    smartButtonColorSwatch(hexColor)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Color.black)
        .overlay {
            Rectangle()
                .stroke(Color.white, lineWidth: 1)
        }
    }

    private var smartButtonPreview: some View {
        Group {
            if let symbolDisplay = smartButtonSFSymbolDisplay {
                VStack(spacing: 4) {
                    Image(systemName: symbolDisplay.name)
                        .font(.system(size: max(18, CGFloat(boxFontSize) * 0.9), weight: .semibold))

                    TextField("", text: smartButtonEditablePreviewTextBinding, axis: .vertical)
                        .font(.system(size: max(14, CGFloat(boxFontSize) * 0.55), weight: .semibold))
                        .foregroundStyle(.white)
                        .accentColor(.white)
                        .multilineTextAlignment(.center)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(1...2)
                        .padding(.horizontal, 8)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
            } else {
                TextField("", text: smartButtonEditablePreviewTextBinding, axis: .vertical)
                    .font(.system(size: CGFloat(boxFontSize), weight: .semibold))
                    .foregroundStyle(.white)
                    .accentColor(.white)
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(1...3)
                    .padding(.horizontal, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 104)
        .background(smartButtonPreviewColor)
        .clipShape(.rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white, lineWidth: 1.5)
        }
    }

    private var smartButtonSFSymbolDisplay: (name: String, subtitle: String?)? {
        let rightText = smartButtonTextBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = rightText.components(separatedBy: ":")
        let candidateName = components.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !candidateName.isEmpty,
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

    private var smartButtonEditablePreviewTextBinding: Binding<String> {
        Binding(
            get: {
                if let symbolDisplay = smartButtonSFSymbolDisplay {
                    return symbolDisplay.subtitle ?? ""
                }

                return smartButtonTextBinding.wrappedValue
            },
            set: { newText in
                if let symbolDisplay = smartButtonSFSymbolDisplay {
                    smartButtonTextBinding.wrappedValue = "\(symbolDisplay.name):\(newText)"
                } else {
                    smartButtonTextBinding.wrappedValue = newText
                }
            }
        )
    }

    private func setSmartButtonSFSymbol(_ symbolName: String) {
        let currentText = smartButtonTextBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let symbolText = smartButtonSymbolTextComponents(from: currentText)

        if let symbolText {
            smartButtonTextBinding.wrappedValue = "\(symbolName):\(symbolText.subtitle)"
        } else if currentText.isEmpty {
            smartButtonTextBinding.wrappedValue = "\(symbolName):"
        } else {
            smartButtonTextBinding.wrappedValue = "\(symbolName):\(currentText)"
        }
    }

    private func smartButtonSymbolTextComponents(from text: String) -> (name: String, subtitle: String)? {
        let components = text.components(separatedBy: ":")
        let candidateName = components.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !candidateName.isEmpty,
              !candidateName.contains(where: \.isWhitespace),
              UIImage(systemName: candidateName) != nil else {
            return nil
        }

        return (
            candidateName,
            components.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private var smartVisibilityButton: some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            smartButtonVisibilityBinding.wrappedValue.toggle()
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
        }
        .buttonStyle(.plain)
        .accessibilityLabel(smartButtonVisibilityBinding.wrappedValue ? "Hide button" : "Show button")
    }

    private var smartClearColorButton: some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            smartButtonBrightnessBaseHex = nil
            smartButtonBrightness = 0.5
            smartRightTextBinding.wrappedValue = rightTextWithoutColorPrefix(smartRightTextBinding.wrappedValue)
        } label: {
            Text("clr")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: smartButtonPanelColorCellHeight)
                .background(Color.gray)
                .overlay {
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func smartButtonColorSwatch(_ hexColor: String) -> some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            setSmartButtonColor(hexColor)
        } label: {
            Color(hex: hexColor)
                .frame(maxWidth: .infinity, minHeight: smartButtonPanelColorCellHeight)
                .overlay {
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set button color \(hexColor)")
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
            return Color.blue
        }

        return Color(hex: colorHex)
    }

    private func setSmartButtonColor(_ hexColor: String) {
        smartButtonBrightness = 0.5
        let normalizedHex = hexColor.uppercased()
        smartButtonBrightnessBaseHex = normalizedHex
        smartRightTextBinding.wrappedValue = rightTextReplacingColorPrefix(with: normalizedHex)
    }

    private func applySmartButtonBrightness() {
        guard let colorHex = smartButtonBrightnessBaseHex ?? smartButtonColorHex,
              let adjustedHex = adjustedHexColor(colorHex, brightness: smartButtonBrightness) else {
            return
        }

        if smartButtonBrightnessBaseHex == nil {
            smartButtonBrightnessBaseHex = colorHex
        }
        smartRightTextBinding.wrappedValue = rightTextReplacingColorPrefix(with: adjustedHex)
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
        let components = editingSlotText
            .components(separatedBy: "::")
            .filter { $0 != hiddenButtonMetadataToken }

        if isHidden {
            editingSlotText = (components + [hiddenButtonMetadataToken]).joined(separator: "::")
        } else {
            editingSlotText = components.joined(separator: "::")
        }
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

    private var smartEscapeCodeToggleButton: some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            isSmartEscapeCodeTableVisible.toggle()
        } label: {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(isSmartEscapeCodeTableVisible ? .green : .white)
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
                .frame(height: 26)
                .background(Color.black)
                .overlay {
                    Rectangle()
                        .stroke(Color.white.opacity(0.55), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func insertSmartActionTextAtSelection(_ insertedText: String) {
        var actionText = smartActionTextBinding.wrappedValue
        let replacementRange = Range(smartActionTextSelectionRange, in: actionText) ?? actionText.endIndex..<actionText.endIndex

        let insertionStart = replacementRange.lowerBound
        actionText.replaceSubrange(replacementRange, with: insertedText)
        let insertionEnd = actionText.index(insertionStart, offsetBy: insertedText.count)

        smartActionTextBinding.wrappedValue = actionText
        smartActionTextSelectionRange = NSRange(insertionEnd..<insertionEnd, in: actionText)
    }

    private func toggleSmartModifierPrefix(_ prefix: String) {
        let orderedPrefixes = ["⌃", "⌥", "⇧", "⌘"]
        var actionText = smartActionTextBinding.wrappedValue
        var enabledPrefixes = Set<String>()
        var didRemovePrefix = true

        while didRemovePrefix {
            didRemovePrefix = false
            for knownPrefix in orderedPrefixes where actionText.hasPrefix(knownPrefix) {
                enabledPrefixes.insert(knownPrefix)
                actionText.removeFirst(knownPrefix.count)
                didRemovePrefix = true
                break
            }
        }

        if enabledPrefixes.contains(prefix) {
            enabledPrefixes.remove(prefix)
        } else {
            enabledPrefixes.insert(prefix)
        }

        smartActionTextBinding.wrappedValue = orderedPrefixes
            .filter { enabledPrefixes.contains($0) }
            .joined() + actionText
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

    private var smartSFPanel: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 4),
                    spacing: 0
                ) {
                    ForEach(smartSFPanelSymbols, id: \.self) { symbolName in
                        smartSFSymbolCell(symbolName)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 0) {
                smartSlotPositionLabel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                smartArrowButton(systemName: "arrow.left") {
                    selectPreviousEditableSlot()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                smartArrowButton(systemName: "arrow.right") {
                    selectNextEditableSlot()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 46)

            HStack(spacing: 0) {
                smartControlButton("test btn", background: Color(red: 0.0, green: 0.5, blue: 0.0)) {
                    testEditingSlotText()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                smartControlButton("close", background: Color.gray.opacity(0.45)) {
                    saveSlotEditing()
                    cancelSlotEditing()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 46)
        }
        .background(Color.black)
        .overlay {
            Rectangle()
                .stroke(Color.white, lineWidth: 1)
        }
    }

    private func smartSFSymbolCell(_ symbolName: String) -> some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            setSmartButtonSFSymbol(symbolName)
        } label: {
            Image(systemName: symbolName)
                .font(.system(size: 22, weight: .semibold))
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
        foreground: Color = .white,
        background: Color = .black,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            ButtonClickFeedback.playIfEnabled()
            action()
        } label: {
            Text(title)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(background)
                .overlay {
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1)
                }
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
            Task { @MainActor in
                await runWaitChainCommandTokens(
                    actionTokens,
                    sourceEntry: nil,
                    respectsBluetoothMode: false
                )
            }
            return
        }

        for actionToken in actionTokens {
            if let clipboardText = targetClipboardTextForSendText(actionToken) {
                UIPasteboard.general.string = clipboardText
            }
        }

        let bluetoothTokens = actionTokens
            .filter { actionToken in
                    targetDocumentNameForSendText(actionToken) == nil &&
                    targetURLForSendText(actionToken) == nil &&
                    targetShortcutURLForSendText(actionToken) == nil &&
                    targetSoundFilenameForSendText(actionToken) == nil &&
                    targetSpokenTextForSendText(actionToken) == nil &&
                    targetSpokenFilenameForSendText(actionToken) == nil &&
                    targetAppURLForSendText(actionToken) == nil &&
                    targetClipboardTextForSendText(actionToken) == nil &&
                    targetPreviewFilenameForSendText(actionToken) == nil &&
                    !isWaitCommandText(actionToken.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) &&
                    targetWidgetDescriptorForSendText(actionToken) == nil
            }
            .map(normalizedBluetoothSendText)
        let targetSoundFilename = actionTokens.compactMap(targetSoundFilenameForSendText).first
        let targetSpokenFilename = actionTokens.compactMap(targetSpokenFilenameForSendText).first
        let targetSpokenText = actionTokens.compactMap(targetSpokenTextForSendText).first
        let targetShortcutURL = actionTokens.compactMap(targetShortcutURLForSendText).first

        if !bluetoothTokens.isEmpty {
            guard ble.isConnected else {
                alertTitle = "Bluetooth not connected"
                renameAlertMessage = "Bluetooth needs to be connected\nbefore sending data to the ESP32."
                return
            }

            guard bluetoothTokens.allSatisfy(isBluetoothSendableText(_:)) else {
                showBluetoothUnsupportedTextBlockedPopup()
                return
            }

            for bluetoothToken in bluetoothTokens {
                ble.sendLine(bluetoothToken)
            }
        }

        if let targetSoundFilename {
            playMainGridSound(named: targetSoundFilename)
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
        return mainGridButtonCornerRadiusMaximum - ((mainGridButtonCornerRadiusMaximum - mainGridButtonCornerRadiusMinimum) * normalizedProgress)
    }

    private func handleSelectedDocumentDisplayNameChange() {
        restorePersistedMainScreenModes()
        restoreVisibleGridState()
        cancelDocumentRename()
        isGridEditModeEnabled = false
        activeDragIndex = nil
        cancelSlotEditing()
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
    private func restorePersistedMainScreenModes() {
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

    func stopSpokenGridText() {
        speechSynthesizer.stopSpeaking(at: .immediate)
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
              editingSlotIndex == nil,
              let targetIndex = targetIndexForEditDrag(
                from: sourceIndex,
                translation: translation,
                gridDimensions: gridDimensions
              ) else {
            return
        }

        let sourceSpan = slotSpan(startingAt: sourceIndex, gridDimensions: gridDimensions)
        guard moveFunctionKeySlot(sourceIndex, targetIndex, sourceSpan, gridDimensions) else {
            alertTitle = ""
            renameAlertMessage = "can't move btn"
            return
        }
    }
}

private struct SmartActionTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    @Binding var selectedRange: NSRange
    let fontSize: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        textField.placeholder = placeholder
        textField.textColor = .white
        textField.tintColor = .white
        textField.textAlignment = .center
        textField.backgroundColor = .clear
        textField.borderStyle = .none
        textField.font = .systemFont(ofSize: fontSize, weight: .semibold)
        textField.adjustsFontSizeToFitWidth = true
        textField.minimumFontSize = fontSize * 0.35
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        context.coordinator.isUpdatingView = true
        defer {
            context.coordinator.isUpdatingView = false
        }

        if uiView.text != text {
            uiView.text = text
        }

        context.coordinator.applySelectedRange(to: uiView)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SmartActionTextField
        var isUpdatingView = false
        private var isApplyingSelectedRange = false

        init(_ parent: SmartActionTextField) {
            self.parent = parent
        }

        @objc func textDidChange(_ textField: UITextField) {
            guard !isUpdatingView, !isApplyingSelectedRange else {
                return
            }

            let newText = textField.text ?? ""
            let newSelectedRange = selectedRange(from: textField)
            DispatchQueue.main.async {
                self.parent.text = newText
                if let newSelectedRange {
                    self.parent.selectedRange = newSelectedRange
                }
            }
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            guard !isUpdatingView, !isApplyingSelectedRange,
                  let newSelectedRange = selectedRange(from: textField) else {
                return
            }

            DispatchQueue.main.async {
                self.parent.selectedRange = newSelectedRange
            }
        }

        func selectedRange(from textField: UITextField) -> NSRange? {
            guard let selectedTextRange = textField.selectedTextRange else {
                return nil
            }

            let location = textField.offset(from: textField.beginningOfDocument, to: selectedTextRange.start)
            let length = textField.offset(from: selectedTextRange.start, to: selectedTextRange.end)
            return NSRange(location: location, length: length)
        }

        func applySelectedRange(to textField: UITextField) {
            guard let start = textField.position(from: textField.beginningOfDocument, offset: parent.selectedRange.location),
                  let end = textField.position(from: start, offset: parent.selectedRange.length),
                  textField.selectedTextRange?.start != start || textField.selectedTextRange?.end != end else {
                return
            }

            isApplyingSelectedRange = true
            textField.selectedTextRange = textField.textRange(from: start, to: end)
            isApplyingSelectedRange = false
        }
    }
}

private struct MainScreenFilePreviewOverlay: View {
    let previewedFile: MainScreen.PreviewedFile
    let onClose: () -> Void
    @State private var previewImage: UIImage?
    @State private var imageScale: CGFloat = 1
    @State private var lastImageScale: CGFloat = 1
    @State private var pinchStartScale: CGFloat = 1
    @State private var imageOffset: CGSize = .zero
    @State private var accumulatedImageOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let safeBottomInset = geometry.safeAreaInsets.bottom
            let maxPixelDimension = max(geometry.size.width, geometry.size.height) * UIScreen.main.scale

            ZStack(alignment: .bottomTrailing) {
                Color.black
                    .ignoresSafeArea()

                Group {
                    switch previewedFile {
                    case let .text(_, contents):
                        ScrollView(.vertical) {
                            Text(contents)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.white)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.top, 68)
                                .padding(.bottom, safeBottomInset + 20)
                        }
                    case .image, .renderedImage:
                        GeometryReader { imageGeometry in
                            Group {
                                if let previewImage {
                                    Image(uiImage: previewImage)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: imageGeometry.size.width, height: imageGeometry.size.height)
                                        .scaleEffect(imageScale)
                                        .offset(imageOffset)
                                        .contentShape(Rectangle())
                                        .overlay {
                                            ImagePreviewGestureSurface(
                                                onPinchBegan: {
                                                    pinchStartScale = imageScale
                                                    lastImageScale = imageScale
                                                },
                                                onPinchChanged: { scale, location, containerSize in
                                                    updateImageMagnification(
                                                        gestureScale: scale,
                                                        location: location,
                                                        containerSize: containerSize
                                                    )
                                                },
                                                onPinchEnded: { scale, location, containerSize in
                                                    finishImageMagnification(
                                                        gestureScale: scale,
                                                        location: location,
                                                        containerSize: containerSize
                                                    )
                                                },
                                                onPanChanged: { translation, containerSize in
                                                    updateImagePan(translation: translation, containerSize: containerSize)
                                                },
                                                onPanEnded: { translation, containerSize in
                                                    finishImagePan(translation: translation, containerSize: containerSize)
                                                },
                                                onDoubleTap: resetImagePreviewTransform
                                            )
                                        }
                                } else {
                                    ProgressView()
                                        .tint(.white)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }
                        }
                    }
                }

                Button("close") {
                    onClose()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(minWidth: 88)
                .frame(height: 44)
                .background(Color.gray.opacity(0.8))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
                }
                .clipShape(.rect(cornerRadius: 12))
                .padding(.trailing, 16)
                .padding(.bottom, safeBottomInset + 16)
            }
            .task(id: previewTaskID(maxPixelDimension: maxPixelDimension)) {
                loadPreviewImage(maxPixelDimension: maxPixelDimension)
            }
        }
        .ignoresSafeArea()
    }

    private func previewTaskID(maxPixelDimension: CGFloat) -> String {
        switch previewedFile {
        case let .text(filename, _):
            return "\(filename):text"
        case let .image(filename, _):
            return "\(filename):\(Int(maxPixelDimension.rounded(.up)))"
        case let .renderedImage(filename, _):
            return "\(filename):rendered"
        }
    }

    private func loadPreviewImage(maxPixelDimension: CGFloat) {
        switch previewedFile {
        case let .image(_, url):
            previewImage = downsampledUIImage(at: url, maxPixelDimension: maxPixelDimension)
            resetImagePreviewTransform()
        case let .renderedImage(_, image):
            previewImage = image
            resetImagePreviewTransform()
        default:
            previewImage = nil
            resetImagePreviewTransform()
        }
    }

    private func updateImageMagnification(
        gestureScale: CGFloat,
        location: CGPoint,
        containerSize: CGSize
    ) {
        let pinchScaleTolerance: CGFloat = 0.01

        if abs(gestureScale - 1) <= pinchScaleTolerance {
            imageScale = pinchStartScale
            imageOffset = clampedImageOffset(
                accumulatedImageOffset,
                containerSize: containerSize,
                scale: pinchStartScale
            )
            return
        }

        let newScale = max(1, pinchStartScale * gestureScale)
        let anchorPoint = CGPoint(
            x: location.x - (containerSize.width / 2),
            y: location.y - (containerSize.height / 2)
        )
        let scaleRatio = newScale / pinchStartScale
        let proposedOffset = CGSize(
            width: anchorPoint.x - (scaleRatio * (anchorPoint.x - accumulatedImageOffset.width)),
            height: anchorPoint.y - (scaleRatio * (anchorPoint.y - accumulatedImageOffset.height))
        )

        imageScale = newScale
        imageOffset = clampedImageOffset(
            proposedOffset,
            containerSize: containerSize,
            scale: newScale
        )
    }

    private func finishImageMagnification(
        gestureScale: CGFloat,
        location: CGPoint,
        containerSize: CGSize
    ) {
        updateImageMagnification(
            gestureScale: gestureScale,
            location: location,
            containerSize: containerSize
        )
        lastImageScale = imageScale
        accumulatedImageOffset = imageOffset

        if imageScale == 1 {
            imageOffset = .zero
            accumulatedImageOffset = .zero
        }
    }

    private func updateImagePan(translation: CGSize, containerSize: CGSize) {
        guard imageScale > 1 else {
            imageOffset = .zero
            accumulatedImageOffset = .zero
            return
        }

        imageOffset = clampedImageOffset(
            CGSize(
                width: accumulatedImageOffset.width + translation.width,
                height: accumulatedImageOffset.height + translation.height
            ),
            containerSize: containerSize,
            scale: imageScale
        )
    }

    private func finishImagePan(translation: CGSize, containerSize: CGSize) {
        updateImagePan(translation: translation, containerSize: containerSize)
        accumulatedImageOffset = imageOffset
    }

    private func resetImagePreviewTransform() {
        withAnimation(.easeInOut(duration: 0.2)) {
            imageScale = 1
            lastImageScale = 1
            imageOffset = .zero
            accumulatedImageOffset = .zero
        }
    }

    private func clampedImageOffset(
        _ proposedOffset: CGSize,
        containerSize: CGSize,
        scale: CGFloat
    ) -> CGSize {
        guard let previewImage else {
            return .zero
        }

        let fittedSize = aspectFitSize(for: previewImage.size, in: containerSize)
        let scaledWidth = fittedSize.width * scale
        let scaledHeight = fittedSize.height * scale
        let maximumHorizontalOffset = max(0, (scaledWidth - containerSize.width) / 2)
        let maximumVerticalOffset = max(0, (scaledHeight - containerSize.height) / 2)

        return CGSize(
            width: min(max(proposedOffset.width, -maximumHorizontalOffset), maximumHorizontalOffset),
            height: min(max(proposedOffset.height, -maximumVerticalOffset), maximumVerticalOffset)
        )
    }

    private func aspectFitSize(for imageSize: CGSize, in containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }

        let widthScale = containerSize.width / imageSize.width
        let heightScale = containerSize.height / imageSize.height
        let fitScale = min(widthScale, heightScale)

        return CGSize(
            width: imageSize.width * fitScale,
            height: imageSize.height * fitScale
        )
    }
}

private struct ImagePreviewGestureSurface: UIViewRepresentable {
    let onPinchBegan: () -> Void
    let onPinchChanged: (_ scale: CGFloat, _ location: CGPoint, _ containerSize: CGSize) -> Void
    let onPinchEnded: (_ scale: CGFloat, _ location: CGPoint, _ containerSize: CGSize) -> Void
    let onPanChanged: (_ translation: CGSize, _ containerSize: CGSize) -> Void
    let onPanEnded: (_ translation: CGSize, _ containerSize: CGSize) -> Void
    let onDoubleTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let pinchGestureRecognizer = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        let panGestureRecognizer = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        panGestureRecognizer.minimumNumberOfTouches = 1
        panGestureRecognizer.maximumNumberOfTouches = 1

        let doubleTapGestureRecognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTapGestureRecognizer.numberOfTapsRequired = 2
        doubleTapGestureRecognizer.numberOfTouchesRequired = 1

        pinchGestureRecognizer.delegate = context.coordinator
        panGestureRecognizer.delegate = context.coordinator
        doubleTapGestureRecognizer.delegate = context.coordinator

        view.addGestureRecognizer(pinchGestureRecognizer)
        view.addGestureRecognizer(panGestureRecognizer)
        view.addGestureRecognizer(doubleTapGestureRecognizer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: ImagePreviewGestureSurface

        init(_ parent: ImagePreviewGestureSurface) {
            self.parent = parent
        }

        @objc func handlePinch(_ gestureRecognizer: UIPinchGestureRecognizer) {
            let location = gestureRecognizer.location(in: gestureRecognizer.view)
            let containerSize = gestureRecognizer.view?.bounds.size ?? .zero

            switch gestureRecognizer.state {
            case .began:
                parent.onPinchBegan()
                parent.onPinchChanged(gestureRecognizer.scale, location, containerSize)
            case .changed:
                parent.onPinchChanged(gestureRecognizer.scale, location, containerSize)
            case .ended, .cancelled, .failed:
                parent.onPinchEnded(gestureRecognizer.scale, location, containerSize)
            default:
                break
            }
        }

        @objc func handlePan(_ gestureRecognizer: UIPanGestureRecognizer) {
            let translation = gestureRecognizer.translation(in: gestureRecognizer.view)
            let containerSize = gestureRecognizer.view?.bounds.size ?? .zero
            let size = CGSize(width: translation.x, height: translation.y)

            switch gestureRecognizer.state {
            case .changed:
                parent.onPanChanged(size, containerSize)
            case .ended, .cancelled, .failed:
                parent.onPanEnded(size, containerSize)
            default:
                break
            }
        }

        @objc func handleDoubleTap(_ gestureRecognizer: UITapGestureRecognizer) {
            guard gestureRecognizer.state == .ended else {
                return
            }

            parent.onDoubleTap()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

import SwiftUI

enum MainGridButtonMode {
    case active
    case disabled
    case speech
    case speechActive

    var title: String {
        switch self {
        case .active:
            return "btn active"
        case .disabled:
            return "disabled"
        case .speech:
            return "speech"
        case .speechActive:
            return "spk / active"
        }
    }

    func next() -> MainGridButtonMode {
        switch self {
        case .active:
            return .speech
        case .speech:
            return .speechActive
        case .speechActive:
            return .disabled
        case .disabled:
            return .active
        }
    }

    var sendsBluetooth: Bool {
        switch self {
        case .active, .speechActive:
            return true
        case .disabled, .speech:
            return false
        }
    }

    var speaksText: Bool {
        switch self {
        case .speech, .speechActive:
            return true
        case .active, .disabled:
            return false
        }
    }
}

private struct RepeatingToolbarButton<Label: View>: View {
    let isEnabled: Bool
    let actionVersion: Int
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var repeatTask: Task<Void, Never>?
    @State private var latestAction: (() -> Void)?

    var body: some View {
        Button {
            guard isEnabled else { return }
            ButtonClickFeedback.playIfEnabled()
            latestAction?()
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onLongPressGesture(minimumDuration: 1, maximumDistance: .infinity, pressing: { isPressing in
            guard isEnabled else {
                stopRepeating()
                return
            }

            if isPressing {
                startRepeating()
            } else {
                stopRepeating()
            }
        }, perform: {})
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(.rect)
            .onAppear {
                latestAction = action
            }
            .onChange(of: actionVersion) {
                latestAction = action
            }
            .onDisappear {
                stopRepeating()
            }
    }

    private func startRepeating() {
        repeatTask?.cancel()
        repeatTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            while !Task.isCancelled {
                await MainActor.run {
                    ButtonClickFeedback.playIfEnabled()
                    latestAction?()
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private func stopRepeating() {
        repeatTask?.cancel()
        repeatTask = nil
    }
}

struct MainScreenBottomBar: View {
    private let inactiveButtonBackgroundColor = Color(red: 0.22, green: 0.22, blue: 0.24)
    private let inactiveButtonBorderColor = Color(red: 0.30, green: 0.30, blue: 0.32)
    private let speechActiveModeColor = Color(red: 0.48, green: 0.24, blue: 0.02)
    let availableWidth: CGFloat
    let allowedVisibleBoxCounts: [Int]
    let visibleBoxCount: Int
    let boxFontSize: Double
    let minimumBoxFontSize: Double
    let maximumBoxFontSize: Double
    let speechRecognitionDisplayText: String
    let speechRecognitionDisplayColor: Color
    let isSpeechRecognitionEnabled: Bool
    let mainGridButtonMode: MainGridButtonMode
    let displayMode: FunctionKeyDisplayMode
    let displayModeButtonColor: Color
    let countControlColor: Color
    let fontControlColor: Color
    let speechRecognitionActiveColor: Color
    let bleSendActiveColor: Color
    let onDecreaseVisibleBoxCount: () -> Void
    let onIncreaseVisibleBoxCount: () -> Void
    let onDecreaseBoxFontSize: () -> Void
    let onIncreaseBoxFontSize: () -> Void
    let onToggleSpeechRecognition: () -> Void
    let onCycleMainGridButtonMode: () -> Void
    let onStopSpeech: () -> Void
    let onAdvanceDisplayMode: () -> Void

    var body: some View {
        GeometryReader { _ in
            ViewThatFits(in: .horizontal) {
                bottomBarLayout(
                    isCompact: false,
                    speechBoxWidth: 270,
                    toggleWidth: 110,
                    displayModeWidth: 120
                )

                bottomBarLayout(
                    isCompact: true,
                    speechBoxWidth: 180,
                    toggleWidth: 92,
                    displayModeWidth: 88
                )

                bottomBarLayout(
                    isCompact: true,
                    speechBoxWidth: 120,
                    toggleWidth: 76,
                    displayModeWidth: 72
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .frame(height: 62)
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }

    private func bottomBarLayout(
        isCompact: Bool,
        speechBoxWidth: CGFloat,
        toggleWidth: CGFloat,
        displayModeWidth: CGFloat
    ) -> some View {
        HStack(spacing: isCompact ? 8 : 12) {
            HStack(spacing: isCompact ? 8 : 12) {
                controlTriangle(
                    rotationDegrees: -90,
                    foreground: countControlColor,
                    isEnabled: visibleBoxCount != allowedVisibleBoxCounts.first,
                    actionVersion: visibleBoxCount
                ) {
                    onDecreaseVisibleBoxCount()
                }

                Text("num:\(visibleBoxCount)")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(minWidth: isCompact ? 28 : 32)

                controlTriangle(
                    rotationDegrees: 90,
                    foreground: countControlColor,
                    isEnabled: visibleBoxCount != allowedVisibleBoxCounts.last,
                    actionVersion: visibleBoxCount
                ) {
                    onIncreaseVisibleBoxCount()
                }
            }

            HStack(spacing: isCompact ? 8 : 12) {
                controlTriangle(
                    rotationDegrees: -90,
                    foreground: fontControlColor,
                    isEnabled: boxFontSize > minimumBoxFontSize,
                    actionVersion: Int(boxFontSize)
                ) {
                    onDecreaseBoxFontSize()
                }

                Text("fnt:\(Int(boxFontSize))")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(minWidth: isCompact ? 24 : 32)

                controlTriangle(
                    rotationDegrees: 90,
                    foreground: fontControlColor,
                    isEnabled: boxFontSize < maximumBoxFontSize,
                    actionVersion: Int(boxFontSize)
                ) {
                    onIncreaseBoxFontSize()
                }
            }

            Spacer(minLength: isCompact ? 6 : 12)

            toggleButton(
                title: isSpeechRecognitionEnabled ? "spk rec on" : "spk rec off",
                background: isSpeechRecognitionEnabled ? speechRecognitionActiveColor : inactiveButtonBackgroundColor,
                border: isSpeechRecognitionEnabled ? speechRecognitionActiveColor : inactiveButtonBorderColor,
                action: onToggleSpeechRecognition
            )
            .frame(width: toggleWidth)

            Text(speechRecognitionDisplayText)
                .font(isCompact ? .caption : .body)
                .foregroundStyle(speechRecognitionDisplayColor)
                .opacity(0.6)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: speechBoxWidth, alignment: .leading)
                .padding(.horizontal, isCompact ? 8 : 12)
                .frame(minHeight: isCompact ? 34 : 38)
                .background(Color.black.opacity(0.7))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white, lineWidth: 1)
                }
                .clipShape(.rect(cornerRadius: 6))

            HStack(spacing: 8) {
                stopSpeechButton

                toggleButton(
                    title: mainGridButtonMode.title,
                    background: mainGridButtonModeBackgroundColor,
                    border: mainGridButtonModeBorderColor,
                    action: onCycleMainGridButtonMode
                )
                .frame(width: toggleWidth)
            }

            Button {
                onAdvanceDisplayMode()
            } label: {
                Text(displayMode.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(displayModeButtonColor)
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(displayModeButtonColor, lineWidth: 2)
            }
            .clipShape(.rect(cornerRadius: 12))
            .frame(width: displayModeWidth)
        }
    }

    private func controlTriangle(
        rotationDegrees: Double,
        foreground: Color,
        isEnabled: Bool,
        actionVersion: Int,
        action: @escaping () -> Void
    ) -> some View {
        RepeatingToolbarButton(isEnabled: isEnabled, actionVersion: actionVersion, action: action) {
            Image(systemName: "triangle.fill")
                .font(.system(size: 24))
                .rotationEffect(.degrees(rotationDegrees))
                .frame(width: 24, height: 24)
        }
        .foregroundStyle(foreground)
    }

    private func toggleButton(title: String, background: Color, border: Color, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 50)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(background)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(border, lineWidth: 2)
        }
        .clipShape(.rect(cornerRadius: 12))
    }

    private var stopSpeechButton: some View {
        Button {
            onStopSpeech()
        } label: {
            Image(systemName: "stop.fill")
                .font(.headline)
                .frame(width: 40, height: 50)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isStopSpeechEnabled)
        .foregroundStyle(.white)
        .background(stopSpeechButtonBackgroundColor)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(stopSpeechButtonBorderColor, lineWidth: 2)
        }
        .clipShape(.rect(cornerRadius: 12))
        .opacity(isStopSpeechEnabled ? 1 : 0.55)
    }

    private var stopSpeechButtonBackgroundColor: Color {
        mainGridButtonMode == .speech ? speechRecognitionActiveColor : inactiveButtonBackgroundColor
    }

    private var stopSpeechButtonBorderColor: Color {
        mainGridButtonMode == .speech ? speechRecognitionActiveColor : inactiveButtonBorderColor
    }

    private var isStopSpeechEnabled: Bool {
        mainGridButtonMode == .speech
    }

    private var mainGridButtonModeBackgroundColor: Color {
        switch mainGridButtonMode {
        case .active:
            return bleSendActiveColor
        case .disabled:
            return inactiveButtonBackgroundColor
        case .speech:
            return speechRecognitionActiveColor
        case .speechActive:
            return speechActiveModeColor
        }
    }

    private var mainGridButtonModeBorderColor: Color {
        switch mainGridButtonMode {
        case .active:
            return bleSendActiveColor
        case .disabled:
            return inactiveButtonBorderColor
        case .speech:
            return speechRecognitionActiveColor
        case .speechActive:
            return speechActiveModeColor
        }
    }
}

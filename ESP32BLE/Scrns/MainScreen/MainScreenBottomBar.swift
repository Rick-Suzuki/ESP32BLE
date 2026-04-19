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
            return "spk/active"
        }
    }

    func next() -> MainGridButtonMode {
        switch self {
        case .active:
            return .speechActive
        case .speechActive:
            return .speech
        case .speech:
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

// MARK: - BM:🟩 btm toolbar

struct MainScreenBottomBar: View {
    private let inactiveButtonBackgroundColor = Color(red: 0.22, green: 0.22, blue: 0.24)
    private let inactiveButtonBorderColor = Color(red: 0.30, green: 0.30, blue: 0.32)
    private let speechActiveModeColor = Color(red: 0.48, green: 0.24, blue: 0.02)
    private let rowControlColor = Color.red
    private let columnControlColor = Color.green
    let availableWidth: CGFloat
    let visibleGridDimensions: GridDimensions
    let isGridEditModeEnabled: Bool
    let boxFontSize: Double
    let minimumBoxFontSize: Double
    let maximumBoxFontSize: Double
    let speechRecognitionDisplayText: String
    let speechRecognitionDisplayColor: Color
    let isSpeechRecognitionEnabled: Bool
    let isBluetoothConnected: Bool
    let mainGridButtonMode: MainGridButtonMode
    let displayMode: FunctionKeyDisplayMode
    let displayModeButtonColor: Color
    let fontControlColor: Color
    let speechRecognitionActiveColor: Color
    let bleSendActiveColor: Color
    let onDecreaseRows: () -> Void
    let onIncreaseRows: () -> Void
    let onDecreaseColumns: () -> Void
    let onIncreaseColumns: () -> Void
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
                singleStepTriangle(
                    rotationDegrees: -90,
                    foreground: rowControlColor,
                    isEnabled: visibleGridDimensions.rows > 1,
                    action: onDecreaseRows
                )

                Text("\(visibleGridDimensions.rows)")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(minWidth: isCompact ? 28 : 32)

                singleStepTriangle(
                    rotationDegrees: 90,
                    foreground: rowControlColor,
                    isEnabled: visibleGridDimensions.rows < 12,
                    action: onIncreaseRows
                )
            }

            HStack(spacing: isCompact ? 8 : 12) {
                singleStepTriangle(
                    rotationDegrees: -90,
                    foreground: columnControlColor,
                    isEnabled: visibleGridDimensions.columns > 1,
                    action: onDecreaseColumns
                )

                Text("\(visibleGridDimensions.columns)")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(minWidth: isCompact ? 28 : 32)

                singleStepTriangle(
                    rotationDegrees: 90,
                    foreground: columnControlColor,
                    isEnabled: visibleGridDimensions.columns < 12,
                    action: onIncreaseColumns
                )
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

                ZStack {
                    Rectangle()
                        .fill(Color.black.opacity(0.001))

                    Text("\(Int(boxFontSize))")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(width: isCompact ? 40 : 48, alignment: .center)
                .contentShape(.rect)
                .onTapGesture {}

                controlTriangle(
                    rotationDegrees: 90,
                    foreground: fontControlColor,
                    isEnabled: boxFontSize < maximumBoxFontSize,
                    actionVersion: Int(boxFontSize)
                ) {
                    onIncreaseBoxFontSize()
                }
            }

            HStack(spacing: isCompact ? 8 : 12) {
                bluetoothIndicator
            }
            .padding(.leading, 100)

            Spacer(minLength: isCompact ? 6 : 12)

            toggleButton(
                title: isSpeechRecognitionEnabled ? "spk rec on" : "spk rec off",
                background: isSpeechRecognitionEnabled ? speechRecognitionActiveColor : inactiveButtonBackgroundColor,
                border: isSpeechRecognitionEnabled ? speechRecognitionActiveColor : inactiveButtonBorderColor,
                isEnabled: !isGridEditModeEnabled,
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
                    isEnabled: !isGridEditModeEnabled,
                    action: onCycleMainGridButtonMode
                )
                .frame(width: toggleWidth)
            }
			//
			//----------------------------------------
			//
				Button {
					onAdvanceDisplayMode()
				} label: {
				Text(displayMode.title)
					.lineLimit(1)
					.minimumScaleFactor(0.7)
					.frame(maxWidth: .infinity, minHeight: 50)
					.foregroundStyle(.white)
					.background(
						RoundedRectangle(cornerRadius: 12)
							.fill(displayModeButtonColor.opacity(0.7))
					)
					.overlay(
						RoundedRectangle(cornerRadius: 12)
							.stroke(displayModeButtonColor, lineWidth: 2)
					)
					.clipShape(RoundedRectangle(cornerRadius: 12))
					}
					.opacity(0.7)
					.buttonStyle(.plain)
					.frame(width: displayModeWidth)
				//
				//----------------------------------------
			//
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

    private func singleStepTriangle(
        rotationDegrees: Double,
        foreground: Color,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard isEnabled else { return }
            ButtonClickFeedback.playIfEnabled()
            action()
        } label: {
            Image(systemName: "triangle.fill")
                .font(.system(size: 24))
                .rotationEffect(.degrees(rotationDegrees))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .foregroundStyle(foreground)
        .opacity(isEnabled ? 1 : 0.35)
    }

    private func toggleButton(title: String, background: Color, border: Color, isEnabled: Bool = true, action: @escaping () -> Void) -> some View {
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
        .disabled(!isEnabled)
        .foregroundStyle(.white)
        .background(background)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(border, lineWidth: 2)
        }
        .clipShape(.rect(cornerRadius: 12))
			.opacity(isEnabled ? 0.7 : 0.35)
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
        !isGridEditModeEnabled && mainGridButtonMode == .speech
    }

    private var bluetoothIndicator: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            Circle()
                .fill(bluetoothIndicatorColor(at: context.date))
                .frame(width: 24, height: 24)
                .overlay {
                    Circle()
                        .stroke(Color.white, lineWidth: 1.5)
                }
        }
        .frame(width: 24, height: 24)
    }

    private func bluetoothIndicatorColor(at date: Date) -> Color {
        guard !isBluetoothConnected else {
            guard isGridEditModeEnabled else {
                return .blue
            }

            return isIndicatorPulseVisible(at: date, activeFraction: 0.5) ? .blue : .black
        }

        return isIndicatorPulseVisible(at: date, activeFraction: 0.1) ? .red : .black
    }

    private func isIndicatorPulseVisible(at date: Date, activeFraction: Double) -> Bool {
        let normalizedFraction = min(max(activeFraction, 0), 1)
        let seconds = date.timeIntervalSinceReferenceDate
        let fractionalSecond = seconds - floor(seconds)
        return fractionalSecond < normalizedFraction
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

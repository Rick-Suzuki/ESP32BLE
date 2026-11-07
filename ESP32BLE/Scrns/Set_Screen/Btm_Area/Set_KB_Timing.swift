import SwiftUI

struct SettingsKeyboardTimingSection: View {
    private let maximumSpeechRecognitionAutoOffMinutes = 31
    private let iPadTimingRowsMaxWidth: CGFloat = 520
    let timingLabelWidth: Double
    @Binding var keyboardTimingOnMs: Double
    @Binding var keyboardTimingOffMs: Double
    @Binding var speechRecognitionAutoOffMinutes: Int
    @Binding var opacitySliderValue: Double
    @Binding var documentEditorFontSize: CGFloat
    @Binding var templateViewerFontSize: CGFloat
    let imageControlButtons: AnyView
    let navigationControlsTitle: String
    let isNavigationControlsActive: Bool
    let isImageControlsActive: Bool
    let isDocumentEditorControlsActive: Bool
    let isTemplateViewerControlsActive: Bool
    let onImageOpacityEditingChanged: (Bool) -> Void
    let isMacMode: Bool
    let isTimingControlsEnabled: Bool
    let isTestEnabled: Bool
    let onSetAndTest: () -> Void

    private var bodyButtonCornerRadius: CGFloat {
        isPad ? 18 : 10
    }

    var body: some View {
        VStack(alignment: .center, spacing: 5) {
            customKeyboardTimingControls

            if isPad {
                HStack(alignment: .top, spacing: 12) {
                    speechRecognitionAutoOffRow
                        .frame(maxWidth: iPadTimingRowsMaxWidth, alignment: .leading)

                    Spacer(minLength: 0)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    speechRecognitionAutoOffRow

                    Spacer(minLength: 0)
                }
            }

            if !isPad {
                HStack(alignment: .top, spacing: 12) {
                    iPhoneImageControls

                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var customKeyboardTimingControls: some View {
        VStack(alignment: .center, spacing: 5) {
            HStack(spacing: 12) {
                Text(timingHeading)
                    .font(settingsCompactControlFont)

                setAndTestButton
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 10) {
                    sliderRow(title: "on", value: $keyboardTimingOnMs, range: 0...1000)
                    sliderRow(title: "off", value: $keyboardTimingOffMs, range: 0...3000)
                }
                .frame(maxWidth: iPadTimingRowsMaxWidth, alignment: .leading)

                Spacer(minLength: 0)
            }
            .disabled(!isTimingControlsEnabled)
        }
    }

    @ViewBuilder
    private var setAndTestButton: some View {
        if isPad {
            Button(testButtonTitle) {
                ButtonClickFeedback.playIfEnabled()
                onSetAndTest()
            }
            .font(settingsCompactControlFont)
            .buttonStyle(.borderedProminent)
            .tint(Color.red.opacity(0.5))
            .disabled(!isTestEnabled)
        } else {
            Button(testButtonTitle) {
                ButtonClickFeedback.playIfEnabled()
                onSetAndTest()
            }
            .buttonStyle(.plain)
            .font(settingsCompactControlFont)
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Color.red.opacity(0.5))
            .clipShape(.rect(cornerRadius: bodyButtonCornerRadius))
            .disabled(!isTestEnabled)
        }
    }

    private var timingHeading: String {
        if isMacMode {
            return "test Mac"
        }

        return isPad ? "custom kb timing" : "custom\nkb timing"
    }

    private var testButtonTitle: String {
        isMacMode ? "test" : "set & test"
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 9) {
            Text(title)
                .font(settingsCompactControlFont)
                .foregroundStyle(.primary)
                .frame(width: timingLabelWidth, alignment: .trailing)
                .opacity(timingContentOpacity)

            if isPad {
                Button {
                    ButtonClickFeedback.playIfEnabled()
                    value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1)
                } label: {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 26))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .disabled(value.wrappedValue <= range.lowerBound)
                .opacity(timingContentOpacity)
            }

				VStack(spacing: isPad ? -10 : 0) {
                Text("\(Int(value.wrappedValue)) ms")
                    .font(settingsCompactControlFont)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .opacity(timingContentOpacity)

                Slider(value: value, in: range, step: 10)
                    .tint(timingSliderTint)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)

            if isPad {
                Button {
                    ButtonClickFeedback.playIfEnabled()
                    value.wrappedValue = min(range.upperBound, value.wrappedValue + 1)
                } label: {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 26))
                        .rotationEffect(.degrees(90))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .disabled(value.wrappedValue >= range.upperBound)
                .opacity(timingContentOpacity)
            }
        }
    }

    private var speechRecognitionAutoOffRow: some View {
        HStack(spacing: 9) {
            Text("rec off")
                .font(settingsCompactControlFont)
                .foregroundStyle(.white)
                .frame(width: timingLabelWidth, alignment: .trailing)

            if isPad {
                Button {
                    ButtonClickFeedback.playIfEnabled()
                    speechRecognitionAutoOffMinutes = max(1, speechRecognitionAutoOffMinutes - 1)
                } label: {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 26))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .disabled(speechRecognitionAutoOffMinutes <= 1)
            }

            VStack(spacing: 0) {
                Text(speechRecognitionAutoOffDisplayText)
                    .font(settingsCompactControlFont)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)

                Slider(
                    value: Binding(
                        get: { Double(speechRecognitionAutoOffMinutes) },
                        set: { speechRecognitionAutoOffMinutes = Int($0.rounded()) }
                    ),
                    in: 1...Double(maximumSpeechRecognitionAutoOffMinutes),
                    step: 1
                )
                .tint(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)

            if isPad {
                Button {
                    ButtonClickFeedback.playIfEnabled()
                    speechRecognitionAutoOffMinutes = min(maximumSpeechRecognitionAutoOffMinutes, speechRecognitionAutoOffMinutes + 1)
                } label: {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 26))
                        .rotationEffect(.degrees(90))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .disabled(speechRecognitionAutoOffMinutes >= maximumSpeechRecognitionAutoOffMinutes)
            }
        }
    }

    private var iPhoneImageControls: some View {
        HStack(spacing: 9) {
            Text(navigationControlsTitle)
                .font(settingsCompactControlFont)
                .foregroundStyle(
                    isNavigationControlsActive ? .white : SettingsImageControlAppearance.disabledColor
                )
                .frame(width: timingLabelWidth, alignment: .trailing)

            VStack(alignment: .leading, spacing: 6) {
                imageControlButtons

                navigationSlider
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var navigationSlider: some View {
        if isDocumentEditorControlsActive {
            Slider(value: $documentEditorFontSize, in: 10...72, step: 1)
                .tint(.cyan)
        } else if isTemplateViewerControlsActive {
            Slider(value: $templateViewerFontSize, in: 10...72, step: 1)
                .tint(.cyan)
        } else {
            Slider(
                value: $opacitySliderValue,
                in: 0...1,
                onEditingChanged: onImageOpacityEditingChanged
            )
                .tint(
                    isImageControlsActive ? .cyan : SettingsImageControlAppearance.disabledColor
                )
                .disabled(!isImageControlsActive)
        }
    }

    private var speechRecognitionAutoOffDisplayText: String {
        speechRecognitionAutoOffMinutes >= maximumSpeechRecognitionAutoOffMinutes
            ? "Never"
            : "\(speechRecognitionAutoOffMinutes) min"
    }

    private var settingsCompactControlFont: Font {
        isPad ? .headline : .system(size: 13, weight: .semibold)
    }

    private var timingContentOpacity: Double {
        isTimingControlsEnabled ? 1 : 0.45
    }

    private var timingSliderTint: Color {
        isTimingControlsEnabled ? .white : SettingsImageControlAppearance.disabledColor
    }
}

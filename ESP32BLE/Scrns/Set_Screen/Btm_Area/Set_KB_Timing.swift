import SwiftUI

struct SettingsKeyboardTimingSection: View {
    private let maximumSpeechRecognitionAutoOffMinutes = 31
    private let iPadTimingRowsMaxWidth: CGFloat = 520
    let timingLabelWidth: Double
    @Binding var keyboardTimingOnMs: Double
    @Binding var keyboardTimingOffMs: Double
    @Binding var speechRecognitionAutoOffMinutes: Int
    @Binding var opacitySliderValue: Double
    let imageControlButtons: AnyView
    let isEnabled: Bool
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
                speechRecognitionAutoOffRow
            }

            if !isPad {
                iPhoneImageControls
            }
        }
    }

    private var customKeyboardTimingControls: some View {
        VStack(alignment: .center, spacing: 5) {
            HStack(spacing: 12) {
                Text(isPad ? "custom kb timing" : "custom\nkb timing")
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
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }

    @ViewBuilder
    private var setAndTestButton: some View {
        if isPad {
            Button("set & test") {
                ButtonClickFeedback.playIfEnabled()
                onSetAndTest()
            }
            .font(settingsCompactControlFont)
            .buttonStyle(.borderedProminent)
            .tint(Color.red.opacity(0.5))
        } else {
            Button("set & test") {
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
        }
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 4) {
            Text(isPad ? title : title.uppercased())
                .font(settingsCompactControlFont)
                .foregroundStyle(.primary)
                .frame(width: timingLabelWidth, alignment: .trailing)

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
            }

				VStack(spacing: isPad ? -10 : 0) {
                Text("\(Int(value.wrappedValue)) ms")
                    .font(settingsCompactControlFont)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)

                Slider(value: value, in: range, step: 10)
                    .tint(.white)
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
            }
        }
    }

    private var speechRecognitionAutoOffRow: some View {
        HStack(spacing: 4) {
            Text(isPad ? "rec off" : "REC OFF")
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
        HStack(spacing: 4) {
            Text("IMAGE")
                .font(settingsCompactControlFont)
                .foregroundStyle(.white)
                .frame(width: timingLabelWidth, alignment: .trailing)

            VStack(alignment: .leading, spacing: 6) {
                imageControlButtons

                Slider(value: $opacitySliderValue, in: 0...1)
                    .tint(.cyan)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
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
}

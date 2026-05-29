import SwiftUI

struct SettingsKeyboardTimingSection: View {
    private let maximumSpeechRecognitionAutoOffMinutes = 31
    let timingLabelWidth: Double
    @Binding var keyboardTimingOnMs: Double
    @Binding var keyboardTimingOffMs: Double
    @Binding var speechRecognitionAutoOffMinutes: Int
    let onSetAndTest: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 5) {
            HStack(spacing: 12) {
                Text("custom kb timing")
                    .font(settingsCompactControlFont)

                Button("set & test") {
                    ButtonClickFeedback.playIfEnabled()
                    onSetAndTest()
                }
                .font(settingsCompactControlFont)
                .buttonStyle(.borderedProminent)
                .tint(Color.red.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 10) {
                    sliderRow(title: "on", value: $keyboardTimingOnMs, range: 0...1000)
                    sliderRow(title: "off", value: $keyboardTimingOffMs, range: 0...3000)
                    speechRecognitionAutoOffRow
                }
                .frame(maxWidth: 520, alignment: .leading)

                Spacer(minLength: 0)
            }
        }
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(settingsCompactControlFont)
                .foregroundStyle(.primary)
                .frame(width: timingLabelWidth, alignment: .trailing)

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

    private var speechRecognitionAutoOffRow: some View {
        HStack(spacing: 4) {
            Text("rec off")
                .font(settingsCompactControlFont)
                .foregroundStyle(.white)
                .frame(width: timingLabelWidth, alignment: .trailing)

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

    private var speechRecognitionAutoOffDisplayText: String {
        speechRecognitionAutoOffMinutes >= maximumSpeechRecognitionAutoOffMinutes
            ? "Never"
            : "\(speechRecognitionAutoOffMinutes) min"
    }

    private var settingsCompactControlFont: Font {
        isPad ? .headline : .system(size: 14, weight: .semibold)
    }
}

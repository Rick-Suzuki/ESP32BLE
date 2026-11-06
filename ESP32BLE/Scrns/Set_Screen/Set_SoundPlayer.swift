import SwiftUI
import UIKit

struct SettingsSoundPlayerView: View {
    let title: String
    let playbackPosition: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    let canGoPrevious: Bool
    let canGoNext: Bool
    let backgroundImageURL: URL?
    let usesCompactLayout: Bool
    let isPlaybackPrepared: Bool
    let isAutoStartEnabled: Bool
    let isRepeatEnabled: Bool
    let isRandomEnabled: Bool
    let onSeek: (TimeInterval) -> Void
    let onPrevious: () -> Void
    let onTogglePlayback: () -> Void
    let onNext: () -> Void
    let onSetAutoStart: (Bool) -> Void
    let onToggleRepeat: () -> Void
    let onToggleRandom: () -> Void

    @State private var sliderPosition: TimeInterval = 0
    @State private var isSeeking = false
    @State private var backgroundImage: UIImage?

    private var controlSize: CGFloat {
        usesCompactLayout ? 32 : 46
    }

    private var titleFont: Font {
        usesCompactLayout ? .system(size: 14, weight: .semibold) : .title3.weight(.semibold)
    }

    private var timeFont: Font {
        usesCompactLayout ? .system(size: 10, design: .monospaced) : .system(size: 13, design: .monospaced)
    }

    private var safeDuration: TimeInterval {
        duration.isFinite && duration > 0 ? duration : 0
    }

    private var canControlPlayback: Bool {
        isPlaybackPrepared && safeDuration > 0
    }

    var body: some View {
        Group {
            if usesCompactLayout {
                compactPlayerBody
            } else {
                iPadPlayerBody
            }
        }
        .task(id: backgroundImageURL?.path) {
            backgroundImage = backgroundImageURL.flatMap { UIImage(contentsOfFile: $0.path) }
        }
        .onAppear {
            sliderPosition = clampedPosition(playbackPosition)
        }
        .onChange(of: playbackPosition) { _, newPosition in
            guard !isSeeking else { return }
            sliderPosition = clampedPosition(newPosition)
        }
        .onChange(of: safeDuration) { _, _ in
            sliderPosition = clampedPosition(sliderPosition)
        }
    }

    private var compactPlayerBody: some View {
        GeometryReader { geometry in
            ZStack {
                playerBackground

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.22),
                        Color.black.opacity(0.82)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(spacing: 8) {
                    Text(title)
                        .font(titleFont)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Spacer(minLength: 0)

                    Slider(
                        value: $sliderPosition,
                        in: 0...max(safeDuration, 1),
                        onEditingChanged: handleSliderEditingChanged
                    )
                    .tint(.cyan)
                    .disabled(!canControlPlayback)
                    .accessibilityLabel("Playback position")
                    .accessibilityValue("\(formattedTime(sliderPosition)) of \(formattedTime(safeDuration))")

                    HStack {
                        Text(formattedTime(sliderPosition))
                        Spacer()
                        Text(formattedTime(safeDuration))
                    }
                    .font(timeFont)
                    .foregroundStyle(.white.opacity(0.9))

                    transportControls(spacing: 13)

                    HStack(spacing: 8) {
                        disabledFeatureLabel(title: "Auto Start", systemName: "arrow.right.circle")
                        disabledFeatureLabel(title: "Random", systemName: "shuffle")
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color.black)
    }

    private var iPadPlayerBody: some View {
        Color.black
            .overlay { playerBackground }
            .overlay {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.22),
                        Color.black.opacity(0.82)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                iPadPlayerControls
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .overlay {
                Rectangle()
                    .stroke(Color.white, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }

    @ViewBuilder
    private var playerBackground: some View {
        if let backgroundImage {
            Image(uiImage: backgroundImage)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            Color.black
        }
    }

    private var iPadPlayerControls: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .center)

            Slider(
                value: $sliderPosition,
                in: 0...max(safeDuration, 1),
                onEditingChanged: handleSliderEditingChanged
            )
            .tint(.cyan)
            .disabled(!canControlPlayback)
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(formattedTime(sliderPosition)) of \(formattedTime(safeDuration))")

            iPadControlRow
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private var iPadControlRow: some View {
        GeometryReader { geometry in
            let metrics = iPadControlMetrics(for: geometry.size.width)
            let sideWidth = max(
                0,
                (geometry.size.width - metrics.transportWidth - metrics.transportClearance) / 2
            )

            ZStack {
                HStack(spacing: 0) {
                    iPadAutoStartControl(metrics: metrics)
                        .frame(width: sideWidth, alignment: .leading)

                    Color.clear
                        .frame(width: metrics.transportWidth + metrics.transportClearance)

                    iPadRightControls(metrics: metrics)
                        .frame(width: sideWidth, alignment: .trailing)
                }

                HStack {
                    iPadRepeatControl(metrics: metrics)
                        .frame(width: sideWidth, alignment: .trailing)
                    Spacer(minLength: 0)
                }

                iPadTransportControls(metrics: metrics)
            }
        }
        .frame(height: controlSize * 1.28)
    }

    private func iPadTransportControls(metrics: IPadControlMetrics) -> some View {
        HStack(spacing: metrics.transportSpacing) {
            iPadTransportButton(
                systemName: "backward.end.fill",
                accessibilityLabel: "Previous sound",
                isEnabled: canGoPrevious,
                size: metrics.transportButtonSize,
                action: onPrevious
            )

            iPadTransportButton(
                systemName: isPlaying ? "pause.fill" : "play.fill",
                accessibilityLabel: isPlaying ? "Pause" : "Play",
                isEnabled: canControlPlayback,
                size: metrics.transportButtonSize,
                action: onTogglePlayback
            )

            iPadTransportButton(
                systemName: "forward.end.fill",
                accessibilityLabel: "Next sound",
                isEnabled: canGoNext,
                size: metrics.transportButtonSize,
                action: onNext
            )
        }
    }

    private func iPadAutoStartControl(metrics: IPadControlMetrics) -> some View {
        HStack(spacing: 6) {
            Text("Auto Start")
                .font(metrics.modeLabelFont)
                .foregroundStyle(.white.opacity(0.9))

            Toggle("Auto Start", isOn: Binding(
                get: { isAutoStartEnabled },
                set: onSetAutoStart
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(.cyan)
            .scaleEffect(metrics.autoStartScale)
            .accessibilityLabel("Auto Start")
        }
    }

    private func iPadRepeatControl(metrics: IPadControlMetrics) -> some View {
        iPadModeButton(
            systemName: "repeat",
            accessibilityLabel: "Repeat playback",
            isEnabled: isRepeatEnabled,
            size: metrics.transportButtonSize,
            action: onToggleRepeat
        )
    }

    private func iPadRightControls(metrics: IPadControlMetrics) -> some View {
        HStack(spacing: metrics.randomTimeSpacing) {
            iPadModeButton(
                systemName: "shuffle",
                accessibilityLabel: "Random playback",
                isEnabled: isRandomEnabled,
                size: metrics.transportButtonSize,
                action: onToggleRandom
            )

            Text("\(formattedTimeWithHundredths(sliderPosition)) of \(formattedTimeWithHundredths(safeDuration))")
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func iPadModeButton(
        systemName: String,
        accessibilityLabel: String,
        isEnabled: Bool,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(isEnabled ? Color.black : Color.white.opacity(0.85))
                .frame(width: size, height: size)
                .background(
                    isEnabled ? Color.cyan : Color.black.opacity(0.42),
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isEnabled ? "On" : "Off")
    }

    private func iPadTransportButton(
        systemName: String,
        accessibilityLabel: String,
        isEnabled: Bool,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard isEnabled else { return }
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(isEnabled ? Color.white : Color.white.opacity(0.35))
                .frame(width: size, height: size)
                .background(Color.white.opacity(0.16), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }

    private func transportControls(spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            playerButton(
                systemName: "backward.end.fill",
                accessibilityLabel: "Previous sound",
                isEnabled: canGoPrevious,
                action: onPrevious
            )

            playerButton(
                systemName: isPlaying ? "pause.fill" : "play.fill",
                accessibilityLabel: isPlaying ? "Pause" : "Play",
                isEnabled: canControlPlayback,
                isPrimary: true,
                action: onTogglePlayback
            )

            playerButton(
                systemName: "forward.end.fill",
                accessibilityLabel: "Next sound",
                isEnabled: canGoNext,
                action: onNext
            )
        }
    }

    private var disabledRandomButton: some View {
        Button(action: {}) {
            Image(systemName: "shuffle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: 36, height: 28)
                .background(Color.black.opacity(0.42), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(true)
        .accessibilityLabel("Random, unavailable")
    }

    private func playerButton(
        systemName: String,
        accessibilityLabel: String,
        isEnabled: Bool,
        isPrimary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard isEnabled else { return }
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: isPrimary ? controlSize * 0.52 : controlSize * 0.42, weight: .semibold))
                .foregroundStyle(isEnabled ? Color.white : Color.white.opacity(0.35))
                .frame(
                    width: isPrimary ? controlSize * 1.28 : controlSize,
                    height: isPrimary ? controlSize * 1.28 : controlSize
                )
                .background(
                    isPrimary ? Color.cyan.opacity(isEnabled ? 0.76 : 0.25) : Color.white.opacity(0.16),
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }

    private func disabledFeatureLabel(title: String, systemName: String) -> some View {
        Label(title, systemImage: systemName)
            .font(usesCompactLayout ? .caption2 : .caption)
            .foregroundStyle(.white.opacity(0.45))
            .padding(.horizontal, usesCompactLayout ? 7 : 10)
            .padding(.vertical, usesCompactLayout ? 4 : 6)
            .background(Color.black.opacity(0.42), in: Capsule())
            .accessibilityLabel("\(title), unavailable")
    }

    private func disabledFeatureButton(title: String, systemName: String) -> some View {
        Button(action: {}) {
            Label(title, systemImage: systemName)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.42), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(true)
        .accessibilityLabel("\(title), unavailable")
    }

    private func handleSliderEditingChanged(_ isEditing: Bool) {
        isSeeking = isEditing
        guard !isEditing else { return }
        let targetPosition = clampedPosition(sliderPosition)
        sliderPosition = targetPosition
        onSeek(targetPosition)
    }

    private func clampedPosition(_ position: TimeInterval) -> TimeInterval {
        guard position.isFinite else { return 0 }
        return min(max(position, 0), safeDuration)
    }

    private func formattedTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time > 0 else { return "0:00" }
        let totalSeconds = Int(time.rounded(.down))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func formattedTimeWithHundredths(_ time: TimeInterval) -> String {
        guard time.isFinite, time > 0 else { return "00:00.00" }
        let totalHundredths = Int((time * 100).rounded(.down))
        let minutes = totalHundredths / 6_000
        let seconds = (totalHundredths / 100) % 60
        let hundredths = totalHundredths % 100
        return String(format: "%02d:%02d.%02d", minutes, seconds, hundredths)
    }

    private struct IPadControlMetrics {
        let autoStartScale: CGFloat
        let modeLabelFont: Font
        let transportButtonSize: CGFloat
        let transportSpacing: CGFloat
        let transportClearance: CGFloat
        let randomTimeSpacing: CGFloat

        var transportWidth: CGFloat {
            (transportButtonSize * 3) + (transportSpacing * 2)
        }
    }

    private func iPadControlMetrics(for width: CGFloat) -> IPadControlMetrics {
        if width < 640 {
            return IPadControlMetrics(
                autoStartScale: 0.9,
                modeLabelFont: .caption.weight(.medium),
                transportButtonSize: 42,
                transportSpacing: 10,
                transportClearance: 28,
                randomTimeSpacing: 6
            )
        }

        return IPadControlMetrics(
            autoStartScale: 1.0,
            modeLabelFont: .callout.weight(.medium),
            transportButtonSize: 48,
            transportSpacing: 14,
            transportClearance: 36,
            randomTimeSpacing: 10
        )
    }
}

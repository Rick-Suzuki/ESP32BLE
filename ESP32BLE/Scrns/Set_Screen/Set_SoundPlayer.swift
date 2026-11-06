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
    let onSeek: (TimeInterval) -> Void
    let onPrevious: () -> Void
    let onTogglePlayback: () -> Void
    let onNext: () -> Void

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
        safeDuration > 0
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
                playerControls
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
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

    @ViewBuilder
    private var playerControls: some View {
        iPadPlayerControls
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

            Text("\(formattedTime(sliderPosition)) of \(formattedTime(safeDuration))")
                .font(timeFont)
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .trailing)

            transportControls(spacing: 48)

            ZStack {
                HStack {
                    disabledFeatureButton(title: "Auto Start", systemName: "arrow.right.circle")
                    Spacer(minLength: 0)
                }

                disabledRandomButton
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 14)
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
}

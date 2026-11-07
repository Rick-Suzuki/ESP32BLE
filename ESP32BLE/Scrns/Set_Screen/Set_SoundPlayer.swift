import SwiftUI
import UIKit
import Observation

private enum SettingsSoundPlayerButtonStyle {
    static let enabledToggleBackground = Color.cyan.opacity(0.76)
    static let iPhoneToggleOffBackground = Color.gray.opacity(0.72)
    static let iPadToggleOffBackground = Color.black.opacity(0.42)
    static let iPadToggleOffForeground = Color.white.opacity(0.45)
    static let transportBackground = Color.white.opacity(0.16)
}

@Observable
@MainActor
final class SettingsSoundPlaybackPresentation {
    var position: TimeInterval = 0
    var duration: TimeInterval = 0
    var isPlaying = false
}

struct SettingsSoundPlayerView: View {
    private struct BackgroundImageRequest {
        let id: String
        let generation: UUID
        let url: URL
        let targetPixelDimension: Int
    }

    let title: String
    let playbackPresentation: SettingsSoundPlaybackPresentation
    let canGoPrevious: Bool
    let canGoNext: Bool
    let backgroundImageURL: URL?
    let backgroundImageOpacity: Double
    let usesCompactLayout: Bool
    let isPlaybackPrepared: Bool
    let isAutoStartEnabled: Bool
    let isRepeatEnabled: Bool
    let isRandomEnabled: Bool
    let isAutoRandomBackgroundEnabled: Bool
    let onSeek: (TimeInterval) -> Void
    let onPrevious: () -> Void
    let onTogglePlayback: () -> Void
    let onNext: () -> Void
    let onSetAutoStart: (Bool) -> Void
    let onToggleRepeat: () -> Void
    let onToggleRandom: () -> Void
    let onToggleAutoRandomBackground: () -> Void

    @Environment(\.displayScale) private var displayScale
    @State private var sliderPosition: TimeInterval = 0
    @State private var isSeeking = false
    @State private var backgroundImage: UIImage?
    @State private var pendingBackgroundImageRequest: BackgroundImageRequest?
    @State private var backgroundImageLoadingTask: Task<Void, Never>?
    @State private var backgroundImageLoadingWorkerID: UUID?
    @State private var backgroundImageRequestGeneration = UUID()
    @State private var backgroundImageTargetPixelDimension = 0

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
        playbackPresentation.duration.isFinite && playbackPresentation.duration > 0 ? playbackPresentation.duration : 0
    }

    private var canControlPlayback: Bool {
        isPlaybackPrepared && safeDuration > 0
    }

    private var clampedBackgroundImageOpacity: Double {
        min(max(backgroundImageOpacity, 0), 1)
    }

    var body: some View {
        Group {
            if usesCompactLayout {
                compactPlayerBody
            } else {
                iPadPlayerBody
            }
        }
        .onAppear {
            sliderPosition = clampedPosition(playbackPresentation.position)
        }
        .onChange(of: playbackPresentation.position) { _, newPosition in
            guard !isSeeking else { return }
            sliderPosition = clampedPosition(newPosition)
        }
        .onChange(of: safeDuration) { _, _ in
            sliderPosition = clampedPosition(sliderPosition)
        }
        .onDisappear {
            backgroundImageLoadingTask?.cancel()
            backgroundImageLoadingTask = nil
            backgroundImageLoadingWorkerID = nil
            pendingBackgroundImageRequest = nil
        }
    }

    private var compactPlayerBody: some View {
        GeometryReader { geometry in
            let metrics = iPhonePlayerMetrics(for: geometry.size)

            ZStack {
                playerBackground

                HStack(spacing: metrics.topControlSpacing) {
                    iPhoneModeButton(
                        systemName: "shuffle",
                        accessibilityLabel: "Random playback",
                        isEnabled: isRandomEnabled,
                        size: metrics.modeButtonSize,
                        action: onToggleRandom
                    )

                    iPhoneModeButton(
                        systemName: "photo.artframe",
                        accessibilityLabel: "Automatic random background",
                        isEnabled: isAutoRandomBackgroundEnabled,
                        size: metrics.modeButtonSize,
                        action: onToggleAutoRandomBackground
                    )
                }
                .padding(.leading, metrics.horizontalInset)
                .padding(.top, metrics.topInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Text(backgroundImageURL?.lastPathComponent ?? "No image")
                    .font(.system(size: metrics.filenameFontSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .truncationMode(.tail)
                    .padding(.leading, metrics.filenameLeadingInset)
                    .padding(.trailing, metrics.horizontalInset)
                    .padding(.top, metrics.topInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                VStack(spacing: metrics.sliderToControlsSpacing) {
                    VStack(alignment: .trailing, spacing: metrics.timeToSliderSpacing) {
                        Text("\(formattedIPhoneTimeWithHundredths(sliderPosition)) of \(formattedIPhoneTimeWithHundredths(safeDuration))")
                            .font(.system(size: metrics.timeFontSize, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .offset(y: metrics.timeToSliderOffset)

                        Slider(
                            value: $sliderPosition,
                            in: 0...max(safeDuration, 1),
                            onEditingChanged: handleSliderEditingChanged
                        )
                        .tint(.cyan)
                        .disabled(!canControlPlayback)
                        .accessibilityLabel("Playback position")
                        .accessibilityValue("\(formattedTime(sliderPosition)) of \(formattedTime(safeDuration))")
                    }

                    HStack(spacing: metrics.transportSpacing) {
                        iPhoneTransportButton(
                            systemName: "backward.end.fill",
                            accessibilityLabel: "Previous sound",
                            isEnabled: canGoPrevious,
                            size: metrics.modeButtonSize,
                            action: onPrevious
                        )

                        iPhoneTransportButton(
                            systemName: playbackPresentation.isPlaying ? "pause.fill" : "play.fill",
                            accessibilityLabel: playbackPresentation.isPlaying ? "Pause" : "Play",
                            isEnabled: canControlPlayback,
                            size: metrics.modeButtonSize,
                            isPrimary: true,
                            action: onTogglePlayback
                        )

                        iPhoneTransportButton(
                            systemName: "forward.end.fill",
                            accessibilityLabel: "Next sound",
                            isEnabled: canGoNext,
                            size: metrics.modeButtonSize,
                            action: onNext
                        )

                        Spacer(minLength: 0)

                        SettingsAutoStartButton(
                            isEnabled: isAutoStartEnabled,
                            size: metrics.modeButtonSize,
                            offBackground: SettingsSoundPlayerButtonStyle.iPhoneToggleOffBackground,
                            action: { onSetAutoStart(!isAutoStartEnabled) }
                        )

                        iPhoneModeButton(
                            systemName: "repeat",
                            accessibilityLabel: "Repeat playback",
                            isEnabled: isRepeatEnabled,
                            size: metrics.modeButtonSize,
                            action: onToggleRepeat
                        )
                    }
                }
                .padding(.horizontal, metrics.horizontalInset)
                .padding(.bottom, metrics.bottomInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color.black)
        .overlay {
            Rectangle()
                .stroke(Color.white, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private struct IPhonePlayerMetrics {
        let horizontalInset: CGFloat
        let topInset: CGFloat
        let bottomInset: CGFloat
        let topControlSpacing: CGFloat
        let modeButtonSize: CGFloat
        let transportSpacing: CGFloat
        let timeToSliderSpacing: CGFloat
        let timeToSliderOffset: CGFloat
        let sliderToControlsSpacing: CGFloat
        let filenameLeadingInset: CGFloat
        let filenameFontSize: CGFloat
        let timeFontSize: CGFloat
    }

    private func iPhonePlayerMetrics(for size: CGSize) -> IPhonePlayerMetrics {
        let safeWidth = max(size.width, 0)
        let safeHeight = max(size.height, 0)
        let modeButtonSize = min(max(min(safeWidth * 0.13, safeHeight * 0.22), 28), 40)

        return IPhonePlayerMetrics(
            horizontalInset: min(max(safeWidth * 0.025, 6), 12),
            topInset: min(max(safeHeight * 0.04, 4), 8),
            bottomInset: min(max(safeHeight * 0.04, 4), 8),
            topControlSpacing: min(max(safeWidth * 0.025, 4), 8),
            modeButtonSize: modeButtonSize,
            transportSpacing: min(max(safeWidth * 0.035, 7), 14),
            timeToSliderSpacing: min(max(safeHeight * 0.005, 0), 2),
            timeToSliderOffset: min(max(safeHeight * 0.06, 8), 12),
            sliderToControlsSpacing: min(max(safeHeight * 0.03, 3), 6),
            filenameLeadingInset: min(max(safeWidth * 0.025, 6), 12) + (modeButtonSize * 2) + min(max(safeWidth * 0.025, 4), 8) + min(max(safeWidth * 0.04, 8), 16),
            filenameFontSize: min(max(safeHeight * 0.075, 11), 15),
            timeFontSize: min(max(safeHeight * 0.065, 10), 13)
        )
    }

    private func iPhoneModeButton(
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
                    isEnabled
                        ? SettingsSoundPlayerButtonStyle.enabledToggleBackground
                        : SettingsSoundPlayerButtonStyle.iPhoneToggleOffBackground,
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isEnabled ? "On" : "Off")
    }

    private func iPhoneTransportButton(
        systemName: String,
        accessibilityLabel: String,
        isEnabled: Bool,
        size: CGFloat,
        isPrimary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard isEnabled else { return }
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: size * (isPrimary ? 0.47 : 0.4), weight: .semibold))
                .foregroundStyle(isEnabled ? Color.white : Color.white.opacity(0.35))
                .frame(width: size, height: size)
                .background(
                    SettingsSoundPlayerButtonStyle.transportBackground,
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }

    private var iPadPlayerBody: some View {
        Color.black
            .overlay { playerBackground }
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
        GeometryReader { geometry in
            let targetPixelDimension = max(geometry.size.width, geometry.size.height) * displayScale
            let requestID = backgroundImageRequestID(maxPixelDimension: targetPixelDimension)

            Group {
                if let backgroundImage {
                    Image(uiImage: backgroundImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .opacity(clampedBackgroundImageOpacity)
                } else {
                    Color.black
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .task(id: requestID) {
                await loadBackgroundImage(maxPixelDimension: targetPixelDimension)
            }
        }
        .allowsHitTesting(false)
    }

    private func backgroundImageRequestID(maxPixelDimension: CGFloat) -> String {
        "\(backgroundImageURL?.path ?? "none"):\(Int(maxPixelDimension.rounded(.up)))"
    }

    private func loadBackgroundImage(maxPixelDimension: CGFloat) async {
        let targetPixelDimension = Int(maxPixelDimension.rounded(.up))
        let requestID = backgroundImageRequestID(maxPixelDimension: maxPixelDimension)
        let requestGeneration = UUID()

        backgroundImageRequestGeneration = requestGeneration
        backgroundImageTargetPixelDimension = targetPixelDimension

        guard let backgroundImageURL, targetPixelDimension > 0 else {
            pendingBackgroundImageRequest = nil
            backgroundImageLoadingTask?.cancel()
            backgroundImageLoadingTask = nil
            backgroundImageLoadingWorkerID = nil
            backgroundImage = nil
            print("🐞 \(ISO8601DateFormatter().string(from: Date())) SOUND IMAGE SUPERSEDED request=\(requestID) reason=no-selected-image-or-zero-target")
            return
        }

        pendingBackgroundImageRequest = BackgroundImageRequest(
            id: requestID,
            generation: requestGeneration,
            url: backgroundImageURL.standardizedFileURL,
            targetPixelDimension: targetPixelDimension
        )
        startBackgroundImageLoadingWorkerIfNeeded()
    }

    private func startBackgroundImageLoadingWorkerIfNeeded() {
        guard backgroundImageLoadingTask == nil else { return }

        let workerID = UUID()
        backgroundImageLoadingWorkerID = workerID
        backgroundImageLoadingTask = Task { @MainActor in
            await processPendingBackgroundImageRequests(workerID: workerID)
        }
    }

    private func processPendingBackgroundImageRequests(workerID: UUID) async {
        defer {
            if backgroundImageLoadingWorkerID == workerID {
                backgroundImageLoadingTask = nil
                backgroundImageLoadingWorkerID = nil
            }
        }

        while !Task.isCancelled, let request = pendingBackgroundImageRequest {
            pendingBackgroundImageRequest = nil
            let decodeStart = Date()
            print("🐞 \(ISO8601DateFormatter().string(from: decodeStart)) SOUND IMAGE DECODE START request=\(request.id) filename=\(request.url.lastPathComponent) targetPx=\(request.targetPixelDimension)")
            let decodeTask = Task.detached(priority: .userInitiated) {
                settingsPreviewDownsampledUIImage(
                    at: request.url,
                    maxPixelDimension: CGFloat(request.targetPixelDimension)
                )
            }
            let decodedImage = await withTaskCancellationHandler(operation: {
                await decodeTask.value
            }, onCancel: {
                decodeTask.cancel()
            })
            let decodeElapsedMilliseconds = Int(Date().timeIntervalSince(decodeStart) * 1_000)
            print("🐞 \(ISO8601DateFormatter().string(from: Date())) SOUND IMAGE DECODE FINISH request=\(request.id) success=\(decodedImage != nil) elapsedMs=\(decodeElapsedMilliseconds)")

            guard !Task.isCancelled else {
                print("🐞 \(ISO8601DateFormatter().string(from: Date())) SOUND IMAGE SUPERSEDED request=\(request.id) reason=worker-cancelled")
                return
            }

            guard backgroundImageTargetPixelDimension == request.targetPixelDimension else {
                print("🐞 \(ISO8601DateFormatter().string(from: Date())) SOUND IMAGE SUPERSEDED request=\(request.id) reason=target-size-changed")
                continue
            }

            guard let decodedImage else {
                print("🐞 \(ISO8601DateFormatter().string(from: Date())) SOUND IMAGE FAILED request=\(request.id) reason=decode-returned-nil")
                continue
            }

            if backgroundImageRequestGeneration != request.generation {
                guard let pendingRequest = pendingBackgroundImageRequest,
                      pendingRequest.generation == backgroundImageRequestGeneration,
                      pendingRequest.targetPixelDimension == request.targetPixelDimension,
                      backgroundImageLoadingWorkerID == workerID,
                      backgroundImageLoadingTask != nil else {
                    print("🐞 \(ISO8601DateFormatter().string(from: Date())) SOUND IMAGE SUPERSEDED request=\(request.id) reason=generation-changed-without-valid-pending-request")
                    continue
                }

                backgroundImage = decodedImage
                print("🐞 \(ISO8601DateFormatter().string(from: Date())) SOUND IMAGE INTERMEDIATE INSTALLED request=\(request.id) filename=\(request.url.lastPathComponent) generation=\(request.generation.uuidString)")
                continue
            }

            backgroundImage = decodedImage
            print("🐞 \(ISO8601DateFormatter().string(from: Date())) SOUND IMAGE FINAL INSTALLED request=\(request.id) filename=\(request.url.lastPathComponent) generation=\(request.generation.uuidString)")
        }
    }
	//
	//----------------------------------------
	// MARK: - BM:🟪 audio player iPadPlayerControls
	//
    private var iPadPlayerControls: some View {
        VStack(spacing: 4) {
					Text(backgroundImageURL?.lastPathComponent ?? "No image")
					.font(.system(size: 16, weight: .semibold))
					.foregroundStyle(.white)
					.lineLimit(1)
					.truncationMode(.tail)
					.frame(maxWidth: .infinity, alignment: .trailing)

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
	//
	//----------------------------------------
	// MARK: - BM:🟪 audio player iPadControlRow
	//
    private var iPadControlRow: some View {
        GeometryReader { geometry in
            let metrics = iPadControlMetrics(for: geometry.size.width)

            IPadControlRowLayout(minimumGap: metrics.sideControlGap) {
                iPadAutoStartControl(metrics: metrics)
                iPadRepeatControl(metrics: metrics)
                iPadTransportControls(metrics: metrics)
                iPadRandomControl(metrics: metrics)
                iPadAutoRandomBackgroundControl(metrics: metrics)
                iPadTimeDisplay
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
                systemName: playbackPresentation.isPlaying ? "pause.fill" : "play.fill",
                accessibilityLabel: playbackPresentation.isPlaying ? "Pause" : "Play",
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
        SettingsAutoStartButton(
            isEnabled: isAutoStartEnabled,
            size: metrics.transportButtonSize,
            offBackground: SettingsSoundPlayerButtonStyle.iPadToggleOffBackground,
            offTextColor: SettingsSoundPlayerButtonStyle.iPadToggleOffForeground,
            action: { onSetAutoStart(!isAutoStartEnabled) }
        )
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

    private func iPadRandomControl(metrics: IPadControlMetrics) -> some View {
        iPadModeButton(
            systemName: "shuffle",
            accessibilityLabel: "Random playback",
            isEnabled: isRandomEnabled,
            size: metrics.transportButtonSize,
            action: onToggleRandom
        )
    }

    private func iPadAutoRandomBackgroundControl(metrics: IPadControlMetrics) -> some View {
        autoRandomBackgroundButton(size: metrics.transportButtonSize)
    }

    private var compactAutoRandomBackgroundControl: some View {
        autoRandomBackgroundButton(size: controlSize)
    }

    private func autoRandomBackgroundButton(size: CGFloat) -> some View {
        iPadModeButton(
            systemName: "photo.artframe",
            accessibilityLabel: "Automatic random background",
            isEnabled: isAutoRandomBackgroundEnabled,
            size: size,
            action: onToggleAutoRandomBackground
        )
    }

    private var iPadTimeDisplay: some View {
        Text("\(formattedTimeWithHundredths(sliderPosition)) of \(formattedTimeWithHundredths(safeDuration))")
            .font(.system(size: 18, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.9))
            .lineLimit(1)
            .minimumScaleFactor(0.65)
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
                    isEnabled
                        ? SettingsSoundPlayerButtonStyle.enabledToggleBackground
                        : SettingsSoundPlayerButtonStyle.iPadToggleOffBackground,
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
                .background(SettingsSoundPlayerButtonStyle.transportBackground, in: Circle())
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
                systemName: playbackPresentation.isPlaying ? "pause.fill" : "play.fill",
                accessibilityLabel: playbackPresentation.isPlaying ? "Pause" : "Play",
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

    private func formattedIPhoneTimeWithHundredths(_ time: TimeInterval) -> String {
        guard time.isFinite, time > 0 else { return "00:00.00" }
        let totalHundredths = Int((time * 100).rounded(.down))
        let minutes = totalHundredths / 6_000
        let seconds = (totalHundredths / 100) % 60
        let hundredths = totalHundredths % 100
        return String(format: "%02d:%02d.%02d", minutes, seconds, hundredths)
    }

    private struct IPadControlMetrics {
        let transportButtonSize: CGFloat
        let transportSpacing: CGFloat
        let sideControlGap: CGFloat

        var transportWidth: CGFloat {
            (transportButtonSize * 3) + (transportSpacing * 2)
        }
    }

    private func iPadControlMetrics(for width: CGFloat) -> IPadControlMetrics {
        if width < 640 {
            return IPadControlMetrics(
                transportButtonSize: 42,
                transportSpacing: 10,
                sideControlGap: 6
            )
        }

        return IPadControlMetrics(
            transportButtonSize: 48,
            transportSpacing: 14,
            sideControlGap: 10
        )
    }
}

private struct SettingsAutoStartButton: View {
    let isEnabled: Bool
    let size: CGFloat
    let offBackground: Color
    let offTextColor: Color
    let action: () -> Void

    init(
        isEnabled: Bool,
        size: CGFloat,
        offBackground: Color,
        offTextColor: Color = .black,
        action: @escaping () -> Void
    ) {
        self.isEnabled = isEnabled
        self.size = size
        self.offBackground = offBackground
        self.offTextColor = offTextColor
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text("Auto")
                Text("Start")
            }
            .font(.system(size: size * 0.3, weight: .semibold))
            .foregroundStyle(isEnabled ? Color.black : offTextColor)
            .multilineTextAlignment(.center)
			.frame(width: size*1.5, height: size)
            .background(
                isEnabled
                    ? SettingsSoundPlayerButtonStyle.enabledToggleBackground
                    : offBackground,
                in: RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Auto Start")
        .accessibilityValue(isEnabled ? "On" : "Off")
    }
}

private struct IPadControlRowLayout: Layout {
    let minimumGap: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let idealWidth = sizes.reduce(CGFloat.zero) { $0 + $1.width }
        let idealHeight = sizes.map(\.height).max() ?? 0

        return CGSize(
            width: proposal.width ?? idealWidth,
            height: proposal.height ?? idealHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard subviews.count == 6 else { return }

        let autoStart = subviews[0]
        let repeatButton = subviews[1]
        let transport = subviews[2]
        let randomButton = subviews[3]
        let photoButton = subviews[4]
        let time = subviews[5]
        let verticalProposal = ProposedViewSize(width: nil, height: bounds.height)
        let autoStartSize = autoStart.sizeThatFits(verticalProposal)
        let repeatSize = repeatButton.sizeThatFits(verticalProposal)
        let transportSize = transport.sizeThatFits(verticalProposal)
        let randomSize = randomButton.sizeThatFits(verticalProposal)
        let photoSize = photoButton.sizeThatFits(verticalProposal)

        let transportLeading = bounds.midX - (transportSize.width / 2)
        let nextTrailing = transportLeading + transportSize.width
        let randomClusterLeadingGap = minimumGap + 12
        let availableTimeWidth = max(
            0,
            bounds.maxX - nextTrailing - randomSize.width - photoSize.width - (minimumGap * 2) - randomClusterLeadingGap
        )
        let intrinsicTimeSize = time.sizeThatFits(verticalProposal)
        let timeWidth = min(intrinsicTimeSize.width, availableTimeWidth)

        let repeatCenter = (bounds.minX + autoStartSize.width + transportLeading) / 2
        let randomLeading = nextTrailing + randomClusterLeadingGap
        let photoLeading = randomLeading + randomSize.width + minimumGap

        autoStart.place(
            at: CGPoint(x: bounds.minX, y: bounds.midY),
            anchor: .leading,
            proposal: ProposedViewSize(width: autoStartSize.width, height: bounds.height)
        )
        repeatButton.place(
            at: CGPoint(x: repeatCenter, y: bounds.midY),
            anchor: .center,
            proposal: ProposedViewSize(width: repeatSize.width, height: bounds.height)
        )
        transport.place(
            at: CGPoint(x: bounds.midX, y: bounds.midY),
            anchor: .center,
            proposal: ProposedViewSize(width: transportSize.width, height: bounds.height)
        )
        randomButton.place(
            at: CGPoint(x: randomLeading + (randomSize.width / 2), y: bounds.midY),
            anchor: .center,
            proposal: ProposedViewSize(width: randomSize.width, height: bounds.height)
        )
        photoButton.place(
            at: CGPoint(x: photoLeading + (photoSize.width / 2), y: bounds.midY),
            anchor: .center,
            proposal: ProposedViewSize(width: photoSize.width, height: bounds.height)
        )
        time.place(
            at: CGPoint(x: bounds.maxX, y: bounds.midY),
            anchor: .trailing,
            proposal: ProposedViewSize(width: timeWidth, height: bounds.height)
        )
    }
}
